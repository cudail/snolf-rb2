

addHook("PreThinkFrame", function()
	
	for player in players.iterate do
		if player.mo.skin ~= "snolf" then
			continue
		end
		
		--check if the jump button was just tapped
		if not (player.cmd.buttons & BT_JUMP) then
			player.jumptapready = true
			player.jumptapping = false
		elseif player.jumptapready then
			player.jumptapping = true
			player.jumptapready = false
		else
			player.jumptapping = false
		end
		
		--swallow player input
		player.cmd.forwardmove = 0
		player.cmd.sidemove = 0
		player.cmd.buttons = 0
	end
	
end)



addHook("ThinkFrame", function()
	for player in players.iterate do
		if player.mo.skin ~= "snolf" then
			continue
		end
		
		player.mo.state = S_PLAY_ROLL --force rolling animation
		player.pflags = $1 | PF_SPINNING --force spinning flag
		
		-- snolfstate
		-- 0 ready to snolf
		-- 1 snolfing horizontal
		-- 2 snolfing vertical
		-- 3 snolf'd

		player.snolf_max_hrz = 50
		player.snolf_max_vrt = 50
		
		if player.snolfstate == 0 then
			if player.jumptapping then
				player.snolfstate = 1
				player.snolf_hdrive = 0
				player.snolf_vdrive = 0
				player.snolf_increment = 1
				player.snolf_timer = 0
			end
		elseif player.snolfstate == 1 then
			if player.jumptapping then
				player.snolfstate = 2
				player.snolf_increment = 1
			else
				player.snolf_timer = $1 + 1
				
				if player.snolf_hdrive >= player.snolf_max_hrz then
					player.snolf_increment = -1
				elseif player.snolf_hdrive <= 0 then
					player.snolf_increment = 1
				end
			
				if player.snolf_timer % 2 == 0 then
					player.snolf_hdrive = $1 + player.snolf_increment
				end
			end
		elseif player.snolfstate == 2 then
			if player.jumptapping then
				print("SNOLF!")
				player.snolfstate = 3
				P_InstaThrust(player.mo, player.mo.angle, player.snolf_hdrive*FRACUNIT)
				P_SetObjectMomZ(player.mo, player.snolf_vdrive*FRACUNIT, true)
			else
				player.snolf_timer = $1 + 1
				
				if player.snolf_vdrive >= player.snolf_max_vrt then
					player.snolf_increment = -1
				elseif player.snolf_vdrive <= 0 then
					player.snolf_increment = 1
				end
				
				if player.snolf_timer % 2 == 0 then
					player.snolf_vdrive = $1 + player.snolf_increment
				end
			end
		elseif player.snolfstate == 3 then
			if P_IsObjectOnGround(player.mo) then
				player.snolfstate = 0
			end
		elseif player.snolfstate == nil then
			player.snolfstate = 0
		end
		
		if player.snolfstate == 1 or player.snolfstate == 2 then
			print("Horizontal:")
			print(player.snolf_hdrive)
			print("Vertical:")
			print(player.snolf_vdrive)
		end
	end
end)
