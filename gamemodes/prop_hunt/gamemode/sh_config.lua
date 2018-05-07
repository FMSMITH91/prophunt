-- Global Var for custom taunt, delivering from taunts/prop -or- hunter_taunts.lua
PHE.PH_TAUNT_CUSTOM = {}
PHE.PH_TAUNT_FILE_LIST = {}
include("taunts/hunter_taunts.lua")
include("taunts/prop_taunts.lua")

-- \\ General Gamemode Config -- use from ConVar instead modifying them here. // --

-- Maximum time (in minutes) for this fretta gamemode (Default: 30)
PHE.GAME_TIME = GetConVarNumber("ph_game_time")

-- Number of seconds hunters are blinded/locked at the beginning of the map (Default: 30)
PHE.HUNTER_BLINDLOCK_TIME = GetConVarNumber("ph_hunter_blindlock_time")

-- Health points removed from hunters when they shoot  (Default: 5)
PHE.HUNTER_FIRE_PENALTY = GetConVarNumber("ph_hunter_fire_penalty")

-- How much health to give back to the Hunter after killing a prop (Default: 20)
PHE.HUNTER_KILL_BONUS = GetConVarNumber("ph_hunter_kill_bonus")

-- Seconds a player has to wait before they can taunt again (Default: 2 or 3)
PHE.TAUNT_DELAY = GetConVarNumber("ph_normal_taunt_delay")

-- Rounds played on a map (Default: 10)
PHE.ROUNDS_PER_MAP = GetConVarNumber("ph_rounds_per_map")

-- Time (in seconds) for each round (Default: 300)
PHE.ROUND_TIME = GetConVarNumber("ph_round_time")

-- Determains if players should be team swapped every round [0 = No, 1 = Yes] (Default: 1)
PHE.SWAP_TEAMS_EVERY_ROUND = GetConVarNumber("ph_swap_teams_every_round")

-- Boolean if custom taunts enabled (Default: 0)
--PHE.CUSTOM_TAUNT_ENABLED = GetConVar("ph_enable_custom_taunts"):GetBool()
PHE.CUSTOM_TAUNT_ENABLED = GetConVar("ph_enable_custom_taunts"):GetInt()

-- Time (in seconds) for props to play custom taunts again (Default: 6)
PHE.CUSTOM_TAUNT_DELAY = GetConVarNumber("ph_customtaunts_delay")

-- Time (in seconds) for cvar variable update to happen (Default: 1)
PHE.UPDATE_CVAR_TO_VARIABLE_ADD = 1

-- Enable "Wait for Players" checks?
PHE.WAIT_FOR_PLY 	= GetConVar("ph_waitforplayers"):GetBool()

-- Minimum Player before we start the proper round
PHE.MIN_PLY			= GetConVar("ph_min_waitforplayers"):GetInt()

-- Banned Props models
--[[ Add one of your owns model restriction if you have problems. 
	these lists are usually common props that has been used on every maps. ]]--
PHE.BANNED_PROP_MODELS = {
	"models/props/cs_assault/dollar.mdl",
	"models/props/cs_assault/money.mdl",
	"models/props/cs_office/snowman_arm.mdl",
	"models/props/cs_militia/reload_bullet_tray.mdl"
}

--[[ // DO NOT MODIFY! use from taunts/prop_taunts.lua or hunter_taunts.lua instead! \\ ]]--
PHE.HUNTER_TAUNTS = {
	"taunts/hunters/come_to_papa.wav",
	"taunts/hunters/father.mp3",
	"taunts/hunters/fireassis.wav",
	"taunts/hunters/hitassist.wav",
	"taunts/hunters/now_what.wav",
	"taunts/hunters/you_dont_know_the_power.wav",
	"taunts/hunters/you_underestimate_the_power.wav",
	"taunts/hunters/glados-president.wav",
	"taunts/hunters/rude.mp3",
	"taunts/hunters/soul.mp3",
	"taunts/hunters/illfindyou.mp3",
	"vo/npc/male01/vanswer13.wav",
	"vo/npc/male01/thehacks01.wav",
	"vo/npc/male01/runforyourlife02.wav",
	"vo/npc/male01/overhere01.wav",
	"vo/npc/male01/overthere01.wav",
	"vo/npc/male01/overthere02.wav"
}

--[[ // DO NOT MODIFY! use from taunts/props_taunts.lua or hunters_taunts.lua instead! \\ ]]--
PHE.PROP_TAUNTS = {
	"taunts/boom_headshot.wav",
	"taunts/go_away_or_i_shall.wav",
	"taunts/ill_be_back.wav",
	"taunts/negative.wav",
	"taunts/doh.wav",
	"taunts/oh_yea_he_will_pay.wav",
	"taunts/ok_i_will_tell_you.wav",
	"taunts/please_come_again.wav",
	"taunts/threat_neutralized.wav",
	"taunts/what_is_wrong_with_you.wav",
	"taunts/woohoo.wav",
	"taunts/props/1.wav",
	"taunts/props/2.wav",
	"taunts/props/3.wav",
	"taunts/props/4.wav",
	"taunts/props/5.wav",
	"taunts/props/6.wav",
	"taunts/props/7.wav",
	"taunts/props/8.wav",
	"taunts/props/9.wav",
	"taunts/props/10.wav",
	"taunts/props/11.wav",
	"taunts/props/12.wav",
	"taunts/props/14.wav",
	"taunts/props/15.wav",
	"taunts/props/16.wav",
	"taunts/props/17.mp3",
	"taunts/props/18.wav",
	"taunts/props/19.wav",
	"taunts/props/20.wav",
	"taunts/props/21.wav",
	"taunts/props/22.wav",
	"taunts/props/23.wav",
	"taunts/props/24.wav",
	"taunts/props/25.wav",
	"taunts/props/26.wav",
	"taunts/props/27.wav",
	"taunts/props/28.wav",
	"taunts/props/30.wav",
	"taunts/props/31.mp3",
	"taunts/props/32.mp3",
	"taunts/props/33.mp3",
	"taunts/props/34.mp3",
	"taunts/props/35.mp3",
	"vo/citadel/br_ohshit.wav",
	"vo/citadel/br_youfool.wav",
	"vo/citadel/br_youneedme.wav",
	"vo/coast/odessa/male01/nlo_cheer01.wav",
	"vo/coast/odessa/male01/nlo_cheer02.wav",
	"vo/coast/odessa/male01/nlo_cheer03.wav",
	"vo/coast/odessa/male01/nlo_cheer04.wav",
	"vo/coast/odessa/female01/nlo_cheer01.wav",
	"vo/coast/odessa/female01/nlo_cheer02.wav",
	"vo/coast/odessa/female01/nlo_cheer03.wav",
	"vo/gman_misc/gman_riseshine.wav",
	"vo/npc/barney/ba_damnit.wav",
	"vo/npc/barney/ba_laugh01.wav",
	"vo/npc/barney/ba_laugh02.wav",
	"vo/npc/barney/ba_laugh03.wav",
	"vo/npc/barney/ba_laugh04.wav",
	"vo/npc/male01/hacks01.wav",
	"vo/npc/male01/hacks02.wav",
	"vo/npc/male01/vanswer01.wav",
	"vo/npc/male01/question05.wav",
	"vo/npc/male01/question06.wav",
	"vo/npc/male01/answer34.wav",
	"vo/npc/male01/question30.wav",
	"vo/npc/male01/question26.wav",
	"vo/npc/male01/incoming02.wav",
	"vo/npc/male01/gethellout.wav",
	"vo/ravenholm/madlaugh04.wav",
	"taunts/fixed/13_fix.wav",
	"taunts/fixed/bees_fix.wav",
	"taunts/hunters/laugh.wav"
}

-- Custom Player Model bans for props
PHE.PROP_PLMODEL_BANS = {
	"models/player.mdl"
}

PHE.WINNINGSOUNDS = {
	[1] 		= "misc/ph_hunterwin.mp3", 	-- hunter
	[2]			= "misc/ph_propwin.mp3",	-- props
	["Draw"]	= {"misc/ph_rounddraw_1.mp3", "misc/ph_rounddraw_2.mp3"}
}

-- Add custom taunts, if any. See taunts/prop_taunts.lua or taunts/hunter_taunts.lua for more info.
local function AddDemTaunt()
	printVerbose("[PH: Enhanced] Finalising custom prop taunts.")
	if PHE.PH_TAUNT_CUSTOM.PROP != nil then
		for k,prop in pairs(PHE.PH_TAUNT_CUSTOM.PROP) do
			-- We do not need this?
			-- table.insert(PROP_TAUNTS, prop)
			if (SERVER) then
				resource.AddFile("sound/"..prop)
			end
		end
	else
		printVerbose("[PH: Enhanced] WARNING! Custom taunts table is EMPTY!!")
	end
	
	printVerbose("[PH: Enhanced] Finalising custom hunter taunts.")
	if PHE.PH_TAUNT_CUSTOM.HUNTER != nil then
		for k,hunter in pairs(PHE.PH_TAUNT_CUSTOM.HUNTER) do
			-- We do not need this?
			-- table.insert(HUNTER_TAUNTS, hunter)
			if (SERVER) then
				resource.AddFile("sound/"..hunter)
			end
		end
	else
		printVerbose("[PH: Enhanced] WARNING! Custom taunts table is EMPTY!!")
	end
end
AddDemTaunt()

-- Add the custom player model bans for props
if SERVER then
	local function AddBadPLModels()

		-- Create base config area
		if ( !file.Exists( "prop_hunt-enhanced", "DATA" ) ) then
		
			file.CreateDir( "prop_hunt-enhanced" )
		
		end

		-- Create actual config
		if ( !file.Exists( "prop_hunt-enhanced/prop_playermodel_bans.txt", "DATA" ) ) then
		
			file.Write("prop_hunt-enhanced/prop_playermodel_bans.txt", util.TableToJSON(PHE.PROP_PLMODEL_BANS, true))
		
		end

		-- Check and make sure the file still exists in case something caused it to not be created
		if ( file.Exists( "prop_hunt-enhanced/prop_playermodel_bans.txt", "DATA" ) ) then
		
			local PROP_PLMODEL_BANS_READ = util.JSONToTable( file.Read( "prop_hunt-enhanced/prop_playermodel_bans.txt", "DATA" ) )
			for k, v in pairs(PROP_PLMODEL_BANS_READ) do
				if !table.HasValue(PHE.PROP_PLMODEL_BANS, string.lower(v)) then
					printVerbose("[PH: Enhanced] Adding custom prop model ban: "..string.lower(v))
					table.insert(PHE.PROP_PLMODEL_BANS, string.lower(v))
				end
			end
		
		end

	end
	AddBadPLModels()
end