freeslot("SPR_SFST", "SPR_SFAH", "SPR_SFAV", "SPR_SFMR")

hud.add(function(v, player, camera)
	-- Don't do anything if we're not Snolf
	if player.mo.skin == "snolf" then

		local hud_shots = v.getSpritePatch(SPR_SFST) -- SHOTS HUD element
		v.draw(16, 58, hud_shots, V_HUDTRANS|V_SNAPTOLEFT|V_SNAPTOTOP)
		v.drawNum(96, 58, player.snolf.shots, V_HUDTRANS|V_SNAPTOLEFT|V_SNAPTOTOP)

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

		-- draw cheat indicators
		local starColour = -1
		local chts = player.snolf.cheats
		if chts.liferefund and chts.mullpointondie and chts.groundcontrol then
			starColour = 0
		elseif chts.liferefund and chts.mullpointondie then
			starColour = V_YELLOWMAP
		elseif chts.liferefund and chts.groundcontrol then
			starColour = V_MAGENTAMAP
		elseif chts.mullpointondie and chts.groundcontrol then
			starColour = V_SKYMAP
		elseif chts.liferefund then
			starColour = V_REDMAP
		elseif chts.mullpointondie then
			starColour = V_GREENMAP
		elseif chts.groundcontrol then
			starColour = V_BLUEMAP
		end
		if starColour > -1 then
			v.drawString(20, 176, "*", starColour|V_HUDTRANS|V_SNAPTOLEFT|V_SNAPTOBOTTOM)
		end
		if chts.nodrown then
			local bubble = v.getSpritePatch(SPR_BUBL, 1)
			v.draw(24, 188, bubble, V_HUDTRANS|V_SNAPTOLEFT|V_SNAPTOBOTTOM)
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
			player.snolf = {
				shots = 0, state = 0, spinheld = 0, ca2held = 0, player = player,
				inair = false
			}
			player.snolf.mull = {}
			player.snolf.cheats = {
				liferefund = false, mullpointondie = false,
				nodrown = false, groundcontrol = false, inputs = ''
			}
			player.snolf.convert_angle = function (angle, max_val)
				return sin(angle - ANGLE_90)*max_val/FRACUNIT/2 + max_val/2
			end
			player.snolf.go_to_mull = function ()
				local mull = player.snolf.mull
				if mull and #mull > 0 then
					P_TeleportMove(player.mo,
						mull[#mull].x,
						mull[#mull].y,
						mull[#mull].z)
					P_InstaThrust(player.mo, 0, 0)
					P_SetObjectMomZ(player.mo, 0)
					S_StartSound(player.mo, sfx_mixup)
					player.snolf.inair = false
					player.snolf.prev_momz = 0
				end
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
			player.snolf.spinheld = $1 + 1
		else
			player.snolf.spinheld = 0
		end

		-- check if the first custom ability button was just tapped
		if not (player.cmd.buttons & BT_CUSTOM1) then
			player.snolf.ca1ready = true
			player.snolf.ca1tapped = false
		elseif player.snolf.ca1ready then
			player.snolf.ca1tapped = true
			player.snolf.ca1ready = false
		else
			player.snolf.ca1tapped = false
		end


		-- check directional inputs for inputting cheats
		if player.cmd.forwardmove < 40 then
			player.snolf.upready = true
			player.snolf.uptapped = false
		elseif player.snolf.upready then
			player.snolf.uptapped = true
			player.snolf.upready = false
		else
			player.snolf.uptapped = false
		end

		if player.cmd.forwardmove > -40 then
			player.snolf.dnready = true
			player.snolf.dntapped = false
		elseif player.snolf.dnready then
			player.snolf.dntapped = true
			player.snolf.dnready = false
		else
			player.snolf.dntapped = false
		end

		if player.cmd.sidemove < 40 then
			player.snolf.rtready = true
			player.snolf.rttapped = false
		elseif player.snolf.rtready then
			player.snolf.rttapped = true
			player.snolf.rtready = false
		else
			player.snolf.rttapped = false
		end

		if player.cmd.sidemove > -40 then
			player.snolf.lfready = true
			player.snolf.lftapped = false
		elseif player.snolf.lfready then
			player.snolf.lftapped = true
			player.snolf.lfready = false
		else
			player.snolf.lftapped = false
		end

		local cht = player.snolf.cheats

		-- check if the second custom action button is held we are in cheat entering mode
		if player.cmd.buttons & BT_CUSTOM2 then
			if player.snolf.uptapped then
				cht.inputs = $1 .. 'u'
			elseif player.snolf.dntapped then
				cht.inputs = $1 .. 'd'
			elseif player.snolf.lftapped then
				cht.inputs = $1 .. 'l'
			elseif player.snolf.rttapped then
				cht.inputs = $1 .. 'r'
			end

			if #cht.inputs > 10 then -- only keep track of the last ten inputs
				cht.inputs = string.sub($1, #$1 - 10)
			end
		else
			cht.inputs = ''
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

		local bounce_limit = 10 -- Snolf won't bounce if their vertical momentum is less than this (in FRACUNITs)
		local bounce_factor = FRACUNIT / 2 -- when Snolf bounces their momentum is multiplied by this factor

		local button_hold_threshold = 60

		-- I want the meter timing to be sinusoidal so we will be using trigonometry
		local increment = ANG1 + ANG2
		local max_charge = ANGLE_180

		local mull = player.snolf.mull -- list of mulligan points

		local water_air_timer = 1050
		local space_air_timer = 403

		local pmo = player.mo

		pmo.state = S_PLAY_ROLL --force rolling animation

		if player.snolf.ca1tapped then -- quick flip
			pmo.angle = $1 + ANGLE_180
		end

		if player.snolf.ca2tapped then -- free life
			player.lives = $1 +1
			P_PlayLivesJingle(player)
		end

		if player.snolf.cheats.nodrown then
			if player.powers[pw_underwater] > 0 then
				player.powers[pw_underwater] = water_air_timer
			end
			if player.powers[pw_spacetime] > 0 then
				player.powers[pw_spacetime] = space_air_timer
			end
		end

		if player.snolf.cheats.groundcontrol and P_IsObjectOnGround(pmo) then
			-- give the player normal levels of control while rolling
			player.accelstart = 96
			player.acceleration = 40
		else
			-- no control
			player.accelstart = 0
			player.acceleration = 0
		end

		if player.playerstate == PST_REBORN then
			player.snolf.inair = false
			player.snolf.prev_momz = 0
			if player.snolf.cheats.liferefund then
				player.lives = $1 + 1
			end
			if player.snolf.cheats.mullpointondie then
				player.snolf.isbeingreborn = true
			else
				player.snolf.mull = {} --reset  mulligan points
			end
		elseif player.snolf.isbeingreborn and player.playerstate == PST_LIVE then
			player.snolf.isbeingreborn = false
			player.snolf.go_to_mull()
		end

		if player.snolf.spinheld == button_hold_threshold then
			local m = mull[#mull]
			if m then
				if pmo.x == m.x and pmo.y == m.y and pmo.z == m.z then
					table.remove(mull, #mull)
				end
				player.snolf.go_to_mull()
			end
		end

		local chtin = player.snolf.cheats.inputs

		if (string.sub(chtin, #chtin-3)) == 'udlr' then
			S_StartSound(player.mo, sfx_kc46)
			player.snolf.cheats.inputs = ''
			player.snolf.cheats.liferefund = not $1
		elseif (string.sub(chtin, #chtin-7)) == 'uudduuuu' then
			S_StartSound(player.mo, sfx_kc46)
			player.snolf.cheats.inputs = ''
			player.snolf.cheats.mullpointondie = not $1
		elseif (string.sub(chtin, #chtin-7)) == 'ullduudr' then
			S_StartSound(player.mo, sfx_kc46)
			player.snolf.cheats.inputs = ''
			player.snolf.cheats.groundcontrol = not $1
		elseif (string.sub(chtin, #chtin-8)) == 'lllrrruuu' then
			S_StartSound(player.mo, sfx_ideya)
			player.snolf.cheats.inputs = ''
			player.snolf.cheats.nodrown = not $1
		end


		if player.snolf.inair and P_IsObjectOnGround(pmo) then -- we have just landed
			if abs(player.snolf.prev_momz) > abs(bounce_limit * FRACUNIT) then -- bounce if we're above the bounce_limit speed
				P_SetObjectMomZ(pmo, - FixedMul(player.snolf.prev_momz, bounce_factor)) -- bounce with momentum proportional to what we landed with
				player.pflags = $1 | PF_JUMPED --force jumped flag
			else
				player.snolf.inair = false -- we landed
			end
		end
		player.snolf.prev_momz = pmo.momz -- store z momentum from previous frame for landing bounce maths

		-- if the player is on the ground and not on a waterslide
		if P_IsObjectOnGround(pmo) and (player.pflags & PF_SLIDING == 0) then
			player.jumpfactor = 0 -- set jump height to zero
			player.pflags = $1 | PF_SPINNING --force spinning flag
		elseif player.jumpfactor != 1
			-- set jump height to normal
			-- this is to allow the player to jump out waterslides and
			-- things like the Castle Eggman catapults
			player.jumpfactor = 1 * FRACUNIT
		end


		-- if the player is on the ground and stationary
		if P_IsObjectOnGround(pmo) and player.speed == 0 then
			local last_mull = mull[#mull]
			if not last_mull or
				(pmo.x ~= last_mull.x or pmo.y ~= last_mull.y or pmo.z ~= last_mull.z) then
				-- if we already have ten mulligan points clear one out
				if #mull > 9 then
					table.remove(mull, 1)
				end
				-- add a mulligan point
				table.insert(mull,{ --set mulligan spot
					x = pmo.x,
					y = pmo.y,
					z = pmo.z
				})
			end
		end

		if player.snolf.state == 0 then -- state 0: can start a shot
			if player.snolf.jumptapping then
				player.snolf.state = 1
				player.snolf.hdrive = 0
				player.snolf.vdrive = 0
				player.snolf.increment = increment
				S_StartSoundAtVolume(pmo, sfx_spndsh, 64)
				player.pflags = $1 | PF_STARTDASH -- Set player to spindash state
			end
		elseif player.snolf.state == 1 then -- state 1: picking horizontal force
			if player.snolf.jumptapping then
				player.snolf.state = 2
				player.snolf.increment = increment
				S_StartSoundAtVolume(pmo, sfx_spndsh, 100)
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
				player.snolf.inair = true

				local hspeed = player.snolf.convert_angle(player.snolf.hdrive, max_hrz)
				local vspeed = player.snolf.convert_angle(player.snolf.vdrive, max_vrt)

				P_InstaThrust(pmo, pmo.angle, hspeed*FRACUNIT)
				P_SetObjectMomZ(pmo, vspeed*FRACUNIT)
				player.pflags = $1 | PF_JUMPED --force jumped flag
				S_StartSound(pmo, sfx_zoom)
			else

				if player.snolf.vdrive >= max_charge then
					player.snolf.increment = -increment
				elseif player.snolf.vdrive <= 0 then
					player.snolf.increment = increment
				end

				player.snolf.vdrive = $1 + player.snolf.increment
			end
		elseif player.snolf.state == 3 then -- state 3: we have launched and can't do anything till we come to a stop
			if P_IsObjectOnGround(pmo) and player.speed == 0 then
				player.snolf.state = 0
			end
		elseif player.snolf.state == nil then
			player.snolf.state = 0
		end
	end
end)


-- Hook to override default collision and make Snolf bounce off walls
addHook("MobjMoveBlocked", function(mo)
	if mo.skin ~= "snolf" then return false end

	-- P_BounceMove doesn't bounce the player if they are on the ground 
	-- To get around this impart the tiniest possible vertical momentum the
	-- engine will allow so Snolf is technically in the air for a single frame
	if P_IsObjectOnGround(mo) then
		P_SetObjectMomZ(mo, 1)
	end
	P_BounceMove(mo)
	return true
end)
