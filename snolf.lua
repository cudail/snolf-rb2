freeslot("SPR_SFST", "SPR_SFAH", "SPR_SFAV", "SPR_SFMR")


-- initialising these functions because we're about to make some circular
-- references and 
local shot_ready, horizontal_charge, vertical_charge

-- sit ready until the player presses jump
shot_ready = function(snolf_table)
	local snlf = snolf_table
	repeat
		coroutine.yield()
	until (snlf.ctrl.jmp == 1)
	snlf.routine = coroutine.create(horizontal_charge, snlf)
end

-- setting horizontal shot force
horizontal_charge = function(snolf_table)
	local snlf = snolf_table
	snlf.hdrive = -1
	repeat
 		snlf.hdrive = $1 + 1
		print(snlf.hdrive)
 		coroutine.yield()
	until(snlf.ctrl.jmp == 1)
 	snlf.routine = coroutine.create(vertical_charge, snlf)
end

-- setting vertical shot force
vertical_charge = function(snolf_table)
	local snlf = snolf_table
	snlf.vdrive = -1
	repeat
 		snlf.vdrive = $1 + 1
		print(snlf.vdrive)
 		coroutine.yield()
	until(snlf.ctrl.jmp == 1)
	P_InstaThrust(snlf.mo, snlf.mo.angle, snlf.hdrive*FRACUNIT)
 	P_SetObjectMomZ(snlf.mo, snlf.vdrive*FRACUNIT)
	snlf.routine = coroutine.create(shot_ready, snlf)
end


-- store all snolf-relevant state info in player_t.snolf
local snolf_setup = function(player)
	player.snolf = {
		p = player,
		mo = player.mo,
		state = SNLF_RDY,
		ctrl = { jmp = 0 },
		handle_jump = handle_jump,
		hdrive = 0,
		vdrive = 0
	}

	player.snolf.routine = coroutine.create(shot_ready)
end


addHook("PreThinkFrame", function()
	for player in players.iterate do

		-- don't do anything if we're not Snolf
		if player.mo.skin ~= "snolf" then continue end

		if player.snolf == nil then 
			snolf_setup(player)
		end

		-- set some local variables as shortcuts
		local p, pmo, snlf = player, player.mo, player.snolf


		-- check controls
		snlf.ctrl.jmp = p.cmd.buttons & BT_JUMP and $1+1 or 0


		-- run the player's current coroutine
		if snlf.routine and coroutine.status(snlf.routine) ~= "dead" then
			coroutine.resume(snlf.routine, snlf)
		end

	end
end)
