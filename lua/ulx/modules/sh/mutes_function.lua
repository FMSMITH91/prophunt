-- Mute Voice Player Locally.
-- I know this may differs from 'gag' and 'mute', this one however will helps users if there is no admin
-- to make sure they can mute those noisy players by themselves.

-- Additional notes:
-- You can customize admin types here.

function ulx.MutePlayers(calling_ply, target_ply)
-- I am not lazy, maybe you can enhance by yourself.
	if target_ply:IsAdmin() or target_ply:IsSuperAdmin() or target_ply:IsUserGroup("Moderator") or target_ply:IsUserGroup("owner") or target_ply:IsUserGroup("VIP") then
		calling_ply:ChatPrint("Sorry, You cannot mute Admin or Moderator!")
	else
		net.Start("MuteInfo")
		net.WriteEntity(target_ply)
		net.Send(calling_ply)
	end
	
	if target_ply == nil then
		ulx.fancyLogAdmin( calling_ply, "Error: Player was not found." )
	end
end
local mutes_ply = ulx.command( "Mute Player", "ulx mutes", ulx.MutePlayers, "!mutes" )
mutes_ply:addParam{ type=ULib.cmds.PlayerArg }
mutes_ply:defaultAccess( ULib.ACCESS_ALL )
mutes_ply:help( "Toggles mute player\'s voice locally.\nNote: You cannot mute Admin or Moderators!" )
