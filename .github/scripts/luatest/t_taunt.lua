dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

print("\n== [F3] random taunt: ph_normal_taunt_delay must apply in every mode ==")
loadblocks("init.lua@PlayerButtonDown",
  extract("gamemodes/prop_hunt/gamemode/init.lua",
          [[^hook\.Add\("PlayerButtonDown", "PlayerButton_ControlTaunts"]]))

CreateConVar("ph_custom_taunt_mode", "2"); CreateConVar("ph_normal_taunt_delay", "4")
S.boolCVar("ph_use_unstuck", "0"); S.boolCVar("ph_taunt_pitch_enable", "0")
PHX.CachedTaunts[TEAM_PROPS]["A"] = "taunts/props/a.wav"
PHX.CachedTaunts[TEAM_HUNTERS]["H"] = "taunts/hunters/h.wav"
SetGlobalBool("InRound", true)

local F3 = 63
local function press(mode, lastTaunt, opts)
  opts = opts or {}
  S.cvars["ph_custom_taunt_mode"].v = tostring(mode)
  S.taunts = {}
  local p = S.Player{ team = opts.team or TEAM_PROPS, alive = (opts.alive ~= false),
                      info = { ph_default_taunt_key = F3 }, vars = { LastTauntTime = lastTaunt } }
  S.players = { p }
  S.fire("PlayerButtonDown", p, opts.key or F3)
  return #S.taunts, p
end

-- mode 2 is the default and must keep behaving exactly as it does today
check("mode 2, taunted 0.5s ago -> blocked", (press(2, 999.5)), 0)
check("mode 2, taunted 10s ago  -> taunts", (press(2, 990)), 1)
check("mode 2, never taunted    -> taunts", (press(2, 0)), 1)
-- mode 0 used to short-circuit the cooldown entirely (`and` binds before `or`)
check("mode 0, taunted 0.5s ago -> blocked", (press(0, 999.5)), 0)
check("mode 0, taunted 10s ago  -> taunts", (press(0, 990)), 1)
local n1, p1 = press(1, 990)
check("mode 1 -> no taunt", n1, 0)
check("mode 1 -> opens the menu", p1.concmds[1], "ph_showtaunts")
check("wrong key -> no taunt", (press(2, 0, { key = 99 })), 0)
check("dead player -> no taunt", (press(2, 0, { alive = false })), 0)
check("spectator -> no taunt", (press(2, 0, { team = TEAM_SPECTATOR })), 0)
check("hunter, cooldown clear -> taunts", (press(2, 990, { team = TEAM_HUNTERS })), 1)

print("\n== CL2SV_PlayThisTaunt: dead players must not taunt ==")
loadblocks("sv_tauntmgr.lua",
  extractAll("gamemodes/prop_hunt/gamemode/sv_tauntmgr.lua", {
    [[^local function IsDelayed]], [[^local function CheckValidity]],
    [[^local function SetLastTauntDelay]], [[^net\.Receive\("CL2SV_PlayThisTaunt"]] }))

CreateConVar("ph_customtaunts_delay", "4")
S.boolCVar("ph_randtaunt_map_prop_enable", "1"); CreateConVar("ph_randtaunt_map_prop_max", "6")
S.fileExists["sound/taunts/props/a.wav"] = true
S.fileExists["sound/taunts/hunters/h.wav"] = true

local function sendTaunt(opts)
  opts = opts or {}
  S.taunts = {}
  local tm = opts.team or TEAM_PROPS
  local p = S.Player{ team = tm, alive = (opts.alive ~= false), vars = { CLastTauntTime = opts.last or 0 } }
  local nm, pa = "A", "taunts/props/a.wav"
  if tm == TEAM_HUNTERS then nm, pa = "H", "taunts/hunters/h.wav" end
  S.net.readq = { nm, pa, opts.fake or false }
  local ok = pcall(S.receivers["CL2SV_PlayThisTaunt"], 0, p)
  if not ok then return -1 end
  return #S.taunts
end

check("living prop, cooldown clear -> taunts", sendTaunt{}, 1)
check("living prop, on cooldown    -> blocked", sendTaunt{ last = 999 }, 0)
check("living hunter               -> taunts", sendTaunt{ team = TEAM_HUNTERS }, 1)
check("DEAD prop                   -> blocked", sendTaunt{ alive = false }, 0)
check("DEAD hunter                 -> blocked", sendTaunt{ alive = false, team = TEAM_HUNTERS }, 0)
check("spectator                   -> blocked", sendTaunt{ team = TEAM_SPECTATOR }, 0)

print("\n== addon-facing taunt API ==")
AddResources = function() end
loadblocks("sh_config.lua@TauntAPI",
  extractAll("gamemodes/prop_hunt/gamemode/sh_config.lua", {
    [[^function PHX:AddCustomTaunt]], [[^function PHX:AddSingleTaunt]],
    [[^function PHX:RemoveTauntByPath]] }))

PHX.TAUNTS = {}; PHX.CachedTaunts[TEAM_PROPS] = {}
check("AddCustomTaunt, new category", attempt(PHX.AddCustomTaunt, PHX, TEAM_PROPS, "Cat", { T = "a.wav" }), "ok")
check("  ... actually stored", PHX.TAUNTS["Cat"] and PHX.TAUNTS["Cat"][TEAM_PROPS]["T"], "a.wav")
check("AddCustomTaunt refuses to clobber",
      attempt(PHX.AddCustomTaunt, PHX, TEAM_PROPS, "Cat", { T2 = "c.wav" }) == "ok"
      and PHX.TAUNTS["Cat"][TEAM_PROPS]["T"] == "a.wav", true)
check("AddSingleTaunt, new category", attempt(PHX.AddSingleTaunt, PHX, TEAM_PROPS, "Cat2", "Solo", "b.wav"), "ok")
check("  ... actually stored", PHX.TAUNTS["Cat2"][TEAM_PROPS]["Solo"], "b.wav")
check("  ... cache updated", PHX.CachedTaunts[TEAM_PROPS]["Solo"], "b.wav")
check("AddSingleTaunt, duplicate is a no-op",
      attempt(PHX.AddSingleTaunt, PHX, TEAM_PROPS, "Cat2", "Solo", "b.wav"), "ok")
PHX.TAUNTS["Has"] = { [TEAM_PROPS] = { "a.wav" } }
check("RemoveTauntByPath", attempt(PHX.RemoveTauntByPath, PHX, TEAM_PROPS, "Has", "a.wav"), "ok")
check("RemoveTauntByPath, unknown category", attempt(PHX.RemoveTauntByPath, PHX, TEAM_PROPS, "Nope", "a.wav"), "ok")
-- the guards must actually reject
PHX.TAUNTS = {}
PHX:AddCustomTaunt(999, "Bad", { T = "a.wav" })
check("AddCustomTaunt rejects a bad team id", PHX.TAUNTS["Bad"], nil)
PHX:AddCustomTaunt(TEAM_PROPS, "Empty", {})
check("AddCustomTaunt rejects an empty table", PHX.TAUNTS["Empty"], nil)
PHX:AddSingleTaunt(TEAM_PROPS, "NoPath", "N", nil)
check("AddSingleTaunt rejects a nil path", PHX.TAUNTS["NoPath"], nil)

report()
