local netstr = {
	"pcr.ClientRequestPropData",
	"pcr.PropListData",
	"pcr.EditorCustomData",
	"pcr.ForceCloseMenu",
	"pcr.SetMetheProp"
}

for _,v in pairs(netstr) do
	util.AddNetworkString(v)
end

PCR._STORED_PROPS	= {}
PCR._INIT_STORED	= false

PCR.propDatajson 	= ""
PCR.propDataSize 	= 0
PCR.customPropJson 	= ""
PCR.customPropSize 	= 0

-- GMod caps a net message at about 64KB, so a list compressed past that would never
-- arrive. Refuse it with an error the server owner can act on. Sends to target, or
-- to everyone without one; returns whether it was sent.
local MAX_NET_DATA = 60000
function PCR:SendPropNetData( netName, data, size, target )
	if size > MAX_NET_DATA then
		ErrorNoHalt("[Prop Menu] Not sending " .. netName .. ": it is " .. size .. " bytes compressed, over the " .. MAX_NET_DATA .. " byte net message limit. Shorten the custom prop list, or cap the map props with pcr_limit_enable.\n")
		return false
	end
	
	net.Start(netName)
	net.WriteUInt(size, 32)
	net.WriteData(data, size)
	if target then net.Send(target) else net.Broadcast() end
	return true
end

local function SendPropData( ply )

	if !ply.pcrHasPropData then		
        
		PCR:SendPropNetData("pcr.PropListData", PCR.propDatajson, PCR.propDataSize, ply)
		
		if !table.IsEmpty(PCR.CustomProp) then
			PCR:SendPropNetData("pcr.EditorCustomData", PCR.customPropJson, PCR.customPropSize, ply)
		end

		ply.pcrHasPropData = true
	end
    
end

function PCR:ReadBannedProps()
	-- Empty the table first. Entries are stored lowercase, as the scan and the pick check compare lowercased paths.
	self.BannedProp = {}
	local path = PHX.ConfigPath .. "/prop_model_bans"
	
	if !file.Exists(path,"DATA") then
		PHX:VerboseMsg("[Prop Menu] !!WARNING : Prop Hunt: X's Prop Ban Data does not exist. Did you forgot to install Prop Hunt: X? Creating the folder anyway...")
		file.CreateDir(path)
	end
	
	if file.Exists(path.."/model_bans.txt","DATA") then
		PHX:VerboseMsg("[Prop Menu] Reading Prop Hunt: X's Prop Ban Data...")	-- PHX.BANNED_PROP_MODELS
		local read = util.JSONToTable(file.Read(path.."/model_bans.txt") or "") or {}
		for _,mdl in pairs(read) do
			table.insert(self.BannedProp, string.lower( mdl ))
		end
	else
		PHX:VerboseMsg("[Prop Menu] !!WARNING: Prop Hunt: X's Prop Ban Data does not exists, Ignoring..!")
	end
	
	if file.Exists(path.."/pcr_bans.txt","DATA") then
		PHX:VerboseMsg("[Prop Menu] Reading Prop Menu's additional ban list...")
		local read = util.JSONToTable(file.Read(path.."/pcr_bans.txt") or "") or {}
		for _,mdl in pairs(read) do
			table.insert(self.BannedProp, string.lower( mdl ))
		end
	else
		PHX:VerboseMsg("[Prop Menu] !!WARNING: Prop Menu's additional ban list does not exists, Creating new one...")
		
		local proplist = { "models/player.mdl", "models/player/kleiner.mdl" }
		local json = util.TableToJSON(proplist,true)
		file.Write(path.."/pcr_bans.txt", json)
		for _,mdl in pairs(proplist) do
			table.insert(self.BannedProp, string.lower( mdl ))
		end
		
		PHX:VerboseMsg("[Prop Menu] Prop Menu additional ban list has successfully created.")
	end
end

function PCR:CheckBBox(entity)
	local min,max = entity:GetCollisionBounds()
	if math.Round(max.x) >= PHX:QCVar( "pcr_bbox_max_width" ) or
		math.Round(max.y) >= PHX:QCVar( "pcr_bbox_max_width" ) or 
		math.Round(max.z) >= PHX:QCVar( "pcr_bbox_max_height" ) then 
			return true 
	end
	return false
end

function PCR:GetCustomProps()
	-- Empty Table first
	self.CustomProp = {}
	local path = PHX.ConfigPath .. "/prop_chooser_custom"
	
	if !file.Exists(path,"DATA") then
		PHX:VerboseMsg("[Prop Menu] Creating default Prop Menu's Prop Data folder...")
		file.CreateDir(path)
		PHX:VerboseMsg("[Prop Menu] Successfully created: "..path.."!")
	end
	
	if file.Exists(path.."/models.txt","DATA") then
		local read = util.JSONToTable(file.Read(path.."/models.txt") or "") or {}
		for _,mdl in pairs(read) do
			table.insert(self.CustomProp, string.lower( mdl ))
		end
	else
		PHX:VerboseMsg("[Prop Menu] Creating default Prop Menu's Custom Prop data file...")
		
		local proplist = { "models/balloons/balloon_star.mdl", "models/balloons/balloon_dog.mdl", "models/balloons/balloon_classicheart.mdl" }
		local json = util.TableToJSON(proplist,true)
		file.Write(path.."/models.txt", json)
		
		for _,mdl in pairs(proplist) do
			table.insert(self.CustomProp, mdl)
		end
		
		PHX:VerboseMsg("[Prop Menu] Prop Menu's Custom Prop Data successfully created.")
	end
end

function PCR:PopulateProp( bUseModCustomProp )
	if bUseModCustomProp == nil then bUseModCustomProp = false end
	self.PropList = {}
	
	-- We have stored props. Use that instead, otherwise, scan all map.
	
	if self._INIT_STORED then
	
		PHX:VerboseMsg("[Prop Menu:Debug] PopulateProp was called: Using from Stored Reference.")
		self.PropList = table.Copy( self._STORED_PROPS )
		
	else
	
		PHX:VerboseMsg("[Prop Menu:Debug] PopulateProp was called from Init Hook. Populating props...")
	
		self:ReadBannedProps()

		local count = 0
		for _,prop in RandomPairs(ents.FindByClass("prop_physics*")) do			
			if (!IsValid(prop:GetPhysicsObject())) then
				PHX:VerboseMsg("[Prop Menu] Warning: Prop "..prop:GetModel().. " @Index #"..prop:EntIndex().." has no physics. Ignoring!")
				continue
			end
			-- update: Do not include Forbidden models that can cause server crashes or exploits
			if PHX.PROHIBITTED_MDLS[ string.lower(prop:GetModel()) ] then continue end
			if table.HasValue(self.PropList, string.lower(prop:GetModel())) then continue end
			if (PHX:QCVar( "pcr_enable_prop_ban" ) && table.HasValue(self.BannedProp, string.lower(prop:GetModel()))) then
				PHX:VerboseMsg("[Prop Menu] Banning prop of "..prop:GetModel().." @Index #"..prop:EntIndex().."!")
				continue
			end
			if (PHX:QCVar( "pcr_enable_bbox_limit" ) && self:CheckBBox(prop)) then
				PHX:VerboseMsg("[Prop Menu] Found prop "..prop:GetModel().." @Index #"..prop:EntIndex().." that Exceeds the OBB settings, Ignoring!")
				continue
			end
			if (PHX:QCVar( "pcr_limit_enable" ) && count == PHX:QCVar( "pcr_max_prop_list" )) then break end
			
			count = count + 1
			table.insert(self.PropList, string.lower(prop:GetModel()))
		end
		PHX:VerboseMsg("[Prop Menu] Total by "..count.." props was added.")
		
		-- Store the map scanned prop list as reference. 
		-- Stored after InitPostEntity calls or any initialization hooks.
		if !self._INIT_STORED then
			self._STORED_PROPS = table.Copy( self.PropList )
			self._INIT_STORED = true
		end
		
	end

	-- Add Custom Props
	if PHX:QCVar( "pcr_allow_custom" ) then
		PHX:VerboseMsg("[Prop Menu] Adding custom props...")
		if !bUseModCustomProp then self:GetCustomProps() end
		for _,prop in pairs(self.CustomProp) do
			-- Custom props get the same prohibited-model filter as map props.
			if PHX.PROHIBITTED_MDLS[ string.lower(prop) ] then
				PHX:VerboseMsg("[Prop Menu] Custom prop "..prop.." is a prohibited model, Ignoring!")
			else
				table.insert(self.PropList, prop)
			end
		end
	end
	
	-- Add to Compressed Caches for Net utilities
	local json = util.TableToJSON(self.PropList)
	self.propDatajson = util.Compress(json)
	self.propDataSize = self.propDatajson:len()
	
	if !table.IsEmpty(self.CustomProp) then
		local jsc = util.TableToJSON(self.CustomProp)
		self.customPropJson = util.Compress(jsc)
		self.customPropSize = self.customPropJson:len()
	end
	
end

hook.Add("InitPostEntity", "PCR.PopulateProps", function()
	PCR:PopulateProp()
end)

hook.Add("PlayerInitialSpawn","pcr.InitPropRequestData",function(ply)
	ply.pcrHasPropData = false
	-- Full allowance, not 0: the per-round reset (PostCleanupMap) has already run for someone joining mid-round.
	ply:ResetUsage()
end)

net.Receive("pcr.ClientRequestPropData", function(len, ply)
    -- The sender may disconnect before the timer runs; SendPropData writes to the player.
    if ply:IsListenServerHost() then
        -- Host don't retreive the prop data at first spawn, for some reason. We might have to DELAY it.
        timer.Simple(2, function() if IsValid( ply ) then SendPropData( ply ) end end)
    else
        timer.Simple(0, function() -- send the data on next frame instead, for safety.
            if IsValid( ply ) then SendPropData( ply ) end -- Dedicated servers should be no problem. Listen Servers however, don't.
        end)
    end
end)

hook.Add("PostCleanupMap","PCR.ResetUseLimit",function()
	for _,ply in pairs(player.GetAll()) do
		ply:ResetUsage()
	end
end)

local function PCRForceClose(ply)
	net.Start("pcr.ForceCloseMenu")
	net.Send(ply)
end
hook.Add("PostPlayerDeath", "PCR.ForceCloseMenu", function(ply) PCRForceClose(ply) end)
hook.Add("PH_RoundEnd", "PCR.ForceCloseMenu", function()
	for _,v in pairs(player.GetAll()) do
		PCRForceClose(v)
	end
end)
hook.Add("OnReloaded", "PCR.OnReload", function()
	-- empty reference props.
	PCR._STORED_PROPS = {}
	PCR._INIT_STORED = false
	
	-- force re-add them. You might want to do a map restart instead.
	PCR:PopulateProp()
	
	for _,ply in pairs(player.GetAll()) do
		ply.pcrHasPropData = false
		ply:ResetUsage()
		timer.Simple(1, function()
			if IsValid( ply ) then SendPropData( ply ) end
		end)
	end
end)

PCR.NotifyPlayer = function( ply , message , kind, ... )
	ply:PHXNotify( message, kind, 5, true, ... )
	ply:SendLua("surface.PlaySound('garrysmod/save_load".. math.random(1,4) ..".wav')")
end

local function PlayerDelayCheck(ply)
	if !ply.waitTime then ply.waitTime = 0 end

	local lastUsedTime = ply:GetNWFloat("pcr.LastUsedTime")
	local delayedTime = lastUsedTime + PHX:QCVar( "pcr_delay_use" )
	local currentTime = CurTime()
	
	ply.waitTime = delayedTime - currentTime
	if ply.waitTime < 0 then
		ply.waitTime = 0
	end
	
	return delayedTime > currentTime; 
end

-- Warn a player asking for a model the menu never offered, and kick on the fourth try.
local function WarnInvalidModel( ply, mdl )
	if !ply.warnInvalidModel then
		ply.warnInvalidModel = 0
	end
	
	print("[Prop Menu] !!WARNING: User ".. ply:Nick() .." ("..ply:SteamID()..") is trying to use Invalid Prop Model : " .. mdl .. ", which DOES NOT EXIST in the map!")
	
	if ( PHX:QCVar( "pcr_kick_invalid" ) ) then
		ply.warnInvalidModel = ply.warnInvalidModel + 1
		ply:PHXChatInfo("ERROR", "PCR_NOT_EXIST_COUNT", tostring(ply.warnInvalidModel))
		if ply.warnInvalidModel >= 4 then -- the message counts to "4 / 4", so kick on the 4th.
			ply:Kick("[PHX Prop Menu] Kicked for Reason: trying to access invalid prop!")
		end
	else
		ply:PHXChatInfo("ERROR", "PCR_NOT_EXIST")
	end
end

-- The menu is on, this player may use it, and the model is one it offers and the server has.
local function CanRequestModel( ply, mdl )
	-- The client's pcr_enable check only hides the menu; a crafted client can still send this.
	if !PHX:QCVar( "pcr_enable" ) then return false end
	
	if PHX:GetCVar( "pcr_only_allow_certain_groups" ) and !PCR:CheckUserGroup( ply ) then
		ply:PHXChatInfo("ERROR", "PCR_ONLY_GROUP")
		return false
	end
	
	-- if so, Warn / Kick player to maximum thresold if they are trying to access invalid model.
	if (not table.HasValue(PCR.PropList, mdl)) then
		WarnInvalidModel( ply, mdl )
		return false
	end
    
    if (not file.Exists(mdl, "GAME")) then
        ply:PHXChatInfo("ERROR", "PCR_MODEL_DONT_EXISTS")
        ply:PrintMessage(HUD_PRINTCONSOLE, "[Prop Menu] Warning: Trying to access model of: " .. mdl ..", is the server owner forgot to enable their game content?")
        print("[Prop Menu] Warning: ".. ply:Nick() .. " is trying to access model: ".. mdl ..", did you forgot to enable your game content?")
        return false
    end
	
	return true
end

-- The player can change right now, and the model is not on the Prop Menu's own ban list.
local function CanChangeNow( ply, mdl )
	-- Only a living prop in a round can change. A dead prop has no ph_prop: PlayerExchangeProp
	-- errors on it after the temporary prop is created, leaking that prop.
	if !GAMEMODE:InRound() or ply:Team() ~= TEAM_PROPS or !ply:Alive() or !IsValid( ply.ph_prop ) then return false end
	
	-- Make sure that the player is On Ground and Not crouching.
	if PHX:GetCVar( "ph_prop_must_standing" ) and ( ply:Crouching() or (not ply:IsOnGround()) ) then
		ply:PHXChatInfo("NOTICE", "PCR_STAY_ON_GROUND")
		return false
	end
	
	-- Make sure player is not accessing banned prop
	if ( PHX:QCVar( "pcr_enable_prop_ban" ) and table.HasValue(PCR.BannedProp, string.lower(mdl)) ) then
		ply:PHXChatInfo("WARNING", "PCR_PROPBANNED_BYPCR")
		return false
	end
	
	return true
end

-- Temporarily spawn a hidden prop of the model under the player, to copy the disguise from.
local function SpawnTempProp( ply, mdl )
	local pos = ply:GetPos()
	local ent = ents.Create("prop_physics")
	if !IsValid( ent ) then return end
	ent:SetPos( Vector( pos.x, pos.y, pos.z-512 ) )
	ent:SetAngles(Angle(0,0,0))
	ent:SetKeyValue("spawnflags","654")
	ent:SetNoDraw(true)
	ent:SetModel(mdl)
	
	ent:Spawn()
	return ent
end

-- PlayerExchangeProp can quietly do nothing (e.g. the prop is already worn),
-- so only spend and announce a use when the disguise actually changed.
local function ExchangeAndSpend( ply, ent, usage )
	local oldMdl, oldSkin = ply.ph_prop:GetModel(), ply.ph_prop:GetSkin()
	GAMEMODE:PlayerExchangeProp(ply,ent)
	if IsValid( ply.ph_prop ) and ( ply.ph_prop:GetModel() ~= oldMdl or ply.ph_prop:GetSkin() ~= oldSkin ) then
		if usage <= -1 then
			PCR.NotifyPlayer( ply, "PCR_USAGE_UNLIMIT", "UNDO" )
		elseif usage > 0 then
			ply:UsageSubstractCount()
			PCR.NotifyPlayer( ply, "PCR_USAGE_COUNT", "GENERIC", usage - 1 )
		end
	end
end

-- Put the player in the temporary prop's disguise, unless there is no room or it is banned.
local function ApplyTempProp( ply, ent )
	local usage = ply:CheckUsage()
	local hmx,hmy,hz = ent:GetPropSize()
	if ( PHX:QCVar( "pcr_use_room_check" ) and (not ply:CheckHull(hmx,hmy,hz)) ) then
		if usage > 0 or usage == -1 then
			ply:PHXChatInfo("NOTICE", "PCR_NOROOM")
		end
	-- The ban list is lowercase, and GetModel keeps the spelling the model was first loaded with.
	elseif PHX:GetCVar( "ph_banned_models" ) and table.HasValue( PHX.BANNED_PROP_MODELS, string.lower(ent:GetModel()) ) then
		ply:PHXChatInfo("WARNING", "PCR_PROPBANNED")
	else
		ExchangeAndSpend( ply, ent, usage )
	end
end

net.Receive("pcr.SetMetheProp",function(len,ply)
	local mdl = net.ReadString()
	
	if !CanRequestModel( ply, mdl ) or !CanChangeNow( ply, mdl ) then return end
	
	if ( IsValid(ply) and (not PlayerDelayCheck(ply)) ) then
	
		if ply:CheckUsage() == 0 then
			ply:PHXChatInfo("GOOD", "PCR_REACHED_LIMIT")
			return
		end
		
		-- Stamp first: this delay is the only throttle on creating the temporary prop below.
		ply:SetNWFloat( "pcr.LastUsedTime", CurTime() )
	
		local ent = SpawnTempProp( ply, mdl )
		if !IsValid( ent ) then return end
		ApplyTempProp( ply, ent )
		ent:Remove()
		
	else
	
		ply:PHXChatInfo( "NOTICE", "PCR_PLS_WAIT", math.Round(ply.waitTime) )
		
	end
end)