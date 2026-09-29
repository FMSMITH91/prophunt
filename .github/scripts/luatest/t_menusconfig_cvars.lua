dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- sh_convar.lua: the ConVar helpers, ph_fc_cue_path, ph_min_waitforplayers and
-- the first-time language, plus sh_config.lua's SetUsableEntity driven through
-- the real ph_usable_prop_type callback. Everything here runs the shipped code.

local CONVAR = "gamemodes/prop_hunt/gamemode/sh_convar.lua"
local CONFIG = "gamemodes/prop_hunt/gamemode/sh_config.lua"

function isfunction(v) return type(v) == "function" end
string.Replace = function(s, find, rep)
  local pat = find:gsub("%W", "%%%0")
  local with = rep:gsub("%%", "%%%%")
  return (s:gsub(pat, with))
end

-- The engine only runs change callbacks when the value actually changes. The
-- shim fires them on every set, which would loop forever on a callback that
-- rewrites its own ConVar, so emulate the engine here and log every call.
local rcc = {}
local shimRCC = RunConsoleCommand
RunConsoleCommand = function(n, v)
  rcc[#rcc + 1] = { n, v }
  if S.cvars[n] and S.cvars[n].v == v then return end
  shimRCC(n, v)
end

local head = extract(CONVAR, "1-10") .. "\n" .. extract(CONVAR, [[^local ConVarTranslate = \{]])

-- Load CVAR entries through the real ConVarTranslate, as the file's own loop does.
local function loadCVars(specs, realm)
  S.cvars, S.cvarcb, S.globals, rcc = {}, {}, {}, {}
  SERVER, CLIENT = realm ~= "client", realm == "client"
  local body = {}
  for _, spec in ipairs(specs) do body[#body + 1] = extract(CONVAR, spec) end
  loadchunk(head .. "\nlocal CVAR = {}\n" .. table.concat(body, "\n") .. [==[

for name, data in pairs(CVAR) do
  ConVarTranslate[data[1]].Set( name, data[2], data[3], data[4], data[5], data[6] )
end
]==], "sh_convar.lua")()
  SERVER, CLIENT = true, false
end

print("\n== #229: PHX:AddCVar must always create a NUMBER/FLOAT ConVar ==")
local AddCVar = loadchunk(head .. "\nlocal CVAR = {}\n" .. extract(CONVAR, [[^function PHX:AddCVar]])
  .. "\nreturn PHX.AddCVar", "sh_convar.lua@AddCVar")()
S.cvars = {}
local called = {}
local function cb(name) called[name] = true end
AddCVar(PHX, CTYPE_NUMBER, "t_num_fn", "5", CVAR_SERVER_ONLY, "help", cb)
check("NUMBER, callback as 5th arg -> ConVar exists", S.cvars["t_num_fn"] ~= nil, true)
check("  ... and GetInt() works (SyncCVar path)", attempt(function() return GetConVar("t_num_fn"):GetInt() end), "ok")
check("  ... and the callback still runs", called["t_num_fn"], true)
AddCVar(PHX, CTYPE_FLOAT, "t_flt_fn", "1.5", CVAR_SERVER_ONLY, "help", cb)
check("FLOAT, callback as 5th arg -> ConVar exists", S.cvars["t_flt_fn"] ~= nil, true)
check("  ... and the callback still runs", called["t_flt_fn"], true)
-- normal use must not change
AddCVar(PHX, CTYPE_NUMBER, "t_num_mm", "5", CVAR_SERVER_ONLY, "help", { min = 1, max = 9 }, cb)
check("NUMBER with {min,max} keeps its bounds", S.cvars["t_num_mm"].min .. "-" .. S.cvars["t_num_mm"].max, "1-9")
check("  ... and its 6th-arg callback", called["t_num_mm"], true)
AddCVar(PHX, CTYPE_FLOAT, "t_flt_mm", "0.8", CVAR_SERVER_ONLY, "help", { min = 0.6, max = 1.2 })
check("FLOAT with {min,max} keeps its bounds", S.cvars["t_flt_mm"].max, 1.2)
AddCVar(PHX, CTYPE_NUMBER, "t_num_nil", "3", CVAR_SERVER_ONLY, "help")
check("NUMBER with no data -> created, no bounds", S.cvars["t_num_nil"] ~= nil and S.cvars["t_num_nil"].min == nil, true)
AddCVar(PHX, CTYPE_NUMBER, "t_num_empty", "3", CVAR_SERVER_ONLY, "help", {})
check("NUMBER with {} -> created", S.cvars["t_num_empty"] ~= nil, true)
check("global mirrors the value", GetGlobalInt("t_num_fn", -1), 5)

print("\n== #252: ph_min_waitforplayers relies on min = 1 and phx.sync_ alone ==")
loadCVars({ [==[^CVAR\["ph_min_waitforplayers"\]]==] })
local cbs = S.cvarcb["ph_min_waitforplayers"] or {}
check("exactly one change callback", #cbs, 1)
check("  ... and it is the sync", cbs[1] and cbs[1].id, "phx.sync_ph_min_waitforplayers")
check("ConVar min is 1", S.cvars["ph_min_waitforplayers"].min, 1)
check("default is 2", GetGlobalInt("ph_min_waitforplayers", -1), 2)
RunConsoleCommand("ph_min_waitforplayers", "5")
check("a change reaches the global", GetGlobalInt("ph_min_waitforplayers", -1), 5)

print("\n== jump power: a mid-round change gives the jump a spawn gives ==")
local JUMP = { [==[^CVAR\["ph_prop_jumppower"\]]==], [==[^CVAR\["ph_hunter_jumppower"\]]==] }
loadCVars(JUMP)
local function jumper(t) local p = S.Player(t); p.SetJumpPower = function(self, v) self._jp = v end; return p end
local prop, deadProp, hunter = jumper{ team = TEAM_PROPS }, jumper{ team = TEAM_PROPS, alive = false }, jumper{ team = TEAM_HUNTERS }
S.players = { prop, deadProp, hunter }
RunConsoleCommand("ph_prop_jumppower", "2")
check("props x2 -> a living prop jumps 400", prop._jp, 400)
check("  ... a dead prop is left alone", deadProp._jp, nil)
check("  ... and hunters are left alone", hunter._jp, nil)
check("  ... and the global follows", GetGlobalFloat("ph_prop_jumppower", -1), 2)
RunConsoleCommand("ph_prop_jumppower", "1.5")
check("props back to the default 1.5 -> the stock 300", prop._jp, 300)
RunConsoleCommand("ph_hunter_jumppower", "1.5")
check("hunters x1.5 -> 300", hunter._jp, 300)
RunConsoleCommand("ph_hunter_jumppower", "1")
check("hunters back to the default 1 -> the stock 200", hunter._jp, 200)
S.players = {}

-- The help text an admin reads in the console must state the real default.
JUMP[#JUMP + 1] = [==[^CVAR\["ph_min_waitforplayers"\]]==]
local defs = loadchunk(head .. "\nlocal CVAR = {}\n" .. extractAll(CONVAR, JUMP) .. "\nreturn CVAR", "sh_convar.lua@help")()
for _, n in ipairs({ "ph_prop_jumppower", "ph_hunter_jumppower", "ph_min_waitforplayers" }) do
  check(n .. " help names its real default", defs[n][4]:match("Default is ([%d.]+)%."), defs[n][2])
end

print("\n== #76: ph_fc_cue_path only rewrites itself on the server ==")
loadCVars({ [==[^CVAR\["ph_fc_cue_path"\]]==] }, "client")
-- a replicated change arriving on a client runs the same callbacks
S.cvars["ph_fc_cue_path"].v = [[custom\fc.wav]]
SERVER, CLIENT = false, true
local okc = attempt(S.fireCvar, "ph_fc_cue_path", "misc/freeze_cam.wav", [[custom\fc.wav]])
SERVER, CLIENT = true, false
check("client: callback runs cleanly", okc, "ok")
check("client: no RunConsoleCommand on a replicated cvar", #rcc, 0)
check("client: PHX.LegalSoundPath still follows it", PHX.LegalSoundPath, "custom/fc.wav")

loadCVars({ [==[^CVAR\["ph_fc_cue_path"\]]==] }, "server")
RunConsoleCommand("ph_fc_cue_path", [[custom\fc.wav]])
check("server: backslashes rewritten in the ConVar", S.cvars["ph_fc_cue_path"].v, "custom/fc.wav")
check("server: and in the global", GetGlobalString("ph_fc_cue_path", "?"), "custom/fc.wav")
rcc = {}
RunConsoleCommand("ph_fc_cue_path", "custom/other.wav")
check("server: a clean path is set once, not re-issued", #rcc, 1)
check("server: clean path reaches the global", GetGlobalString("ph_fc_cue_path", "?"), "custom/other.wav")
-- the client branch still reads it until it moves to the cvar
loadblocks("sh_convar.lua@LegalSoundPath", extract(CONVAR, [[^PHX\.LegalSoundPath]]))
check("PHX.LegalSoundPath stays defined", type(PHX.LegalSoundPath), "string")

print("\n== #151: ph_usable_prop_type must never leave USABLE_PROP_ENTITIES nil ==")
loadblocks("sh_config.lua@Usable", extractAll(CONFIG, {
  [[^PHX\.CVARUseAbleEnts = \{]], [[^function PHX:IsUsablePropEntity]], [[^function PHX:SetUsableEntity]] }))
PHX.USABLE_PROP_ENTITIES = PHX.CVARUseAbleEnts[1]
loadCVars({ [==[^CVAR\["ph_usable_prop_type"\]]==] })
local function usable(cls) return attempt(function() return PHX:IsUsablePropEntity(cls) end) == "ok" and PHX:IsUsablePropEntity(cls) end
RunConsoleCommand("ph_usable_prop_type", "2.5")
check("2.5 -> a table is still set", type(PHX.USABLE_PROP_ENTITIES), "table")
check("2.5 -> treated as 2 (GetInt), prop_dynamic usable", usable("prop_dynamic"), true)
RunConsoleCommand("ph_usable_prop_type", "1")
check("1 -> prop_physics usable", usable("prop_physics"), true)
check("1 -> prop_dynamic not usable", usable("prop_dynamic"), false)
RunConsoleCommand("ph_usable_prop_type", "3")
check("3 -> prop_ragdoll usable", usable("prop_ragdoll"), true)
local before = PHX.USABLE_PROP_ENTITIES
S.errors = 0
PHX:SetUsableEntity(7)
check("out of range -> reported", S.errors, 1)
check("  ... and the previous list is kept", PHX.USABLE_PROP_ENTITIES == before, true)

print("\n== #156/#218: client ConVars and the first-time language ==")
local clientBlock = extract(CONVAR, [[^if CLIENT then]])
local cookies = {}
cookie = { GetString = function(k, d) local v = cookies[k]; if v == nil then return d end return v end,
           Set = function(k, v) cookies[k] = v end, GetNumber = function(_, d) return d end }
function CreateClientConVar(n, v, _, _, help, mn, mx) return CreateConVar(n, v, 0, help, mn, mx) end
PHX.LANGUAGES = { en_us = {}, de = {} }

-- Fresh client: `lang` is ph_cl_language's archived value (nil = never set),
-- `default` the server's ph_default_lang, `chosen` the cookie.
local function joinClient(lang, default, chosen)
  S.cvars, S.cvarcb, S.hooks, rcc = {}, {}, {}, {}
  cookies = { phx_lang_chosen = chosen }
  S.globals = { ph_default_lang = "de" }   -- a global that already says "de" must not matter
  CreateConVar("ph_default_lang", default)  -- the replicated ConVar
  SERVER, CLIENT = false, true
  loadchunk(head .. "\n" .. clientBlock, "sh_convar.lua@client")()
  SERVER, CLIENT = true, false
  local created = S.cvars["ph_cl_language"] and S.cvars["ph_cl_language"].v
  if lang then S.cvars["ph_cl_language"].v = lang end
  local ok = attempt(S.fire, "InitPostEntity")
  return created, ok, PHX:GetCLCVar("ph_cl_language"), cookies.phx_lang_chosen
end

local created, ok, now, ck = joinClient(nil, "de", nil)
check("ph_cl_language is created as en_us", created, "en_us")
check("first join, server default de -> hook runs", ok, "ok")
check("first join, server default de -> de", now, "de")
check("  ... and it is remembered", ck, "1")
_, _, now = joinClient(nil, "de", "1")
check("already chose (cookie) -> untouched", now, "en_us")
_, _, now, ck = joinClient("fr", "de", nil)
check("picked fr before the cookie existed -> kept", now, "fr")
check("  ... and now remembered", ck, "1")
_, ok, now, ck = joinClient(nil, "xx", nil)
check("unknown server default -> no error", ok, "ok")
check("unknown server default -> stays en_us", now, "en_us")
check("  ... and not remembered, so a valid one can apply later", ck, nil)
_, _, now = joinClient(nil, "en_us", nil)
check("stock default en_us -> en_us (normal play)", now, "en_us")

-- #156: AddCLCVar must always create the ConVar
local called2
PHX:AddCLCVar(CTYPE_NUMBER, "t_cl_empty", "1", true, false, "help", {})
check("AddCLCVar with {} -> readable", attempt(function() return PHX:GetCLCVar("t_cl_empty") end), "ok")
check("  ... value", PHX:GetCLCVar("t_cl_empty"), 1)
PHX:AddCLCVar(CTYPE_BOOL, "t_cl_fn", "1", true, false, "help", function() called2 = true end)
check("AddCLCVar with a callback in cData -> readable", attempt(function() return PHX:GetCLCVar("t_cl_fn") end), "ok")
check("  ... and the callback runs", called2, true)
PHX:AddCLCVar(CTYPE_NUMBER, "t_cl_mm", "5", true, false, "help", { min = 1, max = 9 })
check("AddCLCVar with {min,max} keeps its bounds (normal use)", S.cvars["t_cl_mm"].max, 9)

report()
