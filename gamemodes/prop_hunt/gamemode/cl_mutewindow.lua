-- Configure your admin/mod/vip list so they cannot be muted for a reason.
local AdminList = {
	"superadmin",
	"admin",
	
	"Owner",
	"Co-owner",
	
	"developer",
	"moderator",
	
	"vip"
}

function ph_MutePlayer(ply,cmd,arg,args)
	local frame = vgui.Create("DFrame")
	frame:SetPos(0,0)
	frame:SetSize(300,500)
	frame:SetTitle("Mute Player [Double Click to mute]")
	frame:Center()
	frame:SetVisible(true)
	frame:ShowCloseButton(true)
	-- Make sure they have Mouse & Keyboard interactions.
	frame:SetMouseInputEnabled(true)
	frame:SetKeyboardInputEnabled(true)
	
	local list = vgui.Create("DListView", frame)
	list:SetPos( 5, 24 )
	list:SetSize( 290, 470 )
	list:AddColumn( "Player Names" )
	list:AddColumn( "Steam ID" )
	--list:SetTooltip("Double Click to mute.")
	
	for k,v in pairs(player.GetAll()) do
		if v != ply then 
			list:AddLine(v:Nick(),v:SteamID())
		elseif v:IsBot() or v == ply then
			continue
		end
	end
	
	function list:DoDoubleClick(id,line)
	
		for k,v in pairs(player.GetAll()) do
			local plcol = team.GetColor(v:Team())
			if v:SteamID() == list:GetLine(id):GetValue(2) then
				if table.HasValue(AdminList, v:GetUserGroup()) then
					chat.AddText(Color(250,0,0),"Warning: you cannot mute admin or other staff members!")
					frame:Close()
				else
					if not v:IsMuted() then
						v:SetMuted(true)
						chat.AddText(Color(plcol.r,plcol.g,plcol.b),"Player "..v:Nick(),Color(255,255,255)," has been muted.")
					else
						v:SetMuted(false)
						chat.AddText(Color(plcol.r,plcol.g,plcol.b),"Player "..v:Nick(),Color(255,255,255)," has been unmuted.")
					end
				end
			end
		end
		
	end
	
	frame:MakePopup()
	frame:SetKeyboardInputEnabled(false)
	
end
concommand.Add("ph_mute_window", ph_MutePlayer)