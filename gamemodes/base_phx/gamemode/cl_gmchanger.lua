// Fretta's gamemode vote (the VoteScreen panel, the PlayableGamemodes receiver
// and ShowGamemodeChooser & co.) lived here. vgui_vote.lua was never loaded and
// nothing called any of it, so it is gone; PH:X votes through mapvote/.

local ClassChooser = nil 
local cl_classsuicide = CreateConVar( "cl_classsuicide", "0", { FCVAR_ARCHIVE } )

function GM:ShowClassChooser( TEAMID )

	if ( !GAMEMODE.SelectClass ) then return end
	if ( IsValid( ClassChooser ) ) then ClassChooser:Remove() end

	// vgui_Splash is a local of cl_splashscreen.lua, so it was nil here. This is
	// the select-screen panel, the one with SetHeaderText and AddSelectButton.
	ClassChooser = vgui.CreateFromTable( GAMEMODE.VGUISplash )
	ClassChooser:SetHeaderText( "Choose Class" )
	ClassChooser:SetHoverText( "What class do you want to be?" );

	local Classes = team.GetClass( TEAMID )
	for k, v in SortedPairs( Classes ) do
		
		local displayname = v
		local Class = player_class.Get( v )
		if ( Class && Class.DisplayName ) then
			displayname = Class.DisplayName
		end
		
		local description = "Click to spawn as " .. displayname
		
		if( Class and Class.Description ) then
			description = Class.Description
		end
		
		local func = function() if( cl_classsuicide:GetBool() ) then RunConsoleCommand( "kill" ) end RunConsoleCommand( "changeclass", k ) end
		local btn = ClassChooser:AddSelectButton( displayname, func, description )
		btn.m_colBackground = team.GetColor( TEAMID )
		
	end
	
	ClassChooser:AddCancelButton()
	ClassChooser:MakePopup()
	ClassChooser:NoFadeIn()

end
