if SERVER then
	util.AddNetworkString("CL2SV_PlayThisTaunt")
	
	net.Receive("CL2SV_PlayThisTaunt", function(len, ply)
		local snd = net.ReadString()
		
		if IsValid(ply) then
			ply:EmitSound(snd, 100)
		end
	end)	
end

if CLIENT then
	local isplayed = false
	local isopened = false
	local isforcedclose = false
	
	net.Receive("PH_ForceCloseTauntWindow", function()
		isforcedclose = true
	end)
	
	net.Receive("PH_AllowTauntWindow", function()
		isforcedclose = false
	end)
	
	local function MainFrame()
		if !GetConVar("ph_enable_custom_taunts"):GetBool() then
			chat.AddText(Color(220,0,0),"[PH: Enhanced - Taunt] Warning: This server has custom taunts disabled.")
			return
		end
		
		isopened = true
	
		local frame = vgui.Create("DFrame")
		frame:SetSize(400,600)
		frame:SetTitle("Prop Hunt | Custom Taunt List")
		frame:Center()
		frame:MakePopup()
		
		frame.OnClose = function()
			isopened = false
		end
		
		local function frame_Think_Force()
			if isforcedclose == true && isopened == true then
				isopened = false
				frame:Close()
			end
		end
		hook.Add("Think", "CloseWindowFrame_Force", frame_Think_Force)
		
		local list = vgui.Create("DListView", frame)
		list:SetMultiSelect(false)
		list:AddColumn("Sound list")
		list:SetPos(10,52)
		list:SetSize(380,528)
		
		for _,snd in pairs(PROP_TAUNTS) do
			list:AddLine(snd)
		end
		
		local comb = vgui.Create("DComboBox", frame)
		comb:SetPos(10,28)
		comb:SetSize(380, 20)
		comb:SetValue("All Taunts")
			comb:AddChoice("Original Taunts")
			comb:AddChoice("Custom Taunts")
			
		comb.OnSelect = function(pnl, idx, val)
			if val == "Original Taunts" then
				list:Clear()
				for k,v in pairs(PROP_TAUNTS) do
					list:AddLine(v)
				end
			elseif val == "Custom Taunts" then
				list:Clear()
				for k,v in pairs(PH_TAUNT_CUSTOM.PROP) do
					list:AddLine(v)
				end
			end
		end
		
		list.OnRowRightClick = function(panel,line)
			local getline = list:GetLine(list:GetSelectedLine()):GetValue(1)
			
			local function SendToServer()
				if isplayed != true then
					net.Start("CL2SV_PlayThisTaunt"); net.WriteString(tostring(getline)); net.SendToServer();
					isplayed = true
					timer.Simple(CUSTOM_TAUNT_DELAY, function() isplayed = false; end)
				else
					chat.AddText(Color(220,40,0),"[PH: Enhanced - Taunt] Warning: ",Color(220,220,220),"You have to wait "..CUSTOM_TAUNT_DELAY.." seconds to play this taunt again!")
				end
			end
			
			local menu = DermaMenu()
			menu:AddOption("Play for self", function() surface.PlaySound(getline); print("Playing: "..getline); end):SetIcon("icon16/control_play.png")
			menu:AddOption("Play as Taunt (everyone can hear)", function() SendToServer(); end):SetIcon("icon16/sound.png")
			menu:AddOption("Play as Taunt and Close (everyone can hear)", function() SendToServer(); frame:Close(); end):SetIcon("icon16/sound_delete.png")
			menu:AddSpacer()
			menu:AddOption("Close", function() end)
			menu:Open()
		end
	end
	
	concommand.Add("ph_showtaunts", function()
	if LocalPlayer():Team() == TEAM_PROPS && LocalPlayer():Alive() && isforcedclose != true then
		if isopened != true then
			MainFrame()
		end	
	else
		chat.AddText(Color(220,40,0),"[PH: Enhanced - Taunt] Notice: ",Color(220,220,220),"You can only play custom taunts when you\'re Alive as a Prop and you can\'t play taunts while you dead!")
	end
	end, nil, "Show Prop Hunt taunt list, so You can select and play for self or play as a taunt.")
	
	local function BindPress(ply, bind, pressed)
		if string.find(bind, "+menu_context") and pressed then
			if LocalPlayer():Team() == TEAM_PROPS && LocalPlayer():Alive() && isforcedclose != true then
				if isopened != true then
					MainFrame()
				end
			else
				chat.AddText(Color(220,40,0),"[PH: Enhanced - Taunt] Notice: ",Color(220,220,220),"You can only play custom taunts when you\'re Alive as a Prop and you can\'t play taunts while you dead!")
			end
		end
	end
	hook.Add("PlayerBindPress", "PlayerBindPress_menuContext", BindPress)
	
end