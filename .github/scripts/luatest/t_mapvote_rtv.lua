local here = (debug.getinfo(1, "S").source:match("@(.*/)") or "./")
dofile(here .. "runner.lua")
local F = dofile(here .. "mapvote_fixture.lua")
local boot, run, count, players, vote, timerAt =
  F.boot, F.run, F.count, F.players, F.vote, F.timerAt

-- Map vote RTV, cancel and the round controller: rock-the-vote starts one
-- vote, a cancel sticks, ph_enable_mapvote 0 only forces the end-of-game vote,
-- and ChangingMap tells the round controller the truth. Also checks PH:X's own
-- net, hook and timer names. Setup shared with t_mapvote_lifecycle.lua is in
-- mapvote_fixture.lua.

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
