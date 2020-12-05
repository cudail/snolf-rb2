freeslot("SPR_SFST", "SPR_SFAH", "SPR_SFAV", "SPR_SFMR")


-- declare functions in advance so they can reference each other
-- without causing parsing errors
local shot_ready, horizontal_charge, vertical_charge, waiting_to_stop
local is_snolf, at_rest, take_a_mulligan, same_position, snolf_setup

---------------
-- constants --
---------------
local H_METER_LENGTH = 50
local V_METER_LENGTH = 50
local TICKS_FOR_MULLIGAN = 35


---------------------------------
-- player behaviour coroutines --
---------------------------------
-- sit ready until the player presses jump
shot_ready = function(snolf_table)
	local snlf = snolf_table
	repeat

		-- if Snolf is at rest try to set a mulligan point
		if snlf:at_rest() then
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
		coroutine.yield()
	until snlf.ctrl.jmp == 1
	snlf.charging = true
	snlf.hdrive = -1
	snlf.vdrive = -1
	snlf.routine = coroutine.create(horizontal_charge, snlf)
end

-- setting horizontal shot force
horizontal_charge = function(snolf_table)
	local snlf = snolf_table
	local increment = 1
	repeat
		if snlf.hdrive >= H_METER_LENGTH then
			increment = -1
		elseif snlf.hdrive <= 0 then
			increment = 1
		end
		snlf.hdrive = $1 + increment
		coroutine.yield()
	until snlf.ctrl.jmp == 1
	snlf.routine = coroutine.create(vertical_charge, snlf)
end

-- setting vertical shot force
vertical_charge = function(snolf_table)
	local snlf = snolf_table
	local increment = 1
	repeat
		if snlf.vdrive >= V_METER_LENGTH then
			increment = -1
		elseif snlf.vdrive <= 0 then
			increment = 1
		end
		snlf.vdrive = $1 + increment
		coroutine.yield()
	until snlf.ctrl.jmp == 1
	P_InstaThrust(snlf.mo, snlf.mo.angle, snlf.hdrive*FRACUNIT)
	P_SetObjectMomZ(snlf.mo, snlf.vdrive*FRACUNIT)
	snlf.charging = false
	snlf.shotcount = $1 + 1
	snlf.routine = coroutine.create(waiting_to_stop, snlf)
end


-- wait until Snolf comes to a complete stop before they can take another shot
waiting_to_stop = function(snolf_table)
	local snlf = snolf_table
	repeat
		coroutine.yield()
	until snlf:at_rest()
	snlf.routine = coroutine.create(shot_ready, snlf)
end


---------------
-- functions --
---------------

-- store all snolf-relevant state info in player_t.snolf
snolf_setup = function(player)
	player.snolf = {
		-- SRB2 data structures
		p = player,
		mo = player.mo,
		-- Snolf shot state
		charging = false,
		hdrive = 0,
		vdrive = 0,
		-- controls
		ctrl = { jmp = 0, spn = 0 },
		-- mulligan points
		mull_pts = {},
		--stats
		shotcount = 0,
		mullcount = 0,
		--functions
		at_rest = at_rest,
		take_a_mulligan = take_a_mulligan
	}

	player.snolf.routine = coroutine.create(shot_ready)
end


is_snolf = function(mo)
	return mo and mo.skin == "snolf"
end


at_rest = function(snlf)
	return P_IsObjectOnGround(snlf.mo) and snlf.p.speed == 0 and snlf.mo.momz == 0
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

	v.draw(158, 103, meter)
	v.draw(160+player.snolf.hdrive, 151, harrow)
	if player.snolf.vdrive ~= -1 then
		v.draw(159, 150-player.snolf.vdrive, varrow)
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
		local p, pmo, snlf = player, player.mo, player.snolf


		-- check controls
		snlf.ctrl.jmp = p.cmd.buttons & BT_JUMP and $1+1 or 0
		snlf.ctrl.spn = p.cmd.buttons & BT_SPIN and $1+1 or 0

		-- run the player's current coroutine
		if snlf.routine and coroutine.status(snlf.routine) ~= "dead" then
			coroutine.resume(snlf.routine, snlf)
		end

		if snlf.ctrl.spn == TICKS_FOR_MULLIGAN then
			snlf:take_a_mulligan()
		end

	end
end)


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

