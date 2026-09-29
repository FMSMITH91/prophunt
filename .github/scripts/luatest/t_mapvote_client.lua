dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- Client half of the map vote: hiding the modern screen, handing the cursor
-- back, and the classic screen's voter icons. Runs the shipped functions with
-- stand-in panels; the Derma drawing itself cannot run here.

local CLV = "gamemodes/prop_hunt/gamemode/mapvote/cl_mapvote.lua"
local CUI = "gamemodes/prop_hunt/gamemode/mapvote/cl_mapvote_ui.lua"

-- Engine includes/util.lua returns false for a falsy argument; the shim raises.
-- MapVote.Panel starts out as `false`, so that difference matters here.
local shimIsValid = IsValid
function IsValid(e) if not e then return false end return shimIsValid(e) end

net.SendToServer = function() S.net.cur.to = "server"; table.insert(S.net.sent, S.net.cur) end
S.clicker = {}
gui = { EnableScreenClicker = function(b) S.clicker[#S.clicker + 1] = b end }

-- A stand-in panel: visibility, removal (which invalidates it, as in GMod) and
-- the few layout calls the code makes.
local function Panel(t)
  local p = t or {}
  p.__valid, p._visible, p.removed = true, true, 0
  function p:SetVisible(b) self._visible = b end
  function p:IsVisible() return self._visible end
  function p:Remove() self.removed = self.removed + 1; self.__valid = false end
  function p:MoveTo(x, y) self.x, self.y = x, y end
  function p:GetWide() return self.w or 100 end
  function p:GetTall() return self.h or 20 end
  function p:SetText() end function p:SizeToContents() end function p:CenterHorizontal() end
  return p
end

PHX.MV = { Votes = {}, UPDATE_VOTE = 1, EndTime = 0 }
PHX.MV.HasExtraVotePower = function() return false end

local function loadPanel(path, specs)
  return loadblocks(path, extractAll(path, specs), "local MapVote = PHX.MV\nlocal PANEL = {}\n")
end
local function chunkReturningPanel(path, specs)
  return loadchunk("local MapVote = PHX.MV\nlocal PANEL = {}\n" .. extractAll(path, specs) .. "\nreturn PANEL", path)()
end

------------------------------------------------------------------------------
print("\n== #50: the modern vote screen can be hidden and brought back ==")
------------------------------------------------------------------------------
loadPanel(CUI, { [[^function MapVote\.ReleaseCursor]] })
local Screen = chunkReturningPanel(CUI, { [[^function PANEL:Minimise]], [[^function PANEL:SendVote]] })
loadblocks(CLV, extractAll(CLV, { [[^net\.Receive\("PHX\.MV\.Cancel"]], [[^concommand\.Add\( "ph_mapvote_show"]] }),
  "local MapVote = PHX.MV\n")

local function screen()
  local s = Panel()
  for k, v in pairs(Screen) do s[k] = v end
  return s
end

do
  local s = screen()
  s.Pending, s.NextSend = 2, CurTime() + 0.3
  S.net.sent, S.clicker, g_ScoreBoard = {}, {}, nil
  s:Minimise()
  local m = S.net.sent[1]
  check("hiding sends the vote still waiting on the debounce", m and m.name, "PHX.MV.Update")
  check("  ...for the map last clicked", m and m.data[2], 2)
  check("  ...and clears it", s.Pending, nil)
  check("the screen is hidden", s:IsVisible(), false)
  check("the cursor is handed back", S.clicker[1], false)

  s = screen()
  S.net.sent, S.clicker = {}, {}
  g_ScoreBoard = Panel()
  s:Minimise()
  check("nothing pending: nothing sent", #S.net.sent, 0)
  check("scoreboard open: it keeps the cursor", #S.clicker, 0)

  g_ScoreBoard = Panel(); g_ScoreBoard:SetVisible(false)
  PHX.MV.Panel = s
  S.concommands["ph_mapvote_show"].fn()
  check("ph_mapvote_show brings it back", s:IsVisible(), true)
  PHX.MV.Panel = false
  check("ph_mapvote_show with no vote is harmless", attempt(S.concommands["ph_mapvote_show"].fn), "ok")

  S.clicker = {}
  PHX.MV.Panel = s
  S.receivers["PHX.MV.Cancel"]()
  check("cancel removes the screen", s.removed, 1)
  check("cancel hands the cursor back", S.clicker[1], false)
  S.clicker = {}
  g_ScoreBoard:SetVisible(true)
  PHX.MV.Panel = screen()
  S.receivers["PHX.MV.Cancel"]()
  check("cancel with the scoreboard open leaves its cursor", #S.clicker, 0)
end

------------------------------------------------------------------------------
print("\n== #184: classic screen voter icons ==")
------------------------------------------------------------------------------
local Classic = chunkReturningPanel(CLV, { [[^function PANEL:Think]], [[^function PANEL:GetMapButton]] })

do
  local bars = { Panel{ ID = 1, x = 0, y = 0 }, Panel{ ID = 2, x = 0, y = 30 } }
  local c = Panel()
  for k, v in pairs(Classic) do c[k] = v end
  c.mapList = { GetItems = function() return bars end }
  c.countDown = Panel()

  local stay = S.Player{ sid = "STEAM_0:0:1" }
  local gone = S.Player{ sid = "STEAM_0:0:2" }
  local odd  = S.Player{ sid = "STEAM_0:0:3" }
  local iStay, iGone, iOdd = Panel{ Player = stay }, Panel{ Player = gone }, Panel{ Player = odd }
  c.Voters = { iStay, iGone, iOdd }
  PHX.MV.Votes = { [stay:SteamID()] = 2, [gone:SteamID()] = 1, [odd:SteamID()] = 7 }

  gone.__valid = false
  check("an unknown map id does not error", attempt(c.Think, c), "ok")
  check("the leaver's icon is removed", iGone.removed, 1)
  check("  ...and dropped from the list", #c.Voters, 2)
  check("the vote on a real map is counted", bars[2].NumVotes, 1)
  check("the unknown id counts nowhere", bars[1].NumVotes, 0)
  attempt(c.Think, c); attempt(c.Think, c)
  check("a removed icon is not removed again every frame", iGone.removed, 1)
  check("order of the remaining icons kept", c.Voters[1] == iStay and c.Voters[2] == iOdd, true)
end

------------------------------------------------------------------------------
print("\n== #50: the classic screen's close button hands the cursor back too ==")
------------------------------------------------------------------------------
do
  -- Init builds Derma children; any call it makes on them is a no-op here.
  local function Stub()
    return setmetatable(Panel(), { __index = function() return function() end end })
  end
  local realVgui = vgui
  vgui = { Create = function() return Stub() end }

  local ClassicInit = chunkReturningPanel(CLV, { [[^function PANEL:Init]], [[^function PANEL:AddWindowButtons]] })
  local c = Stub()
  for k, v in pairs(ClassicInit) do c[k] = v end
  check("classic screen builds", attempt(c.Init, c), "ok")

  S.clicker, g_ScoreBoard = {}, nil
  check("classic close button runs", attempt(c.closeButton.DoClick), "ok")
  check("the classic screen is hidden", c:IsVisible(), false)
  check("classic close: the cursor is handed back", S.clicker[1], false)

  S.clicker = {}
  g_ScoreBoard = Panel()
  c:SetVisible(true)
  c.closeButton.DoClick()
  check("classic close, scoreboard open: it keeps the cursor", #S.clicker, 0)

  -- Staff cancel: hides the screen before the server's PHX.MV.Cancel arrives,
  -- and a refused mv_stop never sends one.
  local me = S.Player{ sid = "STEAM_0:0:9" }
  local realChat, realLP = chat, LocalPlayer
  chat, LocalPlayer = { AddText = function() end }, function() return me end
  S.clicker, g_ScoreBoard = {}, nil
  c:SetVisible(true)
  check("classic cancel button runs", attempt(c.CancelBtn.DoClick), "ok")
  check("  ...asks the server to stop the vote", me.concmds[1], "mv_stop")
  check("  ...hides the classic screen", c:IsVisible(), false)
  check("classic cancel: the cursor is handed back", S.clicker[1], false)

  S.clicker = {}
  g_ScoreBoard = Panel()
  c:SetVisible(true)
  c.CancelBtn.DoClick()
  check("classic cancel, scoreboard open: it keeps the cursor", #S.clicker, 0)
  chat, LocalPlayer = realChat, realLP
  vgui = realVgui
end

------------------------------------------------------------------------------
print("\n== the staff Cancel button is gone in the end-of-game vote ==")
------------------------------------------------------------------------------
-- The server refuses that cancel; this is the cosmetic half. Both screens run
-- their real PerformLayout, the modern one with its whole file loaded.
do
  local function Stub()
    return setmetatable(Panel(), { __index = function() return function() end end })
  end
  local realVgui, realChat, realLP = vgui, chat, LocalPlayer
  ScrW, ScrH = function() return 1920 end, function() return 1080 end
  chat = { GetChatBoxPos = function() return 0, 0 end }
  surface, Material = { CreateFont = function() end }, function() return {} end
  local registered = {}
  vgui = { Create = function() return Stub() end, Register = function(n, t) registered[n] = t end }

  loadblocks(CLV, extract(CLV, [[^function MapVote\.CanCancel]]), "local MapVote = PHX.MV\n")
  loadblocks(CUI, extract(CUI, "1-999999"))
  local ClassicLayout = chunkReturningPanel(CLV, { [[^function PANEL:Init]], [[^function PANEL:AddWindowButtons]],
                                                   [[^function PANEL:PerformLayout]] })

  local function classic()
    local c = Stub()
    for k, v in pairs(ClassicLayout) do c[k] = v end
    c:Init()
    c.CancelBtn.GetParent = function() return Panel() end
    return c
  end
  local function modern(winner)
    -- Not a Stub: that answers every missing field with a function, so an unset
    -- self.Winner would read as a winner, where a real panel reads nil.
    local m = Panel()
    m.SetSize = function() end
    for k, v in pairs(registered.PHXMapVote) do m[k] = v end
    m.Cards, m.Winner = {}, winner
    m.Canvas, m.Scroll, m.CancelBtn, m.HideBtn = Stub(), Stub(), Stub(), Stub()
    return m
  end
  -- Lays the screen out as `ply` at this point of the game; nil if it errors.
  local function shown(pnl, ply, endOfGame)
    LocalPlayer = function() return ply end
    SetGlobalBool("IsEndOfGame", endOfGame or nil)
    local ok = attempt(pnl.PerformLayout, pnl, 1920, 1080)
    if ok ~= "ok" then print("  layout error: " .. ok) return nil end
    return pnl.CancelBtn:IsVisible()
  end

  local staff, pleb = S.Player{ staff = true }, S.Player{}
  check("classic, mid-game vote: staff see Cancel", shown(classic(), staff), true)
  check("classic, end-of-game vote: staff do not", shown(classic(), staff, true), false)
  check("classic, mid-game vote: players never did", shown(classic(), pleb), false)
  check("modern, mid-game vote: staff see Cancel", shown(modern(), staff), true)
  check("modern, end-of-game vote: staff do not", shown(modern(), staff, true), false)
  check("modern, once a map has won: gone, as before", shown(modern(2), staff), false)
  check("modern, mid-game vote: players never did", shown(modern(), pleb), false)

  SetGlobalBool("IsEndOfGame", nil)
  vgui, chat, LocalPlayer = realVgui, realChat, realLP
end

report()
