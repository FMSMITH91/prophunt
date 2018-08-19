-- In here you can add two team taunts without seperating them.
-- Make sure you have give a timer to make sure it can get work properly.

-- Begin Table: Hunters (ADD THEM HERE!)
local Hunter_Taunts = {
	["Guuuh!"]						=	"vo/k_lab/ba_guh.wav",
	["If you See Dr. Breen"]		= 	"vo/streetwar/rubble/ba_tellbreen.wav"
	-- Add more here...
}
-- Begin Table: Props (ADD THEM HERE!)
local Prop_Taunts = {
	["Windows XP Shutdown"]			=	"taunts/ph_enhanced/ext_xp_off.wav",
	["Windows XP Startup"]			=	"taunts/ph_enhanced/ext_xp_start.wav"
	-- Add more here...
}

-- Begin Adding Taunts. If it still wont show up, change the timer delay other than 3 seconds.
-- Fix: added FastDL
timer.Simple(3, function()
	-- cancel if PHE public variable did not exists, prevent errors.
	if (!PHE || engine.ActiveGamemode() != "prop_hunt") then 
		print("[PH: Enhanced] Something is wrong when trying to get 'PHE' public table for taunts...")
		return
	end

	-- Adding for Hunters.
	for tauntName, tauntPath in pairs(Hunter_Taunts) do
		-- Description: Prevent Duplication from Taunt Scanner.
		-- Remove any existing taunt that generated from Sound #X to the existing table from this Hunter_Taunts table.
		if table.HasValue(PHE.PH_TAUNT_CUSTOM.HUNTER, tauntPath) then
			-- debug
			printVerbose("[PH: Enhanced] Removing existing taunt from "..tostring(table.KeyFromValue(tauntPath)).." and changing into --> "..tauntName)
			table.RemoveByValue(PHE.PH_TAUNT_CUSTOM.HUNTER, tauntPath)
			PHE:AddCustomTaunt(1,tauntName,tauntPath) -- 1 = TEAM_HUNTERS
		else
			printVerbose("[PH: Enhanced] Adding Custom Hunter Taunt & FastDL: --> "..tauntName)
			PHE:AddCustomTaunt(1,tauntName,tauntPath) -- 1 = TEAM_HUNTERS
		end
		
		if (SERVER) then
			-- Adding them to FastDL...
			resource.AddSingleFile("sound/"..tauntPath)
		end
		
	end
	
	-- Adding for Props
	for tauntPName, tauntPPath in pairs(Prop_Taunts) do
		if table.HasValue(PHE.PH_TAUNT_CUSTOM.PROP, tauntPPath) then
			printVerbose("[PH: Enhanced] Removing existing taunt from "..tostring(table.KeyFromValue(tauntPPath)).." and changing into --> "..tauntPName)
			table.RemoveByValue(PHE.PH_TAUNT_CUSTOM.PROP, tauntPPath)
			PHE:AddCustomTaunt(2,tauntPName,tauntPPath) -- 1 = TEAM_HUNTERS
		else
			printVerbose("[PH: Enhanced] Adding Custom Prop Taunt & FastDL: --> "..tauntPName)
			PHE:AddCustomTaunt(2,tauntPName,tauntPPath) -- 2 = TEAM_PROPS
		end
		
		if (SERVER) then
			-- Adding them to FastDL...
			resource.AddSingleFile("sound/"..tauntPPath)
		end
	end
	
	-- Let's Refresh the taunt list and make it available in the future. 
	-- If this still wont show up, change the timer delay more/less than 1 second.
	timer.Simple(1, function()
		printVerbose("[PH: Enhanced] Refreshing Taunt Lists to make them available for clientside...")
		PHE:RefreshTauntList()
	end)
end)