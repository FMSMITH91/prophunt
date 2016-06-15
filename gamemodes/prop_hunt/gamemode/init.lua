-- Enhanced by: Wolvindra-Vinzuerio and D4UNKN0WNM4N2010 --
-- Special thanks for Kowalski that merged into his github. You may check on his prop hunt workshop page. --

-- Send the required lua files to the client
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("cl_menu.lua")
AddCSLuaFile("sh_config.lua")
AddCSLuaFile("sh_init.lua")
AddCSLuaFile("sh_player.lua")

-- Include the required lua files
include("sh_init.lua")
include("sv_admin.lua")

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


-- We're going to get the usable prop table and send it over to the client with this network string
util.AddNetworkString("ServerUsablePropsToClient")


-- Send the required resources to the client
for _, taunt in pairs(HUNTER_TAUNTS) do resource.AddFile("sound/"..taunt) end
for _, taunt in pairs(PROP_TAUNTS) do resource.AddFile("sound/"..taunt) end

-- Called alot
function GM:CheckPlayerDeathRoundEnd()
	if !GAMEMODE.RoundBased || !GAMEMODE:InRound() then 
		return
	end

	local Teams = GAMEMODE:GetTeamAliveCounts()

	if table.Count(Teams) == 0 then
		GAMEMODE:RoundEndWithResult(1001, "Draw, everyone loses!")
		return
	end

	if table.Count(Teams) == 1 then
		local TeamID = table.GetFirstKey(Teams)
		GAMEMODE:RoundEndWithResult(TeamID, team.GetName(TeamID).." win!")
		return
	end
	
	--todo: add custom wins/lost sound on next update.
end


-- Called when an entity takes damage
function EntityTakeDamage(ent, dmginfo)
    local att = dmginfo:GetAttacker()
	if GAMEMODE:InRound() && ent && (ent:GetClass() != "ph_prop" && ent:GetClass() != "func_breakable" && ent:GetClass() != "prop_door_rotating" && ent:GetClass() != "prop_dynamic*") && !ent:IsPlayer() && att && att:IsPlayer() && att:Team() == TEAM_HUNTERS && att:Alive() then
		att:SetHealth(att:Health() - HUNTER_FIRE_PENALTY)
		if att:Health() <= 0 then
			MsgAll(att:Name() .. " felt guilty for hurting so many innocent props and committed suicide\n")
			att:Kill()
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
	local player_model = "models/Gibs/Antlion_gib_small_3.mdl"

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
	if !pl:Alive() || pl:Team() == TEAM_SPECTATOR then return false end
	
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
	if GAMEMODE:InRound() && pl:Alive() && (pl:Team() == TEAM_HUNTERS || pl:Team() == TEAM_PROPS) && pl.last_taunt_time + TAUNT_DELAY <= CurTime() && #PROP_TAUNTS > 1 && #HUNTER_TAUNTS > 1 then
		repeat
			if pl:Team() == TEAM_HUNTERS then
				rand_taunt = table.Random(HUNTER_TAUNTS)
			else
				rand_taunt = table.Random(PROP_TAUNTS)
			end
		until rand_taunt != pl.last_taunt
		
		pl.last_taunt_time = CurTime()
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
	pl:SetColor( Color(255, 255, 255, 255))
	pl:SetRenderMode( RENDERMODE_TRANSALPHA )
	pl:UnLock()
	pl:ResetHull()
	pl.last_taunt_time = 0
	
	umsg.Start("ResetHull", pl)
	umsg.End()
	
	umsg.Start("DisableDynamicLight", pl)
	umsg.End()
	
	pl:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR)
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
						-- i hope the logic is right... GetBool() if true = 1, else 0.
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
					end
				
				pl:ChatPrint("Teams have been swapped!")

			end
		end
	end
	
	UTIL_StripAllPlayers()
	UTIL_SpawnAllPlayers()
	UTIL_FreezeAllPlayers()
end


-- Called every server tick.
function GM:Think()
	for _, pl in pairs(team.GetPlayers(TEAM_PROPS)) do
		if GetConVar("ph_better_prop_movement"):GetBool() then
			if pl && pl:IsValid() && pl:Alive() && pl.ph_prop && pl.ph_prop:IsValid() then
				if (pl.ph_prop:GetModel() == "models/player/kleiner.mdl") || table.HasValue(ADDITIONAL_STARTING_MODELS, pl.ph_prop:GetModel()) then
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
end

-- Bonus Drop :D
function PH_Props_OnBreak(ply, ent)
	local pos = ent:GetPos()
	if math.random() < 0.08 then -- 0.8% Chance of drops.
		local dropent = ents.Create("ph_luckyball")
		dropent:SetPos(Vector(pos.x, pos.y, pos.z + 32)) -- to make sure the Lucky Ball didn't fall underground and if the Prop's Center Origin is near underground, they'll spawn with extra +32 hammer unit.
		dropent:SetAngles(Angle(0,0,0))
		dropent:SetColor(Color(math.Round(math.random(0,255)),math.Round(math.random(0,255)),math.Round(math.random(0,255)),255))
		dropent:Spawn()
	end
end
hook.Add("PropBreak", "Props_OnBreak_WithDrops", PH_Props_OnBreak)


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
