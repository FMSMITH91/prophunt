dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- The F1 group-access tab (cl_menuadmacc.lua). Its checkboxes list ULX's groups
-- only, so Apply must leave every other group in the staff and mute lists alone.

print("\n== Apply keeps groups the editor does not list ==")

-- Derma stand-ins: any method is a no-op returning 100, except the ones below.
local created = {}
local function widget()
  local w = setmetatable({}, { __index = function() return function() return 100 end end })
  w.Content = setmetatable({}, getmetatable(w))
  function w:Add(cls) return vgui.Create(cls) end
  return w
end
vgui = { Create = function(cls)
  local w = widget()
  if cls == "DCheckBoxLabel" then
    function w:SetText(t) self.text = t end
    function w:SetChecked(b) self.checked = b and true or false end
    function w:GetChecked() return self.checked end
    function w:SetEnabled() end
    created[#created + 1] = w
  end
  return w
end }

local me = S.Player{ staff = true }
LocalPlayer = function() return me end
function PHX:FTranslate(s) return s end
function PHX:MsgBox_Query(_, _, _, yes) yes() end
local sent = {}
util.PHXQuickCompress = function(t) sent[#sent + 1] = t; return "x", 1 end
-- No "user" group: the loop's only `continue` skips it, and stock LuaJIT (CI)
-- cannot parse `continue`, so that line is dropped below.
ULib = { ucl = { groups = { superadmin = {}, admin = {}, operator = {} } } }
net.SendToServer = net.SendToServer or function() end

PHX.SVAdmins = { superadmin = true, moderator = true }          -- moderator: not a ULX group
PHX.IgnoreMutedUserGroup = { superadmin = true, admin = true, vip = true }

S.hooks = {}
local src = extract("gamemodes/prop_hunt/gamemode/cl_menuadmacc.lua", "1-99999")
local stripped
src, stripped = src:gsub('if group == "user" then continue end', '')
check("harness: the one `continue` line was stripped", stripped, 1)
loadblocks("cl_menuadmacc.lua", src)

-- Open the tab the way the F1 menu does, and keep the Apply button.
local apply
local tab = widget()
function tab:Add(cls)
  local p = vgui.Create(cls)
  local realAdd = p.Add
  function p:Add(c)
    local w = realAdd(self, c)
    if c == "DPanel" then
      local addInner = w.Add
      function w:Add(c2) local b = addInner(self, c2); if c2 == "DButton" and not apply then apply = b end; return b end
    end
    return w
  end
  return p
end
function tab:AddSheet() return {} end
S.fire("PH_CustomTabMenu", tab, nil, function() end)
check("harness: the Apply button was found", apply ~= nil, true)

-- The first DCheckBoxLabel of each pair is access, the second mute.
local access, mute = {}, {}
for i = 1, #created, 2 do access[created[i].text:gsub("PHXM.*", "")] = created[i]; mute[created[i + 1].text] = created[i + 1] end
access.operator:SetChecked(true)       -- staff: add operator
mute.admin:SetChecked(false)           -- mute: drop admin
apply:DoClick()

local admins, mutes = sent[1], sent[2]   -- compressed in this order (sent mute-first)
check("access: the ticked ULX group is added", admins and admins.operator, true)
check("access: a group ULX doesn't list is kept", admins and admins.moderator, true)
check("access: superadmin stays", admins and admins.superadmin, true)
check("mute: the unticked ULX group is removed", mutes and mutes.admin, nil)
check("mute: a group ULX doesn't list is kept", mutes and mutes.vip, true)

report()
