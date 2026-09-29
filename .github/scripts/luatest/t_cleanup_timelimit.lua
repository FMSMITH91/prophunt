dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- ph_game_time is copied into GM.GameLength once per realm, at file load: by
-- the server when the map loads and by each client when it joins. Once an
-- admin changes it mid-map, a later joiner's copy is not the limit the server
-- enforces, so the server publishes that limit and GetTimeLimit on clients
-- reads it. Runs the shipped sh_init.lua line, GetTimeLimit, the Initialize
-- hook and prop_hunt's F1 footer.

local BASE, PH = "gamemodes/base_phx/gamemode/", "gamemodes/prop_hunt/gamemode/"
local lengthSrc = extract(PH .. "sh_init.lua", [[^GM\.GameLength]])
local limitSrc = extractAll(BASE .. "shared.lua", { [[^function GM:GetTimeLimit]], [[^function GM:GetGameTimeLeft]] })
local publishSrc = extract(BASE .. "init.lua", [[^hook\.Add\( "Initialize", "PHX\.PublishTimeLimit"]])
local footerSrc = extract(PH .. "cl_init.lua", [[^\s*Help\.lblFooterText\.Think = function]])

-- Keep the footer's arguments, so the time left it shows can be read.
function PHX:FTranslate(id, ...) return table.concat({ id, ... }, " ") end
CreateConVar("ph_game_time", "30")

-- One realm's gamemode table, built with ph_game_time at `minutes` right now.
local function loadRealm(isClient, minutes)
  SERVER, CLIENT = not isClient, isClient
  S.cvars["ph_game_time"].v = tostring(minutes)
  GM = { RoundBased = true }
  GAMEMODE = GM
  loadblocks("sh_init.lua@GameLength", lengthSrc)
  loadblocks("shared.lua@TimeLimit", limitSrc)
  return GM
end

-- The server loads the map: its gamemode files, then the Initialize hooks.
-- hook.Call skips GM:Initialize when a hook returns a value, so keep that too.
local hookReturned
local function serverLoads(minutes)
  S.globals, S.hooks = {}, {}
  local srv = loadRealm(false, minutes)
  loadblocks("init.lua@PublishTimeLimit", publishSrc)
  hookReturned = S.fire("Initialize")
  return srv
end

local function serverLimit(srv)
  SERVER, CLIENT, GAMEMODE = true, false, srv
  return srv:GetTimeLimit()
end

-- A player joins while ph_game_time is `minutes`. What does their F1 footer say
-- `now` seconds into the map?
local function joinerFooter(minutes, now)
  loadRealm(true, minutes)
  local label = { texts = {} }
  function label:SetText(t) self.texts[#self.texts + 1] = t end
  PHCLIENT_Help = { lblFooterText = label }
  loadblocks("cl_init.lua@FooterThink", footerSrc, "local Help = PHCLIENT_Help")
  local saved = _G.CURTIME
  _G.CURTIME = now
  label:Think()
  _G.CURTIME = saved
  return label.texts[1] or "none"
end

print("\n== the server publishes the limit it loaded with ==")
local srv = serverLoads(30)
check("30 min map: publishes 1800 s", GetGlobalInt("PHX.TimeLimit"), 1800)
check("the hook returns nothing, so GM:Initialize still runs", hookReturned, nil)
S.globals["PHX.TimeLimit"] = -1
check("server enforces its own copy, not the global", serverLimit(srv), 1800)
serverLoads(0)
check("no-limit map: publishes -1, not 0", GetGlobalInt("PHX.TimeLimit"), -1)

print("\n== a player joins after ph_game_time changed mid-map ==")
srv = serverLoads(0)
check("map loaded with no limit: server enforces none", serverLimit(srv), -1)
check("set to 30 later: joiner's footer at 40 min is blank", joinerFooter(30, 2400), "none")
check("set to 30 later: joiner's limit is none", GAMEMODE:GetTimeLimit(), -1)
serverLoads(30)
check("map loaded with 30, set to 0 later: time left at 10 min", joinerFooter(0, 600), "MISC_TIMELEFT 20:00")
check("map loaded with 30, set to 0 later: last round at 40 min", joinerFooter(0, 2400), "MISC_GAMEEND")
check("map loaded with 30, set to 60 later: 20 min left, not 50", joinerFooter(60, 600), "MISC_TIMELEFT 20:00")

print("\n== normal play: no change mid-map ==")
serverLoads(30)
check("30 min: time left at 10 min", joinerFooter(30, 600), "MISC_TIMELEFT 20:00")
check("30 min: last round at 40 min", joinerFooter(30, 2400), "MISC_GAMEEND")
serverLoads(0)
check("no limit: footer blank 2 h in", joinerFooter(0, 7200), "none")

print("\n== before the published limit reaches the client ==")
S.globals = {}
check("30 min own copy: last round at 40 min", joinerFooter(30, 2400), "MISC_GAMEEND")
check("no-limit own copy: footer blank", joinerFooter(0, 2400), "none")

report()
