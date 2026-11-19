fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'dps-fuel'
description 'DPS fuel: gas station drive-offs (ripped hose, pump fire, station camera, police call) for the ox_fuel nozzle'
author 'DaemonAlex'
version '1.0.0'

shared_scripts { '@ox_lib/init.lua', 'config.lua', 'shared/rules.lua' }
client_scripts { 'client/main.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', 'server/main.lua' }

dependencies { 'ox_lib', 'oxmysql', 'qbx_core', 'ox_target' }
