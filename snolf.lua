freeslot("SPR_SFST", "SPR_SFAH", "SPR_SFAV", "SPR_SFMR", "SPR_SFHX", "sfx_msnolf")

-- declare functions in advance so they can reference each other
-- without causing parsing errors
local shot_ready, horizontal_charge, vertical_charge, waiting_to_stop, is_snolf,
	at_rest, take_a_mulligan, same_position, snolf_setup, reset_state,
	sinusoidal_scale, get_charge_increment, in_black_core, allow_air_snolf,
	cheat_toggle, snolfify_name, is_snolf_setup, override_controls, are_touching,
	on_hit_boss, calculate_weight

local cheats = {
	everybodys_snolf = false,
	everybodys_snolf_name_override = 1,

	snolf_inf_rings = false,
	snolf_inf_lives = true,
	snolf_inf_air = false,
	snolf_death_mulligan = false,
	snolf_ground_control = false,
	snolf_air_shot = false,

	snolf_fire_shield = true,

	snolf_shot_on_hit_boss = true,
	snolf_shot_on_hit_by_boss = true,
	snolf_rings_on_hit_boss = true,
	snolf_shot_on_touch_ground_when_in_boss = true,
	snolf_shot_on_touch_wall_when_in_boss = false
}

local bosses_health = {}
local boss_level = false
local metal_snolf_timer = 0
local metal_snolf = nil
local oldmap = nil

---------------
-- constants --
---------------
local TICKS_FOR_MULLIGAN = 35 -- how long to hold down the spin button to take a mulligan
local BOUNCE_LIMIT = 10*FRACUNIT -- Snolf won't bounce if their vertical momentum is less than this
local BOUNCE_FACTOR = FRACUNIT/2 -- when Snolf bounces their momentum is multiplied by this factor
local SKIM_THRESHOLD = 10*FRACUNIT -- Snolf must be going at least this fast horizontally to skip across water
local SKIM_ANLGE = ANG20 -- Snolf will not skip if if angle of approach is greater than this
local SKIM_FACTOR = 4*FRACUNIT/5 -- when Snolf skims their momentum is multiplied by this factor

local STATE_WAITING, STATE_READY, STATE_HCHARGE, STATE_VCHARGE = 1, 2, 3, 4

-- as it stands the max strength of a fully charged shot,
-- the charge meter period and the max displacement of the charge meter arrows
-- during the animation are all deterimned by these two constants, one each
-- for horizontal and vertical. ideally these should be six different constants
local H_METER_LENGTH = 50
local V_METER_LENGTH = 50
local WATER_AIR_TIMER = 1050
local SPACE_AIR_TIMER = 403



---------------
-- functions --
---------------

-- store all snolf-relevant state info in player_t.snolf
snolf_setup = function(player)
	player.snolf = {
		-- SRB2 data structures
		p = player,
		-- Snolf shot state
		state = STATE_WAITING,
		hdrive = 0,
		vdrive = 0,
		chargegoingback = false,
		-- previous tick state
		prev = { momz = 0 },
		-- controls
		ctrl = { jmp = 0, spn = 0, ca1 = 0 },
		-- mulligan points
		mull_pts = {},
		--stats
		shotcount = 0,
		mullcount = 0,
		--collision check
		collided = false
	}
end


-- resetting state to be used on death or level change
reset_state = function(snlf, leave_mulls)
	boss_level = false
	snlf.prev = { momz = 0 }
	snlf.hdrive = 0
	snlf.vdrive = 0
	snlf.state = STATE_WAITING
	if not leave_mulls then
		snlf.mull_pts = {}
	end
end


is_snolf = function(mo)
	return mo and mo.skin and (mo.skin == "snolf" or cheats.everybodys_snolf)
end

is_snolf_setup = function(mo)
	return is_snolf(mo) and mo.player.snolf
end


at_rest = function(snlf)
	-- player is on the ground and not on a waterslide and not moving
	return P_IsObjectOnGround(snlf.p.mo) and snlf.p.pflags & PF_SLIDING == 0 and
		snlf.p.speed == 0 and snlf.p.mo.momz == 0
end


take_a_mulligan = function(snlf, dont_play_sound)
	local lm = snlf.mull_pts[#snlf.mull_pts] -- last mulligan point
	local mo = snlf.p.mo
	-- if we're still at the last mulligan point remove it and go back one
	if lm and same_position(lm, mo) then
		table.remove(snlf.mull_pts, #snlf.mull_pts)
		lm = snlf.mull_pts[#snlf.mull_pts]
	end
	if lm then
		if not dont_play_sound then
			S_StartSound(mo, sfx_mixup)
		end
		P_TeleportMove(mo, lm.x, lm.y, lm.z)
		P_InstaThrust(mo, 0, 0)
		P_SetObjectMomZ(mo, 0)
		if snlf.p.pflags & PF_FINISHED == 0 then
			snlf.mullcount = $1 + 1
		end
	end
end


same_position = function(pt1, pt2)
	return pt1.x == pt2.x and pt1.y == pt2.y and pt1.z == pt2.z
end


-- converts a value on a linear scale with min value 0 and max value m to a
-- sinusoidal scale with the same limits.
-- m/2(1-cos(pi*x/m))
sinusoidal_scale = function(x, m)
	local xf, mf = x*FRACUNIT, m*FRACUNIT
	-- is this this too computationally expensive?
	local angle = FixedAngle(FixedDiv(FixedMul(AngleFixed(ANGLE_180),xf),mf))
	return FixedRound(FixedMul(FRACUNIT - cos(angle),mf)/2) / FRACUNIT
end


get_charge_increment = function(snlf)
	local increment = 1
	if in_black_core() then
		-- double charge rate for the last few bosses
		increment = $1 * 2
	end
	if snlf.p.powers[pw_super] > 0 then
		-- double charge rate for Super Snolf
		increment = $1 * 2
	end
	if snlf.p.powers[pw_sneakers] > 0 then
		-- double charge rate for Speed Shoes
		increment = $1 * 2
	end
	return increment
end


-- the last few bosses are very difficult
-- so I'm going to give the player a few bonuses if they've gotten that far
in_black_core = function()
	local black_core_maps = {
		[25]=true, -- Metal Sonic Race
		[26]=true, -- Metal Sonic Fight
		[27]=true} -- Metal Robotnik Fight
	return black_core_maps[gamemap]
end


-- situations where we want Snolf to be able to shoot mid-air
allow_air_snolf = function(snlf)
	-- air snolf cheat
	if cheats.snolf_air_shot then
		return true
	end
	-- Super Snolf
	if snlf.p.powers[pw_super] > 0 then
		return true
	-- if Snolf is in the vacuum of space
	elseif snlf.p.powers[pw_spacetime] > 0 then
		return true
	end
	-- for the last three bosses
	return in_black_core()
end


override_controls = function(snlf)
	local player = snlf.p
	player.jumpfactor = 0 -- disable jump
	if player.charability2 == CA2_SPINDASH then
		player.charability2 = CA2_NONE --disable spindash
	end
	if cheats.snolf_ground_control and snlf.state == STATE_WAITING then
		player.accelstart = 96
		player.acceleration = 40
	else
		player.accelstart = 0
		player.acceleration = 0
	end
end

-- assume players are spheres of diameter = spinheight
are_touching = function(play1, play2)
	local r1 = P_GetPlayerSpinHeight(play1)/2/FRACUNIT
	local r2 = P_GetPlayerSpinHeight(play2)/2/FRACUNIT

	local x = abs(play1.mo.x - play2.mo.x)/FRACUNIT
	local y = abs(play1.mo.y - play2.mo.y)/FRACUNIT
	local z = abs(play1.mo.z - play2.mo.z)/FRACUNIT

	return x*x+y*y+z*z<r1*r1+r2*r2+2*r1*r2
end


cheat_toggle = function(cheat_name, arg, player)
	local current_bool = cheats[cheat_name]
	if arg == nil then
		cheats[cheat_name] = not $1
	elseif arg == "0" or arg == "off" or arg == "false" then
		cheats[cheat_name] = false
	elseif arg == "1" or arg == "on" or arg == "true" then
		cheats[cheat_name] = true
	else
		CONS_Printf(player, cheat_name.." should be called with either 'on', 'off', or no argument")
		return
	end
	chatprint(cheat_name.." has been "..(cheats[cheat_name] and "enabled" or "disabled")..".")
end


snolfify_name = function(orig_name)
	orig_name = orig_name:lower()

	-- bafflingly the game uses a control character in character names
	local sep = string.char(30)

	-- hardcoding some names for certain characters, including from other mods
	local name_lookup = {
		sonic = "Snolf",
		knuckles = "Knolf",
		amy = "Amy Rolf",
		metal = "M"..sep.."Snolf",
		robotnik = "Robotnolf",
		shadow = "Shdolf",
		silver = "Slolf",
		rouge = "Roulfe",
		gamma = "102-Golf",
		dickkickem = "Dolf Snolfem"}
	name_lookup["k"..sep.."t"..sep.."e"] = "Knolf"
	name_lookup["amy"..sep.."r"] = "Amy Rolf"
	name_lookup["tails doll"] = "Tolf doll"
	name_lookup["m"..sep.."k"] = "M"..sep.."knolf"
	name_lookup["egg robo"] = "Egg Robolf"
	local consonants = "bcdfghjklmnpqrstvwxyz"

	local name = name_lookup[orig_name]

	if name ~= nil then
		return name
	end


	local i = #orig_name
	-- iterate backwards till we find a G
	repeat
		i = $1 - 1
	until i == 0 or orig_name:sub(i,i) == "g"
	if i > 0 then
		return orig_name:sub(1, i) .. "olf"
	end


	i = #orig_name
	-- iterate backwards till we find an O
	repeat
		i = $1 - 1
	until i == 0 or orig_name:sub(i,i) == "o"
	if i > 0 then
		return orig_name:sub(1, i) .. "lf"
	end


	i = 0
	-- iterate over letters till find a consonant
	repeat
		i = $1 + 1
	until i > #orig_name or consonants:find(orig_name:sub(i,i)) ~= nil
	-- then iterate until something that is not a consonant is found
	repeat
		i = $1 + 1
	until i > #orig_name or consonants:find(orig_name:sub(i,i)) == nil

	if i ~= #orig_name and i > 1 then
		return orig_name:sub(1, i-1) .. "olf"
	end

	return orig_name
end

on_hit_boss = function(boss, player_hopefully)
	for player in players.iterate do
		if player.mo ~= player_hopefully then
			continue
		end

		if cheats.snolf_shot_on_hit_boss then
			if is_snolf_setup(player.mo) and player.snolf.state == STATE_WAITING then
				player.snolf.state = STATE_READY
			end
		end
	end
end


-- I wanted some characters to be considered heavier than others but weight is
-- not an attribute characters have. I have opted for some weird logic instead.
-- A character's mass is considered to be inverse of their jumpfactor.
-- So e.g. Knuckles is heavier than Sonic who is heavier than Amy.
calculate_weight = function(mo)
	local jumpfactor = skins[mo.skin].jumpfactor
	if jumpfactor == 0 then jumpfactor = FRACUNIT end -- default in case it's 0

	local mass = FixedDiv(FRACUNIT, jumpfactor)

	-- try to guess if the character is a robot, Robotnik or Milne
	-- if so, double their weight
	local name = string.lower(skins[mo.skin].realname)
	if string.find(name,'metal')~=nil or string.find(name,'gamma')~=nil or
		string.find(name,'omega')~=nil or string.find(name,'robo')~=nil or
		string.find(name,'milne')~=nil or string.find(name,'eggman')~=nil then
		mass = $1*2
	end

	--or if it it's Tails Doll (or anything else named doll) reduce the weight
	if string.find(name, 'doll') ~= nil then
		mass = $1/2
	end

	return mass
end

-------------------
-- HUD functions --
-------------------
-- shot meter
hud.add( function(v, player, camera)
	if not is_snolf_setup(player.mo) then return end

	local state = player.snolf.state
	if state != STATE_HCHARGE and state != STATE_VCHARGE then return end

	local meter = v.getSpritePatch(SPR_SFMR)  -- shot meter sprite
	local harrow = v.getSpritePatch(SPR_SFAH, 0, 4) -- shot meter arrow sprite 1
	local varrow = v.getSpritePatch(SPR_SFAV, 0, 5) -- shot meter arrow sprite 2

	local hpos = sinusoidal_scale(player.snolf.hdrive, H_METER_LENGTH)
	local vpos = sinusoidal_scale(player.snolf.vdrive, V_METER_LENGTH)

	if hpos < 1 then hpos = 1 end
	if vpos < 1 then vpos = 1 end

	v.draw(158, 103, meter)
	v.draw(160+hpos, 151, harrow)
	if state == STATE_VCHARGE then
		v.draw(159, 150-vpos, varrow)
	end
end, "game")


-- shots count
hud.add( function(v, player, camera)
	if not is_snolf_setup(player.mo) then return end

	local hud_shots = v.getSpritePatch(SPR_SFST) -- SHOTS HUD element
	local shotcount = player.snolf.shotcount + player.snolf.mullcount

	if player.pflags & PF_FINISHED == 0 or player.exiting > 0 then
		v.draw(16, 58, hud_shots, V_HUDTRANS|V_SNAPTOLEFT|V_SNAPTOTOP)
		v.drawNum(96, 58, shotcount, V_HUDTRANS|V_SNAPTOLEFT|V_SNAPTOTOP)
	end
end, "game")


-- everybody's snolf life icon
hud.add ( function(v, player, camera)

	if cheats.everybodys_snolf and cheats.everybodys_snolf_name_override == 1 and
		player.mo and player.mo.skin then

		local life_x = v.getSpritePatch(SPR_SFHX)
		v.draw(38, 186	, life_x, V_HUDTRANS|V_SNAPTOLEFT|V_SNAPTOBOTTOM)

		local life_icon = v.getSprite2Patch(player.mo.skin, SPR2_XTRA, player.powers[pw_super] > 0)
		v.drawScaled(16*FRACUNIT, 176*FRACUNIT, FRACUNIT/2, life_icon,
			V_HUDTRANS|V_SNAPTOLEFT|V_SNAPTOBOTTOM,
			v.getColormap(player.mo.skin, player.mo.color))
		v.drawString(74, 184, player.lives, V_HUDTRANS|V_SNAPTOLEFT|V_SNAPTOBOTTOM, "right" )

		local hudname = snolfify_name(skins[player.mo.skin].hudname)

		if #hudname > 7 then
			v.drawString(34, 176, hudname, V_YELLOWMAP|V_HUDTRANS|V_SNAPTOLEFT|V_SNAPTOBOTTOM, "thin")
		elseif #hudname > 6 then
			v.drawString(74, 176, hudname, V_YELLOWMAP|V_HUDTRANS|V_SNAPTOLEFT|V_SNAPTOBOTTOM, "thin-right")
		elseif #hudname == 6 then
			v.drawString(34, 176, hudname, V_YELLOWMAP|V_HUDTRANS|V_SNAPTOLEFT|V_SNAPTOBOTTOM, "left")
		elseif #hudname < 6 then
			v.drawString(74, 176, hudname, V_YELLOWMAP|V_HUDTRANS|V_SNAPTOLEFT|V_SNAPTOBOTTOM, "right")
		end
	end
end, "game")



-----------
-- hooks --
-----------

-- main hook
addHook("PreThinkFrame", function()
	for player in players.iterate do

		-- don't do anything if we're not Snolf
		if not is_snolf(player.mo) then continue end

		if player.snolf == nil then
			snolf_setup(player)
		end

		-- set some local variables as shortcuts
		local p, mo, snlf = player, player.mo, player.snolf

		-- check controls
		snlf.ctrl.jmp = p.cmd.buttons & BT_JUMP and $1+1 or 0
		snlf.ctrl.spn = p.cmd.buttons & BT_SPIN and $1+1 or 0
		snlf.ctrl.ca1 = p.cmd.buttons & BT_CUSTOM1 and $1+1 or 0


		for boss in pairs(bosses_health) do
			if not boss or not boss.valid then
				bosses_health[boss] = nil
			end
		end

		-- try to set a mulligan point
		if at_rest(snlf) then
			local mo, mulls = snlf.p.mo, snlf.mull_pts
			local lm = mulls[#mulls] -- last mulligan point

			-- if we don't have a mulligan point yet
			-- or if our last one does not match our current position
			if not lm or not same_position(mo, lm) then
				-- if there's already ten mulligan points stored then remove one
				if #mulls > 9 then
					table.remove(mulls, 1)
				end
				table.insert(mulls, {x = mo.x, y = mo.y, z = mo.z})
			end
		end

		-- state dependent update
		-- waiting to come to rest
		if snlf.state == STATE_WAITING then
			--allow a shot to happen
			if at_rest(snlf) or allow_air_snolf(snlf) then
				snlf.state = STATE_READY
				override_controls(snlf)
			end
		-- ready to start taking a shot
		elseif snlf.state == STATE_READY then
			-- jump is pressed
			if snlf.ctrl.jmp == 1 then
				snlf.hdrive = -1
				snlf.vdrive = -1
				S_StartSoundAtVolume(pmo, sfx_spndsh, 64)
				snlf.chargegoingback = false
				snlf.state = STATE_HCHARGE
			end
		-- choosing horizontal force
		elseif snlf.state == STATE_HCHARGE then
			-- jump is pressed
			if snlf.ctrl.jmp == 1 then
				S_StartSoundAtVolume(pmo, sfx_spndsh, 100)
				snlf.chargegoingback = false
				snlf.state = STATE_VCHARGE
			else
				local increment = get_charge_increment(snlf)
				if snlf.chargegoingback then
					increment = $1 * -1
				end
				snlf.p.pflags = $1 | PF_STARTDASH | PF_SPINNING -- force spindash state
				if snlf.hdrive >= H_METER_LENGTH then
					snlf.chargegoingback = true
				elseif snlf.hdrive <= 0 then
					snlf.hdrive = 0
					snlf.chargegoingback = false
				end
				snlf.hdrive = $1 + increment
			end
		-- choosing vertical force
		elseif snlf.state == STATE_VCHARGE then
			-- jump is pressed
			if snlf.ctrl.jmp == 1 then
				-- shoot
				S_StartSound(pmo, sfx_zoom)
				local h = sinusoidal_scale(snlf.hdrive, H_METER_LENGTH)
				local v = sinusoidal_scale(snlf.vdrive, V_METER_LENGTH)
				P_InstaThrust(snlf.p.mo, snlf.p.mo.angle, h*FRACUNIT)
				P_SetObjectMomZ(snlf.p.mo, v*FRACUNIT)

				-- change some player state
				snlf.p.pflags = $1 | PF_JUMPED
				if p.pflags & PF_FINISHED == 0 then
					snlf.shotcount = $1 + 1
				end

				snlf.state = STATE_WAITING
			else
				local increment = get_charge_increment(snlf)
				if snlf.chargegoingback then
					increment = $1 * -1
				end
				snlf.p.pflags = $1 | PF_STARTDASH | PF_SPINNING -- force spindash state
				if snlf.vdrive >= V_METER_LENGTH then
					snlf.chargegoingback = true
				elseif snlf.vdrive <= 0 then
					snlf.vdrive = 0
					snlf.chargegoingback = false
				end
				snlf.vdrive = $1 + increment
			end
		end


		-- take a mulligan
		if snlf.ctrl.spn == TICKS_FOR_MULLIGAN then
			take_a_mulligan(snlf)
		end

		-- skim across water
		if mo.momz < 0 and p.speed > SKIM_THRESHOLD and mo.eflags & MFE_TOUCHWATER > 0 and
		R_PointToAngle2(0, 0, p.speed, -mo.momz) < SKIM_ANLGE then
			mo.momx = FixedMul($1, SKIM_FACTOR)
			mo.momy = FixedMul($1, SKIM_FACTOR)
			P_SetObjectMomZ(mo, -mo.momz)
			S_StartSound(mo, sfx_splish)
			if boss_level and cheats.snolf_shot_on_touch_ground_when_in_boss and snlf.state == STATE_WAITING then
				snlf.state = STATE_READY
			end
		end

		-- check if we landed this turn
		if mo.eflags & MFE_JUSTHITFLOOR > 0 then
			--makes bosses easier
			if boss_level and cheats.snolf_shot_on_touch_ground_when_in_boss and snlf.state == STATE_WAITING then
				snlf.state = STATE_READY
			end
			-- if going fast enough when Snolf hits the ground, bounce
			if abs(snlf.prev.momz) > BOUNCE_LIMIT and p.playerstate ~= PST_DEAD then
				P_SetObjectMomZ(mo, - FixedMul(snlf.prev.momz, BOUNCE_FACTOR))
				snlf.p.pflags = $1 | PF_JUMPED
			-- otherwise land
			else
				p.pflags = $1 | PF_SPINNING -- force spinning flag
				override_controls(snlf)
			end
		end

		-- enable jumping while on a water slide
		if p.pflags & PF_SLIDING ~= 0 and p.jumpfactor == 0 then
			p.jumpfactor = FRACUNIT
		elseif not P_IsObjectOnGround(mo) then
			-- give back jump. It will be taken away again on landing
			-- this is done so that players can jump off objects like
			-- the rollout rocks in Red Volcano Zone
			p.jumpfactor = skins[mo.skin].jumpfactor
		end

		-- infinite rings cheat
		if cheats.snolf_inf_rings then
			p.xtralife = 99
			p.rings = 999
		end

		-- no drowning cheat
		if cheats.snolf_inf_air then
			if p.powers[pw_underwater] > 0 then
				p.powers[pw_underwater] = WATER_AIR_TIMER
				P_RestoreMusic(p)
			end
			if p.powers[pw_spacetime] > 0 then
				p.powers[pw_spacetime] = SPACE_AIR_TIMER
			end
		end

		-- store certain state attributes so we can check for changes next tick
		snlf.prev.momz = player.mo.momz
	end
end)


addHook("ThinkFrame", function()
	local snolf_players = {}
	for play1 in players.iterate do
		if not is_snolf_setup(play1.mo) then continue end
		for play2 in players.iterate do
			if play1 == play2 then continue end
			if not is_snolf_setup(play2.mo) then continue end
			if (not at_rest(play1.snolf) or not at_rest(play2.snolf)) and
				not play1.snolf.collided and not play2.snolf.collided and
				are_touching(play1, play2) then

				play1.snolf.collided = true
				play2.snolf.collided = true

				local mo1, mo2 = play1.mo, play2.mo

				local m1 = calculate_weight(mo1)
				local m2 = calculate_weight(mo2)

				if m1 == m2 then -- swap velocities
					mo1.momx, mo2.momx = mo2.momx, mo1.momx
					mo1.momy, mo2.momy = mo2.momy, mo1.momy
					mo1.momz, mo2.momz = mo2.momz, mo1.momz
				else
					-- collision of two spheres
					-- v1 = u1(m1-m2)/(m1+m2) + u2*m2*2/(m1+m2)
					-- v2 = u1*m1*2/(m1+m2) + u2(m2-m1)/(m1+m2)

					local mm1 = FixedDiv(2*m1, m1+m2)
					local mm2 = FixedDiv(2*m2, m1+m2)
					local mm3 = FixedDiv(m1-m2,m1+m2)

					mo1.momx, mo2.momx = FixedMul(mo1.momx,mm3)+FixedMul(mo2.momx,mm2), FixedMul(mo1.momx,mm2)+FixedMul(mo2.momx,-mm3)
					mo1.momy, mo2.momy = FixedMul(mo1.momy,mm3)+FixedMul(mo2.momy,mm2), FixedMul(mo1.momy,mm2)+FixedMul(mo2.momy,-mm3)
					mo1.momz, mo2.momz = FixedMul(mo1.momz,mm3)+FixedMul(mo2.momz,mm2), FixedMul(mo1.momz,mm2)+FixedMul(mo2.momz,-mm3)
				end
				S_StartSound(mo1, sfx_s3k7b)
			end
		end
	end
end)


addHook("PostThinkFrame", function()
	for player in players.iterate do
		if not is_snolf_setup(player.mo) then continue end
		player.mo.state = S_PLAY_ROLL -- always force rolling animation

		local snlf = player.snolf

		snlf.collided = false
	end
end
)

-- Hook to override default collision and make Snolf bounce off walls
addHook("MobjMoveBlocked", function(mo)
	if not is_snolf_setup(mo) then return false end

	local slope = mo.standingslope
	if slope and slope.valid and slope.zangle >= ANGLE_45 then
		return false
	end

	--let player take a shot if they bounce off walls while fighting a boss
	if boss_level and cheats.snolf_shot_on_touch_wall_when_in_boss then
		local player = mo.player
		if is_snolf_setup(mo) and player.snolf.state == STATE_WAITING then
			player.snolf.state = STATE_READY
		end
	end

	-- P_BounceMove doesn't bounce the player if they are on the ground
	-- To get around this impart the tiniest possible vertical momentum the
	-- engine will allow so Snolf is technically in the air for a single frame
	if P_IsObjectOnGround(mo) then
		P_SetObjectMomZ(mo, 1)
	end
	P_BounceMove(mo)
	return true
end, MT_PLAYER)


-- reset state on death
addHook("MobjDeath", function(mo)
	if not is_snolf_setup(mo) then return false end
	reset_state(mo.player.snolf, cheats.snolf_death_mulligan)

	-- infinite lives cheat
	if cheats.snolf_inf_lives then
		mo.player.lives = $1 + 1
	end
end)

-- reset state when a new map is loaded
addHook("MapLoad", function(mapnumber)
	for player in players.iterate do
		if not is_snolf_setup(player.mo) then continue end
		reset_state(player.snolf)
	end


end)


--play announcement when starting metal snolf race
addHook("MapLoad", function(mapnumber)
	--only play when loading map for the first time
	if mapnumber == 25 and mapnumber ~= oldmap then
		for player in players.iterate do
			if player.mo then
				S_StartSound(player.mo, sfx_msnolf, player)
			end
		end
	end
end)


-- cheat to return to last spot on death
addHook("PlayerSpawn", function(player)
	if is_snolf_setup(player.mo) and cheats.snolf_death_mulligan then
		take_a_mulligan(player.snolf, true)
	end
end)

-- Immediately allow player to take another shot if they hit a boss
addHook("MobjCollide", on_hit_boss, MT_EGGMOBILE, S_EGGMOBILE_PAIN)
addHook("MobjCollide", on_hit_boss, MT_EGGMOBILE2)
addHook("MobjCollide", on_hit_boss, MT_EGGMOBILE3)
addHook("MobjCollide", on_hit_boss, MT_EGGMOBILE4)
addHook("MobjCollide", on_hit_boss, MT_FANG)
addHook("MobjCollide", on_hit_boss, MT_BLACKEGGMAN)
addHook("MobjCollide", on_hit_boss, MT_CYBRAKDEMON)
addHook("MobjCollide", on_hit_boss, MT_METALSONIC_BATTLE)

--allow player to take a shot after they've been hit by a boss
addHook("MobjDamage", function(target, inflictor, source, damage, damagetype)
	if not target or not target.player then
		return
	end

	local player = target.player
	if ( source ~= nil and (source.type >= MT_BOSSEXPLODE and source.type <= MT_MSGATHER) )
		or (  inflictor ~= nil and ( inflictor.type >= MT_BOSSEXPLODE and inflictor.type <= MT_MSGATHER ) ) then

		if is_snolf_setup(player.mo) and player.snolf.state == STATE_WAITING then
			player.snolf.state = STATE_READY
		end
	end
end, MT_PLAYER)


--track the health of bosses
addHook("BossThinker", function(boss)
	if not bosses_health[boss] then
		bosses_health[boss] = boss.health
	elseif bosses_health[boss] ~= boss.health then
		bosses_health[boss] = boss.health

		-- boss drops rings
		if cheats.snolf_rings_on_hit_boss then
			S_StartSound(boss, sfx_s3kb9)
			for i=0, 5 do
				local ring = P_SpawnMobjFromMobj(boss, 0,0,0, MT_FLINGRING)
				ring.fuse = 8*TICRATE
				ring.momx = FixedMul(4*FRACUNIT, cos(ANG60*i + boss.angle))
				ring.momy = FixedMul(4*FRACUNIT, sin(ANG60*i + boss.angle))
				ring.momz = 3*FRACUNIT
			end
		end
	end
end)

--if a boss is present then set boss_level flag
addHook("BossThinker", function(boss)
	--unless it's Egg Rock Zone Act 2 because that has a secret boss and
	--and I don't want to trigger boss effects for that entire level
	if gamemap ~= 23 then
		boss_level = true
	end
end)

addHook("MobjDamage", function(player, inflictor, source, damage, damagetype)
	-- Snolf has an asbestos suit because Red Volcano is almost impossible
	if cheats.snolf_fire_shield and inflictor and
		inflictor.type ==  MT_FLAMEJETFLAMEB and is_snolf(player) then
		return true
	end
end, MT_PLAYER)


--force metal sonic to be metal snolf
--find metal snolf in the race
addHook("MobjThinker", function(metal_sonic_race)
	metal_snolf = metal_sonic_race
end, MT_METALSONIC_RACE)

--force metal snolf into rolling animation
addHook("PostThinkFrame", function()
	if metal_snolf ~= nil and metal_snolf.valid then
		-- for the race let finger wag play first
		if metal_snolf_timer > TICRATE*3 - TICRATE/2  then
			metal_snolf.state = S_PLAY_ROLL --force roll state
		elseif gamemap == 25 then
			metal_snolf_timer = $1+1
		end
	end
end)

--record what level we're moving from when changing levels
addHook("MapChange", function(mapnum)
	oldmap = gamemap
	metal_snolf_timer = 0
end)

--------------
-- Commands --
--------------

COM_AddCommand("everybodys_snolf", function(player, arg)
	cheat_toggle("everybodys_snolf", arg, player)
	-- restore character stats
	for player in players.iterate do
		if player.mo and not is_snolf(player.mo) then
			local skin = skins[player.mo.skin]
			player.jumpfactor = skin.jumpfactor
			player.accelstart = skin.accelstart
			player.acceleration = skin.acceleration
			player.charability2 = skin.ability2
		end
	end

	if cheats.everybodys_snolf and cheats.everybodys_snolf_name_override > 0 then
		hud.disable("lives")
	else
		hud.enable("lives")
	end
end, COM_ADMIN)


COM_AddCommand("everybodys_snolf_name_override", function(player, arg)
	if arg == nil then
		cheats.everybodys_snolf_name_override = $1 == 0 and 1 or 0
	elseif arg == "0" or arg == "off" or arg == "false" then
		cheats.everybodys_snolf_name_override = 0
	elseif arg == "1" or arg == "on" or arg == "true" then
		cheats.everybodys_snolf_name_override = 1
	elseif arg == "2" then
		cheats.everybodys_snolf_name_override = 2
	else
		CONS_Printf(player, "everybodys_snolf_name_override should be called with either 0, 1, 2 or no argument")
	end
	chatprint("everybodys_snolf_name_override has been "..(cheats.everybodys_snolf_name_override > 0 and "enabled" or "disabled")..".")

	if cheats.everybodys_snolf and cheats.everybodys_snolf_name_override > 0 then
		hud.disable("lives")
	else
		hud.enable("lives")
	end
end, COM_ADMIN)


COM_AddCommand("snolf_inf_rings", function(player, arg)
	cheat_toggle("snolf_inf_rings", arg, player)
end, COM_ADMIN)

COM_AddCommand("snolf_inf_lives", function(player, arg)
	cheat_toggle("snolf_inf_lives", arg, player)
end, COM_ADMIN)

COM_AddCommand("snolf_inf_air", function(player, arg)
	cheat_toggle("snolf_inf_air", arg, player)
end, COM_ADMIN)

COM_AddCommand("snolf_death_mulligan", function(player, arg)
	cheat_toggle("snolf_death_mulligan", arg, player)
end, COM_ADMIN)

COM_AddCommand("snolf_ground_control", function(player, arg)
	cheat_toggle("snolf_ground_control", arg, player)
end, COM_ADMIN)

COM_AddCommand("snolf_air_shot", function(player, arg)
	cheat_toggle("snolf_air_shot", arg, player)
end, COM_ADMIN)

COM_AddCommand("snolf_fire_shield", function(player, arg)
	cheat_toggle("snolf_fire_shield", arg, player)
end, COM_ADMIN)

COM_AddCommand("snolf_shot_on_hit_boss", function(player, arg)
	cheat_toggle("snolf_shot_on_hit_boss", arg, player)
end, COM_ADMIN)

COM_AddCommand("snolf_shot_on_hit_by_boss", function(player, arg)
	cheat_toggle("snolf_shot_on_hit_by_boss", arg, player)
end, COM_ADMIN)

COM_AddCommand("snolf_rings_on_hit_boss", function(player, arg)
	cheat_toggle("snolf_rings_on_hit_boss", arg, player)
end, COM_ADMIN)

COM_AddCommand("snolf_shot_on_touch_ground_when_in_boss", function(player, arg)
	cheat_toggle("snolf_shot_on_touch_ground_when_in_boss", arg, player)
end, COM_ADMIN)

COM_AddCommand("snolf_shot_on_touch_wall_when_in_boss", function(player, arg)
	cheat_toggle("snolf_shot_on_touch_wall_when_in_boss", arg, player)
end, COM_ADMIN)
