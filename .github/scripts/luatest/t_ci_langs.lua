dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

print("\n== every translation formats with the arguments the server sends ==")
-- string.format has no positional arguments, so a translation that reorders
-- its specifiers hands each argument to the wrong one: %d given the team name
-- raises on the client, and two swapped %s print the sentence inside out.
-- Load every shipped language and format those keys the way the code does.
local here = debug.getinfo(1, "S").source:match("@(.*/)") or "./"
local DIR = "gamemodes/prop_hunt/gamemode/langs/"
local ls = io.popen('ls "' .. here .. "../../../" .. DIR .. '"')
for f in ls:lines() do
  if f:match("%.lua$") then loadblocks(f, extract(DIR .. f, "1-999999")) end
end
ls:close()

local codes = {}
for code in pairs(PHX.LANGUAGES) do codes[#codes + 1] = code end
table.sort(codes)
check("language files loaded", #codes >= 12, true)

-- Format key the way the server does, then check that each argument landed
-- where the english sentence puts it.
local function formats(L, key, want, ...)
  if L[key] == nil then return "absent (falls back to english)" end
  local ok, s = pcall(string.format, L[key], ...)
  if not ok then return "ERROR: " .. tostring(s) end
  for _, piece in ipairs(want) do
    if not s:find(piece, 1, true) then return "missing '" .. piece .. "' in: " .. s end
  end
  return "ok"
end

for _, code in ipairs(codes) do
  local L = PHX.LANGUAGES[code]
  -- init.lua: PHXChatInfo( "NOTICE", "BLIND_RESPAWN_TEAM", <team name>, <seconds> )
  local blind = formats(L, "BLIND_RESPAWN_TEAM", { "TEAMNAME", "12" }, "TEAMNAME", 12)
  check(code .. " BLIND_RESPAWN_TEAM (team name, seconds)",
        blind == "absent (falls back to english)" and "ok" or blind, "ok")
  -- sv_items.lua: SVTranslate( pl, "LD_PRESS2SHOOT", <button>, <item name> ),
  -- and every language shows the button in brackets.
  local shoot = formats(L, "LD_PRESS2SHOOT", { "[BUTTON]", "ITEM" }, "BUTTON", "ITEM")
  check(code .. " LD_PRESS2SHOOT (button, item)",
        shoot == "absent (falls back to english)" and "ok" or shoot, "ok")
end

print("\n== every notice rtv.lua sends is still translated ==")
-- PHXM_MV_VOTEROCKED lost its last reader and was removed. check_langs.py only
-- compares the files with each other, so a key deleted from all 12 passes it.
-- CHAT_STARTING_MAPVOTE is borrowed from the end of the game.
local rtvKeys = {}
local rtvSrc = extract("gamemodes/prop_hunt/gamemode/mapvote/rtv.lua", "1-999999")
for _, rx in ipairs({ '"(PHXM_[%w_]+)"', '"(CHAT_[%w_]+)"' }) do
  for key in rtvSrc:gmatch(rx) do rtvKeys[key] = true end
end
rtvKeys = table.GetKeys(rtvKeys)
table.sort(rtvKeys)
check("rtv.lua's keys were found", #rtvKeys >= 5, true)
for _, key in ipairs(rtvKeys) do
  local have = 0
  for _, code in ipairs(codes) do
    if type(PHX.LANGUAGES[code][key]) == "string" then have = have + 1 end
  end
  check(key .. " in every language", have, #codes)
end

report()
