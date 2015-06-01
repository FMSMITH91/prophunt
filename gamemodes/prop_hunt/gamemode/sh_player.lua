-- Finds the player meta table or terminates
local meta = FindMetaTable("Player")
if !meta then return end


-- Blinds the player by setting view out into the void
function meta:Blind(bool)
	if !self:IsValid() then return end
	
	if SERVER then
		umsg.Start("SetBlind", self)
		if bool then
			umsg.Bool(true)
		else
			umsg.Bool(false)
		end
		umsg.End()
	elseif CLIENT then
		blind = bool
	end
end


-- Player has locked prop rotation?
function meta:GetPlayerLockedRot()
	return self:GetNWBool("PlayerLockedRotation", false)
end


-- Player's prop entity
function meta:GetPlayerPropEntity()
	return self:GetNWEntity("PlayerPropEntity", nil)
end


-- Removes the prop given to the player
function meta:RemoveProp()
	if CLIENT || !self:IsValid() then return end
	
	if self.ph_prop && self.ph_prop:IsValid() then
		self.ph_prop:Remove()
		self.ph_prop = nil
	end
end

function meta:RemoveClientProp()
	if CLIENT || !self:IsValid() then return end
	
	umsg.Start("RemoveClientPropUMSG", self)
	umsg.End()
end