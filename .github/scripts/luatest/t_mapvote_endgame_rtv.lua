local here = (debug.getinfo(1, "S").source:match("@(.*/)") or "./")
dofile(here .. "runner.lua")
local F = dofile(here .. "mapvote_fixture.lua")
local boot, run, count, offered, players, vote, timerAt =
  F.boot, F.run, F.count, F.offered, F.players, F.vote, F.timerAt

-- RTV meeting the end of the game. GM:EndOfGame(true) starts its own vote after
-- GAMEMODE.VotingDelay, so RTV has nothing to start until then, and a built-in
-- vote already open (or decided) when the game ends is the one that changes
-- map rather than being started over. Setup is shared with the other map vote
-- tests in mapvote_fixture.lua.

local NOCANCEL = "PHXM_MV_ENDGAME_NOCANCEL"

local function say(p, text) return S.fire("PlayerSay", p, text) end
local function lastMsg(p) return p.chat[#p.chat] and p.chat[#p.chat][2] end
local function heard(p, key)
  for _, c in ipairs(p.chat) do if c[2] == key then return true end end
  return false
end
-- print, recorded around a call so a log line can be asserted on.
local function logged(fn, ...)
  local lines, real = {}, print
  print = function(...) lines[#lines + 1] = table.concat({ ... }, " ") end
  local r = attempt(fn, ...)
  print = real
  -- run() reports a timer error by printing it: never swallow one.
  for _, l in ipairs(lines) do if l:find("timer error", 1, true) then print(l) end end
  return table.concat(lines, "\n"), r
end
local function leave(p)
  S.fire("PlayerDisconnected", p)
  for i, x in ipairs(S.players) do if x == p then table.remove(S.players, i) break end end
  p.__valid = false
  return (logged(run, 0.1))
end

-- A map past RTV's 60 s wait, with player 1 on staff.
local function fresh(n, o)
  S.files = {}
  o = o or {}
  o.map, o.ulxmaps = "ph_a", { "ph_a", "ph_b", "ph_c", "ph_d" }
  boot(o)
  local ps = players(n or 6)
  ps[1]._staff = true
  _G.CURTIME = _G.CURTIME + 61
  return ps
end
local function rock(ps, n) for i = 1, n or 4 do say(ps[i], "rtv") end end
local function stop(p) return attempt(S.concommands["mv_stop"].fn, p, "mv_stop", {}) end
-- The vote runs out, then changelevel's 4 s grace.
local function finish()
  run(PHX.MV.PHXConfig.TimeLimit)
  run(4)
  return S.changelevel
end

------------------------------------------------------------------------------
print("\n== an RTV countdown the game ends under ==")
------------------------------------------------------------------------------
do
  local ps = fresh()
  rock(ps)
  check("rtv rocked: the 4 s countdown is armed", timerAt("PHX.RTV.Start") ~= nil, true)
  run(1)
  GAMEMODE:EndOfGame(true)
  run(3)
  check("its time is up after the game ended: no vote of its own", count("PHX.MV.Start"), 0)
  check("  ...and the tally is spent", PHX.MV.RTV.TotalVotes, 0)
  run(GAMEMODE.VotingDelay - 3)
  check("the end-of-game vote opens", count("PHX.MV.Start"), 1)
  vote(ps[2], 2); vote(ps[3], 2)
  local deadline = timerAt("PHX.MV.Vote")
  run(10)
  check("exactly one vote", count("PHX.MV.Start"), 1)
  check("  ...the votes cast stand", PHX.MV.Votes[ps[2]:SteamID()], 2)
  check("  ...so does its deadline", timerAt("PHX.MV.Vote"), deadline)
  check("  ...and it changes to the voted map", finish(), offered()[2])
  check("  ...without errors", S.errors, 0)
end

do
  -- ph_use_custom_mapvote_cmd: the addon's command is run once, not twice.
  local ps = fresh(6, { customCmd = true, concmd = "addon_mapvote 15" })
  rock(ps)
  run(1)
  GAMEMODE:EndOfGame(true)
  run(GAMEMODE.VotingDelay)
  check("custom command mode: the addon is asked once", table.concat(S.consolecmds, "|"), "addon_mapvote 15\n")
  check("  ...and no built-in vote races it", count("PHX.MV.Start"), 0)
end

------------------------------------------------------------------------------
print("\n== rtv once the game is over ==")
------------------------------------------------------------------------------
do
  local ps = fresh()
  rock(ps, 2)
  GAMEMODE:EndOfGame(true)
  say(ps[3], "rtv")
  check("rtv in the voting delay: told the end-of-game vote is starting", lastMsg(ps[3]), "CHAT_STARTING_MAPVOTE")
  check("  ...and it is not counted", PHX.MV.RTV.TotalVotes, 2)
  check("  ...nothing is armed", timerAt("PHX.RTV.Start"), nil)
  check("  ...and nobody is told the vote rocked", heard(ps[1], "PHXM_MV_VOTEROCKED_IMMINENT"), false)
  -- 2 of 6 already in; three leaving make it 2 of 3, which is over the line.
  leave(ps[6]); leave(ps[5]); leave(ps[4])
  check("  (the tally is over the line now)", PHX.MV.RTV.ShouldChange(), true)
  check("disconnects tipping the tally over: nothing armed", timerAt("PHX.RTV.Start"), nil)
  check("  ...nobody is told the vote rocked", heard(ps[1], "PHXM_MV_VOTEROCKED_IMMINENT"), false)
  PHX.MV.RTV.Start()
  check("RTV.Start called directly: nothing armed", timerAt("PHX.RTV.Start"), nil)
  check("  ...nobody is told the vote rocked", heard(ps[1], "PHXM_MV_VOTEROCKED_IMMINENT"), false)
  check("  ...and the tally is spent", PHX.MV.RTV.TotalVotes, 0)
  run(GAMEMODE.VotingDelay)
  check("one vote, the end-of-game one", count("PHX.MV.Start"), 1)
  say(ps[3], "rtv")
  check("rtv during it: a vote is in progress, as before", lastMsg(ps[3]), "PHXM_MV_VOTEINPROG")
  run(PHX.MV.PHXConfig.TimeLimit)
  say(ps[3], "rtv")
  check("rtv once it is decided: the map is changing, as before", lastMsg(ps[3]), "PHXM_MV_ALR_IN_VOTE")
  run(4)
  check("still one vote, and the map changes", count("PHX.MV.Start") == 1 and S.changelevel ~= nil, true)
end

do
  -- Everyone leaving in the voting delay: the end-of-game vote is already on
  -- its way, so RTV's "server emptied" start is not needed.
  local ps = fresh(2)
  GAMEMODE:EndOfGame(true)
  local log = leave(ps[1]) .. leave(ps[2])
  check("server empties in the voting delay: no 'Server emptied' start", log:find("Server emptied", 1, true), nil)
  check("  ...nothing armed", timerAt("PHX.RTV.Start"), nil)
  run(GAMEMODE.VotingDelay)
  check("  ...the end-of-game vote still runs", count("PHX.MV.Start"), 1)
  check("  ...and changes map", finish() ~= nil, true)
end

------------------------------------------------------------------------------
print("\n== a vote already open or decided when the game ends ==")
------------------------------------------------------------------------------
do
  -- The round controller waits out a running vote, so this is an addon (or a
  -- GM:CanEndRoundBasedGame override) ending the game mid-vote.
  local ps = fresh()
  rock(ps)
  run(4)
  check("the RTV vote is open", count("PHX.MV.Start") == 1 and PHX.MV.Allow, true)
  vote(ps[2], 3); vote(ps[3], 3)
  local deadline = timerAt("PHX.MV.Vote")
  run(2)
  GAMEMODE:EndOfGame(true)
  local log = logged(run, GAMEMODE.VotingDelay)
  check("the game ends under it: it is kept, not started again", count("PHX.MV.Start"), 1)
  check("  ...and the console says why", log:find("that vote picks the next map", 1, true) ~= nil, true)
  check("  ...its votes stand", PHX.MV.Votes[ps[2]:SteamID()], 3)
  check("  ...its deadline too", timerAt("PHX.MV.Vote"), deadline)
  stop(ps[1])
  check("  ...staff can no longer cancel it", PHX.MV.Allow, true)
  check("  ...and are told why", lastMsg(ps[1]), NOCANCEL)
  check("  ...it changes to the voted map", finish(), offered()[3])
  check("  ...without errors", S.errors, 0)
end

do
  -- Staff start a vote in the voting delay: that is the end-of-game vote now.
  local ps = fresh(3)
  GAMEMODE:EndOfGame(true)
  run(1)
  S.concommands["mv_start"].fn(ps[1], "mv_start", {})
  vote(ps[2], 1)
  logged(run, GAMEMODE.VotingDelay)
  check("mv_start in the voting delay: one vote", count("PHX.MV.Start"), 1)
  check("  ...its vote stands", PHX.MV.Votes[ps[2]:SteamID()], 1)
  check("  ...and it changes map", finish(), offered()[1])
end

do
  -- A vote already decided, its changelevel pending, when the game ends.
  local ps = fresh(3)
  S.concommands["mv_start"].fn(ps[1], "mv_start", {})
  vote(ps[2], 2)
  run(PHX.MV.PHXConfig.TimeLimit)
  local won = PHX.MV.ChangingMap
  check("a result is in", won, offered()[2])
  GAMEMODE:EndOfGame(true)
  logged(run, GAMEMODE.VotingDelay)
  check("the game ends in its grace: no new vote", count("PHX.MV.Start"), 1)
  check("  ...and the decided map is the one changed to", S.changelevel, won)
end

do
  -- A custom function that failed fell back to the built-in vote; keeping it
  -- must not also run the function again.
  local ps = fresh(3, { custom = true, func = "error('addon missing')" })
  S.errors = 0
  PHX.StartMapVote()
  check("custom function failed: the built-in vote runs instead", count("PHX.MV.Start") == 1 and PHX.MV.Allow, true)
  vote(ps[2], 2)
  GAMEMODE:EndOfGame(true)
  logged(run, GAMEMODE.VotingDelay)
  check("the game ends under it: the function is not run again", #S.runstrings, 1)
  check("  ...and the vote is not started again", count("PHX.MV.Start"), 1)
  check("  ...it changes to the voted map", finish(), offered()[2])
end

------------------------------------------------------------------------------
print("\n== staff cancel at the end of the game clears an RTV countdown ==")
------------------------------------------------------------------------------
do
  local ps = fresh()
  rock(ps)
  run(1)
  GAMEMODE:EndOfGame(true)
  check("the countdown is still armed when staff act", timerAt("PHX.RTV.Start") ~= nil, true)
  check("mv_stop runs", stop(ps[1]), "ok")
  check("  ...is refused", lastMsg(ps[1]), NOCANCEL)
  check("  ...and still clears the countdown", timerAt("PHX.RTV.Start"), nil)
  check("  ...and the tally", PHX.MV.RTV.TotalVotes, 0)
  check("  ...so rtv starts from nothing", PHX.MV.RTV.Pending, false)
  run(GAMEMODE.VotingDelay)
  check("the end-of-game vote opens, once", count("PHX.MV.Start"), 1)
  check("  ...and changes map", finish() ~= nil, true)

  ps = fresh()
  rock(ps)
  GAMEMODE:EndOfGame(true)
  local _, r = logged(function() return PHX.MV.PHXCancel() end)
  check("PHXCancel from Lua at the end of the game runs", r, "ok")
  check("  ...and clears the countdown too", timerAt("PHX.RTV.Start"), nil)
end

------------------------------------------------------------------------------
print("\n== RTV waits only while the end-of-game vote is due ==")
------------------------------------------------------------------------------
do
  -- EndOfGame(false): an addon ends the game and schedules no vote. No round
  -- starts again, so RTV is the players' only way to one.
  local ps = fresh()
  GAMEMODE:EndOfGame(false)
  run(GAMEMODE.VotingDelay)
  check("EndOfGame(false): no vote opens by itself", count("PHX.MV.Start"), 0)
  rock(ps, 3)
  check("  ...rtv is counted", lastMsg(ps[3]), "PHXM_MV_VOTEROCKED_PLY_TOTAL")
  say(ps[4], "rtv")
  check("  ...and rocks the vote", lastMsg(ps[1]), "PHXM_MV_VOTEROCKED_IMMINENT")
  run(4)
  check("  ...which opens", count("PHX.MV.Start") == 1 and PHX.MV.Allow, true)
  vote(ps[2], 2)
  check("  ...and changes to the voted map", finish(), offered()[2])

  -- Custom command mode: the end-of-game vote goes to the addon, and PH:X
  -- cannot see it after that. If it never opened, rtv asks the addon again.
  ps = fresh(6, { customCmd = true, concmd = "addon_mapvote 15" })
  GAMEMODE:EndOfGame(true)
  say(ps[1], "rtv")
  check("custom command mode, voting delay: rtv waits", lastMsg(ps[1]), "CHAT_STARTING_MAPVOTE")
  run(GAMEMODE.VotingDelay)
  check("  ...the addon is asked when the delay is up", #S.consolecmds, 1)
  rock(ps)
  check("  after that rtv counts again", lastMsg(ps[1]), "PHXM_MV_VOTEROCKED_IMMINENT")
  run(4)
  check("  ...and asks the addon again", #S.consolecmds, 2)
  check("  ...never with a built-in vote alongside", count("PHX.MV.Start"), 0)
end

------------------------------------------------------------------------------
print("\n== mv_stop in custom mode stops an RTV countdown ==")
------------------------------------------------------------------------------
do
  for _, o in ipairs{ { customCmd = true, concmd = "addon_mapvote 15" }, { custom = true, func = "print('addon')" } } do
    local mode = o.customCmd and "command" or "function"
    local ps = fresh(6, o)
    rock(ps)
    check(mode .. " mode, rtv rocked: the countdown is armed", timerAt("PHX.RTV.Start") ~= nil, true)
    check("  ...mv_stop runs", stop(ps[1]), "ok")
    check("  ...clears the countdown", timerAt("PHX.RTV.Start"), nil)
    check("  ...and the tally", PHX.MV.RTV.TotalVotes, 0)
    run(4)
    check("  ...so the addon is never asked", #S.consolecmds + #S.runstrings, 0)
  end
end

------------------------------------------------------------------------------
print("\n== normal play is unchanged ==")
------------------------------------------------------------------------------
do
  local ps = fresh()
  rock(ps, 3)
  check("mid-game rtv is counted", lastMsg(ps[3]), "PHXM_MV_VOTEROCKED_PLY_TOTAL")
  say(ps[4], "rtv")
  check("  ...and rocks the vote at the threshold", lastMsg(ps[1]), "PHXM_MV_VOTEROCKED_IMMINENT")
  run(4)
  check("  ...which opens after the countdown", count("PHX.MV.Start") == 1 and PHX.MV.Allow, true)
  vote(ps[2], 2)
  check("  ...and changes to the voted map", finish(), offered()[2])

  -- Mid-game a second start still replaces a running vote, as it always has:
  -- keeping one is only for the end of the game.
  fresh(2)
  PHX.MV.PHXStart()
  PHX.StartMapVote()
  check("mid-game, a second start still restarts the vote", count("PHX.MV.Start"), 2)

  -- The end-of-game vote with no RTV about.
  ps = fresh(3)
  GAMEMODE:EndOfGame(true)
  run(GAMEMODE.VotingDelay)
  check("end of game, no RTV: one vote", count("PHX.MV.Start"), 1)
  vote(ps[2], 1); vote(ps[3], 1)
  check("  ...changes to the voted map", finish(), offered()[1])
  check("  ...without errors", S.errors, 0)

  -- Custom command mode mid-game: RTV still hands the vote to the addon.
  ps = fresh(6, { customCmd = true, concmd = "addon_mapvote 15" })
  rock(ps)
  run(4)
  check("custom command mode, mid-game rtv: the addon is asked", table.concat(S.consolecmds, "|"), "addon_mapvote 15\n")
end

report()
