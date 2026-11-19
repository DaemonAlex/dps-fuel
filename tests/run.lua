package.path = './?.lua;' .. package.path
local passed, failed = 0, 0
local function check(name, ok, d) if ok then passed = passed + 1 else failed = failed + 1; print('  FAIL ' .. name .. (d and (' -> ' .. tostring(d)) or '')) end end
local function eq(name, got, want) check(name, got == want, ('got %s want %s'):format(tostring(got), tostring(want))) end
lib = {}
vec3 = function(x, y, z) return { x = x, y = y, z = z } end
dofile('config.lua'); dofile('shared/rules.lua')

local function seq(t) local i = 0 return function() i = i + 1 return t[i] end end
local r = Fuel.roll({ fire = 0.35, explode = 0.5, camera = 0.8 }, seq({ 0.1, 0.2, 0.9 }))
check('low roll lights the pump', r.fire); check('and it can blow', r.explode); check('high roll: camera broken', not r.camera)
r = Fuel.roll({ fire = 0.35, explode = 0.5, camera = 0.8 }, seq({ 0.9, 0.0, 0.1 }))
check('no fire, so no explosion', not r.fire and not r.explode); check('camera works', r.camera)
local fires, n = 0, 10000
math.randomseed(7)
for _ = 1, n do if Fuel.roll(Config.Odds, math.random).fire then fires = fires + 1 end end
check('fire odds roughly as set', math.abs(fires / n - Config.Odds.fire) < 0.03, fires / n)
eq('pump key rounds', Fuel.pumpKey({ x = 1.4, y = -2.6, z = 30.5 }), '1:-3:31')
check('police can pull a nozzle', Fuel.canRemove('police')); check('a civilian cannot', not Fuel.canRemove('unemployed'))
local d = Fuel.describe({ plate = 'ABC123', model = 'Sultan', colour = 'red', fire = true, photo = 'https://x/y.webp' })
check('description has the plate', d:find('ABC123', 1, true) ~= nil); check('and the photo', d:find('https://x/y.webp', 1, true) ~= nil)
-- fuel theft and the bill
eq('drive-off kind', Fuel.kind({}), 'fuel_driveoff'); eq('fire kind', Fuel.kind({ fire = true }), 'fuel_driveoff_fire')
eq('theft kind', Fuel.kind({ theft = true, fire = true }), 'fuel_theft')
local t = Fuel.describe({ plate = 'ABC123', theft = true, owed = 84 })
check('theft text names the bill', t:find('without paying $84', 1, true) ~= nil); check('and not the nozzle', t:find('nozzle', 1, true) == nil)
local T = { leaveRadius = 45, maxMinutes = 10 }
eq('car at the pump, fresh bill: fine', Fuel.tabState(5, 30, T), nil)
eq('car drove away: left', Fuel.tabState(46, 30, T), 'left')
eq('car is gone: left', Fuel.tabState(nil, 30, T), 'left')
eq('bill too old: late', Fuel.tabState(5, 601, T), 'late')
-- out of order
local B = { minutes = { rip = 10, fire = 30, explode = 0 }, repairJobs = { mechanic = true } }
eq('a rip breaks the pump for 10 minutes', Fuel.brokenUntil('rip', 1000, nil, B), 1600)
eq('a fire makes it longer', Fuel.brokenUntil('fire', 1000, 1600, B), 2800)
eq('a rip does not shorten a fire', Fuel.brokenUntil('rip', 1000, 2800, B), 2800)
eq('0 minutes never breaks it', Fuel.brokenUntil('explode', 1000, nil, B), nil)
check('mechanic can repair', Fuel.canRepair('mechanic', B)); check('police cannot', not Fuel.canRepair('police', B))
check('config has every broken kind priced', Config.Station.repairCost.rip and Config.Station.repairCost.fire and Config.Station.repairCost.explode)
print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
