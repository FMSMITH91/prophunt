dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- Prop Menu (PCR), server side: executes the shipped sh_propchoose.lua, sh_meta.lua,
-- sv_propchoose.lua and sv_customprop.lua, with the real GM:PlayerExchangeProp from init.lua
-- and the real Entity:GetPropSize / Player:CheckHull from sh_player.lua.
local PCRDIR = "gamemodes/prop_hunt/gamemode/plugins/propmenu/"
local GMDIR = "gamemodes/prop_hunt/gamemode/"

-- Engine pieces shim.lua leaves out (kept here: shim.lua is shared with other branches).
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
local created, removed = 0, 0
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
loadblocks("init.lua@PlayerExchangeProp", extract(GMDIR .. "init.lua", [[^function GM:PlayerExchangeProp]]))
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

print("\n== a living prop in a round: the normal path must not change ==")
resetCounts()
local p = player()
check("pick: no error", pick(p, "models/props/a.mdl"), "ok")
check("pick: disguise changed", p.ph_prop:GetModel(), "models/props/a.mdl")
check("pick: one use spent (3 -> 2)", p:CheckUsage(), 2)
check("pick: told how many uses are left", said(p, "PCR_USAGE_COUNT"), true)
check("pick: temp prop created", created, 1)
check("pick: temp prop removed", removed, 1)
check("pick: delay stamped", p:GetNWFloat("pcr.LastUsedTime"), CurTime())
p.chat = {}
check("second pick inside the delay: no error", pick(p, "models/props/b.mdl"), "ok")
check("second pick inside the delay: asked to wait", said(p, "PCR_PLS_WAIT"), true)
check("second pick inside the delay: no temp prop", created, 1)
check("second pick inside the delay: still a", p.ph_prop:GetModel(), "models/props/a.mdl")
S.pump(3)
pick(p, "models/props/b.mdl")
check("pick after the delay: changes to b", p.ph_prop:GetModel(), "models/props/b.mdl")
check("pick after the delay: 2 -> 1", p:CheckUsage(), 1)
S.pump(3); p.chat = {}
pick(p, "models/props/c.mdl")
check("last use: 1 -> 0", p:CheckUsage(), 0)
S.pump(3); p.chat = {}; resetCounts()
pick(p, "models/props/a.mdl")
check("no uses left: refused", said(p, "PCR_REACHED_LIMIT"), true)
check("no uses left: no temp prop", created, 0)
check("no uses left: still c", p.ph_prop:GetModel(), "models/props/c.mdl")

set("pcr_max_use", -1)
resetCounts()
p = player()
check("unlimited: allowance is -1", p:CheckUsage(), -1)
pick(p, "models/props/a.mdl")
check("unlimited: disguise changed", p.ph_prop:GetModel(), "models/props/a.mdl")
check("unlimited: allowance untouched", p:CheckUsage(), -1)
check("unlimited: told it is unlimited", said(p, "PCR_USAGE_UNLIMIT"), true)
check("unlimited: temp prop removed", select(2, counts()), 1)
set("pcr_max_use", 3)

S.traceHits = true                      -- no room for the new prop
resetCounts()
p = player()
pick(p, "models/props/a.mdl")
check("no room: told so", said(p, "PCR_NOROOM"), true)
check("no room: disguise unchanged", p.ph_prop:GetModel(), "models/start.mdl")
check("no room: use kept", p:CheckUsage(), 3)
check("no room: temp prop created and removed", created == 1 and removed == 1, true)
check("no room: delay stamped", p:GetNWFloat("pcr.LastUsedTime"), CurTime())
S.traceHits = false

-- The delay is the only throttle on the temp prop, so it must hold even if the exchange throws.
local realExchange = GAMEMODE.PlayerExchangeProp
GAMEMODE.PlayerExchangeProp = function() error("exchange failed") end
resetCounts()
p = player()
check("exchange throws: error surfaces", pick(p, "models/props/a.mdl"), "exchange failed")
check("exchange throws: delay already stamped", p:GetNWFloat("pcr.LastUsedTime"), CurTime())
pick(p, "models/props/b.mdl")
check("exchange throws: next rapid pick makes no temp prop", created, 1)
GAMEMODE.PlayerExchangeProp = realExchange
S.pump(3)
S.entsCreateFails = true
p = player()
check("ents.Create fails: no error", pick(p, "models/props/a.mdl"), "ok")
check("ents.Create fails: use kept", p:CheckUsage(), 3)
S.entsCreateFails = false

print("\n== a pick that changes nothing spends no use and claims no success ==")
p = player{ mdl = "models/props/a.mdl" }
check("same model: no error", pick(p, "models/props/a.mdl"), "ok")
check("same model: use kept (3)", p:CheckUsage(), 3)
check("same model: no 'uses left' message", said(p, "PCR_USAGE_COUNT"), false)
check("same model: delay still stamped (throttles the temp prop)", p:GetNWFloat("pcr.LastUsedTime"), CurTime())
S.pump(3); p.chat = {}
p.ph_prop:SetSkin(1)
pick(p, "models/props/a.mdl")
check("same model, other skin: that is a change (skin -> 0)", p.ph_prop:GetSkin(), 0)
check("same model, other skin: use spent (3 -> 2)", p:CheckUsage(), 2)
S.pump(3); p.chat = {}
pick(p, "models/thin.mdl")
check("too thin: PlayerExchangeProp refuses", said(p, "PHX_PROP_TOO_THIN"), true)
check("too thin: use kept (2)", p:CheckUsage(), 2)
check("too thin: no 'uses left' message", said(p, "PCR_USAGE_COUNT"), false)

print("\n== only a living prop in a round reaches the temp prop ==")
set("ph_prop_must_standing", 0)         -- the only thing that used to stop a dead prop
resetCounts()
p = player{ alive = false }
check("dead prop: no server error", pick(p, "models/props/a.mdl"), "ok")
check("dead prop: no temp prop created", created, 0)
check("dead prop: use kept (3)", p:CheckUsage(), 3)
set("pcr_max_use", -1)
p = player{ alive = false }
for _ = 1, 5 do pick(p, "models/props/b.mdl") end
check("dead prop, unlimited, 5 rapid picks: no temp props", created, 0)
set("pcr_max_use", 3)
local h = player{ team = TEAM_HUNTERS }
check("hunter: no error", pick(h, "models/props/a.mdl"), "ok")
check("hunter: no temp prop", created, 0)
check("hunter: use kept", h:CheckUsage(), 3)
check("hunter: no false success", said(h, "PCR_USAGE_COUNT"), false)
SetGlobalBool("InRound", false)
p = player()
pick(p, "models/props/a.mdl")
check("between rounds: no temp prop", created, 0)
check("between rounds: use kept", p:CheckUsage(), 3)
SetGlobalBool("InRound", true)
pick(p, "models/props/a.mdl")
check("must_standing 0, living prop: still works", p.ph_prop:GetModel(), "models/props/a.mdl")
set("ph_prop_must_standing", 1)

print("\n== pcr_enable is enforced by the server ==")
set("pcr_enable", 0)
resetCounts()
p = player()
check("disabled: no error", pick(p, "models/props/a.mdl"), "ok")
check("disabled: no temp prop", created, 0)
check("disabled: disguise unchanged", p.ph_prop:GetModel(), "models/start.mdl")
check("disabled: use kept", p:CheckUsage(), 3)
set("pcr_enable", 1)
pick(p, "models/props/a.mdl")
check("re-enabled: works again", p.ph_prop:GetModel(), "models/props/a.mdl")

print("\n== invalid-model kick matches its '( n / 4 )' counter ==")
p = player()
for _ = 1, 3 do pick(p, "models/not/in/list.mdl") end
check("3 invalid picks: not kicked", p.kicked == true, false)
pick(p, "models/not/in/list.mdl")
check("4th invalid pick (shows 4 / 4): kicked", p.kicked == true, true)
set("pcr_kick_invalid", 0)
p = player()
for _ = 1, 6 do pick(p, "models/not/in/list.mdl") end
check("pcr_kick_invalid 0: never kicked", p.kicked == true, false)
check("pcr_kick_invalid 0: warned", said(p, "PCR_NOT_EXIST"), true)
set("pcr_kick_invalid", 1)

print("\n== a mid-round joiner starts with the round's allowance ==")
p = S.Player{}
S.fire("PlayerInitialSpawn", p)
check("joiner: pcr_max_use uses (3), not 0", p:CheckUsage(), 3)
set("pcr_max_use", -1)
p = S.Player{}
S.fire("PlayerInitialSpawn", p)
check("joiner, unlimited: -1", p:CheckUsage(), -1)
set("pcr_max_use", 3)
check("joiner: prop data not yet sent", p.pcrHasPropData, false)

print("\n== prop-list send survives the requester leaving ==")
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
S.net.sent = {}
p = S.Player{}
S.fire("PlayerInitialSpawn", p)
S.receivers["pcr.ClientRequestPropData"](0, p)
check("request: no error on the next tick", #S.pump(0), 0)
check("request: prop list sent", sentTo("pcr.PropListData", p), 1)
check("request: marked as sent", p.pcrHasPropData, true)
p = S.Player{}
S.fire("PlayerInitialSpawn", p)
S.receivers["pcr.ClientRequestPropData"](0, p)
disconnect(p)
local errs = S.pump(0)
check("request then leave: no timer error", errs[1], nil)

print("\n== the ban list matches map models whatever their case ==")
set("pcr_enable_prop_ban", 1)
S.fileExists["phx_data/prop_model_bans/model_bans.txt"] = true
S.fileExists["phx_data/prop_model_bans/pcr_bans.txt"] = true
S.json = { ["phx_data/prop_model_bans/model_bans.txt"] = { "models/props_c17/furniturecouch001a.mdl" },
           ["phx_data/prop_model_bans/pcr_bans.txt"] = { "models/props_c17/OilDrum001.mdl" } }
mapProps{ "models/props_c17/FurnitureCouch001a.mdl", "models/props_c17/oildrum001.mdl", "models/props/a.mdl" }
PCR._INIT_STORED = false
PCR:PopulateProp()
check("lowercase ban, mixed-case map model: not listed",
  table.HasValue(PCR.PropList, "models/props_c17/furniturecouch001a.mdl"), false)
check("mixed-case ban, lowercase map model: not listed", table.HasValue(PCR.PropList, "models/props_c17/oildrum001.mdl"), false)
check("unbanned prop: still listed", table.HasValue(PCR.PropList, "models/props/a.mdl"), true)
check("ban list: banned prop's pick is refused", (function()
  local pl = player(); pick(pl, "models/props_c17/oildrum001.mdl"); return pl.ph_prop:GetModel() end)(), "models/start.mdl")
set("pcr_enable_prop_ban", 0)
PCR._INIT_STORED = false
PCR:PopulateProp()
check("ban off: couch listed (lowercased)", table.HasValue(PCR.PropList, "models/props_c17/furniturecouch001a.mdl"), true)

print("\n== custom props get the crash-model filter ==")
set("pcr_allow_custom", 1)
S.fileExists["phx_data/prop_chooser_custom/models.txt"] = true
S.json["phx_data/prop_chooser_custom/models.txt"] = { "models/balloons/balloon_dog.mdl", "models/props_collectables/PiePan.mdl" }
PCR:PopulateProp()
check("custom prop: listed", table.HasValue(PCR.PropList, "models/balloons/balloon_dog.mdl"), true)
check("prohibited custom prop: not listed", table.HasValue(PCR.PropList, "models/props_collectables/piepan.mdl"), false)

print("\n== AddToGroup matches CheckUserGroup's lowercase lookup ==")
p = S.Player{}
p.GetUserGroup = function() return "Supporter" end
check("unknown group: refused", PCR:CheckUserGroup(p), false)
PCR:AddToGroup("Supporter")
check("AddToGroup('Supporter'): member accepted", PCR:CheckUserGroup(p), true)
p.GetUserGroup = function() return "VIP" end
check("preset group, any case: accepted", PCR:CheckUserGroup(p), true)

print("\n== custom-prop editor lock ==")
local A, B = S.Player{ staff = true, name = "A" }, S.Player{ staff = true, name = "B" }
local function request(pl) S.net.sent = {}; pl.chat = {}; S.receivers["phxpm.fb_RequestOpen_w"](0, pl)
  return sentTo("phxpm.fb_openPM_Editor", pl) == 1 end
local function done(pl) S.receivers["PCR.DoneEditing"](0, pl) end
local function editing()
  local c = S.Player{ staff = true }; S.concommands["is_someone_editing"].fn(c); return c.chat[1] and c.chat[1][1] end
check("A opens: granted", request(A), true)
check("B while A edits: refused", request(B), false)
check("B while A edits: told it is in use", said(B, "PCR_EDT_IN_USE"), true)
check("is_someone_editing: true", editing(), "Is someone editing?: true")
local C = S.Player{}
check("non-staff: refused", request(C), false)
check("non-staff: no rights", said(C, "PCR_EDT_NO_RIGHTS"), true)
done(B)
check("B's Close does not free A's lock", request(B), false)
done(A)
check("A closes, B opens: granted", request(B), true)
check("holder re-requests (window never opened): granted", request(B), true)
S.fire("PlayerDisconnected", B)         -- still a valid entity while the hook runs
check("holder disconnecting: A granted", request(A), true)
done(A)
B = S.Player{ staff = true, name = "B" }  -- back under a new entity
check("B rejoined: granted", request(B), true)
disconnect(B)
check("holder gone (entity invalid): A granted", request(A), true)
S.pump(599)
B = S.Player{ staff = true, name = "B" }
check("599 s later: still A's", request(B), false)
S.pump(2)
check("after the 600 s timeout: B granted", request(B), true)
done(B)
check("is_someone_editing after release: false", editing(), "Is someone editing?: false")

-- Saving counts as activity and refreshes the lock.
local function save(pl, list)
  S.json["saved"] = list
  S.net.readq = { "PCR", "CustomProp", 5, "saved" }
  return attempt(S.receivers["PCR.EditedCustomPropData"], 0, pl)
end
S.fileExists["phx_data/prop_chooser_custom"] = true
for _, m in ipairs{ "models/balloons/balloon_dog.mdl", "models/props_collectables/piepan.mdl" } do S.fileExists[m] = true end
check("A opens again", request(A), true)
S.pump(500)
check("A saves: no error", save(A, { "models/balloons/balloon_dog.mdl", "models/props_collectables/piepan.mdl" }), "ok")
check("save drops the prohibited model", table.HasValue(PCR.CustomProp, "models/props_collectables/piepan.mdl"), false)
check("save keeps the normal model", table.HasValue(PCR.CustomProp, "models/balloons/balloon_dog.mdl"), true)
S.net.sent = {}
check("save: confirmation timer has no error", #S.pump(1), 0)
check("save: editor told it succeeded", sentTo("phxpm.fb_UpdateConfirmed_Editor", A), 1)
S.pump(199)
check("700 s after opening, 200 s after saving: still A's", request(B), false)
S.pump(402)
check("600 s after the save: B granted", request(B), true)
done(B)
check("A re-opens", request(A), true)
save(A, { "models/balloons/balloon_dog.mdl" })
disconnect(A)
S.net.sent = {}
check("editor leaves before the confirmation: no timer error", S.pump(1)[1], nil)
check("editor leaves before the confirmation: nothing sent to them", sentTo("phxpm.fb_UpdateConfirmed_Editor", A), 0)
check("editor left: lock free", request(B), true)

report()
