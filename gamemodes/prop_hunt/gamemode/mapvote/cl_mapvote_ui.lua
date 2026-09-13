/*
	cl_mapvote_ui.lua - Prop Hunt: X2Z modern map vote
	-----------------------------------------------------------------
	Replaces the DPanelList of grey text buttons with a grid of map cards:
	thumbnail, live vote count, a share bar and the avatars of everyone who
	voted for it.

	Registered as PHXMapVote, deliberately NOT as "VoteScreen". base_phx's
	vgui/vgui_vote.lua already registers a control by that name - Fretta's
	gamemode vote, which cl_gmchanger.lua creates - and prop_hunt loads second,
	so the old map vote silently overwrote it. Two different panels answering to
	one name meant whichever loaded last won.

	The net protocol is untouched, so the server side needs no changes:
	  RAM_MapVoteStart   amt, map strings, seconds
	  RAM_MapVoteUpdate  UPDATE_VOTE -> entity + map id, UPDATE_WIN -> map id
	  RAM_MapVoteCancel
*/

local MapVote = PHX.MV

local function MVScale( n )
	return math.Round( n * math.Clamp( ScrH() / 1080, 0.8, 1.5 ) )
end

local function MVFont( name, size, weight )
	surface.CreateFont( name, {
		font = "Roboto", size = MVScale( size ), weight = weight,
		antialias = true, extended = true
	} )
end

MVFont( "PHX.MV.Title",  30, 700 )
MVFont( "PHX.MV.Sub",    16, 500 )
MVFont( "PHX.MV.Clock",  42, 700 )
MVFont( "PHX.MV.Card",   18, 700 )
MVFont( "PHX.MV.Count",  26, 700 )
MVFont( "PHX.MV.Small",  14, 500 )

local COL_SHADE   = Color(   8,   9,  12, 225 )
local COL_BG      = Color(  20,  22,  28, 248 )
local COL_CARD    = Color(  31,  35,  44, 255 )
local COL_CARD_HI = Color(  44,  50,  62, 255 )
local COL_TEXT    = Color( 235, 238, 243, 255 )
local COL_DIM     = Color( 142, 150, 165, 255 )
local COL_BORDER  = Color( 255, 255, 255,  20 )
local COL_ACCENT  = Color(  96, 170, 255, 255 )
local COL_WIN     = Color(  92, 205, 130, 255 )
local COL_URGENT  = Color( 226,  92,  82, 255 )

local matBlur = Material( "pp/blurscreen" )
local matGrad = Material( "gui/gradient_down" )

// PHX:FTranslate returns the key itself for an undefined string, so the usual
// `FTranslate( k ) or "text"` idiom never falls back. SBTranslate handles that;
// this also covers it not being loaded yet.
local function Tr( key, fallback, ... )
	if ( !PHX || !PHX.SBTranslate ) then return fallback end
	return PHX:SBTranslate( key, fallback, ... )
end

local MAX_FACES = 6

/*
	Map thumbnails are content, not guaranteed. GMod's own map list looks for
	materials/maps/<map>.png; some packs ship materials/maps/thumb/<map>.png
	instead. Check both once per map and fall back to a generated tile rather
	than an error texture.
*/
local thumbCache = {}

local function MapThumb( map )

	if ( thumbCache[ map ] ~= nil ) then return thumbCache[ map ] end

	local paths = { "maps/thumb/" .. map .. ".png", "maps/" .. map .. ".png" }

	for _, rel in ipairs( paths ) do
		if ( file.Exists( "materials/" .. rel, "GAME" ) ) then
			local mat = Material( rel )
			if ( mat && !mat:IsError() ) then
				thumbCache[ map ] = mat
				return mat
			end
		end
	end

	thumbCache[ map ] = false
	return false

end

// Deterministic colour per map name, so a map without a thumbnail still gets a
// stable identity instead of a flat grey rectangle.
local function MapTint( map )

	local h = 0
	for i = 1, #map do h = ( h * 31 + map:byte( i ) ) % 360 end

	return HSVToColor( h, 0.45, 0.38 )

end

local function DrawBlur( panel, amount )

	local x, y = panel:LocalToScreen( 0, 0 )

	surface.SetDrawColor( 255, 255, 255, 255 )
	surface.SetMaterial( matBlur )
	matBlur:SetFloat( "$blur", amount )
	render.UpdateScreenEffectTexture()
	surface.DrawTexturedRect( -x, -y, ScrW(), ScrH() )

end


/*---------------------------------------------------------
	PHXMapVoteCard - one map
---------------------------------------------------------*/
local PANEL = {}

function PANEL:Init()

	self.HoverFrac = 0
	self.Voters    = {}
	self.Faces     = {}
	self.NumVotes  = 0
	self.Share     = 0
	self.ShareShown = 0

	self:SetCursor( "hand" )

end

function PANEL:Setup( id, map, screen )
	self.ID     = id
	self.Map    = map
	self.Screen = screen
	self.Thumb  = MapThumb( map )
	self.Tint   = MapTint( map )

	// The name bar clips anything too long (ph_awesomewarehouse_night_map and
	// friends), so the full name is always available on hover.
	self:SetTooltip( map )
end

function PANEL:OnMousePressed( code )
	if ( code == MOUSE_LEFT && IsValid( self.Screen ) ) then
		self.Screen:CastVote( self.ID )
	end
end

// Avatars are real panels, so only rebuild them when the voter set changes.
function PANEL:SetVoters( players )

	local same = ( #players == #self.Voters )

	if ( same ) then
		for i, ply in ipairs( players ) do
			if ( self.Voters[ i ] ~= ply ) then same = false break end
		end
	end

	if ( same ) then return end

	self.Voters = players

	for _, f in ipairs( self.Faces ) do f:Remove() end
	self.Faces = {}

	for i = 1, math.min( #players, MAX_FACES ) do
		local av = vgui.Create( "AvatarImage", self )
		av:SetMouseInputEnabled( false )
		av:SetPlayer( players[ i ], 32 )
		av:SetTooltip( players[ i ]:Nick() )
		table.insert( self.Faces, av )
	end

	self:InvalidateLayout()

end

function PANEL:PerformLayout( w, h )

	local size = MVScale( 20 )
	local pad  = MVScale( 8 )
	local x    = w - pad - size

	for _, av in ipairs( self.Faces ) do
		av:SetSize( size, size )
		av:SetPos( x, self:ThumbHeight() - size - pad )
		x = x - size - MVScale( 3 )
	end

end

function PANEL:ThumbHeight()
	return self:GetTall() - MVScale( 44 )
end

function PANEL:Paint( w, h )

	local selected = ( self.Screen && self.Screen.MyVote == self.ID )
	local winner   = ( self.Screen && self.Screen.Winner == self.ID )

	self.HoverFrac  = math.Approach( self.HoverFrac, self:IsHovered() and 1 or 0, FrameTime() * 6 )
	self.ShareShown = math.Approach( self.ShareShown, self.Share, FrameTime() * 1.5 )

	local r  = MVScale( 6 )
	local th = self:ThumbHeight()

	draw.RoundedBox( r, 0, 0, w, h, COL_CARD )

	if ( self.HoverFrac > 0 ) then
		draw.RoundedBox( r, 0, 0, w, h,
			Color( COL_CARD_HI.r, COL_CARD_HI.g, COL_CARD_HI.b, 255 * self.HoverFrac ) )
	end

	// Thumbnail, or a tinted tile carrying the map name so a missing image
	// still reads as a deliberate card.
	render.SetScissorRect( 0, 0, 0, 0, false )

	if ( self.Thumb ) then
		surface.SetDrawColor( 255, 255, 255, 255 )
		surface.SetMaterial( self.Thumb )
		surface.DrawTexturedRect( 0, 0, w, th )
	else
		// No name here: the bar directly below already carries it, and printing
		// it twice per card just read as a doubled label. The tint alone is the
		// map's identity; the gradient keeps it from looking like a flat swatch.
		draw.RoundedBoxEx( r, 0, 0, w, th, self.Tint, true, true, false, false )

		surface.SetDrawColor( 0, 0, 0, 70 )
		surface.SetMaterial( matGrad )
		surface.DrawTexturedRect( 0, 0, w, th )
	end

	// Scrim under the avatars, so faces stay legible over a bright thumbnail.
	// Only when there are faces - otherwise it is an unexplained dark band
	// across the bottom of every card.
	if ( #self.Voters > 0 ) then
		surface.SetDrawColor( 0, 0, 0, 90 )
		surface.DrawRect( 0, th - MVScale( 34 ), w, MVScale( 34 ) )
	end

	local pad = MVScale( 9 )

	// Name, clipped so a long map name cannot run under the vote count.
	local sx, sy = self:LocalToScreen( pad, th )
	local nameW  = w - pad * 2 - MVScale( 46 )

	render.SetScissorRect( sx, sy, sx + nameW, sy + MVScale( 44 ), true )
	draw.SimpleText( self.Map, "PHX.MV.Card", pad, th + MVScale( 14 ),
		COL_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
	render.SetScissorRect( 0, 0, 0, 0, false )

	draw.SimpleText( self.NumVotes, "PHX.MV.Count", w - pad, th + MVScale( 13 ),
		self.NumVotes > 0 and COL_TEXT or COL_DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER )

	if ( #self.Voters > MAX_FACES ) then
		draw.SimpleText( "+" .. ( #self.Voters - MAX_FACES ), "PHX.MV.Small",
			w - pad - MVScale( 23 ) * MAX_FACES, th - MVScale( 18 ),
			COL_TEXT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER )
	end

	// Share of the vote along the bottom edge.
	local barH = MVScale( 3 )
	if ( self.ShareShown > 0 ) then
		draw.RoundedBoxEx( r, 0, h - barH, math.max( barH, w * self.ShareShown ), barH,
			winner and COL_WIN or COL_ACCENT, false, false, true, true )
	end

	local edge = winner and COL_WIN or ( selected and COL_ACCENT or nil )

	if ( edge ) then
		surface.SetDrawColor( edge )
		surface.DrawOutlinedRect( 0, 0, w, h, MVScale( 2 ) )
	end

	if ( self.Flashing ) then
		draw.RoundedBox( r, 0, 0, w, h, Color( COL_WIN.r, COL_WIN.g, COL_WIN.b, 60 ) )
	end

end

vgui.Register( "PHXMapVoteCard", PANEL, "Panel" )


/*---------------------------------------------------------
	PHXMapVote - the vote screen
---------------------------------------------------------*/
local PANEL = {}

function PANEL:Init()

	self.Cards  = {}
	self.MyVote = nil
	self.Winner = nil

	self:SetSize( ScrW(), ScrH() )
	self:SetPos( 0, 0 )
	self:ParentToHUD()

	// MakePopup on a child canvas, the way the original did: the vote needs the
	// cursor without the whole HUD taking keyboard focus.
	self.Canvas = vgui.Create( "Panel", self )
	self.Canvas:MakePopup()
	self.Canvas:SetKeyboardInputEnabled( false )
	self.Canvas.Paint = function( pnl, w, h )
		draw.RoundedBox( MVScale( 10 ), 0, 0, w, h, COL_BG )
		self:PaintChrome( w, h )
	end

	self.Scroll = vgui.Create( "DScrollPanel", self.Canvas )
	self.Scroll:SetPaintBackground( false )

	local bar = self.Scroll:GetVBar()
	bar:SetWide( MVScale( 8 ) )
	bar:SetHideButtons( true )
	bar.Paint = function( _, w, h )
		draw.RoundedBox( MVScale( 4 ), 0, 0, w, h, Color( 255, 255, 255, 18 ) )
	end
	bar.btnGrip.Paint = function( pnl, w, h )
		draw.RoundedBox( MVScale( 4 ), 0, 0, w, h,
			Color( 255, 255, 255, pnl.Depressed and 190 or ( pnl:IsHovered() and 150 or 110 ) ) )
	end

	self.CancelBtn = vgui.Create( "DButton", self.Canvas )
	self.CancelBtn:SetText( "" )
	self.CancelBtn:SetVisible( false )
	self.CancelBtn.Paint = function( pnl, w, h )
		draw.RoundedBox( MVScale( 5 ), 0, 0, w, h,
			pnl:IsHovered() and Color( 150, 60, 55, 255 ) or Color( 90, 44, 42, 255 ) )
		draw.SimpleText( Tr( "PHXM_MV_CANCEL", "Cancel vote" ), "PHX.MV.Sub",
			w * 0.5, h * 0.5, COL_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
	end
	self.CancelBtn.DoClick = function()
		LocalPlayer():ConCommand( "mv_stop" )
	end

end

/*
	The server drops votes that arrive inside its cooldown
	(sv_mapvote.lua, VOTE_COOLDOWN). Sending blindly would let a quick change of
	mind be silently thrown away, so the pick is shown immediately and the send
	is debounced on the trailing edge - the last map clicked is always the one
	that reaches the server.
*/
function PANEL:CastVote( id )

	if ( self.Winner ) then return end

	self.MyVote = id

	local wait = ( self.NextSend or 0 ) - CurTime()

	if ( wait > 0 ) then
		self.Pending = id
		return
	end

	self:SendVote( id )

end

function PANEL:SendVote( id )

	self.NextSend = CurTime() + 0.45
	self.Pending  = nil

	net.Start( "RAM_MapVoteUpdate" )
		net.WriteUInt( MapVote.UPDATE_VOTE, 3 )
		net.WriteUInt( id, 32 )
	net.SendToServer()

end

function PANEL:SetMaps( maps )

	for _, c in ipairs( self.Cards ) do c:Remove() end
	self.Cards = {}

	// RandomPairs so the same map is not always top-left, matching the original.
	for id, map in RandomPairs( maps ) do
		local card = self.Scroll:Add( "PHXMapVoteCard" )
		card:Setup( id, map, self )
		table.insert( self.Cards, card )
	end

	self:InvalidateLayout()

end

function PANEL:GetCard( id )
	for _, c in ipairs( self.Cards ) do
		if ( c.ID == id ) then return c end
	end
end

// Kept because the net handler calls it; the tally is rebuilt in Think, so this
// only needs to make sure a newly arrived vote is reflected promptly.
function PANEL:AddVoter()
	self.Dirty = true
end

function PANEL:Think()

	if ( self.Pending && ( self.NextSend or 0 ) <= CurTime() ) then
		self:SendVote( self.Pending )
	end

	// Rebuild the tally from MapVote.Votes every frame: it is keyed by SteamID,
	// so players who disconnected mid-vote simply stop being found and drop out
	// without any bookkeeping.
	local byMap, total = {}, 0

	for _, ply in ipairs( player.GetAll() ) do
		local id = MapVote.Votes[ ply:SteamID() ]
		if ( id ) then
			byMap[ id ] = byMap[ id ] or { players = {}, votes = 0 }
			table.insert( byMap[ id ].players, ply )

			local weight = MapVote.HasExtraVotePower( ply ) and 2 or 1
			byMap[ id ].votes = byMap[ id ].votes + weight
			total = total + weight
		end
	end

	for _, card in ipairs( self.Cards ) do
		local e = byMap[ card.ID ]

		card.NumVotes = e and e.votes or 0
		card.Share    = ( total > 0 ) and ( card.NumVotes / total ) or 0
		card:SetVoters( e and e.players or {} )
	end

	self.Total = total

end

function PANEL:PerformLayout( w, h )

	self:SetSize( ScrW(), ScrH() )

	local cw = math.min( ScrW() * 0.86, MVScale( 1220 ) )
	local ch = math.min( ScrH() * 0.86, MVScale( 840 ) )

	self.Canvas:SetSize( cw, ch )
	self.Canvas:SetPos( ( ScrW() - cw ) * 0.5, ( ScrH() - ch ) * 0.5 )

	local pad     = MVScale( 20 )
	local headerH = MVScale( 96 )
	local footerH = MVScale( 46 )

	self.Scroll:SetPos( pad, headerH )
	self.Scroll:SetSize( cw - pad * 2, math.max( 0, ch - headerH - footerH ) )

	// Flow the cards, wrapping to as many rows as needed.
	local gap    = MVScale( 12 )
	local cardW  = MVScale( 236 )
	local cardH  = MVScale( 166 )
	local avail  = self.Scroll:GetWide() - MVScale( 10 )
	local cols   = math.max( 1, math.floor( ( avail + gap ) / ( cardW + gap ) ) )

	// Spread any leftover width across the columns rather than leaving a gutter.
	local realW = math.floor( ( avail - gap * ( cols - 1 ) ) / cols )

	for i, card in ipairs( self.Cards ) do
		local col = ( i - 1 ) % cols
		local row = math.floor( ( i - 1 ) / cols )

		card:SetSize( realW, cardH )
		card:SetPos( col * ( realW + gap ), row * ( cardH + gap ) )
	end

	self.CancelBtn:SetSize( MVScale( 150 ), MVScale( 30 ) )
	self.CancelBtn:SetPos( cw - pad - MVScale( 150 ), ch - footerH + MVScale( 8 ) )

	local staff = LocalPlayer().PHXIsStaff and LocalPlayer():PHXIsStaff()
	self.CancelBtn:SetVisible( staff and !self.Winner )

end

function PANEL:Paint( w, h )

	DrawBlur( self, 5 )

	surface.SetDrawColor( COL_SHADE )
	surface.DrawRect( 0, 0, w, h )

end

/*
	Header and footer, drawn by the canvas rather than by this panel.

	self.Canvas is MakePopup'd, which puts it in the popup render layer - above
	everything this panel draws. Painting the chrome here would bury it behind
	the canvas background, so it is drawn from the canvas itself, in canvas-local
	coordinates.
*/
function PANEL:PaintChrome( cw, ch )

	local cx, cy = 0, 0
	local pad    = MVScale( 20 )

	local left = math.Clamp( MapVote.EndTime - CurTime(), 0, math.huge )
	local secs = math.ceil( left )
	local urgent = ( secs <= 5 && !self.Winner )

	local title = self.Winner
		and Tr( "PHXM_MV_WINNER", "Next map" )
		or  Tr( "PHXM_MV_TITLE", "Vote for the next map" )

	draw.SimpleText( title, "PHX.MV.Title", cx + pad, cy + MVScale( 18 ),
		COL_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )

	local sub = self.Winner and ( MapVote.CurrentMaps[ self.Winner ] or "" )
		or Tr( "PHXM_MV_TALLY", ( self.Total or 0 ) .. " / " .. #player.GetAll() .. " voted",
			self.Total or 0, #player.GetAll() )

	draw.SimpleText( sub, "PHX.MV.Sub", cx + pad, cy + MVScale( 56 ),
		self.Winner and COL_WIN or COL_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )

	if ( !self.Winner ) then
		draw.SimpleText( secs, "PHX.MV.Clock", cx + cw - pad, cy + MVScale( 20 ),
			urgent and COL_URGENT or COL_TEXT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP )
	end

	// Time remaining as a bar under the header.
	local barY = cy + MVScale( 86 )
	local frac = ( MapVote.Duration && MapVote.Duration > 0 ) and math.Clamp( left / MapVote.Duration, 0, 1 ) or 0

	surface.SetDrawColor( COL_BORDER )
	surface.DrawRect( cx + pad, barY, cw - pad * 2, 1 )

	if ( !self.Winner && frac > 0 ) then
		surface.SetDrawColor( urgent and COL_URGENT or COL_ACCENT )
		surface.DrawRect( cx + pad, barY - MVScale( 1 ), ( cw - pad * 2 ) * frac, MVScale( 2 ) )
	end

	draw.SimpleText( Tr( "PHXM_MV_HINT", "Click a map to vote. You can change your mind." ),
		"PHX.MV.Small", cx + pad, ch - MVScale( 30 ),
		COL_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )

end

function PANEL:Flash( id )

	self:SetVisible( true )
	self.Winner = id
	self.CancelBtn:SetVisible( false )

	local card = self:GetCard( id )
	if ( !IsValid( card ) ) then return end

	for i = 0, 2 do
		timer.Simple( i * 0.4, function()
			if ( !IsValid( card ) ) then return end
			card.Flashing = true
			surface.PlaySound( "hl1/fvox/blip.wav" )
		end )
		timer.Simple( i * 0.4 + 0.2, function()
			if ( IsValid( card ) ) then card.Flashing = false end
		end )
	end

	timer.Simple( 1.2, function()
		if ( IsValid( card ) ) then card.Flashing = true end
	end )

end

vgui.Register( "PHXMapVote", PANEL, "Panel" )
