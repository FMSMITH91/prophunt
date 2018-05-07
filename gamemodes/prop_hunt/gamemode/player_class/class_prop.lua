-- Create new class
local CLASS = {}


-- Some settings for the class
CLASS.DisplayName			= "Prop"
CLASS.WalkSpeed 			= 250
CLASS.CrouchedWalkSpeed 	= 0.2
CLASS.RunSpeed				= 275
CLASS.DuckSpeed				= 0.2
CLASS.JumpPower				= 250
CLASS.DrawTeamRing			= false

-- Prevent 'mod_studio: MOVETYPE_FOLLOW with No Models error.'
CLASS.DrawViewModel			= false


-- Called by spawn and sets loadout
function CLASS:Loadout(pl)
	-- Props don't get anything
end


-- Called when player spawns with this class
function CLASS:OnSpawn(pl)
	pl:SetColor( Color(255, 255, 255, 0))
	pl:SetupHands()
	pl:SetCustomCollisionCheck(true)
	pl:SetAvoidPlayers(true)
	pl:CrosshairDisable()
	
	-- Prevent 'mod_studio: MOVETYPE_FOLLOW with No Models error.'
	pl:DrawViewModel(false)
	
	pl.ph_prop = ents.Create("ph_prop")
	pl.ph_prop:SetPos(pl:GetPos())
	pl.ph_prop:SetAngles(pl:GetAngles())
	pl.ph_prop:Spawn()
	if GetConVar("ph_use_custom_plmodel_for_prop"):GetBool() then
		if table.HasValue(PHE.PROP_PLMODEL_BANS, string.lower(player_manager.TranslatePlayerModel(pl:GetInfo("cl_playermodel")))) then
			pl.ph_prop:SetModel("models/player/kleiner.mdl")
			pl:ChatPrint("Your custom playermodel was banned from Props.")
		elseif table.HasValue(PHE.PROP_PLMODEL_BANS, string.lower(pl:GetInfo("cl_playermodel"))) then
			pl.ph_prop:SetModel("models/player/kleiner.mdl")
			pl:ChatPrint("Your custom playermodel was banned from Props.")
		else
			pl.ph_prop:SetModel(player_manager.TranslatePlayerModel(pl:GetInfo("cl_playermodel")))
		end
	end
	pl.ph_prop:SetSolid(SOLID_BBOX)
	if !GetConVar("ph_better_prop_movement"):GetBool() then
		pl.ph_prop:SetParent(pl)
	end
	pl.ph_prop:SetOwner(pl)
	pl:SetNWEntity("PlayerPropEntity", pl.ph_prop)
	
	if GetConVar("ph_better_prop_movement"):GetBool() then
		-- Give it a delay
		timer.Simple(0.1, function()
			if pl:IsValid() then
				umsg.Start("ClientPropSpawn", pl)
				umsg.End()
			end
		end)
	end

	timer.Simple(0.1, function()
		if pl:IsValid() then
			umsg.Start("AutoTauntSpawn")
			umsg.End()
		end
	end)

	pl.ph_prop.max_health = 100
end


-- Hands
function CLASS:GetHandsModel()
	return
end


-- Called when a player dies with this class
function CLASS:OnDeath(pl, attacker, dmginfo)
	pl:RemoveProp()
	pl:RemoveClientProp()
end


-- Register
player_class.Register("Prop", CLASS)