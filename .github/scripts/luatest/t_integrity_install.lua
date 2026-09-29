dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- The integrity checker reads each gamemode's .txt to confirm it is PH:X's. It
-- read only the THIRDPARTY path, so a gamemode installed straight into
-- garrysmod/gamemodes/ (as the smoke test installs it) read as missing and the
-- server logged "PH:X (may be) stopped working" on every boot.
--
-- Which path IDs can see a file, as measured on a real srcds with file.Read:
--   garrysmod/gamemodes/<gm>/     GAME, MOD
--   garrysmod/addons/<x>/         THIRDPARTY, GAME
--   a mounted .gma (Workshop)     THIRDPARTY, GAME, WORKSHOP
local LAYOUT = { direct = { "GAME", "MOD" }, addon = { "THIRDPARTY", "GAME" },
                 workshop = { "THIRDPARTY", "GAME", "WORKSHOP" } }

local IG = "lua/autorun/!!sh_phx_integrity.lua"
local REPO = (debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "../../../"
local function slurp(p)
  local f = assert(io.open(REPO .. p, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local FRETTA, PH = "gamemodes/base_phx/base_phx.txt", "gamemodes/prop_hunt/prop_hunt.txt"
-- The shipped files, so a txt that loses its isphx key fails here too.
local GOOD = { [FRETTA] = slurp(FRETTA), [PH] = slurp(PH) }
-- The original Prop Hunt: same folder name, no isphx key.
local OTHER = '"prop_hunt"\n{\n\t"base"\t\t"fretta13"\n\t"title"\t\t"Prop Hunt"\n}\n'

-- The body of the root key with keys lower-cased, as util.KeyValuesToTable.
util.KeyValuesToTable = function(s)
  local t = {}
  for k, v in s:gmatch('"([^"]*)"%s+"([^"]*)"') do t[k:lower()] = v end
  return t
end
check("harness: shipped base_phx.txt says isphx", util.KeyValuesToTable(GOOD[FRETTA]).isphx, "1")
check("harness: shipped prop_hunt.txt says isphx", util.KeyValuesToTable(GOOD[PH]).isphx, "1")
check("harness: the other prop_hunt.txt does not", util.KeyValuesToTable(OTHER).isphx, nil)

-- A filesystem keyed by path ID. Every read is logged as "ID:path".
local mounts, reads = {}, {}
local function reset() mounts, reads = { DATA = {} }, {} end
local function put(ids, path, text)
  for _, id in ipairs(ids) do
    mounts[id] = mounts[id] or {}
    mounts[id][path] = text
  end
end
local function install(layout, fretta, ph)
  put(LAYOUT[layout], FRETTA, fretta or GOOD[FRETTA])
  put(LAYOUT[layout], PH, ph or GOOD[PH])
end
file.Read = function(p, id)
  reads[#reads + 1] = tostring(id) .. ":" .. p
  return mounts[id] and mounts[id][p]
end
file.Exists = function(p, id)
  if id == "LUA" then return true end
  return mounts[id] ~= nil and mounts[id][p] ~= nil
end
file.Write = function(p, d) mounts.DATA[p] = d end
file.Find = function() return {}, { "base", "base_phx", "prop_hunt", "sandbox" } end

reset()
file.Read("x", "GAME")
check("harness: reads are logged with their path ID", reads[1], "GAME:x")

local SRC = extractAll(IG, { [[^local function ReadGamemodeTXT]], [[^local function CheckGamemodeTXT]] })
-- A fresh copy per call, so ErrorList starts empty. Returns the count, the
-- errors joined, and the reads it made.
local function checkTXT()
  local fn, list = loadchunk("local ErrorList = {}\n" .. SRC .. "\nreturn CheckGamemodeTXT, ErrorList",
    "integrity@CheckGamemodeTXT")()
  reads = {}
  local n = fn()
  return n, table.concat(list, " | "), table.concat(reads, " ")
end

print("\n== CheckGamemodeTXT: where the gamemode is installed ==")
SERVER, CLIENT = true, false
reset(); install("direct")
local n, errs, how = checkTXT()
check("installed in garrysmod/gamemodes -> no errors", n, 0)
check("  ... nothing reported", errs, "")
check("  ... THIRDPARTY tried first, then GAME", how,
  "THIRDPARTY:" .. FRETTA .. " GAME:" .. FRETTA .. " THIRDPARTY:" .. PH .. " GAME:" .. PH)

reset(); install("addon")
n, errs, how = checkTXT()
check("installed as an addon -> no errors", n, 0)
check("  ... read from THIRDPARTY alone", how, "THIRDPARTY:" .. FRETTA .. " THIRDPARTY:" .. PH)

reset(); put({ "THIRDPARTY" }, FRETTA, GOOD[FRETTA]); put({ "THIRDPARTY" }, PH, GOOD[PH])
check("files only on THIRDPARTY -> no errors", checkTXT(), 0)

reset(); put({ "GAME" }, FRETTA, GOOD[FRETTA]); put({ "GAME" }, PH, GOOD[PH])
check("files only on GAME -> no errors", checkTXT(), 0)

reset()
n, errs = checkTXT()
check("files on neither -> both reported", n, 2)
check("  ... fretta's cannot be read", errs:find("Cannot read fretta's", 1, true) ~= nil, true)
check("  ... prop_hunt's cannot be read", errs:find("Cannot read prop_hunt's", 1, true) ~= nil, true)

print("\n== CheckGamemodeTXT: the isphx check is unchanged ==")
reset(); install("direct", nil, OTHER)
n, errs = checkTXT()
check("gamemodes/ prop_hunt without isphx -> reported", n, 1)
check("  ... as a different prop_hunt", errs, "Found different prop_hunt version, using different gamemode detected")

reset(); install("addon", nil, OTHER)
check("addon prop_hunt without isphx -> reported", checkTXT(), 1)

reset(); install("direct", OTHER)
n, errs = checkTXT()
check("base_phx without isphx -> reported", n, 1)
check("  ... as a different fretta", errs, "Found different fretta version, using different gamemode detected")

-- An addon shipping its own prop_hunt.txt is the copy that has to be checked,
-- whichever of the two GAME would hand back. Here GAME has the good one.
reset(); install("direct"); put({ "THIRDPARTY" }, PH, OTHER)
check("addon's non-PH:X copy over a good install -> reported", checkTXT(), 1)

print("\n== CheckGamemodeTXT on a client ==")
-- The gamemode reaches players as the Workshop addon the server pushes, which
-- mounts like any .gma and ships both txt files with isphx set.
SERVER, CLIENT = false, true
reset(); install("workshop")
n, errs, how = checkTXT()
check("client with the Workshop download -> no errors", n, 0)
check("  ... read from THIRDPARTY alone", how, "THIRDPARTY:" .. FRETTA .. " THIRDPARTY:" .. PH)
reset(); install("workshop", nil, OTHER)
check("client whose Workshop copy is not PH:X -> reported", checkTXT(), 1)
SERVER, CLIENT = true, false

print("\n== the whole file: what the server's console shows ==")
-- The smoke test fails on the banner the checker prints, so bind to the text
-- the workflow greps for rather than a copy of it.
local NEEDLE = slurp(".github/workflows/smoke-test.yml"):match("grep %-[%a]*F[%a]* [^']*'([^']+)' console%.log")
check("harness: the workflow's integrity grep was found", NEEDLE, "[PH:X Integrity Check] Error")

local dialogs = 0
local function panel()
  return setmetatable({}, { __index = function() return function() return panel() end end })
end
vgui = { Create = function() dialogs = dialogs + 1; return panel() end }
IS_PHX, GAMEMODE = true, { IS_PROPER_PHX_INSTALLED = true }
-- Inside the two-day cache window, so the conflict check runs without http.
cookie.GetNumber = function() return os.time() + 3600 end

-- Boot with the whole file and return everything it printed, one string.
local function boot()
  local out, realPrint = {}, print
  local function say(...)
    local parts = {}
    for i = 1, select("#", ...) do
      local v = select(i, ...)
      if type(v) ~= "table" then parts[#parts + 1] = tostring(v) end
    end
    out[#out + 1] = table.concat(parts)
  end
  S.hooks, S.timers, dialogs = {}, {}, 0
  loadblocks("integrity.lua", extract(IG, "1-99999"))
  MsgC, print = say, say
  S.fire("InitPostEntity")
  local thrown = S.pump(1)
  MsgC, print = function() end, realPrint
  return table.concat(out, "\n"), #thrown
end

reset(); install("direct")
local log, thrown = boot()
check("gamemodes/ install boots without the error banner", NEEDLE ~= nil and log:find(NEEDLE, 1, true), nil)
check("  ... says no errors found", log:find("No errors found", 1, true) ~= nil, true)
check("  ... nothing thrown", thrown, 0)

reset(); install("addon")
log = boot()
check("addon install boots without the error banner", NEEDLE ~= nil and log:find(NEEDLE, 1, true), nil)

reset()
log = boot()
check("gamemode txt unreadable -> banner printed", NEEDLE ~= nil and log:find(NEEDLE, 1, true) ~= nil, true)
check("  ... counting both reads and the summary", log:find("There was 3 Errors found!", 1, true) ~= nil, true)

SERVER, CLIENT = false, true
reset(); install("workshop")
log = boot()
check("client with the Workshop download -> no banner", NEEDLE ~= nil and log:find(NEEDLE, 1, true), nil)
check("  ... and no warning window", dialogs, 0)
reset()
boot()
check("client that cannot see the files -> warning window", dialogs, 1)
SERVER, CLIENT = true, false

report()
