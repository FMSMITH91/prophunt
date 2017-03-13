-- Include these
include("sh_init.lua")

include("cl_menu.lua")
include("cl_tauntwindow.lua")
include("cl_mutewindow.lua")
include("cl_targetid.lua")

overlaydraw = 0

-- Convars are bad at networking sometimes
CL_BETTER_PROP_MOVEMENT = true
CL_CAMERA_COLLISIONS = false

-- Glimpse of thirdperson (Timed)
CL_THIRDPERSON_TIMED = 0

-- Serverside control of plhalos
CL_PLNAMES_SERVERENABLED = 0

-- Add some network stuff here (Warning: Dirty/Unoptimised code)
function PH_BetterPropMovement(len)
	CL_BETTER_PROP_MOVEMENT = net.ReadBool()
end
net.Receive("PH_BetterPropMovement", PH_BetterPropMovement)

function PH_CameraCollisions(len)
	CL_CAMERA_COLLISIONS = net.ReadBool()
end
net.Receive("PH_CameraCollisions", PH_CameraCollisions)

function PH_CustomTauntEnabled(len)
	PHE.CUSTOM_TAUNT_ENABLED = net.ReadInt(8)
end
net.Receive("PH_CustomTauntEnabled", PH_CustomTauntEnabled)

function PH_CustomTauntDelay(len)
	PHE.CUSTOM_TAUNT_DELAY = net.ReadInt(8)
end
net.Receive("PH_CustomTauntDelay", PH_CustomTauntDelay)

function PH_PlayerName_AboveHead(len)
	CL_PLNAMES_SERVERENABLED = net.ReadBool()
end
net.Receive("PH_PlayerName_AboveHead", PH_PlayerName_AboveHead)

-- Receive the Winning Notification
net.Receive("PH_RoundDraw_Snd", function(len)
	if GetConVar("ph_cl_endround_sound"):GetBool() then
		surface.PlaySound(table.Random(PHE.WINNINGSOUNDS["Draw"]))
	end
end)
net.Receive("PH_TeamWinning_Snd", function(len)
	local snd = net.ReadString()
	if GetConVar("ph_cl_endround_sound"):GetBool() then
		surface.PlaySound(snd)
	end
end)

-- Decides where  the player view should be (forces third person for props)
function GM:CalcView(pl, origin, angles, fov)
	local view = {} 
	
	if blind then
		view.origin = Vector(20000, 0, 0)
		view.angles = Angle(0, 0, 0)
		view.fov = fov
		
		return view
	end
	
 	view.origin = origin 
 	view.angles	= angles 
 	view.fov = fov 
 	
 	-- Give the active weapon a go at changing the viewmodel position 
	if pl:Team() == TEAM_PROPS && pl:Alive() then
		if CL_CAMERA_COLLISIONS then
			local trace = {}
			
			-- Fix camera collision bugs for smaller prop size.
			if hullz <= 32 then
				hullz = 36
			end
			
			trace.start = origin + Vector(0, 0, hullz - 60)
			trace.endpos = origin + Vector(0, 0, hullz - 60) + (angles:Forward() * -80)
			trace.filter = client_prop_model && ents.FindByClass("ph_prop")
			local tr = util.TraceLine(trace)
			
			view.origin = tr.HitPos
		else
			view.origin = origin + Vector(0, 0, hullz - 60) + (angles:Forward() * -80)
		end
	elseif pl:Team() == TEAM_HUNTERS && pl:Alive() then
		-- hunter here
	 	local wep = pl:GetActiveWeapon() 
	 	if wep && wep != NULL then 
	 		local func = wep.GetViewModelPosition 
	 		if func then 
	 			view.vm_origin, view.vm_angles = func(wep, origin*1, angles*1) -- Note: *1 to copy the object so the child function can't edit it. 
	 		end
	 		 
	 		local func = wep.CalcView 
	 		if func then 
	 			view.origin, view.angles, view.fov = func(wep, pl, origin*1, angles*1, fov) -- Note: *1 to copy the object so the child function can't edit it. 
	 		end 
	 	end
		-- hunter glimpse of thirdperson
		if CL_THIRDPERSON_TIMED > CurTime() then
			local trace = {}
			
			trace.start = origin
			trace.endpos = origin + (angles:Forward() * -80)
			trace.filter = player.GetAll()
			trace.maxs = Vector(4, 4, 4)
			trace.mins = Vector(-4, -4, -4)
			local tr = util.TraceHull(trace)
			
			view.drawviewer = true
			view.origin = tr.HitPos
		end
	end
 	
 	return view 
end


-- Draw round timeleft and hunter release timeleft
function HUDPaint()
local ply = LocalPlayer()
	-- Draw text players.
	if CL_PLNAMES_SERVERENABLED && GetConVar("ph_cl_pltext"):GetBool() then
		for _, pl in pairs(player.GetAll()) do
			if pl != LocalPlayer() && (pl && pl:IsValid() && pl:Alive() && pl:Team() == LocalPlayer():Team() && !pl:IsLineOfSightClear(LocalPlayer())) then
				if  (GetConVarNumber("ph_cl_pltext") > 0) then
					draw.DrawText(pl:Name(), "TargetID", (pl:EyePos() + Vector(0, 0, 32)):ToScreen().x, (pl:EyePos() + Vector(0, 0, 32)):ToScreen().y, team.GetColor(pl:Team()), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
			end
		end
	end
	
	if GetGlobalBool("InRound", false) then
		-- local blindlock_time_left = (HUNTER_BLINDLOCK_TIME - (CurTime() - GetGlobalFloat("RoundStartTime", 0))) + 1
		local blindlock_time_left = (GetConVarNumber("ph_hunter_blindlock_time") - (CurTime() - GetGlobalFloat("RoundStartTime", 0))) + 1
		
		if blindlock_time_left < 1 && blindlock_time_left > -6 then
			blindlock_time_left_msg = "Ready or not, here we come!"
			overlaydraw = 0
		elseif blindlock_time_left > 0 then
			if ply:Team() == TEAM_HUNTERS then
				if ply:Alive() then
					overlaydraw = 1
				else end
			end
			blindlock_time_left_msg = "Hunters will be unblinded and released in "..string.ToMinutesSeconds(blindlock_time_left)
		else
			blindlock_time_left_msg = nil
		end
		
		if blindlock_time_left_msg then
			surface.SetFont("MyFont")
			local tw, th = surface.GetTextSize(blindlock_time_left_msg)
			
			draw.RoundedBox(8, 20, 20, tw + 20, 26, Color(0, 0, 0, 75))
			draw.DrawText(blindlock_time_left_msg, "MyFont", 31, 26, Color(255, 255, 0, 255), TEXT_ALIGN_LEFT)
		end
	end
	
	-- Draw some nice text
	if LocalPlayer():GetNWBool("InFreezeCam", false) then
		local w1, h1 = surface.GetTextSize("You were killed by "..LocalPlayer():GetNWEntity("PlayerKilledByPlayerEntity", nil):Name() );
		local textx = ScrW()/2
		local steamx = (ScrW()/2) - 32
		draw.SimpleTextOutlined("You were killed by "..LocalPlayer():GetNWEntity("PlayerKilledByPlayerEntity", nil):Name(), "TrebuchetBig", textx, ScrH()*0.75, Color(255, 10, 10, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1.5, Color(0, 0, 0, 255))
	end
end
hook.Add("HUDPaint", "PH_HUDPaint", HUDPaint)

function DrawMaterial()
	if blind then
		draw.RoundedBox( 0, 0, 0, ScrW(), ScrH(), Color( 50, 50, 50, 255 ) )
	else
	end
end

hook.Add( "HUDPaintBackground", "RenderBlindOverlay", DrawMaterial )

-- Called immediately after starting the gamemode 
function Initialize()
	hullz = 80
	client_prop_light = false
	
	CreateClientConVar("ph_cl_halos", "0", true, true, "Toggle Enable/Disable Halo effects when choosing a prop.")
	--CreateClientConVar("ph_cl_plhalos", "8", true, false, "Toggle Enable/Disable Halo effects on players & disable automatically if over this limit.")
	CreateClientConVar("ph_cl_pltext", "1", true, false, "Options for Text above players. 0 = Disable. 1 = Enable.")
	CreateClientConVar("ph_cl_endround_sound", "1", true, false, "Play a sound when round ends? 0 to disable.")
	CreateClientConVar("ph_cl_autoclose_taunt", "1", true, false, "Auto close the taunt window (When Double Clicking on them)?")
	
	-- Just like the server constant
	USABLE_PROP_ENTITIES_CL = {
		"prop_physics",
		"prop_physics_multiplayer"
	}
	
	-- surface.CreateFont("Arial", 14, 1200, true, false, "ph_arial")
	surface.CreateFont( "MyFont",
	{
		font	= "Arial",
		size	= 14,
		weight	= 1200,
		antialias = true,
		underline = false
	})

	surface.CreateFont("TrebuchetBig", {
		font = "Impact",
		size = 40
	})
end
hook.Add("Initialize", "PH_Initialize", Initialize)


-- Resets the player hull
function ResetHull(um)
	if LocalPlayer() && LocalPlayer():IsValid() then
		LocalPlayer():ResetHull()
		hullz = 80
	end
end
usermessage.Hook("ResetHull", ResetHull)


-- Sets the local blind variable to be used in CalcView
function SetBlind(um)
	blind = um:ReadBool()
end
usermessage.Hook("SetBlind", SetBlind)

-- here you can add more than 2 additional freeze cam sounds. Every list ends with commas.
local rndfrz = {
	"misc/freeze_cam.wav",
	"misc/freeze_cam_sad1.wav"
}

-- Plays the Freeze Cam sound
function PlayFreezeCamSound(um)
	-- surface.PlaySound("misc/freeze_cam.wav") // if you want single Freeze Cam Sound instead 2, uncomment this, and comment below.
	surface.PlaySound(table.Random(rndfrz))
end
usermessage.Hook("PlayFreezeCamSound", PlayFreezeCamSound)


-- Sets the player hull
function SetHull(um)
	hullxy = um:ReadLong()
	hullz = um:ReadLong()
	new_health = um:ReadLong()
	
	LocalPlayer():SetHull(Vector(hullxy * -1, hullxy * -1, 0), Vector(hullxy, hullxy, hullz))
	LocalPlayer():SetHullDuck(Vector(hullxy * -1, hullxy * -1, 0), Vector(hullxy, hullxy, hullz))
	LocalPlayer():SetHealth(new_health)
end
usermessage.Hook("SetHull", SetHull)


-- Player has a client-side prop model
function ClientPropSpawn(um)
	client_prop_model = ents.CreateClientProp("models/player/kleiner.mdl")
end
usermessage.Hook("ClientPropSpawn", ClientPropSpawn)


-- Remove the client prop model
function RemoveClientPropUMSG(um)
	if client_prop_model && client_prop_model:IsValid() then
		client_prop_model:Remove()
		client_prop_model = nil
	end
end
usermessage.Hook("RemoveClientPropUMSG", RemoveClientPropUMSG)


-- Called every client frame.
function GM:Think()
	for _, pl in pairs(team.GetPlayers(TEAM_PROPS)) do
		if CL_BETTER_PROP_MOVEMENT then
			if LocalPlayer() && LocalPlayer():IsValid() && LocalPlayer():Alive() && LocalPlayer():GetPlayerPropEntity() && LocalPlayer():GetPlayerPropEntity():IsValid() && client_prop_model && client_prop_model:IsValid() then
				if client_prop_model:GetModel() == "models/player/kleiner.mdl" then
					client_prop_model:SetPos(LocalPlayer():GetPos())
				else
					client_prop_model:SetPos(LocalPlayer():GetPos() - Vector(0, 0, LocalPlayer():GetPlayerPropEntity():OBBMins().z))
				end
				client_prop_model:SetModel(LocalPlayer():GetPlayerPropEntity():GetModel())
				client_prop_model:SetAngles(LocalPlayer():GetPlayerPropEntity():GetAngles())
				client_prop_model:SetSkin(LocalPlayer():GetPlayerPropEntity():GetSkin())
			end
		end
	end
	
	if client_prop_light && LocalPlayer() && LocalPlayer():IsValid() && LocalPlayer():Alive() && LocalPlayer():Team() == TEAM_PROPS then
		local prop_light = DynamicLight(LocalPlayer():EntIndex())
		if prop_light then
			prop_light.pos = LocalPlayer():GetPos()
			prop_light.r = 255
			prop_light.g = 255
			prop_light.b = 255
			prop_light.brightness = 0.15
			prop_light.decay = 1
			prop_light.size = 128
			prop_light.dietime = CurTime() + 0.1
		end
	end
end

-- Draws halos on team members
function TeamDrawHalos()

	if GetConVar("ph_cl_halos"):GetBool() then
		-- Something to tell if the prop is selectable
		if LocalPlayer():Team() == TEAM_PROPS && LocalPlayer():Alive() then
			local trace = {}
			-- fix for smaller prop size. They should stay horizontal rather than looking straight down.
			if hullz < 25 then
				trace.start = LocalPlayer():EyePos() + Vector(0, 0, hullz - 30)
				trace.endpos = LocalPlayer():EyePos() + Vector(0, 0, hullz - 30) + LocalPlayer():EyeAngles():Forward() * 100 -- 100 Hammer units.
			else
				trace.start = LocalPlayer():EyePos() + Vector(0, 0, hullz - 60)
				trace.endpos = LocalPlayer():EyePos() + Vector(0, 0, hullz - 60) + LocalPlayer():EyeAngles():Forward() * 100
			end
			trace.filter = client_prop_model && ents.FindByClass("ph_prop")
			
			local trace2 = util.TraceLine(trace) 
			if trace2.Entity && trace2.Entity:IsValid() && table.HasValue(USABLE_PROP_ENTITIES_CL, trace2.Entity:GetClass()) then
				local ent_table = {}
				table.insert(ent_table, trace2.Entity)
				halo.Add(ent_table, Color(20, 250, 0), 1.2, 1.2, 1, true, true)
			end
		end
		
	end
end
hook.Add("PreDrawHalos", "TeamDrawHalos", TeamDrawHalos)


-- Replaces the flashlight with a client-side dynamic light for props
function PlayerSwitchDynamicLight(um)
	if client_prop_light then
		client_prop_light = false
		if IsMounted("cstrike") then
			surface.PlaySound("items/nvg_off.wav")
		end
	else
		client_prop_light = true
		if IsMounted("cstrike") then
			surface.PlaySound("items/nvg_on.wav")
		end
	end
end
usermessage.Hook("PlayerSwitchDynamicLight", PlayerSwitchDynamicLight)


-- Receive a list of usable prop entities
function ServerUsablePropsToClient(len)
	USABLE_PROP_ENTITIES_CL = net.ReadTable()
end
net.Receive("ServerUsablePropsToClient", ServerUsablePropsToClient)


-- Turns the dynamic light OFF
function DisableDynamicLight(um)
	if client_prop_light then
		client_prop_light = false
	end
end
usermessage.Hook("DisableDynamicLight", DisableDynamicLight)
