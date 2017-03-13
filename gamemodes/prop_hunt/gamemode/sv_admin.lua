util.AddNetworkString("CheckAdminFirst")
util.AddNetworkString("CheckAdminResult")
util.AddNetworkString("SvCommandReq")

util.AddNetworkString("SvCommandMinPly")
util.AddNetworkString("SendTauntStateCmd")

local admins = {}

-- Note: Since this will check default admins and server from ULX, this should be recommended as it follows from admins.users tables.
admins.users = { 
	"admin",
	"superadmin",
	"owner"
	-- add more here, example: mods, operator, etc if you want.
}

net.Receive("CheckAdminFirst", function(len, ply)
	if ply:IsAdmin() or table.HasValue(admins.users, ply:GetUserGroup()) then
		net.Start("CheckAdminResult")
		net.Send(ply)
	end
end)

net.Receive("SvCommandReq", function(len, ply)
	local cmd = net.ReadString()
	local valbool = net.ReadString()
	if ply:IsAdmin() or table.HasValue(admins.users, ply:GetUserGroup()) then
		RunConsoleCommand(cmd, valbool)
		printverbose("[ADMIN CVAR NOTIFY] Commands: "..cmd.." has been changed (Player: "..ply:Nick().." ("..ply:SteamID()..")")
	end
end)

net.Receive("SvCommandMinPly", function(len, ply)
	local cmd = net.ReadString()
	local val = net.ReadString()
	if ply:IsAdmin() or table.HasValue(admins.users, ply:GetUserGroup()) then
		RunConsoleCommand(cmd, val)
		printverbose("[ADMIN CVAR SLIDER NOTIFY] Commands: "..cmd.." has been changed (Player: "..ply:Nick().." ("..ply:SteamID()..")")
	end
end)

net.Receive("SendTauntStateCmd", function(len, ply)
	local cmdval = net.ReadString()
	
	if ply:IsAdmin() or table.HasValue(admins.users, ply:GetUserGroup()) then
		RunConsoleCommand("ph_enable_custom_taunts", cmdval)
		printverbose("[ADMIN CVAR TAUNT NOTIFY] Commands: "..cmdval.." has been changed (Player: "..ply:Nick().." ("..ply:SteamID()..")")
	end
end)