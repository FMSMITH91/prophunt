dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- Spectator cycling, run as shipped (the whole sv_spectator.lua): the helpers that
-- replaced the deprecated table.FindNext/FindPrev give the same order and wrap,
-- StartEntitySpectate always finds the one teammate still alive, and with nobody
-- to follow the camera roams instead of chasing nothing.

OBS_MODE_NONE, OBS_MODE_DEATHCAM, OBS_MODE_FREEZECAM = 0, 1, 2
OBS_MODE_FIXED, OBS_MODE_IN_EYE, OBS_MODE_CHASE, OBS_MODE_ROAMING = 3, 4, 5, 6

local PM = S.PlyMeta
function PM:GetObserverTarget() return self._target end
function PM:SpectateEntity(e) if e == NULL then e = nil end self._target = e end
function PM:Spectate(mode) self._obs = mode end
function PM:GetObserverMode() return self._obs or OBS_MODE_NONE end
function PM:IsObserver() return (self._obs or OBS_MODE_NONE) ~= OBS_MODE_NONE end
function PM:GetClass() return "player" end

-- The deprecated engine helpers (includes/extensions/table.lua), so the pre-fix code
-- still runs here and a reverted fix fails by name rather than by crashing.
table["FindNext"] = function(tab, val)
  local bfound = false
  for _, v in pairs(tab) do
    if bfound then return v end
    if val == v then bfound = true end
  end
  local _, first = next(tab)
  return first
end
table["FindPrev"] = function(tab, val)
  local _, last = next(tab, table.Count(tab) - 1)
  for _, v in pairs(tab) do
    if val == v then return last end
    last = v
  end
  return last
end
function table.Merge(dest, source)
  for k, v in pairs(source) do dest[k] = v end
  return dest
end

GAMEMODE.ValidSpectatorModes = { OBS_MODE_CHASE, OBS_MODE_IN_EYE, OBS_MODE_ROAMING }
GAMEMODE.ValidSpectatorEntities = { "player" }
GAMEMODE.CanOnlySpectateOwnTeam = true

loadblocks("sv_spectator.lua", extract("gamemodes/base_phx/gamemode/sv_spectator.lua", "1-999999"))
local spec_mode, spec_next, spec_prev = S.concommands["spec_mode"].fn, S.concommands["spec_next"].fn, S.concommands["spec_prev"].fn

-- A dead prop watching, plus whoever else is on the server.
local function server(props, hunters, specs)
  S.players = {}
  local me = S.Player{ team = TEAM_PROPS, alive = false, name = "me" }
  me._obs = OBS_MODE_CHASE
  S.players[1] = me
  local mates = {}
  for i = 1, props do mates[i] = S.Player{ team = TEAM_PROPS, name = "prop" .. i }; S.players[#S.players + 1] = mates[i] end
  for i = 1, hunters do S.players[#S.players + 1] = S.Player{ team = TEAM_HUNTERS, name = "h" .. i } end
  for i = 1, specs do local s = S.Player{ team = TEAM_SPECTATOR, name = "s" .. i }; s._obs = OBS_MODE_ROAMING; S.players[#S.players + 1] = s end
  S.entsByClass["player"] = S.players
  return me, mates
end
local function name(p) return p and p:Nick() or "none" end

print("\n== spec_mode cycles CHASE -> IN_EYE -> ROAMING -> CHASE ==")
local me = server(1, 0, 0)
local order = {}
for _ = 1, 4 do spec_mode(me); order[#order + 1] = me:GetObserverMode() end
check("mode order (wraps)", table.concat(order, ","), table.concat({ OBS_MODE_IN_EYE, OBS_MODE_ROAMING, OBS_MODE_CHASE, OBS_MODE_IN_EYE }, ","))
me._obs = OBS_MODE_DEATHCAM
spec_mode(me)
check("from deathcam (not in the list): first mode", me:GetObserverMode(), OBS_MODE_CHASE)
me._obs = OBS_MODE_FREEZECAM; me._info.cl_spec_mode = 99
GAMEMODE:BecomeObserver(me)
check("BecomeObserver with a bad cl_spec_mode: first mode", me:GetObserverMode(), OBS_MODE_CHASE)

print("\n== spec_next / spec_prev ==")
local mates
me, mates = server(3, 2, 1)
me._obs = OBS_MODE_CHASE
me._target = mates[1]
local seq = {}
for _ = 1, 4 do spec_next(me); seq[#seq + 1] = name(me:GetObserverTarget()) end
check("next: skips enemies/spectators, wraps", table.concat(seq, ","), "prop2,prop3,prop1,prop2")
me._target = mates[1]; seq = {}
for _ = 1, 4 do spec_prev(me); seq[#seq + 1] = name(me:GetObserverTarget()) end
check("prev: skips enemies/spectators, wraps", table.concat(seq, ","), "prop3,prop2,prop1,prop3")
me._target = nil
spec_next(me)
check("next with no current target: first teammate", name(me:GetObserverTarget()), "prop1")
me._target = nil
spec_prev(me)
check("prev with no current target: last teammate", name(me:GetObserverTarget()), "prop3")

print("\n== picking a target when spectating starts ==")
math.randomseed(12345)
me, mates = server(1, 12, 10)                 -- 24 on the server, one teammate alive
local found = 0
for _ = 1, 300 do
  me._target = nil
  GAMEMODE:ChangeObserverMode(me, OBS_MODE_CHASE)
  if me:GetObserverTarget() == mates[1] and me:GetObserverMode() == OBS_MODE_CHASE then found = found + 1 end
end
check("24 players, 1 teammate: found every time (300 tries)", found, 300)
me._target = mates[1]
GAMEMODE:ChangeObserverMode(me, OBS_MODE_IN_EYE)
check("a valid current target is kept", name(me:GetObserverTarget()), "prop1")

me, mates = server(3, 2, 0)
local seen = {}
for _ = 1, 100 do me._target = nil; GAMEMODE:StartEntitySpectate(me); seen[name(me:GetObserverTarget())] = true end
check("several teammates: only teammates are picked", (seen.h1 or seen.h2 or seen.me) and "enemy/self" or "ok", "ok")
check("several teammates: more than one gets picked", (seen.prop1 and 1 or 0) + (seen.prop2 and 1 or 0) + (seen.prop3 and 1 or 0) > 1, true)

me = server(0, 5, 2)                           -- no teammate left to follow
me._target = nil
GAMEMODE:ChangeObserverMode(me, OBS_MODE_CHASE)
check("nobody to follow: roams", me:GetObserverMode(), OBS_MODE_ROAMING)
check("nobody to follow: no target", me:GetObserverTarget(), nil)
GAMEMODE:ChangeObserverMode(me, OBS_MODE_ROAMING)
check("roaming asked for: roams", me:GetObserverMode(), OBS_MODE_ROAMING)

print("\n== every spectatable class is listed ==")
GAMEMODE.ValidSpectatorEntities = { "player", "npc_test" }
me = server(2, 0, 0)
S.entsByClass["npc_test"] = { { __valid = true, n = "npc1" }, { __valid = true, n = "npc2" } }
check("two classes: all entities of both", #GAMEMODE:GetSpectatorTargets(me), #S.players + 2)
GAMEMODE.ValidSpectatorEntities = { "player" }

report()
