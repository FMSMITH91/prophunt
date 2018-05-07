-- Help & documentation of how to add your custom taunts: http://www.wolvindra.net/phe_faq
-- There is no need anymore to read from Help & Documentation as the gamemode now automatically finds taunts (Unless adding sounds from other directories than hunters_custom)

-- HUNTER TAUNT LISTS
PHE.PH_TAUNT_CUSTOM.HUNTER = {
	-- Same as prop_taunts.lua, except this only for Team Hunter.
	"vo/k_lab/ba_guh.wav",
	"taunts/props_extra/dx_augmented.wav"
}

-- Create custom taunt directory if needed and find custom taunts if it all exists
-- Directory Existant
if !file.Exists("sound/taunts/hunters_custom/", "GAME") then
	printVerbose("[PH: Enhanced] Custom hunter taunts cannot be detected because one or more directories are missing!!")
	printVerbose("[PH: Enhanced] Make sure this directory exists: sound/taunts/hunters_custom/ !")
end

-- Let us go find them shall we
if file.Exists("sound/taunts/hunters_custom/", "GAME") then
	-- Add WAV
	PHE.PH_TAUNT_FILE_LIST.HUNTER = file.Find("sound/taunts/hunters_custom/*.wav", "GAME")
	printVerbose("[PH: Enhanced] Looking for custom WAV taunts.")
	if #PHE.PH_TAUNT_FILE_LIST.HUNTER < 1 then printVerbose("[PH: Enhanced] Custom Taunt: There is nothing here??") end
	for k, v in pairs(PHE.PH_TAUNT_FILE_LIST.HUNTER) do
		printVerbose("[PH: Enhanced] Detected & adding custom hunter taunt: sound/taunts/hunters_custom/"..v.." .")
		table.insert(PHE.PH_TAUNT_CUSTOM.HUNTER, "taunts/hunters_custom/"..v)
	end
	
	-- Add MP3
	PHE.PH_TAUNT_FILE_LIST.HUNTER = file.Find("sound/taunts/hunters_custom/*.mp3", "GAME")
	printVerbose("[PH: Enhanced] Looking for custom MP3 taunts.")
	if #PHE.PH_TAUNT_FILE_LIST.HUNTER < 1 then printVerbose("[PH: Enhanced] Custom Taunt: There is nothing here??") end
	for k, v in pairs(PHE.PH_TAUNT_FILE_LIST.HUNTER) do
		printVerbose("[PH: Enhanced] Detected & adding custom hunter taunt: sound/taunts/hunters_custom/"..v.." .")
		table.insert(PHE.PH_TAUNT_CUSTOM.HUNTER, "taunts/hunters_custom/"..v)
	end
end
