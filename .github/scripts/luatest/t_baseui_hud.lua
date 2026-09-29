dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- base_phx client odds and ends: HUDShouldDraw, the class chooser and help
-- splash, the team select spacer, and the client include list.

local here = (debug.getinfo(1, "S").source:match("@(.*/)") or "./")
local REPO = here .. "../../../"
local function noop() end
local function read(p) local f = io.open(REPO .. p); if not f then return nil end local s = f:read("*a"); f:close(); return s end

print("\n== HUDShouldDraw lets the active weapon hide HUD elements ==")
-- The engine base gamemode's HUDShouldDraw (gamemodes/base/gamemode/cl_init.lua)
-- is where SWEP:HUDShouldDraw is asked. Same logic, restated here because the
-- engine tree is not in this repo.
local BaseGM = {}
function BaseGM.HUDShouldDraw(_, name)
  local ply = LocalPlayer()
  if IsValid(ply) then
    local wep = ply:GetActiveWeapon()
    if IsValid(wep) and type(wep.HUDShouldDraw) == "function" then
      local ret = wep.HUDShouldDraw(wep, name)
      if ret ~= nil then return ret end
    end
  end
  return true
end
baseclass = { Get = function(n) assert(n == "gamemode_base", n); return BaseGM end }

local lp = S.Player{}
local wep = NULL
function lp:GetActiveWeapon() return wep end
function LocalPlayer() return lp end
loadblocks("cl_init.lua@HUDShouldDraw", extractAll("gamemodes/base_phx/gamemode/cl_init.lua", {
  [[^local BaseGM = baseclass.Get]], [[^function GM:HUDShouldDraw]] }))

local scope = { __valid = true, HUDShouldDraw = function(_, n) if n == "CHudCrosshair" then return false end end }
wep = scope
check("a scoped weapon hides the crosshair", GAMEMODE:HUDShouldDraw("CHudCrosshair"), false)
check("...and leaves everything else", GAMEMODE:HUDShouldDraw("CHudHealth"), true)
wep = { __valid = true }
check("a plain weapon: crosshair draws", GAMEMODE:HUDShouldDraw("CHudCrosshair"), true)
wep = NULL
check("no weapon: health draws", GAMEMODE:HUDShouldDraw("CHudHealth"), true)
lp._alive = false
check("dead: no damage indicator", GAMEMODE:HUDShouldDraw("CHudDamageIndicator"), false)
lp._alive = true
check("alive: damage indicator draws", GAMEMODE:HUDShouldDraw("CHudDamageIndicator"), true)
local saved = lp
lp = NULL
check("before the local player exists: no error",
  attempt(function() return GAMEMODE:HUDShouldDraw("CHudDamageIndicator") end), "ok")
lp = saved

print("\n== GetTeamColor still resolves the team after the rename ==")
function GAMEMODE:GetTeamNumColor(id) return "colour" .. tostring(id) end
loadblocks("cl_init.lua@GetTeamColor",
  extract("gamemodes/base_phx/gamemode/cl_init.lua", [[^function GM:GetTeamColor]]))
check("a player -> their team's colour", GAMEMODE:GetTeamColor(S.Player{ team = TEAM_HUNTERS }), "colour1")
check("no team -> unassigned", GAMEMODE:GetTeamColor({}), "colour1001")

-- Splash panels ---------------------------------------------------------------

-- vgui.CreateFromTable returns nil for a non-table, exactly as the engine's
-- scriptedpanels.lua does; that nil is what the old code then indexed.
local function Splash()
  local p = { buttons = {}, lblFooterText = {} }
  function p:AddSelectButton(name) local b = { name = name }; self.buttons[#self.buttons + 1] = b; return b end
  p.SetHeaderText, p.SetHoverText, p.SetForHelp, p.AddCancelButton = noop, noop, noop, noop
  p.MakePopup, p.NoFadeIn, p.AddPanelButton, p.Remove = noop, noop, noop, noop
  return p
end
vgui = vgui or {}
function vgui.CreateFromTable(t) if type(t) ~= "table" then return nil end return Splash() end
GAMEMODE.VGUISplash = {}

print("\n== The class chooser opens (it used the nil vgui_Splash) ==")
GAMEMODE.SelectClass = true
function team.GetClass() return { "class_a", "class_b" } end
player_class.Get = function(v) return { DisplayName = v:upper() } end
loadblocks("cl_gmchanger.lua", extract("gamemodes/base_phx/gamemode/cl_gmchanger.lua", "1-999999"))
check("ShowClassChooser does not raise", attempt(function() GAMEMODE:ShowClassChooser(TEAM_HUNTERS) end), "ok")
check("no global 'Classes' written", rawget(_G, "Classes"), nil)
check("no global 'cl_classsuicide' written", rawget(_G, "cl_classsuicide"), nil)
GAMEMODE.SelectClass = nil
check("SelectClass off: still a no-op", attempt(function() GAMEMODE:ShowClassChooser(TEAM_HUNTERS) end), "ok")

print("\n== base_phx's F1 help opens (it used the nil vgui_Splash) ==")
GAMEMODE.TeamBased = true
GAMEMODE.Name = "Prop Hunt"
loadblocks("cl_help.lua", "local cvPlayerModel, cvPlayerColor = nil, nil\n"
  .. extract("gamemodes/base_phx/gamemode/cl_help.lua", [[^function GM:ShowHelp]]))
check("ShowHelp does not raise", attempt(function() GAMEMODE:ShowHelp() end), "ok")

print("\n== F1 footer: no time limit never says the game is ending ==")
-- ph_game_time 0 makes GetTimeLimit -1. The footer's `tl == -1` early return
-- is what keeps `CurTime() > -1` from reading as "past the limit".
loadblocks("shared.lua@timelimit", extractAll("gamemodes/base_phx/gamemode/shared.lua", {
  [[^function GM:GetTimeLimit]], [[^function GM:GetGameTimeLeft]] }))
local help
function vgui.CreateFromTable() help = Splash(); return help end
GAMEMODE.RoundBased = true
GAMEMODE:ShowHelp()
local footer = help.lblFooterText
function footer:SetText(t) self.text = t end
GAMEMODE.GameLength, _G.CURTIME = 0, 5000
footer:Think()
check("ph_game_time 0: footer left alone", footer.text, nil)
GAMEMODE.GameLength = 15                       -- 900 s
footer:Think()
check("limit passed: ends after this round", footer.text, "MISC_GAMEEND")
_G.CURTIME = 100
footer:Think()
check("limit ahead: shows the time left", footer.text, "MISC_TIMELEFT")
_G.CURTIME = 1000

print("\n== Fretta fonts are extended (non-Latin glyphs render) ==")
local fonts = {}
surface = { CreateFont = function(name, data) fonts[name] = data end }
function ScrH() return 1080 end
loadblocks("cl_init.lua@CreateLegacyFont", extract("gamemodes/base_phx/gamemode/cl_init.lua",
  [[^function surface\.CreateLegacyFont]]))
-- Run cl_init.lua's own font lines (plain Lua, nothing to translate).
local made = 0
for call in ("\n" .. read("gamemodes/base_phx/gamemode/cl_init.lua")):gmatch("\n(surface%.CreateLegacyFont%b())") do
  loadchunk(call, "cl_init.lua@font")()
  made = made + 1
end
check("cl_init.lua builds the eight FRETTA_ fonts", made, 8)
local plain = {}
for name, data in pairs(fonts) do if data.extended ~= true then plain[#plain + 1] = name end end
table.sort(plain)
check("every one is extended", table.concat(plain, ","), "")
local m = fonts.FRETTA_MEDIUM_SHADOW
check("...and the other fields still pass through",
  m.font == "Roboto" and m.size == 19 and m.weight == 700 and m.antialias == true and m.shadow == true, true)

print("\n== Team select: the spacer before Spectators is laid out ==")
local SelectScreen = loadchunk("local PANEL = {}\n"
  .. extract("gamemodes/base_phx/gamemode/cl_selectscreen.lua", [[^function PANEL:AddSpacer]])
  .. "\nreturn PANEL", "cl_selectscreen.lua")()
vgui.Create = function(cls, parent)
  local p = { cls = cls, parent = parent }
  function p:SetTall(h) self.h = h end
  function p:SetSize(_, h) self.h = h end
  p.SetMouseInputEnabled = noop
  return p
end
local list = { items = {} }
function list:AddItem(it) self.items[#self.items + 1] = it end
local splash = { pnlButtons = list, Buttons = {} }
local spacer = SelectScreen.AddSpacer(splash, 12)
check("spacer is in the button list", list.items[1], spacer)
check("spacer keeps its height", spacer.h, 12)
check("spacer still tracked in Buttons", splash.Buttons[1], spacer)

print("\n== Every client include still resolves and is sent to clients ==")
-- vgui_vote.lua is deleted and cl_notify.lua no longer included; make sure
-- nothing still includes a file that is not there, or one init.lua never sends.
local initSrc = read("gamemodes/base_phx/gamemode/init.lua")
for _, file in ipairs{ "cl_init.lua", "cl_scores.lua", "cl_deathnotice.lua", "vgui/vgui_scoreboard.lua" } do
  local src = "\n" .. read("gamemodes/base_phx/gamemode/" .. file)
  local dir = file:match("^(.*/)") or ""
  for inc in src:gmatch("\ninclude%(%s*[\"']([^\"']+)[\"']%s*%)") do
    -- include() tries the including file's folder first, then the gamemode root.
    local path = read("gamemodes/base_phx/gamemode/" .. dir .. inc) and (dir .. inc) or inc
    check(("%s includes %s, which exists"):format(file, inc),
      read("gamemodes/base_phx/gamemode/" .. path) ~= nil, true)
    check(("...and init.lua AddCSLuaFile's %s"):format(path),
      initSrc:find("AddCSLuaFile%(%s*[\"']" .. path:gsub("%p", "%%%0") .. "[\"']%s*%)") ~= nil, true)
  end
end
check("nothing creates the unregistered VoteScreen",
  read("gamemodes/base_phx/gamemode/cl_gmchanger.lua"):find('"VoteScreen"', 1, true), nil)

report()
