dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

print("\n== CheckTeamBalanceCustom must always leave at least one hunter ==")
-- ph_preventconsecutivehunting flags last round's hunters so they are not picked
-- again. If EVERY player is flagged, the shuffle has nobody left to pick and the
-- round starts with zero hunters - CheckPlayerDeathRoundEnd then ends it
-- immediately and the server spins through rounds.
loadblocks("sh_enhancedplus.lua",
  extractAll("gamemodes/prop_hunt/gamemode/enhancedplus/sh_enhancedplus.lua", {
    [[^function GM:GetPlayingCount]], [[^function GM:GetHunterCount]] }))
loadblocks("sv_enhancedplus.lua@Balance",
  extractAll("gamemodes/prop_hunt/gamemode/enhancedplus/sv_enhancedplus.lua", {
    [[^local function InRotateWindow]], [[^local function FillHunterSlots]], [[^function GM:RotateTeams]], [[^function GM:CheckTeamBalanceCustom]] }))

S.boolCVar("ph_forcespectatorstoplay", "0")
CreateConVar("ph_huntercount", "0")
S.boolCVar("ph_rotateteams", "0")
S.boolCVar("ph_preventconsecutivehunting", "1")
S.boolCVar("ph_swap_teams_every_round", "1")
S.boolCVar("ph_enable_teambalance", "1")

-- CheckTeamBalanceCustom flags last round's hunters, which OnPreRoundStart
-- records as PHXHuntedLastRound before the swap. `flaggedShare` picks how many
-- of the n players hunted: 1.0 is the degenerate all-flagged case, lower values
-- are an ordinary mixed lobby.
local function balance(n, flaggedShare)
  local flagged = math.floor(n * (flaggedShare or 0.34))
  S.players = {}
  for i = 1, n do
    S.players[i] = S.Player{ name = "p" .. i, idx = i,
                             team = (i <= flagged) and TEAM_PROPS or TEAM_HUNTERS }
    S.players[i].PHXHuntedLastRound = (i <= flagged)
  end
  GAMEMODE:CheckTeamBalanceCustom()
  local h, p = 0, 0
  for _, ply in ipairs(S.players) do
    if ply:Team() == TEAM_HUNTERS then h = h + 1 else p = p + 1 end
  end
  return h, p
end

-- the ordinary case: a mix of teams, some flagged, some not
local h, p = balance(6, 0.34)
check("6 players, mixed -> some hunters", h > 0, true)
check("6 players, mixed -> some props", p > 0, true)

-- the degenerate case: everyone was a hunter last round, so everyone is flagged
for _, n in ipairs{ 2, 3, 4, 6, 9 } do
  local hh, pp = balance(n, 1.0)
  check(("%d players, ALL flagged -> at least one hunter"):format(n), hh > 0, true)
  check(("%d players, ALL flagged -> at least one prop"):format(n), pp > 0, true)
end

-- flags must be cleared afterwards so the next round is not also degenerate
local cleared = true
for _, ply in ipairs(S.players) do
  if ply:IsCurrentlyForcedAsProp() then cleared = false end
end
check("forced-as-prop flags cleared after balancing", cleared, true)

print("\n== ph_rotateteams honours and clears Force Hunter as Prop ==")
S.cvars["ph_rotateteams"].v = "1"
local function rotate(n, forced, offset)
  S.players = {}
  for i = 1, n do
    S.players[i] = S.Player{ name = "r" .. i, uid = 100 + i, team = TEAM_PROPS }
    if forced[i] then S.players[i]:SetForceAsProp(true) end
  end
  SetGlobalInt("RotateTeamsOffset", offset)
  GAMEMODE:CheckTeamBalanceCustom()
  local hunters, anyFlag = {}, false
  for i, ply in ipairs(S.players) do
    if ply:Team() == TEAM_HUNTERS then hunters[#hunters + 1] = i end
    if ply:IsCurrentlyForcedAsProp() then anyFlag = true end
  end
  return hunters, anyFlag
end

-- 6 players -> 2 hunters. Offset 0: the window is players 1-2.
local hs = rotate(6, {}, 0)
check("rotate, nobody forced -> window hunts", table.concat(hs, ","), "1,2")
hs, flag = rotate(6, { [1] = true }, 0)
check("rotate, window player forced -> next in order hunts", table.concat(hs, ","), "2,3")
check("rotate, forced flag cleared", flag, false)
hs = rotate(6, { [6] = true }, 5)	-- window wraps: players 6 and 1
check("rotate, forced player at the wrap -> still two hunters", #hs, 2)
check("rotate, forced player at the wrap is a prop", S.players[6]:Team(), TEAM_PROPS)
hs = rotate(3, { [1] = true, [2] = true, [3] = true }, 0)
check("rotate, everyone forced -> force ignored, one hunter", #hs, 1)
S.cvars["ph_rotateteams"].v = "0"

report()
