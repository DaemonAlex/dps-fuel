-- dps-fuel client: the station camera shot, the pump explosion, and pulling a stuck nozzle (police, BCSO, SASP,
-- mechanics). The nozzle itself lives in ox_fuel (DPS patch); it reports a drive-off with 'dps-fuel:driveOff'.

-- The driver's view cuts to the station camera for a moment; the server grabs that view as the picture.
lib.callback.register('dps-fuel:camera', function(pump, vehNet)
    local veh = NetworkDoesNetworkIdExist(vehNet) and NetToVeh(vehNet) or 0
    if veh == 0 then return nil end
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
