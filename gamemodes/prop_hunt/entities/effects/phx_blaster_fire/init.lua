
local matBulge 		= Material("Effects/strider_bulge_dudv")
local matBlueBeam	= Material("Effects/blueblacklargebeam")

-- Vector() is (0,0,0), so the old `Vector()*size` padding added nothing, and the two
-- corners were never ordered. Order them, then pad by the sprite size.
local function SetBeamRenderBounds(ent, a, b, size)
	local mins, maxs = Vector(a), Vector(b) -- copies: OrderVectors swaps in place.
	OrderVectors(mins, maxs)
	local pad = Vector(size,size,size)
	ent:SetRenderBoundsWS(mins - pad, maxs + pad)
end

function EFFECT:Init(data)
	
	self.Ent        = data:GetEntity()
	if (not IsValid(self.Ent)) then return end
	self.Shooter	= self.Ent:GetOwner()
	if (not IsValid(self.Shooter)) then return end
	
	self.EndPos         = data:GetOrigin()
	self.Attachment     = data:GetAttachment()
	self.WeaponEnt      = self.Ent
	self.KillTime       = 0
	self.ShouldRender   = false
	
	if not self.Shooter or not IsValid(self.Shooter) then return end
	if not self.WeaponEnt or not IsValid(self.WeaponEnt) then return end
	
	self.BeamWidth      = 32

	local Muzzle    = 	self.WeaponEnt:GetAttachment(self.Attachment)
	if not Muzzle then return end -- e.g. error.mdl when the workshop content is missing.
	
	self.RenderAng  = Muzzle.Pos - self.EndPos 
	self.RenderDist = self.RenderAng:Length()
	self.RenderAng  = self.RenderAng/self.RenderDist
	
	self.Duration   = self.RenderDist/8000
	self.KillTime   = CurTime() + self.Duration
	
	SetBeamRenderBounds(self, Muzzle.Pos, self.EndPos, 280)
	
	self.ShouldRender = true

end


function EFFECT:Think()
	
	if (not self.KillTime) or self.KillTime == nil then return false end
	if CurTime() > self.KillTime then return false end
	if (not IsValid(self.Ent)) then return end
	if (not IsValid(self.Shooter)) then return end
	return true
	
end


function EFFECT:Render()

	if not self.ShouldRender then return end
	
	local invintrplt    = (self.KillTime - CurTime())/self.Duration
	local intrplt       = 1 - invintrplt
	
	local RenderPos     = self.EndPos + self.RenderAng*(self.RenderDist*invintrplt)
	SetBeamRenderBounds(self, RenderPos, self.EndPos, 280)
	
	matBulge:SetFloat("$refractamount", 0.16)
	render.SetMaterial(matBulge)
	render.UpdateRefractTexture()
	render.DrawSprite(RenderPos,280,280,Color(255,255,255,150))
	
	render.SetMaterial(matBlueBeam)
	render.DrawBeam(RenderPos,self.EndPos,self.BeamWidth,0,0,Color(255, 255, 255, 160))
	
end
