dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- Last Prop Standing, client side: the halo and laser draw hooks and the HUD hint, run
-- from the shipped cl_lps.lua and sh_lps_config.lua with CLIENT set.
local LPS = "gamemodes/prop_hunt/gamemode/plugins/lps/"
SERVER, CLIENT = false, true

-- Engine pieces shim.lua leaves out (kept here: shim.lua is shared with other branches).
function isfunction(v) return type(v) == "function" end
math.Rand = function(low, high) return low + (high - low) * math.random() end
IN_ATTACK, IN_ATTACK2 = 1, 2048
TEXT_ALIGN_CENTER = 1
function FindMetaTable(n) if n == "Player" then return S.PlyMeta end end
function IsFirstTimePredicted() return true end
function Model(m) return m end
function Sound(s) return s end
function Material() return { SetInt = function() end, SetFloat = function() end } end
S.rand = 0
function ColorRand() S.rand = S.rand + 1; return Color(S.rand % 256, 0, 0) end
function LocalPlayer() return S.localPlayer end
function ScrW() return 1920 end
function ScrH() return 1080 end
S.halos, S.beams, S.texts = {}, {}, {}
-- Only a call that halos something counts: halo.Add with an empty list draws nothing.
halo = { Add = function(list, col) if #list > 0 then S.halos[#S.halos + 1] = { n = #list, col = col } end end }
render = { SetMaterial = function() end,
           DrawBeam = function(_, _, _, _, _, col) S.beams[#S.beams + 1] = col end }
draw = { WordBox = function() end, SimpleText = function(t) S.texts[#S.texts + 1] = t end }
surface = { PlaySound = function() end }
util.TraceLine = function()
  return { Hit = true, HitPos = Vector(100, 0, 0), StartPos = Vector(0, 0, 0), HitNormal = Vector(0, 0, 1),
           Normal = Vector(1, 0, 0), Entity = { IsValid = function() return false end } }
end
GAMEMODE.ViewCam.CamColEnabled = function(_, _, _, t) return t or {} end
GAMEMODE.ViewCam.CommonCamCollEnabledView = function() return {} end

local PM = S.PlyMeta
function PM:SetNWString(k, v) self._nw[k] = v end
function PM:GetNWString(k, d) local v = self._nw[k]; if v == nil then return d end return v end
function PM:GetHull() return Vector(-16, -16, 0), Vector(16, 16, 72) end

-- Count the LPS hex-colour warnings; let everything else (the check() lines) through.
local realPrint = print
S.warnings = 0
print = function(first, ...)
  if tostring(first):find("^%[LPS WARNING%]") then S.warnings = S.warnings + 1 return end
  realPrint(first, ...)
end

-- See t_plugins_lps.lua: GLua `continue` -> LuaJIT goto, placed by the extractor's block walker.
local function withContinue(src, path, loopSpec)
  local loop = extract(path, loopSpec)
  local s, e = src:find(loop, 1, true)
  assert(s, "loop not found verbatim in " .. path .. " :: " .. loopSpec)
  local body, n = loop:gsub("%f[%w_]continue%f[^%w_]", "goto continue")
  if n == 0 then return src end
  body = body:gsub("end%s*$", "::continue:: end")
  return src:sub(1, s - 1) .. body .. src:sub(e + 1)
end

loadblocks("sh_convar.lua@cvars",
  extract("gamemodes/prop_hunt/gamemode/sh_convar.lua", "1-10") .. "\n"
  .. extract("gamemodes/prop_hunt/gamemode/sh_convar.lua", [[^local ConVarTranslate = \{]]) .. "\nlocal CVAR = {}\n"
  .. extractAll("gamemodes/prop_hunt/gamemode/sh_convar.lua", {
       [[^function PHX:AddCVar]], [[^function PHX:GetCVar]], [[^function PHX:QCVar]] }))
function PHX:Includes() end
function PHX:AddCLCVar() end
function PHX:GetCLCVar() return true end
PHX:AddCVar(CTYPE_NUMBER, "ph_rounds_per_map", "10", CVAR_SERVER_ONLY, "")

loadblocks("sh_utils.lua@IsHexColor", extract("gamemodes/prop_hunt/gamemode/sh_utils.lua", [[^function util\.IsHexColor]]))
loadblocks("sh_lps.lua", extract(LPS .. "sh_lps.lua", "1-99999"))
loadblocks("sh_lps_player.lua", extract(LPS .. "sh_lps_player.lua", "1-99999"))
do
  local path = LPS .. "sh_lps_config.lua"
  local src = extract(path, "1-99999")
  src = withContinue(src, path, [[for _,v in pairs\(player\.GetAll\(\)\) do]])
  src = withContinue(src, path, [[for _,v in pairs\(team\.GetPlayers\(TEAM_PROPS\)\) do]])
  loadblocks("sh_lps_config.lua", src)
end
loadblocks("cl_lps.lua", extract(LPS .. "cl_lps.lua", "1-99999"))

local function set(name, v) RunConsoleCommand(name, tostring(v)) end
local function fakeWepEnt()
  return { __valid = true, GetAttachment = function() return { Pos = Vector(0, 0, 50) } end }
end
local function lpsProp(opts)
  opts = opts or {}
  local p = S.Player{ team = TEAM_PROPS }
  p._nw["bLps.LastStanding"] = true
  p._nw["bLps.WeaponName"] = opts.weapon or "smg"
  p._nw["bLps.WeaponState"] = opts.state or LPS_WEAPON_READY
  p._nw["bLps.FiringState"] = opts.firing == true
  p._nw["bLps.WeaponEnt"] = fakeWepEnt()
  if opts.blocked then p.LPSCheckEntityCanShoot = function() return false end end
  return p
end
local function frames(ev, n) for _ = 1, n do S.fire(ev) end end

print("\n== #188 halo colour: parsed on change, not every frame ==")
set("lps_halo_show", 1)
set("lps_halo_color", "green")
S.players = { lpsProp() }
S.warnings, S.halos = 0, {}
frames("PreDrawHalos", 100)
check("invalid lps_halo_color warns once, not every frame", S.warnings, 1)
check("halo is still drawn every frame (normal play)", #S.halos, 100)
S.players[1]._nw["bLps.LastStanding"] = false
S.warnings, S.halos = 0, {}
set("lps_halo_color", "blue")
frames("PreDrawHalos", 100)
check("no last prop -> no colour parsing, no warning", S.warnings, 0)
check("no last prop -> no halo", #S.halos, 0)
S.players = { lpsProp() }
set("lps_halo_color", "#FF0000"); S.halos = {}
frames("PreDrawHalos", 1)
check("valid hex colour is used (normal play)", S.halos[1].col.r == 255 and S.halos[1].col.g == 0, true)
set("lps_halo_color", "#00FF00")
frames("PreDrawHalos", 1)
check("changing the cvar mid-round takes effect (normal play)", S.halos[2].col.g == 255 and S.halos[2].col.r == 0, true)
set("lps_halo_color", "rainbow"); S.rand = 0
frames("PreDrawHalos", 5)
check("rainbow still changes every frame (normal play)", S.rand, 5)
S.players = { lpsProp{ state = LPS_WEAPON_HOLSTER } }; S.halos = {}
frames("PreDrawHalos", 3)
check("holstered last prop -> no halo (normal play)", #S.halos, 0)

print("\n== #188 laser colour: parsed on change, not every frame ==")
SetGlobalBool("LPS.InLastPropStanding", true); SetGlobalBool("InRound", true)
S.players = { lpsProp{ weapon = "laser", firing = true } }
set("lps_laser_color", "nothex"); S.warnings, S.beams = 0, {}
frames("PreDrawEffects", 50)
check("invalid lps_laser_color warns once, not every frame", S.warnings, 1)
check("laser beam is still drawn every frame (normal play)", #S.beams, 50)
set("lps_laser_color", "#00FF00")
frames("PreDrawEffects", 1)
check("changing the laser colour takes effect (normal play)", S.beams[51].g == 255 and S.beams[51].r == 0, true)

print("\n== #253 one blocked laser does not hide the others ==")
S.beams = {}
S.players = { lpsProp{ weapon = "laser", firing = true, blocked = true }, lpsProp{ weapon = "laser", firing = true } }
frames("PreDrawEffects", 1)
check("first prop blocked -> second prop's beam still drawn", #S.beams, 1)
S.beams = {}
S.players = { lpsProp{ weapon = "laser", firing = true, blocked = true } }
frames("PreDrawEffects", 1)
check("single blocked prop -> no beam (normal play)", #S.beams, 0)
S.beams = {}
S.players = { lpsProp{ weapon = "laser", firing = false } }
frames("PreDrawEffects", 1)
check("not firing -> no beam (normal play)", #S.beams, 0)

print("\n== #53 the right-click-to-holster hint follows lps_allow_holster ==")
local function hint(allow, holstered)
  set("lps_allow_holster", allow and 1 or 0)
  S.localPlayer = lpsProp{ state = holstered and LPS_WEAPON_HOLSTER or LPS_WEAPON_READY }
  S.texts = {}
  S.fire("HUDPaint")
  return S.texts[1]
end
check("holstering allowed -> hint shown (normal play)", hint(true), "LPS_HOLSTER_HELPER_TEXT")
check("holstering disallowed -> hint hidden", hint(false), nil)
check("disallowed but still holstered -> hint shown to unholster", hint(false, true), "LPS_HOLSTER_HELPER_TEXT")

print("\n== the HUD font can draw translated (non-Latin) text ==")
S.fonts = {}
surface.CreateFont = function(name, data) S.fonts[name] = data end
language, killicon = { Add = function() end }, { Add = function() end }
loadblocks("sh_load.lua@CLIENT", extract(LPS .. "sh_load.lua", [[^if CLIENT then]]))
local font = S.fonts["PHX.LPS.IndicatorFont"] or {}
check("PHX.LPS.IndicatorFont is created (normal play)", font.font, "Roboto")
check("PHX.LPS.IndicatorFont is extended", font.extended, true)

report()
