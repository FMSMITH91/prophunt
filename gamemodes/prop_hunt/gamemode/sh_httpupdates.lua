PHX.Messagedata = {}

-- Only a 2xx carrying valid update JSON counts. The primary URL now redirects
-- to an HTML page, which used to pass as success and stop there, so the backup
-- was never tried. A failed check logs one line; details are verbose-only.
local function IsUpdateInfo( body, code )
	code = tonumber(code) or 0
	return code >= 200 and code < 300 and PHX:NotifyUpdate( body )
end

local function UPDATE_DO_FETCH_BACKUP()
	
	PHX:VerboseMsg( "[Update] Retrying with backup update..." )
	
	http.Fetch(
		GAMEMODE.UPDATEURLBACKUP,
		function(body,_,_,code)
			if IsUpdateInfo( body, code ) then return end
			
			print( "[!PH:X Update] Update info unavailable (backup HTTP Code: "..tostring(code)..")." )
		end,
		function(err)
			print("[!PH:X Update] Update info unavailable. Reason: " .. tostring(err))
		end
	)
	
end

local function UPDATE_DO_FETCH()

	http.Fetch(
		GAMEMODE.UPDATEURL,
		function(body,_,_,code)
			if IsUpdateInfo( body, code ) then return end
			
			PHX:VerboseMsg( "[Update] No update info at the primary URL (HTTP Code: "..tostring(code)..")." )
			UPDATE_DO_FETCH_BACKUP()
		end,
		function(err)
			PHX:VerboseMsg( "[Update] Primary update URL failed: " .. tostring(err) )
			UPDATE_DO_FETCH_BACKUP()
		end
	)

end

function PHX:PrintUpdateConsole()
	MsgC( color_white, "[ Prop Hunt X - Update Info ]\n" )
	
	if (!self.Messagedata) then
		MsgC(Color(230,20,20), "[!!] Error: Update message data is empty")
		return
	end
	
	if (!self.Messagedata.version or !self.Messagedata.revision or !self.Messagedata.url) then
		MsgC(Color(230,20,20), "[!!] Error Retreiving updates info - some update elements are missing.")
		return
	end
	
	MsgC(Color(181,230, 30), "[+] Current Version : "..self.Messagedata.version.."\n")
	MsgC(Color(175,245, 15), "[+] Current Revision: "..self.Messagedata.revision.."\n")
	MsgC(Color(247,211, 13), "[!] See ChangeLog   : "..self.Messagedata.url.."\n")
	MsgC(Color(220,220,220), "[*] Full Description update: \n" .. self.Messagedata.info .. "\n")
end

-- Revisions are dd.mm.yy; turn one into a number that sorts by date.
local function RevisionStamp( rev )
	local d, m, y = string.match( rev or "", "^(%d%d)%.(%d%d)%.(%d%d)$" )
	if !d then return nil end
	return tonumber(y) * 10000 + tonumber(m) * 100 + tonumber(d)
end

-- Returns true only when `result` held usable update info.
function PHX:NotifyUpdate(result)
	
	if (!result or result == "") then
		self:VerboseMsg("[Update] Warning: Data contains nothing!", 2)
		return false
	end
	
	self:VerboseMsg("[*PH: X Update] Incoming update result data, parsing infos...")
	local data = util.JSONToTable(result)
	
	if !istable(data) or !isstring(data.version) or !isstring(data.revision) or !isstring(data.url) or !isstring(data.notice) then
		self:VerboseMsg("[Update] Error: Unable to parse update info.", 2)
		return false
	end
	
	local ver = data.version
	local rev = data.revision
	local url = data.url
	local log = data.notice

	PHX.Messagedata = {
		version 	= ver,
		revision 	= rev,
		url			= url,
		info		= log
	}
	
	-- write to /data instead. CLIENT SIDE ONLY.
	if CLIENT then
		file.Write(PHX.ConfigPath .. "/phx_update_info.txt", result)
	end
	
	local text = "[*PH: X Update] Your gamemode is up to date."
	local color = Color(0,200,40)
	local isNew = false
	-- Compare revisions as dates when both parse: this build's revision can be
	-- newer than the published one, and plain inequality called that an update.
	local localStamp, remoteStamp = RevisionStamp( GAMEMODE.REVISION ), RevisionStamp( rev )
	local revIsNew = GAMEMODE.REVISION ~= rev
	if localStamp and remoteStamp then revIsNew = remoteStamp > localStamp end
	
	if GAMEMODE._VERSION ~= ver then
		text = "[!PH: X Update] New version of "..ver.." is available."
		color = Color(0,160,230)
		isNew = true
	elseif revIsNew then
		text = "[!PH: X Update] New Revision of "..rev.." is available."
		color = Color(0,160,230)
		isNew = true
	end
	
	MsgC(color, text .. "\n")
	
	if isNew then
		self:PrintUpdateConsole()
	end
	
	return true
end

function PHX:CheckUpdate()
	PHX:VerboseMsg("[Update] Checking Update Notification... Please Wait!")
	UPDATE_DO_FETCH()
end

-- This file is shared, so the command exists on the server too - where running
-- it costs an outbound http.Fetch (plus a second one to the backup URL on any
-- failure). Ungated, one client could drive that as fast as they could bind a
-- key, so the server side is staff-only like every other PH:X admin command.
-- util.IsStaff() also covers the dedicated server console, where ply == NULL.
-- Clients may still check their own copy: that costs the server nothing.
concommand.Add("ph_check_update", function( ply )
	if SERVER and ( not util.IsStaff( ply ) ) then
		if IsValid( ply ) then ply:PHXChatInfo( "ERROR", "MISC_ACCESSDENIED" ) end
		PHX:VerboseMsg("[Update] Rejected ph_check_update from a non-staff player.", 2)
		return
	end

	PHX:CheckUpdate()
end , nil, "Force Check Update Prop Hunt: X. (Server: staff only)")

local cooldown	= 86400
hook.Add("Initialize", "PHX.CheckUpdateInit", function()

timer.Simple(3, function()
	local nextUpdate = cookie.GetNumber("phxNextUpdateInfo",0)
	local time		 = os.time()
	
	if time < nextUpdate then
		print("[Update] Skipping update check. Will recheck on "..os.date("%Y/%m/%d - %H:%M:%S", nextUpdate))
	else	
		print("[Update] Checking Update...")
		PHX:CheckUpdate()
		cookie.Set("phxNextUpdateInfo", time + cooldown)
		print("[Update] Update has been checked. Your next update notice will be displayed on "..os.date("%Y/%m/%d - %H:%M:%S", cookie.GetNumber("phxNextUpdateInfo",0)) )
	end
end)
	
end)

if CLIENT then
	local w = {}
	
	function PHX:notifyUser()
		local data = {}
	
		if (file.Exists(PHX.ConfigPath .. "/phx_update_info.txt", "DATA")) then
			local json = file.Read(PHX.ConfigPath .. "/phx_update_info.txt", "DATA")
			data = util.JSONToTable(json)
		else
			PHX:MsgBox("UPDATE_NOTIFY_MSG_NOTFOUND", "UPDATE_NOTIFY_MSG_TITLE", "MISC_OK")
			return
		end
	
		w.frame = vgui.Create("DFrame")
		w.frame:SetTitle( PHX:FTranslate("UPDATE_NOTIFY_WINDOW_TITLE") )
		w.frame:SetSize(640, ScrH() * 0.75)
		w.frame:Center()
		
		w.richtext = vgui.Create("RichText", w.frame)
		w.richtext:Dock(FILL)
		w.richtext:DockMargin(4,8,4,8)
		w.richtext:InsertColorChange(255,205, 50,255)
		w.richtext:AppendText(data.notice)
		function w.richtext:PerformLayout()
			self:SetFontInternal("PHX.TopBarFont")
		end
		w.richtext:InsertColorChange(220,220,220,255)
		w.richtext:AppendText( PHX:FTranslate( "UPDATE_RTBOX_APPEND", GAMEMODE._VERSION, GAMEMODE.REVISION ) )
		
		w.button = vgui.Create("DButton", w.frame)
		w.button:Dock(BOTTOM)
		w.button:DockMargin(4,8,4,8)
		w.button:SetSize(0,48)
		w.button:SetText( PHX:FTranslate( "UPDATE_BTN_SEEFULL" ) )
		function w.button:DoClick()
			gui.OpenURL(data.url)
		end
		
		w.frame:MakePopup()
	end
	
end