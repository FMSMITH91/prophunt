local netstr = {
	"PCR.RequestServerGameContents",	-- Admin Request Game Contents
	"PCR.TheServerGameContents",		-- Granted Request Game Contents
	
	"PCR.DoneEditing",					-- Notify an Admin Done Editing
	
	"PCR.EditedCustomPropData",			-- Admin Sent Edited PropData
	
	"phxpm.fb_RequestOpen_w",			-- Admin Request Open
	"phxpm.fb_openPM_Editor",			-- Granted Request to open the window.
	"phxpm.fb_UpdateConfirmed_Editor"	-- Confirm after Sending the Data to Server
}

for _,v in pairs(netstr) do
	util.AddNetworkString(v)
end

local function CheckUser(ply)
	if ( ply:PHXIsStaff() ) then return true end
	return false
end

-- The lock remembers its holder: it is freed when they leave, they can re-request it if their
-- window never opened, and it lapses after EDIT_LOCK_TIMEOUT seconds so nobody holds it all map.
local EDIT_LOCK_TIMEOUT = 600
local editor, editSince = nil, 0

local function IsEditLocked( ply )
	return IsValid( editor ) and editor ~= ply and CurTime() - editSince < EDIT_LOCK_TIMEOUT
end

hook.Add("PlayerDisconnected", "PCR.ReleaseEditLock", function(ply)
	if ply == editor then editor = nil end
end)

-- verify user request, ONLY ONE INSTANCE IS DONE!
net.Receive("phxpm.fb_RequestOpen_w", function(len, ply)
	if CheckUser(ply) then
	  if PHX:QCVar( "pcr_allow_custom" ) then
		if !IsEditLocked( ply ) then
			net.Start("phxpm.fb_openPM_Editor")
				net.WriteTable({ global = "PCR", sub = "CustomProp" })
			net.Send(ply)
			editor, editSince = ply, CurTime()
		else
			ply:PHXChatInfo("WARNING", "PCR_EDT_IN_USE")
		end
	  else
		ply:PHXChatInfo("ERROR", "PCR_EDT_ERROR_DISABLED")
	  end
	else
		ply:PHXChatInfo("WARNING", "PCR_EDT_NO_RIGHTS")
	end
end)

local function getServerGames()
	local tab = {}
	local games = engine.GetGames()
	
	for _,g in pairs(games) do
		if g.mounted then
			tab[g.folder] = g.title
		end
	end

	return tab
end

local gameData,gameSize
hook.Add("Initialize", "pcr.InfoGameContents", function()
	gameData = util.Compress( util.TableToJSON( getServerGames() ) )
	gameSize = gameData:len()
end)

net.Receive("PCR.RequestServerGameContents", function(len, ply)
	if CheckUser(ply) then
		
		net.Start("PCR.TheServerGameContents")
			net.WriteUInt(gameSize,32)
			net.WriteData(gameData,gameSize)
		net.Send(ply)
		
	end
end)

local function checkModelExistence( mdlPath )
	local svgames = getServerGames()
	svgames["MOD"]	= "gmod"	-- GMod Directory
	svgames["GAME"]	= "all"		-- everything
	
	local Found = false
	
	for gamepath,_ in SortedPairs(svgames) do
		if file.Exists(mdlPath, gamepath) then
			Found = true
			break -- we only need to verify once and fully stop the loop operation.
		end
	end
	
	return Found
end

local function SavePropData( tblToAdd )	

	local path = PHX.ConfigPath .. "/prop_chooser_custom"
	
	if !file.Exists(path, "DATA") then
		ErrorNoHalt("[!Prop Menu] ERROR: Cannot save prop settings because '" .. path .. "' is Missing!\n")
		return false
	end
	
	if !tblToAdd or tblToAdd == nil then
		ErrorNoHalt("[!Prop Menu] ERROR: Cannot save prop settings because Table is Invalid!\n")
		return false 
	end
	
	if table.IsEmpty( tblToAdd ) then
		ErrorNoHalt("[!Prop Menu] ERROR: Cannot save prop settings because Table is Empty!\n")
		return false
	end

	local ValidModels = {}
	-- Empty PCR.CustomProp data because we'll change it anyway.
	PCR.CustomProp = {}
	
	for _,mdl in SortedPairs( tblToAdd ) do
		local good = checkModelExistence( mdl )
		
		if PHX.PROHIBITTED_MDLS[ string.lower( mdl ) ] then
			print("[Prop Menu] Cannot add model '" .. mdl .. "' because it is a prohibited model (PHX.PROHIBITTED_MDLS)!")
		elseif good then
			table.insert( ValidModels, mdl )
		else
			print("[Prop Menu] Cannot add model '" .. mdl .. "' because it seems not exists in the server!") --should verbose message?
		end
	end
	
	PCR.CustomProp = table.Copy( ValidModels )
	local json = util.TableToJSON( ValidModels, true )
	file.Write( path.."/models.txt", json )
	
	return true
end

local function InformEditor( ply, bool )
	if !bool or bool == nil then bool = false end
	
	net.Start("phxpm.fb_UpdateConfirmed_Editor")
	if bool then -- if Error
		net.WriteBool(true)
	else
		net.WriteBool(false)
	end
	net.Send(ply)
end

net.Receive("PCR.EditedCustomPropData", function(len, ply)
	if CheckUser(ply) then
		
		local var = net.ReadString()
		local sub = net.ReadString()
		local size = net.ReadUInt(32)
		local data = net.ReadData(size)
		
		if !data or data == nil then 
			-- confirm to editor that variable PCR and CustomProp is missing.
			ErrorNoHalt("[!Prop Menu] Error Retreiving Prop Data: Unknown Error\n")
			InformEditor(ply, true)
			return
		end
		
		local js = util.Decompress( data )
		local DataTable = util.JSONToTable(js)
		
		if var ~= "PCR" or sub ~= "CustomProp" then --Strict to PCR and CustomProp!
			-- confirm to editor that variable PCR and CustomProp is missing.
			ErrorNoHalt("[!Prop Menu] Error: Cannot save - reason: One of the variable: [" .. var .. ", ".. sub .."] appears to be invalid!\n")
			InformEditor(ply, true)
			return
		end
		
		local stat = SavePropData( DataTable )
		
		if stat then
			-- Saving counts as activity, so an editor who keeps working keeps the lock.
			if ply == editor then editSince = CurTime() end
			
			timer.Simple(1, function()
				PCR:PopulateProp( true )
				-- Broadcast to Players First
				net.Start("pcr.PropListData")
				net.WriteUInt(PCR.propDataSize, 32)
				net.WriteData(PCR.propDatajson, PCR.propDataSize)
				net.Broadcast()
				-- Send Custom Props for Editing
				if !table.IsEmpty(PCR.CustomProp) then
					net.Start("pcr.EditorCustomData")
					net.WriteUInt(PCR.customPropSize, 32)
					net.WriteData(PCR.customPropJson, PCR.customPropSize)
					net.Broadcast()
				end
				-- Confirm To Last Editor (who may have left during the delay)
				if IsValid( ply ) then InformEditor(ply, false) end
			end)
		else
			-- Inform to the Last Editor that, something is causing Error.
			InformEditor(ply, true)
		end
		
	end
end)

net.Receive("PCR.DoneEditing", function(len, ply)
	-- Only the holder can release the lock, so a stale Close can't free someone else's.
	if CheckUser(ply) and ply == editor then
		editor = nil
	end
end)

if SERVER then
	local function checkifsomeoneediting(ply)
		local inEditing = IsEditLocked()
		
		if ( game.IsDedicated() and ply == NULL ) then
			print( "Is someone editing?: " .. tostring(inEditing) )
			return
		end
	
		if CheckUser(ply) then
			MsgAll( "Is someone editing?: " .. tostring(inEditing) .. "\n" )
			ply:ChatPrint( "Is someone editing?: " .. tostring(inEditing) )
		end
	end
	concommand.Add("is_someone_editing", checkifsomeoneediting)
end