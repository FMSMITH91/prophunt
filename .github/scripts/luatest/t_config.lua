dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

print("\n== ConVarTranslate: a custom callback must not lose the global sync ==")
-- Every PH:X cvar read goes through PHX:GetCVar -> GetGlobal*, so a cvar whose
-- change never reaches the global is a cvar that silently does nothing. Four
-- cvars in sh_convar.lua supply their own callback; none of them may drop it.
-- Constants block, then the ConVarTranslate table by name so this does not
-- re-break every time a line is added above it.
local head = extract("gamemodes/prop_hunt/gamemode/sh_convar.lua", "1-10")
  .. "\n" .. extract("gamemodes/prop_hunt/gamemode/sh_convar.lua", [[^local ConVarTranslate = \{]])

local function loadCVar(entrySpec)
  S.cvars, S.cvarcb, S.globals = {}, {}, {}
  local entry = extract("gamemodes/prop_hunt/gamemode/sh_convar.lua", entrySpec)
  loadchunk(head .. "\nlocal CVAR = {}\n" .. entry .. [==[

for name, data in pairs(CVAR) do
  ConVarTranslate[data[1]].Set( name, data[2], data[3], data[4], data[5], data[6] )
end
]==], "sh_convar.lua")()
end

loadCVar([==[^CVAR\["ph_min_waitforplayers"\]]==])
check("initial value reaches the global", GetGlobalInt("ph_min_waitforplayers", -1), 2)
RunConsoleCommand("ph_min_waitforplayers", "4")
check("set 4 -> global reads 4", GetGlobalInt("ph_min_waitforplayers", -1), 4)
RunConsoleCommand("ph_min_waitforplayers", "6")
check("set 6 -> global reads 6", GetGlobalInt("ph_min_waitforplayers", -1), 6)
RunConsoleCommand("ph_min_waitforplayers", "0")
check("rejected 0 does not land in the global", GetGlobalInt("ph_min_waitforplayers", -1) >= 1, true)

-- The other three custom-callback cvars must sync too.
loadCVar([==[^CVAR\["ph_prop_jumppower"\]]==])
S.players = {}
RunConsoleCommand("ph_prop_jumppower", "2.5")
check("ph_prop_jumppower syncs", GetGlobalFloat("ph_prop_jumppower", -1), 2.5)

loadCVar([==[^CVAR\["ph_hunter_jumppower"\]]==])
RunConsoleCommand("ph_hunter_jumppower", "1.5")
check("ph_hunter_jumppower syncs", GetGlobalFloat("ph_hunter_jumppower", -1), 1.5)

loadCVar([==[^CVAR\["ph_usable_prop_type"\]]==])
PHX.SetUsableEntity = function() end
RunConsoleCommand("ph_usable_prop_type", "3")
check("ph_usable_prop_type syncs", GetGlobalInt("ph_usable_prop_type", -1), 3)

print("\n== mv_cooldown must be honourable ==")
local f = loadchunk("local MapVote = ...\n"
  .. extract("gamemodes/prop_hunt/gamemode/mapvote/sv_mapvote.lua", "188-193")
  .. "\nreturn cooldown", "sv_mapvote.lua")
check("mv_cooldown 1 -> cooldown on", f{ PHXConfig = { EnableCooldown = true } }, true)
check("mv_cooldown 0 -> cooldown off", f{ PHXConfig = { EnableCooldown = false } }, false)
check("unset -> defaults on", f{ PHXConfig = {} }, true)

print("\n== RTV must read mv_rtvcount live, not at load ==")
PHX.MV = { PHXConfig = { RTVPlayerCount = 2, TimeLimit = 28, ChangeMapNoPlayer = true } }
PHX.StartMapVote = function() end
loadblocks("rtv.lua", extract("gamemodes/prop_hunt/gamemode/mapvote/rtv.lua", "1-999"))

-- Drive the real entry point rather than reaching into rtv.lua's local table.
local function rtv(count, others)
  PHX.MV.PHXConfig.RTVPlayerCount = count
  S.players = {}
  for i = 1, others do S.players[i] = S.Player{ name = "p" .. i, sid = "STEAM_0:0:" .. i } end
  local p = S.Player{ name = "voter", sid = "STEAM_0:0:99" }
  S.players[#S.players + 1] = p
  _G.CURTIME = 100000 + count      -- past RTV._ActualWait
  S.concommands["rtv_start"].fn(p)
  if p.RTVoted then return "allowed" end
  return p.chat[1] and p.chat[1][2] or "no message"
end
check("rtvcount 2, 3 players -> allowed", rtv(2, 2), "allowed")
check("rtvcount raised to 9 at runtime -> blocked", rtv(9, 2), "PHXM_MV_NEED_MORE_PLY")

report()
