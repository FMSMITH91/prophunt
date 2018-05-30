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
timer.Simple(3, function()
	-- cancel if PHE public variable did not exists, prevent errors.
	if !PHE then 
		print("[PH: Enhanced] Something is wrong when trying to get 'PHE' public table variable...")
		return
	end

	-- Adding for Hunters.
	for tauntName, tauntPath in pairs(Hunter_Taunts) do
		printVerbose("[PH: Enhanced] Adding Custom Hunter Taunt: --> "..tauntName)
		PHE:AddCustomTaunt(1,tauntName,tauntPath) -- 1 = TEAM_HUNTERS
	end
	
	-- Adding for Props
	for tauntPName, tauntPPath in pairs(Prop_Taunts) do
		printVerbose("[PH: Enhanced] Adding Custom Prop Taunt: --> "..tauntPName)
		PHE:AddCustomTaunt(2,tauntPName,tauntPPath) -- 2 = TEAM_PROPS
	end
	
	-- Let's Refresh the taunt list and make it available in the future. 
	-- If this still wont show up, change the timer delay other than 1 second.
	timer.Simple(1, function()
		printVerbose("[PH: Enhanced] Refreshing Taunt Lists to make them available...")
		PHE:RefreshTauntList()
	end)
end)