local here = (debug.getinfo(1, "S").source:match("@(.*/)") or "./")
dofile(here .. "runner.lua")
local F = dofile(here .. "mapvote_fixture.lua")
local boot, run, count, lastSent, offered, has, players, endGame, vote =
  F.boot, F.run, F.count, F.lastSent, F.offered, F.has, F.players, F.endGame, F.vote

-- Map vote lifecycle: start, the vote itself, the end-of-game hand-off, the
-- custom map vote settings and mv_map_prefix. RTV, cancel and the round
-- controller contract are in t_mapvote_rtv.lua; the setup both share is in
-- mapvote_fixture.lua.

-- Stock Lua has no `continue`; the extractor leaves it in place, and a loop that
-- used it would run bodies it should skip. None of these files may rely on it.
local function hasContinue(src) return src:find("%f[%w_]continue%f[^%w_]") ~= nil end
check("sv_mapvote.lua needs no `continue` translation", hasContinue(F.SV), false)
check("rtv.lua needs no `continue` translation", hasContinue(F.RTV), false)

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

report()
