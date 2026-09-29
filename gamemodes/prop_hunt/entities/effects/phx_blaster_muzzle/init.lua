local matBlueFlash 	= Material("Effects/blueblackflash")
local matBlueMuzzle	= Material("Effects/bluemuzzle")
matBlueMuzzle:SetInt("$spriterendermode",9) -- 8 ?

function EFFECT:Init(data)
	
	self.Ent        = data:GetEntity()
	if (not IsValid(self.Ent)) then return end
	self.Shooter	= self.Ent:GetOwner()
	if (not IsValid(self.Shooter)) then return end
	
	self.Attachment     = data:GetAttachment()
	self.WeaponEnt      = self.Ent
	self.KillTime       = 0
	self.ShouldRender   = false
	
    self.SpriteSize = 55
    self.FlashSize = 110
	
	if not IsValid(self.WeaponEnt) then return end	

	local Muzzle = 	self.WeaponEnt:GetAttachment(self.Attachment)
	if not Muzzle then return end -- e.g. error.mdl when the workshop content is missing.
	-- Vector() is (0,0,0), so `Vector()*size` padded nothing and the effect culled as a single point.
	local pad = Vector(self.SpriteSize,self.SpriteSize,self.SpriteSize)
	self:SetRenderBoundsWS(Muzzle.Pos - pad, Muzzle.Pos + pad)

	self.KillTime = CurTime() + 2
	self.ShouldRender = true

end


function EFFECT:Think()

	if (not self.KillTime) or self.KillTime == nil then return false end
	if CurTime() > self.KillTime then return false end
	if not self.Shooter then return false end
	if not IsValid(self.WeaponEnt) then return false end

	return true
	
end


function EFFECT:Render()

	if not self.ShouldRender then return end

	local Muzzle    = 	self.WeaponEnt:GetAttachment(self.Attachment)
	if not Muzzle then return end
	
	local RenderPos = Muzzle.Pos
	local pad = Vector(self.SpriteSize,self.SpriteSize,self.SpriteSize)
	self:SetRenderBoundsWS(RenderPos - pad,RenderPos + pad)

	local invintrplt = (self.KillTime - CurTime())/2
	local intrplt = 1 - invintrplt

	local size
	
	if invintrplt > 0.8 then
		render.SetMaterial(matBlueMuzzle)
		size = 2*self.FlashSize*(invintrplt - 0.5)
		local alpha = 1275*(invintrplt - 0.8)
		render.DrawSprite(RenderPos,size,size,Color(255,255,255,alpha))
	end

	render.SetMaterial(matBlueFlash)
	size = self.SpriteSize*invintrplt
	render.DrawSprite(RenderPos,size,size,Color(255,255,255,100*invintrplt))
	

end
