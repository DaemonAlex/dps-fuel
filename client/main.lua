-- dps-fuel client: the station camera shot, the pump explosion, pulling a stuck nozzle, paying the fuel bill at the
-- pump, and "out of order" pumps with their repair. The nozzle itself lives in ox_fuel (DPS patch).
local owed = 0

local function pumpKey(entity) return Fuel.pumpKey(GetEntityCoords(entity)) end
local function isBroken(entity)
    local b = GlobalState.dpsBrokenPumps
    return b ~= nil and b[pumpKey(entity)] ~= nil
end
local function myJob()
    local ok, pd = pcall(function() return exports.qbx_core:GetPlayerData() end)
    return ok and pd and pd.job and pd.job.name or nil
end

-- The view cuts to the station camera for a moment; the server grabs that view as the picture.
lib.callback.register('dps-fuel:camera', function(pump, vehNet)
    local veh = NetworkDoesNetworkIdExist(vehNet) and NetToVeh(vehNet) or 0
    if veh == 0 or not DoesEntityExist(veh) then return nil end
    local model = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(veh)))
    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    local C = Config.Camera
    SetCamCoord(cam, pump.x + C.offset.x, pump.y + C.offset.y, pump.z + C.offset.z)
    PointCamAtEntity(cam, veh, 0.0, 0.0, 0.0, true)
    SetCamFov(cam, C.fov)
    RenderScriptCams(true, false, 0, true, true)
    if C.filter ~= '' then SetTimecycleModifier(C.filter); SetTimecycleModifierStrength(1.0) end
    Wait(C.holdMs)
    local photo = lib.callback.await('dps-fuel:snap', false)
    ClearTimecycleModifier()
    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(cam, false)
    lib.notify({ title = 'Gas station', description = Config.Messages.camera, type = 'error' })
    return { photo = photo, model = model ~= 'NULL' and model or nil }
end)

-- An untouched pump fire blows. Explosion type 9 is the game's petrol pump explosion.
RegisterNetEvent('dps-fuel:explode', function(pump)
    AddExplosion(pump.x, pump.y, pump.z + 0.5, Config.Explosion.type, Config.Explosion.scale, true, false, 1.0)
end)

-- The fuel bill. The server keeps the amount; this is only what the player is shown.
RegisterNetEvent('dps-fuel:tab', function(amount)
    local before = owed
    owed = tonumber(amount) or 0
    if owed > before then lib.notify({ title = 'Gas station', description = Config.Messages.owe:format(owed), type = 'inform', duration = 8000 }) end
end)

-- Pulling a stuck nozzle: police, BCSO, SASP and mechanics (the server checks the job).
exports.ox_target:addGlobalVehicle({
    {
        name = 'dps_fuel_pull',
        icon = 'fas fa-gas-pump',
        label = Config.Messages.pullLabel,
        distance = Config.Pull.reach / 2,
        canInteract = function(entity) return Entity(entity).state.dpsStuckNozzle == true end,
        onSelect = function(data)
            if not lib.progressBar({ duration = Config.Pull.seconds * 1000, label = Config.Messages.pulling, canCancel = true,
                disable = { move = true, car = true, combat = true }, anim = Config.Pull.anim }) then return end
            local ok, msg = lib.callback.await('dps-fuel:pull', false, VehToNet(data.entity))
            lib.notify({ description = msg, type = ok and 'success' or 'error' })
        end,
    },
})

-- At the pump: pay the bill, see that it is out of order, repair it. The pump models are ox_fuel's own list.
CreateThread(function()
    local waited = 0
    while GetResourceState('ox_fuel') ~= 'started' and waited < 60 do Wait(1000); waited = waited + 1 end
    local ok, models = pcall(function() return exports.ox_fuel:pumpModels() end)
    if not ok or type(models) ~= 'table' then return print('[dps-fuel] ox_fuel has no pumpModels export: pump options are off') end
    exports.ox_target:addModel(models, {
        {
            name = 'dps_fuel_pay', icon = 'fas fa-credit-card', label = Config.Messages.payLabel, distance = 2,
            canInteract = function() return owed > 0 and not cache.vehicle end,
            onSelect = function()
                local done, msg = lib.callback.await('dps-fuel:pay', false)
                lib.notify({ title = 'Gas station', description = msg, type = done and 'success' or 'error' })
            end,
        },
        {
            name = 'dps_fuel_broken', icon = 'fas fa-triangle-exclamation', label = Config.Messages.brokenLabel, distance = 2,
            canInteract = function(entity) return isBroken(entity) end,
            onSelect = function() lib.notify({ title = 'Gas station', description = Config.Messages.broken, type = 'error' }) end,
        },
        {
            name = 'dps_fuel_repair', icon = 'fas fa-screwdriver-wrench', label = Config.Messages.repairLabel, distance = 2,
            canInteract = function(entity) return isBroken(entity) and Fuel.canRepair(myJob()) and not cache.vehicle end,
            onSelect = function(data)
                local at = GetEntityCoords(data.entity)
                local can, why = lib.callback.await('dps-fuel:repair', false, at, true)
                if not can then return lib.notify({ description = why or Config.Messages.repairNo, type = 'error' }) end
                if not lib.progressBar({ duration = Config.Broken.repairSeconds * 1000, label = Config.Messages.repairing, canCancel = true,
                    disable = { move = true, car = true, combat = true }, anim = Config.Broken.anim }) then return end
                local done, msg = lib.callback.await('dps-fuel:repair', false, at)
                lib.notify({ title = 'Gas station', description = msg, type = done and 'success' or 'error' })
            end,
        },
    })
end)
