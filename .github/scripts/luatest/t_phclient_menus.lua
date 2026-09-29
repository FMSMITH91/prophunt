dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- Client menus and receivers from cl_init.lua: the key-hint popup, the F1/F2
-- splashes, the decoy death notice and the freeze-cam sound.

CLIENT, SERVER = true, false
function ScrW() return 1920 end
function ScrH() return 1080 end
function Format(...) return string.format(...) end
string.Replace = function(s, find, rep)
  return (s:gsub(find:gsub("%p", "%%%0"), (rep:gsub("%%", "%%%%"))))
end
function PHX:GetCLCVar(n) return PHX:GetCVar(n) end

-- GMod's IsValid asks the object; a plain table with no IsValid is not valid.
function IsValid(e)
  if e == nil or e == NULL then return false end
  local f = e.IsValid
  return f ~= nil and f(e) == true
end

-- input.GetKeyName returns nil outside 1..0x411, so a cleared bind (0) has no name.
input = { GetKeyName = function(k)
  if type(k) ~= "number" or k < 1 or k > 0x411 then return nil end
  return "k" .. k
end }

-- A VGUI panel that accepts any method call and records the ones tests read.
local created = {}
local function Panel(kind)
  local p = { __kind = kind, __valid = true, items = {}, texts = {}, popups = 0 }
  created[#created + 1] = p
  local methods = {
    IsValid = function(self) return self.__valid end,
    Remove = function(self) self.__valid = false end,
    Add = function(_, k) return Panel(k) end,
    AddItem = function(self, it) self.items[#self.items + 1] = it end,
    SetText = function(self, t) self.texts[#self.texts + 1] = t end,
    SetDisabled = function(self, b) self.disabled = b end,
    MakePopup = function(self) self.popups = self.popups + 1 end,
    AddSelectButton = function(self, name, fn)
      local b = Panel("button"); b.name, b.fn = name, fn
      local list = rawget(self, "buttons") or {}
      list[#list + 1] = b
      rawset(self, "buttons", list)
      return b
    end,
    GetWide = function() return 256 end, GetColWide = function() return 248 end,
    GetRowHeight = function() return 32 end,
  }
  return setmetatable(p, { __index = function(_, k) return methods[k] or function() end end })
end
local splashes = 0
vgui = {
  Create = function(kind) return Panel(kind) end,
  CreateFromTable = function()
    splashes = splashes + 1
    local s = Panel("splash"); s.lblFooterText = Panel("label")
    return s
  end,
}
chat = { AddText = function() end }

local ME
function LocalPlayer() return ME end

print("\n== [#37] key-hint popup survives a cleared key ==")
S.boolCVar("ph_show_tutor_control", "1"); CreateConVar("ph_hunter_blindlock_time", "30")
for cv, v in pairs{ ph_thirdperson_key = 57, ph_default_taunt_key = 63, ph_default_customtaunt_key = 46,
                    ph_default_rotation_lock_key = 61, ph_prop_menu_key = 68, ph_prop_midair_freeze_key = 56,
                    ph_cl_decoy_spawn_key = 2, ph_cl_unstuck_key = 66 } do
  CreateConVar(cv, tostring(v))
end
loadblocks("cl_init.lua@ShowTutorPopup",
  "local curshow = 0\n" .. extractAll("gamemodes/prop_hunt/gamemode/cl_init.lua", {
    [[^local DefaultKeysTut = \{]], [[^function PHX:ShowTutorPopup]] }))

-- Returns ok, whether the popup was finished (AddItem on the DNotify), and the
-- key labels it built.
local function popup(tm)
  ME = S.Player{ team = tm }
  created = {}
  local ok = attempt(PHX.ShowTutorPopup, PHX)
  local finished, keys = false, {}
  for _, p in ipairs(created) do
    if p.__kind == "DNotify" and #p.items > 0 then finished = true end
    if p.__kind == "DLabel" and p.texts[1] and #p.texts[1] <= 4 then keys[#keys + 1] = p.texts[1] end
  end
  table.sort(keys)
  return ok, finished, table.concat(keys, ",")
end
local ok, done, keys = popup(TEAM_HUNTERS)
check("hunter, all keys bound: ok", ok, "ok")
check("hunter, all keys bound: popup finished", done, true)
check("hunter, all keys bound: third-person key shown", keys:find("K57", 1, true) ~= nil, true)
S.cvars["ph_thirdperson_key"].v = "0"
ok, done, keys = popup(TEAM_HUNTERS)
check("hunter, third-person key cleared: ok", ok, "ok")
check("hunter, third-person key cleared: popup finished", done, true)
check("hunter, third-person key cleared: shown as ?", keys:find("?", 1, true) ~= nil, true)
S.cvars["ph_thirdperson_key"].v = "57"
S.cvars["ph_cl_unstuck_key"].v = "0"
ok, done = popup(TEAM_PROPS)
check("prop, unstuck key cleared: ok", ok, "ok")
check("prop, unstuck key cleared: popup finished", done, true)
S.cvars["ph_cl_unstuck_key"].v = "66"
ok, done = popup(TEAM_PROPS)
check("prop, all keys bound: popup finished", done, true)
ok, done = popup(TEAM_SPECTATOR)
check("spectator: no popup", ok == "ok" and not done, true)

print("\n== [#248] F1 help splash is a singleton ==")
GAMEMODE.VGUISplash = {}
GAMEMODE.GetGameTimeLeft = function() return -1 end
GAMEMODE.PHXContributors = ""
GM = GAMEMODE
loadblocks("cl_init.lua@ShowHelp",
  extractAll("gamemodes/prop_hunt/gamemode/cl_init.lua", { [[^local HelpPanel$]], [[^function GM:ShowHelp]] }))
ME = S.Player{ team = TEAM_PROPS }
splashes, created = 0, {}
check("first F1: ok", attempt(GAMEMODE.ShowHelp, GAMEMODE), "ok")
check("second F1 before the first closes: ok", attempt(GAMEMODE.ShowHelp, GAMEMODE), "ok")
check("two F1s -> one splash", splashes, 1)
local help = created[1]
check("the open splash is brought forward again", help and help.popups, 2)
help:Remove()
GAMEMODE:ShowHelp()
check("after closing it, F1 opens a new one", splashes, 2)

print("\n== [#254] team menu keeps your own team's button disabled ==")
S.teamFull = {}
GAMEMODE.AllowSpectating = true
GAMEMODE.CustomTeamHasEnoughPlayers = function(_, id) return S.teamFull[id] == true end
team.GetAllTeams = function() return { [TEAM_HUNTERS] = { Color = {} }, [TEAM_PROPS] = { Color = {} } } end
loadblocks("cl_init.lua@ShowTeam",
  extractAll("gamemodes/prop_hunt/gamemode/cl_init.lua", { [[^local TeamPanel = \{\}]], [[^function GM:ShowTeam]] }))
ME = S.Player{ team = TEAM_PROPS }
S.players = { ME }
created = {}
check("F2: ok", attempt(GAMEMODE.ShowTeam, GAMEMODE), "ok")
local panel
for _, p in ipairs(created) do if rawget(p, "buttons") then panel = p end end
local btn = {}
for _, b in ipairs(panel and rawget(panel, "buttons") or {}) do b:Think(); btn[b.name] = b end
check("own team (Props) disabled after a frame", btn.Props and btn.Props.disabled, true)
check("other team (Hunters) enabled", btn.Hunters and btn.Hunters.disabled, false)
S.teamFull[TEAM_HUNTERS] = true
btn.Hunters:Think()
check("other team full -> disabled", btn.Hunters.disabled, true)
S.teamFull[TEAM_HUNTERS] = nil
ME._team = TEAM_HUNTERS
btn.Props:Think(); btn.Hunters:Think()
check("after switching: old team re-enabled", btn.Props.disabled, false)
check("after switching: new team disabled", btn.Hunters.disabled, true)

print("\n== [#212] decoy death notice with an unknown attacker ==")
local notices = {}
GAMEMODE.AddDeathNotice = function(_, a) notices[#notices + 1] = a end
net.ReadEntity = function() return table.remove(S.net.readq, 1) end
loadblocks("cl_init.lua@DeathNoticeDecoy",
  extractAll("gamemodes/prop_hunt/gamemode/cl_init.lua", {
    [[^function PHX:DrawDecoyDeathNotice]], [[^net\.Receive\( "PHX\.DeathNoticeDecoy"]] }))
S.net.readq = { S.Player{ name = "Hunter1", team = TEAM_HUNTERS }, NULL }
check("valid attacker: ok", attempt(S.receivers["PHX.DeathNoticeDecoy"]), "ok")
check("valid attacker: notice shown", notices[1], "Hunter1")
S.net.readq = { NULL, NULL }
check("NULL attacker (still joining): no error", attempt(S.receivers["PHX.DeathNoticeDecoy"]), "ok")
check("NULL attacker: no notice", #notices, 1)

print("\n== [#163] freeze-cam cue follows the server's ph_fc_cue_path ==")
local played = {}
surface = { PlaySound = function(s) played[#played + 1] = s end }
PHX.FreezeCamSounds = { "misc/fc_from_list.wav" }
S.boolCVar("ph_fc_use_single_sound", "1"); CreateConVar("ph_fc_cue_path", "misc/freeze_cam.wav")
loadblocks("cl_init.lua@PlayFreezeCamSound",
  extract("gamemodes/prop_hunt/gamemode/cl_init.lua", [[^net\.Receive\("PlayFreezeCamSound"]]))
PHX.LegalSoundPath = "misc/freeze_cam.wav"   -- what the client captured at load
S.cvars["ph_fc_cue_path"].v = "mysounds/fc.wav"
S.receivers["PlayFreezeCamSound"]()
check("custom cue path is played", played[#played], "mysounds/fc.wav")
S.cvars["ph_fc_cue_path"].v = "misc/freeze_cam.wav"
S.receivers["PlayFreezeCamSound"]()
check("default cue path is played", played[#played], "misc/freeze_cam.wav")
S.cvars["ph_fc_use_single_sound"].v = "0"
S.receivers["PlayFreezeCamSound"]()
check("single sound off -> the sound list", played[#played], "misc/fc_from_list.wav")

report()
