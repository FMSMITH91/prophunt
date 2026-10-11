local CUR_MAP_DATA = {}

-- The same hulls keyed by lowercased model. The per-entity copy only reaches map props
-- that existed when the config ran; a prop-menu pick is a fresh entity.
PHX.CustomHulls = PHX.CustomHulls or {}
local OwnHulls = {}

local function LoadOBBConfig()
	local map = game.GetMap()
	local GetData = PHX.ConfigPath .. "/obb/"..map..".txt"
	
	if !file.Exists(GetData, "DATA") then
		PHX:VerboseMsg("[OBB] No OBB Configuration found for map: "..map)
		return false
	end
	
	if file.Exists(GetData, "DATA") then
		local data = file.Read(GetData,"DATA")
		local ParsedData = util.JSONToTable(data)

		return ParsedData
	end
end

-- A { x, y, z } list of numbers.
local function IsVec3( t )
	return istable( t ) and isnumber( t[1] ) and isnumber( t[2] ) and isnumber( t[3] )
end

-- { "model.mdl", { min = {x,y,z}, max = {x,y,z} } }
local function IsValidEntry( e )
	return istable( e ) and isstring( e[1] ) and istable( e[2] ) and IsVec3( e[2]["min"] ) and IsVec3( e[2]["max"] )
end

local function DoConfig()
	-- Clear only what we added last time, so a model dropped from the file stops matching.
	for mdl in pairs(OwnHulls) do PHX.CustomHulls[mdl] = nil end
	OwnHulls = {}
	
	local data = CUR_MAP_DATA
	if !istable( data ) then return end
	
	--[[
	JSON structure:
	[
		[
			"model/path/b.mdl",
			{
				"min": [0, 0, 0],
				"max": [16, 16, 72],
				"dmin": [0, 0, 0],	 -- No longer needed
				"dmax": [16, 16, 28] -- No longer needed
			}
		]
	]
	
	LUA structure:
	1:
		1: "model/path/b.mdl"
		2:
			min 	= {-0,-0,-0}
			max 	= {16,16,72}
			dmin	= {-0,-0,-0} -- no longer needed
			dmax	= {16,16,28} -- no longer needed
	]]
	
	for i=1,#data do
		-- One bad entry used to error here every round and drop every entry after it.
		if !IsValidEntry( data[i] ) then
			PHX:VerboseMsg( "[OBB] Skipping malformed entry #"..i.." in this map's OBB config.", 2 )
			continue
		end
		local tent = ents.FindByModel(data[i][1])
		local min 	= Vector(data[i][2]["min"][1],data[i][2]["min"][2],data[i][2]["min"][3])
		local max 	= Vector(data[i][2]["max"][1],data[i][2]["max"][2],data[i][2]["max"][3])
		--[[ local dmin 	= Vector(data[i][2]["dmin"][1],data[i][2]["dmin"][2],data[i][2]["dmin"][3])
		local dmax 	= Vector(data[i][2]["dmax"][1],data[i][2]["dmax"][2],data[i][2]["dmax"][3]) ]]
		
		local mdl = string.lower(data[i][1])
		PHX.CustomHulls[mdl] = {min,max}
		OwnHulls[mdl] = true
		
		for _,found in pairs(tent) do
			if IsValid(found) then
				PHX:VerboseMsg( "[OBB MODIFIER] Setting up OBB Value for Entity ["..found:EntIndex().."]["..found:GetModel().."]: \n   >Hull-Vector: min "..tostring(min).." max "..tostring(max) )
				found:SetNWBool("hasCustomHull",true)
				found.m_Hull 	= {min,max}
			end
		end
	end
	
end

hook.Add("Initialize", "PHX.InitOBBModelData", function()

	if !file.Exists(PHX.ConfigPath .. "/obb","DATA") then
		file.CreateDir(PHX.ConfigPath .. "/obb")
	end

	timer.Simple(1.5, function()
		PHX:VerboseMsg("[OBB] Initializing OBB ModelData Config...")
		
		CUR_MAP_DATA = LoadOBBConfig()
		DoConfig()
	end)
end)

hook.Add("PostCleanupMap", "PHX.PostOBBModelData", function()
	-- Every round starts with a cleanup that respawns the map props without their
	-- hulls, so always re-apply. The ConVar only decides whether to re-read the file.
	if PHX:GetCVar( "ph_reload_obb_setting_everyround" ) then
		PHX:VerboseMsg("[OBB] PostCleanup: reloading OBB ModelData Config...")
		CUR_MAP_DATA = LoadOBBConfig()
	end
	
	DoConfig()
end)

concommand.Add("refresh_obb_map_setting", function(ply)

	if ( util.IsStaff( ply ) ) then

		PHX:VerboseMsg("[OBB] Refreshing OBB Model Data Modifier...")
		CUR_MAP_DATA = LoadOBBConfig()
	
		DoConfig()
		
	end

end, nil, "Force Reload PHX OBB/Collission Bound Model Data Modifier on this map.")