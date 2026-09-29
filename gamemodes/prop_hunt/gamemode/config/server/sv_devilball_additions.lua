-- This is a template of Devil Balls Additions which will adds a new events for Devil balls entity.
-- Note: Key name (the "UniqueName") must be different and cannot be similar with other name's addition. This is purposely used for PHX:VerboseMsg and preventing
-- Duplicated addition and table reading errors.

-- To add something, Remove "--[[" and "]]" to make them available again.

--[[
list.Set("DevilBallsAddition", "UniqueName", function(pl)
	
	-- give something to the player or modify something to pl.ph_prop. for example:
	pl:ChatPrint("Hello! Let me change the prop color and revert in 5 seconds!")
	
	if IsValid(pl.ph_prop) then
		pl.ph_prop:SetMaterial("models/shiny")
		pl.ph_prop:SetColor(Color(255,0,0))
		
		timer.Simple(5, function()
			-- The player may have left or lost the prop in those 5 seconds.
			if IsValid(pl) and IsValid(pl.ph_prop) then
				pl.ph_prop:SetMaterial("")
				pl.ph_prop:SetColor(color_white)
			end
		end)
	end
end)
]]