-- Include the required lua files
include("sh_config.lua")
include("sh_player.lua")

-- mapvote
if SERVER then
    AddCSLuaFile("sh_mapvote.lua")
    AddCSLuaFile("mapvote/cl_mapvote.lua")

	include("sh_mapvote.lua")
    include("mapvote/sv_mapvote.lua")
    include("mapvote/rtv.lua")
else
	include("sh_mapvote.lua")
    include("mapvote/cl_mapvote.lua")
end

-- Fretta!
DeriveGamemode("fretta")
IncludePlayerClasses()

-- Information about the gamemode
GM.Name		= "Enhanced Prop Hunt"
GM.Author	= "Wolvindra-Vinzuerio and D4UNKN0WNM4N2010 (Enhanced), original by Kowalski/AMT"

-- Help info
GM.Help = [[Prop Hunt is a twist on the classic backyard game Hide and Seek.
TEAM PROP:
As a Prop you have ]]..HUNTER_BLINDLOCK_TIME..[[ seconds to replicate an existing prop on the map and then find a good hiding spot. Press [E] to replicate the prop you are looking at.
You can also rotate the prop around and lock the rotation by pressing R.

TEAM HUNTER:
As a Hunter you will be blindfolded for the first ]]..HUNTER_BLINDLOCK_TIME..[[ seconds of the round while the Props hide. When your blindfold is taken off, you will need to find props controlled by players and kill them. Damaging non-player props will lower your health significantly. 
However, killing a Prop will increase your health by ]]..HUNTER_KILL_BONUS..[[ points.

Both teams can press [F3] to play a taunt sound. Props can press [C] for custom taunts.]]

-- Fretta configuration
GM.GameLength				= GetConVarNumber("ph_game_time")
GM.AddFragsToTeamScore		= false
GM.CanOnlySpectateOwnTeam 	= true
GM.ValidSpectatorModes 		= { OBS_MODE_CHASE, OBS_MODE_IN_EYE, OBS_MODE_ROAMING }
GM.Data 					= {}
GM.EnableFreezeCam			= true
GM.NoAutomaticSpawning		= true
GM.NoNonPlayerPlayerDamage	= true
GM.NoPlayerPlayerDamage 	= true
GM.RoundBased				= true
GM.RoundLimit				= ROUNDS_PER_MAP
GM.RoundLength 				= ROUND_TIME
GM.RoundPreStartTime		= 0
GM.SuicideString			= "died mysteriously." -- i think this one is pretty obsolete.
GM.TeamBased 				= true
GM.AutomaticTeamBalance 	= false
GM.ForceJoinBalancedTeams 	= true

-- Additional xP
if !ConVarExists("ph_use_custom_plmodel_for_prop") then
	local ph_use_custom_plmodel_for_prop = CreateConVar("ph_use_custom_plmodel_for_prop", "0", { FCVAR_SERVER_CAN_EXECUTE, FCVAR_REPLICATED, FCVAR_ARCHIVE, FCVAR_NOTIFY }, "[EXPERIMENTAL] Should use a custom Player's Model for Props when the round begins?")
end

if !ConVarExists("ph_use_custom_plmodel") then
	local ph_use_custom_plmodel = CreateConVar("ph_use_custom_plmodel", "0", { FCVAR_SERVER_CAN_EXECUTE, FCVAR_REPLICATED, FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Should use a custom player model available for Hunters?\nPlease note that you must have to activate \'ph_use_custom_plmodel_for_prop\' too!")
end

-- D4UNKN0WNM4N2010: Yay! Prop Hunt specify cvars.
if !ConVarExists("ph_prop_camera_collisions") then
	local ph_prop_camera_collisions = CreateConVar("ph_prop_camera_collisions", "0", { FCVAR_SERVER_CAN_EXECUTE, FCVAR_REPLICATED, FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Attempts to stop props from viewing inside walls.")
end

if !ConVarExists("ph_freezecam") then
	local ph_freezecam = CreateConVar("ph_freezecam", "1", { FCVAR_SERVER_CAN_EXECUTE, FCVAR_REPLICATED, FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Freeze Camera.")
end

if !ConVarExists("ph_better_prop_movement") then
	local ph_better_prop_movement = CreateConVar("ph_better_prop_movement", "1", { FCVAR_SERVER_CAN_EXECUTE, FCVAR_REPLICATED, FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Should Enable Prop Rotation or Not?")
end

if !ConVarExists("ph_prop_collision") then
	local ph_prop_collision = CreateConVar("ph_prop_collision", "0", { FCVAR_SERVER_CAN_EXECUTE, FCVAR_REPLICATED, FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Should Team Props collide with each other?")
end

if !ConVarExists("ph_prop_additional_models") then
	local ph_prop_additional_models = CreateConVar("ph_prop_additional_models", "1", { FCVAR_SERVER_CAN_EXECUTE, FCVAR_REPLICATED, FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Should Team Props have different starting models instead of just Kleiner?")
end

-- Custom Taunts ConVars
if !ConVarExists("ph_customtaunts_delay") then
	local ph_customtaunts_delay = CreateConVar("ph_customtaunts_delay", "6", { FCVAR_SERVER_CAN_EXECUTE, FCVAR_REPLICATED, FCVAR_ARCHIVE, FCVAR_NOTIFY }, "How many in seconds delay for props to play custom taunt again? (Default is 6)")
end

if !ConVarExists("ph_enable_custom_taunts") then
	local ph_enable_custom_taunts = CreateConVar("ph_enable_custom_taunts", "0", { FCVAR_SERVER_CAN_EXECUTE, FCVAR_REPLICATED, FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Enable custom taunts for prop teams by pressing C? (Default 0)\n  You must have a list of custom taunts to enable this.")
end

if !ConVarExists("ph_hunter_fire_penalty") then
	local ph_hunter_fire_penalty = CreateConVar("ph_hunter_fire_penalty", "5", { FCVAR_SERVER_CAN_EXECUTE, FCVAR_REPLICATED, FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Health points removed from hunters when they shoot.")
	local ph_hunter_kill_bonus = CreateConVar("ph_hunter_kill_bonus", "20", { FCVAR_SERVER_CAN_EXECUTE, FCVAR_REPLICATED, FCVAR_ARCHIVE, FCVAR_NOTIFY }, "How much health to give back to the Hunter after killing a prop.")
	local ph_swap_teams_every_round = CreateConVar("ph_swap_teams_every_round", "1", { FCVAR_SERVER_CAN_EXECUTE, FCVAR_REPLICATED, FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Should teams swapped on every round?")
	local ph_game_time = CreateConVar("ph_game_time", "30", { FCVAR_SERVER_CAN_EXECUTE, FCVAR_REPLICATED, FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Maximum Time Left (in minutes) - Default is 30 minutes.")
	local ph_hunter_blindlock_time = CreateConVar("ph_hunter_blindlock_time", "30", { FCVAR_SERVER_CAN_EXECUTE, FCVAR_REPLICATED, FCVAR_ARCHIVE, FCVAR_NOTIFY }, "How long hunters are blinded (in seconds)")
	local ph_round_time = CreateConVar("ph_round_time", "300", { FCVAR_SERVER_CAN_EXECUTE, FCVAR_REPLICATED, FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Time (in seconds) for each rounds.")
	local ph_rounds_per_map = CreateConVar("ph_rounds_per_map", "10", { FCVAR_SERVER_CAN_EXECUTE, FCVAR_REPLICATED, FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Numbers played on a map (Default: 10)")
end

-- Called on gamemdoe initialization to create teams
function GM:CreateTeams()
	if !GAMEMODE.TeamBased then
		return
	end
	
	TEAM_HUNTERS = 1
	team.SetUp(TEAM_HUNTERS, "Hunters", Color(150, 205, 255, 255))
	team.SetSpawnPoint(TEAM_HUNTERS, {"info_player_counterterrorist", "info_player_combine", "info_player_deathmatch", "info_player_axis"})
	team.SetClass(TEAM_HUNTERS, {"Hunter"})

	TEAM_PROPS = 2
	team.SetUp(TEAM_PROPS, "Props", Color(255, 60, 60, 255))
	team.SetSpawnPoint(TEAM_PROPS, {"info_player_terrorist", "info_player_rebel", "info_player_deathmatch", "info_player_allies"})
	team.SetClass(TEAM_PROPS, {"Prop"})
end


function CheckPropCollision(entA, entB)
	if !GetConVar("ph_prop_collision"):GetBool() && (entA && entB && ((entA:IsPlayer() && entA:Team() == TEAM_PROPS && entB:IsValid() && entB:GetClass() == "ph_prop") || (entB:IsPlayer() && entB:Team() == TEAM_PROPS && entA:IsValid() && entA:GetClass() == "ph_prop"))) then
		return false
	end
end
hook.Add("ShouldCollide", "CheckPropCollision", CheckPropCollision)