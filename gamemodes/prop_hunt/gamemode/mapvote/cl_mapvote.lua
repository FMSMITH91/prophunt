local MapVote = PHX.MV

MapVote.EndTime = 0
MapVote.Panel = false
MapVote.Duration = 0

local cvarModern = CreateClientConVar( "ph_cl_modern_mapvote", "1", true, false,
    "Use the modern map vote screen. 0 falls back to the classic list." )

net.Receive("PHX.MV.Start", function()
    MapVote.CurrentMaps = {}
    MapVote.Allow = true
    MapVote.Votes = {}
    
    local amt = net.ReadUInt(32)
    
    for i = 1, amt do
        local map = net.ReadString()
        
        MapVote.CurrentMaps[#MapVote.CurrentMaps + 1] = map
    end
    
    local duration = net.ReadUInt(32)
    
    MapVote.Duration = duration
    MapVote.EndTime = CurTime() + duration
    
    if(IsValid(MapVote.Panel)) then
        MapVote.Panel:Remove()
    end
    
    MapVote.Panel = vgui.Create( cvarModern:GetBool() and "PHXMapVote" or "PHXMapVoteClassic" )
    MapVote.Panel:SetMaps(MapVote.CurrentMaps)
    
    // GM:OnEndOfGame force-opens the scoreboard just before the vote starts.
    // Close it now the panel exists, so it cannot sit on top of the vote.
    if ( GAMEMODE && GAMEMODE.ScoreboardHide ) then GAMEMODE:ScoreboardHide() end
end)

net.Receive("PHX.MV.Update", function()
    local update_type = net.ReadUInt(3)
    
    if(update_type == MapVote.UPDATE_VOTE) then
        local ply = net.ReadEntity()
        
        if(IsValid(ply)) then
            local map_id = net.ReadUInt(32)
            MapVote.Votes[ply:SteamID()] = map_id
        
            if(IsValid(MapVote.Panel)) then
                MapVote.Panel:AddVoter(ply)
            end
        end
    elseif(update_type == MapVote.UPDATE_WIN) then      
        if(IsValid(MapVote.Panel)) then
            MapVote.Panel:Flash(net.ReadUInt(32))
        end
    end
end)

net.Receive("PHX.MV.Cancel", function()
    if IsValid(MapVote.Panel) then
        MapVote.Panel:Remove()
    end

    MapVote.ReleaseCursor()
end)

// The modern screen can be hidden mid-vote; this brings it back. The result
// re-opens it anyway.
concommand.Add( "ph_mapvote_show", function()
    if ( IsValid( MapVote.Panel ) ) then MapVote.Panel:SetVisible( true ) end
end, nil, "Show the map vote screen again after hiding it." )

// Whether the staff Cancel button shows, on either screen. Not once a map has
// won, and never in the end-of-game vote: that is the only way off the map, and
// the server refuses to cancel it (MapVote.PHXCancel), which is the real guard.
function MapVote.CanCancel( winner )
    return !winner && !GetGlobalBool( "IsEndOfGame", false )
end

local PANEL = {}

function PANEL:Init()
    self:ParentToHUD()
    
    self.Canvas = vgui.Create("Panel", self)
    self.Canvas:MakePopup()
    self.Canvas:SetKeyboardInputEnabled(false)
	
    self.countDown = vgui.Create("DLabel", self.Canvas)
    self.countDown:SetTextColor(color_white)
    self.countDown:SetFont("RAM_VoteFontCountdown")
    self.countDown:SetText("")
    self.countDown:SetPos(0, 14)
    
    self.mapList = vgui.Create("DPanelList", self.Canvas)
    self.mapList:SetPaintBackground(false)
    self.mapList:SetSpacing(4)
    self.mapList:SetPadding(4)
    self.mapList:EnableHorizontal(true)
    self.mapList:EnableVerticalScrollbar()
    
    self:AddWindowButtons()
	
	self.CancelBtn = vgui.Create("DButton", self.Canvas)
	self.CancelBtn:SetPos(0,0)
	self.CancelBtn:SetText("Cancel MapVote")
	self.CancelBtn:SetSize(160,32)
	self.CancelBtn.DoClick = function()
		chat.AddText( "MapVote has been stopped." )
		LocalPlayer():ConCommand("mv_stop")
		self:SetVisible(false)
		MapVote.ReleaseCursor()
	end

    self.Voters = {}
end

// The close, maximise and minimise buttons of the old window chrome. Only
// close does anything: it hides the vote, which ph_mapvote_show brings back.
function PANEL:AddWindowButtons()
    self.closeButton = vgui.Create("DButton", self.Canvas)
    self.closeButton:SetText("")

    self.closeButton.Paint = function(panel, w, h)
        derma.SkinHook("Paint", "WindowCloseButton", panel, w, h)
    end

    self.closeButton.DoClick = function()
        print("Map Voting has been started...")
        self:SetVisible(false)
        MapVote.ReleaseCursor()
    end

    self.maximButton = vgui.Create("DButton", self.Canvas)
    self.maximButton:SetText("")
    self.maximButton:SetDisabled(true)

    self.maximButton.Paint = function(panel, w, h)
        derma.SkinHook("Paint", "WindowMaximizeButton", panel, w, h)
    end

    self.minimButton = vgui.Create("DButton", self.Canvas)
    self.minimButton:SetText("")
    self.minimButton:SetDisabled(true)

    self.minimButton.Paint = function(panel, w, h)
        derma.SkinHook("Paint", "WindowMinimizeButton", panel, w, h)
    end
end

function PANEL:PerformLayout()
    local cx, cy = chat.GetChatBoxPos()
    
    self:SetPos(0, 0)
    self:SetSize(ScrW(), ScrH())
    
    local extra = math.Clamp(300, 0, ScrW() - 640)
    self.Canvas:StretchToParent(0, 0, 0, 0)
    self.Canvas:SetWide(640 + extra)
    // self.Canvas:SetTall(cy -60)
	self.Canvas:SetTall(self:GetTall())
    self.Canvas:SetPos(0, 64)
    self.Canvas:CenterHorizontal()
    self.Canvas:SetZPos(0)
    
    self.mapList:StretchToParent(0, 90, 0, 220)

    local buttonPos = 640 + extra - 31 * 3

    self.closeButton:SetPos(buttonPos - 31 * 0, 4)
    self.closeButton:SetSize(31, 31)
    self.closeButton:SetVisible(true)

    self.maximButton:SetPos(buttonPos - 31 * 1, 4)
    self.maximButton:SetSize(31, 31)
    self.maximButton:SetVisible(true)

    self.minimButton:SetPos(buttonPos - 31 * 2, 4)
    self.minimButton:SetSize(31, 31)
    self.minimButton:SetVisible(true)
	
	self.CancelBtn:CenterHorizontal()
	self.CancelBtn:SetY( self.CancelBtn:GetParent():GetTall() - 200 )
	if ( LocalPlayer():PHXIsStaff() && MapVote.CanCancel() ) then
		self.CancelBtn:SetVisible( true )
	else
		self.CancelBtn:SetVisible( false )
	end
    
end

local star_mat = Material("icon16/star.png")

function PANEL:AddVoter(voter)
    for k, v in pairs(self.Voters) do
        if(v.Player and v.Player == voter) then
            return false
        end
    end
    
    
    local icon_container = vgui.Create("Panel", self.mapList:GetCanvas())
    local icon = vgui.Create("AvatarImage", icon_container)
    icon:SetSize(16, 16)
    icon:SetZPos(1000)
    icon:SetTooltip(voter:Name())
    icon_container.Player = voter
    icon_container:SetTooltip(voter:Name())
    icon:SetPlayer(voter, 16)

    if MapVote.HasExtraVotePower(voter) then
        icon_container:SetSize(40, 20)
        icon:SetPos(21, 2)
        icon_container.img = star_mat
    else
        icon_container:SetSize(20, 20)
        icon:SetPos(2, 2)
    end
    
    icon_container.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Color(255, 0, 0, 80))
        
        if(icon_container.img) then
            surface.SetMaterial(icon_container.img)
            surface.SetDrawColor(Color(255, 255, 255))
            surface.DrawTexturedRect(2, 2, 16, 16)
        end
    end
    
    table.insert(self.Voters, icon_container)
end

function PANEL:Think()
    for k, v in pairs(self.mapList:GetItems()) do
        v.NumVotes = 0
    end
    
    // Removed icons are dropped from the list, not Removed again every frame
    // for the rest of the vote.
    local kept = {}
    
    for _, v in ipairs(self.Voters) do
        if(not IsValid(v.Player) or not MapVote.Votes[v.Player:SteamID()]) then
            v:Remove()
        else
            kept[#kept + 1] = v
            
            // GetMapButton returns false for an unknown id.
            local bar = self:GetMapButton(MapVote.Votes[v.Player:SteamID()])
            
            if(IsValid(bar)) then
                if(MapVote.HasExtraVotePower(v.Player)) then
                    bar.NumVotes = bar.NumVotes + 2
                else
                    bar.NumVotes = bar.NumVotes + 1
                end
                
                local CurrentPos = Vector(v.x, v.y, 0)
                local NewPos = Vector((bar.x + bar:GetWide()) - 21 * bar.NumVotes - 2, bar.y + (bar:GetTall() * 0.5 - 10), 0)
                
                if(not v.CurPos or v.CurPos ~= NewPos) then
                    v:MoveTo(NewPos.x, NewPos.y, 0.3)
                    v.CurPos = NewPos
                end
            end
        end
        
    end
    
    self.Voters = kept
    
    local timeLeft = math.Round(math.Clamp(MapVote.EndTime - CurTime(), 0, math.huge))
    
    self.countDown:SetText(tostring(timeLeft or 0).." seconds")
    self.countDown:SizeToContents()
    self.countDown:CenterHorizontal()
end

function PANEL:SetMaps(maps)
    self.mapList:Clear()
    
    for k, v in RandomPairs(maps) do
        local button = vgui.Create("DButton", self.mapList)
        button.ID = k
        button:SetText(v)
        
        button.DoClick = function()
            net.Start("PHX.MV.Update")
                net.WriteUInt(MapVote.UPDATE_VOTE, 3)
                net.WriteUInt(button.ID, 32)
            net.SendToServer()
        end
        
        do
            local Paint = button.Paint
            button.Paint = function(s, w, h)
                local col = Color(255, 255, 255, 10)
                
                if(button.bgColor) then
                    col = button.bgColor
                end
                
                draw.RoundedBox(4, 0, 0, w, h, col)
                Paint(s, w, h)
            end
        end
        
        button:SetTextColor(color_white)
        button:SetContentAlignment(4)
        button:SetTextInset(8, 0)
        button:SetFont("RAM_VoteFont")
        
        local extra = math.Clamp(300, 0, ScrW() - 640)
        
        button:SetPaintBackground(false)
        button:SetTall(24)
        button:SetWide(285 + (extra / 2))
        button.NumVotes = 0
        
        self.mapList:AddItem(button)
    end
end

function PANEL:GetMapButton(id)
    for k, v in pairs(self.mapList:GetItems()) do
        if(v.ID == id) then return v end
    end
    
    return false
end

function PANEL:Paint()
    --Derma_DrawBackgroundBlur(self)
    
    local CenterY = ScrH() / 2
    local CenterX = ScrW() / 2
    
    surface.SetDrawColor(0, 0, 0, 200)
    surface.DrawRect(0, 0, ScrW(), ScrH())
end

function PANEL:Flash(id)
    self:SetVisible(true)

    local bar = self:GetMapButton(id)
	
	self.CancelBtn:SetEnabled(false)
    
    if(IsValid(bar)) then
        timer.Simple( 0.0, function() bar.bgColor = Color( 0, 255, 255 ) surface.PlaySound( "hl1/fvox/blip.wav" ) end )
        timer.Simple( 0.2, function() bar.bgColor = nil end )
        timer.Simple( 0.4, function() bar.bgColor = Color( 0, 255, 255 ) surface.PlaySound( "hl1/fvox/blip.wav" ) end )
        timer.Simple( 0.6, function() bar.bgColor = nil end )
        timer.Simple( 0.8, function() bar.bgColor = Color( 0, 255, 255 ) surface.PlaySound( "hl1/fvox/blip.wav" ) end )
        timer.Simple( 1.0, function() bar.bgColor = Color( 100, 100, 100 ) end )
    end
end

-- Named PHXMapVoteClassic to stay clear of Fretta's old VoteScreen name.
derma.DefineControl("PHXMapVoteClassic", "", PANEL, "DPanel")