util.AddNetworkString("CheckAdminFirst")
util.AddNetworkString("CheckAdminResult")
util.AddNetworkString("SvCommandReq")

local admins = {}

-- Note: Since this will check default admins and server from ULX, this should be recommended as it follows from admins.users tables.
admins.users = { 
	"admin",
	"superadmin",
	"owner"
	-- add more here, example: mods, operator, etc if you want.
}

net.Receive("CheckAdminFirst", function(len, ply)
	-- I was wanting from table.HasValue but it seems to be having some performance impact.
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
		print("[ADMIN CVAR NOTIFY] Commands: "..cmd.." has been changed (Player: "..ply:Nick().." ("..ply:SteamID()..")")
	end
end)