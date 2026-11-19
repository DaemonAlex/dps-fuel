# dps-fuel

Gas station drive-offs for a Qbox FiveM server. Players fill up with a real nozzle (the DPS nozzle in
ox_fuel). Drive off with the nozzle still in the car and the hose rips: the nozzle stays stuck in the
fuel cap for everyone to see, the pump may catch fire (and blow if nobody puts it out), and the station
camera may catch the car for the police.

## What it is for

Filling up is a small moment that happens all day. With a real nozzle and a hose it becomes something
you do with your hands, and forgetting it becomes a scene: a ripped hose, a burning pump, firefighters
on the way, and a camera picture of your plate in the police computer. It does not happen every time:
each part is a roll, so most drive-offs are just embarrassing.

## What happens on a drive-off

1. **The hose rips.** Always. The nozzle stays stuck in the car's fuel cap. The driver cannot pull it
   out; police, BCSO, SASP or a mechanic can (**Pull out the stuck nozzle**), and it falls off by itself
   after 30 minutes.
2. **The pump may catch fire** (`Config.Odds.fire`, 35%). It is a real SmartFires fire, so the fire job
   gets the call.
3. **An untouched fire may blow** (`Config.Odds.explode`, 50% of fires). If it is still burning after
   `Config.ExplodeAfter` seconds (90), the pump explodes.
4. **The station camera may catch the car** (`Config.Odds.camera`, 80%; otherwise it was "broken").
   The driver's view cuts to the station camera for a moment and that picture goes to Fivemanage.
5. **The police get a call** in wasabi_mdt: plate, model, the fire if there is one, and the camera
   picture link.

6. **Insurance goes up** (with dps-insurance). A drive-off the camera caught is filed in m-Insurance's
   accident log with the picture, and the car's active policy gets dearer (10%, or 20% with a pump
   fire; set in dps-insurance's config, capped at 50% in 90 days). No picture, no proof: nothing is
   filed (`Config.Insurance.onlyWithCamera`).

Every drive-off is saved in `dps_fuel_driveoffs` (plate, driver, place, fire, explosion, picture).
A pump has a cooldown (`Config.PumpCooldown`, 5 minutes) so one pump cannot be farmed.

## Pay after you fill, and fuel theft

With `nozzle.payAfter` on in ox_fuel, fuel goes in first and the bill waits at the pump
(**Pay for your fuel**). The price is worked out on the server: litres times the station's own price.

Drive the fuelled car more than `Config.Tab.leaveRadius` (45 m) from the pump without paying and it is
fuel theft. No fire, but the station camera may catch it (`Config.Tab.cameraOdds`), the police get the
call, the plate goes on a BOLO, and the insurance goes up (5%). Walking into the shop is fine: it is
the car leaving that counts. A bill left for 10 minutes is taken from the bank. Logging out with a
bill takes it from the bank too.

## Out of order

A pump that had its hose ripped is out of order for 10 minutes, a burned one for 30, a blown one for
60 (`Config.Broken.minutes`). It gives no nozzle until then, or until a mechanic or city worker fixes
it (**Repair the pump**, paid `Config.Broken.repairPay`). A burning pump cannot be fixed until the
fire is out.

## The station pays

When the pump belongs to an owned gas station (lc_gas_stations), pump damage comes out of that
station's money and shows in its balance (`Config.Station.repairCost`). Stolen fuel is gone from its
stock and no money arrives. The clerk at a dps-shops counter near the pump remembers the driver.

## BOLO

A plate the camera caught goes on the police computer's own BOLO list (wasabi_mdt, `wsb_mdt_bolos`)
with the picture link. Police resolve it there. One open BOLO per plate per day.

## What the server checks

The server does not take the player's word for which car or which pump. When a nozzle is clipped in,
the server checks the player is at that car, the car is at the pump, and the nozzle is a real nozzle
their own game made. A drive-off only counts for that car. The camera cuts on whoever is in the
driver's seat. A screen grab is only taken from a player the server just asked.

## Tuning

Everything is in `config.lua`: the odds, the explosion delay, fire size and type, explosion type, who
may pull a stuck nozzle, how long a nozzle stays stuck, the camera position, field of view, look and
picture size, the dispatch code and departments, and every message players see. The nozzle itself
(reach, how far a car may move before the hose rips, how it sits in the hand and in the fuel cap) is in
ox_fuel's `config.lua` under `nozzle`.

## On its own, and with other scripts

**It needs the DPS nozzle in ox_fuel.** ox_fuel reports the drive-off; without that patch nothing here
ever fires. Without dps-fuel running, the ox_fuel nozzle still works and a drive-off simply pulls the
nozzle back to the pump.

**With SmartFires (paid).** Pump fires are real SmartFires fires: they spread, firefighters get the
alert, and putting the fire out stops the explosion. Without it there is no fire.

**With wasabi_mdt (paid).** The drive-off arrives as a dispatch call. Without it nothing is sent.

**With dps-insurance.** Caught drive-offs raise the car's insurance premium and show in the accident
log brokers and police read. Without it, no insurance effect.

**With screencapture and a Fivemanage key.** The camera picture needs both (the key is the server-only
convar `dps:fivemanage_image`, the same one dps-studio uses). Without them the call goes out with no
picture.

## Requirements

`ox_lib`, `oxmysql`, `qbx_core`, `ox_target`, and ox_fuel with the DPS nozzle. Optional: SmartFires,
wasabi_mdt, screencapture.

## Performance

Nothing runs until a drive-off. The only loop is a once-a-minute check that drops stuck nozzles past
their time. The ox_fuel nozzle watches distance twice a second, and only for a player holding it.

## Tests

`lua5.4 tests/run.lua` checks the odds, the pump key, who may pull a nozzle and the call text.

## Recent changes

- **1.1.0** Pay after you fill and fuel theft. Out-of-order pumps with a repair job. Pump damage is
  charged to an owned station. BOLO on the plate. Shop clerks remember. Fixes: a player could name
  someone else's car or any object in a drive-off report, and the camera could cut on a bystander.

- **19 November 2026.** Caught drive-offs go to dps-insurance: accident log entry and a premium rise.
- **19 November 2026.** First version: ripped hose and stuck nozzle, pump fire and explosion through
  SmartFires, station camera picture, wasabi_mdt call, everything tunable in `config.lua`.

## Author

Made by [DaemonAlex](https://github.com/DaemonAlex) for DelPerroSands.

## Other DPS scripts

All of these are made for DelPerroSands and run together on one Qbox server. Each one works on
its own. The ones marked "pairs with" do more when both are running.

| Script | What it does |
|---|---|
| [dps-inventory](https://github.com/DaemonAlex/dps-inventory) | The inventory: ox_inventory with equipment slots, backpacks, armour plates and a self status panel, in the DelPerroSands colours. |
| [dps-medical](https://github.com/DaemonAlex/dps-medical) | Patient records, illness and diagnostic tests. A companion to wasabi_ambulance. Pairs with dps-inventory: symptoms and diagnoses show on the status panel. |
| [dps-insurance](https://github.com/DaemonAlex/dps-insurance) | Ties m-Insurance into the MDT, impound, hospital and medical chart. Pairs with dps-medical. |
| [dps-studio](https://github.com/DaemonAlex/dps-studio) | Build rooms, doors and portals in game from one panel (`/studio`), with owners and managers so staff do not have to support them. |
| [dps-shops](https://github.com/DaemonAlex/dps-shops) | Shop clerks who greet and react to a robbery, then player-owned shops. |
| [dps-fleet](https://github.com/DaemonAlex/dps-fleet) | Vehicle browser and workshop on one panel: extras, liveries and mods for emergency vehicles. |
| [dps-parking](https://github.com/DaemonAlex/dps-parking) | Parking with valet, impound, violations and reserved spots. |
| [dps-vehiclepersistence](https://github.com/DaemonAlex/dps-vehiclepersistence) | Vehicles stay where they were parked. Pairs with dps-parking. |
| [dps-towjob](https://github.com/DaemonAlex/dps-towjob) | Queue-based tow job with jg-mechanic integration. |
| [dps-services](https://github.com/DaemonAlex/dps-services) | Request a tow and follow it live on the lb-phone and lb-tablet. Pairs with dps-towjob. |
| [dps-autoshops](https://github.com/DaemonAlex/dps-autoshops) | Self-service repair shops when no mechanic is on duty. |
| [dps-cityworker](https://github.com/DaemonAlex/dps-cityworker) | City infrastructure job and career. |
| [dps-ainpcs](https://github.com/DaemonAlex/dps-ainpcs) | NPCs you can talk to, with trust, quests and intel. |
| [dps-badpeds](https://github.com/DaemonAlex/dps-badpeds) | Police interaction with NPCs: stops, arrests, intel and jail records. |
| [dps-gangwars](https://github.com/DaemonAlex/dps-gangwars) | Ambient gang NPCs, territory population and war reinforcements. |
| [dps-rotations](https://github.com/DaemonAlex/dps-rotations) | Moves dealers, harvests and other spots on a fixed schedule. |
| [dps-trains](https://github.com/DaemonAlex/dps-trains) | The train system. Pairs with dps-trains-stock, dps-traintools and dps-transitapp. |
| [dps-transitapp](https://github.com/DaemonAlex/dps-transitapp) | Live train arrival boards on the lb-phone. |
| [dps-faceplant](https://github.com/DaemonAlex/dps-faceplant) | City help, reports and staff tools on the lb-phone and lb-tablet. |
| [dps-chat](https://github.com/DaemonAlex/dps-chat) | A command box for voice-only servers. No chat feed. |
| [dps-filmmode](https://github.com/DaemonAlex/dps-filmmode) | One key hides every HUD layer and gives a smooth free camera for recording. |
