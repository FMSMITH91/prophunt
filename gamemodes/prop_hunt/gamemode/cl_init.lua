include("sh_init.lua")

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
		if GetConVar("ph_prop_camera_collisions"):GetBool() then
			local trace = {}
			local TraceOffset = 2

			trace.start = origin + Vector(0, 0, hullz - 60)
			trace.endpos = origin + Vector(0, 0, hullz - 60) + (angles:Forward() * -80)
			trace.filter = player.GetAll() && ents.FindByClass("ph_prop")
			trace.mins = Vector(-TraceOffset, -TraceOffset, -TraceOffset)
			trace.maxs = Vector(TraceOffset, TraceOffset, TraceOffset)
			local tr = util.TraceHull(trace)

			view.origin = tr.HitPos
		else
			view.origin = origin + Vector(0, 0, hullz - 60) + (angles:Forward() * -80)
		end
	else
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
	end
 	
 	return view 
end


-- Draw round timeleft and hunter release timeleft
function HUDPaint()
	if GetGlobalBool("InRound", false) then
		-- local blindlock_time_left = (HUNTER_BLINDLOCK_TIME - (CurTime() - GetGlobalFloat("RoundStartTime", 0))) + 1
		local blindlock_time_left = (GetConVarNumber("ph_hunter_blindlock_time") - (CurTime() - GetGlobalFloat("RoundStartTime", 0))) + 1
		
		if blindlock_time_left < 1 && blindlock_time_left > -6 then
			blindlock_time_left_msg = "Ready or not, here we come!"
		elseif blindlock_time_left > 0 then
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


-- Called immediately after starting the gamemode 
function Initialize()
	hullz = 80
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


-- Plays the Freeze Cam sound
function PlayFreezeCamSound(um)
	surface.PlaySound("misc/freeze_cam.wav")
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
	-- client_prop_model = ents.CreateClientProp(LocalPlayer():GetPlayerPropEntity():GetModel())
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
		if GetConVar("ph_better_prop_movement"):GetBool() then
			if LocalPlayer() && LocalPlayer():IsValid() && LocalPlayer():Alive() && LocalPlayer():GetPlayerPropEntity() && LocalPlayer():GetPlayerPropEntity():IsValid() && client_prop_model && client_prop_model:IsValid() then
				client_prop_model:SetPos(LocalPlayer():GetPos() - Vector(0, 0, LocalPlayer():GetPlayerPropEntity():OBBMins().z))
				client_prop_model:SetModel(LocalPlayer():GetPlayerPropEntity():GetModel())
				client_prop_model:SetAngles(LocalPlayer():GetPlayerPropEntity():GetAngles())
			end
		end
	end
end