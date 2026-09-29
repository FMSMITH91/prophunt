dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- The scoreboard's right-click admin menu (base_phx cl_scoreboard_admin.lua).
-- Every action runs later than the menu opens - a click, or a ban reason
-- dialog that deliberately outlives TAB - so the target can have left by then.

-- Derma / engine stand-ins --------------------------------------------------

local function Menu()
  local m = { options = {}, subs = {} }
  function m:AddOption(label, fn)
    local o = { label = label, fn = fn }
    function o.SetIcon() return o end
    function o.SetEnabled() end
    self.options[#self.options + 1] = o
    return o
  end
  function m.AddSpacer() end
  function m:AddSubMenu(label)
    local sub = Menu()
    self.subs[label] = sub
    return sub, { SetIcon = function() end }
  end
  function m:find(label)
    for _, o in ipairs(self.options) do if o.label == label then return o end end
    error("no menu option " .. tostring(label), 2)
  end
  return m
end
function DermaMenu() return Menu() end

-- Removing a frame runs its OnRemove, as Panel:Remove does.
local function Frame(t)
  t.__valid = true
  function t:Remove() self.__valid = false; if self.OnRemove then self:OnRemove() end end
  return t
end
local dialogs = {}
function Derma_StringRequest(title, text, default, fnEnter)
  local f = Frame{ kind = "request", title = title, fnEnter = fnEnter }
  dialogs[#dialogs + 1] = f
  return f
end
function Derma_Query(text, title, yes, fnYes)
  local f = Frame{ kind = "query", text = text, fnYes = fnYes }
  dialogs[#dialogs + 1] = f
  return f
end
-- Derma_StringRequest's OK button: Window:Close() then fnEnter( value ).
local function pressOK(req, value) req:Remove(); req.fnEnter(value) end

local clicker
gui = { EnableScreenClicker = function(b) clicker = b end }
local clipboard
function SetClipboardText(s) clipboard = s end

local ran = {}
function RunConsoleCommand(...) ran[#ran + 1] = { ... } end
local function lastCmd() local c = ran[#ran]; return c and table.concat((function()
  local t = {} for i, v in ipairs(c) do t[i] = tostring(v) end return t end)(), " ") or "none" end

local allowed = {}
ULib = { ucl = { query = function(_, access) return allowed[access] end } }
ulx = {}

local admin = S.Player{ name = "Admin", sid = "STEAM_0:0:1", staff = true }
function LocalPlayer() return admin end

-- A player that turns into a NULL entity when `state.gone` is set: every
-- method then raises, exactly as a disconnected Player does in GMod.
local function Target(t)
  local real = S.Player(t)
  local state = { gone = false }
  local extra = {
    IsMuted = function() return real._muted == true end,
    SetMuted = function(_, b) real._muted = b end,
    UserID = function() return 42 end,
  }
  local proxy = setmetatable({}, {
    __index = function(_, k)
      if k == "__valid" then return not state.gone end
      if state.gone then error("Tried to use a NULL entity!", 2) end
      local v = extra[k] or real[k]
      if type(v) == "function" then return function(_, ...) return v(real, ...) end end
      return v
    end,
    __newindex = function(_, k, v)
      if state.gone then error("Tried to use a NULL entity!", 2) end
      real[k] = v
    end })
  return proxy, state, real
end

-- The shipped file -------------------------------------------------------------

loadblocks("cl_scoreboard_admin.lua",
  extract("gamemodes/base_phx/gamemode/cl_scoreboard_admin.lua", "1-999999"))

-- cl_scores.lua owns these; the menu only asks them.
function PHX:CanOpenSteamProfile() return true end
function PHX:OpenSteamProfile() end
function PHX:CanMutePlayer() return true end

local function grant(...) allowed = {} for _, a in ipairs{ ... } do allowed[a] = true end end
local ALL = { "ulx gag", "ulx ungag", "ulx mute", "ulx unmute", "ulx kick", "ulx ban", "ulx banid" }

print("\n== SBTranslate formats its fallback with the arguments ==")
-- FTranslate in the shim echoes the key back, which is what the real one does
-- for a string no language file defines.
check("missing key, args -> formatted fallback",
  PHX:SBTranslate("DERMA_MENU_CONFIRM_BAN", "Ban %s for %s?", "Griefer", "1 day"), "Ban Griefer for 1 day?")
check("missing key, no args -> fallback untouched",
  PHX:SBTranslate("DERMA_MENU_KICK", "Kick %s?"), "Kick %s?")
check("fallback with a stray % does not raise",
  attempt(function() return PHX:SBTranslate("NOPE", "50%", 1) end), "ok")
local realFT = PHX.FTranslate
PHX.FTranslate = function(_, k, ...) if k == "K" then return string.format("Tr %s", ...) end return k end
check("defined key -> the translation wins", PHX:SBTranslate("K", "fb %s", "x"), "Tr x")
PHX.FTranslate = nil
check("no FTranslate at all -> formatted fallback", PHX:SBTranslate("K", "Kick %s?", "Bob"), "Kick Bob?")
PHX.FTranslate = realFT

print("\n== Ban: normal play still bans the connected player ==")
grant(unpack(ALL))
local ply, state = Target{ name = "Griefer", sid = "STEAM_0:0:5" }
local menu = PHX:OpenPlayerMenu(ply)
menu.subs["Ban"]:find("1 day").fn()
local req = dialogs[#dialogs]
check("reason prompt titled with the name", req.title, "Ban Griefer (1 day)")
pressOK(req, "griefing")
local q = dialogs[#dialogs]
check("confirm names the player", q.text, "Ban Griefer for 1 day?")
q.fnYes()
check("connected -> ulx ban by $SteamID", lastCmd(), "ulx ban $STEAM_0:0:5 1440 griefing")

print("\n== Ban: the target leaves while the reason is typed ==")
ply, state = Target{ name = "Griefer", sid = "STEAM_0:0:5" }
menu = PHX:OpenPlayerMenu(ply)
menu.subs["Ban"]:find("1 day").fn()
req = dialogs[#dialogs]
state.gone = true
local before = #dialogs
check("pressing OK after they left does not raise", attempt(pressOK, req, "griefing"), "ok")
check("the confirm dialog still opens", #dialogs, before + 1)
q = dialogs[#dialogs]
check("confirm still names them", q.text, "Ban Griefer for 1 day?")
check("confirming does not raise", attempt(q.fnYes), "ok")
check("left -> ulx banid by SteamID", lastCmd(), "ulx banid STEAM_0:0:5 1440 griefing")

-- Without banid access, fall back to ulx ban on the SteamID and let ULX answer.
grant("ulx gag", "ulx ungag", "ulx mute", "ulx unmute", "ulx kick", "ulx ban")
ply, state = Target{ name = "Griefer", sid = "STEAM_0:0:5" }
menu = PHX:OpenPlayerMenu(ply)
menu.subs["Ban"]:find("1 week").fn()
req = dialogs[#dialogs]
state.gone = true
pressOK(req, "r")
dialogs[#dialogs].fnYes()
check("left, no banid access -> ulx ban $SteamID", lastCmd(), "ulx ban $STEAM_0:0:5 10080 r")

-- A bot has no SteamID to ban; it is still targeted by UserID.
grant(unpack(ALL))
ply, state = Target{ name = "Bot01", sid = "BOT", bot = true }
menu = PHX:OpenPlayerMenu(ply)
menu.subs["Ban"]:find("Permanent").fn()
req = dialogs[#dialogs]
state.gone = true
pressOK(req, "r")
dialogs[#dialogs].fnYes()
check("bot that left -> no banid, ulx ban $UserID", lastCmd(), "ulx ban $42 0 r")

print("\n== Other menu actions after the target left ==")
ply, state = Target{ name = "Leaver", sid = "STEAM_0:1:7" }
menu = PHX:OpenPlayerMenu(ply)
state.gone = true
clipboard = nil
check("Copy SteamID does not raise", attempt(menu:find("Copy SteamID").fn), "ok")
check("Copy SteamID still copies it", clipboard, "STEAM_0:1:7")
check("Mute for me does not raise", attempt(menu:find("Mute for me").fn), "ok")
check("kick reason does not raise", attempt(menu.subs["Kick"]:find("Trolling").fn), "ok")
dialogs[#dialogs].fnYes()
check("kick goes to the captured $SteamID", lastCmd(), "ulx kick $STEAM_0:1:7 Trolling")
check("custom kick reason does not raise", attempt(menu.subs["Kick"]:find("Custom reason...").fn), "ok")

print("\n== Normal play: connected targets ==")
local real
ply, state, real = Target{ name = "Chatty", sid = "STEAM_0:0:9" }
menu = PHX:OpenPlayerMenu(ply)
check("menu title is the name", menu.options[1].label, "Chatty")
menu:find("Mute for me").fn()
check("Mute for me mutes a connected player", real._muted, true)
menu:find("Gag (voice)").fn()
check("gag -> ulx gag $SteamID", lastCmd(), "ulx gag $STEAM_0:0:9")
menu:find("Mute (text chat)").fn()
check("mute -> ulx mute $SteamID", lastCmd(), "ulx mute $STEAM_0:0:9")
menu.subs["Kick"]:find("Idle").fn()
check("kick confirm names them", dialogs[#dialogs].text, "Kick Chatty?\nIdle")
dialogs[#dialogs].fnYes()
check("kick -> ulx kick $SteamID reason", lastCmd(), "ulx kick $STEAM_0:0:9 Idle")

print("\n== A chained dialog keeps the cursor ==")
-- The ban flow opens the confirm from the reason prompt's OK. If the prompt's
-- OnRemove lands after the confirm is tracked, it must not wipe the confirm's
-- slot or release the cursor underneath it.
g_ScoreBoard = nil
PHX.SBDialog = nil
clicker = true
local A = PHX:TrackScoreboardDialog(Frame{})
local B = PHX:TrackScoreboardDialog(Frame{})
A:Remove()
check("older dialog closing keeps the newer one tracked", PHX:ScoreboardDialogOpen(), true)
check("older dialog closing keeps the cursor", clicker, true)
B:Remove()
check("last dialog closing clears the slot", PHX:ScoreboardDialogOpen(), false)
check("last dialog closing releases the cursor", clicker, false)

-- Normal play: one dialog, board hidden -> released; board open -> kept.
clicker = true
PHX:TrackScoreboardDialog(Frame{}):Remove()
check("single dialog, board hidden -> cursor released", clicker, false)
clicker = true
g_ScoreBoard = { __valid = true, IsVisible = function() return true end }
PHX:TrackScoreboardDialog(Frame{}):Remove()
check("single dialog, board open -> cursor kept", clicker, true)
g_ScoreBoard = nil

report()
