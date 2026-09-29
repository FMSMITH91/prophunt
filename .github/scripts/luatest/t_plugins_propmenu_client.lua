dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- Prop Menu (PCR), client side: the menu's open gate and open/close toggle, the tips timer
-- (cl_propchoose.lua) and the editor's save confirmation (cl_pm_fb.lua), run from the
-- shipped files with CLIENT set.
local PCRDIR = "gamemodes/prop_hunt/gamemode/plugins/propmenu/"
local GMDIR = "gamemodes/prop_hunt/gamemode/"
SERVER, CLIENT = false, true

-- Engine pieces shim.lua leaves out (kept here: shim.lua is shared with other branches).
function isfunction(v) return type(v) == "function" end
function FindMetaTable(n) if n == "Player" then return S.PlyMeta end end
function LocalPlayer() return S.localPlayer end
function ScrW() return 1920 end
function ScrH() return 1080 end
function Model(m) return m end
net.ReadTable = function() return S.net.readq and table.remove(S.net.readq, 1) end
function net.SendToServer() S.net.cur.to = "server"; table.insert(S.net.sent, S.net.cur) end
S.chatlog = {}
chat = { AddText = function(...)
  for _, v in ipairs{ ... } do if type(v) == "string" then S.chatlog[#S.chatlog + 1] = v end end
end }
local function saidInChat(key) for _, v in ipairs(S.chatlog) do if v == key then return true end end return false end

-- Derma: a DFrame whose Close() does what vgui/dframe.lua does (hide, maybe Remove, then
-- OnClose); any other method (CamelCase) is a no-op, while unset fields stay nil.
-- SetDisabled is recorded for the editor buttons.
local Panel = {}
local noop = function() end
local PanelMT = { __index = function(t, k)
  if k == "__valid" then return not rawget(t, "_removed") end
  local v = Panel[k]; if v ~= nil then return v end
  if type(k) == "string" and k:match("^%u") then return noop end
end }
S.frames = {}
vgui = { Create = function(cls)
  local p = setmetatable({ _cls = cls, _visible = true }, PanelMT)
  if cls == "DFrame" then S.frames[#S.frames + 1] = p end
  return p
end }
function ispanel(v) return getmetatable(v) == PanelMT end
function Panel:Add(cls) return vgui.Create(cls) end
function Panel:SetVisible(b) self._visible = b end
function Panel:IsVisible() return self._visible end
function Panel:IsValid() return not self._removed end
function Panel:Remove() self._removed = true end
function Panel:SetDeleteOnClose(b) self._deleteOnClose = b end
function Panel:GetDeleteOnClose() return self._deleteOnClose == true end
function Panel:Close()
  self:SetVisible(false)
  if self:GetDeleteOnClose() then self:Remove() end
  self:OnClose()
end
function Panel:GetWide() return 100 end
function Panel:GetTall() return 100 end
function Panel:SetDisabled(b) self._disabled = b end

-- The real cvar layer and the real definitions of the cvars these files read.
loadblocks("sh_convar.lua@cvars",
  extract(GMDIR .. "sh_convar.lua", "1-10") .. "\n"
  .. extract(GMDIR .. "sh_convar.lua", [[^local ConVarTranslate = \{]]) .. "\nlocal CVAR = {}\n"
  .. extractAll(GMDIR .. "sh_convar.lua", { [[^function PHX:AddCVar]], [[^function PHX:GetCVar]], [[^function PHX:QCVar]] }))
do
  local specs = {}
  for _, n in ipairs{ "pcr_enable", "pcr_allow_custom", "pcr_only_allow_certain_groups", "pcr_use_ulx_menu",
                      "pcr_notify_messages", "ph_banned_models" } do
    specs[#specs + 1] = ([=[^CVAR\["%s"\]]=]):format(n)
  end
  loadblocks("sh_convar.lua@defs", "local CVAR = {}\n" .. extractAll(GMDIR .. "sh_convar.lua", specs)
    .. "\nfor n, d in pairs(CVAR) do PHX:AddCVar(d[1], n, d[2], d[3], d[4], d[5]) end")
end
local function set(n, v) RunConsoleCommand(n, tostring(v)) end
check("cvar layer: pcr_notify_messages defaults off (real bool)", PHX:GetCVar("pcr_notify_messages"), false)

PHX.BANNED_PROP_MODELS = {}
loadblocks("sh_propchoose.lua", extract(PCRDIR .. "sh_propchoose.lua", "1-99999"))
loadblocks("sh_meta.lua", extract(PCRDIR .. "sh_meta.lua", "1-99999"))
loadblocks("cl_propchoose.lua", extract(PCRDIR .. "cl_propchoose.lua", "1-99999"))
PCR.PropList = { "models/props/a.mdl", "models/props/b.mdl" }

print("\n== the tips timer follows pcr_notify_messages ==")
-- The file loads while the replicated value is still the default (off).
local tip
for _, t in ipairs(S.timers) do if t.id == "pcrT.NotifyAddon" then tip = t.fn end end
check("tips timer exists although the cvar was off at load", tip ~= nil, true)
if tip then
  tip()
  check("cvar off: no tip", saidInChat("PCR_NOTIFY_1"), false)
  set("pcr_notify_messages", 1)
  tip()
  check("cvar turned on later: tip shown", saidInChat("PCR_NOTIFY_1"), true)
  set("pcr_notify_messages", 0)
end

print("\n== who can open the menu ==")
SetGlobalBool("InRound", true)
local function opens(opts)
  S.chatlog, S.frames = {}, {}
  local p = S.Player{ team = opts.team or TEAM_PROPS, alive = opts.alive ~= false }
  p._nw.CurrentUsage = 3
  S.localPlayer = p
  SetGlobalBool("InRound", opts.inround ~= false)
  -- A fresh window each time: close and delete any earlier one, as the round-end force-close does.
  S.receivers["pcr.ForceCloseMenu"]()
  PCR:OpenPropMenu()
  return #S.frames == 1 and S.frames[1]:IsVisible()
end
check("living prop in a round: opens", opens{}, true)
check("dead prop in a round: refused", opens{ alive = false }, false)
check("dead prop in a round: told not available", saidInChat("PCR_CL_MENU_NOTREADY"), true)
check("living hunter in a round: refused", opens{ team = TEAM_HUNTERS }, false)
check("spectator in a round: refused", opens{ team = TEAM_SPECTATOR }, false)
check("living prop between rounds: refused", opens{ inround = false }, false)
set("pcr_enable", 0)
check("menu disabled: refused", opens{}, false)
check("menu disabled: told so", saidInChat("PCR_CL_DISABLED"), true)
set("pcr_enable", 1)
SetGlobalBool("InRound", true)

print("\n== the menu key toggles the window, however it was last closed ==")
S.receivers["pcr.ForceCloseMenu"]()
S.frames = {}
local lp = S.Player{}
lp._nw.CurrentUsage = 3
S.localPlayer = lp
PCR:OpenPropMenu()
local fr = S.frames[1]
check("key: opens", fr and fr:IsVisible(), true)
PCR:OpenPropMenu()
check("key again: closes", fr:IsVisible(), false)
PCR:OpenPropMenu()
check("key again: reopens", fr:IsVisible(), true)
fr:Close()                                    -- the X button, or an icon click
check("X button: closed", fr:IsVisible(), false)
PCR:OpenPropMenu()
check("key after X: reopens", fr:IsVisible(), true)
PCR:OpenPropMenu()
check("key again: closes (not stuck open)", fr:IsVisible(), false)
PCR:OpenPropMenu()
check("key again: reopens", fr:IsVisible(), true)
check("same window throughout", #S.frames, 1)

print("\n== the editor's save confirmation reaches an editor re-granted the lock ==")
-- PHXPM_openFileBrowser (cl_fb_core.lua) builds the window only when it is not already
-- open (`if !f.isOpen then ... return f end`) and otherwise returns nothing.
local fbf = {}
function PHXPM_openFileBrowser()
  if fbf.isOpen then return end
  fbf.isOpen = true
  fbf.frame, fbf.btnApply, fbf.btnCancel, fbf.btn = vgui.Create("DFrame"), vgui.Create("DButton"),
    vgui.Create("DButton"), vgui.Create("DButton")
  fbf.updatePreview = function() end
  return fbf
end
PHX.MsgBox = function() end
PHX.ChatInfo = function() end
loadblocks("cl_pm_fb.lua", extract(PCRDIR .. "cl_pm_fb.lua", "1-99999"))
S.localPlayer = S.Player{ staff = true }
set("pcr_allow_custom", 1)
local function openMsg() S.net.readq = { { global = "PCR", sub = "CustomProp" } }; S.receivers["phxpm.fb_openPM_Editor"]() end
openMsg()
check("editor opens", fbf.isOpen, true)
openMsg()                                     -- the server re-grants the lock holder
-- Apply disables the buttons until the server confirms the save.
fbf.btnApply:SetDisabled(true); fbf.btnCancel:SetDisabled(true); fbf.btn:SetDisabled(true)
S.net.readq = { false }
S.receivers["phxpm.fb_UpdateConfirmed_Editor"]()
check("after a second open message: Close re-enabled", fbf.btnCancel._disabled, false)
check("after a second open message: Apply re-enabled", fbf.btnApply._disabled, false)

report()
