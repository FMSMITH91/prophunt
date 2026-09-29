dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- Last Prop Standing, server side: executes the shipped sh_lps.lua, sh_lps_player.lua,
-- sh_lps_config.lua and sv_lps.lua under the shim.
local LPS = "gamemodes/prop_hunt/gamemode/plugins/lps/"

-- Engine pieces shim.lua leaves out (kept here: shim.lua is shared with other branches).
function isfunction(v) return type(v) == "function" end
-- math.Rand is copied from garrysmod/lua/includes/extensions/math.lua.
math.Rand = function(low, high) return low + (high - low) * math.random() end
IN_ATTACK, IN_ATTACK2 = 1, 2048
CHAN_STATIC, SOLID_NONE, MOVETYPE_NONE, DMG_DISSOLVE = 6, 0, 0, 67108864
function FindMetaTable(n) if n == "Player" then return S.PlyMeta end end
function IsFirstTimePredicted() return true end
function Model(m) return m end
function Sound(s) return s end
function EffectData() return setmetatable({}, { __index = function() return function() end end }) end
util.Effect = function() end
util.BlastDamageInfo = function() end
function DamageInfo() return setmetatable({}, { __index = function() return function() end end }) end
function RecipientFilter() return { AddPlayer = function() end } end
S.music = {}
function CreateSound(_, snd)
  S.music[#S.music + 1] = snd
  return { SetSoundLevel = function() end, PlayEx = function() end, Stop = function() end }
end
S.worldSounds = {}
game.GetWorld = function() return { EmitSound = function(_, snd) S.worldSounds[#S.worldSounds + 1] = snd end } end
-- A trace with every field the LPS code reads. Entity is a world-like entity: GMod's NULL
-- answers IsValid(), the shim's strict NULL raises on any read.
util.TraceLine = function()
  return { Hit = true, HitPos = Vector(100, 0, 0), StartPos = Vector(0, 0, 0), HitNormal = Vector(0, 0, 1),
           Normal = Vector(1, 0, 0), Entity = { IsValid = function() return false end } }
end
GAMEMODE.ViewCam.CamColEnabled = function(_, _, _, t) return t or {} end
GAMEMODE.ViewCam.CommonCamCollEnabledView = function() return {} end

local PM = S.PlyMeta
function PM:SetNWString(k, v) self._nw[k] = v end
function PM:GetNWString(k, d) local v = self._nw[k]; if v == nil then return d end return v end
function PM:GetHull() return Vector(-16, -16, 0), Vector(16, 16, 72) end
function PM:ViewPunch(a) self.punches = self.punches or {}; self.punches[#self.punches + 1] = a end
function PM:LagCompensation() end
function PM:FireBullets() self.shots = (self.shots or 0) + 1 end
function PM:SetHealthProp(v) self._hp = v end

-- GLua's `continue` has no stock-Lua spelling, but LuaJIT has goto. Rewrite the loop that
-- uses it, located by the extractor's own block walker so the label lands on that loop's
-- real `end`, and refuse to run if the loop is not found verbatim in the file.
local function withContinue(src, path, loopSpec)
  local loop = extract(path, loopSpec)
  local s, e = src:find(loop, 1, true)
  assert(s, "loop not found verbatim in " .. path .. " :: " .. loopSpec)
  local body, n = loop:gsub("%f[%w_]continue%f[^%w_]", "goto continue")
  if n == 0 then return src end
  body = body:gsub("end%s*$", "::continue:: end")
  return src:sub(1, s - 1) .. body .. src:sub(e + 1)
end

-- The real cvar layer: PHX:AddCVar/GetCVar and ConVarTranslate from sh_convar.lua, so bool
-- cvars read back as real booleans from the replicated globals, exactly as in game.
loadblocks("sh_convar.lua@cvars",
  extract("gamemodes/prop_hunt/gamemode/sh_convar.lua", "1-10") .. "\n"
  .. extract("gamemodes/prop_hunt/gamemode/sh_convar.lua", [[^local ConVarTranslate = \{]]) .. "\nlocal CVAR = {}\n"
  .. extractAll("gamemodes/prop_hunt/gamemode/sh_convar.lua", {
       [[^function PHX:AddCVar]], [[^function PHX:GetCVar]], [[^function PHX:QCVar]] }))
function PHX:Includes() end
-- The engine clamps a FCVAR min/max ConVar on every set; the shim's RunConsoleCommand does not.
local function engineSet(name, v)
  local c = S.cvars[name]
  v = tonumber(v) or v
  if type(v) == "number" then
    if c.min and v < c.min then v = c.min end
    if c.max and v > c.max then v = c.max end
  end
  RunConsoleCommand(name, tostring(v))
end

PHX:AddCVar(CTYPE_NUMBER, "ph_rounds_per_map", "10", CVAR_SERVER_ONLY, "")
PHX:AddCVar(CTYPE_BOOL, "ph_allow_armor", "0", CVAR_SERVER_ONLY, "")

loadblocks("sh_lps.lua", extract(LPS .. "sh_lps.lua", "1-99999"))
loadblocks("sh_load.lua@utils", extractAll(LPS .. "sh_load.lua", {
  [[^function util\.LPSgetSpread]], [[^function util\.LPSgetConValue]], [[^function util\.LPSgetAccurateAim]] }))
loadblocks("sh_lps_player.lua", extract(LPS .. "sh_lps_player.lua", "1-99999"))
do
  local path = LPS .. "sh_lps_config.lua"
  local src = extract(path, "1-99999")
  src = withContinue(src, path, [[for _,v in pairs\(player\.GetAll\(\)\) do]])
  src = withContinue(src, path, [[for _,v in pairs\(team\.GetPlayers\(TEAM_PROPS\)\) do]])
  loadblocks("sh_lps_config.lua", src)
end
loadblocks("round_controller.lua@GetTeamAliveCounts",
  extract("gamemodes/base_phx/gamemode/round_controller.lua", [[^function GM:GetTeamAliveCounts]]))
do
  local path = LPS .. "sv_lps.lua"
  loadblocks("sv_lps.lua", withContinue(extract(path, "1-99999"), path, [[for _,p in pairs\(player\.GetAll\(\)\) do]]))
end
S.fire("Initialize")      -- AddSound: file.Find finds nothing, like a server without sound/lps

SetGlobalBool("InRound", true)

local function fakeWepEnt()
  return { __valid = true, GetAttachment = function() return { Pos = Vector(0, 0, 50), Ang = Angle() } end,
           EmitSound = function() end, GetClass = function() return "ph_lps_weapon" end }
end
local activeWep = { __valid = true, GetClass = function() return "weapon_lps" end, EmitSound = function() end }

-- A prop that already is the last prop standing, holding `weapon` with `ammo` rounds.
local function lpsProp(weapon, ammo)
  local p = S.Player{ team = TEAM_PROPS }
  p:SetLastStanding(true)
  p:SetLPSWeapon(weapon)
  p:SetLPSAmmoCount(ammo)
  p:SetLPSWeaponState(LPS_WEAPON_READY)
  p._nw["bLps.WeaponEnt"] = fakeWepEnt()
  p.HasWeapon = function(_, c) return c == PHX.LPS.DUMMYWEAPON end
  p.GetActiveWeapon = function() return activeWep end
  S.players = { p }
  return p
end

-- One SetupMove tick with the given buttons held (down) / newly pressed (pressed).
local function tick(p, down, pressed)
  local mv = { KeyDown = function(_, k) return (down or {})[k] == true end,
               KeyPressed = function(_, k) return (pressed or {})[k] == true end }
  S.fire("SetupMove", p, mv)
end

print("\n== #55 spread and view punch: real-valued ranges, not two values ==")
local inRange, distinct = true, {}
for _ = 1, 5000 do
  local v = util.LPSgetSpread({ 0.02, 0.05 })
  if v.x < 0.02 or v.x > 0.05 or v.y < 0.02 or v.y > 0.05 then inRange = false end
  distinct[v.x] = true
end
check("SMG spread {0.02,0.05} stays inside 0.02..0.05", inRange, true)
check("SMG spread actually varies (>50 distinct values)", table.Count(distinct) > 50, true)
check("numeric spread passes through unchanged", util.LPSgetSpread(0.08716).x, 0.08716)

local punchOK, p = true, nil
for _ = 1, 500 do
  _G.CURTIME = _G.CURTIME + 1
  p = lpsProp("smg", 300)
  tick(p, { [IN_ATTACK] = true })
  local a = p.punches and p.punches[1]
  if not a or a.p < -0.9 or a.p > 0.02 or a.y < -0.03 or a.y > 0.03 then punchOK = false end
end
check("SMG view punch stays inside x{-0.9,0.02} y{-0.03,0.03}", punchOK, true)

print("\n== #186 ammo counts down what the player holds, not the cvar ==")
local function shoot(weapon, ammo, cvarName, cvarValue)
  if cvarName then engineSet(cvarName, cvarValue) end
  _G.CURTIME = _G.CURTIME + 5
  local pl = lpsProp(weapon, ammo)
  tick(pl, { [IN_ATTACK] = true })
  return pl
end
check("smg 5 rounds, cvar 300 -> 4 (normal play)", shoot("smg", 5, "lps_ammocount_smg", 300):GetLPSAmmo(), 4)
local last = shoot("smg", 1, "lps_ammocount_smg", 300)
check("smg last round -> 0 (normal play)", last:GetLPSAmmo(), 0)
check("smg last round -> OUTOFAMMO (normal play)", last:GetLPSWeaponState(), LPS_WEAPON_OUTOFAMMO)
check("smg unlimited, cvar 300 -> stays unlimited", shoot("smg", -1, "lps_ammocount_smg", 300):GetLPSAmmo(), -1)
check("smg unlimited, cvar -1 -> stays unlimited (normal play)", shoot("smg", -1, "lps_ammocount_smg", -1):GetLPSAmmo(), -1)
check("smg 5 rounds, cvar changed to -1 -> 4", shoot("smg", 5, "lps_ammocount_smg", -1):GetLPSAmmo(), 4)
check("rocket 3 rounds, cvar 30 -> 2 (normal play)", shoot("rocket", 3, "lps_ammocount_rocket", 30):GetLPSAmmo(), 2)
check("rocket 3 rounds, cvar changed to -1 -> 2", shoot("rocket", 3, "lps_ammocount_rocket", -1):GetLPSAmmo(), 2)
check("rocket unlimited, cvar 30 -> stays unlimited", shoot("rocket", -1, "lps_ammocount_rocket", 30):GetLPSAmmo(), -1)
check("blaster (unlimited) stays unlimited (normal play)", shoot("blaster", -1):GetLPSAmmo(), -1)
engineSet("lps_ammocount_smg", 300); engineSet("lps_ammocount_rocket", 30)

print("\n== #53 lps_allow_holster is honoured ==")
local function rightClick(allow, startHolstered)
  engineSet("lps_allow_holster", allow and 1 or 0)
  _G.CURTIME = _G.CURTIME + 5
  local pl = lpsProp("smg", 300)
  if startHolstered then pl:SetLPSWeaponState(LPS_WEAPON_HOLSTER) end
  tick(pl, {}, { [IN_ATTACK2] = true })
  return pl:GetLPSWeaponState()
end
check("allowed: right-click holsters (normal play)", rightClick(true), LPS_WEAPON_HOLSTER)
check("allowed: right-click unholsters (normal play)", rightClick(true, true), LPS_WEAPON_READY)
check("disallowed: right-click does not holster", rightClick(false), LPS_WEAPON_READY)
check("disallowed: an already-holstered prop can unholster", rightClick(false, true), LPS_WEAPON_READY)
check("disallowed: left-click still fires", shoot("smg", 5):GetLPSAmmo(), 4)
engineSet("lps_allow_holster", 1)

print("\n== #54 weapon cooldown timers leave a holstered gun alone ==")
local function cooldown(weapon, ammo, holdFire, holster, wait)
  _G.CURTIME = _G.CURTIME + 10
  S.timers = {}
  local pl = lpsProp(weapon, ammo)
  tick(pl, { [IN_ATTACK] = true })                                   -- fire
  _G.CURTIME = _G.CURTIME + 0.1
  if holdFire then tick(pl, { [IN_ATTACK] = true }) end              -- held through the cooldown
  if holster then tick(pl, {}, { [IN_ATTACK2] = true }) end          -- released, then right-click
  local errs = S.pump(wait)
  return { state = pl:GetLPSWeaponState(), err = errs[1] }
end
local cd = cooldown("blaster", -1, false, true, 3.1)
check("blaster: holstered after the shot stays holstered", cd.state, LPS_WEAPON_HOLSTER)
check("blaster: timers run without error", cd.err, nil)
check("blaster: held fire -> RELOAD -> READY after cooldown (normal play)", cooldown("blaster", -1, true, false, 3.1).state, LPS_WEAPON_READY)
check("rocket: last rocket, holstered, stays holstered", cooldown("rocket", 1, false, true, 1.6).state, LPS_WEAPON_HOLSTER)
check("rocket: held fire -> READY after cooldown (normal play)", cooldown("rocket", 5, true, false, 1.6).state, LPS_WEAPON_READY)
check("rocket: last rocket, not holstered -> OUTOFAMMO (normal play)", cooldown("rocket", 1, true, false, 1.6).state, LPS_WEAPON_OUTOFAMMO)

print("\n== #190/#220 lps_start_every_x_rounds is not capped at the load-time round count ==")
engineSet("ph_rounds_per_map", 20)           -- server.cfg runs after the plugin loaded
engineSet("lps_start_every_x_rounds", 15)
-- tonumber: the plugin's own callback hands SetGlobalInt the raw string, which GMod coerces.
check("lps_start_every_x_rounds 15 with 20 rounds per map -> 15", tonumber(PHX:GetCVar("lps_start_every_x_rounds")), 15)
engineSet("lps_start_every_x_rounds", 1)
check("min 2 still enforced (normal)", tonumber(PHX:GetCVar("lps_start_every_x_rounds")), 2)

-- A round in which every prop but one dies after the hunters are released.
engineSet("lps_weapon", "smg")
local function round(rn, props)
  S.timers = {}
  S.fire("PostCleanupMap")
  SetGlobalInt("RoundNumber", rn); SetGlobalBool("InRound", true)
  local ps = {}
  for i = 1, props or 2 do ps[i] = S.Player{ team = TEAM_PROPS, name = "prop" .. i } end
  S.players = { S.Player{ team = TEAM_HUNTERS } }
  for _, pl in ipairs(ps) do S.players[#S.players + 1] = pl end
  S.fire("PH_BlindTimeOver")
  local errs = S.pump(1)
  for i = 2, #ps do ps[i]._alive = false; S.fire("PostPlayerDeath", ps[i]) end
  for _, e in ipairs(S.pump(0.6)) do errs[#errs + 1] = e end
  for _, e in ipairs(S.pump(0)) do errs[#errs + 1] = e end
  local fired = ps[1]:IsLastStanding()
  S.fire("PH_RoundEnd")
  return { fired = fired, errs = errs, prop = ps[1] }
end

print("\n== #52 'every X rounds' survives a round without LPS ==")
engineSet("lps_start_every_x_rounds", 2); engineSet("lps_start_delayed_rounds", 1)
PHX.LPS.ROUND_LEFT = 2                       -- as the cvar callback leaves it, enabled at round 0
local fired = {}
for rn = 2, 6 do fired[rn] = round(rn).fired end
check("cadence 2: round 2 fires (normal play)", fired[2], true)
check("cadence 2: round 3 does not (normal play)", fired[3], false)
check("cadence 2: round 4 fires (normal play)", fired[4], true)
check("cadence 2: round 6 fires (normal play)", fired[6], true)
PHX.LPS.ROUND_LEFT = 2
fired = {}
fired[2] = round(2, 1).fired                 -- only one prop: nobody dies, no LPS this round
for rn = 3, 8 do fired[rn] = round(rn).fired end
check("round 2 missed -> round 3 still off-cadence", fired[3], false)
check("round 2 missed -> round 4 fires", fired[4], true)
check("round 2 missed -> round 5 does not", fired[5], false)
check("round 2 missed -> round 6 fires", fired[6], true)
check("round 2 missed -> round 8 fires", fired[8], true)
engineSet("lps_start_delayed_rounds", 0)
check("no trigger mode: every round fires (normal play)", round(9).fired and round(10).fired, true)

print("\n== #187 a survivor of the hiding phase gets LPS when hunters are released ==")
local function hidingDeath(enable)
  engineSet("lps_enable", enable and 1 or 0)
  S.timers = {}
  S.fire("PostCleanupMap")                    -- LPSAllowed = false: hunters are blind
  SetGlobalInt("RoundNumber", 20); SetGlobalBool("InRound", true)
  local a, b, c = S.Player{ team = TEAM_PROPS }, S.Player{ team = TEAM_PROPS }, S.Player{ team = TEAM_PROPS }
  S.players = { S.Player{ team = TEAM_HUNTERS }, a, b, c }
  S.players[4] = nil; S.fire("PlayerDisconnected", c)
  b._alive = false; S.fire("PostPlayerDeath", b)
  S.pump(0.6)
  local before = a:IsLastStanding()
  S.fire("PH_BlindTimeOver")
  local errs = S.pump(0.6); S.pump(0)
  local after = a:IsLastStanding()
  S.fire("PH_RoundEnd")
  return { before = before, after = after, err = errs[1] }
end
local hd = hidingDeath(true)
check("no LPS while hunters are still blind (normal)", hd.before, false)
check("LPS starts once hunters are released", hd.after, true)
check("  ...without error", hd.err, nil)
check("lps_enable 0 -> still no LPS at release (normal)", hidingDeath(false).after, false)
engineSet("lps_enable", 1)
check("one-prop team never gets LPS at release (normal)", round(21, 1).fired, false)

print("\n== #185 no alert/music files mounted ==")
local r22 = round(22)
check("LPS starts with no sound files", r22.fired, true)
check("  ...and nothing errors", r22.errs[1], nil)
local musicErrs = S.pump(1)
check("music timer with no music files does not error", musicErrs[1], nil)
check("  ...and the dummy weapon was still given", r22.prop.weapons[1], "weapon_lps")
local lone = S.Player{ team = TEAM_PROPS }
S.players = { lone }
check("CreateSound with no music files does not error", attempt(PHX.LPS.CreateSound, PHX.LPS, lone), "ok")
check("  ...and schedules no replay", timer.Exists("tmr_LPSMusic"), false)
PHX.LPS.SOUND.ALERT = { { sound = "lps/alert/a.wav", Len = 2 } }
PHX.LPS.SOUND.MUSIC = { { sound = "lps/music/m.mp3", Len = 60 } }
S.worldSounds, S.music = {}, {}
S.timers = {}
S.fire("PostCleanupMap")
SetGlobalInt("RoundNumber", 23)
local a2, b2 = S.Player{ team = TEAM_PROPS }, S.Player{ team = TEAM_PROPS }
a2._info.lps_cl_listen_music = 1
S.players = { S.Player{ team = TEAM_HUNTERS }, a2, b2 }
S.fire("PH_BlindTimeOver"); S.pump(1)
b2._alive = false; S.fire("PostPlayerDeath", b2); S.pump(0.6); S.pump(0)
check("alert plays when mounted (normal play)", S.worldSounds[1], "lps/alert/a.wav")
check("music waits for the alert (normal play)", #S.music, 0)
local mErrs = S.pump(2.1)
check("music starts after the alert (normal play)", S.music[1], "lps/music/m.mp3")
check("  ...without error", mErrs[1], nil)
S.fire("PH_RoundEnd")
PHX.LPS.SOUND.ALERT, PHX.LPS.SOUND.MUSIC = {}, {}

print("\n== #189 the deferred dummy-weapon Give survives a disconnect ==")
local function giveTick(disconnect, die)
  S.timers = {}
  S.fire("PostCleanupMap")
  SetGlobalInt("RoundNumber", 30)
  local a, b = S.Player{ team = TEAM_PROPS }, S.Player{ team = TEAM_PROPS }
  S.players = { S.Player{ team = TEAM_HUNTERS }, a, b }
  S.fire("PH_BlindTimeOver"); S.pump(1)
  b._alive = false; S.fire("PostPlayerDeath", b)
  S.pump(0.6)                                  -- a is made the last prop; Give is queued
  if disconnect then
    -- A disconnected player's Lua object turns NULL: every method call raises.
    table.remove(S.players, 2)
    rawset(a, "__valid", false); setmetatable(a, getmetatable(NULL))
  end
  if die then a._alive = false end
  local tickErrs = S.pump(0)
  S.fire("PH_RoundEnd")
  SetGlobalBool("LPS.InLastPropStanding", false)   -- a NULL'd last prop can't be reset by PH_RoundEnd
  return { err = tickErrs[1], weapons = rawget(a, "weapons") }
end
check("last prop disconnects before the Give tick -> no error", giveTick(true).err, nil)
local gt = giveTick(false)
check("normal: Give tick runs without error", gt.err, nil)
check("normal: last prop receives the dummy weapon", gt.weapons[1], "weapon_lps")
check("last prop died before the Give tick -> no weapon", giveTick(false, true).weapons[1], nil)

report()
