-- dps-fuel rules, no natives (tests/run.lua checks them).
Fuel = {}

-- One roll per drive-off. rand() -> [0,1). Explosion only ever follows a fire.
function Fuel.roll(odds, rand)
    local r = {}
    r.fire = rand() < (odds.fire or 0)
    r.explode = r.fire and rand() < (odds.explode or 0) or false
    r.camera = rand() < (odds.camera or 0)
    return r
end

-- A pump is identified by its position, rounded to a metre.
function Fuel.pumpKey(c)
    return ('%d:%d:%d'):format(math.floor(c.x + 0.5), math.floor(c.y + 0.5), math.floor(c.z + 0.5))
end

function Fuel.canRemove(job, cfg)
    return job ~= nil and (cfg or Config).RemoveJobs[job] == true
end

function Fuel.describe(f)
    local parts = { ('Plate %s'):format(f.plate or 'unknown') }
    if f.model then parts[#parts + 1] = (f.colour and (f.colour .. ' ') or '') .. f.model end
    if f.theft then
        parts[#parts + 1] = ('left without paying $%d for fuel'):format(f.owed or 0)
    else
        parts[#parts + 1] = 'drove off with the pump nozzle still in the tank'
    end
    local s = table.concat(parts, ', ') .. '.'
    if f.fire then s = s .. ' The pump is on fire.' end
    if f.photo then s = s .. ' Station camera: ' .. f.photo end
    return s
end

-- The insurance kind for an incident.
function Fuel.kind(f)
    if f.theft then return 'fuel_theft' end
    return f.fire and 'fuel_driveoff_fire' or 'fuel_driveoff'
end

-- An unpaid bill: 'left' when the fuelled car is gone or far from the pump, 'late' when it is too old, else nil.
-- dist = metres from the pump to the car (nil = the car no longer exists).
function Fuel.tabState(dist, ageSeconds, cfg)
    cfg = cfg or Config.Tab
    if dist == nil or dist > cfg.leaveRadius then return 'left' end
    if ageSeconds > cfg.maxMinutes * 60 then return 'late' end
    return nil
end

-- How long a pump is out of order. A worse kind never shortens a longer break already running.
function Fuel.brokenUntil(kind, now, current, cfg)
    local m = ((cfg or Config.Broken).minutes or {})[kind] or 0
    if m <= 0 then return current end
    local t = now + m * 60
    if current and current > t then return current end
    return t
end

function Fuel.canRepair(job, cfg)
    return job ~= nil and (cfg or Config.Broken).repairJobs[job] == true
end
