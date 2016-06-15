local Ph = {}

-- Warning: May Clutter as fuck... yiff, anything!

Ph.txthelp = [[Welcome to Enhanced Prop Hunt!
Prop Hunt is a twist on the classic backyard game Hide and Seek.

More information can be found at [F1] Button.

Both teams can press [F3] to play a taunt sound, with some extra taunts addition.

Additionaly, there are more features with this Gamemode :
  - Added new 'Lucky Ball' system: Break any Non-Player props to get the lucky ball. There is ~1% chance to get the drops.
    The effects can be good, bad, or neutral luck. Doesn't apply for killing any Player Props.
    The more players/props in current map, the more lucky ball drops can be obtained!
  - Added new Player model selection (Server side: admins can enable/disable this feature.)
  - Added new Props Player model (based Hunter's Player model too (make sure admin has enabled this))
  - Added new Player Lists/Mute Options.
  - And much more!

Have fun!
]]

function ph_BaseMainWindow(ply, cmd, args)
	-- init
	local mdlName = ply:GetInfo("cl_playermodel")
	local mdlPath = player_manager.TranslatePlayerModel (mdlName)
	
	-- basic window properties
	local frm = vgui.Create("DFrame")
	frm:SetSize(865,500)
	frm:SetTitle("Prop Hunt: Enhanced | More Menus")
	frm:Center()
	frm:MakePopup()
	
	-- tabs
	local tab = vgui.Create("DPropertySheet", frm)
	tab:Dock(FILL)
	
	function Ph:HelpSelections()
		local panel = vgui.Create("DPanel", tab)
		panel:SetBackgroundColor(Color(100,100,100,255))
	
		local lblhelp = vgui.Create("DLabel", panel)
		lblhelp:SetPos(15,10)
		lblhelp:SetSize(850,250)
		lblhelp:SetFont("HudHintTextLarge")
		lblhelp:SetTextColor(Color(230,230,230,255))
		lblhelp:SetText(Ph.txthelp)
		
		local butt = vgui.Create("DButton", panel)
		butt:SetPos(15,254)
		butt:SetSize(128,32)
		butt:SetText("Server Rules/MOTD")
		butt.DoClick = function()
			ply:ConCommand("ulx motd")
			frm:Close()
		end
		
		function Ph:LuckyBallPreview(mdlpath,xpos)
			local pn = vgui.Create("DPanel", panel) --yodawg
			pn:SetPos(xpos,300)
			pn:SetSize(64,64)
			pn:SetBackgroundColor(Color(40,40,40,255))
			
			local prevw = vgui.Create( "DModelPanel", panel )
			prevw:SetPos(xpos,300)
			prevw:SetSize(64,64)
			prevw:SetFOV(18)
			prevw:SetModel(mdlpath)
			prevw.Entity:SetPos(Vector(0,0,40)) --this is magic
		end
		
		Ph.luckyballprevpos = {
			{ "models/dav0r/hoverball.mdl", 20 },
			{ "models/maxofs2d/hover_basic.mdl", 100 },
			{ "models/maxofs2d/hover_classic.mdl", 180 },
			{ "models/maxofs2d/hover_rings.mdl", 260 }
		}
		
		for k,v in pairs(Ph.luckyballprevpos) do
			Ph:LuckyBallPreview(v[1],v[2])
		end
		
			local txtpv = vgui.Create("DLabel", panel)
			txtpv:SetPos(20,365)
			txtpv:SetSize(500,48)
			txtpv:SetText("Here\'s the preview of Lucky Balls in case if you didn\'t know. These ball have 4 good/3 bad drops.\nYou can obtain these ball by pressing [E] or (+Use) button.\nThe neutral drops may contains some \'familiar\' quotes or they might often do nothing.")
		
		tab:AddSheet("Help", panel, "icon16/help.png")
	end
	
	function Ph:PlayerModelSelections()
		local panel = vgui.Create("DPanel", tab)
		panel:SetBackgroundColor(Color(100,100,100,255))
		
		-- Prefer had to do this instead doing all over and over.
		function Ph:PlayerModelAdditions()
		
			-- the Model's DPanel preview. The Pos & Size must be similar as the ModelPreview.
			local panelpreview = vgui.Create( "DPanel", panel )
			panelpreview:SetPos ( 500, 5 )
			panelpreview:SetSize ( 336, 420 )
			
			-- Model Preview.
			local modelPreview = vgui.Create( "DModelPanel", panel )
			modelPreview:SetPos ( 500, 5 )
			modelPreview:SetSize ( 336, 420 )
			modelPreview:SetFOV ( 50 )
			modelPreview:SetModel ( mdlPath )
			
			-- Scroll used for DGrid below. (strangely, using :EnableHorizontalScrolling() seems bugged?)
			local scroll = vgui.Create( "DScrollPanel", panel )
			scroll:SetSize( 495, 420 )
			scroll:SetPos( 2, 5 )
			
			-- ^dito, grid dimensions 66x66 w/ Coloumn 7.
			local pnl = vgui.Create( "DGrid", scroll )
			pnl:SetPos ( 0, 5 )
			pnl:SetCols( 7 )
			pnl:SetColWide( 66 )
			pnl:SetRowHeight( 66 )
			
			-- Get All Valid Paired Models and sort 'em out.
			for name, model in SortedPairs( player_manager.AllValidModels() ) do
				
				-- dont forget to cache.
				util.PrecacheModel(model)
				
				local icon = vgui.Create( "SpawnIcon" )
				
				-- Click functions
				icon.DoClick = function()
					surface.PlaySound( "buttons/combine_button3.wav" )
					-- Run following commands after a user click on the models.
					RunConsoleCommand( "cl_playermodel", name )
					modelPreview:SetModel(model)
					Derma_Query("Model " .. name.. " has been selected and it will be applied after next respawn!", "Model Applied",
						"OK", function() end)
				end
				
				-- Right click functions
				icon.DoRightClick = function()
					-- Same as above, but they has custom menus once user tries to right click on the models.
					local menu = DermaMenu()
					-- if user caught it says 'ERROR' but the model present, refresh it (:RebuildSpawnIcon)
					--[[ Unfortunately, I noticed some models, e.g: Gaben Playermodel (for example) shows as error instead in SpawnIcons,
					   but it still present and working on model preview (Assume the DModelPanel.)
					   There is no workaround/fix for that (since this seems a Garry's Mod Error)
					   unless to report this glitch to github Garry's Mod Issues. ]]
					menu:AddOption( "Refresh Icon", function() icon:RebuildSpawnIcon() end)
					menu:AddOption( "Preview", function() modelPreview:SetModel(model) end)
					menu:AddOption( "Model Information", function()
						Derma_Message( "Model's name is: " .. name .. "\n \nUsable by: Everyone.", "Model Info", "Close" )
						end )
					menu:AddOption( "Close" )
					menu:Open()
				end
				
				-- Make sure the user has noticed after choosing a model by indicating from "Borders".
				icon.PaintOver = function() 
					if ( GetConVarString( "cl_playermodel" ) == name ) then 
						surface.SetDrawColor( Color( 255, 210 + math.sin(RealTime()*10)*40, 0 ) )
						surface.DrawOutlinedRect( 4, 4, icon:GetWide()-8, icon:GetTall()-8 )
						surface.DrawOutlinedRect( 3, 3, icon:GetWide()-6, icon:GetTall()-6 ) 
					end
				end
				
				-- Set set etc...
				icon:SetModel(model)
				icon:SetSize(64,64)
				icon:SetTooltip(name)
				
				pnl:AddItem(icon)
			end
			return pnl
		end
		
		-- Self Explanationary.
		if !GetConVar("ph_use_custom_plmodel"):GetBool() then
		
			local lblno = vgui.Create("DLabel", panel)
			lblno:SetPos(10,8)
			lblno:SetSize(300,40)
			lblno:SetText("Sorry, Custom Player Model is disabled on this server!")
			
			tab:AddSheet("Player Model", panel, "icon16/brick.png")
		else
			-- Call the VGUI Properties of PlayerModelAdditions().
			Ph:PlayerModelAdditions()
			
			tab:AddSheet("Player Model", panel, "icon16/brick.png")
		end
	end
	
	function Ph:PlayerMuteFunction()
		-- I'll use ol' method in ULX instead. If you want to enhance in a nice way, let me know if you have done it.
		local panel = vgui.Create("DPanel", tab)
		panel:SetBackgroundColor(Color(100,100,100,255))
		
		-- button.
		local btn = vgui.Create("DButton", panel)
		btn:SetText("Show Menu")
		btn:SetPos(10,5)
		btn:SetSize(128,32)
		btn.DoClick = function()
			ply:ConCommand("xgui")
			frm:Close()
		end
		
		local txt = vgui.Create("DLabel", panel)
		txt:SetText("Use ULX Menu and go to Mute Players to see available mute options.\n\nNote: You can\'t mute admins or moderators!")
		txt:SetPos(10,30)
		txt:SetSize(400,64)
	
	tab:AddSheet("Players", panel, "icon16/user_orange.png")
	end
	
	-- Call All Functions, but Admin (must check by serverside user rights from sv_admin.lua)
	Ph:HelpSelections()
	Ph:PlayerMuteFunction()
	Ph:PlayerModelSelections()
	
	-- Just quick simple menu instead making copy paste all over again.
	function Ph:CreateSimpleMenu(checkname, chkposy, cmd, parentui)
		local chk = vgui.Create("DCheckBox", parentui)
		local txt = vgui.Create("DLabel", parentui)
		local numval = GetConVar(cmd):GetBool()
		if numval == true then
			chk:SetChecked(true)
			chk:SetValue(1)
		else
			chk:SetChecked(false)
			chk:SetValue(0)
		end
		chk:SetSize(16, 16)
		chk:SetPos(20, chkposy) -- CheckBox Pos "Y"
		function chk:OnChange(bool)
			local val = 0
			if bool == true then
				val = 1
			else
				val = 0
			end
			net.Start("SvCommandReq")
			net.WriteString(cmd)
			net.WriteString(tostring(val))
			net.SendToServer()
		end
		
		txt:SetText(checkname)
		txt:SetSize(400,32)
		txt:SetPos(40, chkposy - 9)
	end
	
	Ph.CheckBoxes = {
		{"Allow custom models for Hunters?", 20, "ph_use_custom_plmodel"},
		{"Allow custom models for Props? (Make sure to enable for Hunter too!)", 40, "ph_use_custom_plmodel_for_prop"},
		{"Enable Prop Camera Collissions?", 60, "ph_prop_camera_collisions"},
		{"Enable Freezecam?", 80, "ph_freezecam"},
		{"Enable Prop Collission?", 100, "ph_prop_collision"},
		{"Enable Random Additional Models?", 120, "ph_prop_additional_models"},
		{"Swap Teams Everyround? (Keep this remain checked)", 140, "ph_swap_teams_every_round"}
	}
	
	function Ph:ShowAdminMenu()
		local panel = vgui.Create("DPanel", tab)
		panel:SetBackgroundColor(Color(100,100,100,255))
		
		for k,v in pairs(Ph.CheckBoxes) do
			-- Args: Name, Chekbox's Pos, Commands, ParentPanel
			Ph:CreateSimpleMenu(v[1], v[2], v[3], panel)
		end
		
		local buttadmin = vgui.Create("DButton", panel)
		buttadmin:SetPos(15,200)
		buttadmin:SetSize(128,24)
		buttadmin:SetText("Call MapVote")
		buttadmin.DoClick = function()
			ply:ConCommand("mapvote")
			frm:Close()
		end
		
		local buttadmin2 = vgui.Create("DButton", panel)
		buttadmin2:SetPos(148,200)
		buttadmin2:SetSize(128,24)
		buttadmin2:SetText("Stop MapVote")
		buttadmin2.DoClick = function()
			ply:ConCommand("unmapvote")
			frm:Close()
		end
		
		local lblx = vgui.Create("DLabel", panel)
		lblx:SetPos(15,225)
		lblx:SetSize(400,24)
		lblx:SetText("* Make sure you have \'MapVote Fretta-like\' addon installed!")
	
	tab:AddSheet("Admins", panel, "icon16/user_gray.png")
	end
	
	-- if Current User is Admin then check their user as security measure in the server.
	if ply:IsAdmin() then
		net.Start("CheckAdminFirst")
		net.SendToServer()
	end
	
	-- if Current User Passes the admin check, shows the admin tab.
	net.Receive("CheckAdminResult", function(len, pln)
		Ph:ShowAdminMenu()
	end)
end
concommand.Add("ph_enhanced_show_help", ph_BaseMainWindow, nil, "Show Prop Hunt: Enhanced Main and Help menus." )

--[[
	I realise that I didn't use any VGUI Register. Welp, I'm not lazy but I just make it bit complex but, if you want any enhance
	in good way, feel free to modify and let me know that you have done it.
]]