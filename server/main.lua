-- dps-fuel server. Two kinds of trouble at a gas pump, both started by the ox_fuel nozzle (DPS patch):
--   drive-off   - the car leaves with the nozzle still clipped in. The hose rips, the nozzle stays stuck in the car,
--                 and rolls decide a pump fire (a real SmartFires fire), an explosion, and the station camera.
--   fuel theft  - the fuel went in on a bill (pay after you fill) and the car left without paying. No fire.
-- Either way: police call, a BOLO on the plate, the insurance report, the station's money, the shop clerk's memory.
-- The server works out who and what from its own view of the world. The client only says "I clipped the nozzle
-- into this car" (checked here) and "the hose ripped".
local NOZZLE = joaat('prop_cs_fuel_nozle')
local busy = {}       -- pump key -> os.time() of its last drive-off
local stuck = {}      -- vehicle netId -> { prop = netId, until_ = os.time() }
local clipped = {}    -- src -> { veh = netId, prop = netId, pump = vector3 } the nozzle this player clipped in
local tabs = {}       -- src -> { amount, litres, station, pump, veh = netId, plate, at } unpaid fuel
local broken = {}     -- pump key -> { until_, kind, pump, fireId }
local RANK = { rip = 1, fire = 2, explode = 3 }

local function log(...) print('[dps-fuel]', ...) end
local function started(res) return GetResourceState(res) == 'started' end

local function ent(netId)
    if type(netId) ~= 'number' then return nil end
    local e = NetworkGetEntityFromNetworkId(netId)
    return (e and e ~= 0 and DoesEntityExist(e)) and e or nil
end

local function vec(t)
    if type(t) ~= 'table' and type(t) ~= 'vector3' then return nil end
    local x, y, z = tonumber(t.x), tonumber(t.y), tonumber(t.z)
    return x and y and z and vector3(x, y, z) or nil
end

local function trim(s) return s and (s:gsub('^%s+', ''):gsub('%s+$', '')) or nil end

local function nearestPlayer(coords, maxDist)
    local best, bd
    for _, id in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(id)
        if ped and ped ~= 0 then
            local d = #(GetEntityCoords(ped) - coords)
            if d <= maxDist and (not bd or d < bd) then best, bd = tonumber(id), d end
        end
    end
    return best
end

-- The player sitting in the driver's seat, from the server's own view (not the entity's network owner).
local function driverOf(veh)
    local ped = GetPedInVehicleSeat(veh, -1)
    if not ped or ped == 0 then return nil end
    for _, id in ipairs(GetPlayers()) do
        if GetPlayerPed(id) == ped then return tonumber(id) end
    end
    return nil
end

-- ---------- the camera picture ----------
local FM_URL = 'https://api.fivemanage.com/api/v3/file/base64'

local function upload(b64, name)
    local key = GetConvar('dps:fivemanage_image', '')
    if key == '' then return nil end
    local p, done = promise.new(), false
    local function settle(v) if not done then done = true; p:resolve(v) end end
    SetTimeout(Config.Camera.uploadTimeout * 1000, function() settle(nil) end)
    PerformHttpRequest(FM_URL, function(code, body)
        local ok, data = pcall(json.decode, body or '')
        local url = code == 200 and ok and type(data) == 'table' and type(data.data) == 'table' and data.data.url
        settle(type(url) == 'string' and url:match('^https://') and url or nil)
    end, 'POST', json.encode({ base64 = 'data:image/webp;base64,' .. b64, filename = name .. '.webp', path = Config.PhotoPath }),
        { ['Content-Type'] = 'application/json', ['Authorization'] = key })
    return Citizen.Await(p)
end

-- Only a client the server just asked for a camera shot may have its screen grabbed.
local shooting = {}   -- src -> true while its camera callback runs

lib.callback.register('dps-fuel:snap', function(src)
    if not shooting[src] or not started('screencapture') then return nil end
    shooting[src] = nil
    local p, done = promise.new(), false
    local function settle(v) if not done then done = true; p:resolve(v) end end
    local ok = pcall(function()
        exports.screencapture:serverCapture(src, { encoding = 'webp', maxWidth = Config.Camera.width, maxHeight = Config.Camera.height }, settle)
    end)
    if not ok then return nil end
    SetTimeout(Config.Camera.captureTimeout * 1000, function() settle(nil) end)
    local data = Citizen.Await(p)
    if type(data) ~= 'string' then return nil end
    local b64 = data:gsub('^data:image/%w+;base64,', '')
    return upload(b64, ('pump-%d-%d'):format(os.time(), src))
end)

local function dispatch(coords, title, text)
    if not started('wasabi_mdt') then return end
    pcall(function()
        exports.wasabi_mdt:CreateDispatch({
            type = 'theft', code = Config.Dispatch.code, title = title, description = text,
            location = 'Gas station', coords = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 },
            priority = 2, departments = Config.Dispatch.departments,
            metadata = { caller_name = 'Station camera', weapons_involved = false, injuries_reported = false, suspects = 1 },
        })
    end)
end

-- ---------- the station's money (an owned gas station, through ox_fuel) ----------
local function stationCharge(pump, amount, title)
    if not Config.Station.enabled or not amount or amount <= 0 or not started('ox_fuel') then return end
    pcall(function() exports.ox_fuel:stationCharge(pump, amount, title) end)
end

-- ---------- out of order ----------
local function syncBroken()
    local out = {}
    for key, b in pairs(broken) do out[key] = b.kind end
    GlobalState.dpsBrokenPumps = out
end

local function breakPump(key, pump, kind, fireId)
    local b = broken[key] or { pump = pump }
    local until_ = Fuel.brokenUntil(kind, os.time(), b.until_)
    if not until_ then return end
    b.until_ = until_
    if not b.kind or RANK[kind] > RANK[b.kind] then b.kind = kind end
    b.fireId = fireId or b.fireId
    broken[key] = b
    syncBroken()
    stationCharge(pump, Config.Station.repairCost[kind], ('Pump damage (%s)'):format(kind))
end

local function fireBurning(b)
    if not b.fireId or not started('SmartFires') then return false end
    local ok, still = pcall(function() return exports.SmartFires:IsFireStillActive(b.fireId) end)
    return ok and still == true
end

-- ---------- BOLO (wasabi_mdt's own list) ----------
local function bolo(f)
    local B = Config.Bolo
    if not B.enabled or not f.plate or f.plate == '' or (B.onlyWithCamera and not f.photo) then return end
    local ok, err = pcall(function()
        local open = MySQL.scalar.await(
            'SELECT id FROM wsb_mdt_bolos WHERE plate = ? AND status = ? AND issued_by = ? AND created_at > NOW() - INTERVAL ? HOUR LIMIT 1',
            { f.plate, B.status, 'dps-fuel', B.dedupeHours })
        if open then return end
        MySQL.insert.await(
            'INSERT INTO wsb_mdt_bolos (title, description, plate, status, issued_by, issued_by_name, metadata) VALUES (?, ?, ?, ?, ?, ?, ?)',
            { ('%s: %s'):format(f.theft and 'Fuel theft' or 'Gas station drive-off', f.plate), Fuel.describe(f), f.plate, B.status,
              'dps-fuel', B.issuedBy, json.encode({ source = 'dps-fuel', kind = Fuel.kind(f), photo = f.photo }) })
    end)
    if not ok then log('BOLO not written: ' .. tostring(err)) end
end

-- ---------- what follows an incident (both kinds) ----------
-- f: pump, vehNet, plate, culprit (src or nil), cameraMan (src or nil), camera (bool), fire, explode, theft, owed
local function report(f)
    CreateThread(function()
        local who = f.culprit and exports.qbx_core:GetPlayer(f.culprit)
        local pd = who and who.PlayerData
        if f.camera and f.cameraMan and GetPlayerPed(f.cameraMan) ~= 0 then
            shooting[f.cameraMan] = true
            local ok, snap = pcall(lib.callback.await, 'dps-fuel:camera', f.cameraMan, f.pump, f.vehNet)
            shooting[f.cameraMan] = nil
            if ok and type(snap) == 'table' then f.photo, f.model = snap.photo, snap.model end
        end
        dispatch(f.pump, f.theft and Config.Dispatch.theftTitle or Config.Dispatch.title, Fuel.describe(f))
        bolo(f)
        if Config.Insurance.enabled and (f.photo or not Config.Insurance.onlyWithCamera) and started('dps-insurance') then
            local name = pd and pd.charinfo and (pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname)
            pcall(function()
                exports['dps-insurance']:ReportIncident({
                    plate = f.plate, kind = Fuel.kind(f), citizenid = pd and pd.citizenid, name = name,
                    location = Config.Insurance.location, photo = f.photo,
                    notes = f.model and ('Vehicle: ' .. f.model) or nil,
                })
            end)
        end
        if Config.ShopMemory.enabled and f.culprit and started('dps-shops') then
            pcall(function()
                exports['dps-shops']:RecordIncidentNear(f.pump, f.culprit, f.theft and 'fuel_theft' or 'fuel_driveoff', Config.ShopMemory.radius)
            end)
        end
        MySQL.insert('INSERT INTO dps_fuel_driveoffs (kind, plate, citizenid, x, y, z, fire, explode, owed, photo) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            { Fuel.kind(f), f.plate, pd and pd.citizenid, f.pump.x, f.pump.y, f.pump.z, f.fire or false, f.explode or false, f.owed or 0, f.photo })
        log(('%s at %s plate %s fire=%s camera=%s'):format(Fuel.kind(f), Fuel.pumpKey(f.pump), tostring(f.plate), tostring(f.fire or false), tostring(f.photo ~= nil)))
    end)
end

-- ---------- the nozzle: clipped in, ripped off ----------
-- The player says which car the nozzle went into. It only counts if they stand at that car, the car is at the
-- pump, and the nozzle is a real nozzle prop that their own game made.
RegisterNetEvent('dps-fuel:clip', function(vehNet, propNet, pumpAt)
    local src = source
    local pump, veh, prop = vec(pumpAt), ent(vehNet), ent(propNet)
    local ped = GetPlayerPed(src)
    if not pump or not veh or not prop or not ped or ped == 0 then return end
    if GetEntityType(veh) ~= 2 or GetEntityModel(prop) ~= NOZZLE or NetworkGetEntityOwner(prop) ~= src then return end
    local at = GetEntityCoords(veh)
    if #(GetEntityCoords(ped) - at) > Config.ClipReach or #(at - pump) > Config.ClipPumpReach then return end
    clipped[src] = { veh = vehNet, prop = propNet, pump = pump }
end)

RegisterNetEvent('dps-fuel:unclip', function() clipped[source] = nil end)

RegisterNetEvent('dps-fuel:driveOff', function()
    local src = source
    local c = clipped[src]
    clipped[src] = nil
    if not c then return end
    local veh, pump = ent(c.veh), c.pump
    if not veh or #(GetEntityCoords(veh) - pump) > Config.ReportRadius then return end

    -- the nozzle stays in the car for everyone to see, until someone allowed pulls it or it falls off
    local now = os.time()
    if ent(c.prop) then
        stuck[c.veh] = { prop = c.prop, until_ = now + Config.StuckMinutes * 60 }
        Entity(veh).state:set('dpsStuckNozzle', true, true)
    end

    local key = Fuel.pumpKey(pump)
    if busy[key] and now - busy[key] < Config.PumpCooldown then return end   -- this pump just had one: no second roll
    busy[key] = now

    local roll = Fuel.roll(Config.Odds, math.random)
    local driver = driverOf(veh)
    breakPump(key, pump, 'rip')

    if roll.fire and started('SmartFires') then
        local ok, fireId = pcall(function() return exports.SmartFires:CreateFire(pump, Config.FireSize, Config.FireType, true) end)
        if ok and fireId then
            breakPump(key, pump, 'fire', fireId)
            if roll.explode then
                SetTimeout(Config.ExplodeAfter * 1000, function()
                    local okA, still = pcall(function() return exports.SmartFires:IsFireStillActive(fireId) end)
                    if not okA or not still then return end
                    local host = nearestPlayer(pump, Config.Explosion.hostRadius)
                    if host then TriggerClientEvent('dps-fuel:explode', host, pump) end
                    pcall(function() exports.SmartFires:StopFireById(fireId) end)
                    breakPump(key, pump, 'explode')   -- it blew whether or not anyone was near enough to see it
                    log(('pump at %s blew after %ds'):format(key, Config.ExplodeAfter))
                end)
            end
        else
            roll.fire, roll.explode = false, false
        end
    else
        roll.fire, roll.explode = false, false
    end

    report({ pump = pump, vehNet = c.veh, plate = trim(GetVehicleNumberPlateText(veh)), culprit = driver or src,
        cameraMan = driver or src, camera = roll.camera, fire = roll.fire, explode = roll.explode })
end)

-- ---------- pay after you fill ----------
local function setTab(src, amount) TriggerClientEvent('dps-fuel:tab', src, amount) end

local function charge(src, amount, accounts)
    for _, account in ipairs(accounts or Config.Tab.payFrom) do
        local ok, has = pcall(function() return exports.qbx_core:GetMoney(src, account) end)
        if ok and (tonumber(has) or 0) >= amount then
            local okR, done = pcall(function() return exports.qbx_core:RemoveMoney(src, account, amount, 'dps-fuel: fuel') end)
            if okR and done then return true end
        end
    end
    return false
end

local function settle(src, tab)
    tabs[src] = nil
    setTab(src, 0)
    if tab.station and started('ox_fuel') then
        pcall(function() exports.ox_fuel:stationSale(tab.station, tab.amount, tab.litres) end)
    end
end

-- Called by ox_fuel's server when fuel went in on a bill: t = { price, litres, station, pump, netid }.
exports('AddTab', function(src, t)
    local pump = type(t) == 'table' and vec(t.pump)
    local price = type(t) == 'table' and math.floor(tonumber(t.price) or 0) or 0
    local veh = type(t) == 'table' and ent(t.netid)
    if not pump or not veh or price <= 0 or GetPlayerPed(src) == 0 then return false end
    local tab = tabs[src] or { amount = 0, litres = 0, at = os.time() }
    tab.amount = tab.amount + price
    tab.litres = tab.litres + (tonumber(t.litres) or 0)
    tab.station, tab.pump, tab.veh = t.station, pump, t.netid
    tab.plate = trim(GetVehicleNumberPlateText(veh))
    tabs[src] = tab
    setTab(src, tab.amount)
    return true
end)

lib.callback.register('dps-fuel:pay', function(src)
    local tab = tabs[src]
    if not tab then return false, Config.Messages.noTab end
    if #(GetEntityCoords(GetPlayerPed(src)) - tab.pump) > Config.Tab.leaveRadius then return false, Config.Messages.closer end
    if not charge(src, tab.amount) then return false, Config.Messages.cantPay:format(tab.amount) end
    settle(src, tab)
    return true, Config.Messages.paid:format(tab.amount)
end)

local function theft(src, tab)
    tabs[src] = nil
    if GetPlayerPed(src) ~= 0 then setTab(src, 0) end
    local veh = ent(tab.veh)
    report({ pump = tab.pump, vehNet = tab.veh, plate = tab.plate, culprit = src, cameraMan = veh and (driverOf(veh) or src) or nil,
        camera = veh ~= nil and math.random() < Config.Tab.cameraOdds, theft = true, owed = tab.amount })
end

AddEventHandler('playerDropped', function()
    local src = source
    clipped[src], shooting[src] = nil, nil
    local tab = tabs[src]
    if not tab then return end
    -- logging out is not a getaway: the bill comes out of the bank if it can
    if charge(src, tab.amount, { 'bank' }) then tabs[src] = nil; if tab.station and started('ox_fuel') then
        pcall(function() exports.ox_fuel:stationSale(tab.station, tab.amount, tab.litres) end) end
    else theft(src, tab) end
end)

-- ---------- repairing a pump ----------
lib.callback.register('dps-fuel:repair', function(src, pumpAt, checkOnly)
    local pump = vec(pumpAt)
    local p = exports.qbx_core:GetPlayer(src)
    if not pump or not p then return false end
    if not Fuel.canRepair(p.PlayerData.job and p.PlayerData.job.name) then return false, Config.Messages.repairNo end
    if #(GetEntityCoords(GetPlayerPed(src)) - pump) > 5.0 then return false, Config.Messages.closer end
    local key = Fuel.pumpKey(pump)
    local b = broken[key]
    if not b then return false, Config.Messages.notBroken end
    if fireBurning(b) then return false, Config.Messages.fireFirst end
    if checkOnly then return true end
    broken[key] = nil
    syncBroken()
    local pay = Config.Broken.repairPay
    if pay > 0 then exports.qbx_core:AddMoney(src, 'bank', pay, 'dps-fuel: pump repair') end
    return true, Config.Messages.repaired:format(pay)
end)

-- ---------- pulling a stuck nozzle ----------
local function clearStuck(vehNet)
    local s = stuck[vehNet]
    stuck[vehNet] = nil
    if not s then return end
    local prop = ent(s.prop)
    if prop and GetEntityModel(prop) == NOZZLE then DeleteEntity(prop) end
    local veh = ent(vehNet)
    if veh then Entity(veh).state:set('dpsStuckNozzle', nil, true) end
end

lib.callback.register('dps-fuel:pull', function(src, vehNet)
    local p = exports.qbx_core:GetPlayer(src)
    if not p or not Fuel.canRemove(p.PlayerData.job and p.PlayerData.job.name) then return false, Config.Messages.notAllowed end
    local veh = ent(vehNet)
    if not veh or #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(veh)) > Config.Pull.reach then return false, Config.Messages.closer end
    if not stuck[vehNet] then
        Entity(veh).state:set('dpsStuckNozzle', nil, true)   -- a mark left over from before a restart
        return false, Config.Messages.nothing
    end
    clearStuck(vehNet)
    return true, Config.Messages.pulled
end)

-- ---------- start-up, and the only loop ----------
CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS dps_fuel_driveoffs (
        id INT AUTO_INCREMENT PRIMARY KEY, plate VARCHAR(16) NULL, citizenid VARCHAR(64) NULL,
        x FLOAT, y FLOAT, z FLOAT, fire TINYINT(1) NOT NULL DEFAULT 0, explode TINYINT(1) NOT NULL DEFAULT 0,
        photo VARCHAR(255) NULL, at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, KEY (plate), KEY (at))]])
    MySQL.query.await("ALTER TABLE dps_fuel_driveoffs ADD COLUMN IF NOT EXISTS kind VARCHAR(24) NOT NULL DEFAULT 'fuel_driveoff'")
    MySQL.query.await('ALTER TABLE dps_fuel_driveoffs ADD COLUMN IF NOT EXISTS owed INT NOT NULL DEFAULT 0')

    -- after a restart nothing is remembered: clear what the last run left in the world
    GlobalState.dpsBrokenPumps = {}
    for _, veh in ipairs(GetAllVehicles()) do
        if Entity(veh).state.dpsStuckNozzle then Entity(veh).state:set('dpsStuckNozzle', nil, true) end
    end
    for _, obj in ipairs(GetAllObjects()) do
        if GetEntityModel(obj) == NOZZLE and GetEntityAttachedTo(obj) ~= 0 and GetEntityType(GetEntityAttachedTo(obj)) == 2 then
            DeleteEntity(obj)
        end
    end

    -- Every 5 seconds: unpaid bills whose car left, stuck nozzles and broken pumps past their time. All three
    -- tables are empty almost always, so this costs nothing while nobody is at a pump.
    while true do
        Wait(5000)
        local now = os.time()
        for src, tab in pairs(tabs) do
            local veh = ent(tab.veh)
            local state = Fuel.tabState(veh and #(GetEntityCoords(veh) - tab.pump) or nil, now - tab.at)
            if state == 'late' and charge(src, tab.amount, { 'bank' }) then
                settle(src, tab)
                TriggerClientEvent('ox_lib:notify', src, { type = 'inform', description = Config.Messages.autoPaid:format(tab.amount) })
            elseif state then
                theft(src, tab)
            end
        end
        for vehNet, s in pairs(stuck) do
            if now > s.until_ then clearStuck(vehNet) end
        end
        local changed = false
        for key, b in pairs(broken) do
            if now > b.until_ and not fireBurning(b) then broken[key] = nil; changed = true end
        end
        if changed then syncBroken() end
    end
end)
