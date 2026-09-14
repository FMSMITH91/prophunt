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
  extract("gamemodes/prop_hunt/gamemode/enhancedplus/sv_enhancedplus.lua",
          [[^function GM:CheckTeamBalanceCustom]]))

S.boolCVar("ph_forcespectatorstoplay", "0")
CreateConVar("ph_huntercount", "0")
S.boolCVar("ph_rotateteams", "0")
S.boolCVar("ph_preventconsecutivehunting", "1")
S.boolCVar("ph_swap_teams_every_round", "1")
S.boolCVar("ph_enable_teambalance", "1")

-- With ph_swap_teams_every_round on, CheckTeamBalanceCustom flags everyone
-- currently on TEAM_PROPS (ie. last round's hunters, post-swap). `flaggedShare`
-- picks how many of the n players sit there: 1.0 is the degenerate all-flagged
-- case, lower values are an ordinary mixed lobby.
local function balance(n, flaggedShare)
  local flagged = math.floor(n * (flaggedShare or 0.34))
  S.players = {}
  for i = 1, n do
    S.players[i] = S.Player{ name = "p" .. i, idx = i,
                             team = (i <= flagged) and TEAM_PROPS or TEAM_HUNTERS }
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

report()
