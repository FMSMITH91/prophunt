AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

ENT.model = Model("models/props_idbs/phenhanced/devil.mdl")

function ENT:StartTeslaSpark()
	timer.Create("DoTeslaSpark-"..self:EntIndex(),math.random(3,6),0,function()
		self:ShowEffects(self, "StunstickImpact", self:GetPos(), self:GetPos())
	end)
end

function ENT:StopTeslaSpark()
	if timer.Exists("DoTeslaSpark-"..self:EntIndex()) then
		timer.Remove("DoTeslaSpark-"..self:EntIndex())
	end
end

function ENT:Initialize()
	self:SetModel(self.model)
	self:PhysicsInit(SOLID_BBOX)
	self:SetMoveType(MOVETYPE_NONE)
	self:SetSolid(SOLID_BBOX)
	self:SetUseType(SIMPLE_USE)
	self:SetHealth(50)
	
	-- Spawn a Sprite, for an Effect.
	self.Sprite = ents.Create("env_sprite")
	self.Sprite:SetPos(self:GetPos())
	self.Sprite:SetAngles(Angle(0,0,0))
	self.Sprite:SetKeyValue("spawnflags","1")
	self.Sprite:SetKeyValue("framerate","1")
	self.Sprite:SetKeyValue("rendermode","5")
	self.Sprite:SetKeyValue("rendercolor","255 "..tostring(math.random(1,180)).." "..tostring(math.random(1,20)))
	self.Sprite:SetKeyValue("model","sprites/light_glow01.vmt")
	self.Sprite:SetKeyValue("scale","0.4")
	
	self.Sprite:Spawn()
	self.Sprite:Activate()
	
	self.Sprite:SetParent(self)
	
	self:StartTeslaSpark()
end

function ENT:OnRemove()
	self:StopTeslaSpark()
	if IsValid(self.Sprite) then
		self.Sprite:Remove()
	end
end

ENT.sounds = {
	"prop_idbs/huntep4_bc44_pickup.wav",
	"prop_idbs/zavogant_pickup.wav"
}

function ENT:Use(activator)
	-- Remove() only takes effect at the end of the frame; without this a second
	-- player using it in the same tick would get another item.
	if self.Consumed or self:IsMarkedForDeletion() then return end
	
	if GAMEMODE:InRound() && IsValid(activator) && activator:IsPlayer() && activator:Alive() && activator:Team() == TEAM_PROPS then
		self.Consumed = true
		
		if activator:Team() == TEAM_PROPS && activator:Alive() then
			-- The crystal is used once, so there is no previous item to avoid.
			local item = PHX.DEVIL_BALL.Items[math.random(1, #PHX.DEVIL_BALL.Items)]
			item(activator,self)
			
			hook.Call("PH_OnDevilBallPickup", nil, activator)
		end
		
		self:ShowEffects(self, "GlassImpact", self:GetPos(), self:GetPos())
		self:EmitSound(Sound(self.sounds[math.random(1,#self.sounds)]),60)
		self:Remove()
	end
end

function ENT:OnTakeDamage(dmg)
	if self.Consumed or self:IsMarkedForDeletion() then return end
	
	local hit = dmg:GetDamage()
	
	self:SetHealth( self:Health() - hit )
	
	if self:Health() <= 0 then
		self.Consumed = true
		self:EmitSound(Sound("physics/glass/glass_cup_break"..math.random(1,2)..".wav"))
		self:ShowEffects(self, "GlassImpact", self:GetPos(), self:GetPos())
		self:Remove()
	end
end