dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- !unstuck, run as shipped: the last-resort teleport has to find the team's own
-- spawns (many ph_ maps have no info_player_start) and must never drop a prop at
-- the world origin; ph_disabletpunstuckinround covers the mid-air PLAYERCLIP
-- branch too; and the cooldown timer survives the player leaving.

loadblocks("sv_enhancedplus.lua@Unstuck",
  extractAll("gamemodes/prop_hunt/gamemode/enhancedplus/sv_enhancedplus.lua", {
    [[^PHX\.UNSTUCK_COMMANDS = \{]],
    [[^hook\.Add\("PlayerSay", "PH_UnstuckCommand"]],
    [[^function GM:TeleportPlayerToClosestSpawnpoint]], [[^function GM:PosOnGround]],
    [[^function GM:UnstuckPlayer]], [[^function GM:TryNormalUnstuck]] }))

S.boolCVar("ph_use_unstuck", "1"); CreateConVar("ph_unstuck_waittime", "5")
CreateConVar("ph_unstuckrange", "250"); S.boolCVar("ph_disabletpunstuckinround", "0")
SetGlobalBool("InRound", true)

-- team.GetSpawnPoints as the engine has it: the classes set in sh_init, cached.
S.spawns = {}
function team.GetSpawnPoints(id) return S.spawns[id] end
local function spawnAt(x, y, z) local p = Vector(x, y, z); return { __valid = true, GetPos = function() return p end } end

local function mkProp(opts)
  opts = opts or {}
  local p = S.Player{ team = TEAM_PROPS, onground = (opts.onground ~= false) }
  p.ph_prop = { __valid = true, GetPropSize = function() return 16, 16, 32 end }
  p._pos = opts.pos or Vector(500, 500, 64)
  S.players = { p }
  return p
end
local function lastMsg(p) local m = p.chat[#p.chat]; return m and m[2] end
local function hasMsg(p, key) for _, m in ipairs(p.chat) do if m[2] == key then return true end end return false end
local function reset() S.timers = {}; S.traceHits = false; S.spawns = {}; S.entsByClass = {} end

print("\n== last-resort teleport: which spawnpoints ==")
reset()
S.spawns[TEAM_PROPS] = { spawnAt(100, 0, 0) }                -- T spawn only, no info_player_start
local p = mkProp()
local ok = GAMEMODE:TeleportPlayerToClosestSpawnpoint(p)
check("T/CT-only map: prop goes to its team spawn", tostring(p:GetPos()), tostring(Vector(100, 0, 100)))
check("T/CT-only map: reported as moved", ok, true)

reset()
S.entsByClass["info_player_start"] = { spawnAt(-300, 0, 0) }   -- the old path must keep working
p = mkProp()
GAMEMODE:TeleportPlayerToClosestSpawnpoint(p)
check("info_player_start only: still used", tostring(p:GetPos()), tostring(Vector(-300, 0, 100)))

reset()
S.spawns[TEAM_PROPS] = { spawnAt(480, 500, 64) }
S.entsByClass["info_player_start"] = { spawnAt(-3000, 0, 0) }
p = mkProp()
GAMEMODE:TeleportPlayerToClosestSpawnpoint(p)
check("both kinds: the closest one wins", tostring(p:GetPos()), tostring(Vector(480, 500, 164)))
check("team spawn list is not modified (engine caches it)", #S.spawns[TEAM_PROPS], 1)

reset()
S.spawns[TEAM_PROPS] = { S.NULL, spawnAt(100, 0, 0) }          -- a removed spawn entity
p = mkProp()
check("a NULL spawn in the cached list: no error", attempt(GAMEMODE.TeleportPlayerToClosestSpawnpoint, GAMEMODE, p), "ok")

print("\n== no spawnpoint at all: stay put, never the world origin ==")
reset()
p = mkProp({ pos = Vector(500, 500, 64) })
p:SetVar("unstuckRecently", true)
ok = GAMEMODE:TeleportPlayerToClosestSpawnpoint(p)
check("no spawns: position unchanged", tostring(p:GetPos()), tostring(Vector(500, 500, 64)))
check("no spawns: reports failure", ok, false)
check("no spawns: tells the player none was found", lastMsg(p), "UNSTUCK_NO_SPAWNPOINTS")
check("no spawns: can retry right away", p:GetVar("unstuckRecently"), false)

-- through the real callers: every probe hits, so TryNormalUnstuck falls to the teleport
reset(); S.traceHits = true
p = mkProp({ pos = Vector(500, 500, 64) })
S.fire("PlayerSay", p, "!unstuck")
check("grounded & wedged, no spawns: not moved to (0,0,20)", tostring(p:GetPos()), tostring(Vector(500, 500, 64)))
check("grounded & wedged, no spawns: told why", hasMsg(p, "UNSTUCK_NO_SPAWNPOINTS"), true)

reset(); S.traceHits = true
S.spawns[TEAM_PROPS] = { spawnAt(100, 0, 0) }
p = mkProp({ pos = Vector(500, 500, 64) })
S.fire("PlayerSay", p, "!unstuck")
check("grounded & wedged, team spawn: teleported there", tostring(p:GetPos()), tostring(Vector(100, 0, 20)))

print("\n== mid-air PLAYERCLIP branch obeys ph_disabletpunstuckinround ==")
local function clipCase(disable, blind, spawns)
  reset()
  S.cvars["ph_disabletpunstuckinround"].v = disable
  SetGlobalBool("PHX.BlindStatus", blind)
  if spawns ~= false then S.spawns[TEAM_PROPS] = { spawnAt(100, 0, 0) } end
  local pl = mkProp({ onground = false, pos = Vector(500, 500, 300) })
  function pl:TraceLineFromPlayer() return { HitPos = self._pos, Contents = CONTENTS_PLAYERCLIP, HitSky = false } end
  S.fire("PlayerSay", pl, "!unstuck")
  local errs = S.pump(0.3)
  return pl, errs[1]
end
local pl, err = clipCase("1", false)
check("disabled, seek phase: no error", err, nil)
check("disabled, seek phase: NOT teleported", tostring(pl:GetPos()), tostring(Vector(500, 500, 300)))
check("disabled, seek phase: warned", lastMsg(pl), "UNSTUCK_SPAWNPOINTS_DISABLED")
pl = clipCase("1", true)
check("disabled, blind phase: teleported", tostring(pl:GetPos()), tostring(Vector(100, 0, 120)))
pl = clipCase("0", false)
check("allowed (default), seek phase: teleported", tostring(pl:GetPos()), tostring(Vector(100, 0, 120)))
pl = clipCase("0", false, false)
check("allowed, no spawns: left where it was", tostring(pl:GetPos()), tostring(Vector(500, 500, 300)))
SetGlobalBool("PHX.BlindStatus", false); S.cvars["ph_disabletpunstuckinround"].v = "0"

print("\n== cooldown timer after the player leaves ==")
reset()
p = mkProp()
S.fire("PlayerSay", p, "!unstuck")
check("cooldown set", p:GetVar("unstuckRecently"), true)
S.fire("PlayerSay", p, "!unstuck")
check("second try inside the cooldown: told to wait", lastMsg(p), "UNSTUCK_PLEASE_WAIT")
local errs = S.pump(6)
check("cooldown expires normally", p:GetVar("unstuckRecently"), false)
check("  ... without errors", #errs, 0)

reset()
p = mkProp()
S.fire("PlayerSay", p, "!unstuck")
-- disconnect: the entity is gone, so touching its table raises as GMod does
p.__valid = false
function p:SetVar() error("Tried to use a NULL entity!") end
errs = S.pump(6)
check("disconnect inside the cooldown: timer raises nothing", errs[1], nil)

report()
