dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- Admin menu, run as shipped: the F1 MapVote tab's mv_* settings reach the server
-- allow-list through the same net messages the menu sends (and bad values are
-- refused), while everything the allow-list exists to block stays blocked; and
-- the Enhanced Plus ph_huntercount slider only sends what the admin changes.

local ROOT = (debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "../../../"
local function lineOf(path, pat)
  local n = 0
  for line in io.lines(ROOT .. path) do n = n + 1; if line:match(pat) then return n end end
  error("no line matching " .. pat .. " in " .. path)
end

net.ReadFloat = net.ReadInt
function net.SendToServer() S.net.cur.to = "server"; table.insert(S.net.sent, S.net.cur) end

-- Everything from the staff check to the end of the file: allow-list, doCommand
-- and the net receivers.
local ADMIN = "gamemodes/prop_hunt/gamemode/sv_admin.lua"
loadblocks("sv_admin.lua", extract(ADMIN, lineOf(ADMIN, "^local function doAdminStrictCheck") .. "-999999"))

-- The mapvote ConVars as sh_mapvote.lua creates them, plus a few others.
local mv = { mv_maplimit = "24", mv_timelimit = "30", mv_change_when_no_player = "1", mv_allowcurmap = "0",
             mv_use_ulx_votemaps = "1", mv_cooldown = "1", mv_mapbeforerevote = "2", mv_rtvcount = "2",
             mv_map_prefix = "phx_,ph_" }
for n, v in pairs(mv) do CreateConVar(n, v) end
CreateConVar("ph_round_time", "300"); CreateConVar("ph_custom_mv_func", "")
CreateConVar("rcon_password", "secret"); CreateConVar("mv_other_addon", "0")
S.boolCVar("ph_kick_non_admin_access", "0")

local function send(msg, ply, ...)
  ply.chat = {}
  S.net.readq = { ... }
  local ok, err = pcall(S.receivers[msg], 0, ply)
  if not ok then return "ERROR: " .. tostring(err) end
  local m = ply.chat[1]
  return m and m[2] or "none"
end
local function cv(n) return tostring(S.cvars[n] and S.cvars[n].v) end
local staff, user = S.Player{ staff = true, name = "Admin" }, S.Player{ staff = false, name = "Joe" }

print("\n== the F1 MapVote tab (the exact payloads cl_menutypes sends) ==")
for _, n in ipairs{ "mv_allowcurmap", "mv_cooldown", "mv_use_ulx_votemaps", "mv_change_when_no_player" } do
  local want = (mv[n] == "1") and "0" or "1"
  check(n .. " checkbox: accepted", send("SvCommandReq", staff, n, want), "none")
  check(n .. " checkbox: applied", cv(n), want)
end
for n, v in pairs{ mv_maplimit = 40, mv_timelimit = 45, mv_mapbeforerevote = 5, mv_rtvcount = 6 } do
  check(n .. " slider: accepted", send("SvCommandSliderReq", staff, n, false, v), "none")
  check(n .. " slider: applied", cv(n), tostring(v))
end
check("mv_map_prefix text: accepted", send("SvCommandTextEntry", staff, "ph_,cs_office-", "mv_map_prefix"), "none")
check("mv_map_prefix text: applied", cv("mv_map_prefix"), "ph_,cs_office-")

print("\n== obviously bad mv_* values are refused ==")
check("prefix with pattern characters: refused", send("SvCommandTextEntry", staff, "ph_%[", "mv_map_prefix"), "MISC_ERROR")
check("  ... value unchanged", cv("mv_map_prefix"), "ph_,cs_office-")
check("prefix with a paren: refused", send("SvCommandTextEntry", staff, "ph_(", "mv_map_prefix"), "MISC_ERROR")
check("text into a number cvar: refused", send("SvCommandTextEntry", staff, "abc", "mv_maplimit"), "MISC_ERROR")
check("nan into a number cvar: refused", send("SvCommandTextEntry", staff, "nan", "mv_timelimit"), "MISC_ERROR")
check("inf into a number cvar: refused", send("SvCommandTextEntry", staff, "inf", "mv_timelimit"), "MISC_ERROR")
check("  ... values unchanged", cv("mv_maplimit") .. "/" .. cv("mv_timelimit"), "40/45")

print("\n== what the allow-list exists to block stays blocked ==")
check("ph_round_time slider (unchanged path)", send("SvCommandSliderReq", staff, "ph_round_time", false, 240), "none")
check("  ... applied", cv("ph_round_time"), "240")
check("ph_custom_mv_func: denied", send("SvCommandTextEntry", staff, "print(1)", "ph_custom_mv_func"), "PHX_ADMIN_ACCESS_ONLY")
check("  ... unchanged", cv("ph_custom_mv_func"), "")
check("rcon_password: denied", send("SvCommandTextEntry", staff, "x", "rcon_password"), "PHX_ADMIN_ACCESS_ONLY")
check("  ... unchanged", cv("rcon_password"), "secret")
check("another addon's mv_* cvar: denied", send("SvCommandReq", staff, "mv_other_addon", "1"), "PHX_ADMIN_ACCESS_ONLY")
check("non-existent mv_* name: denied", send("SvCommandReq", staff, "mv_nope", "1"), "PHX_ADMIN_ACCESS_ONLY")
check("non-staff, mv_maplimit: denied", send("SvCommandSliderReq", user, "mv_maplimit", false, 10), "PHX_ADMIN_ACCESS_ONLY")
check("  ... unchanged", cv("mv_maplimit"), "40")

print("\n== Enhanced Plus sliders only send what the admin changes ==")
-- DNumSlider as garrysmod/lua/vgui/dnumslider.lua has it: SetMin/SetMax always run
-- ValueChanged -> OnValueChanged, SetValue clamps to the range and fires it twice
-- (Scratch, then ValueChanged), and IsEditing is only true during a drag/typing.
local function noop() end
local created = {}
local mkSlider
local function widget()
  local w = setmetatable({}, { __index = function() return noop end })
  function w:Add(cls)
    local c = (cls == "DNumSlider") and mkSlider() or widget()
    table.insert(created, c)
    return c
  end
  return w
end
function mkSlider()
  local s = widget()
  s.min, s.max, s.val, s.editing = 0, 1, 0.5, false
  s.Label = widget()
  function s:GetMin() return self.min end
  function s:GetMax() return self.max end
  function s:GetValue() return self.val end
  function s:IsEditing() return self.editing end
  function s:ValueChanged(v) self:OnValueChanged(math.Clamp(tonumber(v) or 0, self.min, self.max)) end
  function s:SetMin(m) self.min = tonumber(m) or 0; self:ValueChanged(self.val) end
  function s:SetMax(m) self.max = tonumber(m) or 0; self:ValueChanged(self.val) end
  function s:SetDecimals() self:ValueChanged(self.val) end
  function s:SetValue(v)
    v = math.Clamp(tonumber(v) or 0, self.min, self.max)
    if self.val == v then return end
    self.val = v
    self:OnValueChanged(v)
    self:ValueChanged(self.val)
  end
  function s:OnValueChanged() end
  return s
end
local function parent() return widget() end
function PHX:QTrans(s) return s end
function isfunction(f) return type(f) == "function" end
GAMEMODE.GetPlayingCount = function() return S.playing end

local CL = "gamemodes/prop_hunt/gamemode/enhancedplus/cl_enhancedplus.lua"
loadblocks("cl_enhancedplus.lua@slider",
  "local plus = {}\n" .. extract(CL, [[^plus\.TeamData = \{]]) .. "\n" ..
  "PANELTYPES = {\n" .. extract(CL, [[^\s*\["slider"\]\s*= function]]) .. "\n}\n" ..
  "HUNTERCOUNT = plus.TeamData['ph_huntercount']")

local function sliderSends() local n, vals = 0, {} for _, m in ipairs(S.net.sent) do
  if m.name == "SvCommandSliderReq" then n = n + 1; vals[#vals + 1] = m.data[3] end end return n, vals end

local function build(name, cvar, rangeFn)
  S.net.sent, created = {}, {}
  CreateConVar(name, cvar)
  PANELTYPES.slider(name, rangeFn, parent(), "LABEL", 400, 32)
  local panel, slider = created[1], nil
  for _, w in ipairs(created) do if w.IsEditing then slider = w end end
  return panel, slider
end

-- ph_team_balance_classic 0, ph_huntercount 4 set for a full server, 3 playing now
S.playing = 3
local panel, slider = build("ph_huntercount", "4", HUNTERCOUNT[2])
check("huntercount: opening the tab sends nothing", (sliderSends()), 0)
for _ = 1, 100 do panel.Think() end
check("huntercount: 100 frames with the tab open send nothing", (sliderSends()), 0)
check("huntercount: shows the live value, not a clamped one", slider:GetValue(), 4)
S.playing = 8; panel.Think(); S.playing = 2; panel.Think()
check("huntercount: players joining/leaving send nothing", (sliderSends()), 0)
slider.editing = true; slider:SetValue(1); slider.editing = false
local n, vals = sliderSends()
check("huntercount: the admin drags to 1 -> sent", n > 0, true)
check("huntercount: ... carrying 1", vals[1], 1)
check("huntercount: ... and nothing else", vals[#vals], 1)
S.cvars["ph_huntercount"].v = "1"                          -- the server applied it
S.net.sent = {}
slider.editing = true; slider:ValueChanged(1); slider.editing = false
check("huntercount: the same value again -> not resent", (sliderSends()), 0)
slider.editing = true; slider:SetValue(2); slider.editing = false
n, vals = sliderSends()
check("huntercount: a new drag after that is sent", vals[1], 2)

-- an ordinary slider keeps working
panel, slider = build("ph_unstuck_waittime", "5", function() return 5, 15 end)
for _ = 1, 10 do panel.Think() end
check("waittime: opening + frames send nothing", (sliderSends()), 0)
slider.editing = true; slider:SetValue(10); slider.editing = false
n, vals = sliderSends()
check("waittime: the admin drags to 10 -> sent", vals[1], 10)

report()
