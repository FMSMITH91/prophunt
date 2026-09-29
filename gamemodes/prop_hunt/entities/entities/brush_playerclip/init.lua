-- Credit to Awesome guy: D4UNKN0WNMAN :D
-- Had to place this entity for ph_kleiner maps. for purpose: Anti Exploiting.

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

function ENT:Initialize()
	-- Callers may give the corners in any order, and a box with mins > maxs on
	-- any axis never collides. Order copies: OrderVectors swaps in place.
	local mins, maxs = Vector(self.min), Vector(self.max)
	OrderVectors(mins, maxs)
	
	local w = maxs.x - mins.x
	local l = maxs.y - mins.y
	local h = maxs.z - mins.z
	
	local min = Vector(0 - (w / 2), 0 - (l / 2), 0 - (h / 2))
	local max = Vector(w / 2, l / 2, h / 2) 
	
	self:DrawShadow(false)
	self:SetCollisionBounds(min, max)
	self:SetSolid(SOLID_BBOX)
	self:SetNoDraw(true)
	self:SetCollisionGroup(COLLISION_GROUP_NONE)
	self:SetMoveType(0)
	self:SetTrigger(false)
end