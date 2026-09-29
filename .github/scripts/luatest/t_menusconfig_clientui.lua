dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- The F1 menu and its menu types are client Derma. These tests load each
-- SHIPPED file whole under the Derma stand-in in derma.lua and drive the same
-- entry points a player does (the ph_x_menu command, button DoClicks, the
-- engine's DBinder "Clear"). The prop-list editor and the taunt window are in
-- t_menusconfig_clientwindows.lua.

local GM = "gamemodes/prop_hunt/gamemode/"
local D, lastSent, lastChat, P = dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "derma.lua")

local grid = D.create("DGrid")

---------------------------------------------------------------- cl_menutypes
print("\n== cl_menutypes: F1 menu building blocks ==")
loadchunk(extract(GM .. "cl_menutypes.lua", "1-999999"), "cl_menutypes.lua")()

-- #177: ErrorNoHalt concatenates every argument and adds no newline.
local ehArgs
ErrorNoHalt = function(...) ehArgs = { n = select("#", ...), ... } end
PHX.CLUI["check"]("ph_x", nil, grid, "L")
check("ThrowError passes ErrorNoHalt one argument", ehArgs and ehArgs.n, 1)
check("ThrowError message ends in a newline", ehArgs and ehArgs[1]:sub(-1), "\n")
check("ThrowError with no command name does not raise", attempt(PHX.CLUI["check"], nil, nil, grid, "L"), "ok")

-- #176: any string init means "read the convar".
CreateConVar("ph_test_slider", "42")
local function sliderValue(init)
  D.all = {}
  PHX.CLUI["slider"]("ph_test_slider", { min = 0, max = 100, init = init, dec = 0, kind = "SERVER" }, grid, "L")
  local s = D.find(D.class("DNumSlider"))
  return s and s._value
end
check("slider init=\"auto\" shows the convar", sliderValue("auto"), 42)
check("slider init=\"DEF_CONVAR\" shows the convar", sliderValue("DEF_CONVAR"), 42)
check("slider init=nil shows the convar", sliderValue(nil), 42)
check("slider init=7 shows 7", sliderValue(7), 7)

-- #43: DBinder's own right-click "Clear" does SetValue(0) -> OnChange(0).
CreateConVar("ph_default_taunt_key", "63")
D.all, D.chat = {}, {}
PHX.CLUI["binder"]("ph_default_taunt_key", false, grid, "L")
local bind = D.find(D.class("DBinder"))
check("binder built with the current key", bind and bind._value, 63)
check("binder Clear does not raise", attempt(bind.SetValue, bind, 0), "ok")
check("binder Clear stores 0", S.cvars["ph_default_taunt_key"].v, "0")
check("binder Clear still confirms in chat", lastChat(), "PHXM_CVAR_CHANGED:ph_default_taunt_key,NONE")
check("binder picking F3 names the key", attempt(bind.SetValue, bind, 63) == "ok" and lastChat(),
      "PHXM_CVAR_CHANGED:ph_default_taunt_key,F3")
check("binder picking F3 stores 63", S.cvars["ph_default_taunt_key"].v, "63")

-- #42/#80: ph_default_lang / ph_force_lang set from server.cfg are never validated.
PHX.LANGUAGES = { en_us = { Name = "English", NameEnglish = "English", code = "en_us" },
                  fr = { Name = "Francais", NameEnglish = "French", code = "fr" } }
CreateConVar("ph_default_lang", "english")
CreateConVar("ph_cl_language", "en_us")
local function langBox(c, d)
  D.all = {}
  local r = attempt(PHX.CLUI["langcombobox"], c, d, grid, "L")
  local cb = D.find(D.class("DComboBox"))
  return r, cb
end
local r, cb = langBox("ph_default_lang", true)
check("langcombobox with an unknown server code does not raise", r, "ok")
check("... says the code is unknown", cb and tostring(cb._value):match("^Error: Language english") ~= nil, true)
check("... still offers every real language", cb and #cb._choices, 2)
S.cvars["ph_default_lang"].v = "fr"
r, cb = langBox("ph_default_lang", true)
check("langcombobox with a known server code shows its name", cb and cb._value, "Francais")
r, cb = langBox(nil, nil)
check("langcombobox for the player's own language", cb and cb._value, "English")
-- cl_lang.lua stores a pack with no Name; a nil label errors in the engine's
-- SetValue and silently drops the choice. Show and offer it by its code.
local function choice(box, data) for _, ch in ipairs(box and box._choices or {}) do if ch[2] == data then return ch end end end
PHX.LANGUAGES.xx = { code = "xx" }
S.cvars["ph_cl_language"].v = "xx"
r, cb = langBox(nil, nil)
check("langcombobox with a nameless pack selected shows its code", cb and cb._value, "xx")
check("  ... and offers it by its code", choice(cb, "xx") and choice(cb, "xx")[1], "xx")
check("  ... next to the named ones (normal play)", choice(cb, "fr") and choice(cb, "fr")[1], "Francais")
PHX.LANGUAGES.xx, S.cvars["ph_cl_language"].v = nil, "en_us"

-- #173: the Set button must send what is in the field now.
CreateConVar("ph_fc_cue_path", "misc/freeze_cam.wav")
D.all, D.boxes, D.chat, S.net.sent = {}, {}, {}, {}
PHX.CLUI["textentry"]("ph_fc_cue_path", "SERVER", grid, "L")
local te = D.find(D.class("DTextEntry"))
local setBtn = D.find(function(p) return p._class == "DButton" and p._text == "MISC_SET" end)
check("textentry shows the current value", te:GetValue(), "misc/freeze_cam.wav")
te:SetText("phx_"); te:OnEnter("phx_")
te:SetText("misc/x.wav")   -- edited again, Enter not pressed a second time
setBtn:DoClick()
check("Set sends the edited text, not the last Enter", lastSent() and lastSent().data[1], "misc/x.wav")
check("... for the right cvar", lastSent() and lastSent().data[2], "ph_fc_cue_path")
check("... over the admin textentry message", lastSent() and lastSent().name, "SvCommandTextEntry")
-- The server has not answered yet and may refuse it (sv_admin replies with an error).
check("... without claiming it changed (no popup)", #D.boxes, 0)
check("... or chat line", #D.chat, 0)
te:SetText("sound\\a.wav"); te:OnEnter("sound\\a.wav"); setBtn:DoClick()
check("Enter then Set still rewrites backslashes", lastSent().data[1], "sound/a.wav")
local sentBefore = #S.net.sent
te:SetText(""); setBtn:DoClick()
check("an empty field sends nothing", #S.net.sent, sentBefore)
check("... and says so", D.boxes[#D.boxes], "PHXM_MSG_INPUT_IS_EMPTY")

-- A client-side entry is applied at once, so it still confirms the change.
CreateConVar("ph_test_client_text", "abc")
D.all, D.boxes, D.chat = {}, {}, {}
PHX.CLUI["textentry"]("ph_test_client_text", false, grid, "L")
D.find(D.class("DTextEntry")):SetText("xyz")
D.find(function(p) return p._class == "DButton" and p._text == "MISC_SET" end):DoClick()
check("client textentry: Set applies the ConVar", S.cvars["ph_test_client_text"].v, "xyz")
check("  ... and confirms it in a popup", #D.boxes, 1)
check("  ... and in chat", lastChat(), "PHXM_CVAR_CHANGED:ph_test_client_text,xyz")

-- The LPS colour entries show "#" .. cvar, relying on the engine to eat one
-- leading '#'. Set must send a valid hex colour whether or not it does.
CreateConVar("lps_halo_color", "#14FA00")
local function hexEntry(eats)
  D.all, S.net.sent = {}, {}
  if eats then
    -- GMod localisation: an unknown "#token" shows without its '#'.
    local set = P.SetText
    P.SetText = function(self, t)
      if self._class == "DTextEntry" and type(t) == "string" and t:sub(1, 1) == "#" then t = t:sub(2) end
      return set(self, t)
    end
    P.SetValue = function(self, v) return P.SetText(self, v) end
  end
  PHX.CLUI["textentry"]("lps_halo_color", "SERVER", grid, "L")
  local e = D.find(D.class("DTextEntry"))
  local b = D.find(function(p) return p._class == "DButton" and p._text == "MISC_SET" end)
  return e, b
end
local pSetText, pSetValue = P.SetText, P.SetValue
-- What the player types lands in the field as-is (no SetText).
local function typeIn(e, s) e._text, e._value = s, s; e:OnEnter(s) end
for _, eats in ipairs({ false, true }) do
  local how = eats and "(engine eats '#')" or "(engine keeps '#')"
  local e, b = hexEntry(eats)
  b:DoClick()
  check("hex colour, Set without editing sends #14FA00 " .. how, lastSent() and lastSent().data[1], "#14FA00")
  typeIn(e, "#CC0000"); b:DoClick()
  check("hex colour, Enter then Set sends #CC0000 " .. how, lastSent() and lastSent().data[1], "#CC0000")
  typeIn(e, "CC0000"); b:DoClick()
  check("hex colour typed without '#' is still a hex colour " .. how,
        lastSent() and util.IsHexColor(lastSent().data[1]), true)
  typeIn(e, "rainbow"); b:DoClick()
  check("'rainbow' is sent unchanged " .. how, lastSent() and lastSent().data[1], "rainbow")
  P.SetText, P.SetValue = pSetText, pSetValue
end

---------------------------------------------------------------- cl_menu
print("\n== cl_menu: F1 menu (ph_x_menu) ==")
-- Record the menu types instead of building them; they are covered above.
local made, realCLUI = {}, PHX.CLUI
PHX.CLUI = setmetatable({}, { __index = function(_, typ)
  return function(c, d, _, l) made[#made + 1] = { typ = typ, c = c, d = d, l = l }; return D.create("DPanel") end
end })
local function madeWhere(pred) for _, m in ipairs(made) do if pred(m) then return m end end end

player_manager.AllValidModels = function() return { alyx = "models/alyx.mdl", barney = "models/barney.mdl" } end
list.Get = function(n) if n == "PlayerOptionsModel" then return { kleiner = "models/kleiner.mdl" } end return {} end
util.PrecacheModel = function() end
CreateConVar("cl_playercolor", "0.24 0.34 0.41")
CreateConVar("ph_use_playermodeltype", "0")
S.boolCVar("ph_use_lang", "0")
CreateConVar("ph_force_lang", "en_us")

-- The mv_* ConVars exactly as sh_mapvote.lua creates them.
CVAR_SERVER_ONLY, CVAR_SERVER_ONLY_NO_NOTIFY = 0, 0
local mvList = loadchunk(extract(GM .. "sh_mapvote.lua", [[^local convarlist = \{]]) .. "\nreturn convarlist", "sh_mapvote.lua")()
local mvBounds = {}
for _, e in ipairs(mvList) do
  CreateConVar(e[1], e[2], e[3], e[4], e[5], e[6])
  mvBounds[e[1]] = { min = e[5], max = e[6] }
end

loadchunk(extract(GM .. "cl_menu.lua", "1-999999"), "cl_menu.lua")()
check("ph_x_menu is registered", S.concommands["ph_x_menu"] and S.concommands["ph_x_menu"].fn, PHX.UI.BaseMainMenu)

local ply = S.Player{ info = { cl_playermodel = "alyx" } }
S.players = { ply }
local function openMenu(p)
  made, D.all = {}, {}
  S.pump(10)   -- flush timers left by an earlier build
  return attempt(PHX.UI.BaseMainMenu, p or ply)
end
local function sheets() return PHX.UI.PnlTab and #PHX.UI.PnlTab._sheets end

check("menu builds (defaults)", openMenu(), "ok")
check("... with all five player tabs", sheets(), 5)

-- #80/#42: forced language with a code nobody validated.
S.cvars["ph_use_lang"].v = "1"
S.cvars["ph_force_lang"].v = "english"
check("menu builds with an unknown ph_force_lang", openMenu(), "ok")
check("... and still builds every tab", sheets(), 5)
local fl = madeWhere(function(m) return m.typ == "label" and tostring(m.l):match("forced language") end)
check("... naming the bad code", fl and fl.l:match("english %(unknown%)") ~= nil, true)
S.cvars["ph_force_lang"].v = "fr"
openMenu()
fl = madeWhere(function(m) return m.typ == "label" and tostring(m.l):match("forced language") end)
check("a valid forced language is named", fl and fl.l:match("is: French$") ~= nil, true)
S.cvars["ph_use_lang"].v = "0"

-- #175: ph_use_playermodeltype picks the model list; anything else falls back to 0.
local function icons() return D.count(D.class("SpawnIcon")) end
S.cvars["ph_use_playermodeltype"].v = "1"
check("model type 1 builds", openMenu(), "ok")
check("... from PlayerOptionsModel", icons(), 1)
S.cvars["ph_use_playermodeltype"].v = "0"
openMenu()
check("model type 0 lists every valid model", icons(), 2)
S.cvars["ph_use_playermodeltype"].v = "7"
check("an out-of-range model type does not break the menu", openMenu(), "ok")
check("... and falls back to every valid model", icons(), 2)
local keep = S.cvars["ph_use_playermodeltype"]
S.cvars["ph_use_playermodeltype"] = nil
check("an unset model type does not break the menu", openMenu(), "ok")
check("... and falls back to every valid model", icons(), 2)
S.cvars["ph_use_playermodeltype"] = keep
keep.v = "0"

-- #179: the MOTD button runs `ulx motd`.
local function motd() return D.find(function(p) return p._class == "DButton" and p._text == "SERVER_INFO_MOTD" end) end
ulx = nil
openMenu()
check("no ULX: MOTD button hidden", motd() and motd():IsVisible(), false)
ulx = {}
openMenu()
check("ULX: MOTD button shown", motd() and motd():IsVisible(), true)
ulx = nil

-- #169: PH_CustomTabMenu fires 0.25 s later; bind it to the menu that queued it.
S.pump(10)   -- let the builds above run their own timers before listening
local tabCalls = {}
hook.Add("PH_CustomTabMenu", "t_menusconfig", function(tab) tabCalls[#tabCalls + 1] = tab end)
openMenu()
local tab1 = PHX.UI.PnlTab
local errs = S.pump(1)
check("tab hook runs once for an open menu", #tabCalls, 1)
check("... on that menu's sheet", tabCalls[1] == tab1, true)
check("... without errors", #errs, 0)
tabCalls = {}
openMenu()
PHX.UI.MainForm:Close()
S.pump(1)
check("menu closed within 0.25 s: tab hook not run", #tabCalls, 0)
tabCalls = {}
openMenu()
PHX.UI.BaseMainMenu(ply)   -- rebuilt inside the window (AdminGroupInfo does this)
S.pump(1)
check("menu rebuilt within 0.25 s: tab hook runs once", #tabCalls, 1)
check("... on the new sheet", tabCalls[1] == PHX.UI.PnlTab, true)
hook.Remove("PH_CustomTabMenu", "t_menusconfig")

-- #247: Map Vote sliders must not offer values the ConVar clamps away.
local staff = S.Player{ staff = true, info = { cl_playermodel = "alyx" } }
check("staff menu builds", openMenu(staff), "ok")
check("... with admin and map vote tabs", sheets(), 7)
for _, name in ipairs({ "mv_maplimit", "mv_timelimit", "mv_mapbeforerevote", "mv_rtvcount" }) do
  local s = madeWhere(function(m) return m.typ == "slider" and m.c == name end)
  local b = mvBounds[name]
  check(name .. " slider min >= ConVar min", s and b and s.d.min >= b.min, true)
  check(name .. " slider max <= ConVar max", s and b and (b.max == nil or s.d.max <= b.max), true)
end
check("mv_maplimit slider starts at the ConVar min", madeWhere(function(m) return m.c == "mv_maplimit" end).d.min, mvBounds.mv_maplimit.min)
check("mv_mapbeforerevote slider spans the ConVar",
      (function() local d = madeWhere(function(m) return m.c == "mv_mapbeforerevote" end).d return d.min .. "-" .. d.max end)(),
      mvBounds.mv_mapbeforerevote.min .. "-" .. mvBounds.mv_mapbeforerevote.max)

-- ph_game_time 0 is no time limit. A slider starting at 20 showed a server on 0
-- as 20, and touching it switched the limit back on.
local gameTime = madeWhere(function(m) return m.typ == "slider" and m.c == "ph_game_time" end)
check("ph_game_time slider reaches 0 (no time limit)", gameTime and gameTime.d.min, 0)
check("ph_game_time slider still goes up to 300", gameTime and gameTime.d.max, 300)

-- ...and the ConVar agrees: the server's own floor is the slider's.
local cvarLine = extract(GM .. "sh_convar.lua", [=[^CVAR\["ph_game_time"\]]=])
local cvarMin = cvarLine:match("{%s*min%s*=%s*(%-?%d+)")
check("ph_game_time ConVar min is the slider's", tonumber(cvarMin), gameTime and gameTime.d.min)

-- The slider says what 0 does, on its label and its tooltip, both of which
-- cl_menutypes builds from this key.
local english = loadblocks("english.lua", extract(GM .. "langs/english.lua", "1-999999") .. "\nreturn L",
  "local PHX = setmetatable({ LANGUAGES = {} }, { __index = PHX })")
check("ph_game_time slider label is PHXM_ADMIN_GAME_TIME", gameTime and gameTime.l, "PHXM_ADMIN_GAME_TIME")
check("  ...which says 0 is no limit", tostring(english.PHXM_ADMIN_GAME_TIME):find("0 = no limit", 1, true) ~= nil, true)
-- Built for real, in English.
local qtrans = PHX.QTrans
function PHX:QTrans(k) return english[k] or k end
D.all = {}
realCLUI["slider"](gameTime.c, gameTime.d, grid, gameTime.l)
PHX.QTrans = qtrans
local gtSlider = D.find(D.class("DNumSlider"))
local gtLabel = D.find(function(p) return p._class == "DLabel" and p._text == english.PHXM_ADMIN_GAME_TIME end)
check("  ...on the slider's tooltip", gtSlider and gtSlider._tooltip, english.PHXM_ADMIN_GAME_TIME)
check("  ...and its label", gtLabel ~= nil, true)
check("  ...which can be dragged to 0", gtSlider and gtSlider._min, 0)

-- The Map Vote tab's buttons. Once the game has ended the server refuses to
-- cancel its vote, so the Stop button goes; mid-game both stay.
local function mvButtons()
  local b = madeWhere(function(m) return m.typ == "btn" and m.d and m.d[1] and m.d[1][1] == "PHXM_MV_START" end)
  local names = {}
  for i = 1, b and #b.d or 0 do names[i] = b.d[i][1] end
  return table.concat(names, ","), b
end
local function pressed(b, i)
  local lp = LocalPlayer
  LocalPlayer, staff.concmds = function() return staff end, {}
  local res = attempt(b.d[i][2])
  LocalPlayer = lp
  return res == "ok" and staff.concmds[#staff.concmds] or res
end
SetGlobalBool("IsEndOfGame", nil)
openMenu(staff)
local names, btns = mvButtons()
check("mid-game: the Map Vote tab has Start and Stop", names, "PHXM_MV_START,PHXM_MV_STOP")
check("  ...Stop still runs mv_stop", btns and pressed(btns, 2), "mv_stop")
SetGlobalBool("IsEndOfGame", true)
check("end of game: the menu builds", openMenu(staff), "ok")
names, btns = mvButtons()
check("  ...with Start and no Stop", names, "PHXM_MV_START")
check("  ...Start still runs mv_start", btns and pressed(btns, 1), "mv_start")
D.all = {}
realCLUI["btn"]("", btns.d, grid, "")
check("  ...and cl_menutypes draws the one button", D.count(D.class("DButton")), 1)
SetGlobalBool("IsEndOfGame", nil)

report()
