local function LoadOBBConfig()
	local map = game.GetMap()
	local GetData = "phe-config/obb/"..map..".txt"
	
	if !file.Exists(GetData, "DATA") then
		printVerbose("[PH-ENHANCED] No OBB Configuration found for map: "..map)
		return false
	end
	
	if file.Exists(GetData, "DATA") then
		local data = file.Read(GetData,"DATA")
		local ParsedData = util.JSONToTable(data)

		return ParsedData
	end
end

local function DoConfig()
	local data = PHE:LoadOBBConfig()
	if !data then return end
	
	--[[structure:  -- todo How to make this better???
		{
			model 	= "models/path/mdl.mdl",
			-- min Z for both standing and duck must contain 0. you can make it 0 by default anyway.
			hmin 	= "0,0,0", hmax = "16,16,16",
			dhmin 	= "0,0,0", dhmax = "8,8,8"
		}
	]]
	
	local function SetEntityData(ent, tab1, tab2)
		if IsValid(ent) then
			ent:SetNWBool("hasCustomHull",true)
			ent.m_Hull 	= tab1
			ent.m_dHull = tab2
		end
	end
	
	for _,mdldata in pairs(data) do
		local ent = ents.FindByModel(mdldata["model"])
		
		for _,mdl in pairs(ent) do
			local hull = {
				min = string.Explode(",", mdldata["hmin"]),
				max = string.Explode(",", mdldata["hmax"])
			}
			
			local dhull = {
				min = string.Explode(",", mdldata["dhmin"]),
				max = string.Explode(",", mdldata["dhmax"])
			}
		
			SetEntityData(mdl,
				-- Hull Min Z & Duck Hull Min Z must always stays zero!
				{ min = Vector(hull.min[1],  hull.min[2], hull.min[3]), max = Vector(hull.max[1],  hull.max[2], hull.max[3]) },
				{ min = Vector(dhull.min[1],dhull.min[2],dhull.min[3]), max = Vector(dhull.max[1],dhull.max[2],dhull.max[3]) }
			)
		end
	end
	
end

-- Todo: This feature will be available on Revision C.

--[[
hook.Add("Initialize", "PHE.InitOBBModelData", function()
	timer.Simple(1.5, function()
		printVerbose("[PH: Enhanced] Initializing OBB ModelData Config...")
		DoConfig()
	end)
end)

hook.Add("PostCleanupMap", "PHE.PostLoadOBBModelData", function()
	printVerbose("[PH: Enhanced] Post-Loading (game.CleaUp) OBB ModelData Map Config...")
	DoConfig()
end)
]]--