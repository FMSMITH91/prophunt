local RTV = {}
local MapVote = PHX.MV

-- sv_mapvote.lua loads first and cannot see this file's locals; it resets RTV
-- through here when a vote starts or is cancelled.
MapVote.RTV = RTV

RTV.ChatCommands = {
	"!rtv",
	"/rtv",
	"rtv"
}

RTV.TotalVotes = 0

RTV.Wait = 60 -- The wait time in seconds. This is how long a player has to wait before voting when the map changes. 

RTV._ActualWait = CurTime() + RTV.Wait

-- Read live. This used to snapshot mv_rtvcount at file load, so the cvar's
-- change callback updated MapVote.PHXConfig and RTV carried on using the value
-- it had at boot - changing mv_rtvcount mid-map did nothing at all.
function RTV.GetPlayerCount()
	return MapVote.PHXConfig.RTVPlayerCount or 3
end

function RTV.ChatPrint( mType, ply, bBroadcast, msg, ... )
	
	if !mType or mType == nil then mType = "PRIMARY" end
	if bBroadcast == nil then bBroadcast = false end
	
	if !bBroadcast then
		if ply and ply ~= nil and IsValid(ply) then
			ply:PHXChatInfo( mType, msg, ... )
		end
	else
		-- bBroadcast == true
		for _,v in pairs(player.GetAll()) do
			v:PHXChatInfo( mType, msg, ... )
		end
	end
	
end

-- Humans only: bots never type rtv, so counting them could put the threshold
-- out of reach.
function RTV.ShouldChange()
	return RTV.TotalVotes >= math.Round(#player.GetHumans()*0.66)
end

function RTV.RemoveVote()
	RTV.TotalVotes = math.Clamp( RTV.TotalVotes - 1, 0, math.huge )
end

-- Clears the tally and any countdown. Left at the threshold, every later
-- disconnect or late "rtv" started the vote again, reshuffling the list and
-- wiping everyone's picks.
function RTV.Reset()
	timer.Remove( "PHX.RTV.Start" )
	RTV.Pending = false
	RTV.TotalVotes = 0

	for _,v in pairs(player.GetAll()) do
		v.RTVoted = nil
	end
end

-- Once the game is over its own vote is coming: GM:EndOfGame starts it after
-- GAMEMODE.VotingDelay, and no round starts again. RTV treats that like a vote
-- already on its way.
local function GameOver()
	return GAMEMODE and GAMEMODE.IsEndOfGame
end

function RTV.Start()
	-- A tally that crosses the line after the game ended (a disconnect in the
	-- voting delay) is spent, not started.
	if GameOver() then
		RTV.Reset()
		return
	end

	if RTV.Pending or MapVote.Allow then return end

	RTV.Pending = true
	RTV.ChatPrint( "NOTICE", nil, true, "PHXM_MV_VOTEROCKED_IMMINENT" )
	timer.Create( "PHX.RTV.Start", 4, 1, function()
		RTV.Reset()
		-- The game ended during the countdown. Opening a vote now only had the
		-- end-of-game one replace it seconds later, map list, deadline and
		-- every vote cast with it.
		if GameOver() then return end
		PHX.StartMapVote()
	end )
end


function RTV.AddVote( ply )

	if RTV.CanVote( ply ) then
		RTV.TotalVotes = RTV.TotalVotes + 1
		ply.RTVoted = true
		MsgN( ply:Nick().." has voted to Rock the Vote." )
		
		RTV.ChatPrint( "NOTICE", nil, true, "PHXM_MV_VOTEROCKED_PLY_TOTAL", ply:Nick(), RTV.TotalVotes, math.Round(#player.GetHumans()*0.66) )
		
		if RTV.ShouldChange() then
			RTV.Start()
		end
	end

end

-- PH:X's own hook names. They used to be the upstream MapVote addon's, which
-- replaced its RTV outright; retire the addon's explicitly instead, so a server
-- running both still keeps a single RTV tally.
hook.Remove( "PlayerDisconnected", "Remove RTV" )
hook.Remove( "PlayerSay", "RTV Chat Commands" )

hook.Add( "PlayerDisconnected", "PHX.RTV.Remove", function( ply )

	if ply.RTVoted then
		RTV.RemoveVote()
	end

	timer.Simple( 0.1, function()
		-- Someone leaving a vote that is running, about to run (the end-of-game
		-- one included), or already decided must not start it over.
		if MapVote.Allow or RTV.Pending or MapVote.ChangingMap or GameOver() then return end

		if (#player.GetHumans() < 1 && !MapVote.PHXConfig.ChangeMapNoPlayer) then 
			print("MapVote: There is no player to force change map...")
		else
			if RTV.ShouldChange() then
				if #player.GetHumans() < 1 then
					local time = MapVote.PHXConfig.TimeLimit or 28
					print("MapVote: Server emptied, attempting to force change map and voting random map in "..time.." seconds!")
				end
				RTV.Start()
			end
		end
	end )

end )

function RTV.CanVote( ply )
	local plyCount = #player.GetHumans()
	
	if !IsValid( ply ) then return false, "PHXM_MV_MUST_WAIT" end	-- console/server has no vote.
	
	if RTV._ActualWait >= CurTime() then
		return false, "PHXM_MV_MUST_WAIT"
	end

	-- MapVote.Allow is the real "a vote is running" flag; the old globals here
	-- ("In_Voting" / RTV.ChangingMaps) were never set by anything. Pending
	-- covers RTV's own countdown, when Allow is still false.
	if MapVote.Allow or RTV.Pending then
		return false, "PHXM_MV_VOTEINPROG"
	end

	if MapVote.ChangingMap then
		return false, "PHXM_MV_ALR_IN_VOTE"
	end

	-- The end-of-game vote is on its way: say so, in the words everyone was
	-- just given when the game ended.
	if GameOver() then
		return false, "CHAT_STARTING_MAPVOTE"
	end

	if ply.RTVoted then
		return false, "PHXM_MV_HAS_VOTED"
	end
	if plyCount < RTV.GetPlayerCount() then
        return false, "PHXM_MV_NEED_MORE_PLY"
    end

	return true

end

function RTV.StartVote( ply )

	local can, err = RTV.CanVote(ply)

	if not can then
		RTV.ChatPrint( "WARNING", ply, false, err )
		return
	end

	RTV.AddVote( ply )

end

concommand.Add( "rtv_start", RTV.StartVote )

hook.Add( "PlayerSay", "PHX.RTV.Chat", function( ply, text )

	if table.HasValue( RTV.ChatCommands, string.lower(text) ) then
		RTV.StartVote( ply )
		return ""
	end

end )