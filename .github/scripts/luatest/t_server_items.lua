dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- Lucky balls and devil crystals, run as shipped (the whole sv_items.lua): armor
-- items honour ph_allow_armor, the two speed crystals share one saved speed
-- without SetWalkSpeed(nil), and the "hunters are frozen" crystal never leaves a
-- blinded hunter half-unlocked; ClearBlindedHuntersList unlocks him regardless.

HUD_PRINTCENTER = 4
function Sound(s) return s end

-- Player:Lock / UnLock / Freeze as the engine has them (server.so): Lock adds
-- FL_FROZEN|FL_GODMODE and MOVETYPE_NONE once; UnLock undoes that only if Locked;
-- Freeze touches FL_FROZEN alone. The shim folds all three into one flag.
local PM = S.PlyMeta
function PM:Lock() if self._lk then return end self._frozen, self._god, self._lk = true, true, true end
function PM:UnLock() if not self._lk then return end self._frozen, self._god, self._lk = false, false, false end
function PM:Freeze(b) self._frozen = b end
function PM:IsFrozen() return self._frozen == true end
-- SetWalkSpeed type-checks its argument like the engine (CheckNumber).
function PM:SetWalkSpeed(v)
  if type(v) ~= "number" then error("bad argument #1 to 'SetWalkSpeed' (number expected, got " .. type(v) .. ")") end
  self._walk = v
end
function PM:AddHealthProp() end

loadblocks("sv_items.lua", extract("gamemodes/prop_hunt/gamemode/sv_items.lua", "1-999999"))
loadblocks("init.lua@ClearBlindedHuntersList",
  extract("gamemodes/prop_hunt/gamemode/init.lua", [[^local function ClearBlindedHuntersList]]) ..
  "\n_G.ClearBlindedHuntersList = ClearBlindedHuntersList")

local LUCKY, DEVIL = PHX.LUCKY_BALL.Items, PHX.DEVIL_BALL.Items
local FAST, HEAL, ARMOR, SLOW, FREEZE = 1, 2, 3, 4, 5
S.boolCVar("ph_allow_armor", "1")
SetGlobalBool("InRound", true)

local function has(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
local function said(p) return #p.chat > 0 end

print("\n== armor items follow ph_allow_armor ==")
local h = S.Player{ team = TEAM_HUNTERS }
LUCKY[6](h)
check("armor on: lucky battery given", has(h.weapons, "item_battery"), true)
S.cvars["ph_allow_armor"].v = "0"
h = S.Player{ team = TEAM_HUNTERS }
LUCKY[6](h)
check("armor off: lucky battery NOT given", has(h.weapons, "item_battery"), false)
check("armor off: lucky battery still says something", said(h), true)
h = S.Player{ team = TEAM_HUNTERS }
LUCKY[7](h)
check("armor off: lucky armor gives none", h:Armor(), 0)
check("armor off: lucky armor still says something", said(h), true)
local pr = S.Player{ team = TEAM_PROPS }
DEVIL[ARMOR](pr)
check("armor off: devil armor gives none", pr:Armor(), 0)
check("armor off: devil armor still says something", said(pr), true)
S.cvars["ph_allow_armor"].v = "1"
pr = S.Player{ team = TEAM_PROPS }
DEVIL[ARMOR](pr)
check("armor on: devil armor adds armor", pr:Armor() > 0, true)

print("\n== speed crystals ==")
-- Fix the crystal durations so the order of expiry is known.
local realRandom = math.random
local durations
math.random = function(a, b) if a == 4 and b == 12 and durations and #durations > 0 then return table.remove(durations, 1) end return realRandom(a, b) end

local function speedCase(first, second, d1, d2)
  S.timers = {}
  durations = { d1, d2 }
  local p = S.Player{ team = TEAM_PROPS, walk = 250, idx = 7 }
  S.players = { p }
  DEVIL[first](p)
  if second then DEVIL[second](p) end
  return p
end
local p = speedCase(FAST, nil, 6)
check("fast alone: +100", p:GetWalkSpeed(), 350)
local errs = S.pump(7)
check("fast alone: back to 250", p:GetWalkSpeed(), 250)
check("fast alone: no errors", #errs, 0)

p = speedCase(FAST, SLOW, 4, 8)
check("fast + slow: both applied", p:GetWalkSpeed(), 250)
errs = S.pump(5)
check("fast ends first: only its +100 undone", p:GetWalkSpeed(), 150)
check("  ... no error", errs[1], nil)
errs = S.pump(4)
check("slow ends: back to 250", p:GetWalkSpeed(), 250)
check("  ... no error", errs[1], nil)
check("  ... both flags cleared", tostring(p.ph_fastspeed) .. "/" .. tostring(p.ph_slowspeed), "false/false")

p = speedCase(SLOW, FAST, 4, 8)
S.pump(5)
check("slow ends first: only its -100 undone", p:GetWalkSpeed(), 350)
errs = S.pump(4)
check("fast ends: back to 250, no error", p:GetWalkSpeed() .. "/" .. tostring(errs[1]), "250/nil")

p = speedCase(FAST, nil, 12)
S.fire("PH_RoundEnd")                                     -- ResetEverything
check("round ends mid-buff: speed restored", p:GetWalkSpeed(), 250)
p.chat = {}
errs = S.pump(13)
check("  ... the old timer raises nothing", errs[1], nil)
check("  ... and says nothing after the round", #p.chat, 0)

-- a buff taken next round is not cut short by last round's timer
p = speedCase(FAST, nil, 12)
S.pump(2)
S.fire("PH_RoundEnd")
durations = { 12 }
DEVIL[FAST](p)
S.pump(11)
check("next round's buff lasts its own time", p:GetWalkSpeed(), 350)
math.random = realRandom

print("\n== 'hunters are frozen' crystal ==")
local function hunters(n)
  S.timers, S.players = {}, {}
  local t = {}
  for i = 1, n do t[i] = S.Player{ team = TEAM_HUNTERS, idx = i }; S.players[i] = t[i] end
  return t
end
local prop = S.Player{ team = TEAM_PROPS, idx = 20 }

-- seek phase (normal play): frozen, then released
local H = hunters(2)
H[2]._alive = false
DEVIL[FREEZE](prop)
check("seek phase: living hunter frozen", H[1]:IsFrozen(), true)
check("seek phase: dead hunter untouched", H[2]:IsFrozen(), false)
S.pump(3.1)
check("seek phase: released after 2-3s", H[1]:IsFrozen(), false)

-- blind time: hunters are Locked
H = hunters(1)
SetGlobalBool("PHX.BlindStatus", true)
H[1]:Lock(); H[1]:Blind(true)
DEVIL[FREEZE](prop)
S.pump(3.1)
check("blind time: crystal leaves the Lock intact (still frozen)", H[1]:IsFrozen(), true)
SetGlobalBool("PHX.BlindStatus", false)
ClearBlindedHuntersList()
check("blind over: unlocked", H[1]._lk, false)
check("blind over: no godmode", H[1]._god, false)
check("blind over: can move", H[1]:IsFrozen(), false)

-- something else stripped FL_FROZEN from a locked hunter: still fully unlocked
H = hunters(1)
H[1]:Lock(); H[1]:Freeze(false)
ClearBlindedHuntersList()
check("FL_FROZEN stripped elsewhere: still unlocked", H[1]._lk, false)
check("FL_FROZEN stripped elsewhere: no godmode", H[1]._god, false)
-- an unlocked hunter is left alone by UnLock
H = hunters(1)
H[1]:Freeze(true)                                        -- e.g. end-of-game freeze
ClearBlindedHuntersList()
check("a plain Freeze (not a Lock) is not undone", H[1]:IsFrozen(), true)

-- round ends while the crystal holds them; next round's blind Lock must survive the timer
H = hunters(1)
DEVIL[FREEZE](prop)
S.fire("PH_RoundEnd")
check("round end: crystal freeze released", H[1]:IsFrozen(), false)
H[1]:Lock()
S.pump(3.1)
check("next round's blind Lock survives the old timer", H[1]:IsFrozen() and H[1]._lk, true)

report()
