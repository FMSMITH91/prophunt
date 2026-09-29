dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- Round cycle: PreRoundStart (map vote hold, time limit, waiting for players)
-- and prop_hunt's ph_waitforplayers pause/resume and round counting.

-- Timers as GMod has them: ordered by due time, with repetitions and pause.
-- The shim's pump runs everything due in insertion order and has no pause,
-- which hides both the 0.2s-vs-0.45s style races and the pause bug.
local function addTimer(t) S.timers[#S.timers + 1] = t end
function timer.Simple(d, fn) addTimer{ fn = fn, at = CURTIME + d, delay = d, reps = 1 } end
function timer.Create(id, d, reps, fn)
  timer.Remove(id)
  addTimer{ id = id, fn = fn, at = CURTIME + d, delay = d, reps = reps or 1 }
end
function timer.Pause(id)
  for _, t in ipairs(S.timers) do
    if t.id == id and not t.left then t.left = t.at - CURTIME; t.at = math.huge end
  end
end
function timer.UnPause(id)
  for _, t in ipairs(S.timers) do
    if t.id == id and t.left then t.at = CURTIME + t.left; t.left = nil end
  end
end
function timer.TimeLeft(id)
  for _, t in ipairs(S.timers) do
    if t.id == id then return t.left and -t.left or (t.at - CURTIME) end
  end
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
    if t.reps ~= 1 then
      t.at = t.at + t.delay
      if t.reps > 1 then t.reps = t.reps - 1 end
      addTimer(t)
    end
    t.fn()
  end
  CURTIME = target
end

-- Engine/API bits the shim does not have.
debug.Trace = function() end
function UTIL_UnFreezeAllPlayers() end
function SetGlobalEntity(k, v) S.globals[k] = v end
local scores = {}
function team.GetScore(id) return scores[id] or 0 end
function team.SetScore(id, v) scores[id] = v end
function team.AddScore(id, v) scores[id] = (scores[id] or 0) + v end
function PHX:PlayWinningSound() end

loadblocks("round_controller.lua",
  extractAll("gamemodes/base_phx/gamemode/round_controller.lua", {
    [[^function GM:SetRoundResult]], [[^function GM:ClearRoundResult]],
    [[^function GM:SetInRound]], [[^function GM:InRound]],
    [[^function GM:OnRoundStart]], [[^function GM:OnRoundResult]],
    [[^function GM:GetRoundLimit]], [[^function GM:HasReachedRoundLimit]],
    [[^function GM:GetRoundTime]], [[^function GM:PreRoundStart]],
    [[^function GM:ProcessResultText]], [[^function GM:RoundEndWithResult]],
    [[^function GM:RoundEnd\(]] }))
loadblocks("shared.lua@GetTimeLimit",
  extract("gamemodes/base_phx/gamemode/shared.lua", [[^function GM:GetTimeLimit]]))
loadblocks("init.lua@RoundControl",
  extractAll("gamemodes/prop_hunt/gamemode/init.lua", {
    [[^local function ControlTauntWindow]], [[^local function ClearBlindedHuntersList]],
    [[^local function ClearTimer]], [[^function GM:CanStartRound]],
    [[^local function IsRoundUnderstaffed]], [[^function GM:OnRoundEnd]],
    [[^function GM:RoundStart]], [[^function GM:CheckRoundEnd]],
    [[^function GM:RoundTimerEnd]], [[^local IS_ROUND_FORCED_END]],
    [[^local function ForceEndRound]], [[^concommand\.Add\("ph_force_end_round"]] }))

CreateConVar("ph_min_waitforplayers", "2")
S.boolCVar("ph_waitforplayers", "0")

local ends, preRounds = 0, 0
function GAMEMODE:EndOfGame() ends = ends + 1; self.IsEndOfGame = true end
local grenades = 0
function GAMEMODE:OnPreRoundStart()
  preRounds = preRounds + 1
  -- the real one creates this; RoundStart must pause it with the round clock
  timer.Create("phx.tmr_GiveGrenade", GAMEMODE.RoundLength - 15, 1, function() grenades = grenades + 1 end)
end
GAMEMODE.RoundPreStartTime = 0
GAMEMODE.RoundPostLength = 8
GAMEMODE.RoundLength = 300
GAMEMODE.RoundLimit = 10
GAMEMODE.GameLength = 30
GAMEMODE.RoundBased = true

local function reset(hunters, props)
  S.timers, S.globals, scores = {}, {}, {}
  S.players = {}
  for i = 1, hunters do S.players[#S.players + 1] = S.Player{ team = TEAM_HUNTERS, name = "h" .. i } end
  for i = 1, props do S.players[#S.players + 1] = S.Player{ team = TEAM_PROPS, name = "p" .. i } end
  ends, preRounds, grenades = 0, 0, 0
  GAMEMODE.IsEndOfGame, GAMEMODE.bWaitingForPlayers, GAMEMODE.bRoundIsWarmup = nil, nil, nil
  PHX.MV = nil
  CURTIME = 1000
end
local function join(t) local p = S.Player{ team = t, name = "late" .. #S.players }; S.players[#S.players + 1] = p; return p end
local function leave(t) for i, p in ipairs(S.players) do if p:Team() == t then table.remove(S.players, i) return end end end
local function pending(id) for _, t in ipairs(S.timers) do if t.id == id then return true end end return false end

print("\n== a map vote holds the round cycle, and a cancelled one resumes it ==")
reset(2, 2)
PHX.MV = { Allow = true }
GAMEMODE:PreRoundStart(2)
check("vote live: no round started", preRounds, 0)
advance(5)
check("vote live 5s later: still no round", preRounds, 0)
PHX.MV.Allow = false                       -- mv_stop / ulx unmap_vote / empty list
advance(1.5)
check("vote cancelled: round starts within ~1s", preRounds, 1)
check("vote cancelled: it is round 2", GetGlobalInt("RoundNumber"), 2)
check("vote cancelled: InRound", GAMEMODE:InRound(), true)

reset(2, 2)
PHX.MV = { Allow = true }
GAMEMODE:PreRoundStart(2)
advance(3)
PHX.MV.ChangingMap, PHX.MV.Allow = "ph_next", false  -- vote won, changelevel pending
advance(10)
check("vote won: no round starts under the result", preRounds, 0)
check("vote won: the poll stops", #S.timers, 0)

reset(2, 2)
GAMEMODE:PreRoundStart(1)
check("no map vote table: round starts", preRounds, 1)
reset(2, 2)
PHX.MV = {}
GAMEMODE:PreRoundStart(1)
check("vote table, no vote running: round starts", preRounds, 1)

print("\n== ph_game_time 0 means no time limit ==")
reset(2, 2)
GAMEMODE.GameLength = 0
GAMEMODE:PreRoundStart(1)
check("game time 0: round 1 starts", preRounds, 1)
check("game time 0: game not ended", ends, 0)
reset(2, 2)
GAMEMODE.GameLength = 0
GAMEMODE:PreRoundStart(11)
check("game time 0, past the round limit: game ends", ends, 1)
reset(2, 2)
GAMEMODE.GameLength = 30
GAMEMODE:PreRoundStart(3)
check("30 min, 1000s in: round starts", preRounds, 1)
reset(2, 2)
GAMEMODE.GameLength = 30
CURTIME = 1801
GAMEMODE:PreRoundStart(3)
check("30 min, 1801s in: game ends", ends, 1)
check("30 min, 1801s in: no round started", preRounds, 0)
-- The shipped help text (help ph_game_time, rcon cvarlist) says what 0 does.
local cvarHelp = loadchunk("local CTYPE_NUMBER, CVAR_SERVER_ONLY = 2, 0\nlocal CVAR = {}\n"
  .. extract("gamemodes/prop_hunt/gamemode/sh_convar.lua", [==[^CVAR\["ph_game_time"\]]==])
  .. "\nreturn CVAR", "sh_convar.lua@ph_game_time")()["ph_game_time"][4]
check("help text: 0 = no time limit", cvarHelp:find("0 = no time limit", 1, true) ~= nil, true)
check("help text: still needs a map restart", cvarHelp:find("(Require Map Restart)", 1, true), 1)

print("\n== waiting for players before a round: its own flag for the HUD ==")
reset(1, 0)
GAMEMODE:PreRoundStart(1)
check("1 player: round held", preRounds, 0)
check("1 player: RoundWaitingToStart set", GetGlobalBool("RoundWaitingToStart", false), true)
check("1 player: RoundWaitForPlayers left alone", GetGlobalBool("RoundWaitForPlayers", false), false)
advance(3)
join(TEAM_PROPS)
advance(1.1)
check("2nd player joins: round starts", preRounds, 1)
check("2nd player joins: RoundWaitingToStart cleared", GetGlobalBool("RoundWaitingToStart", true), false)
reset(1, 0)
GAMEMODE:PreRoundStart(1)
advance(801.1)                                   -- the 30 min limit passes during the wait
check("game ends while waiting: game ended", ends, 1)
check("game ends while waiting: wait flag cleared", GetGlobalBool("RoundWaitingToStart", true), false)

print("\n== ph_waitforplayers: min is a TOTAL, each team needs one ==")
S.boolCVar("ph_waitforplayers", "1")
local function startRound(n)
  GAMEMODE:PreRoundStart(n or 1)
  advance(0.01)                                -- RoundStartTimer (RoundPreStartTime 0)
end

reset(1, 1)                                     -- 1v1 at the default min 2
startRound(1)
check("1v1 min 2: round is timed", GetGlobalFloat("RoundEndTime", -1) > 0, true)
check("1v1 min 2: not flagged as waiting", GetGlobalBool("RoundWaitForPlayers", true), false)
advance(301)
check("1v1 min 2: props win on time", GetGlobalInt("RoundResult"), TEAM_PROPS)
check("1v1 min 2: the round counted", GetGlobalInt("RoundNumber"), 1)
advance(8)
check("1v1 min 2: next round is round 2", GetGlobalInt("RoundNumber"), 2)

reset(2, 0)                                     -- a team is empty: warm-up
startRound(1)
check("2v0: round paused", GetGlobalFloat("RoundEndTime", 0), -1)
check("2v0: flagged as waiting", GetGlobalBool("RoundWaitForPlayers", false), true)
check("2v0: grenade timer paused too", timer.TimeLeft("phx.tmr_GiveGrenade") < 0, true)
advance(400)
check("2v0: still in round after 400s", GAMEMODE:InRound(), true)
check("2v0: no near-round-end grenades in a paused round", grenades, 0)
join(TEAM_PROPS)
advance(1.1)
check("2v0 + a prop: round resumes", GAMEMODE.bRoundIsWarmup, false)
check("2v0 + a prop: clock restarted", GetGlobalFloat("RoundEndTime", -1) > CURTIME, true)
check("2v0 + a prop: waiting flag cleared", GetGlobalBool("RoundWaitForPlayers", true), false)
advance(300)
check("resumed round ends on time", GAMEMODE:InRound(), false)
check("resumed round counted", GetGlobalInt("RoundNumber"), 1)

reset(4, 0)                                     -- min 4 is a total across both teams
RunConsoleCommand("ph_min_waitforplayers", "4")
startRound(1)
check("4v0 min 4: paused", GetGlobalFloat("RoundEndTime", 0), -1)
leave(TEAM_HUNTERS); leave(TEAM_HUNTERS); join(TEAM_PROPS)
advance(2)
check("2v1 min 4: still paused (3 < 4)", GetGlobalFloat("RoundEndTime", 0), -1)
join(TEAM_PROPS)
advance(1.1)
check("2v2 min 4: resumes", GetGlobalFloat("RoundEndTime", -1) > CURTIME, true)
RunConsoleCommand("ph_min_waitforplayers", "2")

reset(2, 0)                                     -- a warm-up that ends still short-handed
startRound(1)
GAMEMODE:RoundEndWithResult(1001, "HUD_LOSE")
check("warm-up ended by force: does not count", GetGlobalInt("RoundNumber"), 0)
check("warm-up ended: waiting flag cleared", GetGlobalBool("RoundWaitForPlayers", true), false)

reset(2, 2)                                     -- a full timed round, someone leaves
startRound(3)
advance(100)
leave(TEAM_PROPS)
advance(201)
check("2v2 then a prop leaves: round still ended on time", GAMEMODE:InRound(), false)
check("2v2 then a prop leaves: round counted", GetGlobalInt("RoundNumber"), 3)

print("\n== ph_force_end_round tells a refused caller why ==")
local printed
local function forceEnd(ply, dedicated)
  local realPrint, realDedicated = print, game.IsDedicated
  printed = nil
  print = function(s) printed = s end
  game.IsDedicated = function() return dedicated ~= false end
  local ok, err = pcall(S.concommands["ph_force_end_round"].fn, ply, "ph_force_end_round", {})
  print, game.IsDedicated = realPrint, realDedicated
  assert(ok, err)
end
local function lastChat(p) local m = p.chat[#p.chat]; return m and m[2] end
reset(2, 2); startRound(1)
forceEnd(NULL, false)
check("listen console mid-round: round not ended", GAMEMODE:InRound(), true)
check("  ...told access is denied", printed ~= nil and printed:find("Access denied", 1, true) ~= nil, true)
check("  ...not that no round is running", printed ~= nil and printed:find("Not in active round", 1, true), nil)
local joe = S.Player{ name = "joe" }
forceEnd(joe)
check("non-staff player mid-round: round not ended", GAMEMODE:InRound(), true)
check("  ...told access is denied", lastChat(joe), "MISC_ACCESSDENIED")
forceEnd(NULL)
check("dedicated console mid-round: round ended", GAMEMODE:InRound(), false)
check("  ...no refusal printed", printed, nil)
forceEnd(NULL)
check("dedicated console between rounds: told no round is running",
  printed ~= nil and printed:find("Not in active round", 1, true) ~= nil, true)
local admin = S.Player{ name = "admin", staff = true }
forceEnd(admin)
check("staff between rounds: still 'unavailable'", lastChat(admin), "[PHX] Sorry, this command is unavailable.")
reset(2, 2); startRound(1)
forceEnd(admin, false)
check("staff player on a listen server: round ended", GAMEMODE:InRound(), false)

S.boolCVar("ph_waitforplayers", "0")
reset(2, 0)
startRound(1)
check("waitforplayers off, 2v0: round is timed", GetGlobalFloat("RoundEndTime", -1) > 0, true)
check("waitforplayers off: not flagged", GetGlobalBool("RoundWaitForPlayers", true), false)
advance(301)
check("waitforplayers off: round counted", GetGlobalInt("RoundNumber"), 1)

report()
