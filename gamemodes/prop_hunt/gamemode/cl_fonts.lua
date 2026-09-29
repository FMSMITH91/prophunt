-- Every font that draws text sets `extended`: without it only Latin-1 glyphs
-- render, so the Russian, Korean, Chinese, Polish and Turkish translations (and
-- non-Latin player names) came out with missing characters.

-- cl_init.lua
surface.CreateFont( "HunterBlindLockFont", {
	font	= "Arial",
	size	= 26,
	weight	= 1200,
	antialias = true,
	underline = false,
	extended = true
})

surface.CreateFont("TrebuchetBig", {
	font = "Impact",
	size = 40,
	extended = true
})

-- cl_menu.lua
surface.CreateFont("PHX.MenuCategoryLabel", 
{
	font = "Roboto",
	size = 26,
	weight = 500,
	antialias = true,
	shadow = true,
	extended = true
})

-- cl_hud.lua
surface.CreateFont("PHX.HealthFont", 
{
	font = "Roboto",
	size = 56,
	weight = 650,
	antialias = true,
	shadow = true,
	extended = true
})

surface.CreateFont("PHX.AmmoFont", 
{
	font = "Roboto",
	size = 16,
	weight = 500,
	antialias = true,
	shadow = true,
	extended = true
})

surface.CreateFont("PHX.ArmorFont", 
{
	font = "Roboto",
	size = 32,
	weight = 500,
	antialias = true,
	shadow = true,
	extended = true
})

surface.CreateFont("PHX.TopBarFont", 
{
	font = "Roboto",
	size = 20,
	weight = 500,
	antialias = true,
	shadow = true,
	extended = true
})
surface.CreateFont("PHX.TopBarFontTeam", 
{
	font = "Roboto",
	size = 60,
	weight = 650,
	antialias = true,
	shadow = true,
	extended = true
})

-- cl_fb_core.lua - the Prop Menu File browser.
surface.CreateFont("RobotoInfo", {
	font	= "Roboto",
	size	= 24,
	weight	= 750,
	extended	= true
})
surface.CreateFont("RobotoWarn", {
	font	= "Roboto",
	size	= 16,
	weight	= 750,
	extended	= true
})

-- cl_chat.lua
surface.CreateFont("PHX_NicePrintCenter", {
	font	= "Roboto",
	size	= 32,
	weight	= 750,
	shadow	= true,
	extended	= true
})

-- cl_credits.lua
surface.CreateFont("PHX.TitleFont", 
	{
		font = "Roboto",
		size = 40,
		weight = 700,
		antialias = true,
		shadow = true,
		extended = true
	})

-- cl_tauntwindow.lua
surface.CreateFont("PHX.TauntFont", 
{
	font = "Roboto",
	size = 19,
	weight = 500,
	antialias = true,
	shadow = false,
	extended = true
})

-- Map Votes fonts
surface.CreateFont("RAM_VoteFont", {
    font = "Trebuchet MS",
    size = 19,
    weight = 700,
    antialias = true,
    shadow = true,
    extended = true
})

surface.CreateFont("RAM_VoteFontCountdown", {
    font = "Tahoma",
    size = 32,
    weight = 700,
    antialias = true,
    shadow = true,
    extended = true
})

surface.CreateFont("RAM_VoteSysButton", 
{    font = "Marlett",
    size = 13,
    weight = 0,
    symbol = true,
})

-- Chat Fonts
surface.CreateFont( "eChat_18", {
	font = "Roboto Lt",
	size = 18,
	weight = 500,
	antialias = true,
	shadow = true,
	extended = true,
} )

surface.CreateFont( "eChat_16", {
	font = "Roboto Lt",
	size = 16,
	weight = 500,
	antialias = true,
	shadow = true,
	extended = true,
} )