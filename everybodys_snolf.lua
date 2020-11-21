addHook("PreThinkFrame", function()
	for player in players.iterate do
		if player.snolf ~= nill then
			player.snolf.forcesnolf = true
		end
	end
end)
