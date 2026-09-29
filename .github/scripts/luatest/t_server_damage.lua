dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- prop_hunt's EntityTakeDamage hook, every branch, run as shipped: hits on a
-- prop player go to its ph_prop, and a living hunter who damages a usable map
-- prop pays ph_hunter_fire_penalty (from armor first, with ph_allow_armor).
--
-- The code is loaded from the "Called when an entity takes damage" comment to
-- the hook.Add, so whatever local helpers sit in between come with it.

local INIT = "gamemodes/prop_hunt/gamemode/init.lua"
local ROOT = (debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "../../../"

local a, b, i = nil, nil, 0
for line in io.lines(ROOT .. INIT) do
  i = i + 1
  if not a and line:match("^%-%- Called when an entity takes damage") then a = i end
  if a and not b and line:match('^hook%.Add%("EntityTakeDamage", "PH_EntityTakeDamage"') then b = i end
end
assert(a and b, "EntityTakeDamage block not found in " .. INIT)
loadblocks("init.lua@EntityTakeDamage", extractAll(INIT, { [[^local hunterdamagefix]], a .. "-" .. b }))
local ETD = S.hooks.EntityTakeDamage.PH_EntityTakeDamage

local usable = { prop_physics = true, prop_ragdoll = true, ph_prop = true,
                 func_breakable = true, func_physbox = true, ph_fake_prop = true }
function PHX:IsUsablePropEntity(c) return usable[c] == true end
function S.PlyMeta:GetClass() return "player" end
local msgs = 0
function MsgAll() msgs = msgs + 1 end
local penalised = {}
hook.Add("PH_HunterDeathPenalty", "test", function(p) penalised[#penalised + 1] = p end)
CreateConVar("ph_hunter_fire_penalty", "5")
S.boolCVar("ph_allow_armor", "0")

local WORLD = { __valid = false }
local function disguise()
  local p = { __valid = true, took = {} }
  function p:GetModel() return "models/crate.mdl" end
  function p:TakeDamageInfo(d) self.took[#self.took + 1] = d end
  return p
end
local function prop(t)
  t = t or {}
  local pl = S.Player{ team = t.team or TEAM_PROPS, alive = t.alive, name = "prop" }
  pl.ph_prop = disguise()
  return pl
end
local function hunter(hp, ap, alive)
  local h = S.Player{ team = TEAM_HUNTERS, alive = alive, name = "hunter" }
  h._hp, h._ap = hp or 100, ap or 0
  return h
end
local function ent(cls)
  return { __valid = true, GetClass = function() return cls end, IsPlayer = function() return false end }
end
local function dmg(att)
  return { GetAttacker = function() return att end, GetDamageType = function() return 0 end }
end
-- Runs the hook once; returns what it returned and how many hits the disguise got.
local function hit(victim, att)
  local d = dmg(att)
  local ret = ETD(victim, d)
  local took = victim.ph_prop and victim.ph_prop ~= NULL and #victim.ph_prop.took or 0
  return ret, took, d
end
local function inRound(on) S.globals.InRound = on end

print("\n== prop players: hits go to the disguise ==")
inRound(true)
local h, pl = hunter(), prop()
local ret, took, d = hit(pl, h)
check("hunter hits a prop: forwarded to ph_prop", took, 1)
check("  ...with the same dmginfo", pl.ph_prop.took[1], d)
check("  ...and the hook returns nothing", ret, nil)
check("  ...and the hunter is not penalised", h:Health(), 100)
pl = prop()
check("prop teammate hits a prop: not forwarded", select(2, hit(pl, prop())), 0)
check("fall/world damage: forwarded", select(2, hit(prop(), WORLD)), 1)
check("physics-entity attacker: forwarded", select(2, hit(prop(), ent("prop_physics"))), 1)
check("dead prop: not forwarded", select(2, hit(prop{ alive = false }, h)), 0)
check("hunter hit by a prop: not forwarded", select(2, hit(prop{ team = TEAM_HUNTERS }, prop())), 0)
local fake = ent("npc_thing"); fake.ph_prop = disguise(); fake.Team = function() return TEAM_PROPS end
check("non-player carrying a ph_prop: not forwarded", select(2, hit(fake, h)), 0)
pl = prop(); pl.ph_prop = nil
check("prop without ph_prop (entity limit): no error", attempt(ETD, pl, dmg(h)), "ok")
pl = prop(); pl.ph_prop = NULL
check("prop with NULL ph_prop (cleanup): no error", attempt(ETD, pl, dmg(h)), "ok")
check("NULL victim: no error", attempt(ETD, NULL, dmg(h)), "ok")
inRound(false)
check("not in round: not forwarded", select(2, hit(prop(), h)), 0)
inRound(true)

print("\n== hunters shooting props pay ph_hunter_fire_penalty ==")
local function shoot(target, att) local r = ETD(target, dmg(att)); return r, att:Health(), att:Armor() end
h = hunter()
local r2, hp = shoot(ent("prop_physics"), h)
check("hunter shoots a prop_physics: -5", hp, 95)
check("  ...and the hook returns nothing", r2, nil)
check("shoots a disguise (ph_prop): no penalty", select(2, shoot(ent("ph_prop"), hunter())), 100)
for _, cls in ipairs{ "func_breakable", "func_physbox", "ph_fake_prop" } do
  check("shoots " .. cls .. ": no penalty", select(2, shoot(ent(cls), hunter())), 100)
end
check("shoots a non-usable entity: no penalty", select(2, shoot(ent("func_door"), hunter())), 100)
check("world damage to a prop_physics: no error", attempt(ETD, ent("prop_physics"), dmg(WORLD)), "ok")
-- Hunter-like in every way but IsPlayer, so only that check keeps it unpenalised.
local phys = setmetatable(ent("prop_physics"), { __index = S.PlyMeta }); phys._team, phys._alive, phys._hp = TEAM_HUNTERS, true, 100
check("non-player attacker (physics prop): no penalty", select(2, shoot(ent("prop_physics"), phys)), 100)
local p2 = prop(); p2._hp = 100
check("prop player damaging a prop_physics: no penalty", select(2, shoot(ent("prop_physics"), p2)), 100)
check("dead hunter: no penalty", select(2, shoot(ent("prop_physics"), hunter(100, 0, false))), 100)
usable.player = true
check("usable class but a player (dead prop): no penalty", select(2, shoot(prop{ alive = false }, hunter())), 100)
usable.player = nil
check("NULL target: no error", attempt(ETD, NULL, dmg(hunter())), "ok")
inRound(false)
check("not in round: no penalty", select(2, shoot(ent("prop_physics"), hunter())), 100)
inRound(true)

print("\n== ph_allow_armor takes it from armor first ==")
S.cvars.ph_allow_armor.v = "1"
local _, hp1, ap1 = shoot(ent("prop_physics"), hunter(100, 30))
check("armor 30, penalty 5: health -3 (half, rounded)", hp1, 97)
check("  ...armor -15", ap1, 15)
_, hp1, ap1 = shoot(ent("prop_physics"), hunter(100, 10))
check("armor 10: health -3", hp1, 97)
check("  ...armor clamps at 0", ap1, 0)
_, hp1, ap1 = shoot(ent("prop_physics"), hunter(100, 4))
check("armor 4 (under 5): full penalty", hp1, 95)
check("  ...armor untouched", ap1, 4)
S.cvars.ph_hunter_fire_penalty.v = "3"
_, hp1, ap1 = shoot(ent("prop_physics"), hunter(100, 30))
check("penalty 3 (under 5): full penalty", hp1, 97)
check("  ...armor untouched", ap1, 30)
S.cvars.ph_hunter_fire_penalty.v = "7"
_, hp1 = shoot(ent("prop_physics"), hunter(100, 30))
check("penalty 7 with armor: health -4 (3.5 rounds up)", hp1, 96)
S.cvars.ph_hunter_fire_penalty.v = "5"
S.cvars.ph_allow_armor.v = "0"
_, hp1, ap1 = shoot(ent("prop_physics"), hunter(100, 30))
check("ph_allow_armor 0: full penalty", hp1, 95)
check("  ...armor untouched", ap1, 30)

print("\n== a penalty that empties the hunter kills them ==")
msgs, penalised = 0, {}
h = hunter(5)
shoot(ent("prop_physics"), h)
check("5 hp, penalty 5: dead", h:Alive(), false)
check("  ...PH_HunterDeathPenalty with the hunter", penalised[1], h)
check("  ...announced once", msgs, 1)
msgs, penalised = 0, {}
h = hunter(6)
shoot(ent("prop_physics"), h)
check("6 hp: alive on 1", h:Alive() and h:Health(), 1)
check("  ...no death penalty hook", #penalised, 0)
check("  ...nothing announced", msgs, 0)
h = hunter(3)
shoot(ent("prop_physics"), h)
check("3 hp: dead (below zero)", h:Alive(), false)

print("\n== registration ==")
for _, n in ipairs{ "EntityTakeDamage", "IsDisguisedProp", "RedirectPropDamage", "IsPenalisedProp",
                    "IsLivingHunter", "ApplyFirePenalty" } do
  check(n .. " is not a global", rawget(_G, n), nil)
end

report()
