---------------------------------
-- Golf copy ability for Kirby --
---------------------------------

local K_Snolf = function(checkflags, destroy, late, player)
	if checkflags then
		return 0
		--return AF_NOJUMP|AF_NOSWIM|AF_NODUCK
	elseif destroy then
		--reset stats
		local skin = skins[player.mo.skin]
		player.jumpfactor = skin.jumpfactor
		player.accelstart = skin.accelstart
		player.acceleration = skin.acceleration
		player.charability2 = skin.ability2
	end
	if late then
		return
	end
	player.kvars.ablvar1 = $1+1 --use ablvar1 as a timer
end

addHook("PreThinkFrame", function()
	if K_AddAbility and kirbyabilitytable and not kirby_snolf_ability then
		rawset(_G, "kirby_snolf_ability", K_AddAbility( K_Snolf, false, "GOLF"))
		kirbyabilitytable["snolf"] = kirby_snolf_ability
	end
end)
