dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- Taunt tables: ManageTaunt merging, AddCustomTaunt's duplicate check, the taunt
-- scanner's category merge, and the chunked scanner transfer (#152/#211). The
-- scanner file is loaded WHOLE, once per realm, so both ends of the transfer
-- are the shipped code.

local CONFIG = "gamemodes/prop_hunt/gamemode/sh_config.lua"
local SCANNER = "gamemodes/prop_hunt/gamemode/sh_tauntscanner.lua"

string.Replace = function(s, find, rep)
  local pat = find:gsub("%W", "%%%0")
  local with = rep:gsub("%%", "%%%%")
  return (s:gsub(pat, with))
end
-- The shim's SortedPairs is plain pairs; the scanner's order matters here.
SortedPairs = function(t)
  local keys = table.GetKeys(t)
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local i = 0
  return function() i = i + 1; local k = keys[i]; if k ~= nil then return k, t[k] end end
end
HUD_PRINTCONSOLE = 2

print("\n== #32: ManageTaunt merging a team the category does not have yet ==")
loadblocks("sh_config.lua@Taunts", "local AddResources\n" .. extractAll(CONFIG, {
  [[^\tfunction AddResources\(t\)]], [[^function PHX:CheckCache]], [[^function PHX:AddToCache]],
  [[^function PHX:ManageTaunt]] }))

local function reset()
  PHX.TAUNTS, PHX.CachedTaunts, S.resources = {}, { [1] = {}, [2] = {} }, {}
end
local function has(list, v) return table.HasValue(list, v) end

reset()
check("new category (props only)", attempt(PHX.ManageTaunt, PHX, "Shared", { [TEAM_PROPS] = { A = "p/a.wav" } }), "ok")
check("  ... resource added", has(S.resources, "sound/p/a.wav"), true)
check("merge the OTHER team into it", attempt(PHX.ManageTaunt, PHX, "Shared", { [TEAM_HUNTERS] = { B = "h/b.wav" } }), "ok")
check("  ... hunter taunt stored", PHX.TAUNTS.Shared[TEAM_HUNTERS] and PHX.TAUNTS.Shared[TEAM_HUNTERS].B, "h/b.wav")
check("  ... and cached", PHX.CachedTaunts[TEAM_HUNTERS].B, "h/b.wav")
check("  ... and sent for download", has(S.resources, "sound/h/b.wav"), true)
check("  ... props untouched", PHX.TAUNTS.Shared[TEAM_PROPS].A, "p/a.wav")
-- the same-team merge worked before and must keep working
check("merge the SAME team", attempt(PHX.ManageTaunt, PHX, "Shared", { [TEAM_PROPS] = { C = "p/c.wav" } }), "ok")
check("  ... stored next to the first", PHX.TAUNTS.Shared[TEAM_PROPS].C, "p/c.wav")
check("  ... merged taunt is downloadable", has(S.resources, "sound/p/c.wav"), true)
PHX:ManageTaunt("Shared", { [TEAM_PROPS] = { A = "p/other.wav" } })
check("duplicate name is not overwritten", PHX.TAUNTS.Shared[TEAM_PROPS].A, "p/a.wav")
check("second category (list + scanner order)", attempt(PHX.ManageTaunt, PHX, "Memes",
      { [TEAM_HUNTERS] = { H = "h/h.wav" }, [TEAM_PROPS] = { P = "p/p.wav" } }), "ok")
check("  ... both teams stored", PHX.TAUNTS.Memes[TEAM_HUNTERS].H .. PHX.TAUNTS.Memes[TEAM_PROPS].P, "h/h.wavp/p.wav")

print("\n== #148: AddCustomTaunt checks the cache in the shape it expects ==")
loadblocks("sh_config.lua@AddCustomTaunt", "local AddResources = function() end\n"
  .. extract(CONFIG, [[^function PHX:AddCustomTaunt]]))
reset()
PHX:ManageTaunt("Cat A", { [TEAM_PROPS] = { Laugh = "a/laugh.wav" } })
check("same-named taunt from an addon", attempt(PHX.AddCustomTaunt, PHX, TEAM_PROPS, "Cat B",
      { Laugh = "b/laugh.wav", New = "b/new.wav" }), "ok")
check("  ... cache keeps the first category's path", PHX.CachedTaunts[TEAM_PROPS].Laugh, "a/laugh.wav")
check("  ... the duplicate is dropped from Cat B", PHX.TAUNTS["Cat B"][TEAM_PROPS].Laugh, nil)
check("  ... the new taunt is added", PHX.TAUNTS["Cat B"][TEAM_PROPS].New, "b/new.wav")
check("nil table -> refused, no error", attempt(PHX.AddCustomTaunt, PHX, TEAM_PROPS, "C", nil), "ok")
check("  ... nothing created", PHX.TAUNTS["C"], nil)
PHX:AddCustomTaunt(TEAM_PROPS, "All Dupes", { Laugh = "z/laugh.wav" })
check("all taunts already loaded -> no empty category", PHX.TAUNTS["All Dupes"], nil)
PHX:AddCustomTaunt(TEAM_HUNTERS, "Fresh", { Yo = "h/yo.wav" })
check("normal add still works", PHX.TAUNTS.Fresh and PHX.TAUNTS.Fresh[TEAM_HUNTERS].Yo, "h/yo.wav")
check("  ... and caches it", PHX.CachedTaunts[TEAM_HUNTERS].Yo, "h/yo.wav")

print("\n== #33: two scan folders sharing a category name must merge ==")
-- A fake sound/ tree: two workshop packs with a "memes" category for props.
local FS = {
  ["sound/packa"] = {}, ["sound/packa/2"] = { dirs = { "memes" } },
  ["sound/packa/2/memes"] = { wav = { "bruh.wav", "same.wav" } },
  ["sound/packa/1"] = { dirs = { "memes" } }, ["sound/packa/1/memes"] = { wav = { "hunt.wav" } },
  ["sound/packb"] = {}, ["sound/packb/2"] = { dirs = { "memes" } },
  ["sound/packb/2/memes"] = { wav = { "oof.wav", "same.wav" }, mp3 = { "taunt_big_one.mp3" } },
}
file.Exists = function(p) return FS[p] ~= nil end
file.Find = function(pattern)
  local dir, what = pattern:match("^(.-)/%*(.*)$")
  local node = FS[dir] or {}
  if what == "" then return {}, node.dirs or {} end
  return node[what:sub(2)] or {}, {}
end
list.Get = function(name)
  if name == "PHX.TauntScanFolder" then return { ["Pack A"] = "packa", ["Pack B"] = "packb" } end
  return {}
end

-- net: record what is written, byte-accurately enough to size each message
local wire
net.Start = function(n) S.net.cur = { name = n, data = {}, bytes = 0 } end
net.WriteUInt = function(v, bits)
  table.insert(S.net.cur.data, v % (2 ^ bits))   -- the engine truncates, it doesn't grow
  S.net.cur.bytes = S.net.cur.bytes + bits / 8
end
net.WriteData = function(d, len)
  table.insert(S.net.cur.data, d:sub(1, len))
  S.net.cur.bytes = S.net.cur.bytes + len
end
net.Send = function(p) S.net.cur.to = p; table.insert(S.net.sent, S.net.cur) end
net.ReadUInt = function() return table.remove(wire, 1) end
net.ReadData = function(n) return (table.remove(wire, 1)):sub(1, n) end

local managed, payload, compressedFrom, decompressed = {}, "", nil, nil
PHX.ManageTaunt = function(_, cat, data) managed[cat] = data end
util.PHXQuickCompress = function(t) compressedFrom = t; return payload, #payload end
util.PHXQuickDecompress = function(s) decompressed = s; return { Memes = {} } end
S.boolCVar("ph_enable_taunt_scanner", "1")
S.boolCVar("ph_include_default_taunt", "0")

S.hooks = {}
loadblocks("sh_tauntscanner.lua@server", extract(SCANNER, "1-99999"))
local serverReq = S.receivers["PHX.scan_ReqTaunts"]
payload = "x"
S.fire("Initialize")

local memes = managed["Memes"] or {}
local props = memes[TEAM_PROPS] or {}
check("pack A's prop taunt survives pack B", props["Bruh"], "packa/2/memes/bruh.wav")
check("pack B's prop taunt is there too", props["Oof"], "packb/2/memes/oof.wav")
check("pack B's mp3 (taunt_ prefix) too", props["Big One"], "packb/2/memes/taunt_big_one.mp3")
check("name clash -> the first folder wins", props["Same"], "packa/2/memes/same.wav")
check("pack A's hunter taunts kept (cross-team)", memes[TEAM_HUNTERS] and memes[TEAM_HUNTERS]["Hunt"], "packa/1/memes/hunt.wav")
check("the same table is what gets sent", compressedFrom and compressedFrom.Memes == memes, true)

print("\n== #152/#211: the scanned list survives a transfer over 64KB ==")
SERVER, CLIENT = false, true
loadblocks("sh_tauntscanner.lua@client", extract(SCANNER, "1-99999"))
SERVER, CLIENT = true, false
local clientRecv = S.receivers["PHX.scan_SendTauntLists"]

local function transfer(data)
  payload, decompressed, S.net.sent, S.timers = data, nil, {}, {}
  S.fire("Initialize")
  local ply = S.Player{ name = "joiner" }
  serverReq(0, ply)
  for _ = 1, 200 do S.pump(0.1) if #S.timers == 0 then break end end
  local sent, biggest = 0, 0
  for _, m in ipairs(S.net.sent) do
    if m.name == "PHX.scan_SendTauntLists" then
      sent = sent + 1
      biggest = math.max(biggest, m.bytes)
      wire = {}
      for i, v in ipairs(m.data) do wire[i] = v end
      clientRecv(m.bytes * 8)
    end
  end
  return sent, biggest
end

math.randomseed(7)
local big = {}
for i = 1, 150000 do big[i] = string.char(math.random(0, 255)) end
big = table.concat(big)
local sent, biggest = transfer(big)
check("150KB list -> split over several messages", sent, 3)
check("every message fits GMod's 64KB cap", biggest <= 65533, true)
check("client reassembles it byte for byte", decompressed == big, true)

local tiny = "tiny\0list"
sent, biggest = transfer(tiny)
check("tiny list -> one message", sent, 1)
check("tiny list -> arrives intact", decompressed == tiny, true)
check("exactly at the slice size -> one message", transfer(string.rep("a", 60000)), 1)
check("  ... intact", decompressed == string.rep("a", 60000), true)

-- the request is still once per connection
local ply = S.Player{ name = "again" }
S.net.sent, S.timers = {}, {}
serverReq(0, ply); for _ = 1, 20 do S.pump(0.1) end
local first = #S.net.sent
serverReq(0, ply); for _ = 1, 20 do S.pump(0.1) end
check("a second request sends nothing more", #S.net.sent, first)

report()
