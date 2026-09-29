dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- Smaller server fixes, run as shipped: server-side translation falls back to
-- English, a plugin with missing fields can't break the plugin list, the OBB
-- config survives every round's map cleanup, PHXChatInfo's argument table, and
-- the base_phx paths whose dead code was removed.

local ROOT = (debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "../../../"
local function lineOf(path, pat)
  local n = 0
  for line in io.lines(ROOT .. path) do n = n + 1; if line:match(pat) then return n end end
  error("no line matching " .. pat .. " in " .. path)
end

print("\n== server-side translation falls back to English ==")
local SH = "gamemodes/prop_hunt/gamemode/sh_init.lua"
loadblocks("sh_init.lua@translate", extractAll(SH, {
  [[^\s+local function GetTranslation]], [[^\s+function PHX:SVTranslate]] }) .. "\n" ..
  extract(SH, lineOf(SH, "^local strteam = {}") .. "-" .. (lineOf(SH, "^function PHX:TranslateName") - 1)) .. "\n" ..
  extract(SH, [[^function PHX:TranslateName]]))

PHX.LANGUAGES = {
  en_us = { PHX_TEAM_HUNTERS = "Hunters", PHX_TEAM_PROPS = "Props", LD_PRESS2SHOOT = "Press [%s] to shoot %s !" },
  de    = { PHX_TEAM_HUNTERS = "Jaeger", PHX_TEAM_PROPS = "Requisiten" },
}
S.boolCVar("ph_use_lang", "0"); CreateConVar("ph_force_lang", "en_us")
local function ply(lang) return S.Player{ info = { ph_cl_language = lang } } end

check("German player: German (unchanged)", PHX:TranslateName(TEAM_HUNTERS, ply("de")), "Jaeger")
check("English player: English (unchanged)", PHX:TranslateName(TEAM_HUNTERS, ply("en_us")), "Hunters")
check("no player: English (unchanged)", PHX:TranslateName(TEAM_PROPS), "Props")
check("addon language the server lacks: English, not !error", PHX:TranslateName(TEAM_HUNTERS, ply("vi_vn")), "Hunters")
check("bot (empty ph_cl_language): English, not !error", PHX:TranslateName(TEAM_PROPS, ply("")), "Props")
check("no ph_cl_language at all: English", PHX:TranslateName(TEAM_PROPS, ply(nil)), "Props")
check("key missing in their language: English", PHX:SVTranslate(ply("de"), "LD_PRESS2SHOOT", "RMB", "RPG"), "Press [RMB] to shoot RPG !")
check("unknown language, format args: English, formatted", PHX:SVTranslate(ply("xx"), "LD_PRESS2SHOOT", "RMB", "RPG"), "Press [RMB] to shoot RPG !")
check("key missing everywhere: the key, no error", attempt(PHX.SVTranslate, PHX, ply("de"), "NO_SUCH_KEY"), "ok")
S.cvars["ph_use_lang"].v = "1"; S.cvars["ph_force_lang"].v = "de"
check("forced German: German for everyone", PHX:TranslateName(TEAM_HUNTERS, ply("en_us")), "Jaeger")
S.cvars["ph_force_lang"].v = "xx"
check("forced unknown language: English", PHX:TranslateName(TEAM_HUNTERS, ply("de")), "Hunters")
S.cvars["ph_use_lang"].v = "0"

print("\n== a plugin with missing fields cannot break the plugin list ==")
loadblocks("sh_init.lua@plugins", extract(SH, [[^function PHX:InitializePlugin]]))
local registered = {
  Good    = { name = "Good One", version = "1.2", info = "does things", settings = { { "a" } }, client = { { "b" } } },
  Sloppy  = { name = "Sloppy" },                             -- no version/info/settings/client
  Broken  = "not a table",
}
list.Get = function(id) if id == "PHX.Plugins" then return table.Copy(registered) end return {} end
PHX.PLUGINS = {}
check("InitializePlugin: no error", attempt(PHX.InitializePlugin, PHX), "ok")
local errs = S.pump(0.1)
check("verbose listing (runs even with phx_verbose 0): no error", errs[1], nil)
local sl = PHX.PLUGINS.Sloppy
check("sloppy plugin: loaded", sl ~= nil, true)
check("sloppy plugin: settings/client are tables", sl and (type(sl.settings) == "table" and type(sl.client) == "table"), true)
check("sloppy plugin: version/info are strings", sl and (type(sl.version) == "string" and type(sl.info) == "string"), true)
local good = PHX.PLUGINS.Good
check("good plugin: fields untouched", good and (good.name .. "|" .. good.version .. "|" .. good.info), "Good One|1.2|does things")
check("good plugin: settings untouched", good and good.settings[1][1], "a")
check("non-table entry: skipped", PHX.PLUGINS.Broken, nil)

print("\n== OBB config survives the per-round map cleanup ==")
local BOARD = "models/props_debris/wood_board05a.mdl"
local mapEnts = {}
local function mapProp() local e = { __valid = true, _nw = {} }
  function e:GetModel() return BOARD end
  function e:EntIndex() return 5 end
  function e:SetNWBool(k, v) self._nw[k] = v end
  function e:GetNWBool(k, d) local v = self._nw[k]; if v == nil then return d end return v end
  mapEnts = { e }; return e end
ents.FindByModel = function(m) return m:lower() == BOARD and mapEnts or {} end
S.fileExists["phx_data/obb/ph_test.txt"], S.fileExists["phx_data/obb"] = true, true
local fileData = "v1"
file.Read = function() return fileData end
S.json = { v1 = { { BOARD, { min = { -1, -4, 0 }, max = { 1, 4, 96 } } } },
           v2 = { { BOARD, { min = { -2, -8, 0 }, max = { 2, 8, 50 } } } } }
PHX.CustomHulls = nil
loadblocks("sv_bbox.lua", extract("gamemodes/prop_hunt/gamemode/sv_bbox.lua", "1-999999"))
S.boolCVar("ph_reload_obb_setting_everyround", "0")

S.timers = {}
local first = mapProp()
S.fire("Initialize"); S.pump(2)
check("map start: the prop has its hull", first:GetNWBool("hasCustomHull", false), true)

local respawned = mapProp()                    -- game.CleanUpMap recreated it
S.fire("PostCleanupMap")
check("ph_reload_obb_setting_everyround 0: re-applied after cleanup", respawned:GetNWBool("hasCustomHull", false), true)
check("  ... from the data loaded at map start", respawned.m_Hull and respawned.m_Hull[2].z, 96)
fileData = "v2"
respawned = mapProp(); S.fire("PostCleanupMap")
check("  ... and the file is not re-read", respawned.m_Hull and respawned.m_Hull[2].z, 96)

S.cvars["ph_reload_obb_setting_everyround"].v = "1"
respawned = mapProp(); S.fire("PostCleanupMap")
check("ph_reload_obb_setting_everyround 1: re-applied after cleanup", respawned:GetNWBool("hasCustomHull", false), true)
check("  ... with the file re-read", respawned.m_Hull and respawned.m_Hull[2].z, 50)
S.fileExists["phx_data/obb/ph_test.txt"] = false
respawned = mapProp()
check("config file removed: cleanup still fine", attempt(S.fire, "PostCleanupMap"), "ok")
check("  ... and no hull applied", respawned:GetNWBool("hasCustomHull", false), false)

print("\n== PHXChatInfo / PHXNotify argument table ==")
local SP = "gamemodes/prop_hunt/gamemode/sh_player.lua"
-- Loaded onto a table of our own so the shim's recording PHXChatInfo stays in place.
FAKEMETA = {}
loadblocks("sh_player.lua@chat", extractAll(SP, {
  [[^\s+local kinds = \{]], [[^\s+function Player:PHXNotify]], [[^\s+function Player:PHXChatInfo]] }),
  "local Player = FAKEMETA")
local fake = FAKEMETA
local function lastTable() local m = S.net.sent[#S.net.sent]; return m.data[#m.data] end
S.net.sent = {}
fake.PHXChatInfo({}, "NOTICE", "SOME_KEY")
check("ChatInfo, no args: empty table", next(lastTable()), nil)
fake.PHXChatInfo({}, "NOTICE", "SOME_KEY", "a", "b")
check("ChatInfo, two args: ARG1/ARG2", lastTable().ARG1 .. lastTable().ARG2, "ab")
fake.PHXNotify({}, "SOME_KEY", "HINT", 5, true)
check("Notify, no args: empty table", next(lastTable()), nil)
fake.PHXNotify({}, "SOME_KEY", "HINT", 5, true, "x")
check("Notify, one arg: ARG1", lastTable().ARG1, "x")

print("\n== base_phx paths around the removed dead code ==")
local BINIT = "gamemodes/base_phx/gamemode/init.lua"
loadblocks("base_phx init.lua", extractAll(BINIT, {
  [[^function GM:OnPlayerChangedTeam]], [[^function GM:FindLeastCommittedPlayerOnTeam]] }))
local p = S.Player{ team = TEAM_PROPS }
function p:EyePos() return Vector(1, 2, 3) end
p._alive = false
GAMEMODE:OnPlayerChangedTeam(p, TEAM_PROPS, TEAM_HUNTERS)
check("team -> team: LastTeamChange recorded", p.LastTeamChange, CurTime())
check("team -> team: not respawned", p._alive, false)
p.LastTeamChange = nil
GAMEMODE:OnPlayerChangedTeam(p, TEAM_SPECTATOR, TEAM_HUNTERS)
check("spectator -> team: respawned", p._alive, true)
check("spectator -> team: no LastTeamChange", p.LastTeamChange, nil)
p._alive = false
GAMEMODE:OnPlayerChangedTeam(p, TEAM_HUNTERS, TEAM_SPECTATOR)
check("team -> spectator: respawned in place", p._alive and tostring(p:GetPos()), tostring(Vector(1, 2, 3)))

loadblocks("round_controller.lua", extract("gamemodes/base_phx/gamemode/round_controller.lua", [[^function GM:CheckPlayerDeathRoundEnd]]))
GAMEMODE.RoundBased, GAMEMODE.RoundEndsWhenOneTeamAlive = true, true
local result
function GAMEMODE:RoundEndWithResult(r) result = r end
local alive = {}
function GAMEMODE:GetTeamAliveCounts() return alive end
SetGlobalBool("InRound", true)
alive = { [TEAM_HUNTERS] = 2 }; result = nil; GAMEMODE:CheckPlayerDeathRoundEnd()
check("base round check: one team left wins", result, TEAM_HUNTERS)
alive = {}; result = nil; GAMEMODE:CheckPlayerDeathRoundEnd()
check("base round check: nobody left, draw", result, 1001)
alive = { [TEAM_HUNTERS] = 1, [TEAM_PROPS] = 1 }; result = nil; GAMEMODE:CheckPlayerDeathRoundEnd()
check("base round check: both alive, no result", result, nil)

report()
