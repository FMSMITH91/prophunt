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
	
	pl.ph_prop = ents.Create("ph_prop")
	pl.ph_prop:SetPos(pl:GetPos())
	pl.ph_prop:SetAngles(pl:GetAngles())
	pl.ph_prop:Spawn()
	pl.ph_prop:SetSolid(SOLID_BBOX)
	if !GetConVar("ph_better_prop_movement"):GetBool() then
		pl.ph_prop:SetParent(pl)
	end
	pl.ph_prop:SetOwner(pl)
	pl:SetNWEntity("PlayerPropEntity", pl.ph_prop)
	
	if GetConVar("ph_better_prop_movement"):GetBool() then
		-- Give it a delay
		timer.Simple(0.5, function()
			umsg.Start("ClientPropSpawn", pl)
			umsg.End()
		end)
	end
	
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