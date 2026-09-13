
include( "vgui/vgui_scoreboard.lua" )
include( "vgui/vgui_scoreboard_modern.lua" )
include( "cl_scoreboard_admin.lua" )

local cvarModern = CreateClientConVar( "ph_cl_modern_scoreboard", "1", true, false,
	"Use the modern scoreboard. 0 falls back to the classic Fretta list." )

function PHX:UseModernScoreboard()
	return cvarModern:GetBool()
end

// Rebuild on the next open rather than swapping panels underneath a board that
// might be on screen right now.
cvars.AddChangeCallback( "ph_cl_modern_scoreboard", function()
	if ( IsValid( g_ScoreBoard ) ) then
		g_ScoreBoard:Remove()
		g_ScoreBoard = nil
	end
end, "PHX.ScoreboardStyle" )

function GM:GetScoreboard()

	if ( IsValid( g_ScoreBoard ) ) then
		g_ScoreBoard:Remove()
	end

	if ( PHX:UseModernScoreboard() ) then

		g_ScoreBoard = vgui.Create( "PHXScoreboardModern" )
		self:CreateModernScoreboard( g_ScoreBoard )

	else

		g_ScoreBoard = vgui.Create( "FrettaScoreboard" )
		self:CreateScoreboard( g_ScoreBoard )

	end

	return g_ScoreBoard

end

// True while the map vote panel is on screen. The panel is removed when the
// vote is cancelled or the map changes, so this cannot get stuck on.
local function MapVoteOnScreen()
	return PHX && PHX.MV && IsValid( PHX.MV.Panel )
end

function GM:ScoreboardShow()
	
	// Don't cover the map vote. GM:OnEndOfGame force-opens the scoreboard with
	// +showscores moments before the vote appears, and players holding TAB
	// during a vote would otherwise hide it behind the scoreboard.
	if ( MapVoteOnScreen() ) then return end
	
	gui.EnableScreenClicker(true)
	GAMEMODE:GetScoreboard():SetVisible( true )
	GAMEMODE:PositionScoreboard( GAMEMODE:GetScoreboard() )
	
end

function GM:ScoreboardHide()
	
	GAMEMODE:GetScoreboard():SetVisible( false )
	
	// The vote panel drives the cursor through MakePopup; releasing the screen
	// clicker here would leave it visible but unclickable. The -showscores that
	// GM:OnEndOfGame schedules lands at the same moment the vote opens, so this
	// race is the normal case rather than an edge case.
	if ( MapVoteOnScreen() ) then return end
	
	gui.EnableScreenClicker(false)
	
end

// Bots have no community profile, and a disconnected player has no id to look
// up, so there is nothing to open for either.
function PHX:CanOpenSteamProfile( ply )
	if ( !IsValid( ply ) or !ply:IsPlayer() or ply:IsBot() ) then return false end
	
	local id64 = ply:SteamID64()
	
	return id64 ~= nil and id64 ~= "" and id64 ~= "0"
end

// Opens in the Steam overlay, or the default browser when the overlay is off.
function PHX:OpenSteamProfile( ply )
	if ( !self:CanOpenSteamProfile( ply ) ) then return end
	
	gui.OpenURL( "https://steamcommunity.com/profiles/" .. ply:SteamID64() )
end

// Makes a panel open ply's Steam profile when left clicked. Used for both the
// avatar and the name column.
function PHX:MakeProfileLink( pnl, ply )
	if ( !IsValid( pnl ) ) then return end
	
	if ( !self:CanOpenSteamProfile( ply ) ) then
		pnl:SetMouseInputEnabled( false )
		return
	end
	
	pnl:SetMouseInputEnabled( true )
	pnl:SetCursor( "hand" )
	pnl:SetTooltip( PHX:FTranslate( "DERMA_OPEN_STEAM_PROFILE" ) )
	
	pnl.OnMousePressed = function( _, code )
		if ( code == MOUSE_LEFT ) then PHX:OpenSteamProfile( ply ) end
	end
end

function GM:AddScoreboardAvatar( ScoreBoard )

	local f = function( ply ) 	
		local av = vgui.Create( "AvatarImage", ScoreBoard )
			av:SetSize( 32, 32 )
			av:SetPlayer( ply )
			
			PHX:MakeProfileLink( av, ply )
			
			return av
	end
	
	ScoreBoard:AddColumn( "", 32, f, 360 ) // Avatar

end

function PHX:CanMutePlayer( ply )
	if ( !IsValid( ply ) ) then return false end
	
	local lp = LocalPlayer()
	if ( !IsValid( lp ) ) then return false end
	
	// Player:CheckGroup is ULib's (lua/ulib/shared/sh_ucl.lua). Unlike
	// IsUserGroup it walks the UCL inheritance chain, so a superadmin passes
	// CheckGroup("admin"). Asking it about the target's group answers "is my
	// rank at or above theirs" - an admin can mute a user, a user cannot mute an
	// admin. That is the intended rule; keep it wherever ULib is installed.
	if ( lp.CheckGroup ) then
		return lp:CheckGroup( ply:GetUserGroup() )
	end
	
	// No ULib on this server, so CheckGroup would be a nil call. Fall back to
	// PH:X's own rule, the one the F1 menu applies in
	// prop_hunt/gamemode/cl_menutypes.lua.
	if ( ply:PHXIsStaff() ) then return false end
	
	return !PHX.IgnoreMutedUserGroup[ ply:GetUserGroup() ]
end
 
 
function GM:AddScoreboardVoice( ScoreBoard )
 
	local f = function(ply)
 
		local main = vgui.Create("DPanel", ScoreBoard)
			main:SetPaintBackground(false)
 
			local vc = vgui.Create("DImageButton", main)
				vc:SetPos(15, 6)
				vc:SetSize(20, 20)
			if IsValid(ply) && ply != LocalPlayer() then
				local muted = false
				if PHX:CanMutePlayer(ply) then
					muted = ply:IsMuted()
				else
					vc:SetAlpha(100)
				end
				vc:SetImage(muted and "icon16/sound_mute.png" or "icon16/sound.png")
			else
				vc:Hide()
			end
 
			function vc.DoClick()
				if IsValid(ply) && ply != LocalPlayer() && PHX:CanMutePlayer(ply) then
					ply:SetMuted(!ply:IsMuted() )
				end
			end
		return main
	end
 
	ScoreBoard:AddColumn( "Mute", 40, f, 0.5, nil, 6, 6 )
 
end

function GM:AddScoreboardSpacer( ScoreBoard, iSize )
	ScoreBoard:AddColumn( "", 16 )
end

function GM:AddScoreboardName( ScoreBoard )

	local f = function( ply ) return ply:Name() end
	local col = ScoreBoard:AddColumn( PHX:FTranslate("DERMA_NAME") or "Name", nil, f, 10, nil, 4, 4 )
	
	// Handled in vgui_scoreboard_team.lua: this column's value is plain text, so
	// the label is built by the engine and only reachable from UpdateColumn.
	col.bOpenProfile = true

end

function GM:AddScoreboardKills( ScoreBoard )

	local f = function( ply ) return ply:Frags() end
	ScoreBoard:AddColumn( PHX:FTranslate("DERMA_KILLS") or "Kills", 40, f, 0.5, nil, 6, 6 )

end

function GM:AddScoreboardDeaths( ScoreBoard )

	local f = function( ply ) return ply:Deaths() end
	ScoreBoard:AddColumn( PHX:FTranslate("DERMA_DEATHS") or "Deaths", 60, f, 0.5, nil, 6, 6 )

end

function GM:AddScoreboardPing( ScoreBoard )

	local f = function( ply ) return PHX:FTranslate( ply:ScoreboardPing() ) or "SV" end -- Original: ply:ScoreboardPing()
	ScoreBoard:AddColumn( PHX:FTranslate("DERMA_PING") or "Ping", 40, f, 0.1, nil, 6, 6 )

end

// THESE SHOULD BE THE ONLY FUNCTION YOU NEED TO OVERRIDE

function GM:PositionScoreboard( ScoreBoard )

	// The modern board sizes itself against the screen; nothing to place.
	if ( ScoreBoard.PHXModern ) then
		ScoreBoard:PositionSelf()
		return
	end

	if ( GAMEMODE.TeamBased ) then
		ScoreBoard:SetSize( ScrW()/1.2, ScrH() - 50 )
		ScoreBoard:SetPos( (ScrW() - ScoreBoard:GetWide()) * 0.5,  25 )
	else
		ScoreBoard:SetSize( 420, ScrH() - 64 )
		ScoreBoard:SetPos( (ScrW() - ScoreBoard:GetWide()) / 2, 32 )
	end

end

function GM:AddScoreboardWantsChange( ScoreBoard )

	local f = function( ply ) 
					if ( ply:GetNWBool( "WantsVote", false ) ) then 
						local lbl = vgui.Create( "DLabel" )
							lbl:SetFont( "Marlett" )
							lbl:SetText( "a" )
							lbl:SetTextColor( Color( 100, 255, 0 ) )
							lbl:SetContentAlignment( 5 )
						return lbl
					end					
				end
				
	ScoreBoard:AddColumn( "", 16, f, 2, nil, 6, 6 )

end

function GM:AddScoreboardCustom( ScoreBoard, ... )
	ScoreBoard:AddColumn( ... )
end

function GM:CreateScoreboard( ScoreBoard )

	// This makes it so that it's behind chat & hides when you're in the menu
	// Disable this if you want to be able to click on stuff on your scoreboard
	//ScoreBoard:ParentToHUD()
	
	ScoreBoard:SetRowHeight( 32 )

	ScoreBoard:SetAsBullshitTeam( TEAM_SPECTATOR )
	ScoreBoard:SetAsBullshitTeam( TEAM_CONNECTING )
	ScoreBoard:SetShowScoreboardHeaders( GAMEMODE.TeamBased )
	
	if ( GAMEMODE.TeamBased ) then
		ScoreBoard:SetAsBullshitTeam( TEAM_UNASSIGNED )
		ScoreBoard:SetHorizontal( true )	
	end

	ScoreBoard:SetSkin( GAMEMODE.HudSkin )

	self:AddScoreboardAvatar( ScoreBoard )		// 1
	self:AddScoreboardVoice( ScoreBoard )		// 2
	self:AddScoreboardWantsChange( ScoreBoard )	// 3
	self:AddScoreboardName( ScoreBoard )		// 4
	-- Include custom column externally. Set after Player's Name.
	hook.Call("PH_AddColumnScoreboard", nil, ScoreBoard, function( Name, Fixed, Func, Rate, TeamID, HAlign, VAlign, Font )
		GAMEMODE:AddScoreboardCustom( ScoreBoard, Name, Fixed, Func, Rate, TeamID, HAlign, VAlign, Font )
	end)
	-- Add the Rest.
	self:AddScoreboardKills( ScoreBoard )		// 5
	self:AddScoreboardDeaths( ScoreBoard )		// 6
	self:AddScoreboardPing( ScoreBoard )		// 7
		
	// Here we sort by these columns (and descending), in this order. You can define up to 4
	ScoreBoard:SetSortColumns( { 5, true, 6, false, 4, false } )

end

/*
	The modern board draws avatar/name/kills/deaths/ping/mute itself, so it only
	needs to be told which teams are real and which are a footnote. The
	PH_AddColumnScoreboard hook is still fired with the same signature, so
	addons that add a column keep working on both boards.
*/
function GM:CreateModernScoreboard( ScoreBoard )

	ScoreBoard:SetAsBullshitTeam( TEAM_SPECTATOR )
	ScoreBoard:SetAsBullshitTeam( TEAM_CONNECTING )

	if ( GAMEMODE.TeamBased ) then
		ScoreBoard:SetAsBullshitTeam( TEAM_UNASSIGNED )
	end

	// Custom columns land to the left of kills/deaths/ping.
	hook.Call( "PH_AddColumnScoreboard", nil, ScoreBoard, function( Name, Fixed, Func, Rate, TeamID, HAlign, VAlign, Font )
		GAMEMODE:AddScoreboardCustom( ScoreBoard, Name, Fixed, Func, Rate, TeamID, HAlign, VAlign, Font )
	end )

	// Must run after the bullshit teams are flagged, or they would get a card.
	local ids = {}
	for id in pairs( team.GetAllTeams() ) do table.insert( ids, id ) end

	ScoreBoard:SetupTeams( ids )

end
