-- Wolvin: Warning: there are already like 250+ net tables in PH:X.
-- Mostly those are occupied by GetGlobals* from ConVars.
-- Reduce Next Time!

local nets = {
	-- // start of sv_admins: \\ --
	"SvCommandReq",
	"SvCommandSliderReq",
	"SendTauntStateCmd",
	"PHXPickupCmdState",
	"SvCommandTextEntry",
	"SvCommandLang",
    "SvCheckboxReq",
    "PHX.AdminGroupInfo",
    "PHX.CLAdminGroupInfo",
	"PHX.MutedGroupInfo",
	"PHX.CLMutedGroupInfo",
	-- Enhanced Plus
	"PHX.ResetRotateTeams",
	"PHX.ForceHunterAsProp",
	"PHX.ForceResetHunterAsProp",
	"ResetHunterForceAsPropList",
	-- // end of sv_admins \\ --

	"ResetHull",
	"SetHull",
	"PlayFreezeCamSound",
	"PlayerSwitchDynamicLight",
	"DisableDynamicLight",
	
	"CL2SV_PlayThisTaunt", 
	
	"PH_ForceCloseTauntWindow",
	"PH_AllowTauntWindow", 
	"PH_TeamWinning_Snd", 
	"AutoTauntSpawn", 
	"AutoTauntRoundEnd", 
	
	"PHX.rotateState", 
	
	"PHX.CenterPrint",
	"PHX.ChatPrint", 
	"PHX.bubbleNotify", 
	"PHX.ChatInfo", 

    "PHX.DeathNoticeDecoy",
	"PHX.UpdatePropbanInfo",
	-- PHX.scan_ReqTaunts and PHX.scan_SendTauntLists: sh_tauntscanner.lua registers them.

    -- X2Z Very-first Tutorial Window
	"phx_showVeryFirstTutorial",

	-- Fretta's GM:AddRoundTime. Was a umsg, which Garry's Mod removed.
	"PHX.RoundAddedTime"
}

for _,init in pairs(nets) do
	util.AddNetworkString( init )
end

-- GMod caps one net message at about 64KB, so a payload compressed past that never
-- arrives. Refuse it with an error naming the message instead. The wire format is
-- the one the clients already read: a 32-bit length, then the data. Sends to
-- target, or to everyone without one; returns whether it was sent.
local MAX_NET_DATA = 60000
function util.PHXSendCompressed( netName, data, size, target )
	if size > MAX_NET_DATA then
		ErrorNoHalt( "[PHX] Not sending " .. netName .. ": it is " .. size .. " bytes compressed, over the " .. MAX_NET_DATA .. " byte net message limit.\n" )
		return false
	end

	net.Start( netName )
		net.WriteUInt( size, 32 )
		net.WriteData( data, size )
	if target then net.Send( target ) else net.Broadcast() end
	return true
end
