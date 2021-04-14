freeslot("SPR_SFST", "SPR_SFAH", "SPR_SFAV", "SPR_SFMR", "SPR_SFHX", "SPR_MSNF",
	"SPR_LVBX", "SPR_INFL", "sfx_msnolf")

sfxinfo[sfx_msnolf].caption = "Anomalous Metal Snolf"

-- declare functions in advance so they can reference each other
-- without causing parsing errors
local shot_ready, horizontal_charge, vertical_charge, waiting_to_stop, at_rest,
	take_a_mulligan, same_position, snolf_setup, reset_state, sinusoidal_scale,
	get_charge_increment, in_black_core, allow_air_snolf, option_toggle,
	snolfify_name, is_golf_setup, override_controls, are_touching, on_hit_boss,
	calculate_weight, is_anyone_snolfing, reversed_gravity, print2, shot_charge,
	draw_trajectory, update_state, is_snolf, is_snolfing, is_golfing,
	is_anyone_snolf, update_hud

local options = {
	everybodys_snolf = false,
	snolf_hud_mode = 1,

	snolf_inf_rings = false,
	snolf_inf_lives = true,
	snolf_inf_air = false,
	snolf_death_mulligan = false,
	snolf_ground_control = false,
	snolf_air_shot = false,
	snolf_save_states = false,

	snolf_shot_guide = false,

	snolf_fire_shield = true,

	snolf_shot_on_hit_boss = true,
	snolf_shot_on_hit_by_boss = true,
	snolf_rings_on_hit_boss = true,
	snolf_shot_on_touch_ground_when_in_boss = true,
	snolf_shot_on_touch_wall_when_in_boss = false
}

local bosses_health = {}
local boss_level = false
local metal_snolf_race = nil
local metal_snolf_battle = nil
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

local STATE_WAITING, STATE_READY, STATE_CHARGE1, STATE_CHARGE2 = 1, 2, 3, 4

-- as it stands the max strength of a fully charged shot,
-- the charge meter period and the max displacement of the charge meter arrows
-- during the animation are all deterimned by these two constants, one each
-- for horizontal and vertical. ideally these should be six different constants
local H_METER_LENGTH = 50
local V_METER_LENGTH = 50
local WATER_AIR_TIMER = 1050
local SPACE_AIR_TIMER = 403

local button_names = {
	spn = "SPIN",
	jmp = "JUMP",
	ca1 = "CUSTOM ACTION 1",
	ca2 = "CUSTOM ACTION 2",
	ca3 = "CUSTOM ACTION 3"
}

---------------
-- functions --
---------------

-- just prints to normal console and also chat
print2 = function(string)
	print(string)
	chatprint(string)
end

-- store all snolf-relevant state info in player_t.snolf
snolf_setup = function(player)
	player.snolf = {
		-- SRB2 data structures
		p = player,
		-- Snolf shot state
		state = STATE_WAITING,
		statetimer = 0,
		hdrive = 0,
		vdrive = 0,
		chargegoingback = false,
		verticalfirst = false,
		-- previous tick state
		prev = { momz = 0 },
		-- controls
		ctrl = { jmp = 0, spn = 0, up = 0, ca1 = 0, ca2 = 0, ca3 = 0 },
		mull_button = 'spn',
		-- mulligan points
		mull_pts = {},
		save_pts = {},
		--stats
		shotcount = 0,
		mullcount = 0,
		--collision check
		collided = nil
	}
end


-- resetting state to be used on death or level change
reset_state = function(snlf, leave_mulls)
	boss_level = false
	snlf.prev = { momz = 0 }
	snlf.hdrive = 0
	snlf.vdrive = 0
	update_state(snlf, STATE_WAITING)
	if not leave_mulls then
		snlf.mull_pts = {}
	end
end


-- Is this Snolf?
is_snolf = function(mo)
	if not mo or not mo.player or not mo.skin then
		return false
	end

	return mo.skin == "snolf"
end

-- Is this player Snolf or is Everybody's Snolf on?
is_snolfing = function(mo)
	if not mo or not mo.player or not mo.skin then
		return false
	end

	return is_snolf(mo) or options.everybodys_snolf
end

-- Is this player either of the above or are they playing as Kirby with the
-- Golf ability?
is_golfing = function(mo)
	if not mo or not mo.player or not mo.skin then
		return false
	end

	return is_snolfing(mo) or (mo.skin == "kirby" and kirby_snolf_ability
		and mo.player.kvars.secretability
		and mo.player.kvars.ability == kirby_snolf_ability)
end


is_anyone_snolf = function()
	for p in players.iterate do
		if is_snolf(p.mo) then
			return true
		end
	end
	return false
end


is_anyone_snolfing = function()
	for p in players.iterate do
		if is_snolfing(p.mo) then
			return true
		end
	end
	return false
end


reversed_gravity = function(mo)
	return P_GetMobjGravity(mo) > 0
end


is_golf_setup = function(mo)
	return is_golfing(mo) and mo.player.snolf
end


at_rest = function(snlf)
	-- player is on the ground and not on a waterslide and not moving
	local momx = snlf.p.mo.momx - snlf.p.cmomx
	local momy = snlf.p.mo.momy - snlf.p.cmomy
	return P_IsObjectOnGround(snlf.p.mo) and snlf.p.pflags & PF_SLIDING == 0 and
		momx == 0 and momy == 0
end


take_a_mulligan = function(snlf, pts, dont_play_sound)
	local lm = pts[#pts] -- last mulligan point
	local mo = snlf.p.mo
	-- if we're still at the last mulligan point remove it and go back one
	if lm and same_position(lm, mo) and lm.momx == nil then
		table.remove(pts, #pts)
		lm = pts[#pts]
	end
	if lm then
		if not dont_play_sound then
			S_StartSound(mo, sfx_mixup)
		end

		P_TeleportMove(mo, lm.x, lm.y, lm.z)

		local momx, momy, momz = lm.momx or 0, lm.momy or 0, lm.momz or 0
		mo.momx = momx
		mo.momy = momy
		P_SetObjectMomZ(mo, momz)

		if lm.rings ~= nil then snlf.p.rings = lm.rings end
		if lm.state ~= nil then snlf.state = lm.state end
		if lm.hdrive ~= nil then snlf.hdrive = lm.hdrive end
		if lm.vdrive ~= nil then snlf.vdrive = lm.vdrive end
		if lm.chargegoingback ~= nil then snlf.chargegoingback = lm.chargegoingback end
		if lm.flags ~= nil then mo.flags = lm.flags end
		if lm.flags2 ~= nil then mo.flags2 = lm.flags2 end
		if lm.eflags ~= nil then mo.eflags = lm.eflags end
		if lm.flags ~= nil then snlf.p.pflags = lm.flags end

		if snlf.p.pflags & PF_FINISHED == 0 then
			snlf.mullcount = $1 + 1
		end
		override_controls(snlf)
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
	-- air snolf option
	if options.snolf_air_shot then
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
	if options.snolf_ground_control and snlf.state == STATE_WAITING then
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


option_toggle = function(option_name, arg, player)
	local current_bool = options[option_name]
	if arg == nil then
		options[option_name] = not $1
	elseif arg == "0" or arg == "off" or arg == "false" then
		options[option_name] = false
	elseif arg == "1" or arg == "on" or arg == "true" then
		options[option_name] = true
	else
		CONS_Printf(player, option_name.." should be called with either 'on', 'off', or no argument")
		return
	end
	print2(option_name.." has been "..(options[option_name] and "enabled" or "disabled")..".")
end


snolfify_name = function(orig_name)
	orig_name = orig_name:lower()

	-- bafflingly the game uses a control character in character names
	local sep = string.char(30)

	-- hardcoding some names for certain characters, including from other mods
	local name_replacement = {
		sonic = "Snolf",
		knuckles = "Knolf",
		tails = "Tolf"
	}

	for k, v in pairs(name_replacement) do
		if orig_name:find(k) ~= nil then
			return orig_name:gsub(k, v)
		end
	end

	local name_lookup = {
		amy = "Amy Rolf",
		metal = "M"..sep.."Snolf",
		robotnik = "Robotnolf",
		shadow = "Shdolf",
		silver = "Slolf",
		rouge = "Roulfe",
		gamma = "102-Golf",
		dickkickem = "Dolf Snolfem",
		steve = "Stove"}
	name_lookup["k"..sep.."t"..sep.."e"] = "Knolf"
	name_lookup["amy"..sep.."r"] = "Amy Rolf"
	name_lookup["m"..sep.."k"] = "M"..sep.."Knolf"
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


on_hit_boss = function(boss, pmo)
	if options.snolf_shot_on_hit_boss and pmo.player and pmo.player.snolf
	and is_snolfing(pmo) and pmo.player.snolf.state == STATE_WAITING then
		update_state(pmo.player.snolf, STATE_READY)
	end
end


-- Predict the trajectory of the currently charging shot
draw_trajectory = function(snlf)
	local h = sinusoidal_scale(snlf.hdrive, H_METER_LENGTH)
	local v = sinusoidal_scale(snlf.vdrive, V_METER_LENGTH)
	local mo = snlf.p.mo
	local x, y, z = mo.x, mo.y, mo.z -- current position
	local mx = FixedMul(h*FRACUNIT, cos(mo.angle)) -- force we will take off with
	local my = FixedMul(h*FRACUNIT, sin(mo.angle))
	local mz = v*FRACUNIT

	local slope = mo.standingslope
	if slope then
		local hcomp = FixedMul(mz, sin(slope.zangle))
		mz = FixedMul($1, cos(slope.zangle))
		mx = $1 - FixedMul(hcomp,cos(slope.xydirection))
		my = $1 - FixedMul(hcomp,sin(slope.xydirection))
	end

	-- The full x and y force will only be applied once
	x = $1 + mx
	y = $1 + my

	-- On the first frame friction will be applied to the player's momentum
	-- Thereafter the player will airborne where there is no friction
	mx = FixedMul($1, mo.friction)
	my = FixedMul($1, mo.friction)

	-- Hacky but this makes the path turn out correct
	-- I think perhaps gravity is not applied on the first frame (on the ground)
	-- sot his counteracts it?
	local g = P_GetMobjGravity(mo)
	local grev = reversed_gravity(mo)

	local dummy = P_SpawnMobj(x, y, z, MT_PLAYER)
	if grev then dummy.flags2 = $1 | MF2_OBJECTFLIP end
	if grev then mz = -$1 end
	mz = $1 - g

	local blocked = false
	-- Draw a shot trajectory
	local i = 0
	local prev_floorz = mo.floorz + 1
	local prev_ceilingz = mo.ceilingz - 1
	while not blocked and i < 200 do
		g = P_GetMobjGravity(dummy)

		-- according to the wiki gravity is applied twice if momz == 0
		if mz == 0 then
			mz = $1 + g
		end

		-- apply gravity
		mz = $1 + g

		dummy.z = $1 + mz

		local hblocked = not P_TryMove(dummy, x+mx, y+my, true)
		local fblocked = dummy.z <= prev_floorz
		local cblocked = mo.height + dummy.z >= prev_ceilingz
		blocked = hblocked or fblocked or cblocked

		x = $1 + mx
		y = $1 + my
		z = $1 + mz

		-- spawn a trail
		local dot = P_SpawnMobj(x, y, z,  MT_CYBRAKDEMON_TARGET_DOT)

		i = $1+1
		prev_ceilingz = dummy.ceilingz
		prev_floorz = dummy.floorz
	end
	if blocked then
		local reticule = P_SpawnMobj(dummy.x, dummy.y, dummy.z,  MT_CYBRAKDEMON_TARGET_DOT)
		reticule.sprite = SPR_TARG
		reticule.rollangle = leveltime*ANG1*3
	end
	dummy.type = MT_NULL
	P_KillMobj(dummy)
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
	local skin = skins[mo.skin]
	local name = string.lower(skin.realname)
	if skin.flags & SF_MACHINE > 0 or string.find(name,'milne') or
		string.find(name,'eggman') or string.find(name,'robotnik') then
		mass = $1*2
	end

	--or if it it's Tails Doll (or anything else named doll) reduce the weight
	if string.find(name, 'doll') ~= nil then
		mass = $1/2
	end

	return mass
end


shot_charge = function(snlf, vertical)
	local increment = get_charge_increment(snlf)
	if snlf.chargegoingback then
		increment = $1 * -1
	end
	snlf.p.pflags = $1 | PF_STARTDASH | PF_SPINNING -- force spindash state

	local charge = vertical and snlf.vdrive or snlf.hdrive
	local limit = vertical and V_METER_LENGTH or H_METER_LENGTH
	if charge >= limit then
		snlf.chargegoingback = true
	elseif charge <= 0 then
		if vertical then
			snlf.vdrive = 0
		else
			snlf.hdrive = 0
		end
		snlf.chargegoingback = false
	end
	if vertical then
		snlf.vdrive = $1 + increment
	else
		snlf.hdrive = $1 + increment
	end

	if options.snolf_shot_guide then
		draw_trajectory(snlf)
	end
end


update_state = function(snolf, state)
	snolf.state = state
	snolf.statetimer = 0
end


update_hud = function()
	if options.snolf_hud_mode > 0 then
		hud.disable("lives")
	else
		hud.enable("lives")
	end
end



-------------------
-- HUD functions --
-------------------
-- shot meter
hud.add( function(v, player, camera)
	if not is_golf_setup(player.mo) then return end
	local snlf = player.snolf
	local state = snlf.state
	if state != STATE_CHARGE1 and state != STATE_CHARGE2 then return end

	local meter = v.getSpritePatch(SPR_SFMR)  -- shot meter sprite
	local harrow = v.getSpritePatch(SPR_SFAH, 0, 4) -- shot meter arrow sprite 1
	local varrow = v.getSpritePatch(SPR_SFAV, 0, 5) -- shot meter arrow sprite 2

	local hpos = sinusoidal_scale(snlf.hdrive, H_METER_LENGTH)
	local vpos = sinusoidal_scale(snlf.vdrive, V_METER_LENGTH)

	if hpos < 1 then hpos = 1 end
	if vpos < 1 then vpos = 1 end

	v.draw(158, 103, meter)
	if state == STATE_CHARGE2 or not snlf.verticalfirst then
		v.draw(160+hpos, 151, harrow)
	end
	if state == STATE_CHARGE2 or snlf.verticalfirst then
		v.draw(159, 150-vpos, varrow)
	end
end, "game")


-- shots count
hud.add( function(v, player, camera)
	if not is_golf_setup(player.mo) then return end

	local hud_shots = v.getSpritePatch(SPR_SFST) -- SHOTS HUD element
	local shotcount = player.snolf.shotcount + player.snolf.mullcount

	if player.pflags & PF_FINISHED == 0 or player.exiting > 0 then
		v.draw(16, 58, hud_shots, V_HUDTRANS|V_SNAPTOLEFT|V_SNAPTOTOP)
		v.drawNum(96, 58, shotcount, V_HUDTRANS|V_SNAPTOLEFT|V_SNAPTOTOP)
	end
end, "game")


-- tip for if you're stuck unable to take a shot
hud.add( function(v, player, camera)
	if not is_golf_setup(player.mo) or not is_snolfing(player.mo)
	or player.snolf.state ~= STATE_WAITING or not player.snolf.mull_button
	or player.snolf.statetimer < TICRATE*10 then
		return
	end

	local bname = button_names[player.snolf.mull_button]
	local hint = "Hold "..bname.." to retake shot"
	local colourflag = (player.snolf.statetimer/TICRATE)%2 == 0 and V_YELLOWMAP or V_REDMAP
	v.drawString(16, 166 , hint, colourflag|V_HUDTRANS|V_SNAPTOLEFT|V_SNAPTOBOTTOM, "thin")
end, "game")


-- everybody's snolf life icon
hud.add ( function(v, player, camera)
	if options.snolf_hud_mode == 1 and player.mo and player.mo.skin then
		local mo = player.mo

		local life_x = v.getSpritePatch(SPR_SFHX)
		v.draw(38, 186	, life_x, V_HUDTRANS|V_SNAPTOLEFT|V_SNAPTOBOTTOM)

		local life_icon_box = v.getSpritePatch(SPR_LVBX)
		local life_icon = v.getSprite2Patch(mo.skin, SPR2_XTRA, player.powers[pw_super] > 0)
		v.drawScaled(16*FRACUNIT, 176*FRACUNIT, FRACUNIT/2, life_icon_box,
			V_HUDTRANS|V_SNAPTOLEFT|V_SNAPTOBOTTOM)
		v.drawScaled(16*FRACUNIT, 176*FRACUNIT, FRACUNIT/2, life_icon,
			V_HUDTRANS|V_SNAPTOLEFT|V_SNAPTOBOTTOM,
			v.getColormap(mo.skin, mo.color))

		if is_snolfing(mo) and options.snolf_inf_lives then
			local infinity = v.getSpritePatch(SPR_INFL)
			v.draw(63, 185, infinity, V_HUDTRANS|V_SNAPTOLEFT|V_SNAPTOBOTTOM)
		else
			v.drawString(74, 184, player.lives, V_HUDTRANS|V_SNAPTOLEFT|V_SNAPTOBOTTOM, "right" )
		end

		local hudname = skins[mo.skin].hudname
		if is_snolfing(mo) and options.everybodys_snolf then
			hudname = snolfify_name(hudname)
		end

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
	for boss in pairs(bosses_health) do
		if not boss or not boss.valid then
			bosses_health[boss] = nil
		end
	end

	for player in players.iterate do

		-- don't do anything if we're not golfing
		if not is_golfing(player.mo) then continue end

		if player.snolf == nil then
			snolf_setup(player)
		end

		-- set some local variables as shortcuts
		local p, mo, snlf = player, player.mo, player.snolf

		if p.playerstate == PST_DEAD then continue end

		-- check controls
		snlf.ctrl.jmp = p.cmd.buttons & BT_JUMP and $1+1 or 0
		snlf.ctrl.spn = p.cmd.buttons & BT_SPIN and $1+1 or 0
		snlf.ctrl.up  = p.cmd.forwardmove >  20 and $1+1 or 0
		snlf.ctrl.ca1 = p.cmd.buttons & BT_CUSTOM1 and $1+1 or 0
		snlf.ctrl.ca2 = p.cmd.buttons & BT_CUSTOM2 and $1+1 or 0
		snlf.ctrl.ca3 = p.cmd.buttons & BT_CUSTOM3 and $1+1 or 0

		-- skim across water
		if mo.momz < 0 and p.speed > SKIM_THRESHOLD and mo.eflags & MFE_TOUCHWATER > 0 and
		R_PointToAngle2(0, 0, p.speed, -mo.momz) < SKIM_ANLGE then
			mo.momx = FixedMul($1, SKIM_FACTOR)
			mo.momy = FixedMul($1, SKIM_FACTOR)
			P_SetObjectMomZ(mo, -mo.momz)
			S_StartSound(mo, sfx_splish)
			if boss_level and options.snolf_shot_on_touch_ground_when_in_boss
			and snlf.state == STATE_WAITING and is_snolfing(mo) then
				update_state(snlf, STATE_READY)
			end
		end

		-- check if we landed this turn
		if mo.eflags & MFE_JUSTHITFLOOR > 0
		and p.mo.rollangle <= ANG60 and p.mo.rollangle >= ANG350 - ANG30 - ANG20 then --allow X Momentum faceplants
			--makes bosses easier
			if boss_level and options.snolf_shot_on_touch_ground_when_in_boss
			and snlf.state == STATE_WAITING and is_snolfing(mo) then
				update_state(snlf, STATE_READY)
			end

			-- if going fast enough when Snolf hits the ground, bounce
			if abs(snlf.prev.momz) > BOUNCE_LIMIT and p.playerstate ~= PST_DEAD
			and mo.state ~= S_PLAY_BOUNCE and mo.state ~= S_PLAY_BOUNCE_LANDING then
				P_SetObjectMomZ(mo, FixedMul(snlf.prev.momz, BOUNCE_FACTOR) * (reversed_gravity(mo) and 1 or -1))
				snlf.p.pflags = $1 | PF_JUMPED | PF_THOKKED | PF_SHIELDABILITY
				-- move slightly off the ground immediately so snolf doesn't
				-- count as being classed as on the ground for the frame
				-- otherwise they might be able to do a jump input when they shouldn't
				P_TeleportMove(mo, mo.x, mo.y, mo.z + (reversed_gravity(mo) and -1 or 1))
			-- otherwise land
			else
				p.pflags = $1 | PF_SPINNING -- force spinning flag
				override_controls(snlf)
			end
		end

		-- try to set a mulligan point
		if at_rest(snlf) and not p.onconveyor then
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
				update_state(snlf, STATE_READY)
				override_controls(snlf)
			end
		-- ready to start taking a shot
		elseif snlf.state == STATE_READY then
			-- jump is pressed
			if snlf.ctrl.jmp == 1 then
				snlf.hdrive = 1
				snlf.vdrive = 1
				S_StartSoundAtVolume(mo, sfx_spndsh, 64)
				snlf.chargegoingback = false
				update_state(snlf, STATE_CHARGE1)
				snlf.verticalfirst = snlf.ctrl.up > 0
			end
		-- choosing horizontal force
		elseif snlf.state == STATE_CHARGE1 then
			-- jump is pressed
			if snlf.ctrl.jmp == 1 then
				S_StartSoundAtVolume(mo, sfx_spndsh, 100)
				snlf.chargegoingback = false
				update_state(snlf, STATE_CHARGE2)
			else
				shot_charge(snlf, snlf.verticalfirst)
			end
		-- choosing vertical force
		elseif snlf.state == STATE_CHARGE2 then
			-- jump is pressed
			if snlf.ctrl.jmp == 1 then
				-- shoot
				S_StartSound(mo, sfx_zoom)
				local h = sinusoidal_scale(snlf.hdrive, H_METER_LENGTH)
				local v = sinusoidal_scale(snlf.vdrive, V_METER_LENGTH)
				P_InstaThrust(snlf.p.mo, snlf.p.mo.angle, h*FRACUNIT)
				P_SetObjectMomZ(snlf.p.mo, v*FRACUNIT)

				-- change some player state
				snlf.p.pflags = $1 | PF_JUMPED
				if p.pflags & PF_FINISHED == 0 then
					snlf.shotcount = $1 + 1
				end
				mo.state = S_PLAY_ROLL

				update_state(snlf, STATE_WAITING)
			else
				shot_charge(snlf, not snlf.verticalfirst)
			end
		end


		-- enable jumping while on a water slide
		if p.pflags & PF_SLIDING ~= 0 and p.jumpfactor == 0 then
			p.jumpfactor = FRACUNIT
		elseif P_IsObjectOnGround(mo) then
			-- I don't like forcing stat changes every frame but other mods can
			-- also mess with these values so we need to be defensive about it
			-- to ensure Snolf works correctly with them
			override_controls(snlf)
		elseif not P_IsObjectOnGround(mo) then
			-- Give back jump when in the air. It will be taken away again on
			-- landing. This is done so that players can jump off objects like
			-- the rollout rocks in Red Volcano Zone
			p.jumpfactor = skins[mo.skin].jumpfactor
		end


		-- eat jump inputs entirely so other characters can't use jump abilties
		-- while taking a shot when using Everybody's Snolf
		if snlf.state != STATE_WAITING or snlf.statetimer < TICRATE/5 then
			p.cmd.buttons = $1 & (!BT_JUMP)
		end

		-- store certain state attributes so we can check for changes next tick
		snlf.prev.momz = player.mo.momz

		-- state timer
		snlf.statetimer = $1 + 1


		-- No Kirby zone!
		-- Don't apply everything below here to Kirby with the golf ability
		if not is_snolfing(mo) then continue end

		-- take a mulligan
		if snlf.ctrl[snlf.mull_button] == TICKS_FOR_MULLIGAN then
			take_a_mulligan(snlf, snlf.mull_pts)
		end

		-- save and load player state manually
		if options.snolf_save_states then
			-- save player state
			if snlf.ctrl.ca1 == 1 then
				if #snlf.save_pts > 9 then
					table.remove(snlf.save_pts, 1)
				end
				local state = {
					x = mo.x,
					y = mo.y,
					z = mo.z,
					momx = mo.momx,
					momy = mo.momy,
					momz = mo.momz,
					rings = p.rings,
					state = snlf.state,
					hdrive = snlf.hdrive,
					vdrive = snlf.vdrive,
					chargegoingback = snlf.chargegoingback,
					flags = mo.flags,
					flags2 = mo.flags2,
					eflags = mo.eflags,
					pflags = p.pflags
				}
				table.insert(snlf.save_pts, state)
				S_StartSound(mo, sfx_pop, p)
				CONS_Printf(p, "player state saved")
			end

			-- load player state
			if snlf.ctrl.ca2 == 1 and #snlf.save_pts > 0 then
				take_a_mulligan(snlf, snlf.save_pts)
				S_StartSound(mo, sfx_mixup)
				CONS_Printf(p, "player state loaded")
			end

			-- unload save state
			if snlf.ctrl.ca3 == 1 and #snlf.save_pts > 1 then
				table.remove(snlf.save_pts, #snlf.save_pts)
				S_StartSound(mo, sfx_skid)
				CONS_Printf(p, "undid save state")
			end
		end

		-- infinite rings option
		if options.snolf_inf_rings then
			p.xtralife = 99
			p.rings = 999
		end

		-- no drowning option
		if options.snolf_inf_air then
			if p.powers[pw_underwater] > 0 then
				p.powers[pw_underwater] = WATER_AIR_TIMER
				P_RestoreMusic(p)
			end
			if p.powers[pw_spacetime] > 0 then
				p.powers[pw_spacetime] = SPACE_AIR_TIMER
			end
		end
	end
end)


addHook("ThinkFrame", function()
	local snolf_players = {}
	for play1 in players.iterate do
		if not is_golf_setup(play1.mo) then continue end
		for play2 in players.iterate do
			if play1 == play2 then continue end
			if not is_golf_setup(play2.mo) then continue end
			-- If a player is Kirby and only just copied Snolf make them immune to
			-- collisions for a second. This prevents Snolf from getting stuck in
			-- Kirby while being ejected
			if play1.kvars and kirby_snolf_ability
			and play1.kvars.ability == kirby_snolf_ability
			and play1.kvars.ablvar1 < TICRATE then
				continue
			end
			if play2.kvars and kirby_snolf_ability
			and play2.kvars.ability == kirby_snolf_ability
			and play2.kvars.ablvar1 < TICRATE then
				continue
			end
			if (not at_rest(play1.snolf) or not at_rest(play2.snolf)) and
				not play1.snolf.collided and not play2.snolf.collided and
				are_touching(play1, play2) then

				play1.snolf.collided = play2
				play2.snolf.collided = play1

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
		local mo = player.mo
		if not is_golf_setup(player.mo) then continue end

		-- force rolling animation
		if maptol & TOL_NIGHTS == 0 -- if we're not in NiGHTS mode
			and player.mo.sprite ~= SPR_NULL -- if our sprite isn't null
			and (player.playerstate ~= PST_DEAD or player.mo.skin == "snolf") then -- if we're not dead or Snolf Classic

			local state = mo.state
			if is_snolf(mo) and state ~= S_PLAY_ROLL and state ~= S_PLAY_SPRING and state < S_NAMECHECK then
				mo.state = S_PLAY_ROLL
			elseif is_golfing(mo) and P_IsObjectOnGround(mo) then
				-- don't force rolling animation if the player is in a mod-added state
				-- only do it for default ones like standing, running, etc.
				if state ~= S_PLAY_ROLL and state < S_NAMECHECK then
					mo.state = S_PLAY_ROLL
				end
			elseif is_golfing(mo) and state == S_PLAY_FALL then
				-- if in the air only force the rolling animation if the player is currently in the falling animation
				mo.state = S_PLAY_ROLL
			end
		end

		if player.snolf.collided then
			if not are_touching(player, player.snolf.collided) then
				player.snolf.collided.snolf.collided = nil
				player.snolf.collided = nil
			end
		end
	end
end)


-- Hook to override default collision and make Snolf bounce off walls
addHook("MobjMoveBlocked", function(mo)
	if not is_golf_setup(mo) then return false end

	local slope = mo.standingslope
	if slope and slope.valid and slope.zangle >= ANGLE_45 then
		return false
	end

	if mo.player.pflags & PF_SLIDING then
		return false
	end

	--let player take a shot if they bounce off walls while fighting a boss
	if boss_level and options.snolf_shot_on_touch_wall_when_in_boss
	and is_snolfing(mo) then
		local player = mo.player
		if is_golf_setup(mo) and player.snolf.state == STATE_WAITING then
			update_state(player.snolf, STATE_READY)
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
	if not is_golf_setup(mo) then return false end
	reset_state(mo.player.snolf, options.snolf_death_mulligan)

	-- infinite lives option
	if options.snolf_inf_lives and is_snolfing(mo) then
		mo.player.lives = $1 + 1
	end
end, MT_PLAYER)


-- reset state when a new map is loaded
addHook("MapLoad", function(mapnumber)
	for player in players.iterate do
		if not is_golf_setup(player.mo) then continue end
		reset_state(player.snolf)
		if mapnumber ~= oldmap then
			player.snolf.save_pts = {}
		end
	end
end)


--play announcement when starting metal snolf race
addHook("MapLoad", function(mapnumber)
	--only play when loading map for the first time
	if mapnumber == 25 and mapnumber ~= oldmap and is_anyone_snolf() then
		for player in players.iterate do
			if player.mo then
				S_StartSound(player.mo, sfx_msnolf, player)
			end
		end
	end
end)


-- option to return to last spot on death
addHook("PlayerSpawn", function(player)
	if is_golf_setup(player.mo) and options.snolf_death_mulligan
	and is_snolfing(player.mo) then
		take_a_mulligan(player.snolf, player.snolf.mull_pts, true)
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
	if not target or not target.player or not options.snolf_shot_on_hit_by_boss then
		return
	end

	local player = target.player
	if ( source ~= nil and (source.type >= MT_BOSSEXPLODE and source.type <= MT_MSGATHER) )
		or (  inflictor ~= nil and ( inflictor.type >= MT_BOSSEXPLODE and inflictor.type <= MT_MSGATHER ) ) then

		if is_golf_setup(player.mo) and is_snolfing(player.mo) and player.snolf.state == STATE_WAITING then
			update_state(player.snolf, STATE_READY)
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
		if is_anyone_snolfing() and options.snolf_rings_on_hit_boss then
			S_StartSound(boss, sfx_s3kb9)
			for i=0, 5 do
				local ring = P_SpawnMobjFromMobj(boss, 0,0,0, MT_FLINGRING)
				ring.fuse = 8*TICRATE
				local ringmom = boss.type == MT_EGGMOBILE4 and 32*FRACUNIT or 4*FRACUNIT
				ring.momx = FixedMul(ringmom, cos(ANG60*i + boss.angle))
				ring.momy = FixedMul(ringmom, sin(ANG60*i + boss.angle))
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
	if options.snolf_fire_shield and inflictor and
		inflictor.type ==  MT_FLAMEJETFLAMEB and is_snolfing(player) then
		return true
	end
end, MT_PLAYER)


--force metal sonic to be metal snolf
--find metal snolf in the race
addHook("MobjThinker", function(metal_sonic_race)
	metal_snolf_race = metal_sonic_race
end, MT_METALSONIC_RACE)

--find metal snolf in the battle
addHook("MobjThinker", function(metal_sonic_battle)
	metal_snolf_battle = metal_sonic_battle
end, MT_METALSONIC_BATTLE)

--force metal snolf into rolling animation
addHook("PostThinkFrame", function()
	if metal_snolf_race ~= nil and metal_snolf_race.valid and is_anyone_snolf() then
		-- for the race let finger wag play first
		if leveltime > TICRATE*3 - TICRATE/2  then
			metal_snolf_race.state = S_PLAY_ROLL --force roll state
		end
	end

	if metal_snolf_battle ~= nil and metal_snolf_battle.valid and is_anyone_snolf() then
		metal_snolf_battle.sprite = SPR_MSNF
	end
end)


--record what level we're moving from when changing levels
addHook("MapChange", function(mapnum)
	oldmap = gamemap
end)


--sync game state when joining game
addHook("NetVars", function(network)
    options = network($)
	bosses_health = network($)
	boss_level = network($)
	metal_snolf_race = network($)
	metal_snolf_battle = network($)
	oldmap = network($)
end)


addHook("PlayerJoin", function(playernum)
	update_hud()
end)



--------------
-- Commands --
--------------

COM_AddCommand("everybodys_snolf", function(player, arg)
	option_toggle("everybodys_snolf", arg, player)
	-- restore character stats
	for player in players.iterate do
		if player.mo then
			if is_snolfing(player.mo) then
				if not player.snolf then
					snolf_setup(player)
				end
				if P_IsObjectOnGround(player.mo) then
					override_controls(player.snolf)
				end
			else
				local skin = skins[player.mo.skin]
				player.jumpfactor = skin.jumpfactor
				player.accelstart = skin.accelstart
				player.acceleration = skin.acceleration
				player.charability2 = skin.ability2
			end
		end
	end

	update_hud()
end, COM_ADMIN)


COM_AddCommand("snolf_hud_mode", function(player, arg)
	if arg == nil then
		options.snolf_hud_mode = $1 == 0 and 1 or 0
	elseif arg == "0" or arg == "off" or arg == "false" then
		options.snolf_hud_mode = 0
	elseif arg == "1" or arg == "on" or arg == "true" then
		options.snolf_hud_mode = 1
	elseif arg == "2" then
		options.snolf_hud_mode = 2
	else
		CONS_Printf(player, "snolf_hud_mode should be called with either 0, 1, 2 or no argument")
	end
	print2("snolf_hud_mode has been "..(options.snolf_hud_mode > 0 and "enabled" or "disabled")..".")

	update_hud()
end, COM_ADMIN)


COM_AddCommand("snolf_mulligan_button", function(player, arg)
	if arg then arg = arg:lower() end

	local choices = {
		spin = "spn",
		spn = "spn",
		jump = "jmp",
		jmp = "jmp",
		ca1 = "ca1",
		ca2 = "ca2",
		ca3 = "ca3",
	}
	choices["1"] = "ca1"
	choices["2"] = "ca2"
	choices["3"] = "ca3"

	local snlf = player.snolf
	if choices[arg] then
		snlf.mull_button = choices[arg]
		CONS_Printf(player, "Mulligan set to "..button_names[snlf.mull_button])
	elseif arg == "off" or arg == "0" then
		snlf.mull_button = nil
		CONS_Printf(player, "Mulligan is no longer bound to any button")
	else
		CONS_Printf(player, "snolf_mulligan_button should be called with either 'spin', 'jump', 'ca1', 'ca2', 'ca3' or 'off'")
	end
end)


COM_AddCommand("snolf_inf_rings", function(player, arg)
	option_toggle("snolf_inf_rings", arg, player)
end, COM_ADMIN)

COM_AddCommand("snolf_inf_lives", function(player, arg)
	option_toggle("snolf_inf_lives", arg, player)
	update_hud()
end, COM_ADMIN)

COM_AddCommand("snolf_inf_air", function(player, arg)
	option_toggle("snolf_inf_air", arg, player)
end, COM_ADMIN)

COM_AddCommand("snolf_death_mulligan", function(player, arg)
	option_toggle("snolf_death_mulligan", arg, player)
end, COM_ADMIN)

COM_AddCommand("snolf_ground_control", function(player, arg)
	option_toggle("snolf_ground_control", arg, player)
end, COM_ADMIN)

COM_AddCommand("snolf_air_shot", function(player, arg)
	option_toggle("snolf_air_shot", arg, player)
end, COM_ADMIN)

COM_AddCommand("snolf_shot_guide", function(player, arg)
	option_toggle("snolf_shot_guide", arg, player)
end, COM_ADMIN)

COM_AddCommand("snolf_fire_shield", function(player, arg)
	option_toggle("snolf_fire_shield", arg, player)
end, COM_ADMIN)

COM_AddCommand("snolf_save_states", function(player, arg)
	option_toggle("snolf_save_states", arg, player)
end, COM_ADMIN)

COM_AddCommand("snolf_shot_on_hit_boss", function(player, arg)
	option_toggle("snolf_shot_on_hit_boss", arg, player)
end, COM_ADMIN)

COM_AddCommand("snolf_shot_on_hit_by_boss", function(player, arg)
	option_toggle("snolf_shot_on_hit_by_boss", arg, player)
end, COM_ADMIN)

COM_AddCommand("snolf_rings_on_hit_boss", function(player, arg)
	option_toggle("snolf_rings_on_hit_boss", arg, player)
end, COM_ADMIN)

COM_AddCommand("snolf_shot_on_touch_ground_when_in_boss", function(player, arg)
	option_toggle("snolf_shot_on_touch_ground_when_in_boss", arg, player)
end, COM_ADMIN)

COM_AddCommand("snolf_shot_on_touch_wall_when_in_boss", function(player, arg)
	option_toggle("snolf_shot_on_touch_wall_when_in_boss", arg, player)
end, COM_ADMIN)

update_hud()
