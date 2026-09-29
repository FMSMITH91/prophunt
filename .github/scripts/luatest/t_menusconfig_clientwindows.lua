dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- The prop-list editor and the taunt window are client Derma. These tests load
-- each SHIPPED file whole under the Derma stand-in in derma.lua and drive the
-- same entry points a player does (the ph_showtaunts command, button DoClicks).
-- The F1 menu and its menu types are in t_menusconfig_clientui.lua.

local REPO = (debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "../../../"
local GM = "gamemodes/prop_hunt/gamemode/"
local D, lastSent, lastChat = dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "derma.lua")

-- The editor is opened by a staff member, as from the F1 menu's admin tab.
local staff = S.Player{ staff = true, info = { cl_playermodel = "alyx" } }

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
CreateConVar("ph_default_taunt_key", "63")

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

-- The pitch checkboxes name the taunt key. A cleared bind is 0, which has no
-- key name, and the shipped FTranslate then leaves the raw %s in the label.
do
  local shimFT = PHX.FTranslate
  loadblocks("cl_lang.lua@FTranslate", extract(GM .. "cl_lang.lua", [[^function PHX:FTranslate]]))
  local function pitchLabels() return W.ckPF3:GetText() .. " | " .. W.ckPRandF3:GetText() end
  openTaunts{ taunts = STOCK }
  check("pitch checkboxes name the taunt key (normal play)", pitchLabels(),
        EN.PHX_RTAUNT_USE_PITCH:format("F3") .. " | " .. EN.PHX_RTAUNT_RANDOMIZE:format("F3"))
  S.cvars["ph_default_taunt_key"].v = "0"
  openTaunts{ taunts = STOCK }
  check("cleared taunt key -> the checkboxes say N/A, not %s", pitchLabels(),
        EN.PHX_RTAUNT_USE_PITCH:format(EN.MISC_NA) .. " | " .. EN.PHX_RTAUNT_RANDOMIZE:format(EN.MISC_NA))
  S.cvars["ph_default_taunt_key"].v = "63"
  PHX.FTranslate = shimFT
end

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
