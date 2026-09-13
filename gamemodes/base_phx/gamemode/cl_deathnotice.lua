/*
	Start of the death message stuff.
*/

include( 'vgui/vgui_gamenotice.lua' )

local function CreateDeathNotify()

	local x, y = ScrW(), ScrH()

	g_DeathNotify = vgui.Create( "DNotify" )
	
	g_DeathNotify:SetPos( 0, 25 )
	g_DeathNotify:SetSize( x - ( 25 ), y )
	g_DeathNotify:SetAlignment( 9 )
	g_DeathNotify:SetSkin( GAMEMODE.HudSkin )
	g_DeathNotify:SetLife( 4 )
	g_DeathNotify:ParentToHUD()

end

hook.Add( "InitPostEntity", "CreateDeathNotify", CreateDeathNotify )


local function RecvPlayerKilledByPlayer()

	local victim 	= net.ReadEntity();
	local inflictor	= net.ReadString();
	local attacker 	= net.ReadEntity();

	
	if ( !IsValid( attacker ) ) then return end
	if ( !IsValid( victim ) ) then return end
			
	GAMEMODE:AddDeathNotice( attacker:Name(), attacker:Team(), inflictor, victim:Name(), victim:Team() )

end
	
net.Receive( "PlayerKilledByPlayer", RecvPlayerKilledByPlayer )

local function RecvPlayerKilledSelf()

	local victim 	= net.ReadEntity();
	if ( !IsValid( victim ) ) then return end
	GAMEMODE:AddDeathNotice( victim:Name(), victim:Team(), "suicide", victim:Name(), victim:Team() )

end
	
net.Receive( "PlayerKilledSelf", RecvPlayerKilledSelf )


local function RecvPlayerKilled()

	local victim 	= net.ReadEntity();
	if ( !IsValid( victim ) ) then return end
	local inflictor	= net.ReadString();
	local attacker 	= "#" .. net.ReadString();
			
	GAMEMODE:AddDeathNotice( attacker, -1, inflictor, victim:Name(), victim:Team() )

end
	
net.Receive( "PlayerKilled", RecvPlayerKilled )


local function RecvPlayerKilledNPC()

	local victimtype = net.ReadString();
	local victim 	= "#" .. victimtype;
	local inflictor	= net.ReadString();
	local attacker 	= net.ReadEntity();

	--
	-- For some reason the killer isn't known to us, so don't proceed.
	--
	if ( !IsValid( attacker ) ) then return end
			
	GAMEMODE:AddDeathNotice( attacker:Name(), attacker:Team(), inflictor, victim, -1 )
	
	local bIsLocalPlayer = (IsValid(attacker) && attacker == LocalPlayer())
	
	local bIsEnemy = IsEnemyEntityName( victimtype )
	local bIsFriend = IsFriendEntityName( victimtype )
	
	if ( bIsLocalPlayer && bIsEnemy ) then
		achievements.IncBaddies();
	end
	
	if ( bIsLocalPlayer && bIsFriend ) then
		achievements.IncGoodies();
	end
	
	if ( bIsLocalPlayer && (!bIsFriend && !bIsEnemy) ) then
		achievements.IncBystander();
	end

end
	
net.Receive( "PlayerKilledNPC", RecvPlayerKilledNPC )



local function RecvNPCKilledNPC()

	local victim 	= "#" .. net.ReadString();
	local inflictor	= net.ReadString();
	local attacker 	= "#" .. net.ReadString();
			
	GAMEMODE:AddDeathNotice( attacker, -1, inflictor, victim, -1 )

end
	
net.Receive( "NPCKilledNPC", RecvNPCKilledNPC )

/*---------------------------------------------------------
   Name: gamemode:AddDeathNotice( Victim, Weapon, Attacker )
   Desc: Adds an death notice entry
---------------------------------------------------------*/
--function GM:AddDeathNotice( victim, inflictor, attacker )
/*
	hud_deathnotice_time and hud_deathnotice_limit are declared in
	vgui_gamenotice.lua and were read by nothing at all, so notices fell back to
	DNotify's hardcoded 5 second life and nothing capped how many could stack.
	A mass death event - a round wipe, or an admin slaying the server - filled
	the whole screen edge to edge with notices.
*/
local function PushNotice( pnl )

	if ( !IsValid( pnl ) ) then return end

	local cvTime = GetConVar( "hud_deathnotice_time" )
	local life   = cvTime and math.max( 1, cvTime:GetFloat() ) or 6

	g_DeathNotify:AddItem( pnl, life )

	local cvLimit = GetConVar( "hud_deathnotice_limit" )
	local limit   = cvLimit and math.max( 1, cvLimit:GetInt() ) or 5

	// DNotify blanks expired entries to false rather than removing them, so
	// count the live ones and drop the oldest of those.
	local live = {}
	for _, v in ipairs( g_DeathNotify:GetItems() ) do
		if ( IsValid( v ) ) then table.insert( live, v ) end
	end

	for i = 1, #live - limit do
		live[ i ]:Remove()
	end

end

function GM:AddDeathNotice( Attacker, team1, Inflictor, Victim , team2 )
	
	-- for some odd reason, Attacker == nil if inflictor == "suicide" in the base gamemode. wtf and WHEN DID THEY UPDATED THIS???
	if Inflictor == "suicide" then Attacker = Victim; team1 = team2 end
	
	-- Same deal for world/environment kills ("killed by worldspawn"): the base
	-- gamemode's PlayerKilled receiver passes no attacker at all, which used to
	-- reach pnl:AddText(nil) below and error. Show it as a self-death, which is
	-- what dying to fall damage or a trigger_hurt effectively is.
	if Attacker == nil or Attacker == "" then Attacker = Victim; team1 = team2 end
	
	if ( !IsValid( g_DeathNotify ) ) then return end

	local pnl = vgui.Create( "GameNotice", g_DeathNotify )
	local color1
	local color2
	
	
	-- NPC_Color was never defined - table.Copy(nil) returns nil, so non-team
	-- kills silently lost their colour. DeathNoticeDefaultColor is the value
	-- base_phx/gamemode/shared.lua already defines for exactly this case.
	if ( team1 == -1 ) then color1 = table.Copy( GAMEMODE.DeathNoticeDefaultColor )
	else color1 = table.Copy( team.GetColor( team1 ) ) end
	
	if ( team2 == -1 ) then color2 = table.Copy( GAMEMODE.DeathNoticeDefaultColor )
	else color2 = table.Copy( team.GetColor( team2 ) ) end
	
	if Victim == Attacker then
		pnl:AddText( Attacker, color1 )
		pnl:AddText( PHX:GetRandomTranslated("SUICIDEMSG") or "is ded." )
	elseif Victim == "#ph_fake_prop" then
		pnl:AddText( Attacker, Color(255,174,200,255) )
        pnl:AddIcon( "ph_fake_prop" )
		pnl:AddText( PHX:GetRandomTranslated("DECOY_PROP") or "Decoy Prop" )
	else
		pnl:AddText( Attacker, color1)
		pnl:AddIcon( Inflictor )
		pnl:AddText( Victim, color2 )
	end
	
	
	PushNotice( pnl )

end

function GM:AddPlayerAction( ... )
	
	if ( !IsValid( g_DeathNotify ) ) then return end

	local pnl = vgui.Create( "GameNotice", g_DeathNotify )

	for k, v in ipairs({...}) do
		pnl:AddText( v )
	end
	
	PushNotice( pnl )
	
end