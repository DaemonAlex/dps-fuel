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
    parts[#parts + 1] = 'drove off with the pump nozzle still in the tank'
    local s = table.concat(parts, ', ') .. '.'
    if f.fire then s = s .. ' The pump is on fire.' end
    if f.photo then s = s .. ' Station camera: ' .. f.photo end
    return s
end
