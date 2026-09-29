-- PH:X's own names. These used to be the upstream MapVote addon's, and net.Receive
-- keeps only the last handler per name, so with that addon installed PH:X
-- replaced its receivers on both ends and dropped every vote cast in the
-- addon's own vote.
util.AddNetworkString("PHX.MV.Start")
util.AddNetworkString("PHX.MV.Update")
util.AddNetworkString("PHX.MV.Cancel")

local MapVote = PHX.MV

MapVote.Continued = false
local RecentMapsFile = PHX.ConfigPath .. "/mapvote_recentmaps.txt"

/*
    Every broadcast here turns one client packet into one packet per connected
    player. Left unthrottled a modified client turns that into an amplifier and
    can saturate the server's uplink for the whole length of a vote.

    The vote itself was never forgeable - it is keyed by SteamID and the map id
    is validated below - so this is purely about the outbound traffic. Only the
    broadcast is rate-limited: every vote is still recorded, because dropping
    one inside the cooldown lost a quick change of mind whenever jitter or a
    retransmit squeezed two sends closer together than the client spaced them.
    A vote inside the cooldown gets one trailing broadcast instead.

    The deadline lives on the player so it disappears with them, rather than in
    a table that would need pruning on disconnect.
*/
local VOTE_COOLDOWN = 0.4

-- Sends the player's vote as it stands now, so a held-back broadcast carries
-- their latest pick rather than the one that scheduled it.
local function BroadcastVote(ply)
    if !MapVote.Allow or !IsValid(ply) then return end

    local map_id = MapVote.Votes[ply:SteamID()]
    if !map_id then return end

    ply.PHXNextMapVote = CurTime() + VOTE_COOLDOWN

    net.Start("PHX.MV.Update")
        net.WriteUInt(MapVote.UPDATE_VOTE, 3)
        net.WriteEntity(ply)
        net.WriteUInt(map_id, 32)
    net.Broadcast()
end

net.Receive("PHX.MV.Update", function(len, ply)
    if !MapVote.Allow or !IsValid(ply) then return end
    if net.ReadUInt(3) != MapVote.UPDATE_VOTE then return end

    local map_id = net.ReadUInt(32)
    if !MapVote.CurrentMaps[map_id] then return end

    MapVote.Votes[ply:SteamID()] = map_id

    local wait = (ply.PHXNextMapVote or 0) - CurTime()

    if wait <= 0 then
        BroadcastVote(ply)
    else
        -- Re-creating the timer replaces it, so this stays one broadcast per
        -- cooldown however fast the votes come in.
        timer.Create("PHX.MV.Broadcast" .. ply:UserID(), wait, 1, function() BroadcastVote(ply) end)
    end
end)

local RecentMaps = {}
if file.Exists( RecentMapsFile, "DATA" ) then
    RecentMaps = util.JSONToTable(file.Read( RecentMapsFile, "DATA" ) or "") or {}
else
    RecentMaps = {}
end

-- mv_map_prefix is typed by hand, and the F1 menu's own example wraps it in
-- single quotes, which the console keeps. Trim spaces and quotes off each entry
-- and drop empty ones: "phx_, ph_" used to lose every ph_ map, "'phx_,ph_'" lost
-- both, and an empty value matched every map on the server.
local function ParsePrefixes(s)
	local out = {}

	for _, p in ipairs(string.Explode(",", (s or ""):lower())) do
		p = p:match("^[%s\"']*(.-)[%s\"']*$")
		if p != "" then out[#out + 1] = p end
	end

	if #out == 0 then out = table.Copy(PHX.MVConfigDefault.MapPrefixes) end

	return out
end

-- Literal prefix match. These were Lua patterns, so a `-`, `.` or `[` in
-- mv_map_prefix matched the wrong maps or raised inside the vote timer.
local function MatchesPrefix(lmap, prefixes)
	for _, v in pairs(prefixes) do
		if isstring(v) and lmap:sub(1, #v) == v:lower() then return true end
	end

	return false
end

if ConVarExists("mv_maplimit") then
	PHX:VerboseMsg("[MapVote] Loading ConVars...")
	MapVote.PHXConfig = {
		MapLimit 		= GetConVar("mv_maplimit"):GetInt(),
		TimeLimit 		= GetConVar("mv_timelimit"):GetInt(),
		AllowCurrentMap = GetConVar("mv_allowcurmap"):GetBool(),
		ChangeMapNoPlayer = GetConVar("mv_change_when_no_player"):GetBool(),
		UseULX 			= GetConVar("mv_use_ulx_votemaps"):GetBool(),
		EnableCooldown 	= GetConVar("mv_cooldown"):GetBool(),
		MapsBeforeRevote = GetConVar("mv_mapbeforerevote"):GetInt(), --omfg it has been like, spent 8 years to realise, it was "GetBool", NOT "GetInt", damn it...
		RTVPlayerCount 	= GetConVar("mv_rtvcount"):GetInt(),
		MapPrefixes 	= ParsePrefixes(GetConVar("mv_map_prefix"):GetString())
	}
else
	ErrorNoHaltWithStack( "[PH: X MapVote] Warning: ConVar `mv_maplimit` DOES NOT exist! Returning to default Values!!" )
	MapVote.PHXConfig = table.Copy( PHX.MVConfigDefault )
end

local conv = {
	["mv_maplimit"]		= function(cvar,old,new)
		if new != "" then
			MapVote.PHXConfig.MapLimit = tonumber(new)
		end
	end,
	["mv_timelimit"]	= function(cvar,old,new)
		if new != "" then
			MapVote.PHXConfig.TimeLimit = tonumber(new)
		end
	end,
	["mv_allowcurmap"]	= function(cvar,old,new)
		if new != "" then
			MapVote.PHXConfig.AllowCurrentMap = tobool(new)
		end
	end,
	["mv_change_when_no_player"] = function(cvar,old,new)
		if new != "" then
			MapVote.PHXConfig.ChangeMapNoPlayer = tobool(new)
		end
	end,
	["mv_use_ulx_votemaps"] = function(cvar,old,new)
		if new != "" then
			MapVote.PHXConfig.UseULX = tobool(new)
		end
	end,
	["mv_cooldown"]		= function(cvar,old,new)
		if new != "" then
			MapVote.PHXConfig.EnableCooldown = tobool(new)
		end
	end,
	["mv_mapbeforerevote"]	= function(cvar,old,new)
		if new != "" then
			MapVote.PHXConfig.MapsBeforeRevote = tonumber(new) -- was "tobool", how the fuck that I can be so this less careful
		end
	end,
	["mv_rtvcount"]		= function(cvar,old,new)
		if new != "" then
			MapVote.PHXConfig.RTVPlayerCount = tonumber(new)
		end
	end,
	["mv_map_prefix"]	= function(cvar,old,new)
		MapVote.PHXConfig.MapPrefixes = ParsePrefixes(new)
	end
}

-- Precheck when the convar is changed
for cvar,func in pairs(conv) do
	PHX:VerboseMsg("[MapVote] Adding ConVar Callbacks for: "..cvar)
	cvars.AddChangeCallback(cvar, func)
end

function PHX.CoolDownDoStuff()
    local cooldownnum = MapVote.PHXConfig.MapsBeforeRevote or 3

	if #RecentMaps > cooldownnum then
		-- Remove the rest of table to prevent map being added overgrowingly to cooldown
		-- This occurs when the convar changes in active round.
		for i=cooldownnum+1,#RecentMaps,1 do
			table.remove(RecentMaps) --last arg = #RecentMaps
		end
	end
	
    if #RecentMaps == cooldownnum then
        table.remove(RecentMaps) --last arg = #RecentMaps
    end

    local curmap = game.GetMap():lower()..".bsp"

    if not table.HasValue(RecentMaps, curmap) then
        table.insert(RecentMaps, 1, curmap)
    end

    file.Write(RecentMapsFile, util.TableToJSON(RecentMaps))
end

function MapVote.GetFromULX()

	if (ulx) then
		if (ulx.votemaps) then return ulx.votemaps end
	end
	
	print("[MapVote] WARNING: ULX is not installed! Couldn't get any list from 'votemap' data!")
	return {}

	--[[ if (!ulx or ulx == nil or !ulx.votemaps or ulx.votemaps == nil) then
		print("[!PHX] Warning: ULX is not installed, can't get any votemap information!")
		return {}
	end

	return ulx.votemaps ]]
end

-- Original: MapVote.Start
-- force skips the ph_enable_mapvote check. Only PHX.StartMapVote passes it, as
-- the end-of-game fallback when the vote is off and nothing else will change
-- the map.
function MapVote.PHXStart(length, current, limit, prefix, force)

	if (not force and not PHX:GetCVar( "ph_enable_mapvote" )) then
		MsgAll("PH:X MapVote is disabled!\n")
		for _,v in pairs(player.GetAll()) do
			v:ChatPrint("Warning: MapVote is disabled.")
		end
		return
	end

    current 	= current or MapVote.PHXConfig.AllowCurrentMap or false
    length 		= length or MapVote.PHXConfig.TimeLimit or 28
    limit 		= limit or MapVote.PHXConfig.MapLimit or 24
    -- The old fallback read a pattern from gamemode.txt ("^ph_|^phx_"), which
    -- Lua patterns cannot express, so it matched nothing.
    prefix 		= prefix or MapVote.PHXConfig.MapPrefixes or PHX.MVConfigDefault.MapPrefixes
    
	-- `x or (!x and true)` is true for every possible x, so mv_cooldown 0 could
	-- never actually turn the recent-map cooldown off. Read the setting, and
	-- only default to on when it is genuinely absent.
	local cooldown 	= MapVote.PHXConfig.EnableCooldown
	if cooldown == nil then cooldown = true end

    if type(prefix) ~= "table" then
        prefix = {prefix}
    end
    
	-- Only when it is used: GetFromULX warns on every call without ULX.
	local ulxmap = MapVote.PHXConfig.UseULX and MapVote.GetFromULX()
	local maps = {}
	
	if istable(ulxmap) and !table.IsEmpty(ulxmap) then
		for _,map in pairs(ulxmap) do table.insert(maps, map..".bsp"); end
	else
		maps = file.Find("maps/*.bsp", "GAME")
	end
    
    local curmap = game.GetMap():lower()..".bsp"

    local function Collect(skipCurrent, skipRecent)
        local found = {}

        for _, map in RandomPairs(maps) do
            local lmap = map:lower()

            if not (skipCurrent and lmap == curmap) and not (skipRecent and table.HasValue(RecentMaps, lmap)) and MatchesPrefix(lmap, prefix) then
                found[#found + 1] = map:sub(1, -5)
                if(limit and #found >= limit) then break end
            end
        end

        return found
    end

    -- An empty vote has no winner and never changes map, which at the end of
    -- the game leaves every player frozen. With the default cooldown that is
    -- any pool of three maps or fewer, so relax the filters until something is
    -- left, and reload the current map as the last resort.
    local vote_maps = Collect(not current, cooldown)
    if #vote_maps == 0 and cooldown then vote_maps = Collect(not current, false) end
    if #vote_maps == 0 and not current then vote_maps = Collect(false, false) end
    if #vote_maps == 0 then
        ErrorNoHalt("[PH:X MapVote] No map matches mv_map_prefix or the vote map list; the vote will reload the current map.\n")
        vote_maps = { game.GetMap() }
    end
    
    net.Start("PHX.MV.Start")
        net.WriteUInt(#vote_maps, 32)
        
        for i = 1, #vote_maps do
            net.WriteString(vote_maps[i])
        end
        
        net.WriteUInt(length, 32)
    net.Broadcast()
    
    MapVote.Allow = true
    MapVote.ChangingMap = nil
    MapVote.CurrentMaps = vote_maps
    MapVote.Votes = {}

    -- A vote started in the last one's 4 s grace replaces its result, so that
    -- changelevel must not fire in the middle of this one.
    timer.Remove("PHX.MV.Change")

    -- A vote is running now, however it was started, so any RTV countdown or
    -- tally is spent.
    if MapVote.RTV then MapVote.RTV.Reset() end
    
    timer.Create("PHX.MV.Vote", length, 1, function()
        MapVote.Allow = false
        local map_results = {}
        
        for k, v in pairs(MapVote.Votes) do
            if(not map_results[v]) then
                map_results[v] = 0
            end
            
            for k2, v2 in pairs(player.GetAll()) do
                if(v2:SteamID() == k) then
                    if(MapVote.HasExtraVotePower(v2)) then
                        map_results[v] = map_results[v] + 2
                    else
                        map_results[v] = map_results[v] + 1
                    end
                end
            end
            
        end
        
        PHX.CoolDownDoStuff()

        local winner = table.GetWinningKey(map_results) or 1
        
        net.Start("PHX.MV.Update")
            net.WriteUInt(MapVote.UPDATE_WIN, 3)
            
            net.WriteUInt(winner, 32)
        net.Broadcast()
        
        local map = MapVote.CurrentMaps[winner]
        if !map then
            ErrorNoHalt("[PH:X MapVote] No winning map to change to - the vote list was empty!\n")
            return
        end

        -- Read by the round controller, so no round starts under the result
        -- while changelevel is pending.
        MapVote.ChangingMap = map

        timer.Create("PHX.MV.Change", 4, 1, function()
            hook.Run("MapVoteChange", map)
            RunConsoleCommand("changelevel", map)
        end)
    end)
end

-- There was a hook.Add( "Shutdown", ... ) here that deleted RecentMapsFile.
-- Two things were wrong with it. The event is spelled "ShutDown", so it never
-- fired at all; and GM:ShutDown runs whenever the Lua state goes away - "for
-- example on map change" - which is exactly the transition this file exists to
-- survive. Correcting the spelling would therefore have wiped the cooldown on
-- every changelevel and silently disabled the feature. PHX.CoolDownDoStuff
-- already trims the list to mv_mapbeforerevote entries, so it does not grow.

-- Original: MapVote.Cancel()
-- ply is whoever asked; the server console (NULL) or a Lua caller (nil) is
-- answered in the console. Returns false when the cancel is refused, so a
-- caller does not report one that never happened.
function MapVote.PHXCancel(ply)

	-- The end-of-game vote is the only way off the map: no round starts once
	-- the game is over, so cancelling it left every player frozen until someone
	-- changed map by hand. It carries on; a mid-game vote can still be stopped.
	if (GAMEMODE and GAMEMODE.IsEndOfGame) then
		if IsValid(ply) then
			ply:PHXChatInfo("WARNING", "PHXM_MV_ENDGAME_NOCANCEL")
		else
			print("[MapVote] The game has ended: this map vote picks the next map and cannot be cancelled.")
		end
		return false
	end

	-- RTV's 4 s countdown runs while Allow is still false, so it is stopped
	-- before the checks below. Its tally goes too: left at the threshold, the
	-- next disconnect started the cancelled vote all over again.
	if MapVote.RTV then MapVote.RTV.Reset() end

	-- With the setting off a built-in vote can still be running: it is the
	-- end-of-game fallback when nothing handles PH_OverrideMapVote.
	if (not PHX:GetCVar( "ph_enable_mapvote" )) and not MapVote.Allow then
		MsgAll("PH:X MapVote is disabled.\n")
		return
	end

    if MapVote.Allow then
        MapVote.Allow = false
        MapVote.ChangingMap = nil

        net.Start("PHX.MV.Cancel")
        net.Broadcast()

        timer.Remove("PHX.MV.Vote")
    end
end

-- The shipped defaults point back into PH:X. ph_custom_mv_func
-- "PHX.StartMapVote()" re-entered this function through RunString until the
-- stack gave out, and ph_custom_mv_concmd "mv_start" refuses while custom mode
-- is on. Archived configs keep those values, so they - and blanks - mean "use
-- the built-in vote".
local SELF_FUNCS = { [""] = true, ["PHX.StartMapVote()"] = true, ["MapVote.PHXStart()"] = true }
local SELF_CMDS = { [""] = true, ["mv_start"] = true }
local inCustomFunc = false

function PHX.StartMapVote()
	
	if PHX:GetCVar( "ph_use_custom_mapvote_cmd" ) then	-- Overrides the function mode below.
		local c = string.Trim( tostring( PHX:GetCVar( "ph_custom_mv_concmd" ) or "" ) )
		if !SELF_CMDS[ string.Explode( " ", c )[1] ] then
			game.ConsoleCommand( c .. "\n" )
			return
		end
	end

	-- inCustomFunc catches any other way back in, and falls through to the
	-- built-in vote rather than recursing.
	if PHX:GetCVar( "ph_use_custom_mapvote" ) and !inCustomFunc then
		local f = string.Trim( tostring( PHX:GetCVar( "ph_custom_mv_func" ) or "" ) )
		if !SELF_FUNCS[ f ] then
			inCustomFunc = true
			local ok, err = pcall( RunString, f, "MapVote_CVAR", false )
			inCustomFunc = false

			if ok and !err then return end
			ErrorNoHalt( "[PH:X MapVote] ph_custom_mv_func failed, using the built-in vote: " .. tostring( err ) .. "\n" )
		end
	end
	
	if (not PHX:GetCVar( "ph_enable_mapvote" )) then
		local result = hook.Call( "PH_OverrideMapVote", nil )
		local listeners = hook.GetTable()[ "PH_OverrideMapVote" ]
        if (result) then
		    MsgAll("PH:X MapVote is disabled. Calling Map Vote Overrides Hook... \n")
		    return
        elseif (listeners and next(listeners) ~= nil) then
            -- hook.Call ran it anyway, so its vote has started; a second,
            -- built-in one would race it for the changelevel.
            MsgAll("WARNING: [PH_OverrideMapVote] hook did not return true; assuming it started a vote. (Did you forget to `return true`?)\n")
            return
        end

        -- Nothing else will change the map, and at the end of the game that
        -- leaves every player frozen. PHXStart refuses while the setting is
        -- off, so force it there. Mid-game (RTV, the server emptying) the
        -- setting still means no vote.
        if (GAMEMODE and GAMEMODE.IsEndOfGame) then
            MsgAll("WARNING: Detected no external Map Votes Call from [PH_OverrideMapVote] hook, Falling back to the built-in vote!\n")
            MapVote.PHXStart(nil, nil, nil, nil, true)
            return
        end
	end
	
	MapVote.PHXStart()

end
