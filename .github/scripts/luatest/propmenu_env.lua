-- Shared set-up for the Prop Menu (PCR) server tests, t_plugins_propmenu*.lua: executes the
-- shipped sh_propchoose.lua, sh_meta.lua, sv_propchoose.lua and sv_customprop.lua, with the
-- real GM:PlayerExchangeProp from init.lua and the real Entity:GetPropSize / Player:CheckHull
-- from sh_player.lua. Not a t_*.lua file, so run.sh only runs it through those tests.
local PCRDIR = "gamemodes/prop_hunt/gamemode/plugins/propmenu/"
local GMDIR = "gamemodes/prop_hunt/gamemode/"

-- Engine pieces shim.lua leaves out (kept here: shim.lua is shared with other branches).
function isfunction(v) return type(v) == "function" end
HUD_PRINTCONSOLE, SOLID_VPHYSICS, SOLID_BBOX = 2, 6, 2
local EntMeta = {}
EntMeta.__index = EntMeta
function FindMetaTable(n)
  if n == "Player" then return S.PlyMeta elseif n == "Entity" then return EntMeta end
end
engine.GetGames = function() return {} end
net.ReadData = function() return S.net.readq and table.remove(S.net.readq, 1) end
file.Read = function(p) return p end          -- util.JSONToTable then looks the path up in S.json

-- The code's own console prints are expected here; keep them out of the test output.
local realPrint = print
print = function(first, ...)
  if tostring(first):find("^%[Prop Menu%]") then return end
  realPrint(first, ...)
end

local PM = S.PlyMeta
-- GMod's GetNWFloat falls back to 0; the shim's returns nil when no default is passed, which
-- makes PlayerDelayCheck throw an error of its own and hide the one under test.
function PM:GetNWFloat(k, d) local v = self._nw[k]; if v == nil then return d or 0 end return v end
function PM:PHAdjustView() end
function PM:SetHull() end
function PM:SetHullDuck() end
function PM:PHSendHullInfo() end

-- Entities. ents.Create counts what it makes; Remove counts what goes away.
local THIN = { ["models/thin.mdl"] = true }
created, removed = 0, 0   -- globals: both test files read these counters directly
function EntMeta:GetClass() return self._cls end
function EntMeta:GetModel() return self._mdl end
function EntMeta:SetModel(m) self._mdl = m end
function EntMeta:GetSkin() return self._skin end
function EntMeta:SetSkin(s) self._skin = s end
function EntMeta:SetPos() end
function EntMeta:SetAngles() end
function EntMeta:SetKeyValue() end
function EntMeta:SetNoDraw() end
function EntMeta:SetSolid() end
function EntMeta:SetColor() end
function EntMeta:Spawn() end
function EntMeta:GetColor() return color_white end
function EntMeta:EntIndex() return 1 end
function EntMeta:GetNWBool(_, d) return d end
function EntMeta:OBBMins() return Vector(-10, -10, 0) end
function EntMeta:OBBMaxs() if THIN[self._mdl] then return Vector(0.4, 0.4, 20) end return Vector(10, 10, 20) end
function EntMeta:GetPhysicsObject() return { __valid = true, GetVolume = function() return 5000 end } end
function EntMeta:Remove() removed = removed + 1; self.__valid = false end
local function newEnt(cls, mdl) return setmetatable({ __valid = true, _cls = cls, _mdl = mdl, _skin = 0 }, EntMeta) end
ents.Create = function(cls)
  if S.entsCreateFails then return NULL end      -- the engine's answer at the edict limit
  created = created + 1; return newEnt(cls)
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

-- The real cvar layer, and the real definitions (defaults, types) of every cvar used here.
loadblocks("sh_convar.lua@cvars",
  extract(GMDIR .. "sh_convar.lua", "1-10") .. "\n"
  .. extract(GMDIR .. "sh_convar.lua", [[^local ConVarTranslate = \{]]) .. "\nlocal CVAR = {}\n"
  .. extractAll(GMDIR .. "sh_convar.lua", { [[^function PHX:AddCVar]], [[^function PHX:GetCVar]], [[^function PHX:QCVar]] }))
do
  local specs = {}
  for _, n in ipairs{ "pcr_enable", "pcr_allow_custom", "pcr_enable_prop_ban", "pcr_max_use", "pcr_delay_use",
                      "pcr_only_allow_certain_groups", "pcr_use_ulx_menu", "pcr_limit_enable", "pcr_max_prop_list",
                      "pcr_kick_invalid", "pcr_use_room_check", "pcr_enable_bbox_limit", "ph_banned_models",
                      "ph_prop_must_standing", "ph_prop_viewoffset_mult", "ph_tmp_accurate_hull",
                      "ph_sv_enable_obb_modifier" } do
    specs[#specs + 1] = ([=[^CVAR\["%s"\]]=]):format(n)
  end
  loadblocks("sh_convar.lua@defs", "local CVAR = {}\n" .. extractAll(GMDIR .. "sh_convar.lua", specs)
    .. "\nfor n, d in pairs(CVAR) do PHX:AddCVar(d[1], n, d[2], d[3], d[4], d[5]) end")
end
local function set(n, v) RunConsoleCommand(n, tostring(v)) end
check("cvar layer: pcr_enable defaults on (real bool)", PHX:QCVar("pcr_enable"), true)
check("cvar layer: pcr_max_use defaults to 3", PHX:GetCVar("pcr_max_use"), 3)

loadblocks("sh_config.lua@props", extractAll(GMDIR .. "sh_config.lua", {
  [[^PHX\.PROHIBITTED_MDLS = \{]], [[^PHX\.CVARUseAbleEnts = \{]], [[^PHX\.USABLE_PROP_ENTITIES = ]],
  [[^function PHX:IsUsablePropEntity]] }))
PHX.BANNED_PROP_MODELS = { "models/banned.mdl" }
loadblocks("sh_player.lua@hull", "local Entity, Player = FindMetaTable('Entity'), FindMetaTable('Player')\n"
  .. extractAll(GMDIR .. "sh_player.lua", { [[^function Entity:GetPropSize]], [[^function Player:CheckHull]] }))
GAMEMODE.ViewCam.cHullzMins, GAMEMODE.ViewCam.cHullzMaxs = 16, 72
loadblocks("init.lua@PlayerExchangeProp", extractAll(GMDIR .. "init.lua",
  { [[^local function IsBannedPropModel]], [[^function GM:PlayerExchangeProp]] }))
loadblocks("sh_propchoose.lua", extract(PCRDIR .. "sh_propchoose.lua", "1-99999"))
loadblocks("sh_meta.lua", extract(PCRDIR .. "sh_meta.lua", "1-99999"))
do
  local path = PCRDIR .. "sv_propchoose.lua"
  loadblocks("sv_propchoose.lua", withContinue(extract(path, "1-99999"), path,
    [[for _,prop in RandomPairs\(ents\.FindByClass\("prop_physics\*"\)\) do]]))
end
loadblocks("sv_customprop.lua", extract(PCRDIR .. "sv_customprop.lua", "1-99999"))

-- The map: three ordinary props plus a paper-thin one. Every model exists on disk.
local function mapProps(list)
  local t = {}
  for _, m in ipairs(list) do t[#t + 1] = newEnt("prop_physics", m); S.fileExists[m] = true end
  S.entsByClass["prop_physics*"] = t
end
local MAP = { "models/props/a.mdl", "models/props/b.mdl", "models/props/c.mdl", "models/thin.mdl" }
mapProps(MAP)
S.fire("InitPostEntity")
check("map scan lists the map props", #PCR.PropList, 4)

-- A player as the round leaves them: a living prop owns a ph_prop, a dead one does not
-- (class_prop OnDeath -> RemoveProp nils it). PostCleanupMap grants the round's uses.
local function player(opts)
  opts = opts or {}
  local p = S.Player{ team = opts.team or TEAM_PROPS, alive = opts.alive ~= false, staff = opts.staff }
  if p:Alive() and p:Team() == TEAM_PROPS then
    p.ph_prop = newEnt("ph_prop", opts.mdl or "models/start.mdl")
    p.ph_prop.health, p.ph_prop.max_health = 100, 100
  end
  S.players = { p }
  S.fire("PostCleanupMap")
  return p
end
local function pick(p, mdl)
  S.net.readq = { mdl }
  return attempt(S.receivers["pcr.SetMetheProp"], 0, p)
end
local function said(p, key)
  for _, c in ipairs(p.chat) do for _, v in ipairs(c) do if v == key then return true end end end
  return false
end
local function counts() return created, removed end
local function resetCounts() created, removed = 0, 0 end
SetGlobalBool("InRound", true)

-- A disconnected Player in GMod: reading a field gives nil, writing one throws.
local function disconnect(pl)
  S.fire("PlayerDisconnected", pl)
  for k in pairs(pl) do rawset(pl, k, nil) end
  setmetatable(pl, {
    __index = function(_, k) if k == "__valid" then return false end return nil end,
    __newindex = function(_, k) error("Tried to use a NULL entity! (write " .. tostring(k) .. ")", 2) end })
end
local function sentTo(name, pl)
  local n = 0
  for _, m in ipairs(S.net.sent) do if m.name == name and m.to == pl then n = n + 1 end end
  return n
end

return { set = set, player = player, pick = pick, said = said, counts = counts, resetCounts = resetCounts,
         mapProps = mapProps, disconnect = disconnect, sentTo = sentTo }
