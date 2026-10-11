dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- base_phx's GM:Think ends a timed game once its limit passes, and the client
-- half of GM:AddRoundTime. Both use the shipped code.

print("\n== GM:Think: no time limit (-1) never ends the game ==")
-- The class loop's `continue` can't be parsed by stock LuaJIT (CI); with no
-- players the loop never runs, so that line is dropped.
local thinkSrc, stripped = extract("gamemodes/base_phx/gamemode/init.lua", [[^function GM:Think]])
  :gsub("if %(%s*not Class %) then continue end", "")
check("harness: the one `continue` line was stripped", stripped, 1)
loadblocks("init.lua@Think", thinkSrc)

local ended = 0
GAMEMODE.BaseClass = { Think = function() end }
function GAMEMODE:EndOfGame() ended = ended + 1 end
S.players = {}

local function tick(limit, canEnd)
  ended, GAMEMODE.IsEndOfGame, GAMEMODE.RoundBased = 0, false, true
  function GAMEMODE:CanEndRoundBasedGame() return canEnd end
  function GAMEMODE:GetTimeLimit() return limit end
  GAMEMODE:Think()
  return ended
end

check("round-based, can end mid-round, no limit: game goes on", tick(-1, true), 0)
check("round-based, can end mid-round, limit passed: game ends", tick(CurTime() - 1, true), 1)
check("round-based, can end mid-round, limit ahead: game goes on", tick(CurTime() + 60, true), 0)
check("round-based, cannot end mid-round, limit passed: left to PreRoundStart", tick(CurTime() - 1, false), 0)

print("\n== the client handles PHX.RoundAddedTime ==")
loadblocks("cl_hud.lua@AddedTime", extractAll("gamemodes/base_phx/gamemode/cl_hud.lua",
  { [[^function GM:UpdateHUD_AddedTime]], [[^net\.Receive\( "PHX\.RoundAddedTime"]] }))
check("receiver is registered", type(S.receivers["PHX.RoundAddedTime"]), "function")
local got
function GAMEMODE:UpdateHUD_AddedTime(t) got = t end
net.ReadFloat = function() return 60 end
S.receivers["PHX.RoundAddedTime"]()
check("  ... and passes the added time to GM:UpdateHUD_AddedTime", got, 60)

report()
