include("sh_init.lua")
include("sh_config.lua")
CL_GLOBAL_LIGHT_STATE = 0
include("cl_hud_mask.lua")
include("cl_hud.lua")
include("cl_menu.lua")
include("cl_tauntwindow.lua")
include("cl_targetid.lua")
include("cl_autotaunt.lua")

include("cl_credits.lua")

overlaydraw = 0

-- Called immediately after starting the gamemode 
function Initialize()
	hullz 	= 80
	client_prop_light = false
	blind = false
	
	CreateClientConVar("ph_cl_halos", "1", true, true, "Toggle Enable/Disable Halo effects when choosing a prop.")
	CreateClientConVar("ph_cl_pltext", "1", true, false, "Options for Text above players. 0 = Disable. 1 = Enable.")
	CreateClientConVar("ph_cl_endround_sound", "1", true, false, "Play a sound when round ends? 0 to disable.")
	CreateClientConVar("ph_cl_autoclose_taunt", "1", true, false, "Auto close the taunt window (When Double Clicking on them)?")
	CreateClientConVar("ph_cl_spec_hunter_line", "1", true, false, "Draw a line on hunters so we can see their aim in spectator mode.")
	CreateClientConVar("cl_enable_luckyballs_icon", "1", true,false, "Enable 'Lucky ball' icon to be displayed once they spawned")
	CreateClientConVar("ph_hud_use_new", "1", true, false, "Use new PH: Enhanced HUD")
	CreateClientConVar("ph_show_team_topbar", "1", true, false, "Show total alive team players bar on the top left (Experimental)")
	
	CL_GLIMPCAM 	= 0
	MAT_LASERDOT 	= Material("sprites/glow04_noz")
	
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

-- Decides where  the player view should be (forces third person for props)
local CurEnt
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

			local filterent = ents.FindByClass("ph_prop")
			table.insert(filterent, pl)
			
			CurEnt = LocalPlayer():GetPlayerPropEntity()
			
			if IsValid(CurEnt) && math.Round(CurEnt:OBBMaxs().z) <= 20 then			
				trace.start = origin + Vector(0, 0, -20)
				trace.endpos = origin + Vector(0, 0, -20) + (angles:Forward() * -80)
			else
				trace.start = origin + Vector(0, 0, hullz - 60)
				trace.endpos = origin + Vector(0, 0, hullz - 60) + (angles:Forward() * -80)
			end
			
			trace.filter = filterent
			
			local tr = util.TraceLine(trace)
			view.origin = tr.HitPos
		else
			view.origin = origin + Vector(0, 0, hullz - 60) + (angles:Forward() * -80)
		end
	elseif pl:Team() == TEAM_HUNTERS && pl:Alive() then
	 	local wep = pl:GetActiveWeapon() 
	 	if wep && wep != NULL then 
	 		local func = wep.GetViewModelPosition 
	 		if func then 
	 			view.vm_origin, view.vm_angles = func(wep, origin*1, angles*1)
	 		end
	 		 
	 		local func = wep.CalcView 
	 		if func then 
	 			view.origin, view.angles, view.fov = func(wep, pl, origin*1, angles*1, fov)
	 		end 
	 	end
		-- hunter glimpse of thirdperson
		if CL_GLIMPCAM > CurTime() then
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

local mat = Material("prophunt_enhanced/sprites/luckyball")
-- Draw round timeleft and hunter release timeleft
function HUDPaint()
local ply = LocalPlayer()
	-- Draw player texts
	if GetConVar("ph_enable_plnames"):GetBool() && GetConVar("ph_cl_pltext"):GetBool() && LocalPlayer():Team() != TEAM_SPECTATOR then
		for _, pl in pairs(player.GetAll()) do
			if pl != LocalPlayer() && (pl && pl:IsValid() && pl:Alive() && pl:Team() == LocalPlayer():Team()) then
				local addvector = Vector(0, 0, math.Clamp(pl:EyePos():Distance(LocalPlayer():EyePos())*0.04, 16, 64))
				-- todo: text will disappear in a specified distance.
				draw.DrawText(pl:Name().." ("..pl:Health().."%)", "TargetIDSmall", (pl:EyePos() + addvector):ToScreen().x, (pl:EyePos() + addvector):ToScreen().y, team.GetColor(pl:Team()), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		end
	end
	
	-- Hunter Blindlock Time
	if GetGlobalBool("InRound", false) then
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
	
	-- Draw Lucky Balls Icon
	if GetConVar("cl_enable_luckyballs_icon"):GetBool() then
		local offset = Vector( 0, 0, 45 )
		local ang = LocalPlayer():EyeAngles()
		cam.Start3D()
			for _,ent in pairs(ents.FindByClass('ph_luckyball')) do
				local pos = ent:GetPos() + offset + ang:Up()
				
				ang:RotateAroundAxis( ang:Forward(), 90 )
				ang:RotateAroundAxis( ang:Right(), 90 )
				
				if LocalPlayer():Alive() && LocalPlayer():IsLineOfSightClear(ent) then
					
					local PlayerEntPos = math.floor(LocalPlayer():GetPos():Distance(ent:GetPos()))
					local w,h = 16,16
					
					if PlayerEntPos <= 100 then
						w = 16
						h = 16
					else
						w = 16 * (PlayerEntPos*0.01)
						h = 16 * (PlayerEntPos*0.01)
					end
					
					render.SetMaterial(mat)
					render.DrawSprite(pos,w,h,color_white)
				end
			end
		cam.End3D()
	end
	
	-- The 'You were Killed By' text, or the Freeze Cam text.
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

-- After the player has been drawn
function PH_PostPlayerDraw(pl)
	-- Draw a line on hunters
	if GetConVar("ph_cl_spec_hunter_line"):GetBool() && (!LocalPlayer():Alive() || LocalPlayer():Team() == TEAM_SPECTATOR) then
		if IsValid(pl) && pl:Alive() && pl:Team() == TEAM_HUNTERS then
			render.DrawLine(pl:GetShootPos(), pl:GetEyeTrace().HitPos, team.GetColor(pl:Team()), true)
			render.SetMaterial(MAT_LASERDOT)
			render.DrawSprite(pl:GetEyeTrace().HitPos, 8, 8, team.GetColor(pl:Team()))
		end
	end
end
hook.Add("PostPlayerDraw", "PH_PostPlayerDraw", PH_PostPlayerDraw)

hook.Add("PrePlayerDraw", "PHE.HidePlayer", function(ply)
	if ply:Team() == TEAM_PROPS then return true end
end)

-- Draws halos on team members
function PHEDrawPropselectHalos()

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
			trace.filter = ents.FindByClass("ph_prop")
			
			local trace2 = util.TraceLine(trace) 
			if trace2.Entity && trace2.Entity:IsValid() && table.HasValue(PHE.USABLE_PROP_ENTITIES, trace2.Entity:GetClass()) then
				local ent_table = {}
				table.insert(ent_table, trace2.Entity)
				halo.Add(ent_table, Color(20, 250, 0), 1.2, 1.2, 1, true, true)
			end
		end
		
	end
end
hook.Add("PreDrawHalos", "PHEDrawPropselectHalos", PHEDrawPropselectHalos)

-- the 'Accurate' prop disguise and Play random taunt.
hook.Add("KeyPress", "tracetest.GetPropInfo", function(pl,key)
	if ((pl:Team() == TEAM_PROPS && pl:Alive()) && key == IN_ATTACK) then	
		local trace = {}
		if hullz < 25 then
			trace.start = LocalPlayer():EyePos() + Vector(0, 0, hullz - 30)
			trace.endpos = LocalPlayer():EyePos() + Vector(0, 0, hullz - 30) + LocalPlayer():EyeAngles():Forward() * 100 -- 100 Hammer units.
		else
			trace.start = LocalPlayer():EyePos() + Vector(0, 0, hullz - 60)
			trace.endpos = LocalPlayer():EyePos() + Vector(0, 0, hullz - 60) + LocalPlayer():EyeAngles():Forward() * 100
		end
		trace.filter = ents.FindByClass("ph_prop")
		
		local trace2 = util.TraceLine(trace) 
		if trace2.Entity && trace2.Entity:IsValid() && table.HasValue(PHE.USABLE_PROP_ENTITIES, trace2.Entity:GetClass()) then
			net.Start("CL2SV_ExchangeProp")
			net.WriteEntity(trace2.Entity)
			net.SendToServer()
		end
	end
	
	if ((pl:Team() == TEAM_PROPS && pl:Alive()) && key == IN_ATTACK2) then
		LocalPlayer():ConCommand("gm_showspare1")
	end
end)

-- Called every client frame
function GM:Think()
	-- Prop light
	if client_prop_light && LocalPlayer() && LocalPlayer():IsValid() && LocalPlayer():Alive() && LocalPlayer():Team() == TEAM_PROPS then
		local prop_light = DynamicLight(LocalPlayer():EntIndex())
		if prop_light then
			prop_light.pos = LocalPlayer():GetPos()
			prop_light.r = 255
			prop_light.g = 255
			prop_light.b = 255
			prop_light.brightness = 0.25
			prop_light.decay = 1
			prop_light.size = 180
			prop_light.dietime = CurTime() + 0.1
		end
	end	
end

-- ///////////////////\\\\\\\\\\\\\\\\\ --
-- 			Net Receives Hooks 			--
-- ///////////////////\\\\\\\\\\\\\\\\\ --

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

-- Resets the player hull
net.Receive("ResetHull", function()
	if LocalPlayer() && LocalPlayer():IsValid() then
		LocalPlayer():ResetHull()
		hullz = 80
	end
end)

-- Sets the local blind variable to be used in CalcView
net.Receive("SetBlind", function()
	blind = net.ReadBool()
end)

--[[ Here you can add more than 2 additional freeze cam sounds. 
You can add more sounds by using table.insert(PHE.FreezeCamSnd, <path file>) repeatedly outside of this code scope.
Example:
	table.insert(PHE.FreezeCamSnd, "vo/k_lab/kl_fiddlesticks.wav")
	table.insert(PHE.FreezeCamSnd, "vo/k_lab/kl_ohdear.wav")
	...more ]]
	
-- If you wish to use a single sound instead, use ph_fc_use_single_sound 1 & ph_fc_cue_path "<path/sound/file.wav>" convar to override.

PHE.FreezeCamSnd = {
	-- do not manually add sounds in here, which this may break the sound list. Use table.insert instead!
	"misc/freeze_cam.wav",
	"misc/freeze_cam_sad1.wav"
}
-- Plays the Freeze Cam sound
net.Receive("PlayFreezeCamSound", function()
	if GetConVar("ph_fc_use_single_sound"):GetBool() then
		surface.PlaySound(GetConVar("ph_fc_cue_path"):GetString())
	else
		surface.PlaySound(table.Random(PHE.FreezeCamSnd))
	end
end)

-- Sets the player hull
net.Receive("SetHull", function()
	local hullxy = net.ReadInt(32)
	local hullz = net.ReadInt(32)
	local hulldz = net.ReadInt(32)
	local new_health = net.ReadInt(9)
	
	LocalPlayer():SetHull(Vector(hullxy * -1, hullxy * -1, 0), Vector(hullxy, hullxy, hullz))
	LocalPlayer():SetHullDuck(Vector(hullxy * -1, hullxy * -1, 0), Vector(hullxy, hullxy, hulldz))
	LocalPlayer():SetHealth(new_health)
end)

-- Replaces the flashlight with a client-side dynamic light for props
net.Receive("PlayerSwitchDynamicLight", function() 
	if client_prop_light then
		client_prop_light = false
		surface.PlaySound("prop_idbs/light_off1.wav")
		CL_GLOBAL_LIGHT_STATE = 0
	else
		client_prop_light = true
		surface.PlaySound("prop_idbs/light_on.wav")
		CL_GLOBAL_LIGHT_STATE = 1
	end
end)

-- Turns the dynamic light OFF
net.Receive("DisableDynamicLight", function()
	if client_prop_light then
		client_prop_light = false
	end
end)