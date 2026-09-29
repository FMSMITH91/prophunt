dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- Net payload limits, run as shipped: util.PHXSendCompressed from sv_nettables.lua,
-- init.lua's sendGroupInfo (a joiner's group lists), sh_config.lua's prop ban list
-- send, and the whole of sv_admin.lua from the staff menu's save message to the
-- broadcast of the saved file. GMod caps a net message at about 64KB: past 60000
-- bytes nothing may be sent and the server must say why; under it, every message
-- must go out exactly as before (a 32-bit length, then the data), as that is what
-- the clients read.

local GM = "gamemodes/prop_hunt/gamemode/"

-- Record the wire format as written, bit width and data length included.
function net.WriteUInt(v, bits) table.insert(S.net.cur.data, ("uint%s:%s"):format(bits, v)) end
function net.WriteData(d, n) table.insert(S.net.cur.data, ("data%s:%s"):format(n, d)) end
function net.ReadData() return table.remove(S.net.readq, 1) end
-- A refused payload must not even start a message: count every net.Start.
local starts, shimStart = 0, net.Start
function net.Start(n) starts = starts + 1; shimStart(n) end
local errors = {}
function ErrorNoHalt(msg) errors[#errors + 1] = tostring(msg) end
local realprint = print

local function sent(name)
  local r = {}
  for _, m in ipairs(S.net.sent) do if m.name == name then r[#r + 1] = m end end
  return r
end
-- A message's recipient and payload, or "none" when it was not sent (or sent twice).
local function wire(name)
  local m = sent(name)
  if #m ~= 1 then return #m == 0 and "none" or ("sent " .. #m .. " times") end
  local to = m[1].to == "all" and "all" or (m[1].to and m[1].to._name or "?")
  return (to .. " " .. table.concat(m[1].data, " ")):sub(1, 60)   -- a failure prints no 60KB line
end
local function reset() S.net.sent, errors, starts = {}, {}, 0 end
local function erred(pat) return #errors == 1 and errors[1]:find(pat) ~= nil end

loadblocks("sv_nettables.lua", extract(GM .. "sv_nettables.lua", "1-99999"))

print("\n== util.PHXSendCompressed ==")
local ply = S.Player{ name = "joiner" }
reset()
check("small payload: sent", util.PHXSendCompressed("PHX.Test", "abc", 3, ply), true)
check("  ... to the target, as UInt32 length + data", wire("PHX.Test"), "joiner uint32:3 data3:abc")
check("  ... no error", #errors, 0)
reset()
util.PHXSendCompressed("PHX.Test", "abc", 3)
check("no target: broadcast", wire("PHX.Test"), "all uint32:3 data3:abc")
reset()
local at = string.rep("x", 60000)
check("exactly 60000 bytes: sent (normal play)", util.PHXSendCompressed("PHX.Test", at, #at, ply), true)
check("  ... whole", sent("PHX.Test")[1] and sent("PHX.Test")[1].data[2] == "data60000:" .. at, true)
check("  ... no error", #errors, 0)
reset()
local over = string.rep("x", 60001)
check("60001 bytes: refused", util.PHXSendCompressed("PHX.Test", over, #over, ply), false)
check("  ... nothing sent", wire("PHX.Test"), "none")
check("  ... no message even started", starts, 0)
check("  ... one error naming the message and size", erred("PHX%.Test.*60001 bytes"), true)

print("\n== sendGroupInfo: a joiner's group lists ==")
local sendGroupInfo = loadchunk(extract(GM .. "init.lua", [[^local function sendGroupInfo]])
  .. "\nreturn sendGroupInfo", "init.lua@sendGroupInfo")()
-- Stands in for TableToJSON + Compress: the group names, sorted.
function util.PHXQuickCompress(t)
  local k = table.GetKeys(t); table.sort(k)
  local c = table.concat(k, ",")
  return c, #c
end
PHX.IgnoreMutedUserGroup = { vip = true }
PHX.SVAdmins = { admin = true, superadmin = true }
reset()
sendGroupInfo(ply)
check("muted groups: sent to the joiner as before", wire("PHX.MutedGroupInfo"), "joiner uint32:3 data3:vip")
check("admin groups: sent to the joiner as before", wire("PHX.AdminGroupInfo"), "joiner uint32:16 data16:admin,superadmin")
check("  ... muted first, as before", S.net.sent[1] and S.net.sent[1].name, "PHX.MutedGroupInfo")
check("  ... no error", #errors, 0)
local huge = string.rep("g", 60001)
PHX.SVAdmins = { [huge] = true }
reset()
sendGroupInfo(ply)
check("admin list past the limit: not sent", wire("PHX.AdminGroupInfo"), "none")
check("  ... the server logs why", erred("PHX%.AdminGroupInfo.*60001 bytes"), true)
check("  ... muted list still sent (normal play)", wire("PHX.MutedGroupInfo"), "joiner uint32:3 data3:vip")
check("  ... only that message started", starts, 1)
PHX.SVAdmins, PHX.IgnoreMutedUserGroup = { superadmin = true }, { [huge] = true }
reset()
sendGroupInfo(ply)
check("muted list past the limit: not sent", wire("PHX.MutedGroupInfo"), "none")
check("  ... admin list still sent (normal play)", wire("PHX.AdminGroupInfo"), "joiner uint32:10 data10:superadmin")

print("\n== sh_config.lua: the prop ban lists ==")
local UpdatePropBansInfo = loadchunk(extract(GM .. "sh_config.lua", [[^local function UpdatePropBansInfo]])
  .. "\nreturn UpdatePropBansInfo", "sh_config.lua@UpdatePropBansInfo")()
-- Stands in for TableToJSON + Compress: the models, in order.
function util.PHXQuickCompress(t) local c = table.concat(t, ","); return c, #c end
reset()
UpdatePropBansInfo("BANNED_PROP_MODELS", { "models/a.mdl" }, ply)
check("prop bans: sent to the joiner as before", wire("PHX.UpdatePropbanInfo"),
  "joiner BANNED_PROP_MODELS uint32:12 data12:models/a.mdl")
reset()
UpdatePropBansInfo("PROP_PLMODEL_BANS", { "models/player.mdl" })
check("playermodel bans: broadcast as before", wire("PHX.UpdatePropbanInfo"),
  "all PROP_PLMODEL_BANS uint32:17 data17:models/player.mdl")
reset()
UpdatePropBansInfo("BANNED_PROP_MODELS", { string.rep("m", 60000) })
check("exactly 60000 bytes: broadcast (normal play)", sent("PHX.UpdatePropbanInfo")[1] ~= nil, true)
check("  ... no error", #errors, 0)
reset()
UpdatePropBansInfo("BANNED_PROP_MODELS", { string.rep("m", 60001) }, ply)
check("ban list past the limit: nothing started", starts, 0)
check("  ... the server logs the message, list and size",
  erred("PHX%.UpdatePropbanInfo.*BANNED_PROP_MODELS.*60001 bytes"), true)

print("\n== sv_admin.lua: saving the group lists ==")
-- A DATA folder, and a JSON codec that is just the sorted group names in braces.
local files, writable = {}, true
file.Exists = function(p) return files[p] ~= nil end
file.Read = function(p) return files[p] end
file.Size = function(p) return files[p] and #files[p] or 0 end
file.Write = function(p, d) if writable then files[p] = d end end
util.TableToJSON = function(t) local k = table.GetKeys(t); table.sort(k); return "{" .. table.concat(k, ",") .. "}" end
util.JSONToTable = function(s)
  local body = s and s:match("^{(.*)}$")
  if not body then return nil end
  local t = {}
  for g in body:gmatch("[^,]+") do t[g] = true end
  return t
end
util.PHXQuickDecompress = function(d) return d end   -- the payload is the decoded table
loadblocks("sv_admin.lua", extract(GM .. "sv_admin.lua", "1-99999"))

local staff, pleb = S.Player{ name = "staff", staff = true }, S.Player{ name = "pleb" }
local function save(msg, who, groups)
  who.chat, S.net.readq = {}, { 0, groups }
  reset()
  local r = attempt(S.receivers[msg], 0, who)
  return r ~= "ok" and r or (who.chat[1] and who.chat[1][2] or "none")
end

PHX.SVAdmins, PHX.IgnoreMutedUserGroup = { superadmin = true }, {}
check("staff saves admin groups: told it worked", save("PHX.CLAdminGroupInfo", staff, { admin = true, superadmin = true }),
  "PHXM_ADMIN_ACCCFG_SUCC")
check("  ... written to disk", files["phx_data/admins.txt"], "{admin,superadmin}")
check("  ... broadcast as before", wire("PHX.AdminGroupInfo"), "all uint32:18 data18:{admin,superadmin}")
check("  ... the server's list updated", PHX.SVAdmins.admin, true)
check("  ... no error", #errors, 0)
check("staff saves muted groups: told it worked", save("PHX.CLMutedGroupInfo", staff, { vip = true }), "PHXM_ADMIN_MUTCFG_SUCC")
check("  ... broadcast as before", wire("PHX.MutedGroupInfo"), "all uint32:5 data5:{vip}")
check("non-staff save: ignored (normal play)", save("PHX.CLAdminGroupInfo", pleb, { user = true }), "none")
check("  ... nothing sent", #S.net.sent, 0)
check("  ... list unchanged", PHX.SVAdmins.user, nil)

check("admin list past the limit: still saved", save("PHX.CLAdminGroupInfo", staff, { [huge] = true }), "PHXM_ADMIN_ACCCFG_SUCC")
check("  ... on disk", files["phx_data/admins.txt"] == "{" .. huge .. "}", true)
check("  ... but not broadcast", wire("PHX.AdminGroupInfo"), "none")
check("  ... the server logs why", erred("PHX%.AdminGroupInfo.*60003 bytes"), true)
check("  ... no message even started", starts, 0)
check("muted list past the limit: not broadcast", (function()
  save("PHX.CLMutedGroupInfo", staff, { [huge] = true }); return wire("PHX.MutedGroupInfo") end)(), "none")
check("  ... the server logs why", erred("PHX%.MutedGroupInfo.*60003 bytes"), true)

print("\n== sv_admin.lua: loading the group lists (normal play) ==")
files = { ["phx_data/admins.txt"] = "{mod,superadmin}" }
PHX.SVAdmins = { superadmin = true }
reset()
local data = PHX:ManageGroupInfo(true, false, "SVAdmins", "admins", "PHX.AdminGroupInfo")   -- GM:Initialize
check("load at startup: returns the file's groups", data and data.mod, true)
check("  ... becomes the server's list", PHX.SVAdmins.mod, true)
check("  ... nothing sent", #S.net.sent, 0)
files = {}
PHX.IgnoreMutedUserGroup = { vip = true }
data = PHX:ManageGroupInfo(true, false, "IgnoreMutedUserGroup", "muted_groups", "PHX.MutedGroupInfo")
check("no file yet: the defaults are written", files["phx_data/muted_groups.txt"], "{vip}")
check("  ... and loaded", data and data.vip, true)
files["phx_data/admins.txt"] = "not json"
PHX.SVAdmins = { superadmin = true }
reset()
data = PHX:ManageGroupInfo(true, true, "SVAdmins", "admins", "PHX.AdminGroupInfo")
check("unreadable file: nothing loaded", data, nil)
check("  ... the list kept", PHX.SVAdmins.superadmin, true)
check("  ... nothing sent", #S.net.sent, 0)
files["phx_data/admins.txt"] = "{superadmin}"
reset()
data = PHX:ManageGroupInfo(true, true, "SVAdmins", "admins", nil)
check("no net name: the file still loads", data and data.superadmin, true)
check("  ... nothing sent", #S.net.sent, 0)
check("  ... and the server says why", erred("'netName' is empty or invalid"), true)
reset()
check("no table key: nothing done", PHX:ManageGroupInfo(true, true, nil, "admins", "PHX.AdminGroupInfo"), nil)
check("  ... an error", erred("Table Key and File Name is required"), true)
reset()
check("no file name: nothing done", PHX:ManageGroupInfo(false, false, "SVAdmins", nil), nil)
check("  ... an error", erred("Table Key and File Name is required"), true)
check("save: returns 1", PHX:ManageGroupInfo(false, false, "SVAdmins", "admins"), 1)
files, writable = {}, false
print = function() end   -- its "Error Saving configuration file" line
local r = PHX:ManageGroupInfo(false, false, "SVAdmins", "admins")
print = realprint
check("save to a read-only DATA folder: returns 0", r, 0)

report()
