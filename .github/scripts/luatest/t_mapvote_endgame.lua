local here = (debug.getinfo(1, "S").source:match("@(.*/)") or "./")
dofile(here .. "runner.lua")
local F = dofile(here .. "mapvote_fixture.lua")
local boot, run, count, offered, players, vote, timerAt =
  F.boot, F.run, F.count, F.offered, F.players, F.vote, F.timerAt

-- Cancelling the end-of-game map vote. GM:EndOfGame freezes everyone and no
-- round starts after it, so that vote is the only way off the map. Every way of
-- cancelling it - mv_stop (which both vote screens' Cancel button runs), ulx
-- unmap_vote, the server console, a Lua caller - is refused and the vote goes
-- on to change map. A mid-game vote still cancels exactly as before. RTV at the
-- end of the game is in t_mapvote_endgame_rtv.lua. Setup is shared with the
-- other map vote tests in mapvote_fixture.lua.

local MAPS = { "ph_a", "ph_b", "ph_c" }
local NOCANCEL = "PHXM_MV_ENDGAME_NOCANCEL"

local function lastMsg(p) return p.chat[#p.chat] and p.chat[#p.chat][2] end
local function stop(p) return attempt(S.concommands["mv_stop"].fn, p, "mv_stop", {}) end
local function unmapVote(p) return attempt(S.ulx["ulx map_vote"], p, 25, true) end

-- print and ulx.fancyLogAdmin, recorded so what they said can be asserted on.
local out, logs = {}, {}
local realPrint = print
local function quiet(fn, ...)
  out = {}
  print = function(...) out[#out + 1] = table.concat({ ... }, " ") end
  local r = attempt(fn, ...)
  print = realPrint
  return r
end
ulx.fancyLogAdmin = function(_, msg) logs[#logs + 1] = msg end

-- A fresh map with the end-of-game vote open: the game ended the way the round
-- controller ends it and the voting delay has passed.
local function endOfGameVote(n)
  S.files, logs = {}, {}
  boot{ map = "ph_a", ulxmaps = MAPS }
  local ps = players(n or 3)
  ps[1]._staff = true
  GAMEMODE:EndOfGame(true)
  run(GAMEMODE.VotingDelay)
  return ps
end

-- Let the vote run out, then the 4 s grace before its changelevel.
local function finish()
  run(PHX.MV.PHXConfig.TimeLimit)
  local picked = PHX.MV.ChangingMap
  run(4)
  return picked
end

------------------------------------------------------------------------------
print("\n== mv_stop and the vote screens' Cancel button ==")
------------------------------------------------------------------------------
do
  local ps = endOfGameVote()
  local admin = ps[1]
  local frozen = true
  for _, p in ipairs(ps) do frozen = frozen and p:IsFrozen() end
  check("the game has ended: everyone is frozen", frozen, true)
  check("the end-of-game vote is open", PHX.MV.Allow, true)
  vote(ps[2], 2)
  local deadline = timerAt("PHX.MV.Vote")

  check("staff mv_stop runs", stop(admin), "ok")
  check("  ...is refused: the vote stays open", PHX.MV.Allow, true)
  check("  ...and says why", lastMsg(admin), NOCANCEL)
  check("  ...clients are not told to close the vote", count("PHX.MV.Cancel"), 0)
  check("  ...its deadline is untouched", timerAt("PHX.MV.Vote"), deadline)
  check("  ...the vote cast so far stands", PHX.MV.Votes[ps[2]:SteamID()], 2)
  check("  ...nobody else hears about it", lastMsg(ps[3]), "CHAT_STARTING_MAPVOTE")

  stop(admin)
  check("a second mv_stop is refused too", PHX.MV.Allow, true)
  check("the vote still picks the voted map", finish(), offered()[2])
  check("  ...and changes to it, which is what unfreezes everyone", S.changelevel, offered()[2])
  check("  ...without errors", S.errors, 0)
end

------------------------------------------------------------------------------
print("\n== ulx unmap_vote ==")
------------------------------------------------------------------------------
do
  local admin = endOfGameVote()[1]
  check("ulx unmap_vote runs", unmapVote(admin), "ok")
  check("  ...is refused: the vote stays open", PHX.MV.Allow, true)
  check("  ...and says why", lastMsg(admin), NOCANCEL)
  check("  ...without announcing a cancel that did not happen", table.concat(logs, "|"), "")
  check("  ...clients are not told to close the vote", count("PHX.MV.Cancel"), 0)
  finish()
  check("  ...and the map still changes", S.changelevel ~= nil, true)
end

------------------------------------------------------------------------------
print("\n== the server console and Lua callers ==")
------------------------------------------------------------------------------
do
  endOfGameVote()
  check("mv_stop from the dedicated console runs", quiet(S.concommands["mv_stop"].fn, NULL, "mv_stop", {}), "ok")
  check("  ...is refused", PHX.MV.Allow, true)
  check("  ...and says so in the console", (out[1] or ""):find("cannot be cancelled", 1, true) ~= nil, true)

  local r
  check("PHXCancel with no player runs", quiet(function() r = PHX.MV.PHXCancel() end), "ok")
  check("  ...returns false, so a caller can tell", r, false)
  check("  ...and the vote is still open", PHX.MV.Allow, true)
  finish()
  check("  ...then changes map", S.changelevel ~= nil, true)
end

do
  -- Asked in the voting delay, before the vote has even opened.
  S.files, logs = {}, {}
  boot{ map = "ph_a", ulxmaps = MAPS }
  local admin = players(2)[1]; admin._staff = true
  GAMEMODE:EndOfGame(true)
  run(1)
  stop(admin)
  check("mv_stop in the voting delay is refused", lastMsg(admin), NOCANCEL)
  run(GAMEMODE.VotingDelay)
  check("  ...and the vote still opens", PHX.MV.Allow, true)
  finish()
  check("  ...and changes map", S.changelevel ~= nil, true)
end

------------------------------------------------------------------------------
print("\n== normal play: a mid-game vote can still be cancelled ==")
------------------------------------------------------------------------------
do
  S.files, logs = {}, {}
  boot{ map = "ph_a", ulxmaps = MAPS }
  local admin = players(2)[1]; admin._staff = true
  S.concommands["mv_start"].fn(admin, "mv_start", {})
  check("mid-game vote opens", PHX.MV.Allow, true)
  check("mv_stop runs", stop(admin), "ok")
  check("  ...closes it", PHX.MV.Allow, false)
  check("  ...tells clients", count("PHX.MV.Cancel"), 1)
  check("  ...with no refusal", #admin.chat, 0)
  run(60); run(4)
  check("  ...and the map never changes", S.changelevel, nil)

  S.ulx["ulx map_vote"](admin, 25, false)
  check("ulx map_vote mid-game opens a vote", PHX.MV.Allow, true)
  check("ulx unmap_vote runs", unmapVote(admin), "ok")
  check("  ...closes it", PHX.MV.Allow, false)
  check("  ...and is logged as before", logs[#logs], "#A canceled the votemap!")
  check("  ...with no refusal", #admin.chat, 0)

  S.concommands["mv_start"].fn(admin, "mv_start", {})
  local r = PHX.MV.PHXCancel()
  check("PHXCancel mid-game does not report a refusal", r ~= false, true)
  check("  ...and closes the vote", PHX.MV.Allow, false)
  check("  ...without errors", S.errors, 0)
end

report()
