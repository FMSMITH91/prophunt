dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- Scripted entities under entities/entities, run from the shipped files: the anti-exploit
-- player clip, the decoy spawner and decoy, the Devil Crystal and Lucky Ball, the map's
-- model-ban entity, the prop entity's damage handler and the team item spawner.
local ENTS = "gamemodes/prop_hunt/entities/entities/"
local GMDIR = "gamemodes/prop_hunt/gamemode/"

-- Engine pieces shim.lua leaves out (kept here: shim.lua is shared with other branches).
function isfunction(v) return type(v) == "function" end
SOLID_BBOX, SOLID_VPHYSICS, MOVETYPE_NONE, MOVETYPE_VPHYSICS = 2, 6, 0, 6
COLLISION_GROUP_NONE, SIMPLE_USE, RENDERGROUP_BOTH, TRANSMIT_ALWAYS = 0, 3, 7, 0
HUD_PRINTCONSOLE, OBS_MODE_FREEZECAM, OBS_MODE_CHASE, DMG_CRUSH = 2, 2, 5, 1
function AddCSLuaFile() end
function include() end
function DEFINE_BASECLASS() end
function Model(m) return m end
function Sound(s) return s end
function AngleRand() return Angle(0, 45, 0) end
function EffectData() return setmetatable({}, { __index = function() return function() end end }) end
S.effects, S.precached = {}, {}
util.Effect = function(name) S.effects[#S.effects + 1] = name end
util.PrecacheModel = function(m) S.precached[#S.precached + 1] = m end
util.ColorToVector = function() return Vector(1, 1, 1) end
table.Shuffle = function() end
S.msgc = {}
function MsgC(_, s) S.msgc[#S.msgc + 1] = s end
-- GMod's Vector(v) copies a vector; the shim's Vector only takes numbers.
local ShimVector = Vector
function Vector(x, y, z)
  if type(x) == "table" then return ShimVector(x.x, x.y, x.z) end
  return ShimVector(x, y, z)
end
-- OrderVectors swaps components in place so that every axis of b >= a (engine C function).
function OrderVectors(a, b)
  for _, k in ipairs{ "x", "y", "z" } do if a[k] > b[k] then a[k], b[k] = b[k], a[k] end end
end
function S.PlyMeta:GetMaxHealth() return self._maxhp or 100 end

-- The real cvar layer, and the real definitions (defaults, types) of every cvar used here.
loadblocks("sh_convar.lua@cvars",
  extract(GMDIR .. "sh_convar.lua", "1-10") .. "\n"
  .. extract(GMDIR .. "sh_convar.lua", [[^local ConVarTranslate = \{]]) .. "\nlocal CVAR = {}\n"
  .. extractAll(GMDIR .. "sh_convar.lua", { [[^function PHX:AddCVar]], [[^function PHX:GetCVar]], [[^function PHX:QCVar]] }))
do
  local specs = {}
  for _, n in ipairs{ "ph_allow_armor", "ph_freezecam", "ph_hunter_kill_bonus", "ph_decoy_health" } do
    specs[#specs + 1] = ([=[^CVAR\["%s"\]]=]):format(n)
  end
  loadblocks("sh_convar.lua@defs", "local CVAR = {}\n" .. extractAll(GMDIR .. "sh_convar.lua", specs)
    .. "\nfor n, d in pairs(CVAR) do PHX:AddCVar(d[1], n, d[2], d[3], d[4], d[5]) end")
end
check("cvar layer: ph_allow_armor defaults on (real bool)", PHX:GetCVar("ph_allow_armor"), true)
check("cvar layer: ph_hunter_kill_bonus defaults to 25", PHX:GetCVar("ph_hunter_kill_bonus"), 25)

-- Entities. An instance reads its scripted ENT table first, then these engine methods.
-- Remove() only flags the entity, as in Source: it stays valid until the end of the frame.
local EntMeta = {}
function EntMeta:GetClass() return self._cls end
function EntMeta:GetModel() return self._mdl end
function EntMeta:SetModel(m) self._mdl = m end
function EntMeta:GetPos() return self._pos end
function EntMeta:SetPos(v) self._pos = v end
function EntMeta:GetAngles() return self._ang or Angle(0, 0, 0) end
function EntMeta:SetAngles(a) self._ang = a end
function EntMeta:Health() return self._hp or 0 end
function EntMeta:SetHealth(v) self._hp = v end
function EntMeta:GetOwner() return self._owner or NULL end
function EntMeta:SetOwner(o) self._owner = o end
function EntMeta:EntIndex() return self._idx or 1 end
function EntMeta:IsPlayer() return false end
function EntMeta:EmitSound(s) self._emitted[#self._emitted + 1] = s end
function EntMeta:Remove() self._removed = true end
function EntMeta:IsMarkedForDeletion() return self._removed == true end
function EntMeta:OBBMins() return Vector(-10, -10, -5) end
function EntMeta:GetCollisionBounds() return self._cbMins or Vector(-1, -1, -1), self._cbMaxs or Vector(1, 1, 1) end
function EntMeta:SetCollisionBounds(mn, mx) self._cbMins, self._cbMaxs = mn, mx end
function EntMeta:HasSpawnFlags(f) return self._flags ~= nil and self._flags[f] == true end
function EntMeta:Spawn() local m = getmetatable(self).ENT; if m and m.Initialize then self:Initialize() end end
function EntMeta:PhysicsInit(s) self._physinit = (self._physinit or 0) + 1; self._solid = s end
function EntMeta:SetSolid(s) self._solid = s end
for _, m in ipairs{ "Activate", "DrawShadow", "SetNoDraw", "SetCollisionGroup", "SetMoveType", "SetTrigger",
                    "SetUseType", "SetKeyValue", "SetParent", "SetLagCompensated", "SetEntColorEnabled" } do
  EntMeta[m] = function() end
end
-- Scripted NetworkVars: Get<Name>/Set<Name> on the instance, as the engine generates them.
function EntMeta:NetworkVar(_, _, name)
  self["Get" .. name] = function(e) return e._nv[name] end
  self["Set" .. name] = function(e, v) e._nv[name] = v end
end

local function newEnt(cls, ENTtbl, fields)
  local e = fields or {}
  e.__valid, e._cls, e._nv, e._emitted = true, cls, {}, {}   -- ENT.sounds is the class sound list
  e._pos = e._pos or Vector(0, 0, 0)
  setmetatable(e, { ENT = ENTtbl, __index = function(_, k)
    local v = ENTtbl and ENTtbl[k]
    if v ~= nil then return v end
    return EntMeta[k]   -- an unset field reads nil, as on a real entity
  end })
  if ENTtbl and ENTtbl.SetupDataTables then e:SetupDataTables() end
  return e
end

-- ents.Create builds the scripted class when a section registers it, a bare entity otherwise.
local REG, created = {}, {}
ents.Create = function(cls)
  local e = newEnt(cls, REG[cls])
  created[#created + 1] = e
  return e
end
local byName = {}
ents.FindByName = function(n) return byName[n] or {} end
ents.FindInSphere = function() return {} end

local function loadENT(...)
  ENT = {}
  for _, p in ipairs{ ... } do loadblocks(p, extract(ENTS .. p, "1-99999")) end
  local t = ENT
  ENT = nil
  return t
end

-- GLua's `continue` has no stock-Lua spelling, but LuaJIT has goto (see t_plugins_lps.lua).
local function withContinue(src, path, loopSpec)
  local loop = extract(path, loopSpec)
  local s, e = src:find(loop, 1, true)
  assert(s, "loop not found verbatim in " .. path .. " :: " .. loopSpec)
  local body, n = loop:gsub("%f[%w_]continue%f[^%w_]", "goto continue")
  if n == 0 then return src end
  body = body:gsub("end%s*$", "::continue:: end")
  return src:sub(1, s - 1) .. body .. src:sub(e + 1)
end

local function dmginfo(attacker, amount, inflictor)
  return { GetAttacker = function() return attacker end, GetInflictor = function() return inflictor or attacker end,
           GetDamage = function() return amount end, IsDamageType = function() return false end,
           ScaleDamage = function() end }
end
SetGlobalBool("InRound", true)

print("\n== #71/#31 brush_playerclip: every ph_kliener_v2 wall gets an ordered box ==")
REG.brush_playerclip = loadENT("brush_playerclip/init.lua")
loadblocks("config/sh_init.lua@CreatePlayerClip", extract(GMDIR .. "config/sh_init.lua", [[function PHX:CreatePlayerClip]]))
local Clips = loadblocks("ph_kliener_v2.lua@Clips",
  extract(GMDIR .. "config/maps/ph_kliener_v2.lua", [[^local Clips = \{]]) .. "\nreturn Clips")
check("the map config lists five walls", #Clips, 5)
for i, c in ipairs(Clips) do
  local inMins, inMaxs = tostring(c.mins), tostring(c.maxs)
  created = {}
  local r = attempt(function() PHX:CreatePlayerClip(c.mins, c.maxs) end)
  local pc = created[1]
  check(("wall %d: created without error"):format(i), r, "ok")
  if not (pc and pc._cbMins) then pc = { _cbMins = Vector(0, 0, 0), _cbMaxs = Vector(0, 0, 0), GetPos = EntMeta.GetPos } end
  local mn, mx = pc._cbMins, pc._cbMaxs
  check(("wall %d: box mins < maxs on every axis"):format(i),
    mn.x < mx.x and mn.y < mx.y and mn.z < mx.z, true)
  -- The world-space box (origin + local bounds) must be exactly the region the config names.
  local lo, hi = Vector(c.mins), Vector(c.maxs)
  OrderVectors(lo, hi)
  check(("wall %d: world box covers the configured region"):format(i),
    tostring(pc:GetPos() + mn) .. tostring(pc:GetPos() + mx), tostring(lo) .. tostring(hi))
  check(("wall %d: the config's vectors are not reordered in place"):format(i),
    tostring(c.mins) .. tostring(c.maxs), inMins .. inMaxs)
end
-- Wall 5 was already ordered: its box is exactly what it was before the fix.
created = {}
PHX:CreatePlayerClip(Clips[5].mins, Clips[5].maxs)
check("already-ordered wall: same box as before (normal play)",
  tostring(created[1]._cbMins) .. tostring(created[1]._cbMaxs), "[-4.5 -607.5 -725][4.5 607.5 725]")
check("already-ordered wall: centred on the region (normal play)", tostring(created[1]:GetPos()), "[1053.5 -824.5 675]")

print("\n== #67 decoy spawner: a 'model' keyvalue gives decoys that model ==")
REG.ph_fake_prop = loadENT("ph_fake_prop.lua")
local SPAWNER = (function()
  local path = ENTS .. "ph_decoy_spawner.lua"
  ENT = {}
  loadblocks("ph_decoy_spawner.lua", withContinue(extract(path, "1-99999"), path,
    [[for _,targEnt in pairs\( SpawnToEnt \) do]]))
  local t = ENT
  ENT = nil
  return t
end)()
local function spawner(kvs, targets)
  local sp = newEnt("ph_decoy_spawner", SPAWNER)
  for k, v in pairs(kvs) do sp:KeyValue(k, v) end
  byName.decoyspot = {}
  for i = 1, targets do byName.decoyspot[i] = newEnt("info_target", nil, { _pos = Vector(100 * i, 0, 0) }) end
  created = {}
  return sp
end
local function decoys()
  local t = {}
  for _, e in ipairs(created) do if e._cls == "ph_fake_prop" then t[#t + 1] = e end end
  return t
end
local OILDRUM = "models/props_c17/oildrum001.mdl"
local sp = spawner({ entity = "decoyspot", spawnchance = "1", model = OILDRUM }, 2)
check("model keyvalue: Spawn input runs without error", attempt(function() sp:AcceptInput("Spawn") end), "ok")
local d = decoys()
check("model keyvalue: every target gets a decoy", #d, 2)
check("model keyvalue: decoy 1 has the mapper's model", d[1] and d[1]._mdl, OILDRUM)
check("model keyvalue: decoy 2 has the mapper's model", d[2] and d[2]._mdl, OILDRUM)
check("model keyvalue: decoys are placed and re-solidified", d[2] and d[2]._physinit, 2)
check("model keyvalue: the model is precached", S.precached[1], OILDRUM)
sp = spawner({ entity = "decoyspot", spawnchance = "1" }, 2)
check("no model keyvalue: Spawn input runs without error", attempt(function() sp:AcceptInput("Spawn") end), "ok")
d = decoys()
check("no model keyvalue: every target gets a decoy", #d, 2)
check("no model keyvalue: decoy keeps the Kleiner model", d[2] and d[2]._mdl, "models/player/kleiner.mdl")
-- takemodelfrommap copies a random map prop (normal play, unchanged).
S.entsByClass["prop_physics*"] = { newEnt("prop_physics", nil, { _mdl = "models/map_prop.mdl" }) }
sp = spawner({ entity = "decoyspot", spawnchance = "1", takemodelfrommap = "1", model = OILDRUM }, 1)
check("takemodelfrommap: runs without error", attempt(function() sp:AcceptInput("Spawn") end), "ok")
check("takemodelfrommap: decoy copies the map prop", decoys()[1] and decoys()[1]._mdl, "models/map_prop.mdl")
-- The player's own decoy (sh_player.lua) still copies its ph_prop entity (normal play).
local own = newEnt("ph_fake_prop", REG.ph_fake_prop)
local myprop = newEnt("ph_prop", nil, { _mdl = "models/props/chair.mdl", _cbMins = Vector(-8, -8, 0), _cbMaxs = Vector(8, 8, 30) })
own:Spawn()
own:ChangeModel(myprop)
check("player decoy: copies its prop's model (normal play)", own._mdl, "models/props/chair.mdl")
check("player decoy: copies its prop's bounds (normal play)", tostring(own._cbMaxs), "[8 8 30]")
check("ChangeModel with no entity: no error", attempt(function() own:ChangeModel(nil) end), "ok")

print("\n== #200 decoy: a second hit in the same tick does not die twice ==")
local owner = S.Player{ team = TEAM_PROPS, name = "Owner" }
local hunterA = S.Player{ team = TEAM_HUNTERS, name = "A" }
local hunterB = S.Player{ team = TEAM_HUNTERS, name = "B" }
local propAtk = S.Player{ team = TEAM_PROPS, name = "P" }
hunterA:SetFrags(5); hunterB:SetFrags(5)
local killedHook = 0
hook.Add("PH_OnFakePropKilled", "t", function() killedHook = killedHook + 1 end)
local function notices()
  local n = 0
  for _, m in ipairs(S.net.sent) do if m.name == "PHX.DeathNoticeDecoy" then n = n + 1 end end
  return n
end
local decoy = newEnt("ph_fake_prop", REG.ph_fake_prop)
decoy:Spawn()
decoy:SetOwner(owner); owner.propdecoy = decoy
check("decoy starts with ph_decoy_health (10)", decoy.health, 10)
decoy:OnTakeDamage(dmginfo(propAtk, 50))
check("a prop's shot does nothing (normal play)", decoy.health, 10)
decoy:OnTakeDamage(dmginfo(hunterA, 4))
check("a non-lethal hit only takes health (normal play)", decoy.health, 6)
check("a non-lethal hit steals no frag (normal play)", hunterA:Frags(), 5)
decoy:OnTakeDamage(dmginfo(hunterA, 10))
check("killing blow: the killer loses a frag", hunterA:Frags(), 4)
check("killing blow: the owner gains a frag", owner:Frags(), 1)
check("killing blow: one death notice", notices(), 1)
decoy:OnTakeDamage(dmginfo(hunterB, 10))
check("same-tick second hit: the second hunter keeps his frags", hunterB:Frags(), 5)
check("same-tick second hit: the owner is not paid twice", owner:Frags(), 1)
check("same-tick second hit: no second death notice", notices(), 1)
check("same-tick second hit: PH_OnFakePropKilled fired once", killedHook, 1)

print("\n== #201/#210 Devil Crystal: one item per crystal ==")
local DEVIL = loadENT("ph_devilball/shared.lua", "ph_devilball/init.lua")
local given = {}
PHX.DEVIL_BALL = { Items = { function(pl, ent) given[#given + 1] = { pl = pl, ent = ent } end } }
local pickups = 0
hook.Add("PH_OnDevilBallPickup", "t", function() pickups = pickups + 1 end)
local crystal = newEnt("ph_devilball", DEVIL)
local prop1 = S.Player{ team = TEAM_PROPS, name = "prop1" }
local prop2 = S.Player{ team = TEAM_PROPS, name = "prop2" }
local deadProp = S.Player{ team = TEAM_PROPS, alive = false }
crystal:Use(hunterA)
check("a hunter cannot use it (normal play)", #given, 0)
crystal:Use(deadProp)
check("a dead prop cannot use it (normal play)", #given, 0)
check("a refused use leaves the crystal in place (normal play)", crystal._removed, nil)
crystal:Use(prop1)
check("a prop gets one item", #given, 1)
check("the item is given to the prop, with the crystal", given[1] and given[1].pl == prop1 and given[1].ent == crystal, true)
check("the crystal is removed", crystal._removed, true)
crystal:Use(prop2)
check("same-tick second use: no second item", #given, 1)
check("same-tick second use: pickup hook fired once", pickups, 1)
check("same-tick second use: pickup sound played once", #crystal._emitted, 1)
local c2 = newEnt("ph_devilball", DEVIL)
c2:SetHealth(50)
c2:OnTakeDamage(dmginfo(hunterA, 30))
check("a hit that leaves health does not break it (normal play)", c2._removed, nil)
c2:OnTakeDamage(dmginfo(hunterA, 30))
check("breaking it removes it", c2._removed, true)
c2:OnTakeDamage(dmginfo(hunterB, 30))
check("same-tick second hit: break sound plays once", #c2._emitted, 1)
c2:Use(prop2)
check("a crystal broken this tick gives no item", #given, 1)

print("\n== #201 Lucky Ball: one item per ball ==")
local LUCKY = loadENT("ph_luckyball/shared.lua", "ph_luckyball/init.lua")
local lucky = {}
PHX.LUCKY_BALL = { Items = { function(pl) lucky[#lucky + 1] = pl end } }
local ball = newEnt("ph_luckyball", LUCKY)
ball:Use(prop1)
check("a prop cannot use it (normal play)", #lucky, 0)
ball:Use(hunterA)
check("a hunter gets one item", #lucky, 1)
ball:Use(hunterB)
check("same-tick second use: no second item", #lucky, 1)
check("same-tick second use: pickup sound played once", #ball._emitted, 1)
local b2 = newEnt("ph_luckyball", LUCKY)
b2:SetHealth(100)
b2:OnTakeDamage(dmginfo(prop1, 100))
b2:OnTakeDamage(dmginfo(prop1, 100))
check("same-tick second hit: break sound plays once", #b2._emitted, 1)
b2:Use(hunterB)
check("a ball broken this tick gives no item", #lucky, 1)

print("\n== #69 ph_model_bans: RemoveBans lifts only the bans the map added ==")
local BANS = loadENT("ph_model_bans.lua")
local MOUSE, CHAIR = "models/props/cs_office/computer_mouse.mdl", "models/props/cs_office/chair_office.mdl"
local banUpdates = 0
function PHX:ENT_UpdateModelBan() banUpdates = banUpdates + 1 end
PHX.BANNED_PROP_MODELS = { "models/props/ph_gas_stationrc7/piepan.mdl", MOUSE }
local function has(m) return table.HasValue(PHX.BANNED_PROP_MODELS, m) end
local mb = newEnt("ph_model_bans", BANS)
mb:KeyValue("model1", MOUSE)
mb:KeyValue("model2", CHAIR)
mb:GetBannedList()
mb:AcceptInput("AddBans")
check("AddBans: the map's new ban is added", has(CHAIR), true)
check("AddBans: an existing ban is not duplicated", #PHX.BANNED_PROP_MODELS, 3)
check("AddBans: clients are sent the list", banUpdates, 1)
mb:AcceptInput("RemoveBans")
check("RemoveBans: the map's own ban is lifted (normal play)", has(CHAIR), false)
check("RemoveBans: the server's perma-ban stays", has(MOUSE), true)
check("RemoveBans: unrelated bans stay", has("models/props/ph_gas_stationrc7/piepan.mdl"), true)
mb:AcceptInput("AddBans")
check("AddBans again: the map's ban is back (normal play)", has(CHAIR), true)
mb:AcceptInput("AddBans")
check("AddBans while active: no duplicate (normal play)", #PHX.BANNED_PROP_MODELS, 3)
mb:AcceptInput("RemoveBans")
check("second RemoveBans: the perma-ban still stays", has(MOUSE), true)
check("second RemoveBans: the map's ban is lifted again", has(CHAIR), false)

print("\n== #34 ph_model_bans: a mixed-case model matches the lowercase list ==")
PHX.BANNED_PROP_MODELS = { MOUSE }
local mixed = newEnt("ph_model_bans", BANS)
mixed:KeyValue("model1", "Models/Props/CS_Office/Computer_Mouse.mdl")
mixed:KeyValue("model2", "models/props/CS_Office/Chair_Office.mdl")
mixed:GetBannedList()
mixed:AcceptInput("AddBans")
check("mixed-case copy of a server ban: not added again", #PHX.BANNED_PROP_MODELS, 2)
check("mixed-case new ban: stored lowercase", has(CHAIR), true)
mixed:AcceptInput("RemoveBans")
check("RemoveBans: the mixed-case map ban is lifted", has(CHAIR), false)
check("RemoveBans: the server's ban stays", has(MOUSE), true)

print("\n== #204/#68 ph_prop damage: armor floor and hunter kill bonus ==")
local PROP = loadENT("ph_prop.lua")
local weapon = { __valid = true, GetClass = function() return "weapon_smg1" end }
-- A living prop at full health, owned by a player, as GM:PlayerSpawn leaves it.
local function disguised(armor)
  local pl = S.Player{ team = TEAM_PROPS, name = "prop" }
  pl:SetArmor(armor or 0)
  local ent = newEnt("ph_prop", PROP)
  ent.health = 100
  ent:SetOwner(pl)
  return ent, pl
end
local function shoot(ent, atk, amount) return attempt(function() ent:OnTakeDamage(dmginfo(atk, amount, weapon)) end) end
local hunter = S.Player{ team = TEAM_HUNTERS, name = "hunter" }
local ent, pl = disguised(15)
check("15 armor, 20 damage: handler runs", shoot(ent, hunter, 20), "ok")
check("15 armor, 20 damage: damage is halved", ent.health, 90)
check("15 armor, 20 damage: armor stops at 0, not -5", pl:Armor(), 0)
ent, pl = disguised(30)
shoot(ent, hunter, 20)
check("30 armor, 20 damage: armor 10 (normal play)", pl:Armor(), 10)
check("30 armor, 20 damage: damage halved (normal play)", ent.health, 90)
ent, pl = disguised(5)
shoot(ent, hunter, 20)
check("5 armor: no absorption, full damage (normal play)", ent.health, 80)
check("5 armor: armor untouched (normal play)", pl:Armor(), 5)
RunConsoleCommand("ph_allow_armor", "0")
ent, pl = disguised(30)
shoot(ent, hunter, 20)
check("armor disabled: full damage (normal play)", ent.health, 80)
check("armor disabled: armor untouched (normal play)", pl:Armor(), 30)
RunConsoleCommand("ph_allow_armor", "1")

local function killWith(hp, alive)
  local h = S.Player{ team = TEAM_HUNTERS, name = "killer", alive = alive }
  h:SetHealth(hp); h:SetFrags(0)
  local e, p = disguised(0)
  e.health = 10
  local r = shoot(e, h, 20)
  return h, p, r
end
local h, victim, r = killWith(160)
check("overhealed hunter kills a prop: handler runs", r, "ok")
check("overhealed hunter kills a prop: the prop dies", victim:Alive(), false)
check("overhealed hunter (160 HP): keeps 160, was cut to 100", h:Health(), 160)
check("overhealed hunter: still credited the kill", h:Frags(), 1)
h = killWith(50)
check("hunter at 50 HP: +25 bonus (normal play)", h:Health(), 75)
h = killWith(90)
check("hunter at 90 HP: topped up to 100 (normal play)", h:Health(), 100)
h = killWith(100)
check("hunter at 100 HP: stays 100 (normal play)", h:Health(), 100)
h = killWith(0, false)
check("dead hunter's grenade kills a prop: health left alone", h:Health(), 0)
check("dead hunter's grenade kills a prop: kill still credited", h:Frags(), 1)
RunConsoleCommand("ph_hunter_kill_bonus", "0")
h = killWith(50)
check("kill bonus 0: health unchanged (normal play)", h:Health(), 50)
RunConsoleCommand("ph_hunter_kill_bonus", "25")

print("\n== #242 prop freeze cam: a prop respawned in blind time is left alone ==")
function S.PlyMeta:Spectate(m) self._obs = m end
function S.PlyMeta:SpectateEntity(e) self._spec = e end
S.timers = {}
local killer, frozen = killWith(100)
S.pump(0.6)
check("still dead at 0.5s: freeze cam (normal play)", frozen._obs, OBS_MODE_FREEZECAM)
check("still dead at 0.5s: watching the killer (normal play)", frozen._spec == killer, true)
S.pump(4)
check("still dead at 4.5s: chase cam (normal play)", frozen._obs, OBS_MODE_CHASE)
local _, back = killWith(100)
S.pump(0.4); back:Spawn()                     -- the blind-time respawn (0.45s in game)
S.pump(0.2)
check("respawned before 0.5s: no freeze cam", back._obs, nil)
check("respawned before 0.5s: InFreezeCam stays off", back:GetNWBool("InFreezeCam", false), false)
-- Guard on the 4.5s timer alone: alive again while InFreezeCam is still set.
local _, late = killWith(100)
S.pump(0.6); late:Spawn(); late._obs = nil
S.pump(4)
check("alive again with InFreezeCam set: no chase cam at 4.5s", late._obs, nil)

print("\n== #202 team item spawner: a target name that matches nothing ==")
local ITEMS = loadENT("ph_teamitem_spawner.lua")
local function itemSpawner(target)
  local s = newEnt("ph_teamitem_spawner", ITEMS, { _pos = Vector(1, 2, 3) })
  s:KeyValue("spawnent", "1")
  s:KeyValue("amount", 1)
  s:KeyValue("spawnontarget", target)
  s:SetSilent(true)
  created, S.msgc = {}, {}
  return s
end
local function balls()
  local t = {}
  for _, e in ipairs(created) do if e._cls == "ph_luckyball" then t[#t + 1] = e end end
  return t
end
local is = itemSpawner("nosuchname")
check("unknown target: Spawn input runs without error", attempt(function() is:AcceptInput("Spawn") end), "ok")
check("unknown target: nothing is spawned", #balls(), 0)
check("unknown target: the mapper is told why", S.msgc[1] ~= nil and S.msgc[1]:find("nosuchname", 1, true) ~= nil, true)
byName.itemspot = { newEnt("info_target", nil, { _pos = Vector(10, 20, 30) }) }
is = itemSpawner("itemspot")
check("named target: runs without error (normal play)", attempt(function() is:AcceptInput("Spawn") end), "ok")
check("named target: one ball spawned (normal play)", #balls(), 1)
check("named target: spawned on the target (normal play)", balls()[1] and tostring(balls()[1]:GetPos()), "[10 20 30]")
is = itemSpawner("")
check("no target: runs without error (normal play)", attempt(function() is:AcceptInput("Spawn") end), "ok")
check("no target: spawned on the spawner (normal play)", balls()[1] and tostring(balls()[1]:GetPos()), "[1 2 3]")

report()
