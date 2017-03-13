local Ph = {}

-- Warning: May Clutter as fuck... yiff, anything!

Ph.txthelp = [[Welcome to Prop Hunt: Enhanced! [14 H]
Shortcuts:
[F1] : Splash screen menu
[F2] : Change Team
[F3] or [C] : Play a taunt.
[R] : Lock prop rotation

Features:
  - [NEW] Added 'Wait for Players' function
  - [NEW] New mute system.
  - Fixed some minor bugs
  - Fixed ConVars that not being networked properly
  - GitHub Repo: 14h
  - Enhanced Lucky Ball system.
Have fun!
]]

function ph_BaseMainWindow(ply, cmd, args)
	-- init
	local mdlName = ply:GetInfo("cl_playermodel")
	local mdlPath = player_manager.TranslatePlayerModel (mdlName)
	
	-- basic window properties
	local frm = vgui.Create("DFrame")
	frm:SetSize(865,500)
	frm:SetTitle("Prop Hunt: Enhanced - Menus")
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
			local pn = vgui.Create("DPanel", panel)
			pn:SetPos(xpos,300)
			pn:SetSize(64,64)
			pn:SetBackgroundColor(Color(40,40,40,255))
			
			local prevw = vgui.Create( "DModelPanel", panel )
			prevw:SetPos(xpos,300)
			prevw:SetSize(64,64)
			prevw:SetFOV(18)
			prevw:SetModel(mdlpath)
			prevw.Entity:SetPos(Vector(0,0,40))
		end
		
		Ph.luckyballprevpos = {
			{ "models/dav0r/hoverball.mdl", 20 },
			{ "models/maxofs2d/hover_basic.mdl", 100 },
			{ "models/maxofs2d/hover_classic.mdl", 180 },
			{ "models/maxofs2d/hover_rings.mdl", 260 }
		}
		
		for k,v in pairs(Ph.luckyballprevpos) do
			util.PrecacheModel(v[1])
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
			
			-- this hook is intended to use for custom player model outside from PH:E Menu. (like Custom Donator Model window or something).
			hook.Call("PH_CustomPlayermdlButton", nil, panel)
			
			tab:AddSheet("Player Model", panel, "icon16/brick.png")
		else
			-- Call the VGUI Properties of PlayerModelAdditions().
			Ph:PlayerModelAdditions()
			
			tab:AddSheet("Player Model", panel, "icon16/brick.png")
		end
	end
	
	function Ph:PlayerMuteFunction()
		local panel = vgui.Create("DPanel", tab)
		panel:SetBackgroundColor(Color(100,100,100,255))
	
		local btn = vgui.Create("DButton", panel)
		btn:SetText("Mute Player")
		btn:SetPos(10,5)
		btn:SetSize(128,32)
		btn.DoClick = function()
			ply:ConCommand("ph_mute_window")
			frm:Close()
		end
		
		local txt = vgui.Create("DLabel", panel)
		txt:SetText("Show list of players that you wish to mute one of them.\n\nNote: You can\'t mute admins or moderators!\n\nPlayer Settings:")
		txt:SetPos(10,38)
		txt:SetSize(400,80)
		
		function Ph:CreateSimpleMenu_Ply(txtlabel, chkposy, cmd, notiftext, parentui)
			local chk2 = vgui.Create("DCheckBox", parentui)
			local txt2 = vgui.Create("DLabel", parentui)
			
			local numval = GetConVar(cmd):GetBool()
			if numval == true then
				chk2:SetChecked(true)
				chk2:SetValue(1)
			else
				chk2:SetChecked(false)
				chk2:SetValue(0)
			end
			chk2:SetSize(16, 16)
			chk2:SetPos(10, chkposy)
			function chk2:OnChange(bool)
				if bool == true then
					RunConsoleCommand(cmd, "1")
					notification.AddLegacy(notiftext.." has been enabled.", NOTIFY_GENERIC, 5)
					surface.PlaySound("buttons/button9.wav")
				else
					RunConsoleCommand(cmd, "0")
					notification.AddLegacy(notiftext.." has been disabled.", NOTIFY_GENERIC, 5)
					surface.PlaySound("buttons/button19.wav")
				end
			end
			
			txt2:SetText(txtlabel)
			txt2:SetSize(400,32)
			txt2:SetPos(30, chkposy - 9)
		end
		
		Ph.CheckBoxes_Ply = {
			{ "Toggle Halo effect when choosing a prop", 120, "ph_cl_halos", "Halo prop select effects" },
			{ "Show team player names above players head", 140, "ph_cl_pltext", "Player team names" },
			{ "Play sound cue when a round ends", 160, "ph_cl_endround_sound", "End round sound" },
			{ "Auto close taunt window menu (When Double Clicking them)", 180, "ph_cl_autoclose_taunt", "Auto close taunt window function" }
		}
	
		for k,v in pairs(Ph.CheckBoxes_Ply) do
			Ph:CreateSimpleMenu_Ply(v[1], v[2], v[3], v[4], panel)
		end
		
	tab:AddSheet("Player", panel, "icon16/user_orange.png")
	end
	
	-- Call All Functions, but Admin (must check by serverside user rights from sv_admin.lua)
	Ph:HelpSelections()
	Ph:PlayerMuteFunction()
	Ph:PlayerModelSelections()
	
	-- Custom Hook Menu here. Give 1 second for better safe-calling...
	timer.Simple(1, function()
		hook.Call("PH_CustomTabMenu", nil, tab)
	end)
	
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
		{"Swap Teams Everyround? (Keep this remain checked)", 120, "ph_swap_teams_every_round"},
		-- {"Enable Custom Taunts?", 140, "ph_enable_custom_taunts"}
		{"Enable Lucky Balls?", 140, "ph_enable_lucky_balls"},
		{"Allow Player Team Names appear through wall?", 160, "ph_enable_plnames"},
		{"Wait for Players?", 180, "ph_waitforplayers"}
	}
	
	function Ph:ShowAdminMenu()
		local panel = vgui.Create("DPanel", tab)
		panel:SetBackgroundColor(Color(100,100,100,255))
		
		for k,v in pairs(Ph.CheckBoxes) do
			-- Args: Name, Chekbox's Pos, Commands, ParentPanel
			Ph:CreateSimpleMenu(v[1], v[2], v[3], panel)
		end
		
		local slider = vgui.Create("DNumSlider", panel)
		slider:SetPos(40,191)
		slider:SetSize(250,32)
		slider:SetText("Min Players :")
		slider:SetMin(1)
		slider:SetMax(tonumber(game.MaxPlayers()))
		slider:SetValue(GetConVar("ph_min_waitforplayers"):GetInt())
		slider:SetDecimals(0)
		slider.OnValueChanged = function(pnl, val)
			slider:SetValue(math.Round(val))
			net.Start("SvCommandMinPly")
				net.WriteString("ph_min_waitforplayers")
				net.WriteString(tostring(math.Round(val)))
			net.SendToServer()
		end

		local function Tauntoption_Button()
			local CusTauntConvar = {
				[0] = "Mode [F3]: Random Taunt",
				[1] = "Mode [C]: Custom Taunt",
				[2] = "Both Modes (F3 & C)"
			}

			local function SendTauntCommandState(state)
				net.Start("SendTauntStateCmd")
				net.WriteString(tostring(state))
				net.SendToServer()
			end

			local lblt = vgui.Create("DLabel", panel)
			lblt:SetPos(20,220)
			lblt:SetSize(400,24)
			lblt:SetText("Enable Custom Taunts?")

			local state = 0
			local butt = vgui.Create("DButton", panel)
			butt:SetPos(20,240)
			butt:SetSize(140,24)
			butt:SetText(CusTauntConvar[PHE.CUSTOM_TAUNT_ENABLED])
			butt.DoClick = function()
				if PHE.CUSTOM_TAUNT_ENABLED == 0 then
					state = 1
					SendTauntCommandState(1)
					butt:SetText(CusTauntConvar[state])
				elseif PHE.CUSTOM_TAUNT_ENABLED == 1 then
					state = 2
					SendTauntCommandState(2)
					butt:SetText(CusTauntConvar[state])
				elseif PHE.CUSTOM_TAUNT_ENABLED == 2 then
					state = 0
					SendTauntCommandState(0)
					butt:SetText(CusTauntConvar[state])
				end
			end
		end

		Tauntoption_Button()
		
		local buttadmin = vgui.Create("DButton", panel)
		buttadmin:SetPos(15,280)
		buttadmin:SetSize(128,24)
		buttadmin:SetText("Start MapVote")
		buttadmin.DoClick = function()
			ply:ConCommand("map_vote")
			frm:Close()
		end
		
		local buttadmin2 = vgui.Create("DButton", panel)
		buttadmin2:SetPos(148,280)
		buttadmin2:SetSize(128,24)
		buttadmin2:SetText("Stop MapVote")
		buttadmin2.DoClick = function()
			ply:ConCommand("unmap_vote")
			frm:Close()
		end
		
		local lblx = vgui.Create("DLabel", panel)
		lblx:SetPos(15,305)
		lblx:SetSize(500,24)
		lblx:SetText("To cancel MapVote, type !unmap_vote in the chat or type \'unmap_vote\' in the console!")
	
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
