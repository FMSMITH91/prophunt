hook.Add("PH_CustomTabMenu", "PHE.About", function(tab, pVgui)
	-- Help Wanted: Returned argument of Ph:CreateBasicLayout()->this Hook cannot captured properly in this scope. Any Idea?
	-- Todo: this 3 variable function below should be a function argument callback instead recopying over. (tab, layout, pVgui)
	
	surface.CreateFont("PHE.TitleFont", 
	{
		font = "Roboto",
		size = 40,
		weight = 700,
		antialias = true,
		shadow = true
	})
	
	local panel = vgui.Create("DPanel", tab)
	panel:SetBackgroundColor(Color(40,40,40,120))
	
	local scroll = vgui.Create( "DScrollPanel", panel )
	scroll:Dock(FILL)
	
	local grid = vgui.Create("DGrid", scroll)
	grid:Dock(NODOCK)
	grid:SetPos(10,10)
	grid:SetCols(1)
	grid:SetColWide(800)
	grid:SetRowHeight(50)
	
	local label = {
		title 	= "Prop Hunt: Enhanced",
		author	= "Enhanced by: Wolvindra-Vinzuerio, D4UNKN0WNM4N, Original: AMT, Modified: Kowalski",
		version = GAMEMODE._VERSION,
		rev 	= GAMEMODE.REVISION,
		credits	= "Yam, Godfather, adk, Lucas2107, Jonpopnycorn, Thundernerd",
		lgit	= "https://github.com/Vinzuerio/ph-enhanced/",
		lhome	= "https://project.wolvindra.net/phe/",
		ldonate = GAMEMODE.DONATEURL,
		lwiki	= "https://project.wolvindra.net/phe/?go=phe_faq",
	}
	
	-- > pVgui = Ph:CreateVGUIType, with no return. Seems works?
	pVgui("","label","PHE.TitleFont",grid, label.title .. " [BETA]" )
	pVgui("","label",false,grid, "Version: "..label.version.." | Revision: "..label.rev)
	pVgui("","label","PHE.PFont",grid, "Special Thanks for the support, suggestion & contributing:\n"..label.credits )
	
	pVgui("spacer1","spacer",nil,grid,"" )
	
	pVgui("","label",false,grid, "Helpful External Links:" )
	pVgui("","btn",{max = 4,textdata = {
		[1] = {"Donate PH:E Project", 	  function() gui.OpenURL(label.ldonate); tab:GetParent():Close() end},
		[2] = {"PH:E Official Homepage", 	  function() gui.OpenURL(label.lhome); tab:GetParent():Close() end},
		[3] = {"Project GitHub", 	  function() gui.OpenURL(label.lgit); tab:GetParent():Close() end},
		[4] = {"PH:E Help & Wiki", function() gui.OpenURL(label.lwiki); tab:GetParent():Close() end}
	}},grid,"")
	
	pVgui("spacer2","spacer",nil,grid,"" )
	pVgui("","label",false,grid, "Try out the new Prop Hunt: Enhanced Plugins + Addons:\n(Coming Soon!)" )
	
	tab:AddSheet("About & Credits",panel,"icon16/information.png")

end)