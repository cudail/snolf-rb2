freeslot("SPR_SFST", "SPR_SFAH", "SPR_SFAV", "SPR_SFMR")


-- declare functions in advance so they can reference each other
-- without causing parsing errors
local shot_ready, horizontal_charge, vertical_charge, waiting_to_stop, is_snolf,
	at_rest, take_a_mulligan, same_position, snolf_setup, reset_state,
	sinusoidal_scale, get_charge_increment, in_black_core, allow_air_snolf,
	cheat_toggle

local cheats = {
	everybodys_snolf = false,
	snolf_inf_rings = false,
	snolf_inf_lives = false,
	snolf_inf_air = false,
	snolf_death_mulligan = false,
	snolf_ground_control = false
}

---------------
-- constants --
---------------
local TICKS_FOR_MULLIGAN = 35 -- how long to hold down the spin button to take a mulligan
local BOUNCE_LIMIT = 10*FRACUNIT -- Snolf won't bounce if their vertical momentum is less than this
local BOUNCE_FACTOR = FRACUNIT/2 -- when Snolf bounces their momentum is multiplied by this factor

-- as it stands the max strength of a fully charged shot,
-- the charge meter period and the max displacement of the charge meter arrows
-- during the animation are all deterimned by these two constants, one each
-- for horizontal and vertical. ideally these should be six different constants
local H_METER_LENGTH = 50
local V_METER_LENGTH = 50


---------------------------------
-- player behaviour coroutines --
---------------------------------
-- sit ready until the player presses jump
shot_ready = function(snolf_table)
	local snlf = snolf_table

	snlf.p.jumpfactor = 0 -- disable jump
	repeat
		coroutine.yield()
	until snlf.ctrl.jmp == 1
	snlf.charging = true
	snlf.hdrive = -1
	snlf.vdrive = -1
	S_StartSoundAtVolume(pmo, sfx_spndsh, 64)
	snlf.routine = coroutine.create(horizontal_charge, snlf)
end

-- setting horizontal shot force
horizontal_charge = function(snolf_table)
	local snlf = snolf_table
	local increment = get_charge_increment(snlf)
	repeat
		snlf.p.pflags = $1 | PF_STARTDASH -- force spindash state
		if snlf.hdrive >= H_METER_LENGTH then
			increment = - get_charge_increment(snlf)
		elseif snlf.hdrive <= 0 then
			increment = get_charge_increment(snlf)
		end
		snlf.hdrive = $1 + increment
		coroutine.yield()
	until snlf.ctrl.jmp == 1
	S_StartSoundAtVolume(pmo, sfx_spndsh, 100)
	snlf.routine = coroutine.create(vertical_charge, snlf)
end

-- setting vertical shot force
vertical_charge = function(snolf_table)
	local snlf = snolf_table
	local increment = get_charge_increment(snlf)
	repeat
		snlf.p.pflags = $1 | PF_STARTDASH -- force spindash state
		if snlf.vdrive >= V_METER_LENGTH then
			increment = - get_charge_increment(snlf)
		elseif snlf.vdrive <= 0 then
			increment = get_charge_increment(snlf)
		end
		snlf.vdrive = $1 + increment
		coroutine.yield()
	until snlf.ctrl.jmp == 1

	-- shoot
	S_StartSound(pmo, sfx_zoom)
	local h = sinusoidal_scale(snlf.hdrive, H_METER_LENGTH)
	local v = sinusoidal_scale(snlf.vdrive, V_METER_LENGTH)
	P_InstaThrust(snlf.mo, snlf.mo.angle, h*FRACUNIT)
	P_SetObjectMomZ(snlf.mo, v*FRACUNIT)

	-- change some player state
	snlf.p.pflags = $1 | PF_JUMPED
	snlf.charging = false
	snlf.shotcount = $1 + 1
	snlf.routine = coroutine.create(waiting_to_stop, snlf)
end


-- wait until Snolf comes to a complete stop before they can take another shot
waiting_to_stop = function(snolf_table)
	local snlf = snolf_table

	-- enable jumping after taking a shot. this is to allow players to dismount
	-- level gimmicks like rolling boulders in Red Volcano Zone
	-- this is here rather than at the end of the vertical_charge function so
	-- that it happens the frame after Snolf has left the ground
	snlf.p.jumpfactor = FRACUNIT
	repeat
		coroutine.yield()
	until snlf:at_rest() or snlf:allow_air_snolf()

	snlf.routine = coroutine.create(shot_ready, snlf)

	-- try to set a mulligan point
	local mo, mulls = snlf.mo, snlf.mull_pts
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


---------------
-- functions --
---------------

-- store all snolf-relevant state info in player_t.snolf
snolf_setup = function(player)
	local snolf = {
		-- SRB2 data structures
		p = player,
		-- Snolf shot state
		charging = false,
		hdrive = 0,
		vdrive = 0,
		-- previous tick state
		prev = { inair = false, momz = 0 },
		-- controls
		ctrl = { jmp = 0, spn = 0 },
		-- mulligan points
		mull_pts = {},
		--stats
		shotcount = 0,
		mullcount = 0,
		--functions
		at_rest = at_rest,
		take_a_mulligan = take_a_mulligan,
		reset_state = reset_state,
		allow_air_snolf = allow_air_snolf,
		--coroutine
		routine = coroutine.create(waiting_to_stop)
	}

	setmetatable(snolf, {
		__index = function(snolf, key)
			-- make all properties of the parent player accessible
			return snolf.p[key]
		end
	})

	player.snolf = snolf
end


-- resetting state to be used on death or level change
reset_state = function(snlf)
	snlf.prev = { inair = false, momz = 0 }
	snlf.mull_pts = {}
	snlf.charging = false
	snlf.hdrive = 0
	snlf.vdrive = 0
	snlf.routine = coroutine.create(waiting_to_stop)
end


is_snolf = function(mo)
	return mo and mo.skin and (mo.skin == "snolf" or cheats.everybodys_snolf)
end


at_rest = function(snlf)
	-- player is on the ground and not on a waterslide and not moving
	return P_IsObjectOnGround(snlf.mo) and snlf.pflags & PF_SLIDING == 0 and
		snlf.speed == 0 and snlf.mo.momz == 0
end


take_a_mulligan = function(snlf)
	local lm = snlf.mull_pts[#snlf.mull_pts] -- last mulligan point
	local mo = snlf.mo
	-- if we're still at the last mulligan point remove it and go back one
	if lm and same_position(lm, mo) then
		table.remove(snlf.mull_pts, #snlf.mull_pts)
		lm = snlf.mull_pts[#snlf.mull_pts]
	end
	if lm then
		P_TeleportMove(mo, lm.x, lm.y, lm.z)
		P_InstaThrust(mo, 0, 0)
		P_SetObjectMomZ(mo, 0)
		S_StartSound(mo, sfx_mixup)
		snlf.mullcount = $1 + 1
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
	if snlf.powers[pw_super] > 0 then
		-- double charge rate for Super Snolf
		increment = $1 * 2
	end
	if snlf.powers[pw_sneakers] > 0 then
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
	-- Super Snolf
	if snlf.powers[pw_super] > 0 then
		return true
	-- if Snolf is in the vacuum of space
	elseif snlf.powers[pw_spacetime] > 0 then
		return true
	end
	-- for the last three bosses
	return in_black_core()
end


cheat_toggle = function(cheat_name, arg)
	local current_bool = cheats[cheat_name]
	if arg == nil then
		cheats[cheat_name] = not $1
	elseif arg == "0" then
		cheats[cheat_name] = false
	elseif arg == "1" then
		cheats[cheat_name] = true
	else
		CONS_Printf(player, cheat_name.." should be called with either 0, 1 or no argument")
		return
	end
	chatprint(cheat_name.." has been "..(cheats[cheat_name] and "enabled" or "disabled")..".")
end



-------------------
-- HUD functions --
-------------------
-- shot meter
hud.add( function(v, player, camera)
	if not is_snolf(player.mo) then return end
	if not player.snolf.charging then return end

	local meter = v.getSpritePatch(SPR_SFMR)  -- shot meter sprite
	local harrow = v.getSpritePatch(SPR_SFAH, 0, 4) -- shot meter arrow sprite 1
	local varrow = v.getSpritePatch(SPR_SFAV, 0, 5) -- shot meter arrow sprite 2

	local hpos = sinusoidal_scale(player.snolf.hdrive, H_METER_LENGTH)
	local vpos = sinusoidal_scale(player.snolf.vdrive, V_METER_LENGTH)

	v.draw(158, 103, meter)
	v.draw(160+hpos, 151, harrow)
	if player.snolf.vdrive ~= -1 then
		v.draw(159, 150-vpos, varrow)
	end
end, "game")


-- shots count
hud.add( function(v, player, camera)
	if not is_snolf(player.mo) then return end

	local hud_shots = v.getSpritePatch(SPR_SFST) -- SHOTS HUD element
	local shotcount = player.snolf.shotcount + player.snolf.mullcount

	if player.pflags & PF_FINISHED == 0 or player.exiting > 0 then
		v.draw(16, 58, hud_shots, V_HUDTRANS|V_SNAPTOLEFT|V_SNAPTOTOP)
		v.drawNum(96, 58, shotcount, V_HUDTRANS|V_SNAPTOLEFT|V_SNAPTOTOP)
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

		-- run the player's current coroutine
		local resumed, err = coroutine.resume(snlf.routine, snlf)
		if not resumed then
			snlf.routine = coroutine.create(waiting_to_stop)
		end

		if snlf.ctrl.spn == TICKS_FOR_MULLIGAN then
			snlf:take_a_mulligan()
		end

		-- check if we landed this turn
		if snlf.prev.inair and P_IsObjectOnGround(mo) then
			-- if going fast enough when Snolf hits the ground, bounce
			if abs(snlf.prev.momz) > BOUNCE_LIMIT then
				P_SetObjectMomZ(mo, - FixedMul(snlf.prev.momz, BOUNCE_FACTOR))
			-- otherwise land
			else
				p.pflags = $1 | PF_SPINNING -- force spinning flag
				p.jumpfactor = 0 -- disable jump
			end
		end

		-- enable jumping while on a water slide
		if p.pflags & PF_SLIDING ~= 0 and p.jumpfactor == 0 then
			p.jumpfactor = FRACUNIT
		end

		-- infinite rings cheat
		if cheats.snolf_inf_rings then
			p.xtralife = 99
			p.rings = 999
		end

		-- store certain state attributes so we can check for changes next tick
		snlf.prev.inair = not P_IsObjectOnGround(mo)
		snlf.prev.momz = mo.momz
	end
end)


addHook("PostThinkFrame", function()
	for player in players.iterate do
		if not is_snolf(player.mo) then continue end
		player.mo.state = S_PLAY_ROLL -- always force rolling animation
	end
end
)

-- Hook to override default collision and make Snolf bounce off walls
addHook("MobjMoveBlocked", function(mo)
	if not is_snolf(mo) then return false end

	-- P_BounceMove doesn't bounce the player if they are on the ground
	-- To get around this impart the tiniest possible vertical momentum the
	-- engine will allow so Snolf is technically in the air for a single frame
	if P_IsObjectOnGround(mo) then
		P_SetObjectMomZ(mo, 1)
	end
	P_BounceMove(mo)
	return true
end)


-- reset state on death
addHook("MobjDeath", function(mo)
	if not is_snolf(mo) then return false end
	mo.player.snolf:reset_state()

	-- infinite lives cheat
	if cheats.snolf_inf_lives then
		mo.player.lives = $1 + 1
	end
end)

-- reset state when a new map is loaded
addHook("MapLoad", function(mapnumber)
	for player in players.iterate do
		if not is_snolf(player.mo) then continue end
		player.snolf:reset_state()
	end
end)


--------------
-- Commands --
--------------

COM_AddCommand("everybodys_snolf", function(player, arg)
	cheat_toggle("everybodys_snolf", arg)

	-- re-enable jump for everyone who's not Snolf. this is hacky and replaces
	-- the character's original jump height with the default one. sorry
	for player in players.iterate do
		if not is_snolf(player.mo) then
			player.jumpfactor = FRACUNIT
		end
	end
end, COM_ADMIN)


COM_AddCommand("snolf_inf_rings", function(player, arg)
	cheat_toggle("snolf_inf_rings", arg)
end, COM_ADMIN)


COM_AddCommand("snolf_inf_lives", function(player, arg)
	cheat_toggle("snolf_inf_lives", arg)
end, COM_ADMIN)


COM_AddCommand("snolf_inf_air", function(player, arg)
	cheat_toggle("snolf_inf_air", arg)
end, COM_ADMIN)


COM_AddCommand("snolf_death_mulligan", function(player, arg)
	cheat_toggle("snolf_death_mulligan", arg)
end, COM_ADMIN)


COM_AddCommand("snolf_ground_control", function(player, arg)
	cheat_toggle("snolf_ground_control", arg)
end, COM_ADMIN)
