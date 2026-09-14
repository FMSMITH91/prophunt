dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

print("\n== !unstuck must never error the server ==")
loadblocks("sv_enhancedplus.lua@Unstuck",
  extractAll("gamemodes/prop_hunt/gamemode/enhancedplus/sv_enhancedplus.lua", {
    [[^PHX\.UNSTUCK_COMMANDS = \{]],
    [[^hook\.Add\("PlayerSay", "PH_UnstuckCommand"]],
    [[^function GM:TeleportPlayerToClosestSpawnpoint]], [[^function GM:PosOnGround]],
    [[^function GM:UnstuckPlayer]], [[^function GM:TryNormalUnstuck]] }))

S.boolCVar("ph_use_unstuck", "1"); CreateConVar("ph_unstuck_waittime", "5")
CreateConVar("ph_unstuckrange", "250"); S.boolCVar("ph_disabletpunstuckinround", "0")
SetGlobalBool("InRound", true)

local function unstuck(opts)
  opts = opts or {}
  local p = S.Player{ team = opts.team or TEAM_PROPS, alive = (opts.alive ~= false),
                      onground = (opts.onground ~= false) }
  -- a living prop owns a ph_prop; a dead one does not (OnDeath nils it)
  if opts.alive ~= false and (opts.team or TEAM_PROPS) == TEAM_PROPS then
    p.ph_prop = { GetPropSize = function() return 16, 16, 32 end, __valid = true }
  end
  S.players = { p }
  local ok, err = pcall(function() S.fire("PlayerSay", p, "!unstuck") end)
  if not ok then return tostring(err) end
  local errs = S.pump(0.3)
  return errs[1]
end

check("living prop, grounded", unstuck{}, nil)
check("living prop, airborne", unstuck{ onground = false }, nil)
check("hunter (ignored by design)", unstuck{ team = TEAM_HUNTERS }, nil)
check("spectator", unstuck{ team = TEAM_SPECTATOR }, nil)
check("DEAD prop, grounded", unstuck{ alive = false }, nil)
check("DEAD prop, airborne", unstuck{ alive = false, onground = false }, nil)

print("\n== hunter loadout across the whole ph_hunter_blindlock_time range ==")
loadblocks("sh_player.lua@PHSetColor",
  "local Player = S.PlyMeta\n" ..
  extract("gamemodes/prop_hunt/gamemode/sh_player.lua", [[^function Player:PHSetColor]]))
S.boolCVar("ph_enable_hunter_player_color", "0")
loadblocks("class_hunter.lua", extract("gamemodes/prop_hunt/gamemode/player_class/class_hunter.lua", "1-999"))
local HUNTER = S.classes["Hunter"]
S.boolCVar("ph_give_grenade_near_roundend", "0"); CreateConVar("ph_smggrenadecounts", "1")
S.boolCVar("ph_enable_devil_balls", "0"); S.boolCVar("ph_use_custom_plmodel", "0")

local function armed(blindTime)
  SetGlobalBool("PHX.BlindStatus", true)      -- PostCleanupMap sets this before spawning
  SetGlobalInt("unBlind_Time", blindTime)
  local p = S.Player{ team = TEAM_HUNTERS, info = { cl_playercolor = "1 1 1" } }
  S.players = { p }
  HUNTER:OnSpawn(p)
  S.pump(blindTime + 2)
  return #p.weapons > 0
end
for _, t in ipairs{ 0, 1, 2, 3, 15, 30, 60 } do
  check(("blindlock %-2d -> hunter ends up armed"):format(t), armed(t), true)
end
SetGlobalBool("PHX.BlindStatus", false)
local p = S.Player{ team = TEAM_HUNTERS, info = { cl_playercolor = "1 1 1" } }
HUNTER:OnSpawn(p)
check("blind disabled -> armed immediately", #p.weapons > 0, true)

print("\n== prop spawn must survive the entity limit ==")
loadblocks("sh_player.lua@CreatePlayerPropEntity",
  "local Player = S.PlyMeta\n" ..
  extract("gamemodes/prop_hunt/gamemode/sh_player.lua", [[function Player:CreatePlayerPropEntity]]))
loadblocks("class_prop.lua", extract("gamemodes/prop_hunt/gamemode/player_class/class_prop.lua", "1-999"))
local PROP = S.classes["Prop"]
S.boolCVar("ph_use_custom_plmodel_for_prop", "0")

local function spawnProp(limitHit)
  S.entsCreateFails = limitHit
  local p = S.Player{ team = TEAM_PROPS }
  S.players = { p }
  local res = attempt(PROP.OnSpawn, PROP, p)
  S.entsCreateFails = false
  return res
end
check("normal spawn", spawnProp(false), "ok")
check("ents.Create fails at the limit", spawnProp(true), "ok")

print("\n== ph_check_update is staff-only on the server ==")
loadblocks("sh_httpupdates.lua",
  extractAll("gamemodes/prop_hunt/gamemode/sh_httpupdates.lua", {
    [[^local function UPDATE_DO_FETCH_BACKUP]], [[^local function UPDATE_DO_FETCH\(]],
    [[^function PHX:CheckUpdate]], [[^concommand\.Add\("ph_check_update"]] }))

local cmd = S.concommands["ph_check_update"]
local function fetches(ply, times)
  S.http.calls = {}
  for _ = 1, (times or 1) do pcall(cmd.fn, ply, "ph_check_update", {}, "") end
  return #S.http.calls
end
check("ordinary player -> refused", fetches(S.Player{ staff = false }), 0)
check("ordinary player, 25 presses -> refused", fetches(S.Player{ staff = false }, 25), 0)
check("staff -> allowed", fetches(S.Player{ staff = true }), 1)
check("server console -> allowed", fetches(NULL), 1)

report()
