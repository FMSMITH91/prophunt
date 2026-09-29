dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- Server-side taunt rules, run as shipped: auto-taunt with an empty props list,
-- and CL2SV_PlayThisTaunt enforcing what only the client used to (custom taunt
-- mode, the [F3] cooldown, round state), checking the cheap things before the
-- filesystem, and rate-limiting requests that fail.

local TM = "gamemodes/prop_hunt/gamemode/sv_tauntmgr.lua"

-- AutoTauntThink uses GLua's `continue`; express it as a goto for stock Lua.
local auto = extractAll(TM, { [[^local function TauntTimeLeft]], [[^local function AutoTauntThink]] })
local n1, n2
auto, n1 = auto:gsub("continue;", "goto continue_", 1)
auto, n2 = auto:gsub("(\n\t\tend\n)", "\n::continue_::%1", 1)
assert(n1 == 1 and n2 == 1, "AutoTauntThink no longer has the shape this test rewrites")
loadblocks("sv_tauntmgr.lua@auto", auto .. "\n_G.AutoTauntThink = AutoTauntThink")

loadblocks("sv_tauntmgr.lua@net", extractAll(TM, {
  [[^local function IsDelayed]], [[^local function CheckValidity]],
  [[^local function SetLastTauntDelay]], [[^net\.Receive\("CL2SV_PlayThisTaunt"]] }))

S.boolCVar("ph_autotaunt_enabled", "1"); CreateConVar("ph_autotaunt_delay", "45")
CreateConVar("ph_custom_taunt_mode", "2"); CreateConVar("ph_normal_taunt_delay", "4")
CreateConVar("ph_customtaunts_delay", "4"); S.boolCVar("ph_taunt_pitch_enable", "0")
S.boolCVar("ph_randtaunt_map_prop_enable", "1"); CreateConVar("ph_randtaunt_map_prop_max", "6")
SetGlobalBool("InRound", true)
local PROPTAUNT = "taunts/props/a.wav"

local function isCheer(s) return type(s) == "string" and s:match("^vo/coast/odessa/male01/nlo_cheer0%d%.wav$") ~= nil end

print("\n== auto-taunt ==")
local function autoTaunt(propTaunts, fallback)
  PHX.CachedTaunts = { [TEAM_HUNTERS] = { H = "taunts/hunters/h.wav" }, [TEAM_PROPS] = propTaunts }
  TAUNT_FALLBACK = fallback
  S.taunts = {}
  local p = S.Player{ team = TEAM_PROPS, vars = { LastTauntTime = 0 } }
  S.players = { p }
  AutoTauntThink()
  return S.taunts[1] and S.taunts[1][2]
end
check("props list empty, hunters not: plays the cheer", isCheer(autoTaunt({}, nil)), true)
check("props list empty, hunters not: never the sound 'nil'", autoTaunt({}, nil) ~= "nil", true)
check("props have taunts: plays one of them", autoTaunt({ A = PROPTAUNT }, nil), PROPTAUNT)
check("TAUNT_FALLBACK: plays the cheer", isCheer(autoTaunt({}, true)), true)
TAUNT_FALLBACK = nil
PHX.CachedTaunts = { [TEAM_HUNTERS] = { H = "taunts/hunters/h.wav" }, [TEAM_PROPS] = { A = PROPTAUNT } }

print("\n== CL2SV_PlayThisTaunt ==")
local fsLookups = 0
S.fileExists["sound/" .. PROPTAUNT] = true
file.Exists = function(f) fsLookups = fsLookups + 1; return S.fileExists[f] == true end
local decoy = { __valid = true, sounds = {} }
function decoy:EmitSound(s) table.insert(self.sounds, s) end
S.entsByClass["prop_physics"] = { decoy }

local function req(opts)
  opts = opts or {}
  S.cvars["ph_custom_taunt_mode"].v = tostring(opts.mode or 2)
  SetGlobalBool("InRound", opts.inRound ~= false)
  TAUNT_FALLBACK = opts.fallback
  S.taunts, decoy.sounds, fsLookups = {}, {}, 0
  local p = opts.ply or S.Player{ team = TEAM_PROPS, vars = { LastTauntTime = opts.lastF3 or 0, CLastTauntTime = 0 } }
  p.chat = {}
  S.net.readq = { opts.name or "A", opts.snd or PROPTAUNT, opts.fake or false }
  local ok, err = pcall(S.receivers["CL2SV_PlayThisTaunt"], 0, p)
  if not ok then return "ERROR " .. tostring(err), p end
  return #S.taunts + #decoy.sounds, p
end

-- the paths that must keep working
check("mode 2, in round, cooldowns clear: plays", (req{}), 1)
check("mode 1 (menu only): plays", (req{ mode = 1 }), 1)
check("mode 2, fake taunt: plays from a map prop", (req{ fake = true }), 1)
check("[F3] 10s ago: plays", (req{ lastF3 = 990 }), 1)
check("empty taunt list (C in any mode): the cheer still plays", (req{ mode = 0, fallback = true, name = "___fail", snd = "___fail" }), 1)
TAUNT_FALLBACK = nil

-- what only the client enforced before
check("mode 0: a crafted custom taunt is refused", (req{ mode = 0 }), 0)
check("mode 0: a crafted fake taunt is refused", (req{ mode = 0, fake = true }), 0)
check("[F3] 1s ago: refused (ph_normal_taunt_delay)", (req{ lastF3 = 999 }), 0)
check("round over: refused", (req{ inRound = false }), 0)

print("\n== cheap checks first, and failures are rate-limited ==")
local n, p = req{ name = "nope", snd = "../../cfg/server.cfg" }
check("unknown taunt: refused", n, 0)
check("unknown taunt: no filesystem lookup", fsLookups, 0)
check("unknown taunt: player told", p.chat[1] and p.chat[1][2], "TM_DELAYTAUNT_NOT_EXIST")
n = req{ name = "A", snd = "taunts/props/not_in_cache.wav" }
check("known name, path not in the cache: no filesystem lookup", fsLookups, 0)
req{}
check("a valid taunt still checks the file exists", fsLookups, 1)
S.fileExists["sound/" .. PROPTAUNT] = false
check("valid entry but the file is gone: refused", (req{}), 0)
S.fileExists["sound/" .. PROPTAUNT] = true

local spam = S.Player{ team = TEAM_PROPS, vars = { LastTauntTime = 0, CLastTauntTime = 0 } }
req{ ply = spam, name = "nope" }
local _, p2 = req{ ply = spam, name = "nope" }
check("second bad request in the same instant: dropped silently", #p2.chat, 0)
_G.CURTIME = _G.CURTIME + 0.3
_, p2 = req{ ply = spam, name = "nope" }
check("after 0.3s: handled again", #p2.chat, 1)
_G.CURTIME = _G.CURTIME + 0.3
check("after 0.3s: a good request plays", (req{ ply = spam }), 1)

report()
