## Snolf Robo Blast 2

Snolf character mod for Sonic Robo Blast 2 that allows you to play it like golf. Snolf cannot move normally and controls like a golf game. Aim with the camera and use the jump button to start charging a shot. Use the jump button again to time your shot power.


## Installation

Download and install [Sonic Robo Blast 2].

Download the Snolf WAD file. See the Sonic Robo Blast 2 wiki for [how to load a WAD file]. Snolf will appear as a separate character in the character select menu.

Sonic Robo Blast 2 does not allow saving with addons loaded by default. In order to enable saving use [V_customsave-v1.soc].

[Sonic Robo Blast 2]: https://www.srb2.org/
[how to load a WAD file]: https://wiki.srb2.org/wiki/WAD_file#Loading_WAD_files
[V_customsave-v1.soc]: https://mb.srb2.org/showthread.php?t=45730


## Controls

Snolf cannot move or jump like a normal character. Instead they must take a golf swing.

**Swing:** Aim with the camera and use the Jump button to time your shots' horizontal and vertical power.

**Mulligan:** Hold the Spin button to undo your last shot. Use this if you get stuck.

**Quick Turn:** Press Custom Action 1 to do a 180° turn.

*Tip:* If the camera is getting caught on a wall use first person view to aim.


## Cheats

Because this, by design, makes many levels incredibly difficult I've included a built in cheat mode. Cheats are toggled by holding down the second custom action button and pressing a series of directional inputs with the WASD keys or whatever you are using for movement. When a cheat is toggled a sound will play and an indicator will be displayed on the HUD. Entering a cheat a second time will disable it.

* ↑ ↓ ← → - Infinite lives
* ↑ ↓ ↓ ← → - Infinite rings
* ↑ ↑ ↓ ↓ ↑ ↑ ↑ ↑ - On death return to last resting point
* ↑ ← ← ↓ ↑ ↑ ↓ → - Enable steering on the ground
* ← ← ← → → → ↑ ↑ ↑ - No drowning


## Everybody's Snolf

Everybody's Snolf is a mini-WAD containing a single Lua script that if used in conjunction with Snolf will force all characters, including characters from other mods, to use Snolf's controls. This is just for a bit of fun and will probably be very unstable and not work very well with a lot of other mods.


## Known Issues

* Quarter- and half-pipe structures do not work correctly. Snolf will just bounce off them instead of being launched into the air.
* Enabling the no drowning cheat while the drowning music is playing will not stop stop the drowning music and the normal stage music will not resume afterwards. You can get it back by disabling the cheat, waiting until the drowning music starts again, getting air the normal way so the stage music resumes, then activating the cheat again.


## Credits

Snolf Robo Blast 2 by [Caoimhe Ní Chaoimh].

Inspired by the original Snolf ROM hacks by [Melon].

Character art by [Mike Tona].

Made using the [Sonic Robo Blast 2 Custom Character Preset] by Blu The Hedgehog.

Life count icon from Mario Golf: Advance Tour.

[Caoimhe Ní Chaoimh]: https://oakreef.ie/
[Melon]: https://melon.zone/
[Mike Tona]: https://miketona.carrd.co/
[Sonic Robo Blast 2 Custom Character Preset]: https://gamebanana.com/skins/181950


## Changelog

v1.3
* Fixed Snolf breaking netplay gameas

v1.2
* Changed how Snolf mode was being checked to fix potential error messages when using Everybody's Snolf
* Added new continue icon
* Added constellation sprites
* Copied rolling animations over walking animations so that Snolf is distinguishable from Sonic in the multiplayer character select screen
* Copied rolling animations to continue screen animations so Snolf is still in a ball on the continue screen
* Added controls and known issues to readme

v1.1

* Added infinite rings cheats
* Added flag to allow other skins to be forced into Snolf controls
* Added small mini WAD to force Snolf controls on all characters
* Added description of cheats to readme
* Added tip about first person view to character select screen
* Mulligan point list is cleared on death (unless return to mulligan point cheat is enabled)
* Mulligan point list is cleared on map change
* Shot is reset on death, map change or while touching a slide
* Moved shots tracker under the ring count and styled to be similar
* Made new HUD elements display consistently on different resolutions
* At-rest check now checks vertical momentum as well
* Teleport sound no longer plays if resetting to last mulligan point on death with cheat

v1.0
* Snolf now rebounds off walls and floors
* Snolf can now revert to previous resting spots with the mulligan
* Added cheats
* Instead of setting forcing PF_JUMPSTASIS Snolf's jumpfactor stat is changed based on situation to allow certain level features to work
* Lots of refactoring

v0.5

* Added Quick Turn ability if spin button is tapped
* Relaxed Mulligan conditions to prevent potential softlocks
* Charging a shot now counts as a spindash and allows player to activate spindash switches
* Snolf's code no longer blocks player input allowing several previously broken mechanics to work
* Force PF_JUMPSTASIS flag to 1 as the new way of preventing Snolf from jumping
* Set Snolf's speed and acceleration to 0 as the new way of preventing Snolf from moving
* Added checks to allow player control when on a waterslide
* Updated character select text
* Code cleanup
* Every level in the main story mode should now, in theory, be completable

v0.4
* Power meter now moves sinusoidally instead of linearlly
* Mulligan disallowed if stationary
* Re-enabled control for NiGHTS mode
* Added custom graphics for power meter
* Added custom graphics for character select, signpost, extra life and life count
* Added warning that levels may not be beatable and credit for life count icon to readme

v0.3
* Added shot counters
* Mulligan resets player's momentum on the Z axis
* Shot Z thrust is no longer relative to existing Z momentum
* Added basic visual charge meters
* Removed print statements
* Increased rate the charge builds
* Moved variables to player.snolf table to reduce risk of conflict with other mods

v0.2
* Snolf no longer swallows inputs for the spin button or custom action buttons
* Snolf now is set to a jump state when launched, allowing them to use shield abilities
* Snolf can take a mulligan, hold the spin button to reset to last stationary position
* Snolf must come to a rest before a new shot can be taken
* Added character select text
* Changed character select colours

v0.1
* Initial Snolf
