dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- sh_config.lua (prop bans, cleanup sweep, removed commands), sh_utils.lua's
-- ULX commands, the update checker, the integrity checker and the map configs.
-- Whole files are loaded wherever that is practical, so the hooks and commands
-- under test are the ones the file registers.

local GM = "gamemodes/prop_hunt/gamemode/"
local REPO = (debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "../../../"

-- A tiny DATA folder. file.Write refuses a non-string the way the engine's
-- f:Write does, rather than quietly storing nil.
local files, parsed = {}, {}
file.Exists = function(p) return files[p] ~= nil end
file.Read = function(p) return files[p] end
file.Size = function(p) return files[p] and #files[p] or 0 end
file.Write = function(p, d)
  if type(d) ~= "string" then error("bad argument #1 to 'Write' (string expected, got " .. type(d) .. ")", 2) end
  files[p] = d
end
file.CreateDir = function(p) files[p] = files[p] or "" end
util.JSONToTable = function(s) return parsed[s] end
util.PHXQuickCompress = function(t) local c = table.concat(t, ","); return c, #c end

local entsAll = {}
ents.GetAll = function() return entsAll end
local function Ent(cls, mdl)
  local e = { __valid = true, cls = cls, mdl = mdl, fired = {}, kv = {} }
  function e:GetModel() return self.mdl end
  function e:GetClass() return self.cls end
  function e:Remove() self.__valid = false; self.removed = true end
  function e:SetPos(v) self.pos = v end
  function e:GetPos() return self.pos end
  function e:SetAngles() end
  function e:SetKeyValue(k, v) self.kv[k] = v end
  function e:Spawn()   -- an entity is findable once spawned
    S.entsByClass[self.cls] = S.entsByClass[self.cls] or {}
    table.insert(S.entsByClass[self.cls], self)
  end
  function e:Activate() end
  function e:Fire(input, v) table.insert(self.fired, input .. "=" .. tostring(v)) end
  return e
end
local created = {}
ents.Create = function(cls) local e = Ent(cls); created[#created + 1] = e; return e end
-- The engine hands back a fresh list, so spawning while iterating one is safe.
ents.FindByClass = function(c) local r = {} for i, e in ipairs(S.entsByClass[c] or {}) do r[i] = e end return r end

local function count(list, v) local n = 0 for _, x in ipairs(list) do if x == v then n = n + 1 end end return n end
local function sentTo(name, key)
  local r = {}
  for _, m in ipairs(S.net.sent) do
    if m.name == name and (key == nil or m.data[1] == key) then r[#r + 1] = m end
  end
  return r
end

print("\n== #34: prop bans are stored and deduplicated in lowercase ==")
files["phx_data/prop_model_bans/model_bans.txt"] = "BANS"
parsed["BANS"] = { "models/props_junk/PopCan01a.mdl", "models/Props/CS_Assault/Money.mdl" }
files["phx_data/prop_plymodel_bans/bans.txt"] = "PLBANS"
parsed["PLBANS"] = { "models/Player.mdl" }
S.hooks, S.concommands = {}, {}
loadblocks("sh_config.lua", extract(GM .. "sh_config.lua", "1-99999"))
local bans = PHX.BANNED_PROP_MODELS
check("file entry stored lowercase", count(bans, "models/props_junk/popcan01a.mdl"), 1)
check("mixed-case copy of a perma ban is not added twice", count(bans, "models/props/cs_assault/money.mdl"), 1)
local staff, pleb = S.Player{ staff = true }, S.Player{ name = "pleb" }
S.concommands["ph_refresh_propmodel_ban"].fn(staff)
S.concommands["ph_refresh_propmodel_ban"].fn(staff)
check("refresh twice -> still one entry", count(bans, "models/props_junk/popcan01a.mdl"), 1)

print("\n== #214: ban lists reach late joiners and follow a refresh ==")
S.net.sent = {}
S.concommands["ph_refresh_propmodel_ban"].fn(staff)
local m = sentTo("PHX.UpdatePropbanInfo", "BANNED_PROP_MODELS")
check("refresh rebroadcasts the prop ban list", #m == 1 and m[1].to, "all")
S.net.sent = {}
S.concommands["ph_refresh_plmodel_ban"].fn(staff)
check("refresh rebroadcasts the playermodel ban list", #sentTo("PHX.UpdatePropbanInfo", "PROP_PLMODEL_BANS"), 1)
S.net.sent = {}
S.concommands["ph_refresh_propmodel_ban"].fn(pleb)
check("non-staff refresh sends nothing", #S.net.sent, 0)
local joiner = S.Player{ name = "joiner" }
S.fire("PHX.PlayerFullLoad", joiner)
m = sentTo("PHX.UpdatePropbanInfo", "BANNED_PROP_MODELS")
check("late joiner is sent the prop ban list", #m == 1 and m[1].to == joiner, true)
check("  ... with the models in it", m[1] and m[1].data[3]:find("popcan01a", 1, true) ~= nil, true)
check("late joiner is sent the playermodel ban list", #sentTo("PHX.UpdatePropbanInfo", "PROP_PLMODEL_BANS"), 1)

print("\n== #157: the round-start sweep is one pass and case-insensitive ==")
CreateConVar("ph_usable_prop_type", "1")
local egg = Ent("prop_physics", "models/FoodNHouseholdItems/egg.mdl")
local chair = Ent("prop_physics", "models/props_c17/FurnitureChair001a.mdl")
local gone = Ent("prop_physics", "models/sims/lightwall2.mdl"); gone.__valid = false
local world = Ent("worldspawn", nil)
entsAll = { egg, chair, gone, world }
for i = 1, 500 do entsAll[#entsAll + 1] = Ent("prop_physics", "models/props_c17/chair.mdl") end
S.timers, S.net.sent = {}, {}
S.fire("PostCleanupMap")
check("one timer for the whole map", #S.timers, 1)
local errs = S.pump(0.1)
check("sweep runs without error", #errs, 0)
check("mixed-case prohibited model is removed", egg.removed, true)
check("an ordinary prop stays", chair.removed, nil)
check("round start still broadcasts both ban lists", #sentTo("PHX.UpdatePropbanInfo"), 2)

print("\n== #149/#221 #150/#222: broken commands are gone ==")
check("ph_refresh_taunt_list (server)", S.concommands["ph_refresh_taunt_list"], nil)
S.concommands = {}
SERVER, CLIENT = false, true
loadblocks("sh_config.lua@client", extract(GM .. "sh_config.lua", "1-99999"))
SERVER, CLIENT = true, false
check("ph_refresh_taunt_list (client)", S.concommands["ph_refresh_taunt_list"], nil)
check("aaaaaaargghhhhhh (client)", S.concommands["aaaaaaargghhhhhh"], nil)

print("\n== #139: ULX commands with a console caller and a ULX-only group ==")
local ulxcmds = {}
ulx = { command = function(_, name, fn) ulxcmds[name] = fn
  return { defaultAccess = function() end, help = function() end } end }
ULib = { ACCESS_SUPERADMIN = "superadmin", ACCESS_ALL = "user" }
PHX.TITLE = "PH:X"
S.concommands = {}
loadblocks("sh_utils.lua", extract(GM .. "sh_utils.lua", "1-99999"))
-- the real ph_force_end_round, and a console that dispatches to it
local ended
function GAMEMODE:RoundEndWithResult(r) ended = r end
function ControlTauntWindow() end
function ClearTimer() end
function PHX:PlayWinningSound() end
loadblocks("init.lua@ForceEndRound", extractAll(GM .. "init.lua", {
  [[^local function ForceEndRound]], [[^concommand\.Add\("ph_force_end_round"]] }))
local shimRCC = RunConsoleCommand
RunConsoleCommand = function(n, ...)
  if S.concommands[n] then return S.concommands[n].fn(NULL, n, { ... }) end
  return shimRCC(n, ...)
end
local shimConCommand = S.PlyMeta.ConCommand
S.PlyMeta.ConCommand = function(self, c)
  shimConCommand(self, c)
  if S.concommands[c] then S.concommands[c].fn(self, c, {}) end
end
SetGlobalBool("InRound", true)

check("ulx ph3padjust from the console -> no error", attempt(ulxcmds["ulx ph3padjust"], NULL), "ok")
check("ulx phmenu from the console -> no error", attempt(ulxcmds["ulx phmenu"], NULL), "ok")
local p = S.Player{}
ulxcmds["ulx ph3padjust"](p)
check("ulx ph3padjust in game opens the window", p.lua[1], "OpenTPSAdjust()")
ulxcmds["ulx phmenu"](p)
check("ulx phmenu in game opens the menu", p.concmds[#p.concmds], "ph_x_menu")

local mod = S.Player{ name = "moderator", staff = false }   -- granted by ULX, not PH:X staff
ended = nil
ulxcmds["ulx phforceend"](mod)
check("dedicated: ULX-granted non-PHX-staff ends the round", ended, 1001)
ended = nil
ulxcmds["ulx phforceend"](NULL)
check("dedicated: server console ends the round", ended, 1001)
game.IsDedicated = function() return false end
ended = nil
ulxcmds["ulx phforceend"](S.Player{ name = "host", staff = true })
check("listen: staff player ends the round as themself", ended, 1001)
ended = nil
local nobody = S.Player{ name = "nobody" }
ulxcmds["ulx phforceend"](nobody)
check("listen: non-staff player is still refused", ended, nil)
game.IsDedicated = function() return true end

print("\n== #147: update check falls back and fails quietly ==")
local routes, fetched, printed, colored = {}, {}, {}, {}
http.Fetch = function(url, ok, fail)
  fetched[#fetched + 1] = url
  local r = routes[url]
  if r.err then fail(r.err) else ok(r.body, #r.body, {}, r.code) end
end
GAMEMODE.UPDATEURL, GAMEMODE.UPDATEURLBACKUP = "https://primary/", "https://backup/"
GAMEMODE._VERSION, GAMEMODE.REVISION = "X2Z", "21.03.25"
local function info(ver, rev) return { version = ver, revision = rev, url = "https://changelog", notice = "notes" } end
parsed['{"old"}'] = info("X2Z", "01.10.24")
parsed['{"newer"}'] = info("X2Z", "01.01.26")
parsed['{"newver"}'] = info("X3", "01.01.26")
parsed['{"broken"}'] = { version = "X2Z" }
local HTML = "<!doctype html><title>GModGaming</title>"
S.concommands = {}
loadblocks("sh_httpupdates.lua", extract(GM .. "sh_httpupdates.lua", "1-99999"))

local realprint = print
local function run(primary, backup)
  routes = { ["https://primary/"] = primary, ["https://backup/"] = backup }
  fetched, printed, colored, PHX.Messagedata = {}, {}, {}, {}
  print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
  MsgC = function(...) local t = {} for _, v in ipairs({ ... }) do if type(v) == "string" then t[#t + 1] = v end end colored[#colored + 1] = table.concat(t) end
  local r = attempt(PHX.CheckUpdate, PHX)
  print = realprint
  MsgC = function() end
  return r
end
local function said(pat) for _, l in ipairs(colored) do if l:find(pat) then return true end end return false end

check("primary gives HTML -> no error", run({ code = 200, body = HTML }, { code = 200, body = '{"old"}' }), "ok")
check("  ... backup is tried", fetched[2], "https://backup/")
check("  ... backup's info is used", PHX.Messagedata.revision, "01.10.24")
check("  ... an older published revision is not an update", said("New Revision"), false)
check("  ... reported up to date", said("up to date"), true)
check("  ... and nothing printed", #printed, 0)
run({ code = 301, body = HTML }, { code = 200, body = '{"old"}' })
check("primary 301 with a body -> backup tried", #fetched, 2)
run({ err = "timeout" }, { code = 200, body = '{"old"}' })
check("primary unreachable -> backup tried", PHX.Messagedata.revision, "01.10.24")
run({ code = 200, body = HTML }, { code = 404, body = "Not Found" })
check("both fail -> exactly one log line", #printed, 1)
run({ code = 200, body = HTML }, { err = "timeout" })
check("backup unreachable -> exactly one log line", #printed, 1)
run({ code = 200, body = '{"broken"}' }, { code = 200, body = '{"old"}' })
check("primary JSON missing fields -> backup used", PHX.Messagedata.revision, "01.10.24")
-- the normal paths
run({ code = 200, body = '{"old"}' }, { code = 200, body = '{"newer"}' })
check("primary valid -> backup not fetched", #fetched, 1)
run({ code = 200, body = '{"newer"}' }, {})
check("a newer revision is still announced", said("New Revision of 01.01.26"), true)
run({ code = 200, body = '{"newver"}' }, {})
check("a new version is still announced", said("New version of X3"), true)

print("\n== #155/#154: integrity checker ==")
local IG = "lua/autorun/!!sh_phx_integrity.lua"
S.cvarcb = {}
loadblocks("integrity.lua", extract(IG, "1-99999"))
check("no dead change callbacks", S.cvarcb["phx_integrity_check"] == nil and S.cvarcb["phx_integrity_check_fretta"] == nil, true)

local ManageData = loadchunk(extractAll(IG, { [[^local path = ]], [[^local KnownConflictWSID]],
  [[^local function ManageData]] }) .. "\nreturn ManageData, KnownConflictWSID", "integrity@ManageData")
local md, known = ManageData()
files = {}
local r1
check("save nil -> no error", attempt(function() r1 = md(true, nil) end), "ok")
check("  ... falls back to the known list", r1 == known, true)
check("save \"\" -> falls back", md(true, "") == known, true)
check("save real data -> kept (normal)", md(true, '["1"]'), '["1"]')
check("  ... and written", files["phx_addons_conflict.json"], '["1"]')

local CheckTXT = loadchunk("local ErrorList = {}\n" .. extractAll(IG, { [[^local function ReadGamemodeTXT]],
  [[^local function CheckGamemodeTXT]] }) .. "\nreturn CheckGamemodeTXT", "integrity@CheckGamemodeTXT")()
files["gamemodes/base_phx/base_phx.txt"] = "KV"; files["gamemodes/prop_hunt/prop_hunt.txt"] = "KV"
util.KeyValuesToTable = function() return { isphx = "1" } end
file.Find = function(pat) if pat == "gamemodes/*" then return {}, { "base_phx", "prop_hunt", "fretta13" } end return {}, {} end
SERVER, CLIENT = false, true
check("client with a fretta13 install -> no error counted", CheckTXT(), 0)
SERVER, CLIENT = true, false
check("server with fretta13 -> still flagged", CheckTXT(), 1)

local GetConflicts = loadchunk([[
local Errors, ErrorList, captured = 0, {}, nil
local function PHX___openWarningDialog(found, result) captured = { found, result } end
]] .. extractAll(IG, { [[^local function GetSubscribbedAddons]], [[^local function GetConflictingAddons]] })
  .. "\nreturn GetConflictingAddons, function() return captured end", "integrity@Conflicts")
local conflicts, got = GetConflicts()
engine.GetAddons = function() return { { mounted = true, wsid = 135509255, title = "Old PH" },
                                       { mounted = true, wsid = 42, title = "Fine" } } end
parsed['["135509255"]'] = { "135509255" }
SERVER, CLIENT = false, true
conflicts('["135509255"]')
SERVER, CLIENT = true, false
local res = got() and got()[2] or {}
check("conflict found and reported", got() and got()[1], true)
check("  ... keyed and labelled by workshop id", res["135509255"] and res["135509255"].wsid, "135509255")
check("  ... with its title", res["135509255"] and res["135509255"].title, "Old PH")
check("  ... and nothing else", res["42"], nil)

print("\n== #140/#141: map configs ==")
function PHX:CreatePlayerClip() end
S.hooks, S.entsByClass, created = {}, {}, {}
loadblocks("ph_kliener_v2.lua", extract(GM .. "config/maps/ph_kliener_v2.lua", "1-99999"))
S.fire("PostCleanupMap")
S.fire("PostCleanupMap")
S.fire("PostCleanupMap")
local sc = 0
for _, e in ipairs(created) do if e.cls == "shadow_control" then sc = sc + 1 end end
check("three rounds -> one shadow_control", sc, 1)
check("  ... created with shadows disabled", created[1] and created[1].kv.disableallshadows, "1")
check("  ... and kept disabled on later rounds", created[1] and created[1].fired[1], "SetShadowsDisabled=1")
local mapSC = Ent("shadow_control"); mapSC:Spawn()
S.entsByClass["shadow_control"] = { mapSC }
created = {}
S.fire("PostCleanupMap")
check("map's own shadow_control is reused", #created, 0)
check("  ... and told to disable shadows", mapSC.fired[1], "SetShadowsDisabled=1")

S.hooks, S.entsByClass, created = {}, {}, {}
loadblocks("ph_motel_blacke_v3.lua", extract(GM .. "config/maps/ph_motel_blacke_v3.lua", "1-99999"))
check("no PreCleanupMap pass", S.hooks.PreCleanupMap == nil or next(S.hooks.PreCleanupMap) == nil, true)
local s1, s2 = Ent("info_player_start"), Ent("info_player_start")
s1.pos, s2.pos = Vector(0, 0, 0), Vector(100, 0, 0)
S.entsByClass["info_player_start"] = { s1, s2 }
S.fire("PostCleanupMap")
check("PostCleanupMap still raises each spawn", s1.pos.z .. "," .. s2.pos.z, "6,6")
check("  ... and adds one above each", #created, 2)
check("  ... 78 units up", created[1] and created[1].pos.z, 78)

-- ph_hotel: a prop-menu pick is a fresh entity, so the tall boards' hull must
-- also be recorded per model, not only on the boards already on the map.
S.hooks, PHX.CustomHulls = {}, nil
local BOARD = "models/props_debris/wood_board05a.mdl"
local board = Ent("prop_physics", BOARD)
function board:SetNWBool(k, v) self[k] = v end
ents.FindByModel = function(mdl) if mdl == BOARD then return { board } end return {} end
CreateConVar("ph_sv_enable_obb_modifier", "1")
loadblocks("ph_hotel.lua", extract(GM .. "config/maps/ph_hotel.lua", "1-99999"))
S.fire("PostCleanupMap")
local hull = PHX.CustomHulls and PHX.CustomHulls[BOARD]
check("ph_hotel records the board hull per model", hull and tostring(hull[1]) .. " " .. tostring(hull[2]), "[-1.3 -4.3 0] [1.3 4.3 96]")
check("  ... for the other board too", PHX.CustomHulls and PHX.CustomHulls["models/props_debris/wood_board03a.mdl"] ~= nil, true)
check("  ... and the board on the map still gets its own", board.hasCustomHull and tostring(board.m_Hull[2]), "[1.3 4.3 96]")
PHX.CustomHulls["models/from_obb_file.mdl"] = "sv_bbox"
S.fire("PostCleanupMap")
check("  ... next round, other models' hulls are kept", PHX.CustomHulls["models/from_obb_file.mdl"], "sv_bbox")

print("\n== #143: the devil ball template works once uncommented ==")
local fh = io.open(REPO .. GM .. "config/server/sv_devilball_additions.lua")
local src = fh:read("*a"); fh:close()
-- the block a server owner uncomments: from a line that is just "--[[" to the final "]]"
local body = src:match("\n%-%-%[%[\n(.-)\n%]%]%s*$")
local addition
list.Set = function(_, _, fn) addition = fn end
loadchunk(body, "sv_devilball_additions.lua(uncommented)")()
local function Prop()
  local e = Ent("ph_prop")
  function e:SetMaterial(mat) self.mat = mat end
  function e:SetColor(c) self.col = c.r .. "," .. c.g .. "," .. c.b end   -- the engine reads col.r
  return e
end
local pl = S.Player{}
pl.ph_prop = Prop()
S.timers = {}
check("pickup runs cleanly", attempt(addition, pl), "ok")
check("  ... prop turned shiny red", pl.ph_prop.mat .. " " .. pl.ph_prop.col, "models/shiny 255,0,0")
check("revert after 5s runs cleanly", #S.pump(5), 0)
check("  ... colour restored", pl.ph_prop.mat .. " " .. pl.ph_prop.col, " 255,255,255")
pl.ph_prop = Prop()
addition(pl)
pl.ph_prop = nil   -- lost the prop before the revert
check("prop gone before the revert -> no error", #S.pump(5), 0)

report()
