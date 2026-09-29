dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- Hunter SWEPs and the LPS blaster effects, run from the shipped entity files.
local WEP = "gamemodes/prop_hunt/entities/weapons/"
local FX = "gamemodes/prop_hunt/entities/effects/"

-- Engine pieces shim.lua leaves out (kept here: shim.lua is shared with other branches).
math.Rand = function(low, high) return low + (high - low) * math.random() end
function AddCSLuaFile() end
function Model(m) return m end
function Sound(s) return s end
function Material() return { SetInt = function() end, SetFloat = function() end } end
function SuppressHostEvents() end
function AngleRand() return Angle(0, 0, 0) end
effects = { BeamRingPoint = function() end }
render = setmetatable({}, { __index = function() return function() end end })
-- GMod's Vector(v) copies a vector; the shim's Vector only takes numbers.
local ShimVector = Vector
function Vector(x, y, z)
  if type(x) == "table" then return ShimVector(x.x, x.y, x.z) end
  return ShimVector(x, y, z)
end
-- OrderVectors swaps components in place so that every axis of b >= a.
function OrderVectors(a, b)
  for _, k in ipairs{ "x", "y", "z" } do if a[k] > b[k] then a[k], b[k] = b[k], a[k] end end
end
S.created = {}
ents.Create = function(c)
  local e = { cls = c, __valid = true }
  function e.SetAngles(self, a) self.ang = a end
  S.created[#S.created + 1] = setmetatable(e, { __index = function() return function() end end })
  return e
end

-- A weapon instance: the SWEP table plus the engine (C) weapon methods and the few
-- weapon_base helpers these SWEPs lean on, copied from garrysmod's weapon_base/shared.lua.
local function weapon(swep, st)
  local w = setmetatable({ clip1 = st.clip1 or 0, clip2 = st.clip2 or 0, ammo1 = st.ammo1 or 0,
                           ammo2 = st.ammo2 or 0, nextP = 0, nextS = 0, sounds = {}, owner = st.owner },
                         { __index = swep })
  function w:Clip1() return self.clip1 end
  function w:Clip2() return self.clip2 end
  function w:Ammo1() return self.ammo1 end
  function w:Ammo2() return self.ammo2 end
  function w:GetMaxClip1() return self.Primary.ClipSize end
  function w:GetOwner() return self.owner end
  function w:GetSecondaryAmmoType() return 2 end
  function w:SetNextPrimaryFire(t) self.nextP = t end
  function w:SetNextSecondaryFire(t) self.nextS = t end
  function w:EmitSound(s) self.sounds[#self.sounds + 1] = s end
  function w:SendWeaponAnim() end
  function w:ShootEffects() end
  function w:ShootBullet() end
  function w:TakePrimaryAmmo(n) self.clip1 = self.clip1 - n end
  function w:SetDeploySpeed() end
  -- Source's CBaseCombatWeapon::DefaultReload: nothing happens (false) without reserve ammo
  -- or with a full clip; otherwise the reload runs and the next-fire times follow its animation.
  function w:DefaultReload()
    if self.ammo1 <= 0 or self.clip1 >= self.Primary.ClipSize then return false end
    local take = math.min(self.Primary.ClipSize - self.clip1, self.ammo1)
    self.clip1, self.ammo1 = self.clip1 + take, self.ammo1 - take
    self.nextP, self.nextS = CurTime() + 1.5, CurTime() + 1.5
    return true
  end
  -- weapon_base
  function w:CanPrimaryAttack()
    if self:Clip1() <= 0 then
      self:EmitSound("Weapon_Pistol.Empty"); self:SetNextPrimaryFire(CurTime() + 0.2); self:Reload()
      return false
    end
    return true
  end
  function w:CanSecondaryAttack()
    if self:Clip2() <= 0 then
      self:EmitSound("Weapon_Pistol.Empty"); self:SetNextSecondaryFire(CurTime() + 0.2)
      return false
    end
    return true
  end
  return w
end
local function owner()
  local o = { __valid = true, punches = {} }
  function o.GetPos() return Vector(0, 0, 0) end
  function o.GetShootPos() return Vector(0, 0, 64) end
  function o.GetAimVector() return Vector(1, 0, 0) end
  function o.EyeAngles() return Angle(0, 0, 0) end
  function o.SetVelocity() end
  function o.ViewPunch(self, a) self.punches[#self.punches + 1] = a end
  function o.RemoveAmmo(self, n) self.wep.ammo2 = self.wep.ammo2 - n end
  return o
end
local function loadSWEP(file)
  SWEP = { Primary = {}, Secondary = {} }
  loadblocks(file, extract(WEP .. file, "1-99999"))
  return SWEP
end

print("\n== #70 flechette gun: R with nothing to reload is not a 3 s lockout ==")
local FCHET = loadSWEP("weapon_fchet.lua")
local function reload(clip, reserve)
  local w = weapon(FCHET, { clip1 = clip, clip2 = 1, ammo1 = reserve, ammo2 = 1 })
  w:Reload()
  return w
end
local w = reload(30, 0)
check("full clip: no fire lockout", w.nextP, 0)
check("full clip: no reload sound", #w.sounds, 0)
w = reload(25, 0)
check("25/30, no reserve (as issued): no fire lockout", w.nextP, 0)
check("25/30, no reserve: no secondary lockout", w.nextS, 0)
check("25/30, no reserve: no reload sound", #w.sounds, 0)
w = weapon(FCHET, { clip1 = 0, clip2 = 1, ammo1 = 0 })
w:PrimaryAttack()
check("empty clip: only weapon_base's 0.2 s empty-click delay", w.nextP, CurTime() + 0.2)
w = reload(25, 60)
check("with reserve: reload still happens (normal play)", w.clip1, 30)
check("with reserve: reload sound plays (normal play)", w.sounds[1], "wlv.guardgun_reload")

print("\n== #208 flechette ring: 12 flechettes, one per 30 degrees ==")
S.created = {}
local ply = owner()
w = weapon(FCHET, { clip1 = 30, clip2 = 1, ammo2 = 1, owner = ply })
ply.wep = w
w:SecondaryAttack()
local yaws, n, maxYaw = {}, 0, -1
for _, e in ipairs(S.created) do
  if e.cls == "hunter_flechette" then
    n = n + 1; yaws[e.ang.y] = true; if e.ang.y > maxYaw then maxYaw = e.ang.y end
  end
end
check("ring fires 12 flechettes", n, 12)
check("ring has 12 distinct headings", table.Count(yaws), 12)
check("ring still starts at 0 (normal play)", yaws[0], true)
check("ring ends at 330", maxYaw, 330)
check("secondary still consumes its charge (normal play)", w.ammo2, 0)

print("\n== #205 underwater SMG: the grenade it is issued can be fired ==")
local SMGW = loadSWEP("weapon_smg1_water.lua")
-- Source's CBaseCombatCharacter::Weapon_Equip: with no clip (ClipSize -1) the whole
-- DefaultClip goes to reserve; with a clip it fills the clip and reserves only the rest.
local function equip(t)
  if t.ClipSize == -1 then return -1, t.DefaultClip end
  local clip = math.min(t.DefaultClip, t.ClipSize)
  return clip, t.DefaultClip - clip
end
local c2, a2 = equip(SMGW.Secondary)
S.created = {}
ply = owner()
w = weapon(SMGW, { clip1 = 45, clip2 = c2, ammo2 = a2, owner = ply })
ply.wep = w
w:SecondaryAttack()
check("first right-click launches a grenade", #S.created, 1)
check("  ...with the launch sound", w.sounds[1], "NPC_Combine.GrenadeLaunch")
_G.CURTIME = _G.CURTIME + 2
w:SecondaryAttack()
check("second right-click: only one grenade issued, no second launch", #S.created, 1)
check("  ...empty click", w.sounds[2], "Weapon_Pistol.Empty")
local p1, r1 = equip(SMGW.Primary)
check("primary still issues 45 + 180 (normal)", p1 == 45 and r1 == 180, true)

print("\n== #206/#207 BREN (base mode): recoil range and Deploy ==")
-- The base-mode functions only, from inside wlv_bren.lua's `else` branch.
local BREN = { Primary = { Sound = "BREN.Fire" } }
loadchunk("local SWEP = ...\n" .. extractAll(WEP .. "wlv_bren.lua", {
  [[function SWEP:PrimaryAttack\(\)]], [[function SWEP:Deploy\(\)]] }), "wlv_bren.lua@base")(BREN)
ply = owner()
w = weapon(BREN, { clip1 = 30, owner = ply })
local inRange, distinct = true, {}
for _ = 1, 3000 do
  w.clip1 = 30
  w:PrimaryAttack()
end
for _, a in ipairs(ply.punches) do
  if a.p < -0.7 or a.p > -0.2 or a.y < -0.1 or a.y > 0.1 then inRange = false end
  distinct[a.p] = true
end
check("3000 shots fired (normal play)", #ply.punches, 3000)
check("recoil pitch stays in -0.7..-0.2, yaw in -0.1..0.1", inRange, true)
check("recoil actually varies", table.Count(distinct) > 50, true)
check("Deploy returns true", w:Deploy(), true)

-- Effects ------------------------------------------------------------------
local function loadEffect(dir)
  EFFECT = {}
  loadblocks(dir, extract(FX .. dir .. "/init.lua", "1-99999"))
  local E = EFFECT
  return function()
    local inst = setmetatable({}, { __index = E })
    function inst.SetRenderBoundsWS(self, mins, maxs) self.bounds = { mins, maxs } end
    return inst
  end
end
local MUZZLE, HIT = Vector(0, 0, 50), Vector(-500, 300, -20)
local function gunEnt(hasAttachment)
  local shooter = { __valid = true }
  local e = { __valid = true }
  function e.GetAttachment() if hasAttachment then return { Pos = Vector(MUZZLE) } end end
  function e.GetOwner() return shooter end
  function shooter.GetLPSWeaponEntity() return e end
  function shooter.GetEyeTrace() return { HitPos = Vector(HIT) } end
  function shooter.GetAimVector() return Vector(1, 0, 0) end
  return e
end
local function fxData(ent, origin)
  return { GetEntity = function() return ent end, GetAttachment = function() return 1 end,
           GetOrigin = function() return origin end, GetNormal = function() return Vector(0, 0, 1) end }
end
-- Bounds are ordered, and reach `pad` past every corner of the box spanned by a and b.
-- (1e-6 slack: fire's Render recomputes the muzzle as EndPos + dir * dist.)
local function covers(fx, a, b, pad)
  if not fx.bounds then return "no bounds set" end
  local mins, maxs = fx.bounds[1], fx.bounds[2]
  pad = pad - 1e-6
  for _, k in ipairs{ "x", "y", "z" } do
    if mins[k] > math.min(a[k], b[k]) - pad or maxs[k] < math.max(a[k], b[k]) + pad then
      return ("%s: %g..%g"):format(k, mins[k], maxs[k])
    end
  end
  return "ok"
end

print("\n== #203 blaster fire/muzzle effects with no muzzle attachment ==")
local newFire, newMuzzle = loadEffect("phx_blaster_fire"), loadEffect("phx_blaster_muzzle")
local fx = newFire()
check("fire: Init without attachment does not error", attempt(fx.Init, fx, fxData(gunEnt(false), Vector(HIT))), "ok")
check("fire: ...and the effect ends", fx:Think(), false)
fx = newMuzzle()
check("muzzle: Init without attachment does not error", attempt(fx.Init, fx, fxData(gunEnt(false))), "ok")
check("muzzle: ...and the effect ends", fx:Think(), false)
fx = newFire(); fx:Init(fxData(gunEnt(true), Vector(HIT)))
check("fire: with attachment it renders (normal play)", fx.ShouldRender, true)
fx = newMuzzle(); fx:Init(fxData(gunEnt(true)))
check("muzzle: with attachment it renders (normal play)", fx.ShouldRender, true)

print("\n== #209 blaster effects get real, ordered render bounds ==")
local newCharge, newExplode = loadEffect("phx_blaster_charge"), loadEffect("phx_blaster_explode")
fx = newCharge(); fx:Init(fxData(gunEnt(true)))
check("charge Init: bounds cover muzzle..hit + 280", covers(fx, MUZZLE, HIT, 280), "ok")
fx.bounds = nil; fx:Render()
check("charge Render: bounds cover muzzle..hit + 280", covers(fx, MUZZLE, HIT, 280), "ok")
fx = newFire(); fx:Init(fxData(gunEnt(true), Vector(HIT)))
check("fire Init: bounds cover muzzle..hit + 280", covers(fx, MUZZLE, HIT, 280), "ok")
fx.bounds = nil; fx:Render()
check("fire Render: bounds cover muzzle..hit + 280", covers(fx, MUZZLE, HIT, 280), "ok")
fx = newMuzzle(); fx:Init(fxData(gunEnt(true)))
check("muzzle Init: bounds cover the muzzle + 55", covers(fx, MUZZLE, MUZZLE, 55), "ok")
fx.bounds = nil; fx:Render()
check("muzzle Render: bounds cover the muzzle + 55", covers(fx, MUZZLE, MUZZLE, 55), "ok")
fx = newExplode()
fx.Position, fx.KillTime = Vector(HIT), CurTime() + 0.3
fx:Render()
local size = 280 + 200 * (1 - 0.3 / 0.65)
check("explode Render: bounds cover the growing sprite", covers(fx, HIT, HIT, size), "ok")

report()
