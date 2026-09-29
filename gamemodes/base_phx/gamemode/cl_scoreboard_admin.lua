/*
	cl_scoreboard_admin.lua - ULX actions for the scoreboard
	-----------------------------------------------------------------
	Right-click menu backing the modern scoreboard: gag, mute, kick and ban
	through ULX, plus the non-admin bits (Steam profile, copy SteamID, local
	voice mute).

	On authority: the checks in here only decide what to DRAW. ULib re-runs
	ULib.ucl.query against the calling player inside its own command dispatch
	(ulib/shared/commands.lua, translateCmdCallback) and answers "You don't have
	access to this command" if it fails, so a hand-edited client gains nothing
	by unhiding a menu entry.

	Naming, because ULX is the opposite of what people expect:
	    ulx gag   -> blocks the MICROPHONE  (help: "disables microphone")
	    ulx mute  -> blocks TEXT CHAT       (help: "unable to chat")
	The menu labels say which is which rather than repeating the bare verb.
*/

// This file is included from base_phx, which loads through DeriveGamemode, so
// do not assume prop_hunt's sh_init.lua has run yet.
PHX = PHX or {}

/*
	Translate with a real fallback.

	PHX:FTranslate hands back the KEY ITSELF when a string is defined in no
	language file (cl_lang.lua: "return textToFind"), so the usual
	`PHX:FTranslate( k ) or "..."` idiom can never fall back - it just prints
	the key on screen. This compares against the key to catch that, and also
	covers PHX not being loaded at all.

	The fallback gets the same arguments the translation would have, so
	"Kick %s?" still names the player when the key is missing.
*/
function PHX:SBTranslate( key, fallback, ... )

	local str = self.FTranslate && self:FTranslate( key, ... )
	if ( str != nil && str != key ) then return str end

	if ( select( "#", ... ) == 0 ) then return fallback end

	// A fallback with a stray % must not take the menu down with it.
	local ok, formatted = pcall( string.format, fallback, ... )

	return ok and formatted or fallback

end

// "ulx kick" is registered as concommand "ulx" with a routed sub-word
// (ULib.cmds.addCommand splits on whitespace), so every command dispatches as
// RunConsoleCommand( "ulx", "<sub>", ... ).
local ULX_CMD = "ulx"

function PHX:HasULX()
	return ULib ~= nil && ULib.ucl ~= nil && ulx ~= nil
end

/*
	Whether the local player may run an ULX command.

	ULib.ucl.query raises on a player it has not authed yet, so it is never
	called bare. It returns nil for an access string nobody was granted, which
	means an unknown or misspelled command fails closed.
*/
function PHX:CanRunULX( access )

	if ( !self:HasULX() ) then return false end

	local lp = LocalPlayer()
	if ( !IsValid( lp ) ) then return false end

	// ucl.query only auto-grants the listen host on the server; mirror that
	// here or the host's own menu comes up empty on a local server.
	if ( lp:IsListenServerHost() ) then return true end

	local ok, allowed = pcall( ULib.ucl.query, lp, access )

	return ok && ( allowed == true )

end

/*
	ULib resolves "$<id>" through ULib.getPlyByID, which matches UniqueID, IP,
	SteamID or UserID. SteamID is used here because it cannot collide with
	another player's name the way a bare nickname target can.
*/
function PHX:ULXTarget( ply )

	if ( !IsValid( ply ) ) then return nil end

	local sid = ply:SteamID()
	if ( !sid || sid == "" || sid == "BOT" ) then

		// Bots have no SteamID; fall back to their session UserID.
		return "$" .. ply:UserID()

	end

	return "$" .. sid

end

// ply may also be a target string ULXTarget already built. The menu builds it
// when it opens, so an action confirmed after the player left or rejoined
// still names their SteamID.
function PHX:RunULX( sub, ply, ... )

	local target = isstring( ply ) and ply or self:ULXTarget( ply )
	if ( !target ) then return end

	RunConsoleCommand( ULX_CMD, sub, target, ... )

end

// ulx gag networks its state, so the menu can show the real toggle.
// ulx mute keeps its state in a server-only field, so both directions are
// offered rather than guessing.
function PHX:IsULXGagged( ply )
	return IsValid( ply ) && ply:GetNWBool( "ulx_gagged", false )
end

local function KickReasons()

	// ULX ships a list and server owners edit it; use theirs when present.
	if ( ulx && istable( ulx.common_kick_reasons ) && #ulx.common_kick_reasons > 0 ) then
		return ulx.common_kick_reasons
	end

	return { "Breaking the rules", "Trolling", "Idle", "Abusive language" }

end

// ulx ban takes minutes, with 0 meaning permanent.
local BAN_TIMES = {
	{ mins = 5,     key = "DERMA_BAN_5MIN",  fallback = "5 minutes" },
	{ mins = 30,    key = "DERMA_BAN_30MIN", fallback = "30 minutes" },
	{ mins = 60,    key = "DERMA_BAN_1HOUR", fallback = "1 hour" },
	{ mins = 1440,  key = "DERMA_BAN_1DAY",  fallback = "1 day" },
	{ mins = 10080, key = "DERMA_BAN_1WEEK", fallback = "1 week" },
	{ mins = 0,     key = "DERMA_BAN_PERMA", fallback = "Permanent" }
}

/*
	Derma_Query and Derma_StringRequest both return a MakePopup'd modal DFrame
	that is not a child of the scoreboard. GM:ScoreboardHide releases the screen
	clicker, which would strand one of these on screen and unclickable - the
	same failure an open DMenu had. The board asks ScoreboardDialogOpen before
	letting the cursor go, and the cursor is handed back when the dialog closes.
*/
function PHX:TrackScoreboardDialog( frame )

	if ( !IsValid( frame ) ) then return frame end

	self.SBDialog = frame

	local previous = frame.OnRemove

	frame.OnRemove = function( pnl, ... )

		if ( previous ) then previous( pnl, ... ) end

		// The ban flow opens its confirm dialog from the reason prompt's OK
		// button, so by now the slot may belong to that newer dialog.
		if ( PHX.SBDialog == pnl ) then PHX.SBDialog = nil end

		// Only take the cursor back if neither the board nor another tracked
		// dialog is still holding it.
		if ( !IsValid( PHX.SBDialog ) && ( !IsValid( g_ScoreBoard ) || !g_ScoreBoard:IsVisible() ) ) then
			gui.EnableScreenClicker( false )
		end

	end

	return frame

end

function PHX:ScoreboardDialogOpen()
	return IsValid( self.SBDialog )
end

local function Confirm( text, fn )
	PHX:TrackScoreboardDialog( Derma_Query( text, PHX.TITLE or "Prop Hunt",
		PHX:SBTranslate( "DERMA_MENU_YES", "Yes" ), fn,
		PHX:SBTranslate( "DERMA_MENU_NO",  "No" ), function() end ) )
end

/*
	The scoreboard right-click menu. Returns the menu so callers can position
	it; nil when there is nothing worth showing.
*/
function PHX:OpenPlayerMenu( ply )

	if ( !IsValid( ply ) || !ply:IsPlayer() ) then return nil end

	local lp = LocalPlayer()
	if ( !IsValid( lp ) ) then return nil end

	local menu  = DermaMenu()
	local isSelf = ( ply == lp )

	// Every callback below runs later - from a menu click, or from a reason
	// dialog that stays open after TAB is released - and the player may have
	// left by then. Player methods raise on a NULL entity, so take what the
	// callbacks need now.
	local nick   = ply:Nick()
	local sid    = ply:SteamID()
	local target = self:ULXTarget( ply )

	local title = menu:AddOption( nick )
	title:SetEnabled( false )
	menu:AddSpacer()

	if ( self:CanOpenSteamProfile( ply ) ) then
		menu:AddOption( self:SBTranslate( "DERMA_MENU_PROFILE", "Open Steam Profile" ), function()
			self:OpenSteamProfile( ply )
		end ):SetIcon( "icon16/user_go.png" )

		menu:AddOption( self:SBTranslate( "DERMA_MENU_COPYID", "Copy SteamID" ), function()
			SetClipboardText( sid )
		end ):SetIcon( "icon16/page_copy.png" )
	end

	// Client-side voice mute. Unlike the ULX commands this only affects what
	// the local player hears, and needs no permissions beyond PHX's own rule.
	if ( !isSelf && self:CanMutePlayer( ply ) ) then
		local muted = ply:IsMuted()

		menu:AddOption( muted
			and ( self:SBTranslate( "DERMA_MENU_UNMUTE_ME", "Unmute for me" ) )
			or  ( self:SBTranslate( "DERMA_MENU_MUTE_ME", "Mute for me" ) ), function()
			if ( IsValid( ply ) ) then ply:SetMuted( !ply:IsMuted() ) end
		end ):SetIcon( muted and "icon16/sound.png" or "icon16/sound_mute.png" )
	end

	if ( isSelf || !self:HasULX() ) then return menu end

	local canGag   = self:CanRunULX( "ulx gag" )
	local canUngag = self:CanRunULX( "ulx ungag" )
	local canMute  = self:CanRunULX( "ulx mute" )
	local canUnmute = self:CanRunULX( "ulx unmute" )
	local canKick  = self:CanRunULX( "ulx kick" )
	local canBan   = self:CanRunULX( "ulx ban" )

	if ( !canGag && !canUngag && !canMute && !canUnmute && !canKick && !canBan ) then
		return menu
	end

	menu:AddSpacer()

	local gagged = self:IsULXGagged( ply )

	if ( gagged && canUngag ) then
		menu:AddOption( self:SBTranslate( "DERMA_MENU_UNGAG", "Ungag (voice)" ), function()
			self:RunULX( "ungag", target )
		end ):SetIcon( "icon16/user_comment.png" )
	elseif ( !gagged && canGag ) then
		menu:AddOption( self:SBTranslate( "DERMA_MENU_GAG", "Gag (voice)" ), function()
			self:RunULX( "gag", target )
		end ):SetIcon( "icon16/sound_mute.png" )
	end

	if ( canMute ) then
		menu:AddOption( self:SBTranslate( "DERMA_MENU_MUTE", "Mute (text chat)" ), function()
			self:RunULX( "mute", target )
		end ):SetIcon( "icon16/comment_delete.png" )
	end

	if ( canUnmute ) then
		menu:AddOption( self:SBTranslate( "DERMA_MENU_UNMUTE", "Unmute (text chat)" ), function()
			self:RunULX( "unmute", target )
		end ):SetIcon( "icon16/comment_add.png" )
	end

	if ( canKick ) then
		local kick, kickBtn = menu:AddSubMenu( self:SBTranslate( "DERMA_MENU_KICK", "Kick" ) )
		kickBtn:SetIcon( "icon16/door_out.png" )

		for _, reason in ipairs( KickReasons() ) do
			kick:AddOption( reason, function()
				Confirm( self:SBTranslate( "DERMA_MENU_CONFIRM_KICK", "Kick %s?", nick ) .. "\n" .. reason, function()
					self:RunULX( "kick", target, reason )
				end )
			end )
		end

		kick:AddSpacer()
		kick:AddOption( self:SBTranslate( "DERMA_MENU_CUSTOM_REASON", "Custom reason..." ), function()
			self:TrackScoreboardDialog( Derma_StringRequest(
				self:SBTranslate( "DERMA_MENU_KICK_TITLE", "Kick %s", nick ),
				self:SBTranslate( "DERMA_MENU_REASON", "Reason:" ), "",
				function( reason )
					self:RunULX( "kick", target, reason )
				end ) )
		end )
	end

	if ( canBan ) then
		local ban, banBtn = menu:AddSubMenu( self:SBTranslate( "DERMA_MENU_BAN", "Ban" ) )
		banBtn:SetIcon( "icon16/cancel.png" )

		for _, t in ipairs( BAN_TIMES ) do

			local label = self:SBTranslate( t.key, t.fallback )

			ban:AddOption( label, function()
				self:TrackScoreboardDialog( Derma_StringRequest(
					self:SBTranslate( "DERMA_MENU_BAN_TITLE", "Ban %s (%s)", nick, label ),
					self:SBTranslate( "DERMA_MENU_REASON", "Reason:" ), "",
					function( reason )
						Confirm( self:SBTranslate( "DERMA_MENU_CONFIRM_BAN", "Ban %s for %s?", nick, label ), function()
							// ulx ban only finds a connected player. If they left while
							// the reason was typed, ban the SteamID instead.
							if ( !IsValid( ply ) && isstring( sid ) && sid:match( "^STEAM_%d:%d:%d+$" ) && self:CanRunULX( "ulx banid" ) ) then
								RunConsoleCommand( ULX_CMD, "banid", sid, t.mins, reason )
								return
							end

							// ulx ban <player> <minutes, 0 = permanent> <reason>
							self:RunULX( "ban", target, t.mins, reason )
						end )
					end ) )
			end )

		end
	end

	return menu

end
