dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- base_phx cl_hud: what the round-state HUD shows while the server waits for
-- players, and that HUDPaint runs once per frame under prop_hunt. Derma is
-- stubbed down to "which texts ended up on the HUD layout".

CLIENT, SERVER = true, false
function GetGlobalEntity(k, d) local v = S.globals[k]; if v == nil then return d end return v end
function PHX:FTranslate(key) return "T:" .. key end        -- every key "exists"
function PHX:TranslateName(id) return team.GetName(id) end

local function elem(kind)
  return setmetatable({ kind = kind, items = {} }, { __index = function(_, k)
    return function(self, a)
      if k == "SetText" then self.text = a elseif k == "AddItem" then self.items[#self.items + 1] = a end
    end
  end })
end
vgui = { Create = elem }

local me = { alive = true, team = TEAM_HUNTERS, obs = false }
function LocalPlayer()
  return { GetNWString = function(_, _, d) return d end, Alive = function() return me.alive end,
           Team = function() return me.team end, GetNWFloat = function(_, _, d) return d end,
           IsObserver = function() return me.obs end, GetObserverMode = function() return 0 end,
           GetObserverTarget = function() return nil end, Nick = function() return "me" end }
end

-- Inheritance as gamemode.Register builds it: prop_hunt (GAMEMODE) inherits
-- base_phx's functions, BaseClass chains to base.
local BASE, BPHX = {}, {}
local baseHUD, onPaint = 0, 0
function BASE:HUDPaint() baseHUD = baseHUD + 1 end
BPHX.BaseClass = BASE
baseclass = { Get = function(n) if n == "gamemode_base" then return BASE end end }
GM = BPHX
loadblocks("cl_hud.lua", extract("gamemodes/base_phx/gamemode/cl_hud.lua", "1-999"))
loadblocks("cl_scoreboard_admin.lua@SBTranslate",
  extract("gamemodes/base_phx/gamemode/cl_scoreboard_admin.lua", [[^function PHX:SBTranslate]]))
GM = GAMEMODE
for k, v in pairs(BPHX) do if k ~= "BaseClass" and GAMEMODE[k] == nil then GAMEMODE[k] = v end end
GAMEMODE.BaseClass = BPHX
GAMEMODE.RoundBased, GAMEMODE.TeamBased, GAMEMODE.ShowTeamName = true, true, true
function GAMEMODE:InGamemodeVote() return false end
function GAMEMODE:InRound() return GetGlobalBool("InRound", false) end
local realOnPaint = GAMEMODE.OnHUDPaint
function GAMEMODE:OnHUDPaint() onPaint = onPaint + 1; return realOnPaint(self) end

-- Rebuild the HUD from the given globals and return every text on it.
local layout
local realCreate = vgui.Create
vgui.Create = function(k) local e = realCreate(k); if k == "DHudLayout" then layout = e end; return e end
local function hud(g, who)
  S.globals = g
  me.alive, me.team, me.obs = true, TEAM_HUNTERS, false
  for k, v in pairs(who or {}) do me[k] = v end
  GAMEMODE:RefreshHUD()
  local texts = {}
  for _, it in ipairs(layout and layout.items or {}) do
    if rawget(it, "Think") then it:Think() end
    if rawget(it, "text") then texts[#texts + 1] = it.text end
  end
  return table.concat(texts, "|")
end
S.players = { S.Player{ team = TEAM_HUNTERS }, S.Player{ team = TEAM_PROPS }, S.Player{ team = TEAM_PROPS } }

print("\n== waiting for players before a round ==")
check("stale round result + waiting: shows the wait",
  hud{ RoundResult = 2, RRText = "HUD_TEAMWIN", InRound = false, RoundWaitingToStart = true }, "T:HUD_WAITPLY")
check("... for a dead player too",
  hud({ RoundResult = 2, RRText = "HUD_TEAMWIN", InRound = false, RoundWaitingToStart = true }, { alive = false }), "T:HUD_WAITPLY")
hud{ RoundResult = 2, RRText = "HUD_TEAMWIN", InRound = false }
S.globals.RoundWaitingToStart = true
check("the wait starting rebuilds the HUD", GAMEMODE:HUDNeedsUpdate(), true)
check("no wait: the round result shows",
  hud{ RoundResult = 2, RRText = "HUD_TEAMWIN", InRound = false }, "T:HUD_TEAMWIN")
check("dead before the first round: translated text",
  hud({ InRound = false }, { alive = false }), "T:HUD_WAITPLY")

print("\n== a round paused by ph_waitforplayers ==")
local t = hud{ InRound = true, RoundWaitForPlayers = true }
check("server says paused (both teams populated): wait shown", t:find("T:HUD_WAITPLY", 1, true) ~= nil, true)
hud{ InRound = true, RoundWaitForPlayers = true }
S.globals.RoundWaitForPlayers = false
check("resume rebuilds the HUD", GAMEMODE:HUDNeedsUpdate(), true)
t = hud{ InRound = true, RoundWaitForPlayers = false }
check("not paused: no wait text", t:find("HUD_WAITPLY", 1, true), nil)

print("\n== HUDPaint runs once per frame ==")
baseHUD, onPaint = 0, 0
GAMEMODE:HUDPaint()
check("base HUDPaint once", baseHUD, 1)
check("OnHUDPaint once", onPaint, 1)

report()
