freeslot("SPR_SFAH", "SPR_SFAV", "SPR_SFMR")

hud.add(function(v, player, camera)
	-- Don't do anything if we're not Snolf
	if player.mo.skin == "snolf" then
		v.drawString(16, 164, "SHOTS", V_YELLOWMAP)
		v.drawString(64, 164, player.snolf.shots)

		if player.snolf.state == 1 or player.snolf.state == 2 then
			local meter = v.getSpritePatch(SPR_SFMR)  -- shot meter sprite
			local harrow = v.getSpritePatch(SPR_SFAH) -- shot meter arrow sprite 1
			local varrow = v.getSpritePatch(SPR_SFAV) -- shot meter arrow sprite 2

			local h_meter_length = 50 -- how many pixels wide the charge meter range is
			local v_meter_length = 50 -- how many pixels tall the charge meter range is

			local hpos = player.snolf.convert_angle(player.snolf.hdrive, h_meter_length)
			local vpos = player.snolf.convert_angle(player.snolf.vdrive, v_meter_length)

			v.drawScaled(
				FRACUNIT*158,
				FRACUNIT*103,
				FRACUNIT, meter)
			v.drawScaled(
				FRACUNIT*(160+hpos),
				FRACUNIT*150,
				FRACUNIT, harrow)
			if player.snolf.state == 2 then
				v.drawScaled(
					FRACUNIT*160,
					FRACUNIT*(150-vpos),
					FRACUNIT, varrow)
			end
		end
	end
end, "game")


addHook("PreThinkFrame", function()

	for player in players.iterate do
		-- Don't do anything if we're not Snolf
		if player.mo.skin ~= "snolf" then
			continue
		end

		-- Don't do anything for NiGHTS mode
		if maptol & TOL_NIGHTS > 1 then
			continue
		end

		if player.snolf == nil then
			player.snolf = { shots = 0, state = 0, spinheld = 0 }
			player.snolf.mull = {}
			player.snolf.convert_angle = function (angle, max_val)
				return sin(angle - ANGLE_90)*max_val/FRACUNIT/2 + max_val/2
			end
		end

		-- check if the jump button was just tapped
		if not (player.cmd.buttons & BT_JUMP) then
			player.snolf.jumptapready = true
			player.snolf.jumptapping = false
		elseif player.snolf.jumptapready then
			player.snolf.jumptapping = true
			player.snolf.jumptapready = false
		else
			player.snolf.jumptapping = false
		end

		-- check if the ability button is being held
		if player.cmd.buttons & BT_USE then
			player.snolf.spintapped = false
			player.snolf.spinheld = $1 + 1
		else
			player.snolf.spintapped = 0 < player.snolf.spinheld and player.snolf.spinheld < 10
			player.snolf.spinheld = 0
		end

		-- check if the first custom action button is being held
		if player.cmd.buttons & BT_CUSTOM1 then
			player.snolf.ca1held = $1 + 1
		else
			player.snolf.ca1held = 0
		end
	end

end)



addHook("ThinkFrame", function()
	-- Don't do anything if we're not Snolf
	for player in players.iterate do
		if player.mo.skin ~= "snolf" then
			continue
		end

		-- snolfstate
		-- 0 ready to snolf
		-- 1 snolfing horizontal
		-- 2 snolfing vertical
		-- 3 snolf'd

		local max_hrz = 50 --max horizontal release speed
		local max_vrt = 50 --max vertical release speed


		-- I want the meter timing to be sinusoidal so we will be using trigonometry
		local increment = ANG1 + ANG2
		local max_charge = ANGLE_180

		local mull = player.snolf.mull -- list of mulligan points

		player.mo.state = S_PLAY_ROLL --force rolling animation

		if player.snolf.spintapped then
			player.mo.angle = $1 + ANGLE_180
		end


		if player.snolf.ca1held > 60 and #mull > 1 then
			table.remove(mull, #mull)
			P_TeleportMove(player.mo,
				mull[#mull].x,
				mull[#mull].y,
				mull[#mull].z)
			P_InstaThrust(player.mo, 0, 0)
			P_SetObjectMomZ(player.mo, 0)
			player.snolf.ca1held = 0
			S_StartSound(player.mo, sfx_mixup)
		elseif player.snolf.spinheld > 60 and player.snolf.state == 3 then
			P_TeleportMove(player.mo,
				mull[#mull].x,
				mull[#mull].y,
				mull[#mull].z)
			P_InstaThrust(player.mo, 0, 0)
			P_SetObjectMomZ(player.mo, 0)
			player.snolf.spinheld = 0
			S_StartSound(player.mo, sfx_mixup)
		end

		-- if the player is on the ground and not on a waterslide
		if P_IsObjectOnGround(player.mo) and (player.pflags & PF_SLIDING == 0) then
			player.jumpfactor = 0 -- set jump height to zero
			player.pflags = $1 | PF_SPINNING --force spinning flag
		elseif player.jumpfactor != 1
			-- set jump height to normal
			-- this is to allow the player to jump out waterslides and
			-- things like the Castle Eggman catapults
			player.jumpfactor = 1 * FRACUNIT
		end


		-- if the player is on the ground and stationary
		if P_IsObjectOnGround(player.mo) and player.speed == 0 then
			local last_mull = mull[#mull]
			local pmo = player.mo
			if not last_mull or
				(pmo.x ~= last_mull.x or pmo.y ~= last_mull.y or pmo.z ~= last_mull.z) then
				-- if we already have ten mulligan points clear one out
				if #mull > 9 then
					table.remove(mull, 1)
				end
				-- add a mulligan point
				table.insert(mull,{ --set mulligan spot
					x = player.mo.x,
					y = player.mo.y,
					z = player.mo.z
				})
			end
		end

		if player.snolf.state == 0 then -- state 0: can start a shot
			if player.snolf.jumptapping then
				player.snolf.state = 1
				player.snolf.hdrive = 0
				player.snolf.vdrive = 0
				player.snolf.increment = increment
				S_StartSoundAtVolume(player.mo, sfx_spndsh, 64)
				player.pflags = $1 | PF_STARTDASH -- Set player to spindash state
			end
		elseif player.snolf.state == 1 then -- state 1: picking horizontal force
			if player.snolf.jumptapping then
				player.snolf.state = 2
				player.snolf.increment = increment
				S_StartSoundAtVolume(player.mo, sfx_spndsh, 100)
			else

				if player.snolf.hdrive >= max_charge then
					player.snolf.increment = - increment
				elseif player.snolf.hdrive <= 0 then
					player.snolf.increment = increment
				end

				player.snolf.hdrive = $1 + player.snolf.increment
			end
		elseif player.snolf.state == 2 then -- state 2: picking vertical force
			if player.snolf.jumptapping then
				player.snolf.shots = $1 + 1
				player.snolf.state = 3

				local hspeed = player.snolf.convert_angle(player.snolf.hdrive, max_hrz)
				local vspeed = player.snolf.convert_angle(player.snolf.vdrive, max_vrt)

				P_InstaThrust(player.mo, player.mo.angle, hspeed*FRACUNIT)
				P_SetObjectMomZ(player.mo, vspeed*FRACUNIT)
				player.pflags = $1 | PF_JUMPED --force jumped flag
				S_StartSound(player.mo, sfx_zoom)
			else

				if player.snolf.vdrive >= max_charge then
					player.snolf.increment = -increment
				elseif player.snolf.vdrive <= 0 then
					player.snolf.increment = increment
				end

				player.snolf.vdrive = $1 + player.snolf.increment
			end
		elseif player.snolf.state == 3 then -- state 3: we have launched and can't do anything till we come to a stop
			if P_IsObjectOnGround(player.mo) and player.speed == 0 then
				player.snolf.state = 0
			end
		elseif player.snolf.state == nil then
			player.snolf.state = 0
		end
	end
end)
