-- Include needed files
include("shared.lua")

-- Called every frame?
function ENT:Draw()
	if CL_BETTER_PROP_MOVEMENT then
		if (LocalPlayer():GetPlayerPropEntity() != self.Entity) then
			self.Entity:DrawModel()
			self.Entity:DrawShadow(true)
		else
			self.Entity:DrawShadow(false)
		end
	else
		self.Entity:DrawModel()
	end
end 