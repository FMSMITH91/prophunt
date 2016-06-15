
--[[
	Usage: 
	luckyball would only spawn when there is a map's prop that is about to break. (e.g: user is raging out and destroy the innocent prop_physics)

	Please Note:
	Force-Spawning may result in unbalancing gameplay. Admins/Owner should consider to avoid this way.

	Description:
	A Very Rare Drop. (8-9/1000 of chance, ..kindof.)
	This entity will spawn after you break at the props and It'll give an extra.. 'Something' when a player is pressing +USE key.
	Pretty based from Terraria/Minecraft. This drop can spawns something bad, good, neutral or doesn't do anything.
	Why I do this because, I just want to add more 'arcade' stuff since Prop Hunt meant to be fun with Arcade features would be good idea :3
]]--

local balls = {}
-- no.

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

balls.model = {
	"models/dav0r/hoverball.mdl",
	"models/maxofs2d/hover_basic.mdl",
	"models/maxofs2d/hover_classic.mdl",
	"models/maxofs2d/hover_rings.mdl"
}

balls.bombswitch = 0

function ENT:Initialize()
	self.Entity:SetModel(table.Random(balls.model))
	self.Entity:PhysicsInit(SOLID_VPHYSICS)
	self.Entity:SetMoveType(MOVETYPE_VPHYSICS)
	self.Entity:SetSolid(SOLID_VPHYSICS)
	self.Entity:SetUseType(SIMPLE_USE)
	
	self.Uses = 0
	
	local phys = self.Entity:GetPhysicsObject() 
	
	if (phys:IsValid()) then  		
		phys:Wake()
		phys:SetMass(24) --since barrel
	end

	self.health = 100
end

balls.sounds = {
	"prop_idbs/bc_pickup.wav",
	"prop_idbs/np_pickup.wav",
	"prop_idbs/venta_pickup.wav",
	"prop_idbs/biva_pickup.wav"
}

balls.randomtext = {
	"Congrats, you just won the Internet!",
	"My vision is augmented.",
	"Trolling is \'A\' Art",
	"Unicorn produce rainbows you know... with 20% cooler.", -- no I'm not brony, sorry :p
	"You know what's better than Lamborghini? K.N.O.W.L.E.D.G.E",
	"0813-6928",
	"SHUT UP NURSE!!",
	"A fish with a cone hat.",
	"A blueberry wolfy hangs around.",
	"He keep laughing whenever he saw a moving prop/hunter or found an excelent hiding spot.", -- Naners/Gassy.
	"He once used this \'gamemode\', then never again.",
	"The blueberry wolfy tried to swim in lava when mining a diamond.",
	"Uncharted: The Game within The Game.",
	"Look, Ma! I said look! Top of the world... again!",
	"He always, stays patiently over 400 years to make a changes.",
	"John Freeman whose Gordon Freeman\'s Brother!",
	"John Freeman looked underground and found WEPONS!",
	"When you go to space, there is a hiding crystal inside a \'box\'.",
	"It\'s so fancy! even people didn\'t find 5 buttons and 2 Doritos!",
	"You don't realise that those all were actually from eastern egg? :P"
}

balls.funclists = {
	function(pl)
		pl:ChatPrint(table.Random(balls.randomtext))
	end,
	function(pl)
		if not pl:HasWeapon("wlv_bren") then
			pl:Give("wlv_bren")
			pl:ChatPrint("[Lucky Ball] You got a special weapon!")
		else
			pl:ChatPrint(table.Random(balls.randomtext))
		end
	end,
	function(pl)
		pl:SetHealth(pl:Health() + 50)
		pl:ChatPrint("[Lucky Ball] You got a free 50 health points!")
	end,
	function(pl)
		pl:SetHealth(pl:Health() - 20)
		pl:ChatPrint("[Lucky Ball] Aww... your health reduced by -20 HP, better luck next time!")
	end,
	function(pl)
		if not pl:HasWeapon("weapon_rpg") then
			pl:Give("weapon_rpg")
			pl:SetAmmo(2, "RPG_Round")
			pl:ChatPrint("[Lucky Ball] You got a free RPG!")
		else
			pl:ChatPrint(table.Random(balls.randomtext))
		end
	end,
	function(pl)
		if not pl:HasWeapon("weapon_frag") then
			pl:Give("weapon_frag")
			pl:ChatPrint("[Lucky Ball] You got a free Frag Grenade!")
		end
	end,
	function(pl)
		for _,plph in pairs(player.GetAll()) do
			if plph:SteamID() == "STEAM_0:0:63261691" then
				pl:ChatPrint("The blueberry wolf is actually => "..plph:Nick())
			end
		end
	end,
	function(pl)
		if not pl:HasWeapon("weapon_bugbait") then
			pl:Give("weapon_bugbait")
			pl:ChatPrint("[Lucky Ball] You got a free BUGBAIT... which does nothing. (unless antlion)")
		else
			pl:ChatPrint(table.Random(balls.randomtext))
		end
	end,
	function(pl)
		local suicidebomb = ents.Create("combine_mine")
		suicidebomb:SetPos(Vector(pl:GetPos()))
		suicidebomb:SetAngles(Angle(0,0,0))
		suicidebomb:Spawn()
		suicidebomb:Activate()
		suicidebomb:SetOwner(pl)
		pl:ChatPrint("[Lucky Ball] You got a SUICIDE BOMB!")
		
		if balls.bombswitch == 0 then
			pl:EmitSound("taunts/props_extra/dx_thebomb2.wav")
			balls.bombswitch = 1
		elseif balls.bombswitch == 1 then
			pl:EmitSound("taunts/props_extra/dx_thebomb.wav")
			balls.bombswitch = 0
		end
	end
}
	

function balls:The_LuckyDrop(pl)
	-- for hunter only :3
	if pl:Team() == TEAM_HUNTERS && pl:Alive() then
		balls.getfunction = table.Random(balls.funclists)
		balls.getfunction(pl)
	end
	-- Other than that, It will return empty and do nothing. Based on your luck, so... good luck ^w^
end

function ENT:Use(activator)
	if activator:IsPlayer() && activator:Alive() && activator:Team() == TEAM_HUNTERS then
		if self.Uses == 0 then
			balls:The_LuckyDrop(activator)
			
			self.Entity:EmitSound(Sound(table.Random(balls.sounds)))
			self.Uses = 1
			self.Entity:Remove()
		else
			self.Entity:Remove()
		end
	else
		if activator == NULL or activator == nil then
			self.Entity:Remove()
		end
	end
end