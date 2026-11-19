Config = {}

-- What can happen when someone drives off with the nozzle still in the car. The hose always rips and the nozzle
-- stays stuck in the car's fuel cap. The rest is a roll, so it is not every time (Damon: "give it odds").
Config.Odds = {
    fire = 0.35,      -- the pump catches fire
    explode = 0.5,    -- a fire nobody puts out in time blows the pump (rolled when the fire starts)
    camera = 0.8,     -- the station camera gets a picture (the rest of the time it is "broken")
}

Config.ExplodeAfter = 90          -- seconds a fire must burn untouched before it can blow
Config.FireSize = 4.0             -- SmartFires fire size at the pump
Config.FireType = 'normal'        -- a SmartFires fire type (config.lua fireTypes in SmartFires)
Config.PumpCooldown = 300         -- seconds before the same pump can have another incident
Config.StuckMinutes = 30          -- a stuck nozzle falls off by itself after this long

-- Who can pull a stuck nozzle out of a car (job names).
Config.RemoveJobs = { police = true, bcso = true, sasp = true, mechanic = true }

-- The police call. Departments get it in wasabi_mdt; the picture link is in the description.
Config.Dispatch = {
    code = '10-60',
    title = 'Gas station drive-off',
    departments = { 'police', 'bcso', 'sasp' },
}

-- The camera picture goes to Fivemanage with the server-only convar dps:fivemanage_image (as dps-studio does).
Config.PhotoPath = 'dps-fuel/driveoffs'

-- The station camera shot (the driver's view cuts to it for a moment).
Config.Camera = {
    offset = vec3(2.5, 2.5, 3.5),   -- where the camera hangs, relative to the pump
    fov = 55.0,
    filter = 'scanline_cam_cheap',  -- timecycle look; '' for none
    holdMs = 350,                   -- how long the view sits on the camera before the picture
    width = 960, height = 540,      -- picture size
    captureTimeout = 8,             -- seconds to wait for the picture
    uploadTimeout = 15,             -- seconds to wait for Fivemanage
}

Config.Explosion = {
    type = 9,            -- game explosion type (9 = petrol pump)
    scale = 1.0,
    hostRadius = 300.0,  -- a player this close to the pump sets it off (someone has to be near to see it)
}

Config.Pull = {
    seconds = 4,
    reach = 5.0,         -- metres from the car
    anim = { dict = 'mini@repair', clip = 'fixing_a_ped' },
}

Config.ReportRadius = 80.0   -- a drive-off report must come from a player this close to the pump

Config.Messages = {
    camera = 'Smile, you are on camera.',
    pulled = 'Nozzle pulled out.',
    notAllowed = 'You need a mechanic or the police for that.',
    closer = 'Get closer.',
    nothing = 'Nothing stuck in this one.',
    pulling = 'Working the nozzle loose...',
    pullLabel = 'Pull out the stuck nozzle',
}

-- Insurance (dps-insurance): the drive-off is filed in m-Insurance's accident log and raises the car's premium
-- (the percent per kind is in dps-insurance's config: fuel_driveoff, fuel_driveoff_fire).
Config.Insurance = {
    enabled = true,
    onlyWithCamera = true,   -- no camera picture, no proof: nothing is filed
    location = 'Gas station',
}
