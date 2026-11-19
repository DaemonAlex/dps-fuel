-- dps-fuel server: a drive-off reported by the ox_fuel nozzle becomes an incident. The hose rips (the nozzle stays
-- stuck in the car), then rolls decide whether the pump catches fire (a real SmartFires fire, so the fire job is
-- called), whether an untouched fire blows the pump, and whether the station camera gets a picture for the police.
local busy = {}       -- pump key -> os.time() of its last incident
local stuck = {}      -- vehicle netId -> { prop = netId, until_ = os.time() }

local function log(...) print('[dps-fuel]', ...) end

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

-- Called by the driver's client while its view is on the station camera: grab that view and upload it.
lib.callback.register('dps-fuel:snap', function(src)
    if GetResourceState('screencapture') ~= 'started' then return nil end
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
    return upload(b64, ('driveoff-%d-%d'):format(os.time(), src))
end)

local function dispatch(coords, text)
    if GetResourceState('wasabi_mdt') ~= 'started' then return end
    pcall(function()
        exports.wasabi_mdt:CreateDispatch({
            type = 'theft', code = Config.Dispatch.code, title = Config.Dispatch.title, description = text,
            location = 'Gas station', coords = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 },
            priority = 2, departments = Config.Dispatch.departments,
            metadata = { caller_name = 'Station camera', weapons_involved = false, injuries_reported = false, suspects = 1 },
        })
    end)
end

-- ---------- the incident ----------
RegisterNetEvent('dps-fuel:driveOff', function(data)
    local src = source
    if type(data) ~= 'table' or type(data.pump) ~= 'table' then return end
    local pump = vector3(tonumber(data.pump.x) or 0, tonumber(data.pump.y) or 0, tonumber(data.pump.z) or 0)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - pump) > Config.ReportRadius then return end   -- only from someone at that pump
    local veh = data.vehicle and NetworkGetEntityFromNetworkId(data.vehicle)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end

    local key = Fuel.pumpKey(pump)
    local now = os.time()
    if busy[key] and now - busy[key] < Config.PumpCooldown then return end
    busy[key] = now

    -- the nozzle stays in the car for everyone to see, until someone allowed pulls it or it falls off
    if data.prop then
        stuck[data.vehicle] = { prop = data.prop, until_ = now + Config.StuckMinutes * 60 }
        Entity(veh).state:set('dpsStuckNozzle', true, true)
    end

    local roll = Fuel.roll(Config.Odds, math.random)
    local driver = NetworkGetEntityOwner(veh)
    local dpd = driver and exports.qbx_core:GetPlayer(driver)
    local facts = { plate = GetVehicleNumberPlateText(veh), fire = roll.fire }

    if roll.fire and GetResourceState('SmartFires') == 'started' then
        local ok, fireId = pcall(function() return exports.SmartFires:CreateFire(pump, Config.FireSize, Config.FireType, true) end)
        if ok and fireId and roll.explode then
            SetTimeout(Config.ExplodeAfter * 1000, function()
                local okA, still = pcall(function() return exports.SmartFires:IsFireStillActive(fireId) end)
                if not okA or not still then return end
                local host = nearestPlayer(pump, Config.Explosion.hostRadius)
                if host then TriggerClientEvent('dps-fuel:explode', host, pump) end
                pcall(function() exports.SmartFires:StopFireById(fireId) end)
                log(('pump at %s blew after %ds'):format(key, Config.ExplodeAfter))
            end)
        end
    end

    -- the camera: the driver's view cuts to the station camera for a moment and that picture goes to the police
    CreateThread(function()
        if roll.camera and driver then
            local snap = lib.callback.await('dps-fuel:camera', driver, pump, data.vehicle)
            if type(snap) == 'table' then facts.photo, facts.model = snap.photo, snap.model end
        end
        dispatch(pump, Fuel.describe(facts))
        MySQL.insert('INSERT INTO dps_fuel_driveoffs (plate, citizenid, x, y, z, fire, explode, photo) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            { facts.plate, dpd and dpd.PlayerData.citizenid, pump.x, pump.y, pump.z, roll.fire, roll.explode, facts.photo })
        log(('drive-off %s plate %s fire=%s camera=%s'):format(key, tostring(facts.plate), tostring(roll.fire), tostring(facts.photo ~= nil)))
    end)
end)

-- ---------- pulling a stuck nozzle ----------
local function clearStuck(vehNet)
    local s = stuck[vehNet]
    stuck[vehNet] = nil
    if not s then return end
    local prop = NetworkGetEntityFromNetworkId(s.prop)
    if prop and prop ~= 0 and DoesEntityExist(prop) then DeleteEntity(prop) end
    local veh = NetworkGetEntityFromNetworkId(vehNet)
    if veh and veh ~= 0 and DoesEntityExist(veh) then Entity(veh).state:set('dpsStuckNozzle', nil, true) end
end

lib.callback.register('dps-fuel:pull', function(src, vehNet)
    local p = exports.qbx_core:GetPlayer(src)
    if not p or not Fuel.canRemove(p.PlayerData.job and p.PlayerData.job.name) then return false, Config.Messages.notAllowed end
    local veh = NetworkGetEntityFromNetworkId(vehNet)
    if not veh or veh == 0 or #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(veh)) > Config.Pull.reach then return false, Config.Messages.closer end
    if not stuck[vehNet] then return false, Config.Messages.nothing end
    clearStuck(vehNet)
    return true, Config.Messages.pulled
end)

-- the only loop: once a minute, stuck nozzles past their time fall off
CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS dps_fuel_driveoffs (
        id INT AUTO_INCREMENT PRIMARY KEY, plate VARCHAR(16) NULL, citizenid VARCHAR(64) NULL,
        x FLOAT, y FLOAT, z FLOAT, fire TINYINT(1) NOT NULL DEFAULT 0, explode TINYINT(1) NOT NULL DEFAULT 0,
        photo VARCHAR(255) NULL, at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, KEY (plate), KEY (at))]])
    while true do
        Wait(60000)
        local now = os.time()
        for vehNet, s in pairs(stuck) do
            if now > s.until_ then clearStuck(vehNet) end
        end
    end
end)
