dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- Every behaviour test runs on shim.lua, so a place where it differs from GMod
-- is a place where a test can pass against code that fails on a server, or
-- fail against code that works. Each case here either used to differ or pins
-- down behaviour that other tests rely on.

-- fn's result, or its error as a string, so a missing function fails by name.
local function try(fn, ...)
  local ok, res = pcall(fn, ...)
  if ok then return res end
  return "ERROR: " .. tostring(res)
end

print("\n== IsValid: a falsy argument is invalid, not an error ==")
-- includes/util.lua returns false for it. Panels often start out as `false`.
check("IsValid(false)", try(IsValid, false), false)
check("IsValid(nil)", try(IsValid, nil), false)
check("IsValid(NULL)", try(IsValid, NULL), false)
check("IsValid(player)", try(IsValid, S.Player{}), true)

print("\n== timer.Create replaces a timer of the same name ==")
S.timers = {}
local fired = 0
timer.Create("t", 5, 1, function() fired = fired + 1 end)
timer.Create("t", 10, 1, function() fired = fired + 10 end)
S.pump(5)
check("the replaced timer does not fire on its old deadline", fired, 0)
S.pump(5)
check("only the replacement fires", fired, 10)

print("\n== one S.pump is one tick ==")
-- GMod runs a timer created during a tick on a later tick, even at delay 0.
-- Tests rely on this to change the world in between, e.g. to kill a player
-- after a timer is queued for them and before it runs.
S.timers = {}
local order = {}
timer.Simple(1, function()
  order[#order + 1] = "outer"
  timer.Simple(0, function() order[#order + 1] = "next tick" end)
end)
S.pump(1)
check("a timer queued at 0 during a pump waits", table.concat(order, ","), "outer")
S.pump(0)
check("  and runs on the next pump", table.concat(order, ","), "outer,next tick")

print("\n== hook.GetTable, player.GetHumans, Player:UserID ==")
hook.Add("Think", "a", print)
S.hooks = {}
hook.Add("Tick", "b", print)
check("hook.GetTable reads the current hooks",
      try(function() local h = hook.GetTable() return h.Tick.b == print and h.Think == nil end), true)
local human, bot = S.Player{ name = "human" }, S.Player{ name = "bot", bot = true }
S.players = { human, bot, { _name = "stand-in" } }
check("player.GetHumans leaves out bots", try(function()
  local names = {}
  for _, p in ipairs(player.GetHumans()) do names[#names + 1] = p._name end
  return table.concat(names, ",")
end), "human,stand-in")
S.players = {}
check("each player has its own UserID",
      try(function() return type(human:UserID()) == "number" and human:UserID() ~= bot:UserID() end), true)
check("a test can name the UserID", try(function() return S.Player{ uid = 7 }:UserID() end), 7)

print("\n== string.Explode and string.Trim, as includes/extensions/string.lua ==")
local function split(...) return table.concat(string.Explode(...), "|") .. " (" .. #string.Explode(...) .. ")" end
check("Explode keeps empty fields", try(split, ",", "a,,b"), "a||b (3)")
check("Explode splits on a plain '.'", try(split, ".", "a.b"), "a|b (2)")
check("Explode with a pattern", try(split, "%s+", "a  b", true), "a|b (2)")
check("Explode on '' splits characters", try(split, "", "ab"), "a|b (2)")
check("Explode with no separator in it", try(split, " ", "ab"), "ab (1)")
check("Trim spaces", try(string.Trim, "  x y \n"), "x y")
check("Trim a character, even a magic one", try(function() return ("..x.."):Trim(".") end), "x")

report()
