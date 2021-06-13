
include( "vgui/vgui_scoreboard.lua" )

function GM:GetScoreboard()

	if ( IsValid( g_ScoreBoard ) ) then
		g_ScoreBoard:Remove()
	end
	
	g_ScoreBoard = vgui.Create( "FrettaScoreboard" )
	self:CreateScoreboard( g_ScoreBoard )
	
	return g_ScoreBoard
	
end

function GM:ScoreboardShow()

	gui.EnableScreenClicker(true)
	GAMEMODE:GetScoreboard():SetVisible( true )
	GAMEMODE:PositionScoreboard( GAMEMODE:GetScoreboard() )
	
end

function GM:ScoreboardHide()
	
	gui.EnableScreenClicker(false)
	GAMEMODE:GetScoreboard():SetVisible( false )
	
end

function GM:AddScoreboardAvatar( ScoreBoard )

	local f = function( ply ) 	
		local av = vgui.Create( "AvatarImage", ScoreBoard )
			av:SetSize( 32, 32 )
			av:SetPlayer( ply )
			av.Click = function()
				--print( "LOL" )
				-- todo: Let's add something here in future. Hopefully...
			end
			return av
	end
	
	ScoreBoard:AddColumn( "", 32, f, 360 ) // Avatar

end

local function canMute(ply)
	return LocalPlayer():CheckGroup(ply:GetUserGroup() )
end
 
 
function GM:AddScoreboardVoice( ScoreBoard )
 
	local f = function(ply)
 
		local main = vgui.Create("DPanel", ScoreBoard)
			main:SetPaintBackground(false)
 
			local vc = vgui.Create("DImageButton", main)
				vc:SetPos(15, 6)
				vc:SetSize(20, 20)
			if IsValid(ply) && ply != LocalPlayer() then
				muted = false
				if canMute(ply) then
					muted = ply:IsMuted()
				else
					vc:SetAlpha(100)
				end
				vc:SetImage(muted and "icon16/sound_mute.png" or "icon16/sound.png")
			else
				vc:Hide()
			end
 
			function vc.DoClick()
				if IsValid(ply) && ply != LocalPlayer() && canMute(ply) then
					ply:SetMuted(!ply:IsMuted() )
				end
			end
		return main
	end
 
	ScoreBoard:AddColumn( "Mute", 40, f, 0.5, nil, 6, 6 )
 
end

function GM:AddScoreboardSpacer( ScoreBoard, iSize )
	ScoreBoard:AddColumn( "", 16 )
end

function GM:AddScoreboardName( ScoreBoard )

	local f = function( ply ) return ply:Name() end
	ScoreBoard:AddColumn( PHX:FTranslate("DERMA_NAME") or "Name", nil, f, 10, nil, 4, 4 )

end

function GM:AddScoreboardKills( ScoreBoard )

	local f = function( ply ) return ply:Frags() end
	ScoreBoard:AddColumn( PHX:FTranslate("DERMA_KILLS") or "Kills", 40, f, 0.5, nil, 6, 6 )

end

function GM:AddScoreboardDeaths( ScoreBoard )

	local f = function( ply ) return ply:Deaths() end
	ScoreBoard:AddColumn( PHX:FTranslate("DERMA_DEATHS") or "Deaths", 60, f, 0.5, nil, 6, 6 )

end

function GM:AddScoreboardPing( ScoreBoard )

	local f = function( ply ) return ply:ScoreboardPing() end
	ScoreBoard:AddColumn( PHX:FTranslate("DERMA_PING") or "Ping", 40, f, 0.1, nil, 6, 6 )

end

// THESE SHOULD BE THE ONLY FUNCTION YOU NEED TO OVERRIDE

function GM:PositionScoreboard( ScoreBoard )

	if ( GAMEMODE.TeamBased ) then
		ScoreBoard:SetSize( ScrW()/1.2, ScrH() - 50 )
		ScoreBoard:SetPos( (ScrW() - ScoreBoard:GetWide()) * 0.5,  25 )
	else
		ScoreBoard:SetSize( 420, ScrH() - 64 )
		ScoreBoard:SetPos( (ScrW() - ScoreBoard:GetWide()) / 2, 32 )
	end

end

function GM:AddScoreboardWantsChange( ScoreBoard )

	local f = function( ply ) 
					if ( ply:GetNWBool( "WantsVote", false ) ) then 
						local lbl = vgui.Create( "DLabel" )
							lbl:SetFont( "Marlett" )
							lbl:SetText( "a" )
							lbl:SetTextColor( Color( 100, 255, 0 ) )
							lbl:SetContentAlignment( 5 )
						return lbl
					end					
				end
				
	ScoreBoard:AddColumn( "", 16, f, 2, nil, 6, 6 )

end

function GM:CreateScoreboard( ScoreBoard )

	// This makes it so that it's behind chat & hides when you're in the menu
	// Disable this if you want to be able to click on stuff on your scoreboard
	//ScoreBoard:ParentToHUD()
	
	ScoreBoard:SetRowHeight( 32 )

	ScoreBoard:SetAsBullshitTeam( TEAM_SPECTATOR )
	ScoreBoard:SetAsBullshitTeam( TEAM_CONNECTING )
	ScoreBoard:SetShowScoreboardHeaders( GAMEMODE.TeamBased )
	
	if ( GAMEMODE.TeamBased ) then
		ScoreBoard:SetAsBullshitTeam( TEAM_UNASSIGNED )
		ScoreBoard:SetHorizontal( true )	
	end

	ScoreBoard:SetSkin( GAMEMODE.HudSkin )

	self:AddScoreboardAvatar( ScoreBoard )		// 1
	self:AddScoreboardVoice( ScoreBoard )		// 2
	self:AddScoreboardWantsChange( ScoreBoard )	// 3
	self:AddScoreboardName( ScoreBoard )		// 4
	self:AddScoreboardKills( ScoreBoard )		// 5
	self:AddScoreboardDeaths( ScoreBoard )		// 6
	self:AddScoreboardPing( ScoreBoard )		// 7
		
	// Here we sort by these columns (and descending), in this order. You can define up to 4
	ScoreBoard:SetSortColumns( { 5, true, 6, false, 4, false } )
	
end
