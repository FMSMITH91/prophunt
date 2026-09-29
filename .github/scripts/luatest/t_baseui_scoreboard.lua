dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- base_phx scoreboards: the classic Fretta board's columns and sort, TAB
-- show/hide against the map vote, and the modern board's custom columns.

local here = (debug.getinfo(1, "S").source:match("@(.*/)") or "./")
local REPO = here .. "../../../"

local function noop() end
_G.REALTIME = 100
function RealTime() return _G.REALTIME end
function ColorAlpha(c) return c end
TEXT_ALIGN_CENTER = 1

loadblocks("SBTranslate", extract("gamemodes/base_phx/gamemode/cl_scoreboard_admin.lua",
  [[^function PHX:SBTranslate]]))

-- Classic board: column order and sort ----------------------------------------

-- The real FrettaScoreboard:AddColumn, driving one team board that numbers its
-- columns in call order exactly as TeamScoreboard:AddColumn does.
local Fretta = loadchunk("local PANEL = {}\n"
  .. extract("gamemodes/base_phx/gamemode/vgui/vgui_scoreboard.lua", [[^function PANEL:AddColumn]])
  .. "\nreturn PANEL", "vgui_scoreboard.lua")()

loadblocks("cl_scores.lua@columns", extractAll("gamemodes/base_phx/gamemode/cl_scores.lua", {
  [[^function GM:AddScoreboardAvatar]], [[^function GM:AddScoreboardVoice]],
  [[^function GM:AddScoreboardName]], [[^function GM:AddScoreboardKills]],
  [[^function GM:AddScoreboardDeaths]], [[^function GM:AddScoreboardPing]],
  [[^function GM:AddScoreboardCustom]], [[^function GM:CreateScoreboard]] }))

-- origin/master's CreateScoreboard also called this. Defined here only so the
-- old code can still run as a negative control; it adds the same empty column.
if not GM.AddScoreboardWantsChange then
  function GM:AddScoreboardWantsChange(sb) sb:AddColumn("", 16, function() end, 2, nil, 6, 6) end
end

GAMEMODE.TeamBased = true

local function ClassicBoard(extraCols)
  S.hooks.PH_AddColumnScoreboard = nil
  if extraCols > 0 then
    hook.Add("PH_AddColumnScoreboard", "test", function(_, add)
      for i = 1, extraCols do add("Custom" .. i, 40, function() return "x" end, 1) end
    end)
  end
  local team = { cols = {} }
  function team:AddColumn(col) self.cols[#self.cols + 1] = col end
  local sb = { Boards = { [1] = team }, AddColumn = Fretta.AddColumn,
               SetRowHeight = noop, SetAsBullshitTeam = noop, SetShowScoreboardHeaders = noop,
               SetHorizontal = noop, SetSkin = noop }
  function sb:SetSortColumns(t) self.sort = t end
  GAMEMODE:CreateScoreboard(sb)
  return sb, team.cols
end

local function colName(cols, i) return cols[i] and cols[i].Name or ("<no column " .. tostring(i) .. ">") end

print("\n== Classic board sorts by Kills, Deaths, Name whatever columns an addon adds ==")
for _, n in ipairs{ 0, 1, 2 } do
  local sb, cols = ClassicBoard(n)
  local tag = ("%d hook column(s): "):format(n)
  check(tag .. "first sort key is Kills", colName(cols, sb.sort[1]), "Kills")
  check(tag .. "Kills sorts descending", sb.sort[2], true)
  check(tag .. "second sort key is Deaths", colName(cols, sb.sort[3]), "Deaths")
  check(tag .. "third sort key is Name", colName(cols, sb.sort[5]), "Name")
end
local _, cols = ClassicBoard(0)
check("no dead WantsChange column (6 columns)", #cols, 6)
S.hooks.PH_AddColumnScoreboard = nil

print("\n== Classic headers and ping fall back to English, not the raw key ==")
-- The shim's FTranslate echoes the key, as the real one does for a missing string.
local names = {}
for _, c in ipairs(cols) do names[#names + 1] = c.Name end
check("headers", table.concat(names, ","), ",Mute,Name,Kills,Deaths,Ping")
local ping = cols[#cols].fncValue   -- Ping is always the last column
local function pinger(v) return { ScoreboardPing = function() return v end } end
check("ping: a number is shown as is", ping(pinger(57)), 57)
check("ping: the host tag reads SV", ping(pinger("DERMA_SERVER_TAG")), "SV")
check("ping: the bot tag reads BOT", ping(pinger("DERMA_BOT_TAG")), "BOT")
local realFT = PHX.FTranslate
PHX.FTranslate = function(_, k) return ({ DERMA_BOT_TAG = "ROBOT" })[k] or k end
check("ping: a translated tag is used", ping(pinger("DERMA_BOT_TAG")), "ROBOT")
PHX.FTranslate = realFT

local f = io.open(REPO .. "gamemodes/base_phx/gamemode/cl_scores.lua"); local src = f:read("*a"); f:close()
check("the WantsChange column is gone from cl_scores.lua", src:find("AddScoreboardWantsChange", 1, true), nil)

print("\n== Classic team header uses the translated player count ==")
local Header = loadchunk("local PANEL = {}\n"
  .. extract("gamemodes/base_phx/gamemode/vgui/vgui_scoreboard_team.lua", [[^function PANEL:Think]])
  .. "\nreturn PANEL", "vgui_scoreboard_team.lua")()
local function header(n)
  S.players = {}
  for i = 1, n do S.players[i] = S.Player{ team = TEAM_PROPS } end
  local h = { iTeamID = TEAM_PROPS, PlayerCount = -1,
              TeamName = { SetText = function(self, t) self.text = t end },
              TeamScore = { SetText = noop } }
  Header.Think(h)
  return h.TeamName.text
end
check("one player", header(1), "Props (1 player)")
check("three players", header(3), "Props (3 players)")
PHX.FTranslate = function(_, k, ...) if k == "DERMA_PLAYERS" then return string.format("(%d Spieler)", ...) end return k end
check("translated count", header(3), "Props (3 Spieler)")
PHX.FTranslate = realFT
S.players = {}

-- TAB: show and hide ------------------------------------------------------------

print("\n== TAB builds one board, and a closed map vote does not block it ==")
local built, clicker = 0, nil
gui = { EnableScreenClicker = function(b) clicker = b end }
function CloseDermaMenus() end
vgui = { Create = function()
  built = built + 1
  local p = { __valid = true, visible = true }   -- new panels start visible
  function p:SetVisible(b) self.visible = b end
  function p:IsVisible() return self.visible end
  function p:Remove() self.__valid = false end
  return p
end }
function PHX:UseModernScoreboard() return true end
GAMEMODE.CreateModernScoreboard = noop
GAMEMODE.PositionScoreboard = noop
PHX.ScoreboardDialogOpen = function() return false end

loadblocks("cl_scores.lua@tab", extractAll("gamemodes/base_phx/gamemode/cl_scores.lua", {
  [[^function GM:GetScoreboard]], [[^local function MapVoteOnScreen]],
  [[^function GM:ScoreboardShow]], [[^function GM:ScoreboardHide]] }))

local function Vote(visible)
  return { __valid = true, IsVisible = function() return visible end }
end

PHX.MV = nil
g_ScoreBoard = nil
built = 0
GAMEMODE:ScoreboardShow()
check("no vote: TAB builds exactly one board", built, 1)
check("no vote: the board is shown", g_ScoreBoard.visible, true)
check("no vote: cursor on", clicker, true)
local shown = g_ScoreBoard
built = 0
GAMEMODE:ScoreboardHide()
check("no vote: releasing TAB builds nothing", built, 0)
check("no vote: the shown board is hidden", shown.visible, false)
check("no vote: cursor released", clicker, false)

PHX.MV = { Panel = Vote(true) }
built, clicker = 0, "untouched"
GAMEMODE:ScoreboardShow()
check("vote on screen: TAB does not cover it", built, 0)
check("vote on screen: cursor left alone", clicker, "untouched")
GAMEMODE:ScoreboardHide()
check("vote on screen: release keeps the vote's cursor", clicker, "untouched")

PHX.MV = { Panel = Vote(false) }   -- the classic vote's X button hides it
built = 0
GAMEMODE:ScoreboardShow()
check("vote closed with X: TAB shows the board", built, 1)
check("vote closed with X: board visible", g_ScoreBoard.visible, true)
GAMEMODE:ScoreboardHide()
check("vote closed with X: release frees the cursor", clicker, false)
PHX.MV = nil

-- Modern board: custom columns ---------------------------------------------------

print("\n== Modern board: a custom column cannot leak panels ==")
-- Panels need type() == "Panel", as GMod reports for vgui objects.
local PanelMT = { __type = "Panel" }
PanelMT.__index = PanelMT
function PanelMT:SetParent(p) self.parent = p end
function PanelMT:Remove() self.__valid = false; self.removed = true end
function PanelMT:InvalidateLayout() end
local created = {}
local function NewPanel()
  local p = setmetatable({ __valid = true }, PanelMT)
  created[#created + 1] = p
  return p
end
local drawn = {}
draw = { SimpleText = function(t) drawn[#drawn + 1] = t end }

local Modern = loadchunk([[
local _type = type
local type = function(v) local mt = getmetatable(v) if mt and mt.__type then return mt.__type end return _type(v) end
local PANEL = {}
local SBScale = function(n) return n end
local COL_TEXT = {}
]] .. extractAll("gamemodes/base_phx/gamemode/vgui/vgui_scoreboard_modern.lua", {
  [[^local function UpdateCustomCell]], [[^function PANEL:AddColumn]],
  [[^function PANEL:BuildCustomPanels]] }) .. "\nreturn PANEL", "vgui_scoreboard_modern.lua")()

local function Board() return { CustomCols = {}, RebuildCells = noop,
                                AddColumn = Modern.AddColumn, BuildCustomPanels = Modern.BuildCustomPanels } end
local function Row() local r = NewPanel(); r.CustomPanels = {}; return r end
local function frames(row, col, ply, n, step)
  for _ = 1, n do col.draw(row, ply, 0, col, 30, 255); _G.REALTIME = _G.REALTIME + (step or 0) end
end
local function orphans(row)
  local n = 0
  for _, p in ipairs(created) do
    if p ~= row and not p.removed and p.parent ~= row then n = n + 1 end
  end
  return n
end

-- Fretta's own pattern: build a label only while a condition holds.
local afk, calls = false, 0
local board = Board()
local col = board:AddColumn("", 16, function()
  calls = calls + 1
  if afk then local l = NewPanel(); return l end
end, 2)
local ply = S.Player{}
created = {}
local row = Row()
board:BuildCustomPanels(row, ply)            -- not AFK when the row is built
afk = true                                    -- ...then they go AFK while TAB is held
calls = 0
frames(row, col, ply, 144, 1 / 144)           -- one second at 144 fps
check("144 frames: no orphaned panels", orphans(row), 0)
check("144 frames: asked at most twice (UpdateRate 2)", calls <= 2, true)
frames(row, col, ply, 144 * 5, 1 / 144)       -- five more seconds
check("6 s: still no orphaned panels", orphans(row), 0)
check("6 s: the latest label is on the row", row.CustomPanels[col.id] and row.CustomPanels[col.id].parent == row, true)

-- A panel column adopted at build time is refreshed at its rate, replacing the
-- old panel rather than stacking a new one on top.
board = Board()
created = {}
col = board:AddColumn("Icon", 16, function() return NewPanel() end, 1)
row = Row()
board:BuildCustomPanels(row, ply)
local first = row.CustomPanels[col.id]
check("build time: panel adopted", first ~= nil and first.parent == row, true)
frames(row, col, ply, 10, 0)
check("within UpdateRate: same panel kept", row.CustomPanels[col.id], first)
_G.REALTIME = _G.REALTIME + 1.5
frames(row, col, ply, 1, 0)
check("after UpdateRate: old panel removed", first.removed, true)
check("after UpdateRate: no orphans", orphans(row), 0)

print("\n== Modern board: text columns still draw every frame ==")
board = Board()
local frags = 3
calls = 0
col = board:AddColumn("Score", 40, function() calls = calls + 1; return frags end, 1)
row = Row()
board:BuildCustomPanels(row, ply)
drawn = {}
frames(row, col, ply, 30, 0)
check("value drawn on every frame", #drawn, 30)
check("value text", drawn[#drawn], "3")
frags = 4
frames(row, col, ply, 1, 0)
check("within UpdateRate: previous value", drawn[#drawn], "3")
_G.REALTIME = _G.REALTIME + 1.1
frames(row, col, ply, 1, 0)
check("after UpdateRate: new value", drawn[#drawn], "4")
check("asked twice, not once per frame", calls, 2)

board = Board()
calls = 0
col = board:AddColumn("Once", 40, function() calls = calls + 1; return "v" end, 0)
row = Row()
board:BuildCustomPanels(row, ply)
_G.REALTIME = _G.REALTIME + 50
frames(row, col, ply, 20, 1)
check("UpdateRate 0: asked once", calls, 1)

board = Board()
col = board:AddColumn("Broken", 40, function() error("addon bug") end, 1)
row = Row()
check("a column that errors does not take the board down",
  attempt(function() board:BuildCustomPanels(row, ply); frames(row, col, ply, 5, 1) end), "ok")

report()
