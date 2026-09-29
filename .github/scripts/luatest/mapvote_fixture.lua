-- Shared setup for the map vote server tests (t_mapvote_lifecycle.lua and
-- t_mapvote_rtv.lua). Not a test itself: run.sh only runs t_*.lua. Load it
-- after runner.lua; it returns the helpers the tests drive the code with.
--
-- boot() runs the three shipped server files whole (sh_mapvote.lua,
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

------------------------------------------------------------------------------
-- The shipped code.
------------------------------------------------------------------------------
local SH  = extract("gamemodes/prop_hunt/gamemode/sh_mapvote.lua", "1-999999")
local SV  = extract("gamemodes/prop_hunt/gamemode/mapvote/sv_mapvote.lua", "1-999999")
local RTV = extract("gamemodes/prop_hunt/gamemode/mapvote/rtv.lua", "1-999999")
loadblocks("init.lua", extractAll("gamemodes/base_phx/gamemode/init.lua",
  { [[^function GM:OnEndOfGame]], [[^function GM:EndOfGame]] }))

-- A fresh map: nothing registered, the map and its files, and any addon that
-- loaded before PH:X.
local function resetServer(o)
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
end

-- The gamemode's own map vote convars.
local function gamemodeCVars(o)
  S.boolCVar("ph_enable_mapvote", o.enable == false and "0" or "1")
  S.boolCVar("ph_use_custom_mapvote", o.custom and "1" or "0")
  S.boolCVar("ph_use_custom_mapvote_cmd", o.customCmd and "1" or "0")
  CreateConVar("ph_custom_mv_func", o.func or "PHX.StartMapVote()")
  CreateConVar("ph_custom_mv_concmd", o.concmd or "mv_start")
end

local function boot(o)
  o = o or {}
  resetServer(o)
  gamemodeCVars(o)

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

return {
  SV = SV, RTV = RTV, timerAt = timerAt,
  boot = boot, run = run, count = count, lastSent = lastSent, offered = offered, has = has,
  players = players, endGame = endGame, vote = vote,
}
