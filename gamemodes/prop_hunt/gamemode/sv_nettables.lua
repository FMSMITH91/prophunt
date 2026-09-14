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
    
	"PHX.scan_ReqTaunts",
	"PHX.scan_SendTauntLists",

    -- X2Z Very-first Tutorial Window
	"phx_showVeryFirstTutorial",

	-- Fretta's GM:AddRoundTime. Was a umsg, which Garry's Mod removed.
	"PHX.RoundAddedTime"
}

for _,init in pairs(nets) do
	util.AddNetworkString( init )
end