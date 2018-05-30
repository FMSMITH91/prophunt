
function INITPropTaunts()
	-- ////////// DO NOT ADD TAUNTS HERE \\\\\\\\\\\\ --
	local taunt_init = {}
	
	-- AUTO TAUNT SCANNER
	if GetConVar("ph_enable_taunt_scandir"):GetBool() then
	
		local propst = "sound/taunts/props_custom/"
		if !file.Exists(propst, "GAME") then
			printVerbose("[PH:E Taunts] Custom prop taunts cannot be detected because one or more directories are missing!!")
			printVerbose("[PH:E Taunts] Make sure this directory exists \'"..propst.."\' !!")
		end

		-- Let us go find them shall we
		if file.Exists(propst, "GAME") then
			-- Add WAV
			local wavlist = file.Find(propst.."*.wav", "GAME")
			printVerbose("[PH:E Taunts] Looking for custom WAV taunts...")
			if #wavlist < 1 then 
				printVerbose("[PH:E Taunts] Custom Taunt: There is nothing to add...") 
			else
				for k, v in pairs(wavlist) do
					printVerbose("[PH:E Taunts] Detected & adding custom prop taunt: "..propst..v.." as Sound #"..k..".")
					-- Adds Key names on each added sounds and make it so each sounds will have 'Sound #' Prefix to be listed.
					taunt_init["Sound #"..k] = "taunts/props_custom/"..v
				end
			end
			
			-- Add MP3 -- Warning: Unrecommended. Use WAV for better Precaching and solving BASS error issues.
			local mp3list = file.Find(propst.."*.mp3", "GAME")
			printVerbose("[PH:E Taunts] Looking for custom MP3 taunts...")
			if #mp3list < 1 then 
				printVerbose("[PH:E Taunts] Custom Taunt: There is nothing to add...")
			else
				for k, v in pairs(mp3list) do
					printVerbose("[PH:E Taunts] Detected & adding custom prop taunt: "..propst..v.." as Sound #"..k..".")
					-- Adds Key names on each added sounds and make it so each sounds will have 'Sound #' Prefix to be listed.
					taunt_init["Sound #"..k] = "taunts/props_custom/"..v
				end
			end
		end
		
	end
	
	return taunt_init
end