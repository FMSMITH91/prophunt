dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- Prop disguises and damage, voice/chat rules and spawn settings, run as shipped:
-- PlayerExchangeProp with the real hull and health code and the real sv_bbox
-- config, the damage hooks with the real ph_prop:OnTakeDamage, the voice/chat
-- rules, the HLA combine list across a map load, jump power through the real
-- PH_PlayerSpawn -> meta:OnSpawn order, and GM:Think's BaseClass chain.

local INIT = "gamemodes/prop_hunt/gamemode/init.lua"
local ROOT = (debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "../../../"
SOLID_VPHYSICS, SOLID_BBOX = 6, 2
RENDERMODE_TRANSALPHA, COLLISION_GROUP_PASSABLE_DOOR = 4, 15
OBS_MODE_IN_EYE, OBS_MODE_ROAMING = 4, 6
function isentity(v) return type(v) == "table" end
util.PrecacheModel = function() end

local PM = S.PlyMeta
for _, m in ipairs{ "SetRenderMode", "ResetHull", "SetCollisionGroup", "CollisionRulesChanged",
                    "SetDuckSpeed", "SetRunSpeed", "SetCrouchedWalkSpeed", "AllowFlashlight",
                    "SetMaxHealth", "SetRespawnTime", "ShouldDropWeapon", "SetNoCollideWithTeammates",
                    "SetAllowFullRotation", "SetHullDuck", "SetModel" } do
  PM[m] = function() end
end
function PM:SetHull(mn, mx) self._hull = { mn, mx } end
function PM:SetJumpPower(v) self._jump = v end
function PM:GetObserverMode() return self._obs or 0 end
function PM:GetClass() return "player" end
function PM:GetPlayerClass() return S.classes and S.classes[self._team == TEAM_HUNTERS and "Hunter" or "Prop"] end
local classThinks = 0
function PM:CallClassFunction(name) if name == "Think" then classThinks = classThinks + 1 end end

-- The real ph_prop damage handler; a disguise entity that forwards to it.
ENT = {}
loadblocks("ph_prop.lua@OnTakeDamage",
  extract("gamemodes/prop_hunt/entities/entities/ph_prop.lua", [[^\s*function ENT:OnTakeDamage]]))
local PHPROP = ENT
local function mkProp(owner, hp, maxhp, mdl)
  local p = { __valid = true, health = hp, max_health = maxhp, _mdl = mdl or "models/props_c17/oildrum001.mdl", _skin = 0 }
  function p:GetModel() return self._mdl end
  function p:SetModel(m) self._mdl = m end
  function p:GetSkin() return self._skin end
  function p:SetSkin(s) self._skin = s end
  function p:SetSolid(s) self._solid = s end
  function p:SetPos() end
  function p:SetAngles() end
  function p:SetColor() end
  function p:GetOwner() return owner end
  function p:TakeDamageInfo(d) PHPROP.OnTakeDamage(self, d) end
  return p
end
local function mkEnt(t)
  local e = { __valid = true, _cls = t.cls or "prop_physics", _mdl = t.mdl, _vol = t.vol or 25000,
              _min = t.min or Vector(-10, -10, -10), _max = t.max or Vector(10, 10, 10), _nw = {} }
  function e:GetClass() return self._cls end
  function e:GetModel() return self._mdl end
  function e:GetSkin() return 0 end
  function e:GetPhysicsObject() return { __valid = true, GetVolume = function() return e._vol end } end
  function e:OBBMaxs() return self._max end
  function e:OBBMins() return self._min end
  function e:GetModelBounds() return self._min, self._max end
  function e:GetNWBool(k, d) local v = self._nw[k]; if v == nil then return d end return v end
  function e:SetNWBool(k, v) self._nw[k] = v end
  function e:GetColor() return color_white end
  function e:EntIndex() return 99 end
  return e
end
local function prop(hp, maxhp)
  local pl = S.Player{ team = TEAM_PROPS }
  pl._hp = hp
  pl.ph_prop = mkProp(pl, hp, maxhp or 100)
  return pl
end
local function dmg(attacker, amount)
  return { GetAttacker = function() return attacker end, GetInflictor = function() return attacker end,
           GetDamage = function() return amount end, GetDamageType = function() return 0 end }
end

local sh_player = "gamemodes/prop_hunt/gamemode/sh_player.lua"
loadblocks("sh_player.lua@hull", "local Player = S.PlyMeta\n" .. extractAll(sh_player, {
  [[^\s*function Player:PHSendHullInfo]], [[^\s*function Player:PHSendHullBounds]],
  [[^\s*function Player:PHAdjustView]] }))

-- The damage hook with the local helpers above it: from its header comment to
-- its hook.Add (t_server_damage.lua covers every branch of it).
local function lineRange(path, from, to)
  local a, b, n = nil, nil, 0
  for line in io.lines(ROOT .. path) do
    n = n + 1
    if not a and line:match(from) then a = n end
    if a and not b and line:match(to) then b = n end
  end
  assert(a and b, "range not found in " .. path)
  return a .. "-" .. b
end
loadblocks("init.lua@props", extractAll(INIT, {
  [[^local hunterdamagefix]],
  lineRange(INIT, "^%-%- Called when an entity takes damage", '^hook%.Add%("EntityTakeDamage", "PH_EntityTakeDamage"'),
  [[^hook\.Add\("PostEntityTakeDamage", "PHX\.SyncPropHealth"]],
  [[^function GM:PlayerShouldTakeDamage]], [[^function GM:PlayerExchangeProp]],
  [[^function GM:PlayerCanHearPlayersVoice]], [[^function GM:PlayerCanSeePlayersChat]],
  [[^hook\.Add\("PlayerSpawn", "PH_PlayerSpawn"]], [[^function GM:Think]] }))

S.boolCVar("ph_banned_models", "1")
S.boolCVar("ph_prop_must_standing", "1")
S.boolCVar("ph_tmp_accurate_hull", "1")
S.boolCVar("ph_sv_enable_obb_modifier", "1")
S.boolCVar("ph_allow_armor", "1")
CreateConVar("ph_prop_viewoffset_mult", "0.8")
CreateConVar("ph_hunter_fire_penalty", "5")
CreateConVar("sv_alltalk", "0")
PHX.BANNED_PROP_MODELS = { "models/banned.mdl" }
function PHX:IsUsablePropEntity(c) return c == "prop_physics" or c == "prop_ragdoll" end
GAMEMODE.ViewCam = { cHullzMins = 8, cHullzMaxs = 84 }
GAMEMODE.NoPlayerPlayerDamage, GAMEMODE.NoNonPlayerPlayerDamage, GAMEMODE.NoPlayerTeamDamage = true, true, true
local changes = 0
hook.Add("PH_OnChangeProp", "test", function() changes = changes + 1 end)
local function lastHullMsg() local m = S.net.sent[#S.net.sent]; return m and m.name == "SetHull" and m or nil end
local function v(x) return tostring(x) end

print("\n== ragdoll disguise keeps the health ratio ==")
local rag = mkEnt{ cls = "prop_ragdoll", mdl = "models/humans/charple01.mdl", vol = 5000,
                   min = Vector(-12, -12, 0), max = Vector(12, 12, 60) }
local pl = prop(50)
GAMEMODE:PlayerExchangeProp(pl, rag)
check("hurt prop (50/100) -> ragdoll: health", pl:Health(), 50)
check("hurt prop -> ragdoll: ph_prop.health", pl.ph_prop.health, 50)
check("hurt prop -> ragdoll: ph_prop.max_health", pl.ph_prop.max_health, 100)
check("hurt prop -> ragdoll: client told the same health", lastHullMsg().data[3], 50)
GAMEMODE:PlayerExchangeProp(pl, mkEnt{ mdl = "models/crate.mdl", vol = 25000 })
check("then a 100hp crate: still half health (no heal)", pl:Health(), 50)
pl = prop(100)
GAMEMODE:PlayerExchangeProp(pl, rag)
check("full prop -> ragdoll: 100 as before", pl:Health(), 100)
check("full prop -> ragdoll: client told 100", lastHullMsg().data[3], 100)
pl = prop(1)
GAMEMODE:PlayerExchangeProp(pl, rag)
check("1hp prop -> ragdoll: at least 1", pl:Health(), 1)

print("\n== normal disguise: ratio, hull and client hull unchanged ==")
changes = 0
pl = prop(50)
local crate = mkEnt{ mdl = "models/crate.mdl", vol = 50000, min = Vector(-20, -16, -5), max = Vector(20, 16, 35) }
GAMEMODE:PlayerExchangeProp(pl, crate)
check("50/100 -> 200hp crate: health 100", pl:Health(), 100)
check("server hull min", v(pl._hull[1]), v(Vector(-20, -20, 0)))
check("server hull max (z = 40 * 0.8)", v(pl._hull[2]), v(Vector(20, 20, 32)))
check("client hull min matches", v(lastHullMsg().data[1]), v(pl._hull[1]))
check("client hull max matches", v(lastHullMsg().data[2]), v(pl._hull[2]))
check("PH_OnChangeProp fired for a real change", changes, 1)

print("\n== PH_OnChangeProp only on a real change ==")
changes = 0
pl = prop(100)
GAMEMODE:PlayerExchangeProp(pl, mkEnt{ mdl = "models/banned.mdl" })
check("banned model: player told", #pl.chat, 1)
check("banned model: no PH_OnChangeProp", changes, 0)
pl.ph_prop:SetModel("models/crate.mdl")
GAMEMODE:PlayerExchangeProp(pl, mkEnt{ mdl = "models/crate.mdl" })
check("same model: no PH_OnChangeProp", changes, 0)

print("\n== missing ph_prop / dead prop don't error ==")
pl = prop(100); pl.ph_prop = nil
check("no ph_prop (entity limit): exchange", attempt(GAMEMODE.PlayerExchangeProp, GAMEMODE, pl, crate), "ok")
pl = prop(100); pl.ph_prop = NULL
check("NULL ph_prop (map cleanup): exchange", attempt(GAMEMODE.PlayerExchangeProp, GAMEMODE, pl, crate), "ok")
pl = prop(100); pl._alive = false
GAMEMODE:PlayerExchangeProp(pl, crate)
check("dead prop: disguise untouched", pl.ph_prop:GetModel(), "models/props_c17/oildrum001.mdl")
local hunter = S.Player{ team = TEAM_HUNTERS, name = "h" }
pl = prop(100); pl.ph_prop = NULL
check("NULL ph_prop: hunter hit", attempt(S.fire, "EntityTakeDamage", pl, dmg(hunter, 20)), "ok")

-- The engine's order for damage to a player: EntityTakeDamage hooks, then
-- PlayerShouldTakeDamage decides whether the player's own HP drops, then
-- PostEntityTakeDamage with whether it did.
local WORLD = { __valid = false }
local function hurt(ent, d)
  if S.fire("EntityTakeDamage", ent, d) then return end
  local took = GAMEMODE:PlayerShouldTakeDamage(ent, d:GetAttacker()) and true or false
  if took then ent:SetHealth(ent:Health() - d:GetDamage()) end
  S.fire("PostEntityTakeDamage", ent, d, took)
end

print("\n== fall damage sticks to a prop ==")
pl = prop(100)
hurt(pl, dmg(WORLD, 10))
check("fall 10: player HP", pl:Health(), 90)
check("fall 10: ph_prop.health follows", pl.ph_prop.health, 90)
hurt(pl, dmg(hunter, 20))
check("then a hunter hits for 20: 70, not 80", pl:Health(), 70)
pl = prop(100)
hurt(pl, dmg(WORLD, 10))
GAMEMODE:PlayerExchangeProp(pl, mkEnt{ mdl = "models/crate.mdl", vol = 25000 })
check("fall 10, then a disguise change: 90, not healed", pl:Health(), 90)
pl = prop(100)
hurt(pl, dmg(hunter, 25))
check("hunter hit alone: 75 (unchanged path)", pl:Health(), 75)
check("hunter hit alone: ph_prop.health 75", pl.ph_prop.health, 75)
local mate = S.Player{ team = TEAM_PROPS, name = "mate" }
hurt(pl, dmg(mate, 25))
check("friendly prop hit: nothing", pl:Health(), 75)

print("\n== custom OBB hulls (sv_bbox) ==")
local BOARD = "models/props_debris/wood_board05a.mdl"
S.fileExists["phx_data/obb/ph_test.txt"] = true
file.Read = function() return "obb" end
S.json = { obb = { { "Models/Props_Debris/Wood_Board05a.mdl", { min = { -1.3, -4.3, 0 }, max = { 1.3, 4.3, 96 } } } } }
local mapBoard = mkEnt{ mdl = BOARD, min = Vector(-1.28, -8.28, -64.28), max = Vector(1.28, 8.28, 64.28) }
ents.FindByModel = function(m) return m:lower() == BOARD and { mapBoard } or {} end
loadblocks("sv_bbox.lua", extract("gamemodes/prop_hunt/gamemode/sv_bbox.lua", "1-999"))
S.concommands["refresh_obb_map_setting"].fn(NULL)
check("map board got the per-entity hull", mapBoard:GetNWBool("hasCustomHull", false), true)

pl = prop(100)
GAMEMODE:PlayerExchangeProp(pl, mapBoard)
check("E on the map board: server hull min", v(pl._hull[1]), v(Vector(-1.3, -4.3, 0)))
check("E on the map board: only Z scaled", v(pl._hull[2]), v(Vector(1.3, 4.3, 96 * 0.8)))
check("E on the map board: client gets the same min", v(lastHullMsg().data[1]), v(pl._hull[1]))
check("E on the map board: client gets the same max", v(lastHullMsg().data[2]), v(pl._hull[2]))

pl = prop(100)
local menuBoard = mkEnt{ mdl = BOARD, min = mapBoard._min, max = mapBoard._max }   -- ents.Create'd by the prop menu
GAMEMODE:PlayerExchangeProp(pl, menuBoard)
check("prop-menu board: custom hull max too", v(pl._hull[2]), v(Vector(1.3, 4.3, 96 * 0.8)))

S.json.obb = {}
S.concommands["refresh_obb_map_setting"].fn(NULL)
pl = prop(100)
GAMEMODE:PlayerExchangeProp(pl, mkEnt{ mdl = BOARD, min = mapBoard._min, max = mapBoard._max })
check("model dropped from the config: back to the OBB hull", v(pl._hull[2]), v(Vector(8.28, 8.28, 128.56 * 0.8)))

print("\n== voice and chat ==")
local function P(t, alive) return S.Player{ team = t, alive = alive } end
local liveH, deadH, liveP, spec = P(TEAM_HUNTERS, true), P(TEAM_HUNTERS, false), P(TEAM_PROPS, true), P(TEAM_SPECTATOR, true)
local function hear(l, s) return (GAMEMODE:PlayerCanHearPlayersVoice(l, s)) end
local function see(l, s) return (GAMEMODE:PlayerCanSeePlayersChat("hi", false, l, s)) end
PHX.VOICE_IS_END_ROUND = 0
check("mid-round: living hunter can't hear a spectator", hear(liveH, spec), false)
check("mid-round: living hunter can't read a spectator", see(liveH, spec), false)
check("mid-round: dead hunter hears a spectator", hear(deadH, spec), true)
check("mid-round: dead hunter reads a spectator", see(deadH, spec), true)
check("mid-round: living players hear each other", hear(liveH, liveP), true)
check("mid-round: living players read each other", see(liveH, liveP), true)
check("mid-round: living can't hear the dead", hear(liveH, deadH), false)
check("mid-round: dead hear the living", hear(deadH, liveP), true)
check("mid-round: spectator hears nobody alive", hear(spec, liveH), false)
PHX.VOICE_IS_END_ROUND = 1
check("round over: living hunter hears a spectator", hear(liveH, spec), true)
check("round over: living hunter reads a spectator", see(liveH, spec), true)
PHX.VOICE_IS_END_ROUND = 0
check("console say reaches players (alltalk 0)", see(liveH, NULL), true)
check("console say_team: still hidden", (GAMEMODE:PlayerCanSeePlayersChat("hi", true, liveH, NULL)), false)
check("NULL listener: false", see(NULL, liveH), false)

print("\n== jump power follows the cvars on every spawn ==")
loadblocks("class_hunter.lua", extract("gamemodes/prop_hunt/gamemode/player_class/class_hunter.lua", "1-999"))
loadblocks("class_prop.lua", extract("gamemodes/prop_hunt/gamemode/player_class/class_prop.lua", "1-999"))
loadblocks("player_extension.lua@OnSpawn", "local meta = S.PlyMeta\n" ..
  extract("gamemodes/base_phx/gamemode/player_extension.lua", [[^function meta:OnSpawn]]))
CreateConVar("ph_hunter_jumppower", "1"); CreateConVar("ph_prop_jumppower", "1.5")
local function spawn(p) S.fire("PlayerSpawn", p); p:OnSpawn(); return p._jump end   -- hooks, then GM:PlayerSpawn
local jh, jp = S.Player{ team = TEAM_HUNTERS }, S.Player{ team = TEAM_PROPS }
check("defaults: hunter jump stays 200", spawn(jh), 200)
check("defaults: prop jump stays 300", spawn(jp), 300)
S.cvars.ph_hunter_jumppower.v = "2"; S.cvars.ph_prop_jumppower.v = "1"
check("ph_hunter_jumppower 2: hunter 400 after respawn", spawn(jh), 400)
check("ph_prop_jumppower 1: prop 200 after respawn", spawn(jp), 200)

print("\n== HLA combine models: the cvar is honoured ==")
-- The map-load timeline: sh_convar has just set the replicated global to the
-- default (true) while the ConVar holds the admin's 0; PHX:GetCVar reads the
-- global and PHX:QCVar the ConVar, as in sh_convar. The global is synced later.
local HLA = "models/hlvr/characters/combine/grunt/combine_grunt_hlvr_player.mdl"
S.fileExists[HLA] = true
player_manager.TranslateToPlayerModelName = function(m) return m == HLA and "hla_grunt" or "kleiner" end
local seen
local function mapLoad(adminValue)
  S.boolCVar("ph_add_hla_combine", adminValue)
  S.boolCVar("ph_use_custom_plmodel", "0")
  local getCVar = PHX.GetCVar
  function PHX:GetCVar(n) if n == "ph_add_hla_combine" then return S.globals[n] end return getCVar(self, n) end
  function PHX:QCVar(n) return getCVar(self, n) end
  S.globals.ph_add_hla_combine = true                       -- SetGlobalBool(name, default) at load
  -- From the HLA comment to the end of GM:PlayerSetModel, found by pattern.
  local a, b, i = nil, nil, 0
  for line in io.lines(ROOT .. INIT) do
    i = i + 1
    if not a and line:match("^%-%- Check if HLA Playermodels exists") then a = i end
    if a and not b and line:match("^function GM:PlayerSetModel") then b = -1 end
    if b == -1 and line:match("^end") then b = i end
  end
  loadblocks("init.lua@HLA", extractAll(INIT, { [[^local playerModels]], [[^local HLAModels]], a .. "-" .. b }))
  S.globals.ph_add_hla_combine = S.cvars.ph_add_hla_combine.v == "1"   -- PHX:InitCVar on first join
  local random = table.Random
  table.Random = function(t) seen = t; return t[1] end
  GAMEMODE:PlayerSetModel(S.Player{ team = TEAM_HUNTERS })
  table.Random = random
  PHX.GetCVar = getCVar
  return table.HasValue(seen, "hla_grunt"), #seen
end
local has, n = mapLoad("0")
check("ph_add_hla_combine 0: no HLA models", has, false)
check("ph_add_hla_combine 0: the 4 stock models", n, 4)
has, n = mapLoad("1")
check("ph_add_hla_combine 1: HLA model added", has, true)
check("ph_add_hla_combine 1: added once", n, 5)
GAMEMODE:PlayerSetModel(S.Player{ team = TEAM_HUNTERS })
check("a second spawn doesn't add it again", #seen, 5)

print("\n== GM:Think ==")
local calls = { base = 0, basephx = 0, endgame = 0, obs = 0 }
local BASE = { Think = function() calls.base = calls.base + 1 end }
local BASEPHX = { BaseClass = BASE }
function BASEPHX:Think() calls.basephx = calls.basephx + 1; self.BaseClass:Think() end
GAMEMODE.BaseClass = BASEPHX
GAMEMODE.IsEndOfGame, GAMEMODE.RoundBased = false, false
GAMEMODE.GetTimeLimit = function() return 0 end
function GAMEMODE:EndOfGame() calls.endgame = calls.endgame + 1 end
PHX.SPECTATOR_CHECK, PHX.SPECTATOR_CHECK_ADD = 0, 0.1
hook.Add("ChangeObserverMode", "test", function(p, mode) if mode == OBS_MODE_ROAMING then calls.obs = calls.obs + 1 end end)
local deadProp = S.Player{ team = TEAM_PROPS, alive = false }; deadProp._obs = OBS_MODE_IN_EYE
S.players = { deadProp, S.Player{ team = TEAM_HUNTERS } }
classThinks = 0
GAMEMODE:Think()
check("one tick: base_phx Think body runs once", calls.basephx, 1)
check("one tick: base Think runs once", calls.base, 1)
check("prop_hunt adds no class Think calls of its own", classThinks, 0)
check("prop_hunt adds no second end-of-game check", calls.endgame, 0)
check("dead prop in-eye is moved to roaming", calls.obs, 1)

print("\n== no accidental globals ==")
check("EntityTakeDamage is not a global", rawget(_G, "EntityTakeDamage"), nil)
loadblocks("init.lua@forced", extract(INIT, [[^(local )?IS_ROUND_FORCED_END]]))
check("IS_ROUND_FORCED_END is not a global", rawget(_G, "IS_ROUND_FORCED_END"), nil)

report()
