freeslot("SPR_SFST", "SPR_SFAH", "SPR_SFAV", "SPR_SFMR")

local h_meter_length = 50
local v_meter_length = 50


-- declaring these functions because we're about to make some circular
-- references and we need these to be declared to avoid parsing errors
local shot_ready, horizontal_charge, vertical_charge, waiting_to_stop

-- sit ready until the player presses jump
shot_ready = function(snolf_table)
	local snlf = snolf_table
	repeat
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
		if snlf.hdrive >= h_meter_length then
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
		if snlf.vdrive >= v_meter_length then
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


local is_snolf = function(mo)
	return mo and mo.skin == "snolf"
end


local at_rest = function(snlf)
	return P_IsObjectOnGround(snlf.mo) and snlf.p.speed == 0 and snlf.mo.momz == 0
end



-- draw the charge meter
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


-- store all snolf-relevant state info in player_t.snolf
local snolf_setup = function(player)
	player.snolf = {
		p = player,
		mo = player.mo,
		charging = false,
		ctrl = { jmp = 0 },
		at_rest = at_rest,
		hdrive = 0,
		vdrive = 0
	}

	player.snolf.routine = coroutine.create(shot_ready)
end




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


		-- run the player's current coroutine
		if snlf.routine and coroutine.status(snlf.routine) ~= "dead" then
			coroutine.resume(snlf.routine, snlf)
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

