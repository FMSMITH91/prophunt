/*
	vgui_scoreboard_modern.lua - Prop Hunt: X2Z modern scoreboard
	-----------------------------------------------------------------
	A replacement for the Fretta DListView scoreboard. Everything is drawn
	directly instead of going through DListView + skin hooks, which is what made
	the old board rigid (fixed 21px pills, no hover, no scrolling) and fragile
	(clicking a row called ApplySchemeSettings on every column, including the
	avatar, which has no such method).

	The classic board is untouched and still selectable with
	ph_cl_modern_scoreboard 0.

	Do not call into PHX at file scope: base_phx is loaded through
	DeriveGamemode, so PHX may not exist yet when this file runs. Everything
	that touches PHX does so from inside a function.
*/

// Sizes are tuned against 1080p and scaled from there so the board does not
// turn into a stamp at 1440p or overflow at 900p.
local function SBScale( n )
	return math.Round( n * math.Clamp( ScrH() / 1080, 0.8, 1.6 ) )
end

local function SBFont( name, size, weight )
	surface.CreateFont( name, {
		font      = "Roboto",
		size      = SBScale( size ),
		weight    = weight,
		antialias = true,
		extended  = true
	} )
end

SBFont( "PHX.SB.Title",     28, 700 )
SBFont( "PHX.SB.Sub",       15, 500 )
SBFont( "PHX.SB.TeamName",  21, 700 )
SBFont( "PHX.SB.TeamScore", 30, 700 )
SBFont( "PHX.SB.Label",     13, 700 )
SBFont( "PHX.SB.Row",       17, 500 )
SBFont( "PHX.SB.RowBold",   17, 700 )

local COL_SHADE     = Color(  10,  11,  14, 200 )
local COL_BG        = Color(  20,  22,  28, 244 )
local COL_CARD      = Color(  27,  30,  38, 255 )
local COL_ROW       = Color(  35,  39,  49, 255 )
local COL_ROW_ALT   = Color(  31,  35,  44, 255 )
local COL_ROW_HOVER = Color(  48,  54,  67, 255 )
local COL_TEXT      = Color( 234, 237, 242, 255 )
local COL_TEXT_DIM  = Color( 140, 148, 163, 255 )
local COL_BORDER    = Color( 255, 255, 255,  18 )

local COL_PING_GOOD = Color(  92, 200, 118, 255 )
local COL_PING_OK   = Color( 224, 184,  74, 255 )
local COL_PING_BAD  = Color( 224,  94,  84, 255 )

local matMute   = Material( "icon16/sound_mute.png" )
local matUnmute = Material( "icon16/sound.png" )
local matGagged = Material( "icon16/exclamation.png" )
local matStaff  = Material( "icon16/shield.png" )
local matBlur   = Material( "pp/blurscreen" )

local PAD_ROW = 10

local function PingColor( ping )
	if ( ping <= 0 ) then return COL_TEXT_DIM end
	if ( ping < 80 ) then return COL_PING_GOOD end
	if ( ping < 150 ) then return COL_PING_OK end
	return COL_PING_BAD
end

/*
	Cells are placed from the right edge inwards, so adding a custom column
	never shifts kills/deaths/ping. Both the row and the team header call this
	with their own width, which is what keeps the column labels sitting over
	the values instead of drifting by the scrollbar's width.
*/
local function ComputeCellX( cells, w )

	local xs    = {}
	local right = w - SBScale( PAD_ROW )

	for i = #cells, 1, -1 do
		right = right - cells[ i ].w
		xs[ i ] = right
	end

	return xs

end

// One pass, like the skin's PaintScorePanel. render.UpdateScreenEffectTexture
// is the expensive part and the dim layer drawn over this hides all but a
// little of the blur anyway, so extra passes cost frames for nothing.
local function DrawBlur( panel, amount )

	local x, y = panel:LocalToScreen( 0, 0 )

	surface.SetDrawColor( 255, 255, 255, 255 )
	surface.SetMaterial( matBlur )

	matBlur:SetFloat( "$blur", amount )
	render.UpdateScreenEffectTexture()
	surface.DrawTexturedRect( -x, -y, ScrW(), ScrH() )

end

local function DrawIcon( mat, x, y, size, alpha )
	surface.SetDrawColor( 255, 255, 255, alpha )
	surface.SetMaterial( mat )
	surface.DrawTexturedRect( x, y, size, size )
end


/*---------------------------------------------------------
	PHXScoreRow - one player
---------------------------------------------------------*/
local PANEL = {}

function PANEL:Init()

	self.HoverFrac    = 0
	self.Cells        = {}
	self.CellX        = {}
	self.CustomPanels = {}
	self.NameX        = SBScale( 46 )
	self.NameW        = 0

	self.Avatar = vgui.Create( "AvatarImage", self )

	// A child button rather than the row's own OnMousePressed, so the hand
	// cursor and the hit area follow the name column exactly.
	self.ProfileBtn = vgui.Create( "DButton", self )
	self.ProfileBtn:SetText( "" )
	self.ProfileBtn.Paint = function() end
	self.ProfileBtn.DoClick = function()
		if ( PHX && PHX.OpenSteamProfile ) then PHX:OpenSteamProfile( self.pPlayer ) end
	end
	self.ProfileBtn.DoRightClick = function() self:OpenMenu() end

	self.MuteBtn = vgui.Create( "DButton", self )
	self.MuteBtn:SetText( "" )
	self.MuteBtn.Paint = function( btn, w, h )
		local ply = self.pPlayer
		if ( !IsValid( ply ) || ply == LocalPlayer() ) then return end

		local allowed = PHX && PHX.CanMutePlayer && PHX:CanMutePlayer( ply )
		local muted   = ply:IsMuted()
		local size    = SBScale( 16 )

		DrawIcon( muted and matMute or matUnmute,
			( w - size ) * 0.5, ( h - size ) * 0.5, size,
			allowed and ( btn:IsHovered() and 255 or 185 ) or 65 )
	end
	self.MuteBtn.DoClick = function()
		local ply = self.pPlayer
		if ( !IsValid( ply ) || ply == LocalPlayer() ) then return end
		if ( !PHX || !PHX.CanMutePlayer || !PHX:CanMutePlayer( ply ) ) then return end

		ply:SetMuted( !ply:IsMuted() )
	end
	self.MuteBtn.DoRightClick = function() self:OpenMenu() end

end

function PANEL:OpenMenu()

	if ( !PHX || !PHX.OpenPlayerMenu ) then return end

	local menu = PHX:OpenPlayerMenu( self.pPlayer )
	if ( IsValid( menu ) ) then menu:Open() end

end

function PANEL:OnMousePressed( code )
	if ( code == MOUSE_RIGHT ) then self:OpenMenu() end
end

function PANEL:SetPlayer( ply )

	if ( self.pPlayer == ply ) then return end

	self.pPlayer = ply
	self.Avatar:SetPlayer( ply, 64 )

	local canOpen = PHX && PHX.CanOpenSteamProfile && PHX:CanOpenSteamProfile( ply )

	self.ProfileBtn:SetCursor( canOpen and "hand" or "arrow" )

	if ( canOpen && PHX.FTranslate ) then
		self.ProfileBtn:SetTooltip( PHX:FTranslate( "DERMA_OPEN_STEAM_PROFILE" ) )
	else
		self.ProfileBtn:SetTooltip( nil )
	end

end

function PANEL:SetCells( cells )
	self.Cells = cells or {}
end

function PANEL:PerformLayout( w, h )

	local pad  = SBScale( PAD_ROW )
	local size = h - SBScale( 8 )

	self.Avatar:SetPos( pad, ( h - size ) * 0.5 )
	self.Avatar:SetSize( size, size )

	self.CellX = ComputeCellX( self.Cells, w )

	local firstX = self.CellX[ 1 ] or ( w - pad )

	self.NameX = pad + size + SBScale( 10 )
	self.NameW = math.max( 0, firstX - self.NameX - SBScale( 6 ) )

	self.ProfileBtn:SetPos( 0, 0 )
	self.ProfileBtn:SetSize( self.NameX + self.NameW, h )

	local muteW = SBScale( 22 )
	self.MuteBtn:SetSize( muteW, h )
	self.MuteBtn:SetPos( w - pad - muteW, 0 )

	// Custom columns that handed us a Panel rather than a value.
	for i, cell in ipairs( self.Cells ) do
		local pnl = self.CustomPanels[ cell.id ]
		if ( IsValid( pnl ) ) then
			pnl:SetSize( cell.w, h )
			pnl:SetPos( self.CellX[ i ] or 0, 0 )
		end
	end

end

function PANEL:Paint( w, h )

	local ply = self.pPlayer
	if ( !IsValid( ply ) ) then return end

	local alive   = ply:Alive()
	local isSelf  = ( ply == LocalPlayer() )
	local hovered = self:IsHovered() || self:IsChildHovered()

	self.HoverFrac = math.Approach( self.HoverFrac, hovered and 1 or 0, FrameTime() * 6 )

	local radius = SBScale( 5 )

	draw.RoundedBox( radius, 0, 0, w, h, self.bAlt and COL_ROW_ALT or COL_ROW )

	if ( self.HoverFrac > 0 ) then
		draw.RoundedBox( radius, 0, 0, w, h,
			Color( COL_ROW_HOVER.r, COL_ROW_HOVER.g, COL_ROW_HOVER.b, 255 * self.HoverFrac ) )
	end

	// Your own row gets a tinted wash and a solid accent bar on the left.
	if ( isSelf ) then
		local tc = team.GetColor( ply:Team() )
		draw.RoundedBox( radius, 0, 0, w, h, Color( tc.r, tc.g, tc.b, 38 ) )
		draw.RoundedBoxEx( radius, 0, 0, SBScale( 3 ), h, tc, true, false, true, false )
	end

	// A dead player keeps their row but reads as inactive.
	local fade = alive and 255 or 105
	self.Avatar:SetAlpha( fade )

	local textX = self.NameX
	local iconY = ( h - SBScale( 14 ) ) * 0.5

	if ( ply.PHXIsStaff && ply:PHXIsStaff() ) then
		DrawIcon( matStaff, textX, iconY, SBScale( 14 ), fade )
		textX = textX + SBScale( 18 )
	end

	if ( PHX && PHX.IsULXGagged && PHX:IsULXGagged( ply ) ) then
		DrawIcon( matGagged, textX, iconY, SBScale( 14 ), fade )
		textX = textX + SBScale( 18 )
	end

	local nameW = math.max( 0, self.NameX + self.NameW - textX )

	local sx, sy = self:LocalToScreen( textX, 0 )
	render.SetScissorRect( sx, sy, sx + nameW, sy + h, true )
	draw.SimpleText( ply:Nick(), isSelf and "PHX.SB.RowBold" or "PHX.SB.Row",
		textX, h * 0.5, ColorAlpha( isSelf and color_white or COL_TEXT, fade ),
		TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
	render.SetScissorRect( 0, 0, 0, 0, false )

	for i, cell in ipairs( self.Cells ) do
		if ( cell.draw ) then cell.draw( self, ply, self.CellX[ i ] or 0, cell, h, fade ) end
	end

end

vgui.Register( "PHXScoreRow", PANEL, "Panel" )


/*---------------------------------------------------------
	PHXScoreTeam - one team card
---------------------------------------------------------*/
local PANEL = {}

function PANEL:Init()

	self.Rows = {}

	self.Scroll = vgui.Create( "DScrollPanel", self )
	self.Scroll:SetPaintBackground( false )

	local bar = self.Scroll:GetVBar()
	bar:SetWide( SBScale( 6 ) )
	bar:SetHideButtons( true )
	bar.Paint = function() end
	bar.btnGrip.Paint = function( _, w, h )
		draw.RoundedBox( SBScale( 3 ), 0, 0, w, h, Color( 255, 255, 255, 40 ) )
	end

end

function PANEL:Setup( iTeam, pMain )
	self.iTeam = iTeam
	self.pMain = pMain
end

function PANEL:HeaderHeight()
	return SBScale( 46 ) + SBScale( 22 )
end

function PANEL:ScrollInset()
	return SBScale( 6 )
end

function PANEL:Paint( w, h )

	local tc  = team.GetColor( self.iTeam )
	local pad = SBScale( 12 )

	draw.RoundedBox( SBScale( 6 ), 0, 0, w, h, COL_CARD )

	// Team strip: a dimmed band in the team colour with a bright underline.
	local hh = SBScale( 46 )
	draw.RoundedBoxEx( SBScale( 6 ), 0, 0, w, hh,
		Color( tc.r * 0.34, tc.g * 0.34, tc.b * 0.34, 255 ), true, true, false, false )

	surface.SetDrawColor( tc )
	surface.DrawRect( 0, hh - SBScale( 2 ), w, SBScale( 2 ) )

	local name = ( PHX && PHX.TranslateName ) and PHX:TranslateName( self.iTeam ) or team.GetName( self.iTeam )
	draw.SimpleText( name, "PHX.SB.TeamName", pad, hh * 0.5, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )

	surface.SetFont( "PHX.SB.TeamName" )
	local nameW = surface.GetTextSize( name )

	// DERMA_PLAYERS is a format string - "(%d players)" - and already carries
	// its own brackets, so it takes the count rather than being concatenated.
	local count    = #team.GetPlayers( self.iTeam )
	local countStr = "(" .. count .. " players)"

	if ( PHX && PHX.SBTranslate ) then
		countStr = PHX:SBTranslate( "DERMA_PLAYERS", countStr, count )
	end

	draw.SimpleText( countStr, "PHX.SB.Sub",
		pad + nameW + SBScale( 8 ), hh * 0.5 + SBScale( 1 ), COL_TEXT_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )

	draw.SimpleText( team.GetScore( self.iTeam ), "PHX.SB.TeamScore", w - pad, hh * 0.5,
		color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER )

	// Column labels, positioned with the same maths the rows use so they line
	// up over their values. Rows live inside the scroll panel, hence the inset.
	local cells = self.pMain:GetCells()
	local inset = self:ScrollInset()

	// Measure the canvas, not the scroll panel: DScrollPanel narrows its canvas
	// by the scrollbar's width once the bar appears, and the headers have to
	// follow the rows when that happens.
	local canvas = self.Scroll:GetCanvas()
	local rowW   = IsValid( canvas ) and canvas:GetWide() or ( w - inset * 2 )

	local xs = ComputeCellX( cells, rowW )
	local ly = hh + SBScale( 11 )

	for i, cell in ipairs( cells ) do
		if ( cell.label && cell.label ~= "" ) then
			draw.SimpleText( cell.label, "PHX.SB.Label",
				inset + ( xs[ i ] or 0 ) + cell.w * 0.5, ly, COL_TEXT_DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP )
		end
	end

	local nameLbl = ( PHX && PHX.SBTranslate ) and PHX:SBTranslate( "DERMA_NAME", "Name" ) or "Name"
	draw.SimpleText( nameLbl, "PHX.SB.Label", pad, ly, COL_TEXT_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )

	surface.SetDrawColor( COL_BORDER )
	surface.DrawRect( pad, self:HeaderHeight() - SBScale( 4 ), w - pad * 2, 1 )

end

function PANEL:PerformLayout( w, h )

	local top   = self:HeaderHeight()
	local inset = self:ScrollInset()

	self.Scroll:SetPos( inset, top )
	self.Scroll:SetSize( w - inset * 2, math.max( 0, h - top - inset ) )

	local rh = self.pMain:GetRowHeight()
	for i, row in ipairs( self.Rows ) do
		row:SetTall( rh )
		row:DockMargin( 0, 0, 0, SBScale( 3 ) )
		row.bAlt = ( i % 2 == 0 )
	end

end

function PANEL:Think()

	local players = team.GetPlayers( self.iTeam )

	// Highest frags first, then fewest deaths, then name - the same intent as
	// the classic board's SetSortColumns( { 5, true, 6, false, 4, false } ).
	table.sort( players, function( a, b )
		if ( a:Frags() ~= b:Frags() ) then return a:Frags() > b:Frags() end
		if ( a:Deaths() ~= b:Deaths() ) then return a:Deaths() < b:Deaths() end
		return a:Nick():lower() < b:Nick():lower()
	end )

	// Rows are rebuilt only when the roster or its order actually changes;
	// every other frame just repaints what is already there.
	local dirty = ( #players ~= #self.Rows )

	if ( !dirty ) then
		for i, ply in ipairs( players ) do
			if ( self.Rows[ i ].pPlayer ~= ply ) then dirty = true break end
		end
	end

	if ( !dirty ) then return end

	for _, row in ipairs( self.Rows ) do row:Remove() end
	self.Rows = {}

	for _, ply in ipairs( players ) do
		local row = self.Scroll:Add( "PHXScoreRow" )
		row:Dock( TOP )
		row:SetCells( self.pMain:GetCells() )
		row:SetPlayer( ply )

		self.pMain:BuildCustomPanels( row, ply )

		table.insert( self.Rows, row )
	end

	self:InvalidateLayout()

end

vgui.Register( "PHXScoreTeam", PANEL, "Panel" )


/*---------------------------------------------------------
	PHXScoreboardModern - the board itself
---------------------------------------------------------*/
local PANEL = {}

AccessorFunc( PANEL, "m_iRowHeight", "RowHeight" )

function PANEL:Init()

	self.PHXModern  = true
	self.Boards     = {}
	self.SmallTeams = {}
	self.Cells      = {}
	self.CustomCols = {}
	self.SpecText   = ""

	self:SetRowHeight( SBScale( 34 ) )
	self:RebuildCells()

end

function PANEL:GetCells()
	return self.Cells
end

// Kills / deaths / ping / mute, with any custom columns ahead of them.
function PANEL:RebuildCells()

	// PHX:SBTranslate, not FTranslate: FTranslate returns the key itself for an
	// undefined string, so `FTranslate( k ) or fallback` can never fall back.
	local function Tr( key, fallback )
		if ( !PHX || !PHX.SBTranslate ) then return fallback end
		return PHX:SBTranslate( key, fallback )
	end

	local botTag = Tr( "DERMA_BOT_TAG", "BOT" )

	local function NumberCell( id, label, fnc )
		return {
			id    = id,
			label = label,
			w     = SBScale( 52 ),
			draw  = function( _, ply, x, cell, h, fade )
				draw.SimpleText( fnc( ply ), "PHX.SB.Row", x + cell.w * 0.5, h * 0.5,
					ColorAlpha( COL_TEXT, fade ), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
			end
		}
	end

	self.Cells = {}

	for _, col in ipairs( self.CustomCols ) do
		table.insert( self.Cells, col )
	end

	table.insert( self.Cells, NumberCell( "kills",  Tr( "DERMA_KILLS",  "Kills" ),  function( ply ) return ply:Frags() end ) )
	table.insert( self.Cells, NumberCell( "deaths", Tr( "DERMA_DEATHS", "Deaths" ), function( ply ) return ply:Deaths() end ) )

	table.insert( self.Cells, {
		id    = "ping",
		label = Tr( "DERMA_PING", "Ping" ),
		w     = SBScale( 56 ),
		draw  = function( _, ply, x, cell, h, fade )

			if ( ply:IsBot() ) then
				draw.SimpleText( botTag, "PHX.SB.Row", x + cell.w * 0.5, h * 0.5,
					ColorAlpha( COL_TEXT_DIM, fade ), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
				return
			end

			local ping = ply:Ping()
			local col  = PingColor( ping )

			draw.SimpleText( ping, "PHX.SB.Row", x + cell.w * 0.5 + SBScale( 5 ), h * 0.5,
				ColorAlpha( col, fade ), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )

			surface.SetDrawColor( ColorAlpha( col, fade ) )
			surface.DrawRect( x + SBScale( 2 ), h * 0.5 - SBScale( 3 ), SBScale( 6 ), SBScale( 6 ) )

		end
	} )

	// The mute button is a real child panel on the row; this cell only reserves
	// the space so nothing is drawn underneath it.
	table.insert( self.Cells, { id = "mute", label = "", w = SBScale( 26 ) } )

end

/*
	Compatibility shim for the PH_AddColumnScoreboard hook. Third-party columns
	keep the classic signature:

		AddColumn( Name, iFixedSize, fncValue, UpdateRate, TeamID, HeaderAlign, ValueAlign, Font )

	fncValue may return a value to print or a Panel to embed; both are handled.
	The returned table is the column, matching the classic board's contract.
*/
function PANEL:AddColumn( Name, iFixedSize, fncValue, UpdateRate, TeamID, HeaderAlign, ValueAlign, Font )

	local col = {
		id          = "custom_" .. ( #self.CustomCols + 1 ),
		label       = Name,
		w           = SBScale( iFixedSize or 60 ),
		fncValue    = fncValue,
		Font        = Font,
		TeamID      = TeamID,
		UpdateRate  = UpdateRate,
		HeaderAlign = HeaderAlign,
		ValueAlign  = ValueAlign
	}

	col.draw = function( row, ply, x, cell, h, fade )

		if ( !cell.fncValue ) then return end
		// A panel column draws itself; nothing to print here.
		if ( IsValid( row.CustomPanels[ cell.id ] ) ) then return end

		// Third-party code, so never let it take the whole scoreboard down.
		local ok, value = pcall( cell.fncValue, ply )
		if ( !ok || value == nil || type( value ) == "Panel" ) then return end

		draw.SimpleText( tostring( value ), cell.Font or "PHX.SB.Row", x + cell.w * 0.5, h * 0.5,
			ColorAlpha( COL_TEXT, fade ), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )

	end

	table.insert( self.CustomCols, col )
	self:RebuildCells()

	return col

end

// Called once per row, when the roster changes.
function PANEL:BuildCustomPanels( row, ply )

	for _, col in ipairs( self.CustomCols ) do
		if ( col.fncValue ) then

			local ok, value = pcall( col.fncValue, ply )

			if ( ok && type( value ) == "Panel" && IsValid( value ) ) then
				value:SetParent( row )
				row.CustomPanels[ col.id ] = value
			end

		end
	end

end

/*
	The classic board removes the team's card and replaces it with a one-line
	label. Here the team simply gets no card and is listed along the bottom
	instead, but the call is kept so GM:CreateScoreboard stays valid for both.
*/
function PANEL:SetAsBullshitTeam( iTeamID )
	self.SmallTeams[ iTeamID ] = true
end

function PANEL:SetupTeams( teams )

	for _, id in ipairs( teams ) do
		if ( !self.SmallTeams[ id ] && !IsValid( self.Boards[ id ] ) ) then
			local card = vgui.Create( "PHXScoreTeam", self )
			card:Setup( id, self )
			self.Boards[ id ] = card
		end
	end

	self:InvalidateLayout()

end

function PANEL:PositionSelf()

	local w = math.min( ScrW() * 0.8, SBScale( 1180 ) )
	local h = math.min( ScrH() * 0.84, SBScale( 820 ) )

	self:SetSize( w, h )
	self:SetPos( ( ScrW() - w ) * 0.5, ( ScrH() - h ) * 0.5 )

end

function PANEL:SpectatorText()

	local out = {}

	for id in pairs( self.SmallTeams ) do

		local players = team.GetPlayers( id )

		if ( #players > 0 ) then
			local names = {}
			for _, ply in ipairs( players ) do table.insert( names, ply:Nick() ) end

			local label = ( PHX && PHX.TranslateName ) and PHX:TranslateName( id ) or team.GetName( id )
			table.insert( out, label .. ": " .. table.concat( names, ", " ) )
		end

	end

	return table.concat( out, "   |   " )

end

function PANEL:PerformLayout( w, h )

	local pad     = SBScale( 14 )
	local headerH = SBScale( 74 )

	self.SpecText = self:SpectatorText()

	// The footer is always reserved, spectators or not, so the right-click hint
	// has somewhere to live and the cards do not jump when someone spectates.
	local footerH = SBScale( 28 )

	local cards = {}
	for _, card in pairs( self.Boards ) do table.insert( cards, card ) end
	if ( #cards == 0 ) then return end

	table.sort( cards, function( a, b ) return a.iTeam < b.iTeam end )

	local cardW = ( w - pad * ( #cards + 1 ) ) / #cards
	local cardH = math.max( 0, h - headerH - footerH - pad )

	local x = pad
	for _, card in ipairs( cards ) do
		card:SetPos( x, headerH )
		card:SetSize( cardW, cardH )
		x = x + cardW + pad
	end

	self.FooterY = headerH + cardH + SBScale( 6 )

end

function PANEL:Paint( w, h )

	DrawBlur( self, 6 )

	surface.SetDrawColor( COL_SHADE )
	surface.DrawRect( -self.x, -self.y, ScrW(), ScrH() )

	draw.RoundedBox( SBScale( 8 ), 0, 0, w, h, COL_BG )

	local pad = SBScale( 18 )

	draw.SimpleText( GetHostName(), "PHX.SB.Title", pad, SBScale( 13 ), COL_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )

	local sub = ( PHX && PHX.FTranslate )
		and PHX:FTranslate( "DERMA_GAMEMODE_CREDITS", GAMEMODE.Name, GAMEMODE._VERSION, GAMEMODE.REVISION )
		or GAMEMODE.Name

	draw.SimpleText( sub, "PHX.SB.Sub", pad, SBScale( 47 ), COL_TEXT_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )

	// Right side of the header: map, population, round.
	local info  = game.GetMap() .. "   -   " .. #player.GetAll() .. "/" .. game.MaxPlayers()
	local round = GetGlobalInt( "RoundNumber", 0 )

	if ( round > 0 ) then
		local lbl   = ( PHX && PHX.SBTranslate ) and PHX:SBTranslate( "HUD_ROUND", "ROUND" ) or "ROUND"
		local limit = ( GAMEMODE.RoundLimit && GAMEMODE.RoundLimit > 0 ) and ( "/" .. GAMEMODE.RoundLimit ) or ""

		info = info .. "   -   " .. lbl .. " " .. round .. limit
	end

	draw.SimpleText( info, "PHX.SB.Sub", w - pad, SBScale( 47 ), COL_TEXT_DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP )

	surface.SetDrawColor( COL_BORDER )
	surface.DrawRect( pad, SBScale( 70 ), w - pad * 2, 1 )

	if ( !self.FooterY ) then return end

	local hint = ( PHX && PHX.SBTranslate )
		and PHX:SBTranslate( "DERMA_MENU_HINT", "Right-click a player for options" )
		or "Right-click a player for options"

	surface.SetFont( "PHX.SB.Sub" )
	local hintW = surface.GetTextSize( hint )

	draw.SimpleText( hint, "PHX.SB.Sub", w - pad, self.FooterY, COL_TEXT_DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP )

	if ( self.SpecText && self.SpecText ~= "" ) then

		// Clipped so a long spectator list cannot run under the hint.
		local avail  = w - pad * 2 - hintW - SBScale( 16 )
		local sx, sy = self:LocalToScreen( pad, self.FooterY )

		render.SetScissorRect( sx, sy, sx + math.max( 0, avail ), sy + SBScale( 24 ), true )
		draw.SimpleText( self.SpecText, "PHX.SB.Sub", pad, self.FooterY, COL_TEXT_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP )
		render.SetScissorRect( 0, 0, 0, 0, false )

	end

end

vgui.Register( "PHXScoreboardModern", PANEL, "EditablePanel" )
