dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- Team flow: the per-round swap, E+ balancing (consecutive hunting, rotation),
-- joining a team, the team-switch limit, and what counts toward team score.

local scores = {}
function team.GetScore(id) return scores[id] or 0 end
function team.SetScore(id, v) scores[id] = v end
function team.AddScore(id, v) scores[id] = (scores[id] or 0) + v end
function RealTime() return CURTIME end
function UTIL_StripAllPlayers() end
function UTIL_SpawnAllPlayers() end
function S.PlyMeta:UserID() return self._idx end
function S.PlyMeta:IsPlaying() return self._team == TEAM_HUNTERS or self._team == TEAM_PROPS end
function S.PlyMeta:IsValid() return true end
local hookSwapArgs = {}
hook.Add("PH_OnPreRoundStart", "test", function(num, swap) hookSwapArgs[#hookSwapArgs + 1] = swap end)

loadblocks("sh_enhancedplus.lua",
  extractAll("gamemodes/prop_hunt/gamemode/enhancedplus/sh_enhancedplus.lua", {
    [[^function GM:TeamHasEnoughPlayers]], [[^function GM:GetPlayingCount]],
    [[^function GM:GetHunterCount]], [[^function GM:CustomTeamHasEnoughPlayers]],
    [[^function GM:PlayerCanJoinTeam]] }))
loadblocks("sv_enhancedplus.lua@Balance",
  extractAll("gamemodes/prop_hunt/gamemode/enhancedplus/sv_enhancedplus.lua", {
    [[^function GM:CheckTeamBalanceCustom]], [[^function GM:CheckTeamBalance\(]] }))
loadblocks("init.lua@OnPreRoundStart",
  extract("gamemodes/prop_hunt/gamemode/init.lua", [[^function GM:OnPreRoundStart]]))

S.boolCVar("ph_swap_teams_every_round", "1")
S.boolCVar("ph_notice_prop_rotation", "0")
CreateConVar("ph_usable_prop_type", "1")
S.boolCVar("ph_allow_armor", "1")
S.boolCVar("ph_enable_teambalance", "1")
S.boolCVar("ph_team_balance_classic", "1")
CreateConVar("ph_give_grenade_roundend_before_time", "15")
S.boolCVar("ph_give_grenade_near_roundend", "0")
S.boolCVar("ph_forcespectatorstoplay", "0")
CreateConVar("ph_huntercount", "0")
S.boolCVar("ph_rotateteams", "0")
S.boolCVar("ph_preventconsecutivehunting", "1")
S.boolCVar("ph_force_join_balanced_teams", "0")
GAMEMODE.RoundLength = 300
function GAMEMODE:FindLeastCommittedPlayerOnTeam(t) return team.GetPlayers(t)[1] end

local function cv(n, v) S.cvars[n].v = v end
local function lobby(h, p)
  S.players, S.timers, scores, hookSwapArgs = {}, {}, {}, {}
  for i = 1, h + p do
    S.players[i] = S.Player{ name = "p" .. i, idx = i, team = (i <= h) and TEAM_HUNTERS or TEAM_PROPS }
  end
end
local function hunters()
  local set = {}
  for _, pl in ipairs(S.players) do if pl:Team() == TEAM_HUNTERS then set[#set + 1] = pl._name end end
  return table.concat(set, ",")
end
-- Play n rounds through the real OnPreRoundStart, the winning team scoring each.
-- Returns hunter sets per round, per-player hunt counts and consecutive repeats.
local function play(n)
  local sets, count, consec = {}, {}, 0
  local last = {}
  for r = 1, n do
    SetGlobalInt("RoundNumber", r)
    GAMEMODE:OnPreRoundStart(r)
    S.pump(2)                                    -- the armor timer
    sets[r] = hunters()
    local now = {}
    for _, pl in ipairs(S.players) do
      if pl:Team() == TEAM_HUNTERS then
        now[pl] = true
        count[pl._name] = (count[pl._name] or 0) + 1
        if last[pl] then consec = consec + 1 end
      end
    end
    last = now
    team.AddScore(math.random(2) == 1 and TEAM_HUNTERS or TEAM_PROPS, 1)
  end
  return sets, count, consec
end
local function spread(count, names)
  local lo, hi = math.huge, 0
  for _, n in ipairs(names) do lo = math.min(lo, count[n] or 0); hi = math.max(hi, count[n] or 0) end
  return lo, hi
end
math.randomseed(7)

print("\n== ph_swap_teams_every_round decides the swap on its own ==")
lobby(4, 4)
local sets = play(6)
local swapped = 0
for r = 2, 6 do if sets[r] ~= sets[r - 1] then swapped = swapped + 1 end end
check("swap 1 (default): teams swap every round", swapped, 5)
check("swap 1: PH_OnPreRoundStart fires rounds 2-6", #hookSwapArgs, 5)
check("swap 1: the hook is told a swap happened", hookSwapArgs[1], true)

cv("ph_swap_teams_every_round", "0")
lobby(4, 4)
sets = play(6)                                   -- scores > 0 from round 1 on
local same = 0
for r = 2, 6 do if sets[r] == sets[r - 1] then same = same + 1 end end
check("swap 0: teams stay put although scores > 0", same, 5)
check("swap 0: PH_OnPreRoundStart still fires", #hookSwapArgs, 5)
check("swap 0: the hook is told no swap", hookSwapArgs[1], false)
local armored = 0
for _, pl in ipairs(S.players) do if pl:Team() == TEAM_PROPS and pl:Armor() > 0 then armored = armored + 1 end end
check("swap 0: props still get the 4+ hunters armor bonus", armored, 4)

lobby(4, 4)
SetGlobalInt("RoundNumber", 1)
GAMEMODE:OnPreRoundStart(1)
local flagged = 0
for _, pl in ipairs(S.players) do if pl.PHXHuntedLastRound then flagged = flagged + 1 end end
check("round 1: nobody counts as last round's hunter", flagged, 0)

print("\n== ph_preventconsecutivehunting (E+ shuffle) ==")
cv("ph_team_balance_classic", "0")
local names6 = { "p1", "p2", "p3", "p4", "p5", "p6" }
for _, sw in ipairs{ "0", "1" } do
  cv("ph_swap_teams_every_round", sw)
  lobby(2, 4)
  local _, count, consec = play(30)
  check(("swap %s: nobody hunts two rounds running"):format(sw), consec, 0)
  local lo = spread(count, names6)
  check(("swap %s: everyone hunts at some point"):format(sw), lo > 0, true)
end

cv("ph_preventconsecutivehunting", "0")
lobby(2, 4)
local _, count0 = play(10)
local total = 0
for _, n in ipairs(names6) do total = total + (count0[n] or 0) end
check("preventconsecutivehunting off: still 2 hunters a round", total, 20)
cv("ph_preventconsecutivehunting", "1")

-- the guard for "everyone hunted last round": still leaves hunters to pick
for _, n in ipairs{ 3, 4, 6 } do
  lobby(n, 0)
  for _, pl in ipairs(S.players) do pl.PHXHuntedLastRound = true end
  GAMEMODE:CheckTeamBalanceCustom()
  local h = 0
  for _, pl in ipairs(S.players) do if pl:Team() == TEAM_HUNTERS then h = h + 1 end end
  check(("%d players all hunted last round: still a hunter"):format(n), h > 0, true)
end

print("\n== ph_rotateteams rotates fairly ==")
cv("ph_rotateteams", "1")
for _, sw in ipairs{ "1", "0" } do
  cv("ph_swap_teams_every_round", sw)
  SetGlobalInt("RotateTeamsOffset", 1)
  lobby(2, 4)
  local _, count = play(12)
  local lo, hi = spread(count, names6)
  -- (the window advances one player a round, so some overlap is by design)
  check(("rotate, swap %s: everyone hunts 4 of 12"):format(sw), lo .. "-" .. hi, "4-4")
end
cv("ph_rotateteams", "0")
cv("ph_swap_teams_every_round", "1")
cv("ph_team_balance_classic", "1")

print("\n== joining a team ==")
-- base: the engine base gamemode's check (cooldown, already on that team)
local BASE = {}
function BASE:PlayerCanJoinTeam(ply, teamid)
  if ply.LastTeamSwitch and RealTime() - ply.LastTeamSwitch < 30 then return false end
  if ply:Team() == teamid then return false end
  return true
end
baseclass = { Get = function(n) if n == "gamemode_base" then return BASE end end }
-- base_phx: its own PlayerCanJoinTeam, which adds the classic "team is full" rule
local BPHX = { BaseClass = BASE }
GM = BPHX
loadblocks("base_phx shared.lua@PlayerCanJoinTeam",
  extract("gamemodes/base_phx/gamemode/shared.lua", [[^function GM:PlayerCanJoinTeam]]))
GM = GAMEMODE
GAMEMODE.BaseClass = BPHX

local function canJoin(h, p, spec, want, opts)
  opts = opts or {}
  lobby(h, p)
  local joiner
  for i = 1, spec do
    joiner = S.Player{ name = "s" .. i, idx = 100 + i, team = TEAM_SPECTATOR }
    S.players[#S.players + 1] = joiner
  end
  if opts.from then joiner = team.GetPlayers(opts.from)[1] end
  if opts.cooldown then joiner.LastTeamSwitch = CURTIME - 5 end
  return GAMEMODE:PlayerCanJoinTeam(joiner, want)
end

S.boolCVar("ph_force_join_balanced_teams", "1")
cv("ph_team_balance_classic", "0")
for _, hp in ipairs{ { 1, 2 }, { 2, 4 }, { 3, 6 } } do
  local h, p = hp[1], hp[2]
  check(("E+ ratio, %dh/%dp: spectator may join Props"):format(h, p), canJoin(h, p, 1, TEAM_PROPS), true)
  check(("E+ ratio, %dh/%dp: Hunters quota full"):format(h, p), canJoin(h, p, 1, TEAM_HUNTERS), false)
end
cv("ph_team_balance_classic", "1")
check("classic force-join, 1h/2p: Props full", canJoin(1, 2, 1, TEAM_PROPS), false)
check("classic force-join, 1h/2p: Hunters open", canJoin(1, 2, 1, TEAM_HUNTERS), true)
check("classic force-join, 2h/4p +3 spec: a prop may spectate",
  canJoin(2, 4, 3, TEAM_SPECTATOR, { from = TEAM_PROPS }), true)
cv("ph_force_join_balanced_teams", "0")
check("force-join off: Props open", canJoin(1, 2, 1, TEAM_PROPS), true)
check("base cooldown still applies", canJoin(1, 2, 1, TEAM_HUNTERS, { cooldown = true }), false)
check("base same-team check still applies", canJoin(2, 2, 0, TEAM_PROPS, { from = TEAM_PROPS }), false)

print("\n== the team-switch limit ==")
loadblocks("init.lua@switchLimitter",
  extract("gamemodes/prop_hunt/gamemode/init.lua", [[^hook\.Add\("OnPlayerChangedTeam", "TeamChange_switchLimitter"]]))
CreateConVar("ph_max_teamchange_limit", "2")
local limiter = S.hooks["OnPlayerChangedTeam"]["TeamChange_switchLimitter"]
local function move(pl, new)
  local old = pl:Team()
  pl:SetTeam(new)                               -- PlayerJoinTeam sets the team first
  limiter(pl, old, new)
  S.pump(0.5)
end
S.timers = {}
local pl = S.Player{ team = TEAM_SPECTATOR }
pl.ChangeLimit = 0
move(pl, TEAM_PROPS)
check("first join from Spectator is not a switch", pl.ChangeLimit, 0)
move(pl, TEAM_HUNTERS)
move(pl, TEAM_PROPS)
check("two real switches counted", pl.ChangeLimit, 2)
move(pl, TEAM_SPECTATOR)
move(pl, TEAM_PROPS)
check("back to the same team via Spectator is not a switch", pl.ChangeLimit, 2)
check("... and is allowed", pl:Team(), TEAM_PROPS)
move(pl, TEAM_HUNTERS)
check("over the limit: switch reverted", pl:Team(), TEAM_PROPS)
move(pl, TEAM_SPECTATOR)
move(pl, TEAM_HUNTERS)
check("over the limit via Spectator: still reverted", pl:Team(), TEAM_PROPS)
check("counter stays capped", pl.ChangeLimit, 2)
local staff = S.Player{ team = TEAM_PROPS, staff = true }
staff.ChangeLimit = 0
move(staff, TEAM_HUNTERS); move(staff, TEAM_PROPS); move(staff, TEAM_HUNTERS)
check("staff are not limited", staff:Team(), TEAM_HUNTERS)

print("\n== team balance notice uses the reader's language ==")
function PHX:TranslateName(id, ply) return team.GetName(id) .. "@" .. ply._name end
lobby(4, 1)
S.boolCVar("ph_force_join_balanced_teams", "0")
GAMEMODE:CheckTeamBalance(true)
local reader, msg
for _, p in ipairs(S.players) do
  for _, c in ipairs(p.chat) do
    if c[2] == "CHAT_SWAPBALANCE" then reader, msg = p, c end
  end
end
check("someone was told about the swap", msg ~= nil, true)
check("team name translated for the listener", msg and msg[4], "Props@" .. (reader and reader._name))

print("\n== team score counts rounds, not frags ==")
loadblocks("sh_init.lua@AddFrags",
  extract("gamemodes/prop_hunt/gamemode/sh_init.lua", [[^GM\.AddFragsToTeamScore]]))
check("GM.AddFragsToTeamScore", GAMEMODE.AddFragsToTeamScore, false)
loadblocks("base_phx init.lua@DoPlayerDeath",
  extract("gamemodes/base_phx/gamemode/init.lua", [[^function GM:DoPlayerDeath]]))
function S.PlyMeta:CallClassFunction() end
GAMEMODE.TeamBased = true
scores = {}
local prop, hunter = S.Player{ team = TEAM_PROPS }, S.Player{ team = TEAM_HUNTERS }
GAMEMODE:DoPlayerDeath(hunter, prop, {})
check("a prop's kill of a hunter adds no team score", team.GetScore(TEAM_PROPS), 0)
check("... but still a frag for the prop", prop:Frags(), 1)

report()
