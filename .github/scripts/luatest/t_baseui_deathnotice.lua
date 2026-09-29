dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- base_phx kill feed: cl_deathnotice.lua and vgui/vgui_gamenotice.lua.

local function noop() end
local scrW, scrH = 1920, 1080
function ScrW() return scrW end
function ScrH() return scrH end

GAMEMODE.DeathNoticeDefaultColor = Color(250, 50, 50)
function PHX:GetRandomTranslated(k) return ({ SUICIDEMSG = "SUICIDED", DECOY_PROP = "DECOY" })[k] end

local me = S.Player{ name = "Me" }
function LocalPlayer() return me end

-- A GameNotice that records what AddDeathNotice put in it.
local notice
vgui = { Create = function(cls)
  assert(cls == "GameNotice", "unexpected vgui.Create " .. tostring(cls))
  notice = { __valid = true, parts = {}, m_bHighlight = false }
  notice["AddText"] = function(self, t) self.parts[#self.parts + 1] = tostring(t) end
  function notice:AddIcon(i) self.parts[#self.parts + 1] = "[" .. tostring(i) .. "]" end
  function notice:Remove() self.__valid = false end   -- PushNotice trims old ones
  return notice
end }

local lives = {}
g_DeathNotify = { __valid = true, items = {} }
function g_DeathNotify:AddItem(p, life) self.items[#self.items + 1] = p; lives[#lives + 1] = life end
function g_DeathNotify:GetItems() return self.items end

loadblocks("cl_deathnotice.lua", extractAll("gamemodes/base_phx/gamemode/cl_deathnotice.lua", {
  [[^local function PushNotice]], [[^function GM:AddDeathNotice]],
  [[^hook.Add\( "OnScreenSizeChanged"]] }))

local function feed(...)
  GAMEMODE:AddDeathNotice(...)
  return table.concat(notice.parts, " ")
end

print("\n== Kills between same-named players are kills, not suicides ==")
check("hunter 'Player' kills prop 'Player'", feed("Player", 1, "weapon_smg1", "Player", 2), "Player [weapon_smg1] Player")

print("\n== Normal play: every sender's shape still reads right ==")
check("player kill", feed("Hunter", 1, "weapon_smg1", "Prop", 2), "Hunter [weapon_smg1] Prop")
check("suicide (DeathNoticeEvent: no attacker)", feed(nil, 0, "suicide", "Bob", 2), "Bob SUICIDED")
check("suicide (legacy PlayerKilledSelf)", feed("Bob", 2, "suicide", "Bob", 2), "Bob SUICIDED")
check("world kill (no attacker)", feed(nil, -1, "worldspawn", "Bob", 2), "Bob SUICIDED")
check("empty attacker", feed("", -1, "trigger_hurt", "Bob", 2), "Bob SUICIDED")
check("NPC kill", feed("#npc_zombie", -1, "npc_zombie", "Bob", 2), "#npc_zombie [npc_zombie] Bob")
check("decoy prop", feed("Hunter", -1, {}, "#ph_fake_prop", -1), "Hunter [ph_fake_prop] DECOY")

print("\n== Your own kills and deaths are highlighted ==")
feed("Me", 1, "weapon_smg1", "Prop", 2)
check("a kill you made", notice.m_bHighlight, true)
feed("Hunter", 1, "weapon_smg1", "Me", 2)
check("a death you suffered", notice.m_bHighlight, true)
feed(nil, 0, "suicide", "Me", 2)
check("your own suicide", notice.m_bHighlight, true)
feed("Hunter", 1, "weapon_smg1", "Prop", 2)
check("someone else's kill", notice.m_bHighlight, false)
local saved = me
me = NULL
check("no local player yet: no error", attempt(feed, "Hunter", 1, "weapon_smg1", "Prop", 2), "ok")
me = saved

print("\n== The notice lifetime cvar is the archived PH one ==")
CreateConVar("hud_deathnotice_limit", "5")
CreateConVar("ph_cl_deathnotice_time", "3")
lives = {}
feed("Hunter", 1, "weapon_smg1", "Prop", 2)
check("notice lives ph_cl_deathnotice_time seconds", lives[#lives], 3)
local f = io.open((debug.getinfo(1, "S").source:match("@(.*/)") or "./")
  .. "../../../gamemodes/base_phx/gamemode/vgui/vgui_gamenotice.lua")
local src = f:read("*a"); f:close()
check("ph_cl_deathnotice_time is created archived",
  src:find('CreateClientConVar%( "ph_cl_deathnotice_time", "6", true') ~= nil, true)

print("\n== The feed follows a resolution change ==")
local size, shuffled
function g_DeathNotify:SetSize(w, h) size = w .. "x" .. h end
function g_DeathNotify:Shuffle() shuffled = true end
scrW, scrH = 2560, 1440
S.fire("OnScreenSizeChanged", 1920, 1080)
check("resized to the new screen", size, "2535x1440")
check("notices re-laid out", shuffled, true)
local dn = g_DeathNotify
g_DeathNotify = nil
check("no feed yet: no error", attempt(S.fire, "OnScreenSizeChanged", 2560, 1440), "ok")
g_DeathNotify = dn

print("\n== GameNotice: one label per argument ==")
local labels
vgui = { Create = function(cls)
  local l = { cls = cls }
  function l:SetText(t) self.text = t end
  l.SetTextColor, l.ApplySchemeSettings = noop, noop
  return l
end }
function Derma_Hook() end
string.Left = function(s, n) return s:sub(1, n) end
function GAMEMODE:GetTeamColor() return color_white end

local GameNotice = loadchunk([[
local _type = type
local type = function(v) local mt = getmetatable(v) if mt and mt.__type then return mt.__type end return _type(v) end
function isentity(v) local t = type(v) return t == "Entity" or t == "Player" end
local PANEL = {}
]] .. extractAll("gamemodes/base_phx/gamemode/vgui/vgui_gamenotice.lua", {
  [[^function PANEL:AddEntityText]], [[^function PANEL:AddItem]], [[^function PANEL:AddText]] })
  .. "\nreturn PANEL", "vgui_gamenotice.lua")()

local function Ent(t, valid, cls)
  return setmetatable({ IsValid = function() return valid end, GetClass = function() return cls end,
                        Nick = function() return "Nick" end },
    { __type = t, __tostring = function() return valid and ("Entity [1][" .. cls .. "]") or "[NULL Entity]" end })
end
local function note(v)
  local p = setmetatable({ Items = {}, InvalidateLayout = noop }, { __index = GameNotice })
  local ok = attempt(p.AddText, p, v)
  labels = {}
  for _, l in ipairs(p.Items) do labels[#labels + 1] = l.text end
  return ok, table.concat(labels, "|"), p
end

local ok, txt = note(Ent("Entity", true, "prop_physics"))
check("a valid entity: one label, its class", txt, "prop_physics")
ok, txt = note(Ent("Entity", false))
check("a NULL entity: one label", txt, "[NULL Entity]")
ok, txt = note(5)
check("a number does not raise", ok, "ok")
check("a number prints once", txt, "5")
ok, txt = note("Bob")
check("a string prints once", txt, "Bob")
ok, txt = note(nil)
check("nil prints nothing", txt, "")
local p
ok, txt, p = note(Ent("Player", true, "player"))
check("a player prints their nick", txt, "Nick")

report()
