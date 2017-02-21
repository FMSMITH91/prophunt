-- Enhanced by: Wolvindra-Vinzuerio and D4UNKN0WNM4N2010 --
-- Special thanks for Kowalski that merged into his github. You may check on his prop hunt workshop page. --

-- Send the required lua files to the client
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("cl_menu.lua")
AddCSLuaFile("cl_targetid.lua")
AddCSLuaFile("sh_config.lua")
AddCSLuaFile("taunts/hunter_taunts.lua")
AddCSLuaFile("taunts/prop_taunts.lua")
AddCSLuaFile("sh_init.lua")
AddCSLuaFile("sh_player.lua")
AddCSLuaFile("sh_showwindowtaunt.lua")

-- Include the required lua files
include("sh_init.lua")
include("sv_admin.lua")
include("sh_showwindowtaunt.lua")

-- Server only constants
EXPLOITABLE_DOORS = {
	"func_door",
	"prop_door_rotating", 
	"func_door_rotating"
}
USABLE_PROP_ENTITIES = {
	"prop_physics",
	"prop_physics_multiplayer"
}

-- Voice Control Constant init
VOICE_IS_END_ROUND = 0

-- Update cvar to variables changes every so seconds
UPDATE_CVAR_TO_VARIABLE = 0

-- Player Join/Leave message
gameevent.Listen( "player_connect" )
hook.Add( "player_connect", "AnnouncePLJoin", function( data )
	for k, v in pairs( player.GetAll() ) do
		v:PrintMessage( HUD_PRINTTALK, data.name .. " has connected to the server." )
	end
end )

gameevent.Listen( "player_disconnect" )
hook.Add( "player_disconnect", "AnnouncePLLeave", function( data )
	for k,v in pairs( player.GetAll() ) do
		v:PrintMessage( HUD_PRINTTALK, data.name .. " has left the server (Reason: " .. data.reason ..")" )
	end
end )

-- We're going to get the usable prop table and send it over to the client with this network string
util.AddNetworkString("ServerUsablePropsToClient")
-- Additional network string for Custom Taunts window
util.AddNetworkString("PH_ForceCloseTauntWindow")
util.AddNetworkString("PH_AllowTauntWindow")
-- Perhaps force this instead of using convars?
util.AddNetworkString("PH_BetterPropMovement")
util.AddNetworkString("PH_CameraCollisions")
util.AddNetworkString("PH_CustomTauntEnabled")
util.AddNetworkString("PH_CustomTauntDelay")
util.AddNetworkString("PH_PlayerName_AboveHead")

-- Force Close taunt window function, determined whenever the round ends, or team winning.
local function ForceCloseTauntWindow(num)
	if num == 1 then
		net.Start("PH_ForceCloseTauntWindow")
		net.Broadcast()
	elseif num == 0 then
		net.Start("PH_AllowTauntWindow")
		net.Broadcast()
	end
end

-- Called alot
function GM:CheckPlayerDeathRoundEnd()
	if !GAMEMODE.RoundBased || !GAMEMODE:InRound() then 
		return
	end

	local Teams = GAMEMODE:GetTeamAliveCounts()

	if table.Count(Teams) == 0 then
		GAMEMODE:RoundEndWithResult(1001, "Draw, everyone loses!")
		VOICE_IS_END_ROUND = 1
		ForceCloseTauntWindow(1)
		
		hook.Call("PH_OnRoundDraw", nil)
		return
	end

	if table.Count(Teams) == 1 then
		local TeamID = table.GetFirstKey(Teams)
		-- debug
		MsgAll("Round Result: "..team.GetName(TeamID).." ("..TeamID..") Wins!\n")
		-- End Round
		GAMEMODE:RoundEndWithResult(TeamID, team.GetName(TeamID).." win!") -- fix end result that often opposited as "Props Win" or "Hunter Win".
		VOICE_IS_END_ROUND = 1
		ForceCloseTauntWindow(1)
		
		hook.Call("PH_OnRoundWinTeam", nil, TeamID)
		return
	end
	
end

-- Player Voice & Chat Control to prevent Metagaming. (As requested by some server owners/suggestors.)
-- You can disable this feature by typing 'sv_alltalk 1' in console to make everyone can hear.

-- Control Player Voice
local alltalk = GetConVar("sv_alltalk")
function GM:PlayerCanHearPlayersVoice(listen, speaker)
	
	local alltalk_cvar = alltalk:GetInt()
	if (alltalk_cvar > 0) then return true, false end
	
	-- prevent Loopback check.
	if (listen == speaker) then return false, false end

	-- Only alive players can listen other living players.
	if listen:Alive() && speaker:Alive() then return true, false end
	
	-- Event: On Round Start. Living Players don't listen to dead players.
	if VOICE_IS_END_ROUND == 0 && listen:Alive() && !speaker:Alive() then return false, false end
	
	-- Listen to all dead players while you dead.
	if !listen:Alive() && !speaker:Alive() then return true, false end
	
	-- However, Living players can be heard from dead players.
	if !listen:Alive() && speaker:Alive() then return true, false end
	
	-- Event: On Round End/Time End. Listen to everyone.
	if VOICE_IS_END_ROUND == 1 && listen:Alive() && !speaker:Alive() then return true, false end

	-- Spectator can only read from themselves.
	if listen:Team() == TEAM_SPECTATOR && listen:Alive() && speaker:Alive() then return false, false end
	
	-- This is for ULX "Permanent Gag". Uncomment this if you have issues.
	-- if speaker:GetPData( "permgagged" ) == "true" then return false, false end
end

-- Control Players Chat
function GM:PlayerCanSeePlayersChat(txt, onteam, listen, speaker)
	
	if ( onteam ) then
		-- Generic Specific OnTeam chats
		if ( !IsValid( speaker ) || !IsValid( listen ) ) then return false end
		if ( listen:Team() != speaker:Team() ) then return false end
		
		-- ditto, this is same as below.
		if listen:Alive() && speaker:Alive() then return true end
		if VOICE_IS_END_ROUND == 0 && listen:Alive() && !speaker:Alive() then return false end
		if !listen:Alive() && !speaker:Alive() then return true end
		if !listen:Alive() && speaker:Alive() then return true end
		if VOICE_IS_END_ROUND == 1 && listen:Alive() && !speaker:Alive() then return true end
		if listen:Team() == TEAM_SPECTATOR && listen:Alive() && speaker:Alive() then return false end
	end
	
	local alltalk_cvar = alltalk:GetInt()
	if (alltalk_cvar > 0) then return true end
	
	-- Generic Checks
	if ( !IsValid( speaker ) || !IsValid( listen ) ) then return false end
	
	-- Only alive players can see other living players.
	if listen:Alive() && speaker:Alive() then return true end
	
	-- Event: On Round Start. Living Players don't see dead players' chat.
	if VOICE_IS_END_ROUND == 0 && listen:Alive() && !speaker:Alive() then return false end
	
	-- See Chat to all dead players while you dead.
	if !listen:Alive() && !speaker:Alive() then return true end
	
	-- However, Living players' chat can be seen from dead players.
	if !listen:Alive() && speaker:Alive() then return true end
	
	-- Event: On Round End/Time End. See Chat to everyone.
	if VOICE_IS_END_ROUND == 1 && listen:Alive() && !speaker:Alive() then return true end

	-- Spectator can only read from themselves.
	if listen:Team() == TEAM_SPECTATOR && listen:Alive() && speaker:Alive() then return false end
end

-- Called when an entity takes damage
function EntityTakeDamage(ent, dmginfo)
    local att = dmginfo:GetAttacker()
	if GAMEMODE:InRound() && ent && (ent:GetClass() != "ph_prop" && ent:GetClass() != "func_breakable" && ent:GetClass() != "prop_door_rotating" && ent:GetClass() != "prop_dynamic*") && !ent:IsPlayer() && att && att:IsPlayer() && att:Team() == TEAM_HUNTERS && att:Alive() then
		att:SetHealth(att:Health() - HUNTER_FIRE_PENALTY)
		if att:Health() <= 0 then
			MsgAll(att:Name() .. " felt guilty for hurting so many innocent props and committed suicide\n")
			att:Kill()
			
			hook.Call("PH_HunterDeathPenalty", nil, att)
		end
	end
end
hook.Add("EntityTakeDamage", "PH_EntityTakeDamage", EntityTakeDamage)

-- Called when player tries to pickup a weapon
function GM:PlayerCanPickupWeapon(pl, ent)
 	if pl:Team() != TEAM_HUNTERS then
		return false
	end
	
	return true
end

function PH_ResetCustomTauntWindowState()
	-- Force close any taunt menu windows
	ForceCloseTauntWindow(0)
	-- Extra additional
	VOICE_IS_END_ROUND = 0
end
hook.Add("PostCleanupMap", "PH_ResetCustomTauntWindow", PH_ResetCustomTauntWindowState)

-- Make a variable for 4 unique combines.
-- Clean up, sorry btw.
local playerModels = {
	"combine",
	"combineprison",
	"combineelite",
	"police"
	-- you may add more here.
}

function GM:PlayerSetModel(pl)
	-- set antlion gib small for Prop model. 
	-- Do not change this into others because this might purposed as a hitbox for props.
	local player_model = "models/gibs/antlion_gib_small_3.mdl"

	-- Clean Up.
	if GetConVar("ph_use_custom_plmodel"):GetBool() then
		-- Use a delivered player model info from cl_playermodel ConVar.
		-- This however will use a custom player selection. It'll immediately apply once it is selected.
		local mdlinfo = pl:GetInfo("cl_playermodel")
		local mdlname = player_manager.TranslatePlayerModel(mdlinfo)

		if pl:Team() == TEAM_HUNTERS then
			player_model = mdlname
		end
	else
		-- Otherwise, Use Random one based from a table above.
		local customModel = table.Random(playerModels)
		local customMdlName = player_manager.TranslatePlayerModel(customModel)

		if pl:Team() == TEAM_HUNTERS then
			player_model = customMdlName
		end
	end
	
	-- precache and Set the model.
	util.PrecacheModel(player_model)
	pl:SetModel(player_model)
end
	
-- Called when a player tries to use an object
function GM:PlayerUse(pl, ent)
	if !pl:Alive() || pl:Team() == TEAM_SPECTATOR || pl:Team() == TEAM_UNASSIGNED then return false end
	
	if pl:Team() == TEAM_PROPS && pl:IsOnGround() && !pl:Crouching() && table.HasValue(USABLE_PROP_ENTITIES, ent:GetClass()) && ent:GetModel() then
		if table.HasValue(BANNED_PROP_MODELS, ent:GetModel()) then
			pl:ChatPrint("That prop has been banned by the server.")
		elseif ent:GetPhysicsObject():IsValid() && pl.ph_prop:GetModel() != ent:GetModel() then
			local ent_health = math.Clamp(ent:GetPhysicsObject():GetVolume() / 250, 1, 200)
			local new_health = math.Clamp((pl.ph_prop.health / pl.ph_prop.max_health) * ent_health, 1, 200)
			local per = pl.ph_prop.health / pl.ph_prop.max_health
			pl.ph_prop.health = new_health
			
			pl.ph_prop.max_health = ent_health
			pl.ph_prop:SetModel(ent:GetModel())
			pl.ph_prop:SetSkin(ent:GetSkin())
			pl.ph_prop:SetSolid(SOLID_VPHYSICS)
			pl.ph_prop:SetPos(pl:GetPos() - Vector(0, 0, ent:OBBMins().z))
			pl.ph_prop:SetAngles(pl:GetAngles())
			
			local hullxymax = math.Round(math.Max(ent:OBBMaxs().x, ent:OBBMaxs().y))
			local hullxymin = hullxymax * -1
			local hullz = math.Round(ent:OBBMaxs().z)
			
			pl:SetHull(Vector(hullxymin, hullxymin, 0), Vector(hullxymax, hullxymax, hullz))
			pl:SetHullDuck(Vector(hullxymin, hullxymin, 0), Vector(hullxymax, hullxymax, hullz))
			pl:SetHealth(new_health)
			
			umsg.Start("SetHull", pl)
				umsg.Long(hullxymax)
				umsg.Long(hullz)
				umsg.Short(new_health)
			umsg.End()
		end
	end
	
	-- Prevent the door exploit
	if table.HasValue(EXPLOITABLE_DOORS, ent:GetClass()) && pl.last_door_time && pl.last_door_time + 1 > CurTime() then
		return false
	end
	
	pl.last_door_time = CurTime()
	return true
end

-- Called when player presses [F3]. Plays a taunt for their team
function GM:ShowSpare1(pl)
	if GetConVar("ph_enable_custom_taunts"):GetBool() && GAMEMODE:InRound() then
		pl:ConCommand("ph_showtaunts")
	end
	
	if !GetConVar("ph_enable_custom_taunts"):GetBool() && GAMEMODE:InRound() && pl:Alive() && (pl:Team() == TEAM_HUNTERS || pl:Team() == TEAM_PROPS) && pl.last_taunt_time + TAUNT_DELAY <= CurTime() && #PROP_TAUNTS > 1 && #HUNTER_TAUNTS > 1 then
		repeat
			if pl:Team() == TEAM_HUNTERS then
				rand_taunt = table.Random(HUNTER_TAUNTS)
			else
				rand_taunt = table.Random(PROP_TAUNTS)
			end
		until rand_taunt != pl.last_taunt
		
		pl.last_taunt_time = CurTime() + TAUNT_DELAY
		pl.last_taunt = rand_taunt
		
		pl:EmitSound(rand_taunt, 100)
	end	
end

function GM:CanStartRound()
	if #team.GetPlayers( TEAM_HUNTERS ) + #team.GetPlayers( TEAM_PROPS ) >= 2 then return true end
	return false
end

-- Called when a player leaves
function PlayerDisconnected(pl)
	pl:RemoveProp()
end
hook.Add("PlayerDisconnected", "PH_PlayerDisconnected", PlayerDisconnected)

-- Called when the players spawns
function PlayerSpawn(pl)
	pl:SetNWBool("PlayerLockedRotation", false)
	pl:SetNWBool("InFreezeCam", false)
	pl:SetNWEntity("PlayerKilledByPlayerEntity", nil)
	pl:Blind(false)
	pl:RemoveProp()
	pl:RemoveClientProp()
	pl:SetColor(Color(255, 255, 255, 255))
	pl:SetRenderMode( RENDERMODE_TRANSALPHA )
	pl:UnLock()
	pl:ResetHull()
	pl.last_taunt_time = 0
	
	umsg.Start("ResetHull", pl)
	umsg.End()
	
	umsg.Start("DisableDynamicLight", pl)
	umsg.End()
	
	pl:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR)
	
	-- Do something with jump power
	if pl:Team() == TEAM_HUNTERS then
		pl:SetJumpPower(160)
	elseif pl:Team() == TEAM_PROPS then
		pl:SetJumpPower(160 * 1.4)
	end
end
hook.Add("PlayerSpawn", "PH_PlayerSpawn", PlayerSpawn)


-- Called when round ends
function RoundEnd()
	for _, pl in pairs(team.GetPlayers(TEAM_HUNTERS)) do
		pl:Blind(false)
		pl:UnLock()
	end
end
hook.Add("RoundEnd", "PH_RoundEnd", RoundEnd)


-- This is called when the round time ends (props win)
function GM:RoundTimerEnd()
	if !GAMEMODE:InRound() then
		return
	end
   
	GAMEMODE:RoundEndWithResult(TEAM_PROPS, "Props win!")
	VOICE_IS_END_ROUND = 1
	ForceCloseTauntWindow(1)
	
	hook.Call("PH_OnTimerEnd", nil)
end


-- Called before start of round
function GM:OnPreRoundStart(num)
	game.CleanUpMap()
	
	if GetGlobalInt("RoundNumber") != 1 && (SWAP_TEAMS_EVERY_ROUND == 1 || ((team.GetScore(TEAM_PROPS) + team.GetScore(TEAM_HUNTERS)) > 0 || SWAP_TEAMS_POINTS_ZERO==1)) then
		for _, pl in pairs(player.GetAll()) do
			if pl:Team() == TEAM_PROPS || pl:Team() == TEAM_HUNTERS then
				if pl:Team() == TEAM_PROPS then
					pl:SetTeam(TEAM_HUNTERS)
				else
					pl:SetTeam(TEAM_PROPS)
					if GetConVar("ph_better_prop_movement"):GetBool() then
						pl:SendLua( [[notification.AddLegacy("You are in Prop Team with Rotate support! You can rotate the prop around by moving your mouse.", NOTIFY_UNDO, 20 )]] )
						pl:SendLua( [[notification.AddLegacy("Additionally you can toggle lock rotation by pressing R key!", NOTIFY_GENERIC, 20 )]] )
						pl:SendLua( [[surface.PlaySound("garrysmod/content_downloaded.wav")]] )
					else
						pl:SendLua( [[notification.AddLegacy("You are in Prop Team with Classic mode!", NOTIFY_GENERIC, 20 )]] )
						pl:SendLua( [[surface.PlaySound("ambient/water/drip3.wav")]] )
					end
					
					-- Send some net stuff
					net.Start("ServerUsablePropsToClient")
						net.WriteTable(USABLE_PROP_ENTITIES)
					net.Send(pl)
					local propscore = team.GetScore( TEAM_PROPS )
					local huntscore = team.GetScore( TEAM_HUNTERS )
	
					team.SetScore( TEAM_PROPS, huntscore )
					team.SetScore( TEAM_HUNTERS, propscore )
				end
			
			pl:ChatPrint("Teams have been swapped!")
			end
		end
		
		hook.Call("PH_OnPreRoundStart", nil, SWAP_TEAMS_EVERY_ROUND)
	end
	
	UTIL_StripAllPlayers()
	UTIL_SpawnAllPlayers()
	UTIL_FreezeAllPlayers()
end


-- Called every server tick.
function GM:Think()
	-- Prop Rotation
	for _, pl in pairs(team.GetPlayers(TEAM_PROPS)) do
		if GetConVar("ph_better_prop_movement"):GetBool() then
			if pl && pl:IsValid() && pl:Alive() && pl.ph_prop && pl.ph_prop:IsValid() then
				if pl.ph_prop:GetModel() == "models/player/kleiner.mdl" then
					pl.ph_prop:SetPos(pl:GetPos())
				else
					pl.ph_prop:SetPos(pl:GetPos() - Vector(0, 0, pl.ph_prop:OBBMins().z))
				end
				if !(pl:GetPlayerLockedRot()) then
					pl.ph_prop:SetAngles(pl:GetAngles())
				end
			end
		end
	end
	
	-- Extra check here for changes cvars
	if UPDATE_CVAR_TO_VARIABLE < CurTime() then
		-- Update better prop movement variable
		net.Start("PH_BetterPropMovement")
			net.WriteBool(GetConVar("ph_better_prop_movement"):GetBool())
		net.Broadcast()
		
		-- Update camera collisions variable
		net.Start("PH_CameraCollisions")
			net.WriteBool(GetConVar("ph_prop_camera_collisions"):GetBool())
		net.Broadcast()
		
		-- Update camera collisions variable
		net.Start("PH_CustomTauntEnabled")
			net.WriteBool(GetConVar("ph_enable_custom_taunts"):GetBool())
		net.Broadcast()
		
		-- Update custom taunt delay variable
		net.Start("PH_CustomTauntDelay")
			net.WriteInt(GetConVarNumber("ph_customtaunts_delay"), 8) -- 8 bits so we don't send too much information here
		net.Broadcast()
		
		-- Update plhalos enabled variable
		net.Start("PH_PlayerName_AboveHead")
			net.WriteBool(GetConVar("ph_enable_plnames"):GetBool())
		net.Broadcast()
		
		-- Make sure to update every so seconds and not constantly
		UPDATE_CVAR_TO_VARIABLE = CurTime() + UPDATE_CVAR_TO_VARIABLE_ADD
	end
end

-- Bonus Drop :D
function PH_Props_OnBreak(ply, ent)
	if GetConVar("ph_enable_lucky_balls"):GetBool() then
		local pos = ent:GetPos()
		if math.random() < 0.08 then -- 8% Chance of drops.
			local dropent = ents.Create("ph_luckyball")
			dropent:SetPos(Vector(pos.x, pos.y, pos.z + 32)) -- to make sure the Lucky Ball didn't fall underground.
			dropent:SetAngles(Angle(0,0,0))
			dropent:SetColor(Color(math.Round(math.random(0,255)),math.Round(math.random(0,255)),math.Round(math.random(0,255)),255))
			dropent:Spawn()
		end
	end
end
hook.Add("PropBreak", "Props_OnBreak_WithDrops", PH_Props_OnBreak)

-- Force Close the Taunt Menu whenever the prop is being killed.
function close_PlayerKilledSilently(ply)
	if ply:Team() == TEAM_PROPS then
		net.Start( "PH_ForceCloseTauntWindow" )
		net.Send(ply)
	end
end
hook.Add("PlayerSilentDeath", "SilentDed_ForceClose", close_PlayerKilledSilently)

-- Flashlight toggling
function GM:PlayerSwitchFlashlight(pl, on)
	if pl:Alive() && pl:Team() == TEAM_HUNTERS then
		return true
	end
	
	if pl:Alive() && pl:Team() == TEAM_PROPS then
		umsg.Start("PlayerSwitchDynamicLight", pl)
		umsg.End()
	end
	
	return false
end

-- Player pressed a key
function PlayerPressedKey(pl, key)
	if GetConVar("ph_better_prop_movement"):GetBool() && pl && pl:IsValid() && pl:Alive() && pl:Team() == TEAM_PROPS && pl.ph_prop && pl.ph_prop:IsValid() then
		if ( key == IN_RELOAD ) then
			if pl:GetPlayerLockedRot() then
				pl:SetNWBool("PlayerLockedRotation", false)
				pl:PrintMessage(HUD_PRINTCENTER, "Prop Rotation Lock: Disabled")
			else
				pl:SetNWBool("PlayerLockedRotation", true)
				pl:PrintMessage(HUD_PRINTCENTER, "Prop Rotation Lock: Enabled")
			end
		end
	end
end
hook.Add("KeyPress", "PlayerPressedKey", PlayerPressedKey)
