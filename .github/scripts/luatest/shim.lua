-- Minimal Garry's Mod runtime, enough to execute extracted PH:X functions under
-- LuaJIT (the same Lua 5.1 dialect GMod runs).
--
-- Two details here are load-bearing, because getting either wrong makes tests
-- pass against broken code:
--   * S.boolCVar declares a CTYPE_BOOL convar so PHX:GetCVar hands back a real
--     boolean. In Lua the number 0 is TRUTHY, so returning tonumber("0") from a
--     boolean convar silently inverts every `if cvar then` guard.
--   * NULL raises on write as well as read, exactly as GMod does. An
--     __index-only mock lets `NULL.field = 1` succeed and hides the bug.
local S = {}

TEAM_HUNTERS, TEAM_PROPS = 1, 2
TEAM_SPECTATOR, TEAM_UNASSIGNED, TEAM_CONNECTING = 1002, 1001, 0
MOUSE_RIGHT, MOUSE_MIDDLE = 107, 108
KEY_F3, KEY_C, KEY_R, KEY_M, KEY_N, KEY_1, KEY_F6, KEY_F8 = 63, 46, 61, 56, 57, 2, 66, 68
FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED = 128, 256, 8192
FCVAR_DONTRECORD, FCVAR_USERINFO, FCVAR_SERVER_CAN_EXECUTE = 4096, 512, 16384
MASK_PLAYERSOLID, CONTENTS_PLAYERCLIP = 33636363, 0x10000
SERVER, CLIENT = true, false

_G.CURTIME = 1000
function CurTime() return _G.CURTIME end

NULL = setmetatable({ __valid = false }, {
  __index    = function(_, k) error("Tried to use a NULL entity! (read " .. tostring(k) .. ")", 2) end,
  __newindex = function(_, k) error("Tried to use a NULL entity! (write " .. tostring(k) .. ")", 2) end })
S.NULL = NULL
function IsValid(e) return e ~= nil and e ~= NULL and e.__valid ~= false end

function isnumber(v) return type(v) == "number" end
function isstring(v) return type(v) == "string" end
function istable(v) return type(v) == "table" end
function isbool(v) return type(v) == "boolean" end
function isvector(v) return type(v) == "table" and v.x ~= nil end
function tobool(v)
  if v == nil or v == false or v == 0 or v == "0" or v == "false" then return false end
  return true
end
function ErrorNoHalt(...) S.errors = (S.errors or 0) + 1 end
function ErrorNoHaltWithStack(...) S.errors = (S.errors or 0) + 1 end
function MsgN() end
function MsgC() end
function Msg() end
function MsgAll() end

math.Clamp = function(v, lo, hi) if v < lo then return lo elseif v > hi then return hi else return v end end
math.Round = function(v, d) d = d or 0; local m = 10 ^ d; return math.floor(v * m + 0.5) / m end
math.Max, math.Min = math.max, math.min

table.Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
table.IsEmpty = function(t) return next(t) == nil end
table.HasValue = function(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
table.GetKeys = function(t) local r = {} for k in pairs(t) do r[#r + 1] = k end return r end
table.Random = function(t) local k = table.GetKeys(t); if #k == 0 then return nil end return t[k[math.random(#k)]] end
table.Copy = function(t) local r = {} for k, v in pairs(t) do r[k] = type(v) == "table" and table.Copy(v) or v end return r end
table.Add = function(d, s) for _, v in ipairs(s) do d[#d + 1] = v end return d end
table.RemoveByValue = function(t, v) for i, x in ipairs(t) do if x == v then table.remove(t, i) return i end end return false end
table.GetWinningKey = function(t) local bk, bv for k, v in pairs(t) do if bv == nil or v > bv then bk, bv = k, v end end return bk end
table.CustomShuffle = function(a) local c = #a while c > 1 do local i = math.random(c); a[i], a[c] = a[c], a[i]; c = c - 1 end end
SortedPairs, RandomPairs = pairs, pairs

S.hooks = {}
hook = {}
function hook.Add(ev, name, fn) S.hooks[ev] = S.hooks[ev] or {}; S.hooks[ev][name] = fn end
function hook.Remove(ev, name) if S.hooks[ev] then S.hooks[ev][name] = nil end end
function hook.Run(ev, ...) if S.hooks[ev] then for _, f in pairs(S.hooks[ev]) do local r = f(...) if r ~= nil then return r end end end end
function hook.Call(ev, _, ...) return hook.Run(ev, ...) end
function S.fire(ev, ...) return hook.Run(ev, ...) end

S.timers = {}
timer = {}
function timer.Simple(d, fn) S.timers[#S.timers + 1] = { fn = fn, at = _G.CURTIME + d } end
function timer.Create(id, d, _, fn) S.timers[#S.timers + 1] = { id = id, fn = fn, at = _G.CURTIME + d } end
function timer.Remove(id) for i = #S.timers, 1, -1 do if S.timers[i].id == id then table.remove(S.timers, i) end end end
function timer.Exists(id) for _, t in ipairs(S.timers) do if t.id == id then return true end end return false end
function timer.Pause() end
function timer.Adjust() end
function S.pump(advance)
  _G.CURTIME = _G.CURTIME + (advance or 0)
  local due, keep = {}, {}
  for _, t in ipairs(S.timers) do if t.at <= _G.CURTIME then due[#due + 1] = t else keep[#keep + 1] = t end end
  S.timers = keep
  local errs = {}
  for _, t in ipairs(due) do
    local ok, err = pcall(t.fn)
    if not ok then errs[#errs + 1] = tostring(err) end
  end
  return errs
end

S.concommands = {}
concommand = { Add = function(n, fn, _, help) S.concommands[n] = { fn = fn, help = help } end }

S.net = { sent = {} }
net = {}
function net.Start(n) S.net.cur = { name = n, data = {} } end
local function w(v) table.insert(S.net.cur.data, v) end
net.WriteString, net.WriteBool, net.WriteUInt, net.WriteInt = w, w, w, w
net.WriteFloat, net.WriteData, net.WriteEntity, net.WriteVector = w, w, w, w
net.WriteTable, net.WriteColor = w, w
function net.Send(p) S.net.cur.to = p; table.insert(S.net.sent, S.net.cur) end
function net.Broadcast() S.net.cur.to = "all"; table.insert(S.net.sent, S.net.cur) end
S.receivers = {}
function net.Receive(n, fn) S.receivers[n] = fn end
local function r() return S.net.readq and table.remove(S.net.readq, 1) end
net.ReadString, net.ReadBool, net.ReadUInt, net.ReadInt = r, r, r, r

util = {}
function util.AddNetworkString(n) return n end
util.TraceHull = function(t) return { Hit = S.traceHits == true, HitPos = (t and t.start) or Vector(0, 0, 0), Contents = 0, HitSky = false } end
util.TraceLine = function(t) return { Hit = S.traceHits == true, HitPos = (t and t.start) or Vector(0, 0, 0), Contents = 0, HitSky = false, Entity = NULL } end
util.PointContents = function() return 0 end
util.JSONToTable = function(s) return S.json and S.json[s] or nil end
util.TableToJSON = function() return "{}" end
util.Compress = function(s) return s end
util.Decompress = function(s) return s end
util.KeyValuesToTable = function() return {} end
util.ToMinutesSeconds = function(s) return string.format("%02d:%02d", math.floor(s / 60), math.floor(s % 60)) end

S.http = { calls = {} }
http = { Fetch = function(url) table.insert(S.http.calls, url) end }

S.players = {}
team = {}
function team.GetPlayers(id) local r = {} for _, p in ipairs(S.players) do if p:Team() == id then r[#r + 1] = p end end return r end
function team.NumPlayers(id) return #team.GetPlayers(id) end
function team.GetName(id) return ({ [1] = "Hunters", [2] = "Props" })[id] or ("team" .. tostring(id)) end
function team.GetColor() return { r = 255, g = 255, b = 255 } end
function team.GetAllTeams() return { [1] = {}, [2] = {} } end
function team.Joinable() return true end
function team.SetScore() end
function team.GetScore() return 0 end
function team.BestAutoJoinTeam() return TEAM_PROPS end
player = {}
function player.GetAll() return S.players end
function player.GetCount() return #S.players end
function player.GetHumans() return S.players end

local VecMeta = {}
VecMeta.__index = VecMeta
VecMeta.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
VecMeta.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
VecMeta.__unm = function(a) return Vector(-a.x, -a.y, -a.z) end
VecMeta.__mul = function(a, b)
  if type(b) == "number" then return Vector(a.x * b, a.y * b, a.z * b) end
  if type(a) == "number" then return Vector(b.x * a, b.y * a, b.z * a) end
  return Vector(a.x * b.x, a.y * b.y, a.z * b.z)
end
VecMeta.__div = function(a, b) return Vector(a.x / b, a.y / b, a.z / b) end
VecMeta.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
VecMeta.__tostring = function(a) return ("[%g %g %g]"):format(a.x, a.y, a.z) end
function VecMeta:Unpack() return self.x, self.y, self.z end
function VecMeta:DistToSqr(o) local dx, dy, dz = self.x - o.x, self.y - o.y, self.z - o.z return dx * dx + dy * dy + dz * dz end
function VecMeta:Distance(o) return math.sqrt(self:DistToSqr(o)) end
function VecMeta:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function VecMeta:Rotate() end
function VecMeta:ToScreen() return { x = 0, y = 0 } end
function Vector(x, y, z)
  if type(x) == "string" then
    local a, b, c = x:match("(%S+)%s+(%S+)%s+(%S+)")
    x, y, z = tonumber(a), tonumber(b), tonumber(c)
  end
  return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VecMeta)
end
local AngMeta = { __index = { Forward = function() return Vector(1, 0, 0) end,
                              Right = function() return Vector(0, 1, 0) end,
                              Up = function() return Vector(0, 0, 1) end } }
function Angle(p, y, r2) return setmetatable({ p = p or 0, y = y or 0, r = r2 or 0 }, AngMeta) end
vector_origin, angle_zero = Vector(0, 0, 0), Angle(0, 0, 0)
function Color(r2, g, b, a) return { r = r2, g = g, b = b, a = a or 255 } end
color_white = Color(255, 255, 255)

game = { IsDedicated = function() return true end, MaxPlayers = function() return 32 end,
         GetMap = function() return "ph_test" end, CleanUpMap = function() end,
         SinglePlayer = function() return false end, KickID = function() end,
         ConsoleCommand = function() end, AddParticles = function() end }
engine = { ActiveGamemode = function() return "prop_hunt" end, GetAddons = function() return {} end }
navmesh = { GetPlayerSpawnName = function() return "info_player_start" end }
S.entsByClass = {}
ents = { FindByClass = function(c) return S.entsByClass[c] or {} end,
         FindByModel = function() return {} end,
         Create = function(c)
           if S.entsCreateFails then return NULL end
           return setmetatable({ __cls = c, __valid = true }, { __index = function() return function() end end })
         end }
S.resources = {}
resource = { AddFile = function(f) table.insert(S.resources, f) end, AddWorkshop = function() end }
list = { Get = function() return {} end, Set = function() end }
S.fileExists = {}
file = { Exists = function(n) return S.fileExists[n] == true end, Read = function() return nil end,
         Write = function() end, Find = function() return {}, {} end, Size = function() return 0 end,
         CreateDir = function() end, Delete = function() end }
cookie = { GetNumber = function(_, d) return d or 0 end, Set = function() end }
SafeRemoveEntityDelayed = function() end
player_manager = { TranslatePlayerModel = function(m) return m end,
                   TranslateToPlayerModelName = function() return "mdl" end }
player_class = { Register = function(n, c) S.classes = S.classes or {}; S.classes[n] = c end }
sound = { Add = function() end }
if not bit then bit = { bor = function(a) return a end, band = function() return 0 end } end

S.globals = {}
function SetGlobalInt(k, v) S.globals[k] = v end
function SetGlobalBool(k, v) S.globals[k] = v end
function SetGlobalFloat(k, v) S.globals[k] = v end
function SetGlobalString(k, v) S.globals[k] = v end
function SetGlobalEntity(k, v) S.globals[k] = v end
local function getg(k, d) local v = S.globals[k]; if v == nil then return d end return v end
GetGlobalInt, GetGlobalBool, GetGlobalFloat, GetGlobalString = getg, getg, getg, getg

S.cvars, S.cvarcb, S.boolcvars = {}, {}, {}
function CreateConVar(n, v, _, _, mn, mx)
  S.cvars[n] = { v = v, min = mn, max = mx }
  return GetConVar(n)
end
function GetConVar(n)
  if not S.cvars[n] then return nil end
  return { GetBool = function() return tobool(S.cvars[n].v) end,
           GetInt = function() return math.floor(tonumber(S.cvars[n].v) or 0) end,
           GetFloat = function() return tonumber(S.cvars[n].v) or 0 end,
           GetString = function() return tostring(S.cvars[n].v) end,
           GetMin = function() return S.cvars[n].min end,
           GetMax = function() return S.cvars[n].max end,
           GetHelpText = function() return "" end }
end
function ConVarExists(n) return S.cvars[n] ~= nil end
function RunConsoleCommand(n, v)
  if S.cvars[n] then local old = S.cvars[n].v; S.cvars[n].v = v; S.fireCvar(n, old, v) end
end
-- Registration ORDER matters and GMod preserves it, so keep an ordered list
-- rather than a keyed table. A duplicate identifier replaces in place, as GMod
-- does, instead of appending a second callback.
cvars = { AddChangeCallback = function(n, fn, id)
  S.cvarcb[n] = S.cvarcb[n] or {}
  local list = S.cvarcb[n]
  for _, e in ipairs(list) do
    if id and e.id == id then e.fn = fn; return end
  end
  list[#list + 1] = { id = id, fn = fn }
end }
function S.fireCvar(n, old, new)
  if not S.cvarcb[n] then return end
  for _, e in ipairs(S.cvarcb[n]) do e.fn(n, old, new) end
end

-- Declare a CTYPE_BOOL convar. See the note at the top of this file.
function S.boolCVar(n, v) CreateConVar(n, v); S.boolcvars[n] = true end

PHX = { CachedTaunts = { [1] = {}, [2] = {} }, TAUNTS = {}, LANGUAGES = { en_us = {} },
        ConfigPath = "phx_data", VERSION = "X2Z", REVISION = "rev",
        SVAdmins = { superadmin = true }, PROP_PLMODEL_BANS = {} }
function PHX:VerboseMsg() end
function PHX:GetCVar(n)
  local c = S.cvars[n]; if not c then return nil end
  if S.boolcvars[n] then return tobool(c.v) end
  return tonumber(c.v) or c.v
end
function PHX:QCVar(n) return PHX:GetCVar(n) end
function PHX:SVTranslate(_, id) return id end
function PHX:Translate(id) return id end
function PHX:FTranslate(id) return id end
function PHX:TranslateName(id) return team.GetName(id) end
function PHX:IsBlindStatus() return GetGlobalBool("PHX.BlindStatus", false) end
function PHX:SetBlindStatus(b) SetGlobalBool("PHX.BlindStatus", tobool(b)) end
S.taunts = {}
function PHX:PlayTaunt(...) table.insert(S.taunts, { ... }) end
function PHX:AddToCache() end
function PHX:CheckCache() end

GAMEMODE = { InRound = function() return GetGlobalBool("InRound", true) end,
             UPDATEURL = "http://example/update", UPDATEURLBACKUP = "http://example/backup",
             _VERSION = "X2Z", REVISION = "rev", ViewCam = {} }
GM = GAMEMODE
util.IsStaff = function(ply) return (game.IsDedicated() and ply == NULL) or (ply ~= NULL and ply:PHXIsStaff()) end

local PlyMeta = {}
PlyMeta.__index = PlyMeta
function PlyMeta:Team() return self._team end
function PlyMeta:Alive() return self._alive end
function PlyMeta:Nick() return self._name end
function PlyMeta:Name() return self._name end
function PlyMeta:GetName() return self._name end
function PlyMeta:SteamID() return self._sid end
function PlyMeta:IsBot() return self._bot == true end
function PlyMeta:IsPlayer() return true end
function PlyMeta:IsValid() return true end
function PlyMeta:EntIndex() return self._idx or 1 end
function PlyMeta:IsSuperAdmin() return self._staff == true end
function PlyMeta:GetUserGroup() return self._staff and "superadmin" or "user" end
function PlyMeta:CheckUserGroup() return self._staff == true end
function PlyMeta:PHXIsStaff() return self._staff == true end
function PlyMeta:IsListenServerHost() return false end
function PlyMeta:IsOnGround() return self._onground end
function PlyMeta:Crouching() return false end
function PlyMeta:GetPos() return self._pos end
function PlyMeta:SetPos(v) self._pos = v end
function PlyMeta:EyePos() return self._pos end
function PlyMeta:EyeAngles() return Angle(0, 0, 0) end
function PlyMeta:GetAngles() return Angle(0, 0, 0) end
function PlyMeta:GetVar(k, d) local v = self._vars[k]; if v == nil then return d end return v end
function PlyMeta:SetVar(k, v) self._vars[k] = v end
function PlyMeta:GetInfoNum(k, d) local v = self._info[k]; if v == nil then return d end return v end
function PlyMeta:GetInfo(k) return self._info[k] end
function PlyMeta:PHXChatInfo(...) table.insert(self.chat, { ... }) end
function PlyMeta:PHXChatPrint(...) table.insert(self.chat, { ... }) end
function PlyMeta:PrintCenter(...) table.insert(self.chat, { ... }) end
function PlyMeta:PHXNotify(...) table.insert(self.chat, { ... }) end
function PlyMeta:PrintMessage(...) table.insert(self.chat, { ... }) end
function PlyMeta:ChatPrint(...) table.insert(self.chat, { ... }) end
function PlyMeta:EmitSound(snd, lvl, pitch) table.insert(self.sounds, { snd = snd, lvl = lvl, pitch = pitch }) end
function PlyMeta:StopSound() end
function PlyMeta:SendLua(s) table.insert(self.lua, s) end
function PlyMeta:SendSurfaceSound(s) table.insert(self.sounds, { snd = s }) end
function PlyMeta:GetLastTauntTime(id) local v = self._vars[id]; if v == nil then return 0 end return v end
function PlyMeta:SetLastTauntTime(id, t) self._vars[id] = t end
function PlyMeta:GetNWInt(k, d) local v = self._nw[k]; if v == nil then return d end return v end
function PlyMeta:SetNWInt(k, v) self._nw[k] = v end
function PlyMeta:GetNWBool(k, d) local v = self._nw[k]; if v == nil then return d end return v end
function PlyMeta:SetNWBool(k, v) self._nw[k] = v end
function PlyMeta:GetNWFloat(k, d) local v = self._nw[k]; if v == nil then return d end return v end
function PlyMeta:SetNWFloat(k, v) self._nw[k] = v end
function PlyMeta:GetNWEntity(k, d) local v = self._nw[k]; if v == nil then return d end return v end
function PlyMeta:SetNWEntity(k, v) self._nw[k] = v end
function PlyMeta:GetPlayerPropEntity() return self._nw.PlayerPropEntity or NULL end
function PlyMeta:RemoveProp() self.ph_prop = nil end
function PlyMeta:Health() return self._hp or 100 end
function PlyMeta:SetHealth(v) self._hp = v end
function PlyMeta:Armor() return self._ap or 0 end
function PlyMeta:SetArmor(v) self._ap = v end
function PlyMeta:GetWalkSpeed() return self._walk or 250 end
function PlyMeta:SetWalkSpeed(v) self._walk = v end
function PlyMeta:SetJumpPower() end
function PlyMeta:KillSilent() self._alive = false end
function PlyMeta:Kill() self._alive = false end
function PlyMeta:Spawn() self._alive = true end
function PlyMeta:SetTeam(t) self._team = t end
function PlyMeta:Frags() return self._frags or 0 end
function PlyMeta:AddFrags(n) self._frags = (self._frags or 0) + n end
function PlyMeta:SetFrags(n) self._frags = n end
function PlyMeta:AddDeaths() end
function PlyMeta:HasWeapon() return false end
function PlyMeta:Give(wep) table.insert(self.weapons, wep) end
function PlyMeta:GiveAmmo() end
function PlyMeta:SetAmmo() end
function PlyMeta:SelectWeapon() end
function PlyMeta:StripWeapons() end
function PlyMeta:Blind(b) self._blind = b end
function PlyMeta:GetBlindState() return self._blind == true end
function PlyMeta:Lock() self._locked = true end
function PlyMeta:UnLock() self._locked = false end
function PlyMeta:IsFrozen() return self._locked == true end
function PlyMeta:Freeze(b) self._locked = b end
function PlyMeta:SetupHands() end
function PlyMeta:SetCustomCollisionCheck() end
function PlyMeta:SetAvoidPlayers() end
function PlyMeta:CrosshairEnable() end
function PlyMeta:SetViewOffset() end
function PlyMeta:SetViewOffsetDucked() end
function PlyMeta:DrawViewModel() end
function PlyMeta:SetColor() end
function PlyMeta:SetMoveType() end
function PlyMeta:EnablePropPitchRot() end
function PlyMeta:PHResetView() end
function PlyMeta:ResetTauntRandMapCount() end
function PlyMeta:CreateRagdoll() end
function PlyMeta:HasFakePropEntity() return self._nw.fakeprop == true end
function PlyMeta:SetFakePropEntity(b) self._nw.fakeprop = b end
function PlyMeta:PlaceDecoyProp() end
function PlyMeta:GetPlayerLockedRot() return self._nw.lockrot == true end
function PlyMeta:SetPlayerLockedRot(b) self._nw.lockrot = b end
function PlyMeta:SendRotState() end
function PlyMeta:FreezePropMidAir() end
function PlyMeta:SubTauntRandMapPropCount() end
function PlyMeta:GetTauntRandMapPropCount() return 6 end
function PlyMeta:IsLastStanding() return false end
function PlyMeta:IsCurrentlyForcedAsProp() return self._nw["bPHX.ForcedAsProp"] == true end
function PlyMeta:SetForceAsProp(b) self._nw["bPHX.ForcedAsProp"] = b end
function PlyMeta:ConCommand(c) table.insert(self.concmds, c) end
function PlyMeta:Kick() self.kicked = true end
function PlyMeta:CheckHull() return true end
function PlyMeta:TraceLineFromPlayer() return { HitPos = self._pos, Contents = 0, HitSky = false } end

function S.Player(t)
  t = t or {}
  local p = setmetatable({
    _team = t.team or TEAM_PROPS, _alive = (t.alive ~= false), _name = t.name or "TestPly",
    _sid = t.sid or "STEAM_0:0:1", _staff = t.staff or false, _bot = t.bot,
    _onground = (t.onground ~= false), _pos = Vector(0, 0, 0),
    _vars = t.vars or {}, _info = t.info or {}, _nw = {}, _walk = t.walk,
    _idx = t.idx, chat = {}, sounds = {}, concmds = {}, weapons = {}, lua = {},
  }, PlyMeta)
  p.ph_prop = t.ph_prop
  return p
end
S.PlyMeta = PlyMeta

return S
