-- Derma stand-in shared by the client UI tests (t_menusconfig_clientui.lua and
-- t_menusconfig_clientwindows.lua). Load it after runner.lua; it returns the
-- panel registry D, the lastSent/lastChat readers and the panel methods P.

local GM = "gamemodes/prop_hunt/gamemode/"

-- The files print their own progress; keep the PASS/FAIL lines readable.
local realprint = print
print = function(s, ...)
  if type(s) == "string" and s:match("^%[Taunt Menu%]") then return end
  return realprint(s, ...)
end

---------------------------------------------------------------- Derma stand-in
-- Anything not modelled below is a do-nothing object: every field is callable
-- and returns it again, and writes to it are dropped. Only PascalCase keys fall
-- through to it, so a data field the code never set (ic.selected) reads nil
-- exactly as it does on a real panel.
local Chain = setmetatable({}, {})
getmetatable(Chain).__index = function() return Chain end
getmetatable(Chain).__call = function() return Chain end
getmetatable(Chain).__newindex = function() end

local D = { all = {}, chat = {}, boxes = {}, writes = {} }
local P = {}
local PanelMT = { __index = function(_, k)
  local m = P[k]
  if m ~= nil then return m end
  if type(k) == "string" and k:match("^%u") then return Chain end
  return nil
end }

function D.create(class, parent)
  local p = setmetatable({ __valid = true, _class = class, _children = {}, _items = {},
    _lines = {}, _choices = {}, _options = {}, _sheets = {}, _visible = true,
    _inval = 0, lblTitle = Chain, m_Image = Chain }, PanelMT)
  D.all[#D.all + 1] = p
  if parent ~= nil and getmetatable(parent) == PanelMT then
    p._parent = parent
    table.insert(parent._children, p)
  end
  if class == "DIconBrowser" then
    -- engine: DScrollPanel canvas first, then the IconLayout inside it
    local canvas = D.create("Panel", p)
    rawset(p, "IconLayout", D.create("DIconLayout", canvas))
  end
  return p
end
function D.find(pred) for _, p in ipairs(D.all) do if p.__valid and pred(p) then return p end end end
function D.count(pred) local n = 0 for _, p in ipairs(D.all) do if p.__valid and pred(p) then n = n + 1 end end return n end
function D.class(c) return function(p) return p._class == c end end

function P:SetSize(w, h) self._w, self._h = w, h end
function P:GetWide() return self._w or 100 end
function P:GetTall() return self._h or 30 end
function P:SetWide(w) self._w = w end
function P:SetTall(h) self._h = h end
function P:GetColWide() return self._colw or 800 end
function P:SetColWide(w) self._colw = w end
function P:GetRowHeight() return self._rowh or 35 end
function P:SetRowHeight(h) self._rowh = h end
function P:SetVisible(b) self._visible = b end
function P:IsVisible() return self._visible ~= false end
function P:InvalidateParent() self._inval = self._inval + 1 end
function P:SetText(t) self._text = t; self._value = t end
function P:GetText() return self._text or "" end
function P:SetTooltip(t) self._tooltip = t end
function P:SetValue(v)
  self._value = v; self._text = v
  -- DBinder: SetValue -> SetSelectedNumber -> UpdateText -> OnChange (dbinder.lua:61-66)
  if self._class == "DBinder" and rawget(self, "OnChange") then self:OnChange(v) end
end
function P:GetValue(i) if i then return self._cols and self._cols[i] end return self._value end
function P:SetMin(v) self._min = v end
function P:SetMax(v) self._max = v end
function P:GetMin() return self._min end
function P:GetMax() return self._max end
function P:SetChecked(b) self._checked = b end
function P:GetChecked() return self._checked == true end
function P:SetModel(m) self._model = m end
function P:GetModelName() return self._model end
function P:IsValid() return self.__valid end
function P:GetParent() return self._parent or Chain end
function P:GetChildren() local r = {} for i, c in ipairs(self._children) do r[i] = c end return r end
function P:Add(class) return D.create(class, rawget(self, "IconLayout") or self) end
function P:AddItem(p) table.insert(self._items, p) end
function P:Remove()
  self.__valid = false
  if self._parent then
    for i, c in ipairs(self._parent._children) do if c == self then table.remove(self._parent._children, i) break end end
  end
  for _, c in ipairs(self:GetChildren()) do c:Remove() end
end
function P:Close() local oc = rawget(self, "OnClose"); if oc then oc(self) end self:Remove() end
function P:AddSheet(_, panel) local s = { Button = D.create("DButton", self), Panel = panel }; table.insert(self._sheets, s); return s end
function P:AddLine(...)
  local line = D.create("DListView_Line", self)
  line._cols = { ... }
  line.Columns = { D.create("DLabel", line) }
  table.insert(self._lines, line)
  return line
end
function P:GetLines() return self._lines end
function P:GetLine(i) return self._lines[i] end
function P:GetSelectedLine() return self._selected or 1 end
function P:Clear() self._lines = {} end
function P:AddChoice(text, data) table.insert(self._choices, { text, data }) end
function P:AddMenu() return D.create("DMenu") end
function P:AddOption(text, fn) table.insert(self._options, { text = text, fn = fn }); return D.create("DMenuOption") end

-- The engine only runs Think on a visible panel, and not below a hidden one.
function D.think(p)
  if not p.__valid or not p:IsVisible() then return end
  local th = rawget(p, "Think")
  if th then th(p) end
  for _, c in ipairs(p:GetChildren()) do D.think(c) end
end

vgui = { Create = function(class, parent) return D.create(class, parent) end }
function DermaMenu() local m = D.create("DMenu"); D.lastMenu = m; return m end
function ispanel(v) return getmetatable(v) == PanelMT end
function ScrW() return 1920 end
function ScrH() return 1080 end
surface = setmetatable({}, { __index = function() return function() end end })
draw = surface
language = { GetPhrase = function(s) return ({ ["#dbinder.none"] = "None" })[s] or s end }
-- client_client.so: codes outside 1..1041 return nothing (see finding #43)
local KEYNAMES = { [63] = "F3", [46] = "C" }
input = { GetKeyName = function(code)
  if type(code) ~= "number" then error("bad argument #1 to 'GetKeyName' (number expected)", 2) end
  if code < 1 or code > 1041 then return nil end
  return KEYNAMES[code] or ("KEY" .. code)
end }
string.Replace = function(s, find, rep)
  local pat = find:gsub("%W", "%%%0")
  local with = rep:gsub("%%", "%%%%")
  return (s:gsub(pat, with))
end
function net.SendToServer() S.net.cur.to = "server"; table.insert(S.net.sent, S.net.cur) end
local function lastSent() return S.net.sent[#S.net.sent] end
OBS_MODE_NONE = 0
color_white = Color(255, 255, 255)
file.Write = function(path) table.insert(D.writes, path) end

function PHX:GetCLCVar(n) return PHX:GetCVar(n) end
function PHX:QTrans(x) if type(x) == "table" then return x[1] end return x end
function PHX:Translate(id, ...) local a = { ... } for i = 1, select("#", ...) do a[i] = tostring(a[i]) end return id .. ":" .. table.concat(a, ",") end
function PHX:AddChat(t) table.insert(D.chat, tostring(t)) end
function PHX:ChatInfo(t) table.insert(D.chat, tostring(t)) end
function PHX:MsgBox(t) table.insert(D.boxes, t) end
function PHX:MsgBox_Query(t, _, _, yes) table.insert(D.boxes, t); if D.autoYes and yes then yes() end end
local function lastChat() return D.chat[#D.chat] or "" end

-- util.IsHexColor lives in sh_utils.lua; use the shipped one.
loadblocks("sh_utils.lua@IsHexColor", extract(GM .. "sh_utils.lua", [[^function util\.IsHexColor]]))

return D, lastSent, lastChat, P
