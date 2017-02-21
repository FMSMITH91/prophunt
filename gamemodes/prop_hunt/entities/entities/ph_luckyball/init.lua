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
	"Unicorn produce rainbows you know... with 20% cooler.",
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
	"WHERE\'S THE BLACKSMITH!!", -- Whoops, these fell here (Remove them if not necessary)
	"What a shame.",
	"Knowing these lucky balls will give you something good fills you with determination.", -- Oh God XD
	"PILLS HERE!",
	":3",
	"Here's some text to occupy you.",
	"Have you seen the NannerMan?",
	"I once saw a man with green septic eyes.",
	"I once saw a man with a pink mustache.",
	"There was Obsidian and it had a Conflict.",
	"We all just need a bit of Synergy in our lives.",
	"sudo apt-get moo",
	"\"Have you mooed today?\"",
	"Someone could do well on the stage, we just need to find him.",
	"So much to do, so little time.", -- That was the rest of those fallen text additions
	"You don't realise that (nearly) all those were actually easter eggs? :P"
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
			pl:ChatPrint("[Lucky Ball] You got an RPG for free!")
		else
			pl:ChatPrint(table.Random(balls.randomtext))
		end
	end,
	function(pl)
		if not pl:HasWeapon("weapon_frag") then
			pl:Give("weapon_frag")
			pl:ChatPrint("[Lucky Ball] You got a Frag Grenade for free!")
		end
	end,
	function(pl)
		for _, plph in pairs(player.GetAll()) do
			if plph:SteamID() == "STEAM_0:0:63261691" then
				pl:ChatPrint("The blueberry wolf is actually => "..plph:Nick())
			end
		end
	end,
	function(pl)
		if not pl:HasWeapon("weapon_bugbait") then
			pl:Give("weapon_bugbait")
			pl:ChatPrint("[Lucky Ball] You got Bugbait for free... which does nothing (unless you have a pet antlion).")
		else
			pl:ChatPrint(table.Random(balls.randomtext))
		end
	end,
	 function(pl)  -- Change hunter model to player mdl as a joke
		 if not (pl:GetModel() == "models/player.mdl") then
			 pl:ChatPrint("[Lucky Ball] I saw it once. The player.mdl will get its revenge one day. -D4")
			 pl:SetModel("models/player.mdl")
			 pl:SendLua("CL_THIRDPERSON_TIMED = CurTime() + 3")
		 else
			 pl:ChatPrint(table.Random(balls.randomtext))
		 end
	 end,
	 function(pl)  -- This is a fun little reference to staging
		 for _, plph in pairs(player.GetAll()) do
			 if plph:SteamID() == "STEAM_0:0:49332102" && plph:Team() == TEAM_HUNTERS then
				 pl:ChatPrint("You put "..plph:Name().." on the stage.")
				 plph:SendLua("CL_THIRDPERSON_TIMED = CurTime() + 10")
				 plph:SendLua("RunConsoleCommand(\"act\", \"dance\")")
				 plph:EmitSound("taunts/props/32.mp3", 100)
			 end
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
	-- For hunter only.
	if pl:Team() == TEAM_HUNTERS && pl:Alive() then
		balls.getfunction = table.Random(balls.funclists)
		balls.getfunction(pl)
	end
	-- Other than that, It will return empty and do nothing.
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
