-- HUNTER TAUNT LISTS
PHE.PH_TAUNT_CUSTOM.HUNTER = {
	["Guuuh!"]						=	"vo/k_lab/ba_guh.wav",
	["If you See Dr. Breen"]		= 	"vo/streetwar/rubble/ba_tellbreen.wav"
	-- Add more here. don't forget to add comma above after the list ^
}

-- Create custom taunt directory if needed and find custom taunts if it all exists
-- Directory Existant
if !file.Exists("sound/taunts/hunters_custom/", "GAME") then
	printVerbose("[PH:E Taunts] Custom hunter taunts cannot be detected because one or more directories are missing!!")
	printVerbose("[PH:E Taunts] Make sure this directory exists \'sound/taunts/hunters_custom/\' !!")
end

-- Let us go find them shall we
if file.Exists("sound/taunts/hunters_custom/", "GAME") then
	-- Add WAV
	PHE.PH_TAUNT_FILE_LIST.HUNTER = file.Find("sound/taunts/hunters_custom/*.wav", "GAME")
	printVerbose("[PH:E Taunts] Looking for custom WAV taunts...")
	if #PHE.PH_TAUNT_FILE_LIST.HUNTER < 1 then printVerbose("[PH:E Taunts] Custom Taunt: There is nothing to add...") end
	for k, v in pairs(PHE.PH_TAUNT_FILE_LIST.HUNTER) do
		printVerbose("[PH:E Taunts] Detected & adding custom hunter taunt: sound/taunts/hunters_custom/"..v.." as Sound #"..k..".")
		-- Adds Key names on each added sounds and make it so each sounds will have 'Sound #' Prefix to be listed.
		PHE.PH_TAUNT_CUSTOM.HUNTER["Sound #"..k] = "taunts/hunters_custom/"..v
	end
	
	-- Add MP3 -- Warning: Unrecommended. Use WAV for better Precaching and solving BASS error issues.
	PHE.PH_TAUNT_FILE_LIST.HUNTER = file.Find("sound/taunts/hunters_custom/*.mp3", "GAME")
	printVerbose("[PH:E Taunts] Looking for custom MP3 taunts.")
	if #PHE.PH_TAUNT_FILE_LIST.HUNTER < 1 then printVerbose("[PH:E Taunts] Custom Taunt: There is nothing to add...") end
	for k, v in pairs(PHE.PH_TAUNT_FILE_LIST.HUNTER) do
		printVerbose("[PH:E Taunts] Detected & adding custom hunter taunt: sound/taunts/hunters_custom/"..v.." as Sound #"..k..".")
		-- Adds Key names on each added sounds and make it so each sounds will have 'Sound #' Prefix to be listed.
		PHE.PH_TAUNT_CUSTOM.HUNTER["Sound #"..k] = "taunts/hunters_custom/"..v
	end
end
