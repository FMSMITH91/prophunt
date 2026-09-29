dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- Client HUD: runs the shipped cl_autotaunt.lua, cl_hud.lua and cl_chat.lua
-- against the real cl_lang.lua + english.lua, recording every draw call.

CLIENT, SERVER = true, false
TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, TEXT_ALIGN_BOTTOM = 0, 1, 2, 3, 4
KEY_F = 16

local W, H = 1920, 1080
function ScrW() return W end
function ScrH() return H end

local draws = {}
local function rec(kind) return function(...) draws[#draws + 1] = { kind = kind, ... } end end
local function noop() end
surface = { SetDrawColor = noop, SetMaterial = noop, SetFont = noop, SetTexture = noop,
            DrawTexturedRect = rec("texrect"), DrawRect = rec("rect"), DrawPoly = rec("poly"),
            PlaySound = noop, GetTextureID = function() return 0 end }
draw = { RoundedBox = rec("rbox"), DrawText = rec("text"), NoTexture = noop, Circle = rec("circle"),
         WordBox = rec("wordbox"), SimpleText = rec("text") }
cam = { Start3D = noop, End3D = noop }
render = { SetMaterial = noop, DrawSprite = noop }
function Material(name) return { name = name, IsError = function() return false end } end
math.pow = math.pow or function(a, b) return a ^ b end

-- input.GetKeyName returns nil outside 1..0x411, so a cleared bind (0) has no name.
local keyNames = { [2] = "1", [KEY_F] = "f", [57] = "n" }
input = { GetKeyName = function(k)
  if type(k) ~= "number" or k < 1 or k > 0x411 then return nil end
  return keyNames[k] or ("key" .. k)
end }

local ME
function LocalPlayer() return ME end
function PHX:GetCLCVar(n) return PHX:GetCVar(n) end

local function texts()
  local r = {}
  for _, d in ipairs(draws) do if d.kind == "text" then r[#r + 1] = tostring(d[1]) end end
  return r
end
local function hasText(want)
  for _, t in ipairs(texts()) do if t == want then return true end end
  return false
end
local function anyText(pat)
  for _, t in ipairs(texts()) do if t:find(pat) then return t end end
  return "none"
end

-- Language files are plain Lua data, so load their shipped bytes as they are
-- (extract.py would also warn about the word "continue" inside a string).
local repo = (debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "../../../"
local function loadLang(rel)
  local f = assert(io.open(repo .. rel, "r"))
  local src = f:read("*a")
  f:close()
  loadchunk(src, rel)()
end

-- The real translation layer, so format strings behave as they do in game.
S.boolCVar("ph_use_lang", "0"); CreateConVar("ph_force_lang", "en_us"); CreateConVar("ph_cl_language", "en_us")
loadblocks("cl_lang.lua", extract("gamemodes/prop_hunt/gamemode/cl_lang.lua", "1-999999"))
loadLang("gamemodes/prop_hunt/gamemode/langs/english.lua")

print("\n== [#1/#7] prop taunt HUD: spawn handshake must run Setup() ==")
local autotauntSrc = extract("gamemodes/prop_hunt/gamemode/cl_autotaunt.lua", "1-999999")
S.boolCVar("ph_autotaunt_enabled", "0"); CreateConVar("ph_autotaunt_delay", "45")
S.boolCVar("ph_hud_use_new", "1"); CreateConVar("ph_normal_taunt_delay", "2")
CreateConVar("ph_customtaunts_delay", "4"); CreateConVar("ph_randtaunt_map_prop_max", "6")
CreateConVar("ph_cl_decoy_spawn_key", "2")

-- Fresh file locals for every scenario, as a map load would give.
local function spawn(opts)
  opts = opts or {}
  S.timers, draws = {}, {}
  S.cvars["ph_autotaunt_enabled"].v = opts.auto and "1" or "0"
  S.cvars["ph_autotaunt_delay"].v = "45"
  S.cvars["ph_hud_use_new"].v = (opts.oldhud and "0") or "1"
  loadblocks("cl_autotaunt.lua", autotauntSrc)
  ME = S.Player{ team = opts.team or TEAM_PROPS, alive = opts.alive ~= false,
                 vars = { LastTauntTime = _G.CURTIME - (opts.ago or 10), CLastTauntTime = 0 } }
  local ok = attempt(S.receivers["AutoTauntSpawn"])
  if opts.delay then S.cvars["ph_autotaunt_delay"].v = tostring(opts.delay) end
  if opts.autoLater then S.cvars["ph_autotaunt_enabled"].v = "1" end
  return ok
end
local function paint()
  draws = {}
  return attempt(S.hooks["HUDPaint"]["PH_AutoTauntPaint"])
end
local function panelDrawn()
  for _, d in ipairs(draws) do if d.kind == "texrect" and d[3] == 480 then return true end end
  return false
end

check("prop, auto-taunt off: receiver ok", spawn(), "ok")
check("prop, auto-taunt off: paint ok", paint(), "ok")
check("prop, auto-taunt off: prop panel drawn", panelDrawn(), true)
check("prop, auto-taunt off: says it is disabled", hasText("Auto Taunting is disabled."), true)
check("prop, auto-taunt off: no client auto-taunt timer", timer.Exists("ph_autotaunt_timer"), false)

spawn{ auto = true }
check("prop, auto-taunt on: client timer created", timer.Exists("ph_autotaunt_timer"), true)
check("prop, auto-taunt on: paint ok", paint(), "ok")
check("prop, auto-taunt on: panel drawn", panelDrawn(), true)
check("prop, auto-taunt on: countdown from 45s", anyText("^Auto Taunting in"), "Auto Taunting in 35 second(s)")

-- Team not set yet when the message lands: the retry timer must finish Setup().
S.timers, draws = {}, {}
loadblocks("cl_autotaunt.lua", autotauntSrc)
ME = S.Player{ team = TEAM_SPECTATOR, vars = { LastTauntTime = _G.CURTIME - 10 } }
S.receivers["AutoTauntSpawn"]()
check("late team: retry timer created", timer.Exists("ph_autotaunt_teamchecktimer"), true)
ME._team = TEAM_PROPS
S.pump(0.1)
paint()
check("late team: panel drawn after the retry", panelDrawn(), true)

spawn{ team = TEAM_HUNTERS }
check("hunter: paint ok", paint(), "ok")
check("hunter: no prop panel", #draws, 0)
spawn{ team = TEAM_SPECTATOR }
paint()
check("spectator: no prop panel", #draws, 0)
spawn{ alive = false }
paint()
check("dead prop: no prop panel", #draws, 0)

-- The cases above never run Setup(). Here the panel is already up, so only the
-- painter's own Alive/Team gate hides it: with auto-taunt off no CheckAutoTaunt
-- timer runs, and `started` stays true until the round ends.
for _, auto in ipairs{ false, true } do
  local tag = "set up, auto-taunt " .. (auto and "on" or "off") .. ": "
  spawn{ auto = auto }
  paint()
  check(tag .. "prop sees the panel", panelDrawn(), true)
  ME._alive = false
  paint()
  check(tag .. "prop dies, panel hidden", #draws, 0)
  ME._alive, ME._team = true, TEAM_HUNTERS
  paint()
  check(tag .. "moved to hunters, panel hidden", #draws, 0)
  ME._team = TEAM_SPECTATOR
  paint()
  check(tag .. "moved to spectators, panel hidden", #draws, 0)
end
spawn()
S.receivers["AutoTauntRoundEnd"]()
paint()
check("round end: panel hidden for a living prop", #draws, 0)

spawn{ oldhud = true }
paint()
check("old HUD, auto-taunt off: bar hidden", #draws, 0)
spawn{ oldhud = true, auto = true }
check("old HUD, auto-taunt on: paint ok", paint(), "ok")
check("old HUD, auto-taunt on: bar drawn", #draws > 0, true)

print("\n== [#245] countdown follows the live ph_autotaunt_delay ==")
spawn{ auto = true, delay = 90 }
paint()
check("delay changed to 90 after load", anyText("^Auto Taunting in"), "Auto Taunting in 80 second(s)")
spawn{ delay = 90, autoLater = true }
paint()
check("auto-taunt enabled mid-round, delay 90", anyText("^Auto Taunting in"), "Auto Taunting in 80 second(s)")
spawn{ auto = true, delay = 0, ago = 0 }   -- just taunted: 0 s left over a 0 s delay
paint()
local radius
for _, d in ipairs(draws) do if d.kind == "circle" then radius = d[3] end end
check("delay 0: circle radius is a number, not NaN", radius == radius and type(radius), "number")

print("\n== [#246] decoy key text when the bind is cleared ==")
spawn()
ME:SetFakePropEntity(true)
paint()
check("decoy active, key bound (1)", hasText("Press [1]"), true)
S.cvars["ph_cl_decoy_spawn_key"].v = "0"
check("decoy active, key cleared: paint ok", paint(), "ok")
check("decoy active, key cleared: no literal %s", anyText("%%s"), "none")
check("decoy active, key cleared: shows N/A", hasText("Press [N/A]"), true)
S.cvars["ph_cl_decoy_spawn_key"].v = "2"

print("\n== revived prop panel paints in every shipped language ==")
local langDir = "gamemodes/prop_hunt/gamemode/langs/"
local h = io.popen("ls '" .. repo .. langDir .. "'")
local langFiles = {}
for name in h:lines() do if name:match("%.lua$") then langFiles[#langFiles + 1] = name end end
h:close()
check("found the shipped languages", #langFiles, 12)
for _, name in ipairs(langFiles) do loadLang(langDir .. name) end
local failures = {}
for code in pairs(PHX.LANGUAGES) do
  S.cvars["ph_cl_language"].v = code
  for _, auto in ipairs{ false, true } do
    for _, key in ipairs{ "2", "0" } do
      spawn{ auto = auto }
      ME:SetFakePropEntity(true)
      S.cvars["ph_cl_decoy_spawn_key"].v = key
      local r = paint()
      if r ~= "ok" then failures[#failures + 1] = code .. ": " .. r end
      local lit = anyText("%%[sd]")
      if lit ~= "none" then failures[#failures + 1] = code .. ": unformatted " .. lit end
    end
  end
end
S.cvars["ph_cl_language"].v = "en_us"; S.cvars["ph_cl_decoy_spawn_key"].v = "2"
check("12 languages x auto on/off x key bound/cleared", table.concat(failures, "; "), "")

print("\n== [#159] prop panel follows a resolution change ==")
spawn()
W, H = 1280, 720
S.fire("OnScreenSizeChanged", 1920, 1080)
paint()
local bgx
for _, d in ipairs(draws) do if d.kind == "texrect" and d[3] == 480 then bgx = d[1] end end
check("panel background x after 1920->1280", bgx, 800)
W, H = 1920, 1080
S.fire("OnScreenSizeChanged", 1280, 720)

print("\n== DrawLine decoy indicator (cl_init.lua) ==")
util.TraceLine = function() return { Hit = true, HitNormal = { z = 1 } } end
GAMEMODE.ViewCam = { CamColEnabled = function(_, _, _, t) t.start, t.endpos = Vector(0, 0, 0), Vector(0, 0, 0); return t end }
S.boolCVar("ph_cl_decoy_spawn_helper", "1")
loadblocks("cl_init.lua@DrawLine",
  "local cHullz = 64\n" .. extractAll("gamemodes/prop_hunt/gamemode/cl_init.lua", {
    [[^local DecoyColor = \{]], [[^local function DrawLine]] }) .. "\nPHCLIENT_DrawLine = DrawLine")
ME = S.Player{ team = TEAM_PROPS }
draws = {}
PHCLIENT_DrawLine(ME, nil, TEAM_PROPS, 100, 24, 24, "ph_cl_decoy_spawn_helper")
check("indicator, key bound", hasText("Place Decoy [Press 1]"), true)
S.cvars["ph_cl_decoy_spawn_key"].v = "0"
draws = {}
check("indicator, key cleared: ok", attempt(PHCLIENT_DrawLine, ME, nil, TEAM_PROPS, 100, 24, 24, "ph_cl_decoy_spawn_helper"), "ok")
check("indicator, key cleared: shows N/A", hasText("Place Decoy [Press N/A]"), true)
S.cvars["ph_cl_decoy_spawn_key"].v = "2"

print("\n== [#161] hunter ammo bar never draws NaN ==")
CL_GLOBAL_LIGHT_STATE = 0
S.boolCVar("ph_show_team_topbar", "0"); CreateConVar("ph_cl_halos", "1")
gui = { IsGameUIVisible = function() return false end }
language = { GetPhrase = function(s) return s end }
local avaPos = {}
vgui = { Create = function()
  local p = { __valid = true }
  function p:SetPos(x, y) avaPos[#avaPos + 1] = { x, y } end
  function p:SetSize() end
  function p:SetPlayer() end
  function p:SetVisible() end
  function p:Remove() self.__valid = false end
  return p
end }
S.PlyMeta.GetAmmoCount = function(self, t) return self._ammo and self._ammo[t] or 0 end
S.PlyMeta.FlashlightIsOn = function() return false end
S.PlyMeta.GetActiveWeapon = function(self) return self._wep end
local function weapon(clip, maxclip)
  return { __valid = true, Clip1 = function() return clip end, GetMaxClip1 = function() return maxclip end,
           GetPrimaryAmmoType = function() return 1 end, GetSecondaryAmmoType = function() return 2 end,
           GetPrintName = function() return "wep" end }
end
loadblocks("cl_hud.lua", extract("gamemodes/prop_hunt/gamemode/cl_hud.lua", "1-999999"))
S.fire("Think")
local function ammoBar(clip, maxclip, ammo)
  ME = S.Player{ team = TEAM_HUNTERS }
  ME._wep = weapon(clip, maxclip)
  ME._ammo = { [1] = ammo or 0, [2] = 0 }
  draws = {}
  local ok = attempt(S.hooks["HUDPaint"]["PHX.MainHUD"])
  local rects, circle = {}, nil
  for _, d in ipairs(draws) do
    if d.kind == "rect" then rects[#rects + 1] = d[3] end
    if d.kind == "circle" then circle = d[3] end
  end
  return ok, rects[2], circle
end
local ok, w, r = ammoBar(-1, -1, 0)
check("crowbar: paint ok", ok, "ok")
check("crowbar: bar width is 0, not NaN", w, 0)
check("crowbar: circle radius is 0, not NaN", r, 0)
ok, w = ammoBar(9, 18, 36)
check("pistol 9/18: half bar", w, 130)
_, w = ammoBar(18, 18, 36)
check("pistol 18/18: full bar", w, 260)
_, w = ammoBar(0, 18, 36)
check("pistol 0/18: empty bar", w, 0)
_, w = ammoBar(19, 18, 36)
check("19/18 (chambered round): capped at full", w, 260)
_, w = ammoBar(-1, -1, 5)
check("clipless with reserve ammo: 0, not NaN", w, 0)

print("\n== [#159] avatar follows a resolution change ==")
ME = S.Player{ team = TEAM_HUNTERS }
PHX.HUD.ava = nil
avaPos = {}
S.fire("Think")
check("avatar placed on creation", avaPos[1] and avaPos[1][2], 935)
W, H = 1280, 720
S.fire("OnScreenSizeChanged", 1920, 1080)
check("avatar moved after 1080 -> 720", avaPos[#avaPos][2], 575)
W, H = 1920, 1080
S.fire("OnScreenSizeChanged", 1280, 720)

print("\n== [#162] CenterPrint with showInput ==")
net.ReadColor = function() return table.remove(S.net.readq, 1) end
loadblocks("cl_chat.lua", extract("gamemodes/prop_hunt/gamemode/cl_chat.lua", "1-999999"))
PHX.LANGUAGES.en_us.T_PHCLIENT_PRESS = "Press [%s] now"
local function centre(msg, show, key)
  S.net.readq = { msg, color_white, show, key }
  local okr = attempt(S.receivers["PHX.CenterPrint"])
  draws = {}
  S.hooks["HUDPaint"]["PHX.DrawCenteredText"]()
  return okr, draws[1] and draws[1][1], draws[1] and draws[1][3]
end
local okc, txt, x = centre("HUD_ROTLOCK", false, 0)
check("plain key: receiver ok", okc, "ok")
check("plain key: translated", txt, "Prop Rotation: Locked")
check("plain key: centred at ScrW/2", x, 960)
okc, txt = centre("T_PHCLIENT_PRESS", true, KEY_F)
check("key with %s + input: translated then formatted", txt, "Press [F] now")
okc, txt = centre("Hold [%s]", true, KEY_F)
check("raw format text + input: unchanged", txt, "Hold [F]")
okc, txt = centre("T_PHCLIENT_PRESS", true, 0)
check("input 0 (PrintCenter default): no error", okc, "ok")
check("input 0: placeholder key", txt, "Press [?] now")
W, H = 1280, 720
S.fire("OnScreenSizeChanged", 1920, 1080)
_, _, x = centre("HUD_ROTLOCK", false, 0)
check("centre print follows a resolution change", x, 640)

report()
