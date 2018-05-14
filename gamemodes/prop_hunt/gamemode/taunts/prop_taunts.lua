-- PROP TAUNT LISTS
PHE.PH_TAUNT_CUSTOM.PROP = {
	["Windows XP Shutdown"]			=	"taunts/ph_enhanced/ext_xp_off.wav",
	["Windows XP Startup"]			=	"taunts/ph_enhanced/ext_xp_start.wav"
	-- Add more here. don't forget to add comma above after the list ^
}

local propst = "sound/taunts/props_custom/"

-- Create custom taunt directory if needed and find custom taunts if it all exists
-- Directory Existant
if !file.Exists(propst, "GAME") then
	printVerbose("[PH:E Taunts] Custom prop taunts cannot be detected because one or more directories are missing!!")
	printVerbose("[PH:E Taunts] Make sure this directory exists \'"..propst.."\' !!")
end

-- Let us go find them shall we
if file.Exists(propst, "GAME") then
	-- Add WAV
	PHE.PH_TAUNT_FILE_LIST.PROP = file.Find(propst.."*.wav", "GAME")
	printVerbose("[PH:E Taunts] Looking for custom WAV taunts...")
	if #PHE.PH_TAUNT_FILE_LIST.PROP < 1 then printVerbose("[PH:E Taunts] Custom Taunt: There is nothing to add...") end
	for k, v in pairs(PHE.PH_TAUNT_FILE_LIST.PROP) do
		printVerbose("[PH:E Taunts] Detected & adding custom prop taunt: "..propst..v.." as Sound #"..k..".")
		-- Adds Key names on each added sounds and make it so each sounds will have 'Sound #' Prefix to be listed.
		PHE.PH_TAUNT_CUSTOM.PROP["Sound #"..k] = "taunts/props_custom/"..v
	end
	
	-- Add MP3 -- Warning: Unrecommended. Use WAV for better Precaching and solving BASS error issues.
	PHE.PH_TAUNT_FILE_LIST.PROP = file.Find(propst.."*.mp3", "GAME")
	printVerbose("[PH:E Taunts] Looking for custom MP3 taunts...")
	if #PHE.PH_TAUNT_FILE_LIST.PROP < 1 then printVerbose("[PH:E Taunts] Custom Taunt: There is nothing to add...") end
	for k, v in pairs(PHE.PH_TAUNT_FILE_LIST.PROP) do
		printVerbose("[PH:E Taunts] Detected & adding custom prop taunt: "..propst..v.." as Sound #"..k..".")
		-- Adds Key names on each added sounds and make it so each sounds will have 'Sound #' Prefix to be listed.
		PHE.PH_TAUNT_CUSTOM.PROP["Sound #"..k] = "taunts/props_custom/"..v
	end
end
