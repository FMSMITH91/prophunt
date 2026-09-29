dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

print("\n== extract.py must not change what the extracted GLua does ==")
-- Every behaviour test runs code through this translator, so a translation
-- that quietly drops or rewrites code makes tests pass against code GMod
-- never runs. Each case here used to translate wrongly.
local F = ".github/scripts/luatest/fixtures/glua_translate.lua"

-- Extract one fixture function, call it, and return its result or the error.
local function run(name, ...)
  local args = { ... }
  local ok, res = pcall(function()
    -- Unanchored on purpose: the commented-out copy must be skipped, not matched.
    local src = extract(F, "local function " .. name .. "\\(")
    return loadchunk(src .. "\nreturn " .. name, name)()(unpack(args))
  end)
  if ok then return res end
  return "ERROR: " .. tostring(res)
end

check("//[[ stays a line comment, the code after it runs", run("lineCommentBracket"), 2)
check("/* */ containing ]] is one whole comment", run("blockCommentBrackets"), 1)
check("! x (bang, space) negates: false", run("bangWithSpace", false), "negated")
check("! x (bang, space) negates: true", run("bangWithSpace", true), "kept")
check("a spec skips a commented-out copy", run("commentedOut"), "the real one")

report()
