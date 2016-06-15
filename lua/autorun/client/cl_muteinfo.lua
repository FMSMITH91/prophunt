AddCSLuaFile()

net.Receive("MuteInfo", function()
	local mutedply = net.ReadEntity()
	local pl = LocalPlayer()
	local timcol = Color(0, 0, 0)
	
	-- As I said, I'm not lazy, you can enhance or customize them what you want.
	if mutedply:Team() == TEAM_PROPS then
		timcol = Color(240,30,0)
	elseif mutedply:Team() == TEAM_HUNTERS then
		timcol = Color(0,180,250)
	else
		timcol = Color(240,160,0)
	end
	
	if not mutedply:IsMuted() then
		mutedply:SetMuted(true)
		chat.AddText(Color(255,255,255), "[Voice Mute] You have muted ", timcol, mutedply:Nick())
	else
		mutedply:SetMuted(false)
		chat.AddText(Color(255,255,255), "[Voice Mute] You have unmuted ", timcol, mutedply:Nick())
	end
end)