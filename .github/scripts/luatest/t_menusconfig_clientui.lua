dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- The F1 menu, its menu types, the prop-list editor and the taunt window are all
-- client Derma. These tests load each SHIPPED file whole under a small Derma
-- stand-in and drive the same entry points a player does (the ph_x_menu and
-- ph_showtaunts commands, button DoClicks, the engine's DBinder "Clear").

local REPO = (debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "../../../"
local GM = "gamemodes/prop_hunt/gamemode/"

-- The files print their own progress; keep the PASS/FAIL lines readable.
local realprint = print
print = function(s, ...)
  if type(s) == "string" and s:match("^%[Taunt Menu%]") then return end
  return realprint(s, ...)
end

---------------------------------------------------------------- Derma stand-in
-- Anything not modelled below is a do-nothing object: every field is callable
-- and returns it again, and writes to it are dropped. Only PascalCase keys fall
-- through to it, so a data field the code never set (ic.selected) reads nil
-- exactly as it does on a real panel.
local Chain = setmetatable({}, {})
getmetatable(Chain).__index = function() return Chain end
getmetatable(Chain).__call = function() return Chain end
getmetatable(Chain).__newindex = function() end

local D = { all = {}, chat = {}, boxes = {}, writes = {} }
local P = {}
local PanelMT = { __index = function(_, k)
  local m = P[k]
  if m ~= nil then return m end
  if type(k) == "string" and k:match("^%u") then return Chain end
  return nil
end }

function D.create(class, parent)
  local p = setmetatable({ __valid = true, _class = class, _children = {}, _items = {},
    _lines = {}, _choices = {}, _options = {}, _sheets = {}, _visible = true,
    _inval = 0, lblTitle = Chain, m_Image = Chain }, PanelMT)
  D.all[#D.all + 1] = p
  if parent ~= nil and getmetatable(parent) == PanelMT then
    p._parent = parent
    table.insert(parent._children, p)
  end
  if class == "DIconBrowser" then
    -- engine: DScrollPanel canvas first, then the IconLayout inside it
    local canvas = D.create("Panel", p)
    rawset(p, "IconLayout", D.create("DIconLayout", canvas))
  end
  return p
end
function D.find(pred) for _, p in ipairs(D.all) do if p.__valid and pred(p) then return p end end end
function D.count(pred) local n = 0 for _, p in ipairs(D.all) do if p.__valid and pred(p) then n = n + 1 end end return n end
function D.class(c) return function(p) return p._class == c end end

function P:SetSize(w, h) self._w, self._h = w, h end
function P:GetWide() return self._w or 100 end
function P:GetTall() return self._h or 30 end
function P:SetWide(w) self._w = w end
function P:SetTall(h) self._h = h end
function P:GetColWide() return self._colw or 800 end
function P:SetColWide(w) self._colw = w end
function P:GetRowHeight() return self._rowh or 35 end
function P:SetRowHeight(h) self._rowh = h end
function P:SetVisible(b) self._visible = b end
function P:IsVisible() return self._visible ~= false end
function P:InvalidateParent() self._inval = self._inval + 1 end
function P:SetText(t) self._text = t; self._value = t end
function P:GetText() return self._text or "" end
function P:SetTooltip(t) self._tooltip = t end
function P:SetValue(v)
  self._value = v; self._text = v
  -- DBinder: SetValue -> SetSelectedNumber -> UpdateText -> OnChange (dbinder.lua:61-66)
  if self._class == "DBinder" and rawget(self, "OnChange") then self:OnChange(v) end
end
function P:GetValue(i) if i then return self._cols and self._cols[i] end return self._value end
function P:SetMin(v) self._min = v end
function P:SetMax(v) self._max = v end
function P:GetMin() return self._min end
function P:GetMax() return self._max end
function P:SetChecked(b) self._checked = b end
function P:GetChecked() return self._checked == true end
function P:SetModel(m) self._model = m end
function P:GetModelName() return self._model end
function P:IsValid() return self.__valid end
function P:GetParent() return self._parent or Chain end
function P:GetChildren() local r = {} for i, c in ipairs(self._children) do r[i] = c end return r end
function P:Add(class) return D.create(class, rawget(self, "IconLayout") or self) end
function P:AddItem(p) table.insert(self._items, p) end
function P:Remove()
  self.__valid = false
  if self._parent then
    for i, c in ipairs(self._parent._children) do if c == self then table.remove(self._parent._children, i) break end end
  end
  for _, c in ipairs(self:GetChildren()) do c:Remove() end
end
function P:Close() local oc = rawget(self, "OnClose"); if oc then oc(self) end self:Remove() end
function P:AddSheet(_, panel) local s = { Button = D.create("DButton", self), Panel = panel }; table.insert(self._sheets, s); return s end
function P:AddLine(...)
  local line = D.create("DListView_Line", self)
  line._cols = { ... }
  line.Columns = { D.create("DLabel", line) }
  table.insert(self._lines, line)
  return line
end
function P:GetLines() return self._lines end
function P:GetLine(i) return self._lines[i] end
function P:GetSelectedLine() return self._selected or 1 end
function P:Clear() self._lines = {} end
function P:AddChoice(text, data) table.insert(self._choices, { text, data }) end
function P:AddMenu() return D.create("DMenu") end
function P:AddOption(text, fn) table.insert(self._options, { text = text, fn = fn }); return D.create("DMenuOption") end

-- The engine only runs Think on a visible panel, and not below a hidden one.
function D.think(p)
  if not p.__valid or not p:IsVisible() then return end
  local th = rawget(p, "Think")
  if th then th(p) end
  for _, c in ipairs(p:GetChildren()) do D.think(c) end
end

vgui = { Create = function(class, parent) return D.create(class, parent) end }
function DermaMenu() local m = D.create("DMenu"); D.lastMenu = m; return m end
function ispanel(v) return getmetatable(v) == PanelMT end
function ScrW() return 1920 end
function ScrH() return 1080 end
surface = setmetatable({}, { __index = function() return function() end end })
draw = surface
language = { GetPhrase = function(s) return ({ ["#dbinder.none"] = "None" })[s] or s end }
-- client_client.so: codes outside 1..1041 return nothing (see finding #43)
local KEYNAMES = { [63] = "F3", [46] = "C" }
input = { GetKeyName = function(code)
  if type(code) ~= "number" then error("bad argument #1 to 'GetKeyName' (number expected)", 2) end
  if code < 1 or code > 1041 then return nil end
  return KEYNAMES[code] or ("KEY" .. code)
end }
string.Replace = function(s, find, rep)
  local pat = find:gsub("%W", "%%%0")
  local with = rep:gsub("%%", "%%%%")
  return (s:gsub(pat, with))
end
function net.SendToServer() S.net.cur.to = "server"; table.insert(S.net.sent, S.net.cur) end
local function lastSent() return S.net.sent[#S.net.sent] end
OBS_MODE_NONE = 0
color_white = Color(255, 255, 255)
file.Write = function(path) table.insert(D.writes, path) end

function PHX:GetCLCVar(n) return PHX:GetCVar(n) end
function PHX:QTrans(x) if type(x) == "table" then return x[1] end return x end
function PHX:Translate(id, ...) local a = { ... } for i = 1, select("#", ...) do a[i] = tostring(a[i]) end return id .. ":" .. table.concat(a, ",") end
function PHX:AddChat(t) table.insert(D.chat, tostring(t)) end
function PHX:ChatInfo(t) table.insert(D.chat, tostring(t)) end
function PHX:MsgBox(t) table.insert(D.boxes, t) end
function PHX:MsgBox_Query(t, _, _, yes) table.insert(D.boxes, t); if D.autoYes and yes then yes() end end
local function lastChat() return D.chat[#D.chat] or "" end

-- util.IsHexColor lives in sh_utils.lua; use the shipped one.
loadblocks("sh_utils.lua@IsHexColor", extract(GM .. "sh_utils.lua", [[^function util\.IsHexColor]]))

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

-- #173: the Set button must send what is in the field now.
CreateConVar("ph_fc_cue_path", "misc/freeze_cam.wav")
D.all, D.boxes, S.net.sent = {}, {}, {}
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
te:SetText("sound\\a.wav"); te:OnEnter("sound\\a.wav"); setBtn:DoClick()
check("Enter then Set still rewrites backslashes", lastSent().data[1], "sound/a.wav")
local sentBefore = #S.net.sent
te:SetText(""); setBtn:DoClick()
check("an empty field sends nothing", #S.net.sent, sentBefore)
check("... and says so", D.boxes[#D.boxes], "PHXM_MSG_INPUT_IS_EMPTY")

---------------------------------------------------------------- cl_menu
print("\n== cl_menu: F1 menu (ph_x_menu) ==")
-- Record the menu types instead of building them; they are covered above.
local made = {}
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

---------------------------------------------------------------- cl_fb_core
print("\n== cl_fb_core: prop list editor ==")
-- english.lua is plain Lua; load its bytes as they ship.
PHX.LANGUAGES = {}
loadchunk(io.open(REPO .. GM .. "langs/english.lua"):read("*a"), "english.lua")()
local EN = PHX.LANGUAGES.en_us
local fbSrc = io.open(REPO .. GM .. "cl_fb_core.lua"):read("*a")
local missing = {}
for key in fbSrc:gmatch('FTranslate%(%s*"([%w_]+)"') do if EN[key] == nil then missing[#missing + 1] = key end end
check("every FTranslate key in cl_fb_core is in english.lua", table.concat(missing, ","), "")

local fb = loadchunk(extract(GM .. "cl_fb_core.lua", "1-999999") .. "\nreturn f", "cl_fb_core.lua")()
local uploaded
util.TableToJSON = function(t) uploaded = t; return "json" end
D.autoYes = true

local function icons2() return fb.list.IconLayout:GetChildren() end
local function openEditor(models)
  if fb.frame then fb.frame:Close() end
  D.all = {}
  _G.TestPM = { list = models }
  return attempt(PHXPM_openFileBrowser, staff, "TestPM", "list", {}, "Props")
end
local function apply() uploaded = nil; fb.btnApply.DoClick(fb.btnApply); return uploaded and table.concat(uploaded, ",") end

check("editor opens", openEditor({ "models/a.mdl", "models/b.mdl" }), "ok")
check("Remove Selected tooltip is the legend text", fb.btn._tooltip, "PHZ_msg_removesel")
check("... which english.lua defines", EN[fb.btn._tooltip] ~= nil, true)
-- normal: select an icon by clicking it, then Remove Selected
icons2()[2]:GetChildren()[1]:DoClick()
fb.btn.DoClick()
check("a clicked (red) icon is removed from the upload", apply(), "models/a.mdl")
-- normal: nothing selected, nothing removed
openEditor({ "models/a.mdl", "models/b.mdl" })
fb.btn.DoClick()
check("Remove Selected with nothing marked keeps the list", apply(), "models/a.mdl,models/b.mdl")
-- #170: the server rejected b.mdl; updatePreview marks it yellow without ic.model
openEditor({ "models/a.mdl", "models/b.mdl" })
_G.TestPM.list = { "models/a.mdl" }
fb:updatePreview()
local yellow = 0
for _, ic in ipairs(icons2()) do if ic.markeddontexist then yellow = yellow + 1 end end
check("the rejected model is marked yellow", yellow, 1)
fb.btn.DoClick()
check("Remove Selected drops the yellow model from the upload", apply(), "models/a.mdl")
fb.frame:Close()

---------------------------------------------------------------- cl_tauntwindow
print("\n== cl_tauntwindow: taunt window (ph_showtaunts) ==")
CreateConVar("ph_custom_taunt_mode", "2")
CreateConVar("ph_customtaunts_delay", "4"); CreateConVar("ph_normal_taunt_delay", "2")
S.boolCVar("ph_taunt_pitch_enable", "1")
S.boolCVar("ph_randtaunt_map_prop_enable", "1"); CreateConVar("ph_randtaunt_map_prop_max", "6")
S.boolCVar("ph_prop_right_mouse_taunt", "0"); S.boolCVar("ph_cl_autoclose_taunt", "0")
S.cvars["ph_default_taunt_key"].v = "63"

local W = loadchunk(extract(GM .. "cl_tauntwindow.lua", "1-999999") .. "\nreturn window", "cl_tauntwindow.lua")()

local STOCK = {
  Default = { [TEAM_HUNTERS] = { ["Radio Laugh"] = "taunts/hunters/laugh.wav" },
              [TEAM_PROPS] = { ["Car Horn"] = "taunts/props/horn.wav", ["Over Here"] = "taunts/props/here.wav" } },
  Pack = { [TEAM_PROPS] = { ["Pack Taunt"] = "taunts/props/pack.wav" } },
}
local lp
function LocalPlayer() return lp end

local function openTaunts(o)
  if W.CurrentlyOpen then W.frame:Close() end
  D.all, D.chat, S.net.sent = {}, {}, {}
  PHX.TAUNTS, PHX.DEFAULT_CATEGORY = o.taunts, o.default or "Default"
  lp = S.Player{ team = o.team or TEAM_PROPS, vars = { tauntWindowCategorie = o.cat } }
  lp.GetObserverMode = function() return OBS_MODE_NONE end
  lp.GetTauntRandMapPropCount = function() return o.fcount or 6 end
  S.cvars["ph_randtaunt_map_prop_max"].v = tostring(o.fmax or 6)
  S.receivers["PH_AllowTauntWindow"]()
  return attempt(S.concommands["ph_showtaunts"].fn, lp)
end
local function lines() return #W.list:GetLines() end
local function lineText(i) return W.list:GetLine(i) and W.list:GetLine(i):GetValue(1) end
local function pick(name)
  for i, l in ipairs(W.list:GetLines()) do if l:GetValue(1) == name then W.list._selected = i; return l end end
end
local function dbl() return attempt(W.list.DoDoubleClick, W.list, W.list:GetLine(W.list:GetSelectedLine())) end

-- #167 part 1: nothing starred, nothing changed -> ShutDown writes nothing.
PHX.FavoriteTaunts = {}
D.writes = {}
S.fire("ShutDown")
check("ShutDown with no favourites ever set writes nothing", #D.writes, 0)

-- normal play
check("prop opens the stock category", openTaunts{ taunts = STOCK }, "ok")
check("... listing both prop taunts", lines(), 2)
pick("Car Horn")
check("double-click plays it", dbl(), "ok")
check("... sending the taunt path", lastSent() and lastSent().data[2], "taunts/props/horn.wav")

-- #40: case-insensitive, plain-text search
W.input:OnEnter("Car")
check("search 'Car' finds 'Car Horn'", lines() == 1 and lineText(1), "Car Horn")
W.input:OnEnter("here")
check("search 'here' finds 'Over Here'", lines() == 1 and lineText(1), "Over Here")
check("search '(' does not raise", attempt(W.input.OnEnter, W.input, "("), "ok")
check("... and reports nothing found", lineText(1), "TM_TAUNTS_SEARCH_NOTHING")
-- #174: the 'not found' placeholder is not a taunt
W.input:OnEnter("zzz")
check("search 'zzz' reports nothing found", lineText(1), "TM_TAUNTS_SEARCH_NOTHING")
S.net.sent = {}
W.list._selected = 1
check("double-clicking 'not found' does not raise", dbl(), "ok")
check("... and sends nothing", #S.net.sent, 0)
W.input:OnEnter("")
check("clearing the search restores the list", lines(), 2)

-- #174: the empty-favourites placeholder
openTaunts{ taunts = STOCK, cat = PHX.FAVORITE_CATEGORY }
check("no favourites shows the placeholder", lineText(1), "TM_NO_TAUNTS")
W.list._selected = 1
dbl()
check("double-clicking 'no taunts' sends nothing", #S.net.sent, 0)

-- #44: stock taunts off and a props-only pack; a hunter has nothing to list.
check("hunter opens with stock taunts off", openTaunts{ taunts = { Pack = STOCK.Pack }, default = PHX.FAVORITE_CATEGORY, team = TEAM_HUNTERS }, "ok")
check("... and sees the placeholder", lineText(1), "TM_NO_TAUNTS")
check("... in a popup window", W.CurrentlyOpen, true)
check("prop opens with stock taunts off", openTaunts{ taunts = { Pack = STOCK.Pack }, default = PHX.FAVORITE_CATEGORY }, "ok")
-- #44: a remembered category this team has no taunts in falls back to Default
openTaunts{ taunts = STOCK, team = TEAM_HUNTERS, cat = "Pack" }
check("hunter in a props-only category sees Default", lineText(1), "Radio Laugh")
pick("Radio Laugh")
check("... and double-click plays the hunter taunt", dbl(), "ok")
check("... with the hunter path", lastSent() and lastSent().data[2], "taunts/hunters/laugh.wav")

-- #41: right-click "Play on random props" must mirror sv_tauntmgr's count check.
local function randProp(o)
  o.taunts = STOCK
  openTaunts(o)
  pick("Car Horn")
  S.net.sent = {}
  W.list.OnRowRightClick(W.list, W.list:GetLine(W.list:GetSelectedLine()))
  for _, opt in ipairs(D.lastMenu._options) do
    if tostring(opt.text):match("^PHX_CTAUNT_ON_RAND_PROPS") then opt.fn(); break end
  end
  return #S.net.sent, lastChat()
end
local n, msg = randProp{ fcount = -1, fmax = -1 }
check("right-click random prop, unlimited -> sent", n, 1)
check("... as a fake taunt", lastSent() and lastSent().data[3], true)
n, msg = randProp{ fcount = 3, fmax = 6 }
check("right-click random prop, 3 left -> sent", n, 1)
n, msg = randProp{ fcount = 0, fmax = 6 }
check("right-click random prop, none left -> not sent", n, 0)
check("... and says the limit is hit", msg, "PHX_CTAUNT_RAND_PROPS_LIMIT:")
-- the bottom Fake Taunt button makes the same promise
local function fakeBtn(o)
  o.taunts = STOCK
  openTaunts(o)
  pick("Car Horn")
  W.list.OnRowSelected()
  S.net.sent = {}
  local b = D.find(function(p) return p._class == "DButton" and p._tooltip == "TM_TOOLTIP_FAKETAUNT" end)
  b.DoClick(b)
  return #S.net.sent, lastChat()
end
n = fakeBtn{ fcount = -1, fmax = -1 }
check("Fake Taunt button, unlimited -> sent", n, 1)
n = fakeBtn{ fcount = 2, fmax = 6 }
check("Fake Taunt button, 2 left -> sent", n, 1)
n, msg = fakeBtn{ fcount = 0, fmax = 6 }
check("Fake Taunt button, none left -> not sent", n, 0)
check("... and says the limit is hit", msg, "PHX_CTAUNT_RAND_PROPS_LIMIT:")

-- #178: the pitch controls follow ph_taunt_pitch_enable while the window is open.
openTaunts{ taunts = STOCK }
D.think(W.frame); D.think(W.frame); D.think(W.frame)
check("pitch enabled, no change -> no re-layout per frame", W.pitchpanel._inval, 0)
check("... and the pitch panel shown", W.pitchpanel:IsVisible(), true)
S.cvars["ph_taunt_pitch_enable"].v = "0"
D.think(W.frame)
check("pitch disabled -> pitch panel hidden", W.pitchpanel:IsVisible(), false)
S.cvars["ph_taunt_pitch_enable"].v = "1"
D.think(W.frame)
check("pitch re-enabled -> pitch panel shown again", W.pitchpanel:IsVisible(), true)

-- #167 part 2: un-starring the last favourite must be saved.
PHX.FavoriteTaunts = { ["Car Horn"] = true }
openTaunts{ taunts = STOCK, cat = PHX.FAVORITE_CATEGORY }
check("favourites list the starred taunt", lineText(1), "Car Horn")
local star = D.find(function(p) return p._class == "DImageButton" end)
star:DoClick()
check("un-starring empties the favourites", next(PHX.FavoriteTaunts), nil)
D.writes = {}
S.fire("ShutDown")
check("ShutDown saves the emptied favourites", #D.writes, 1)
check("... to the favourites file", D.writes[1] and D.writes[1]:match("tauntfav/") ~= nil, true)
PHX.FavoriteTaunts = { ["Over Here"] = true }
D.writes = {}
S.fire("ShutDown")
check("ShutDown saves non-empty favourites", #D.writes, 1)

report()
