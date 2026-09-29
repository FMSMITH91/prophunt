dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- One death -> blind-time respawn cycle, end to end: the round's elimination
-- check, the respawn, the hunter class (blindfold, lock, loadout, devil ball),
-- the freeze cam, and team spawn picking. Every piece is the shipped code; only
-- the engine (Kill/Spawn firing the hooks) is simulated here.

-- Timers as GMod has them: run in due-time order, with repetitions. The 0.2s
-- round check racing the 0.45s respawn is exactly what is under test, so the
-- shim's "everything due, in insertion order" pump would not do.
local function addTimer(t) S.timers[#S.timers + 1] = t end
function timer.Simple(d, fn) addTimer{ fn = fn, at = CURTIME + d, delay = d, reps = 1 } end
function timer.Create(id, d, reps, fn)
  timer.Remove(id)
  addTimer{ id = id, fn = fn, at = CURTIME + d, delay = d, reps = reps or 1 }
end
local function advance(dt)
  local target = CURTIME + dt
  while true do
    local best
    for i, t in ipairs(S.timers) do
      if t.at <= target and (not best or t.at < S.timers[best].at) then best = i end
    end
    if not best then break end
    local t = table.remove(S.timers, best)
    CURTIME = t.at
    if t.reps ~= 1 then t.at = t.at + t.delay; addTimer(t) end
    t.fn()
  end
  CURTIME = target
end

OBS_MODE_NONE, OBS_MODE_FREEZECAM, OBS_MODE_CHASE = 0, 2, 5
debug.Trace = function() end
function SetGlobalEntity(k, v) S.globals[k] = v end
function team.AddScore() end
function PHX:PlayWinningSound() end
function PHX:TranslateName(id) return team.GetName(id) end
function table.Shuffle(t) for i = #t, 2, -1 do local j = math.random(i); t[i], t[j] = t[j], t[i] end end

-- The engine: Kill() runs DoPlayerDeath (hooks, then the gamemode's) and then
-- PostPlayerDeath; KillSilent() skips DoPlayerDeath; Spawn() runs PlayerSpawn
-- and the class OnSpawn. That is what the respawn logic reacts to.
local n = { silent = 0, spawns = 0, balls = 0, rot0 = 0 }
local PM = S.PlyMeta
function PM:CallClassFunction(name, ...)
  local cls = S.classes[self._team == TEAM_HUNTERS and "Hunter" or "Prop"]
  if cls and cls[name] then return cls[name](cls, self, ...) end
end
local function die(pl, attacker, silent)
  if not pl._alive then return end
  if not silent then
    S.fire("DoPlayerDeath", pl, attacker, {})
    GAMEMODE:DoPlayerDeath(pl, attacker, {})
  end
  pl._alive = false
  S.fire("PostPlayerDeath", pl)
end
function PM:Kill() die(self, self, false) end
function PM:KillSilent() n.silent = n.silent + 1; die(self, nil, true) end
function PM:Spawn()
  n.spawns = n.spawns + 1
  self._alive, self._obs = true, OBS_MODE_NONE
  S.fire("PlayerSpawn", self)
  self:CallClassFunction("OnSpawn")
end
function PM:Spectate(mode) self._obs = mode end
function PM:SpectateEntity() end
function PM:GetObserverMode() return self._obs or OBS_MODE_NONE end
function PM:SendRotState(v) if v == 0 then n.rot0 = n.rot0 + 1 end end
function PM:AddDeaths() self._deaths = (self._deaths or 0) + 1 end
function PM:CreateRagdoll() self._ragdolls = (self._ragdolls or 0) + 1 end
for _, m in ipairs{ "SetRenderMode", "ResetHull", "SetCollisionGroup", "CollisionRulesChanged" } do
  PM[m] = function() end
end
local realCreate = ents.Create
ents.Create = function(c)
  if c == "ph_devilball" and not S.entsCreateFails then n.balls = n.balls + 1 end
  return realCreate(c)
end
S.classes = { Prop = { OnSpawn = function() end,
                       OnDeath = function(_, pl) pl:RemoveProp() end } }

loadblocks("round_controller.lua",
  extractAll("gamemodes/base_phx/gamemode/round_controller.lua", {
    [[^function GM:SetRoundResult]], [[^function GM:ClearRoundResult]],
    [[^function GM:SetInRound]], [[^function GM:InRound]], [[^function GM:OnRoundResult]],
    [[^function GM:ProcessResultText]], [[^function GM:RoundEndWithResult]],
    [[^function GM:RoundEnd\(]], [[^function GM:GetTeamAliveCounts]],
    [[^hook\.Add\( "PostPlayerDeath", "RoundCheck_PostPlayerDeath"]] }))
loadblocks("base_phx init.lua@DoPlayerDeath",
  extract("gamemodes/base_phx/gamemode/init.lua", [[^function GM:DoPlayerDeath]]))
loadblocks("init.lua@BlindRespawn", "local phx_blind_unlocktime = 0\n" ..
  extractAll("gamemodes/prop_hunt/gamemode/init.lua", {
    [[^local function ControlTauntWindow]], [[^local function ClearBlindedHuntersList]],
    [[^local function ClearTimer]], [[^function GM:CheckPlayerDeathRoundEnd]],
    [[^hook\.Add\("DoPlayerDeath", "HunterFreezeCam"]],
    [[^local spawnpointmin]], [[^local spawnpointmax]], [[^local function IsSpawnpointBlocked]],
    [[^function GM:PlayerSelectTeamSpawn]], [[^function GM:IsSpawnpointSuitable]],
    [[^local function AutoRespawnCheck]], [[^local function WillBlindRespawn]],
    [[^hook\.Add\("PostPlayerDeath", "autoPlayerRepsawnDuringDeath"]],
    [[^hook\.Add\("PlayerChangedTeam", "changeteam"]],
    [[^hook\.Add\("PostCleanupMap", "PH_ResetStats"]],
    [[^hook\.Add\("PlayerSpawn", "PH_PlayerSpawn"]],
    [[^local function IsRoundUnderstaffed]], [[^function GM:OnRoundEnd]] }))
loadblocks("sh_player.lua@PHSetColor",
  "local Player = S.PlyMeta\n" ..
  extract("gamemodes/prop_hunt/gamemode/sh_player.lua", [[^function Player:PHSetColor]]))
loadblocks("class_hunter.lua", extract("gamemodes/prop_hunt/gamemode/player_class/class_hunter.lua", "1-999"))

S.boolCVar("ph_allow_respawnonblind", "1")
S.boolCVar("ph_allow_respawn_from_spectator", "1")
S.boolCVar("ph_allow_respawnonblind_teamchange", "0")
CreateConVar("ph_allow_respawnonblind_team_only", "0")
CreateConVar("ph_blindtime_respawn_percent", "0.75")
CreateConVar("ph_hunter_blindlock_time", "30")
CreateConVar("ph_hunter_jumppower", "1"); CreateConVar("ph_prop_jumppower", "1.5")
S.boolCVar("ph_freezecam_hunter", "1")
S.boolCVar("ph_enable_devil_balls", "1")
S.boolCVar("ph_enable_hunter_player_color", "0"); S.boolCVar("ph_use_custom_plmodel", "0")
S.boolCVar("ph_give_grenade_near_roundend", "1"); CreateConVar("ph_smggrenadecounts", "1")
S.boolCVar("ph_waitforplayers", "0"); CreateConVar("ph_min_waitforplayers", "2")
GAMEMODE.RoundBased = true
GAMEMODE.RoundPostLength = 8
GAMEMODE.AddFragsToTeamScore = false
function GAMEMODE:PreRoundStart() end

-- A fresh round the way OnPreRoundStart builds it: clean-up (blind starts),
-- everyone spawned, then InRound.
local H, P
local function startRound(nh, np, dead)
  S.timers, S.globals, S.players, H, P = {}, {}, {}, {}, {}
  n.silent, n.spawns, n.balls, n.rot0 = 0, 0, 0, 0
  for i = 1, nh do H[i] = S.Player{ team = TEAM_HUNTERS, name = "h" .. i, idx = i, info = { cl_playercolor = "1 1 1" } } end
  for i = 1, np do P[i] = S.Player{ team = TEAM_PROPS, name = "p" .. i, idx = 10 + i } end
  for _, p in ipairs(H) do S.players[#S.players + 1] = p end
  for _, p in ipairs(P) do S.players[#S.players + 1] = p end
  SetGlobalInt("RoundNumber", 1)
  SetGlobalFloat("RoundStartTime", CURTIME)
  S.fire("PostCleanupMap")
  for _, p in ipairs(S.players) do
    if dead and dead[p._name] then p._alive = false else p:Spawn() end
  end
  GAMEMODE:SetInRound(true)
end
local function inRound() return GAMEMODE:InRound() end

print("\n== the last prop dies in blind time: respawned, round goes on ==")
startRound(2, 1)
advance(5)
P[1]:Kill()                                     -- a fall, or `kill`
advance(0.3)
check("0.3s: round not ended by the 0.2s check", inRound(), true)
advance(0.3)
check("0.6s: the prop was respawned", P[1]:Alive(), true)
advance(10)
check("10s later: round still running", inRound(), true)

print("\n== the lone hunter kills himself in blind time ==")
startRound(1, 2)
advance(5)
H[1]:Kill()
advance(0.6)
check("hunter respawned", H[1]:Alive(), true)
check("round still running", inRound(), true)
check("hunter blinded again", H[1]:GetBlindState(), true)
check("no devil crystal for a blind-time suicide", n.balls, 0)
advance(1)
check("hunter locked again after 1s", H[1]:IsFrozen(), true)

print("\n== normal deaths still end the round ==")
startRound(2, 1)
advance(40)                                     -- blind is over
P[1]:KillSilent()                               -- a hunter's kill (ph_prop)
advance(0.25)
check("after blind: last prop dies -> round over at 0.2s", inRound(), false)
check("after blind: hunters win", GetGlobalInt("RoundResult"), TEAM_HUNTERS)

startRound(2, 1)
advance(25)                                     -- past the 75% respawn window, still blind
P[1]:Kill()
advance(0.25)
check("late blind: no respawn, round over at 0.2s", inRound(), false)
check("late blind: hunters win", GetGlobalInt("RoundResult"), TEAM_HUNTERS)

S.cvars["ph_allow_respawnonblind_team_only"].v = "1"   -- hunters only
startRound(2, 1)
advance(5)
P[1]:Kill()
advance(0.25)
check("team_only=hunters: last prop's death ends the round at 0.2s", inRound(), false)
S.cvars["ph_allow_respawnonblind_team_only"].v = "0"

startRound(2, 1)
advance(40)
P[1]._alive = false
P[1]._PHXBlindRespawnAt = CURTIME + 0.5         -- a hold whose timer never ran
GAMEMODE:CheckPlayerDeathRoundEnd()
check("a pending respawn holds the check", inRound(), true)
advance(0.6)
GAMEMODE:CheckPlayerDeathRoundEnd()
check("the hold lapses on its own", inRound(), false)

startRound(2, 1)
advance(5)
P[1]:Kill()
advance(0.1)
GAMEMODE:RoundEndWithResult(TEAM_PROPS, "HUD_TEAMWIN")   -- time up / force end meanwhile
advance(1)
check("round ended while a respawn was pending: hold cleared", P[1]._PHXBlindRespawnAt, nil)

print("\n== a death undone by someone else is not re-killed ==")
startRound(2, 2)
advance(5)
P[1]:Kill()
advance(0.2)
P[1]:Spawn()                                    -- admin respawn inside the 0.45s
local spawnsBefore = n.spawns
advance(10)
check("no KillSilent/Spawn loop", n.silent, 0)
check("no extra spawns", n.spawns - spawnsBefore, 0)
check("prop stays alive", P[1]:Alive(), true)

print("\n== hunter loadout and blind lock ==")
startRound(2, 2)
advance(25)                                     -- dies after the respawn window
H[1]:Kill()
advance(6)                                      -- blind ends at 30, late loadout at 30.1
check("dead hunter not marked as armed", H[1].PHXHasLoadout, false)
H[1]:Spawn()                                    -- an admin respawn later on
check("respawned hunter is armed", #H[1].weapons > 0, true)

startRound(1, 2, { h1 = true })
advance(29.05)
H[1]:Spawn()                                    -- lock timer lands just after blind ends
advance(2)
check("blind ends inside the 1s lock timer: one loadout", #H[1].weapons, 5)

-- Any ControlPlayer unblind (the unblind timer, or the lock timer landing after
-- blind ends) must mark him armed, or the late loadout at blind end arms him again.
startRound(1, 2)
advance(5)
S.classes.Hunter:ControlPlayer(H[1], false, H[1].TimerBlindID)
check("ControlPlayer's unblind marks the hunter armed", H[1].PHXHasLoadout, true)
advance(30)                                     -- blind ends, late loadout at 30.1
check("... so blind end does not arm him twice", #H[1].weapons, 5)

S.cvars["ph_allow_respawnonblind_teamchange"].v = "1"
startRound(2, 2)
advance(0.3)
H[2]:Kill()                                     -- PlayerJoinTeam: Kill, then SetTeam
H[2]:SetTeam(TEAM_PROPS)
S.fire("PlayerChangedTeam", H[2], TEAM_HUNTERS, TEAM_PROPS)
advance(3)
check("hunter->prop inside 1s: respawned as a prop", H[2]:Alive() and H[2]:Team(), TEAM_PROPS)
check("... and not left Locked by the hunter's lock timer", H[2]:IsFrozen(), false)
S.cvars["ph_allow_respawnonblind_teamchange"].v = "0"

print("\n== devil crystal drops ==")
startRound(2, 2)
advance(40)
H[1]:Kill()
check("hunter death after blind drops a crystal", n.balls, 1)
check("one ragdoll per hunter death", H[1]._ragdolls, 1)
S.entsCreateFails = true
local res = attempt(function() H[2]:Kill() end)
S.entsCreateFails = false
check("at the entity limit the death still completes", res, "ok")
check("... death counted", H[2]._deaths, 1)

print("\n== freeze cam leaves a respawned hunter alone ==")
startRound(2, 2)
advance(0.2)
die(H[1], P[1], false)                          -- killed by a prop in the unlocked second
advance(0.6)
check("respawned at 0.45s", H[1]:Alive(), true)
check("0.6s: not put into freeze cam", H[1]:GetObserverMode(), OBS_MODE_NONE)
advance(5)
check("5s: not put into chase cam", H[1]:GetObserverMode(), OBS_MODE_NONE)

startRound(2, 2)
advance(40)
die(H[1], P[1], false)
advance(0.6)
check("dead hunter: freeze cam at 0.5s", H[1]:GetObserverMode(), OBS_MODE_FREEZECAM)
advance(4.2)
check("dead hunter: chase cam at 4.5s", H[1]:GetObserverMode(), OBS_MODE_CHASE)

-- Respawned inside the freeze cam by a spawn that skipped PH_PlayerSpawn (another
-- addon's PlayerSpawn hook returned a value, which stops hook.Call), so
-- InFreezeCam is still set when the 4.5s timer runs.
startRound(2, 2)
advance(40)
die(H[1], P[1], false)
advance(0.6)
H[1]._alive, H[1]._obs = true, OBS_MODE_NONE
advance(4.2)
check("alive at 4.5s with InFreezeCam still set: no chase cam", H[1]:GetObserverMode(), OBS_MODE_NONE)

print("\n== spawn picking never kills ==")
local function spawnAt(x) return { __valid = true, GetPos = function() return Vector(x, 0, 0) end } end
local spawns = { spawnAt(0), spawnAt(100), spawnAt(200) }
function team.GetSpawnPoints() return spawns end
function ents.FindInBox(mn, mx)
  local r = {}
  for _, p in ipairs(S.players) do
    local v = p:GetPos()
    if v.x >= mn.x and v.x <= mx.x and v.y >= mn.y and v.y <= mx.y then r[#r + 1] = p end
  end
  return r
end
startRound(3, 3)
for i = 1, 3 do H[i]:SetPos(spawns[i]:GetPos()) end        -- Locked on their spawns
local picked = GAMEMODE:PlayerSelectTeamSpawn(TEAM_HUNTERS, S.Player{ team = TEAM_HUNTERS })
check("hunter spawns all taken by hunters: still picks one", picked ~= nil, true)
for i = 1, 3 do H[i]:SetPos(Vector(500 + i * 100, 0, 0)) end   -- (hunters block props)
P[1]:SetPos(spawns[1]:GetPos()); P[2]:SetPos(spawns[3]:GetPos()); P[3]:SetPos(Vector(999, 0, 0))
local free = 0
for _ = 1, 20 do
  if GAMEMODE:PlayerSelectTeamSpawn(TEAM_PROPS, S.Player{ team = TEAM_PROPS }) == spawns[2] then free = free + 1 end
end
check("a prop gets the one free spawn, every time", free, 20)
P[3]:SetPos(spawns[2]:GetPos())
check("all spawns taken: still picks one", GAMEMODE:PlayerSelectTeamSpawn(TEAM_PROPS, S.Player{ team = TEAM_PROPS }) ~= nil, true)
check("fallback path's last try is always suitable", GAMEMODE:IsSpawnpointSuitable(S.Player{ team = TEAM_PROPS }, spawns[1], true), true)
local alive = 0
for _, p in ipairs(S.players) do if p:Alive() then alive = alive + 1 end end
check("nobody was killed to make room", alive, 6)

print("\n== spawning resets the client's rotation lock ==")
startRound(0, 1)
check("PlayerSpawn sends SendRotState(0)", n.rot0, 1)

report()
