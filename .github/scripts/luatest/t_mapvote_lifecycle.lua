dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- Map vote lifecycle: start, the vote itself, RTV, cancel and the end-of-game
-- hand-off. Runs the three shipped server files whole (sh_mapvote.lua,
-- mapvote/sv_mapvote.lua, mapvote/rtv.lua) plus base_phx's real GM:EndOfGame,
-- driven only through their entry points: hooks, concommands, net receivers
-- and timers.

------------------------------------------------------------------------------
-- GMod behaviour the shared shim does not model. Kept here, not in shim.lua.
------------------------------------------------------------------------------

-- GMod's timer.Create REPLACES a timer of the same name. The shim appends, which
-- would double-fire every named timer these fixes rely on.
function timer.Create(id, d, _, fn)
  timer.Remove(id)
  S.timers[#S.timers + 1] = { id = id, fn = fn, at = _G.CURTIME + d }
end
local function timerAt(id) for _, t in ipairs(S.timers) do if t.id == id then return t.at end end end

hook.GetTable = function() return S.hooks end
player.GetHumans = function()
  local r = {} for _, p in ipairs(S.players) do if not p._bot then r[#r + 1] = p end end return r
end
S.PlyMeta.UserID = function(self) return self._uid end

-- Engine includes/extensions/string.lua, verbatim.
function string.PatternSafe(str)
  return (str:gsub(".", { ["("]="%(", [")"]="%)", ["."]="%.", ["%"]="%%", ["+"]="%+", ["-"]="%-",
    ["*"]="%*", ["?"]="%?", ["["]="%[", ["]"]="%]", ["^"]="%^", ["$"]="%$", ["\0"]="%z" }))
end
function string.Trim(s, char)
  if (char) then char = string.PatternSafe(char) else char = "%s" end
  return string.match(s, "^" .. char .. "*(.-)" .. char .. "*$") or s
end
function string.Explode(separator, str, withpattern)
  if (withpattern == nil) then withpattern = false end
  local ret = {}
  local current_pos = 1
  for i = 1, string.len(str) do
    local start_pos, end_pos = string.find(str, separator, current_pos, not withpattern)
    if (not start_pos) then break end
    ret[i] = string.sub(str, current_pos, start_pos - 1)
    current_pos = end_pos + 1
  end
  ret[#ret + 1] = string.sub(str, current_pos)
  return ret
end

-- DATA folder that survives a simulated map change, with a real round trip.
S.files = {}
local jsonStore, jsonN = {}, 0
file.Exists = function(n) return S.files[n] ~= nil end
file.Read = function(n) return S.files[n] end
file.Write = function(n, s) S.files[n] = s end
file.Find = function() return S.mapfiles, {} end
util.TableToJSON = function(t) jsonN = jsonN + 1; local k = "json#" .. jsonN; jsonStore[k] = table.Copy(t); return k end
util.JSONToTable = function(s) return jsonStore[s] and table.Copy(jsonStore[s]) or nil end

game.GetMap = function() return S.map end
game.ConsoleCommand = function(c) S.consolecmds[#S.consolecmds + 1] = c end
local shimRCC = RunConsoleCommand
function RunConsoleCommand(n, ...)
  if n == "changelevel" then S.changelevel = ...; return end
  return shimRCC(n, ...)
end

-- RunString as GMod documents it: handleError false returns the error instead
-- of raising. The cap stands in for the C stack giving out.
function RunString(code, ident, handleError)
  S.runstrings[#S.runstrings + 1] = code
  if #S.runstrings > 200 then error("stack overflow (RunString recursion)") end
  local f, err = loadstring(code, ident)
  if not f then if handleError == false then return err end error(err) end
  local ok, e = pcall(f)
  if not ok then if handleError == false then return e end error(e) end
end

ULib = { cmds = { NumArg = {}, BoolArg = {}, optional = {}, round = {} }, ACCESS_ADMIN = "admin" }
ulx = { fancyLogAdmin = function() end,
        command = function(_, name, fn)
          S.ulx = S.ulx or {}; S.ulx[name] = fn
          local c = {}
          function c.addParam() end function c.defaultAccess() end function c.help() end function c.setOpposite() end
          return c
        end }
IS_PHX = true
gamemode = { Call = function(name, ...) return GAMEMODE[name](GAMEMODE, ...) end }
GAMEMODE.VotingDelay = 5

-- print, captured around a call so log lines can be asserted on.
local function capture(fn, ...)
  local lines, real = {}, print
  print = function(...)
    local t = { ... }
    for i = 1, select("#", ...) do t[i] = tostring(t[i]) end
    lines[#lines + 1] = table.concat(t, " ")
  end
  local ok, err = pcall(fn, ...)
  print = real
  if not ok then error(err, 0) end
  return table.concat(lines, "\n")
end

------------------------------------------------------------------------------
-- The shipped code.
------------------------------------------------------------------------------
local SH  = extract("gamemodes/prop_hunt/gamemode/sh_mapvote.lua", "1-999999")
local SV  = extract("gamemodes/prop_hunt/gamemode/mapvote/sv_mapvote.lua", "1-999999")
local RTV = extract("gamemodes/prop_hunt/gamemode/mapvote/rtv.lua", "1-999999")
loadblocks("init.lua", extractAll("gamemodes/base_phx/gamemode/init.lua",
  { [[^function GM:OnEndOfGame]], [[^function GM:EndOfGame]] }))

-- Stock Lua has no `continue`; the extractor leaves it in place, and a loop that
-- used it would run bodies it should skip. None of these files may rely on it.
local function hasContinue(src) return src:find("%f[%w_]continue%f[^%w_]") ~= nil end
check("sv_mapvote.lua needs no `continue` translation", hasContinue(SV), false)
check("rtv.lua needs no `continue` translation", hasContinue(RTV), false)

local function boot(o)
  o = o or {}
  S.cvars, S.cvarcb, S.boolcvars, S.globals = {}, {}, {}, {}
  S.hooks, S.timers, S.concommands, S.receivers = {}, {}, {}, {}
  S.net.sent, S.errors = {}, 0
  S.runstrings, S.consolecmds, S.changelevel = {}, {}, nil
  S.map = o.map or "ph_a"
  S.mapfiles = o.files or {}
  ulx.votemaps = o.ulxmaps
  GAMEMODE.IsEndOfGame = nil
  for _, h in ipairs(o.preHooks or {}) do hook.Add(h[1], h[2], h[3]) end
  for name, fn in pairs(o.preReceivers or {}) do net.Receive(name, fn) end

  S.boolCVar("ph_enable_mapvote", o.enable == false and "0" or "1")
  S.boolCVar("ph_use_custom_mapvote", o.custom and "1" or "0")
  S.boolCVar("ph_use_custom_mapvote_cmd", o.customCmd and "1" or "0")
  CreateConVar("ph_custom_mv_func", o.func or "PHX.StartMapVote()")
  CreateConVar("ph_custom_mv_concmd", o.concmd or "mv_start")

  PHX.MV = {}
  loadblocks("sh_mapvote.lua", SH)
  for k, v in pairs(o.cvars or {}) do S.cvars[k].v = v end   -- server.cfg, before sv_mapvote reads it
  loadblocks("sv_mapvote.lua", SV)
  loadblocks("rtv.lua", RTV)
  return PHX.MV
end

local function run(sec)
  local errs = S.pump(sec or 0)
  for _, e in ipairs(errs) do print("  timer error: " .. e) end
  return #errs
end

local function count(name)
  local n = 0 for _, m in ipairs(S.net.sent) do if m.name == name then n = n + 1 end end return n
end
local function lastSent(name)
  for i = #S.net.sent, 1, -1 do if S.net.sent[i].name == name then return S.net.sent[i] end end
end
local function offered()
  local m = lastSent("PHX.MV.Start")
  if not m then return {} end
  local t = {} for i = 2, 1 + m.data[1] do t[#t + 1] = m.data[i] end return t
end
local function has(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end

local function players(n, bots)
  S.players = {}
  for i = 1, n do
    S.players[i] = S.Player{ name = "p" .. i, sid = "STEAM_0:0:" .. i }
    S.players[i]._uid = i
  end
  for i = 1, bots or 0 do
    local b = S.Player{ name = "bot" .. i, sid = "BOT", bot = true }
    b._uid = 100 + i
    S.players[#S.players + 1] = b
  end
  -- A copy: leave() removes from S.players, and indices must not shift under the test.
  local copy = {} for i, p in ipairs(S.players) do copy[i] = p end
  return copy
end

-- End the game the way the round controller does and let everything run out.
local function endGame()
  GAMEMODE:EndOfGame(true)
  local e = run(GAMEMODE.VotingDelay)
  local maps = offered()
  e = e + run(PHX.MV.PHXConfig.TimeLimit)
  local pending = PHX.MV.ChangingMap
  e = e + run(4)
  return { offered = maps, changing = pending, changelevel = S.changelevel, timerErrors = e }
end

local function vote(ply, id)
  local recv = S.receivers["PHX.MV.Update"]
  if not recv then return check("PHX.MV.Update has a server receiver", nil, "function") end
  S.net.readq = { PHX.MV.UPDATE_VOTE, id }
  recv(0, ply)
end

------------------------------------------------------------------------------
print("\n== normal play: the vote list and the result are unchanged ==")
------------------------------------------------------------------------------
do
  local pool = { "ph_a.bsp", "ph_b.bsp", "ph_c.bsp", "ph_d.bsp", "ph_e.bsp", "ph_f.bsp",
                 "ph_g.bsp", "phx_h.bsp", "gm_construct.bsp", "cs_office.bsp" }
  local cv = { mv_use_ulx_votemaps = "0" }
  -- A finished vote on ph_b puts ph_b in the cooldown list for the next map.
  S.files = {}
  boot{ map = "ph_b", files = pool, cvars = cv }
  players(2)
  PHX.MV.PHXStart(); run(30); run(4)

  boot{ map = "ph_a", files = pool, cvars = cv }
  local ps = players(4)
  PHX.MV.PHXStart()
  local o = offered()
  local sorted = { unpack(o) }
  table.sort(sorted)
  check("offered: every other prefixed map, nothing else", table.concat(sorted, ","),
    "ph_c,ph_d,ph_e,ph_f,ph_g,phx_h")
  check("vote is open", PHX.MV.Allow, true)
  check("nothing is changing map yet", PHX.MV.ChangingMap, nil)
  vote(ps[1], 3); vote(ps[2], 3); vote(ps[3], 1)
  run(30)
  check("winner recorded for the round controller", PHX.MV.ChangingMap, o[3])
  check("no changelevel before the 4 s grace", S.changelevel, nil)
  run(4)
  check("changelevel goes to the most-voted map", S.changelevel, o[3])
  check("no errors", S.errors, 0)

  boot{ map = "ph_a", files = pool, cvars = { mv_use_ulx_votemaps = "0", mv_maplimit = "5" } }
  players(1)
  PHX.MV.PHXStart()
  check("limit honoured (mv_maplimit 5)", #offered(), 5)
  check("no gm_/cs_ maps", table.concat(offered(), ","):find("gm_") == nil
    and table.concat(offered(), ","):find("cs_") == nil, true)
end

------------------------------------------------------------------------------
print("\n== #4: a small pool never opens an empty vote at the end of the game ==")
------------------------------------------------------------------------------
do
  S.files = {}
  local ulxmaps = { "ph_a", "ph_b", "ph_c" }
  local seq, last = {}, nil
  local map = "ph_a"
  for i = 1, 5 do
    boot{ map = map, ulxmaps = ulxmaps }
    players(3)
    local r = endGame()
    seq[#seq + 1] = r
    map = r.changelevel or map
    last = r
  end
  check("on ph_a: 2 maps offered", #seq[1].offered, 2)
  check("on ph_b: 1 map offered", #seq[2].offered, 1)
  check("on ph_c: cooldown relaxed instead of an empty vote", #seq[3].offered > 0, true)
  check("on ph_c: the current map is still not offered", has(seq[3].offered, "ph_c"), false)
  check("on ph_c: changelevel issued", seq[3].changelevel ~= nil, true)
  check("ChangingMap names the map before changelevel", seq[3].changing, seq[3].changelevel)
  local every = true
  for _, r in ipairs(seq) do if not r.changelevel or r.timerErrors > 0 then every = false end end
  check("five end-of-game votes in a row all change map", every, true)
  check("no errors", S.errors, 0)
end

do
  S.files = {}
  boot{ map = "ph_only", ulxmaps = { "ph_only" } }
  players(2)
  local r = endGame()
  check("pool of 1: the current map is offered", r.offered[1], "ph_only")
  check("pool of 1: the vote reloads it", r.changelevel, "ph_only")
  check("pool of 1: not an error (only config left)", S.errors, 0)
end

do
  S.files = {}
  boot{ map = "ph_a", ulxmaps = { "ph_a", "ph_b" }, cvars = { mv_map_prefix = "zz_" } }
  players(2)
  local r = endGame()
  check("prefix matching nothing: last resort is the current map", r.changelevel, "ph_a")
  check("prefix matching nothing: logged once", S.errors, 1)
  check("prefix matching nothing: players are not left frozen on nothing", r.changing, "ph_a")
end

do
  -- Mixed-case file on a case-sensitive filesystem keeps its real name.
  S.files = {}
  boot{ map = "ph_Office", ulxmaps = { "ph_Office" } }
  players(1)
  local r = endGame()
  check("last resort keeps the map's real case", r.changelevel, "ph_Office")
end

------------------------------------------------------------------------------
print("\n== #14/#48: ph_enable_mapvote 0 ==")
------------------------------------------------------------------------------
do
  S.files = {}
  boot{ enable = false, ulxmaps = { "ph_a", "ph_b", "ph_c" } }
  players(2)
  local r = endGame()
  check("no hook at all: the built-in vote runs anyway", #r.offered > 0, true)
  check("no hook at all: the map changes", r.changelevel ~= nil, true)

  local calls = 0
  boot{ enable = false, ulxmaps = { "ph_a", "ph_b" },
        preHooks = { { "PH_OverrideMapVote", "addon", function() calls = calls + 1; return true end } } }
  players(2)
  PHX.StartMapVote()
  check("hook returns true: addon called once", calls, 1)
  check("hook returns true: no built-in vote", count("PHX.MV.Start"), 0)

  calls = 0
  boot{ enable = false, ulxmaps = { "ph_a", "ph_b" },
        preHooks = { { "PH_OverrideMapVote", "addon", function() calls = calls + 1 end } } }
  players(2)
  PHX.StartMapVote()
  check("hook forgets `return true`: it still ran", calls, 1)
  check("hook forgets `return true`: no second, built-in vote", count("PHX.MV.Start"), 0)

  boot{ enable = false, ulxmaps = { "ph_a", "ph_b" } }
  local admin = players(1)[1]; admin._staff = true
  S.concommands["mv_start"].fn(admin, "mv_start", {})
  check("mv_start still refuses while the vote is off", count("PHX.MV.Start"), 0)
end

------------------------------------------------------------------------------
print("\n== #49: custom map vote settings that point back at PH:X ==")
------------------------------------------------------------------------------
do
  boot{ custom = true, ulxmaps = { "ph_a", "ph_b" } }
  players(2)
  check("default ph_custom_mv_func: no recursion", attempt(PHX.StartMapVote), "ok")
  check("default ph_custom_mv_func: built-in vote instead", count("PHX.MV.Start"), 1)
  check("default ph_custom_mv_func: not RunString'd", #S.runstrings, 0)

  boot{ customCmd = true, ulxmaps = { "ph_a", "ph_b" } }
  players(2)
  check("default ph_custom_mv_concmd: no error", attempt(PHX.StartMapVote), "ok")
  check("default ph_custom_mv_concmd: mv_start not run as NULL", #S.consolecmds, 0)
  check("default ph_custom_mv_concmd: built-in vote instead", count("PHX.MV.Start"), 1)

  boot{ custom = true, func = "  ", ulxmaps = { "ph_a", "ph_b" } }
  players(2)
  PHX.StartMapVote()
  check("blank ph_custom_mv_func: built-in vote", count("PHX.MV.Start"), 1)

  S.addonCalls = 0
  boot{ custom = true, func = "S.addonCalls = S.addonCalls + 1", ulxmaps = { "ph_a", "ph_b" } }
  players(2)
  PHX.StartMapVote()
  check("real addon function: called once", S.addonCalls, 1)
  check("real addon function: no built-in vote", count("PHX.MV.Start"), 0)

  boot{ customCmd = true, concmd = "addon_mapvote 15", ulxmaps = { "ph_a", "ph_b" } }
  players(2)
  PHX.StartMapVote()
  check("real addon command: run", S.consolecmds[1], "addon_mapvote 15\n")
  check("real addon command: no built-in vote", count("PHX.MV.Start"), 0)

  boot{ custom = true, func = "error('addon missing')", ulxmaps = { "ph_a", "ph_b" } }
  players(2)
  check("failing addon function: no raise", attempt(PHX.StartMapVote), "ok")
  check("failing addon function: built-in vote instead", count("PHX.MV.Start"), 1)
  check("failing addon function: logged", S.errors, 1)

  -- An addon that is not ready the first time must still be tried the next.
  S.addonCalls, S.ready = 0, false
  boot{ custom = true, func = "if not S.ready then error('not loaded yet') end S.addonCalls = S.addonCalls + 1",
        ulxmaps = { "ph_a", "ph_b" } }
  local admin2 = players(2)[1]; admin2._staff = true
  PHX.StartMapVote()
  PHX.MV.PHXCancel()
  S.ready = true
  PHX.StartMapVote()
  check("addon that failed once is called the next time", S.addonCalls, 1)

  boot{ custom = true, func = "local x = 1 PHX.StartMapVote()", ulxmaps = { "ph_a", "ph_b" } }
  players(2)
  check("other self-reference: no recursion", attempt(PHX.StartMapVote), "ok")
  check("other self-reference: exactly one vote", count("PHX.MV.Start"), 1)
  -- Without the guard the fallback still ends in one vote, but only after
  -- nesting until the stack gives out.
  check("other self-reference: RunString'd once", #S.runstrings, 1)
  check("other self-reference: nothing logged", S.errors, 0)

  boot{ custom = true, ulxmaps = { "ph_a", "ph_b" } }
  local admin = players(1)[1]; admin._staff = true
  check("ulx map_vote with defaults: no recursion", attempt(S.ulx["ulx map_vote"], admin, 25, false), "ok")
  check("ulx map_vote with defaults: built-in vote", count("PHX.MV.Start"), 1)

  boot{ customCmd = true, ulxmaps = { "ph_a", "ph_b" } }
  admin = players(1)[1]; admin._staff = true
  check("ulx map_vote, command mode on its default: no error", attempt(S.ulx["ulx map_vote"], admin, 25, false), "ok")
  check("  ...mv_start not run as NULL", #S.consolecmds, 0)
  check("  ...built-in vote", count("PHX.MV.Start"), 1)

  boot{ customCmd = true, concmd = "addon_mapvote 15", ulxmaps = { "ph_a", "ph_b" } }
  admin = players(1)[1]; admin._staff = true
  S.ulx["ulx map_vote"](admin, 25, false)
  check("ulx map_vote, real addon command: run", S.consolecmds[1], "addon_mapvote 15\n")
  check("  ...no built-in vote", count("PHX.MV.Start"), 0)

  -- Custom mode on its defaults runs PH:X's own vote, so mv_stop (and the
  -- vote screen's Cancel button, which runs it) must be able to stop it.
  for _, mode in ipairs{ "custom", "customCmd" } do
    boot{ [mode] = true, ulxmaps = { "ph_a", "ph_b" } }
    admin = players(2)[1]; admin._staff = true
    PHX.StartMapVote()
    S.concommands["mv_stop"].fn(admin, "mv_stop", {})
    check(mode .. " on its default: mv_stop stops the built-in vote", PHX.MV.Allow, false)
    check("  ...and tells clients", count("PHX.MV.Cancel"), 1)
  end

  boot{ customCmd = true, concmd = "addon_mapvote 15", ulxmaps = { "ph_a", "ph_b" } }
  admin = players(1)[1]; admin._staff = true
  PHX.StartMapVote()
  S.concommands["mv_stop"].fn(admin, "mv_stop", {})
  check("real addon command: mv_stop still says it is not PH:X's vote",
    (admin.chat[#admin.chat] or {})[1], "Couldn't stop PH:X MapVote because Custom External MapVote is currently enabled!")
  check("  ...and cancels nothing", count("PHX.MV.Cancel"), 0)

  -- The server console is NULL; so is game.ConsoleCommand's caller.
  boot{ custom = true }
  check("mv_start from the dedicated console", attempt(S.concommands["mv_start"].fn, NULL, "mv_start", {}), "ok")
  check("mv_stop from the dedicated console", attempt(S.concommands["mv_stop"].fn, NULL, "mv_stop", {}), "ok")
  local ded = game.IsDedicated
  game.IsDedicated = function() return false end
  check("mv_start from a listen server's NULL", attempt(S.concommands["mv_start"].fn, NULL, "mv_start", {}), "ok")
  check("mv_stop from a listen server's NULL", attempt(S.concommands["mv_stop"].fn, NULL, "mv_stop", {}), "ok")
  game.IsDedicated = ded
  local pl = players(1)[1]
  S.concommands["mv_start"].fn(pl, "mv_start", {})
  check("a non-staff player is still told no", pl.chat[1] and pl.chat[1][2], "MISC_ACCESSDENIED")
end

------------------------------------------------------------------------------
print("\n== #95/#181: mv_map_prefix is parsed and matched literally ==")
------------------------------------------------------------------------------
do
  local pool = { "phx_warehouse.bsp", "ph_office.bsp", "cs_office.bsp", "de_dust2.bsp",
                 "gm_construct.bsp", "ph_a-b.bsp", "ph_aXb.bsp", "PH_Upper.bsp" }
  local function offer(prefix, viaCallback)
    S.files = {}
    if viaCallback then
      boot{ map = "ph_none", files = pool, cvars = { mv_use_ulx_votemaps = "0" } }
      RunConsoleCommand("mv_map_prefix", prefix)
    else
      boot{ map = "ph_none", files = pool, cvars = { mv_use_ulx_votemaps = "0", mv_map_prefix = prefix } }
    end
    players(1)
    local ok = attempt(PHX.MV.PHXStart)
    local o = offered()
    table.sort(o)
    return table.concat(o, ","), ok
  end
  check("default phx_,ph_", offer("phx_,ph_"), "PH_Upper,ph_a-b,ph_aXb,ph_office,phx_warehouse")
  check("the menu example, single-quoted", offer("'phx_,ph_,cs_,de_'"),
    "PH_Upper,cs_office,de_dust2,ph_a-b,ph_aXb,ph_office,phx_warehouse")
  check("a single quoted prefix", offer("'ph_'"), "PH_Upper,ph_a-b,ph_aXb,ph_office")
  check("double quotes and spaces", offer("\"phx_\" , ph_ "), "PH_Upper,ph_a-b,ph_aXb,ph_office,phx_warehouse")
  check("trailing comma adds nothing", offer("cs_,"), "cs_office")
  check("empty value -> defaults, not every map", offer(""), "PH_Upper,ph_a-b,ph_aXb,ph_office,phx_warehouse")
  local list, ok = offer("ph_a-")
  check("pattern characters match literally", list, "ph_a-b")
  check("  ...and do not raise", ok, "ok")
  list, ok = offer("ph_[")
  check("unbalanced [ does not raise in the vote", ok, "ok")
  check("changed at runtime through the cvar callback", offer("'cs_, de_'", true), "cs_office,de_dust2")
  check("callback: empty -> defaults", offer("", true), "PH_Upper,ph_a-b,ph_aXb,ph_office,phx_warehouse")
end

------------------------------------------------------------------------------
print("\n== #51: every vote is recorded; only the broadcast is throttled ==")
------------------------------------------------------------------------------
do
  S.files = {}
  boot{ map = "ph_a", ulxmaps = { "ph_a", "ph_b", "ph_c", "ph_d" } }
  local p1, p2 = unpack(players(2))
  PHX.MV.PHXStart()
  local base = count("PHX.MV.Update")
  vote(p1, 1)
  check("first vote recorded", PHX.MV.Votes[p1:SteamID()], 1)
  check("first vote broadcast at once", count("PHX.MV.Update") - base, 1)
  run(0.1); vote(p1, 2)
  check("change of mind inside the cooldown is recorded", PHX.MV.Votes[p1:SteamID()], 2)
  check("  ...but not broadcast yet", count("PHX.MV.Update") - base, 1)
  run(0.1); vote(p1, 3)
  for _ = 1, 50 do vote(p1, 3) end
  check("latest pick recorded", PHX.MV.Votes[p1:SteamID()], 3)
  check("a burst still sends nothing extra", count("PHX.MV.Update") - base, 1)
  run(0.25)
  check("one trailing broadcast at the cooldown", count("PHX.MV.Update") - base, 2)
  check("  ...carrying the latest pick", (lastSent("PHX.MV.Update") or { data = {} }).data[3], 3)
  run(2)
  check("and nothing after it", count("PHX.MV.Update") - base, 2)
  vote(p1, 99)
  check("unknown map id ignored", PHX.MV.Votes[p1:SteamID()], 3)
  vote(p2, 2)
  check("another player is not held back by p1's cooldown", count("PHX.MV.Update") - base, 3)
  run(0.5); vote(p2, 3)
  run(30)
  check("the tally uses the recorded votes", PHX.MV.ChangingMap, offered()[3])
  run(4)
  vote(p1, 1)
  check("votes after the vote closed are ignored", PHX.MV.Votes[p1:SteamID()], 3)

  -- A trailing broadcast for a player who left, or a vote that ended, is dropped.
  boot{ map = "ph_a", ulxmaps = { "ph_a", "ph_b", "ph_c" } }
  local q = players(1)[1]
  PHX.MV.PHXStart()
  vote(q, 1); run(0.1); vote(q, 2)
  q.__valid = false
  local before = count("PHX.MV.Update")
  check("trailing broadcast for a leaver does not error", run(0.5), 0)
  check("  ...and is not sent", count("PHX.MV.Update"), before)
end

------------------------------------------------------------------------------
print("\n== #81: PH:X's own net, hook and timer names ==")
------------------------------------------------------------------------------
do
  local addonUpdate = function() end
  local addonSay = function() return "" end
  boot{ map = "ph_a", ulxmaps = { "ph_a", "ph_b" },
        preReceivers = { RAM_MapVoteUpdate = addonUpdate, RAM_MapVoteStart = addonUpdate },
        preHooks = { { "PlayerSay", "RTV Chat Commands", addonSay },
                     { "PlayerDisconnected", "Remove RTV", addonSay } } }
  check("the upstream addon's vote receiver is left alone", S.receivers["RAM_MapVoteUpdate"], addonUpdate)
  check("PH:X receives on its own name", type(S.receivers["PHX.MV.Update"]), "function")
  check("PH:X's RTV chat hook", type(S.hooks.PlayerSay["PHX.RTV.Chat"]), "function")
  check("PH:X's RTV disconnect hook", type(S.hooks.PlayerDisconnected["PHX.RTV.Remove"]), "function")
  check("one RTV tally: the addon's chat hook is retired", S.hooks.PlayerSay["RTV Chat Commands"], nil)
  check("one RTV tally: the addon's disconnect hook is retired", S.hooks.PlayerDisconnected["Remove RTV"], nil)
  players(2)
  PHX.MV.PHXStart()
  check("PH:X's vote timer", timerAt("PHX.MV.Vote") ~= nil, true)
  check("not the addon's timer name", timerAt("RAM_MapVote"), nil)

  -- Both ends agree, and nothing still uses the old names.
  local dir = "gamemodes/prop_hunt/gamemode/"
  local files = { "sh_mapvote.lua", "mapvote/sv_mapvote.lua", "mapvote/rtv.lua",
                  "mapvote/cl_mapvote.lua", "mapvote/cl_mapvote_ui.lua" }
  local upstream = { RAM_MapVoteStart = true, RAM_MapVoteUpdate = true, RAM_MapVoteCancel = true,
                    RAM_MapVote = true, RTV_Delay = true, ["Remove RTV"] = true, ["RTV Chat Commands"] = true }
  local registered, used, old = {}, {}, {}
  local function scan(f, src, rx, into)
    for n in src:gmatch(rx) do
      if into then into[n] = f end
      if upstream[n] then old[#old + 1] = f .. ":" .. n end
    end
  end
  for _, f in ipairs(files) do
    local src = extract(dir .. f, "1-999999"):gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
    scan(f, src, 'util%.AddNetworkString%(%s*"([^"]+)"', registered)
    scan(f, src, 'net%.Start%(%s*"([^"]+)"', used)
    scan(f, src, 'net%.Receive%(%s*"([^"]+)"', used)
    scan(f, src, 'timer%.Create%(%s*"([^"]+)"')
    scan(f, src, 'timer%.Remove%(%s*"([^"]+)"')
    scan(f, src, 'hook%.Add%(%s*"[^"]+"%s*,%s*"([^"]+)"')
  end
  local missing = {}
  for n, f in pairs(used) do if not registered[n] then missing[#missing + 1] = f .. ":" .. n end end
  check("every net name used is registered", table.concat(missing, " "), "")
  check("no upstream names left in code", table.concat(old, " "), "")
  check("the three PH:X messages are registered", registered["PHX.MV.Start"] and registered["PHX.MV.Update"]
    and registered["PHX.MV.Cancel"] and true, true)
end

------------------------------------------------------------------------------
print("\n== #3/#180: RTV starts one vote, and a cancel sticks ==")
------------------------------------------------------------------------------
local function say(p, text) return S.fire("PlayerSay", p, text) end
local function leave(p)
  S.fire("PlayerDisconnected", p)
  for i, x in ipairs(S.players) do if x == p then table.remove(S.players, i) break end end
  p.__valid = false
  return capture(run, 0.1)
end
local function lastMsg(p) return p.chat[#p.chat] and p.chat[#p.chat][2] end
local function rtvBoot(n, bots, enable)
  S.files = {}
  boot{ map = "ph_a", ulxmaps = { "ph_a", "ph_b", "ph_c", "ph_d" }, enable = enable }
  local ps = players(n, bots)
  _G.CURTIME = _G.CURTIME + 61      -- past RTV.Wait
  return ps
end

do
  local ps = rtvBoot(6)
  for i = 1, 3 do say(ps[i], "rtv") end
  check("3 of 6: not yet", count("PHX.MV.Start"), 0)
  say(ps[4], "!rtv")
  check("4 of 6: vote rocked", lastMsg(ps[6]), "PHXM_MV_VOTEROCKED_IMMINENT")
  run(1)
  say(ps[5], "rtv")
  check("5th rtv inside the countdown is told a vote is on", lastMsg(ps[5]), "PHXM_MV_VOTEINPROG")
  run(3)
  check("exactly one vote after the countdown", count("PHX.MV.Start"), 1)
  run(2)
  check("the late rtv did not queue a second", count("PHX.MV.Start"), 1)
  vote(ps[1], 1); vote(ps[2], 2)
  local deadline = timerAt("PHX.MV.Vote")
  run(8)
  local log = leave(ps[6])
  check("a non-voter leaving does not restart it", count("PHX.MV.Start"), 1)
  check("votes cast so far survive", table.Count(PHX.MV.Votes), 2)
  check("deadline unchanged", timerAt("PHX.MV.Vote"), deadline)
  check("no bogus 'Server emptied' log", log:find("Server emptied", 1, true) == nil, true)
  leave(ps[1]); leave(ps[2])
  check("RTV voters leaving do not restart it", count("PHX.MV.Start"), 1)
  say(ps[3], "rtv")
  check("rtv during the vote: vote in progress", lastMsg(ps[3]), "PHXM_MV_VOTEINPROG")
  run(30)
  say(ps[3], "rtv")
  check("rtv once the result is in: map is changing", lastMsg(ps[3]), "PHXM_MV_ALR_IN_VOTE")
  log = leave(ps[3]) .. leave(ps[4]) .. leave(ps[5])
  check("server emptying during changelevel's grace: no new vote", log:find("Server emptied", 1, true) == nil, true)
  run(4)
  check("  ...only the one vote, then the changelevel", count("PHX.MV.Start") == 1 and S.changelevel ~= nil, true)
end

do
  -- RTV.Start itself refuses while a start is pending or a vote runs, whoever calls it.
  rtvBoot(6)
  PHX.MV.RTV.Start(); PHX.MV.RTV.Start()
  run(4)
  check("RTV.Start twice in the countdown: one vote", count("PHX.MV.Start"), 1)
  PHX.MV.RTV.Start()
  run(4)
  check("RTV.Start during a vote: no restart", count("PHX.MV.Start"), 1)
end

do
  local ps = rtvBoot(6)
  local admin = ps[6]; admin._staff = true
  for i = 1, 4 do say(ps[i], "rtv") end
  run(4)
  check("cancel: vote was running", PHX.MV.Allow, true)
  S.concommands["mv_stop"].fn(admin, "mv_stop", {})
  check("cancel: vote closed", PHX.MV.Allow, false)
  check("cancel: clients told", count("PHX.MV.Cancel"), 1)
  check("cancel: nothing is changing map", PHX.MV.ChangingMap, nil)
  run(10)
  leave(ps[5])
  check("cancelled vote stays cancelled after a disconnect", count("PHX.MV.Start"), 1)
  run(60)
  check("cancelled vote never changes map", S.changelevel, nil)
  say(ps[1], "rtv")
  check("the tally restarted from zero", count("PHX.MV.Start") == 1 and PHX.MV.Allow == false, true)
end

do
  local ps = rtvBoot(6)
  local admin = ps[6]; admin._staff = true
  for i = 1, 4 do say(ps[i], "rtv") end
  run(1)
  S.concommands["mv_stop"].fn(admin, "mv_stop", {})
  run(4)
  check("cancel during the countdown prevents the vote", count("PHX.MV.Start"), 0)
  leave(ps[5])
  run(4)
  check("  ...and a later disconnect does not revive it", count("PHX.MV.Start"), 0)
end

do
  -- Must still work: a leaver lowering the threshold before any vote.
  local ps = rtvBoot(6)
  for i = 1, 3 do say(ps[i], "rtv") end
  local log = leave(ps[6])
  check("leaver brings 3 of 5 over the line", lastMsg(ps[1]), "PHXM_MV_VOTEROCKED_IMMINENT")
  check("  ...without claiming the server emptied", log:find("Server emptied", 1, true) == nil, true)
  run(4)
  check("  ...one vote", count("PHX.MV.Start"), 1)
end

do
  -- An admin vote during the RTV countdown replaces it rather than being restarted by it.
  local ps = rtvBoot(6)
  local admin = ps[6]; admin._staff = true
  for i = 1, 4 do say(ps[i], "rtv") end
  run(1)
  S.concommands["mv_start"].fn(admin, "mv_start", {})
  run(3)
  check("admin vote inside the countdown: still one vote", count("PHX.MV.Start"), 1)
end

do
  -- #180: bots never type rtv.
  local ps = rtvBoot(4, 6)
  for i = 1, 3 do say(ps[i], "rtv") end
  check("4 humans + 6 bots: 3 RTVs pass", lastMsg(ps[1]), "PHXM_MV_VOTEROCKED_IMMINENT")
  local tally
  for _, c in ipairs(ps[1].chat) do if c[2] == "PHXM_MV_VOTEROCKED_PLY_TOTAL" then tally = c[5] end end
  check("the shown threshold counts humans", tally, 3)
  run(4)
  check("  ...and the vote starts", count("PHX.MV.Start"), 1)

  ps = rtvBoot(1, 1)
  say(ps[1], "rtv")
  check("1 human + 1 bot is not the 2 players mv_rtvcount wants", lastMsg(ps[1]), "PHXM_MV_NEED_MORE_PLY")

  ps = rtvBoot(2, 3)
  local log = leave(ps[1])
  log = log .. leave(ps[2])
  check("last human leaving with bots left: map change starts", lastMsg(ps[3]), "PHXM_MV_VOTEROCKED_IMMINENT")
  check("  ...and says so", log:find("Server emptied", 1, true) ~= nil, true)
end

------------------------------------------------------------------------------
print("\n== #14/#48: ph_enable_mapvote 0 forces a vote only at the end of the game ==")
------------------------------------------------------------------------------
do
  -- Mid-game the setting still means no vote, as before.
  local ps = rtvBoot(6, 0, false)
  for i = 1, 4 do say(ps[i], "rtv") end
  run(4)
  check("vote off, mid-game rtv: no vote", count("PHX.MV.Start"), 0)
  run(60); run(4)   -- vote timer, then the changelevel it schedules
  check("  ...and no map change", S.changelevel, nil)
  say(ps[5], "rtv")
  check("  ...and rtv is not stuck on a vote in progress", lastMsg(ps[5]), "PHXM_MV_VOTEROCKED_PLY_TOTAL")

  ps = rtvBoot(2, 0, false)
  leave(ps[1]); leave(ps[2])
  run(4)
  check("vote off, server emptied: no vote", count("PHX.MV.Start"), 0)
  run(60); run(4)   -- vote timer, then the changelevel it schedules
  check("  ...and no map change", S.changelevel, nil)

  -- The end-of-game fallback is a built-in vote like any other: staff can stop it.
  S.files = {}
  boot{ enable = false, ulxmaps = { "ph_a", "ph_b", "ph_c" } }
  local admin = players(2)[1]; admin._staff = true
  GAMEMODE:EndOfGame(true); run(GAMEMODE.VotingDelay)
  check("vote off, end of game: the fallback vote runs", PHX.MV.Allow, true)
  S.concommands["mv_stop"].fn(admin, "mv_stop", {})
  check("  ...mv_stop cancels it", PHX.MV.Allow, false)
  check("  ...and tells clients", count("PHX.MV.Cancel"), 1)
  run(60); run(4)   -- vote timer, then the changelevel it schedules
  check("  ...so it never changes map", S.changelevel, nil)
end

------------------------------------------------------------------------------
print("\n== ChangingMap contract with the round controller ==")
------------------------------------------------------------------------------
do
  S.files = {}
  boot{ map = "ph_a", ulxmaps = { "ph_a", "ph_b", "ph_c" } }
  local admin = players(2)[1]; admin._staff = true
  PHX.MV.PHXStart(); run(30)
  check("set once the result is in", PHX.MV.ChangingMap ~= nil, true)
  S.concommands["mv_start"].fn(admin, "mv_start", {})
  check("cleared when a new vote starts", PHX.MV.ChangingMap, nil)
  run(4)
  check("the replaced result's changelevel does not fire mid-vote", S.changelevel, nil)
  check("  ...and the new vote is still open", PHX.MV.Allow, true)
  run(30); run(4)
  check("the new vote changes map when it ends", S.changelevel ~= nil, true)

  boot{ map = "ph_a", ulxmaps = { "ph_a", "ph_b", "ph_c" } }
  admin = players(2)[1]; admin._staff = true
  PHX.MV.PHXStart(); run(30)
  S.concommands["mv_start"].fn(admin, "mv_start", {})
  S.concommands["mv_stop"].fn(admin, "mv_stop", {})
  run(10)
  check("replacement vote cancelled in the grace: no changelevel at all", S.changelevel, nil)
end

report()
