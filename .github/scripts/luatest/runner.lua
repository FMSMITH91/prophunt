-- Test scaffolding. Every test file starts with dofile("runner.lua").
local here = (debug.getinfo(1, "S").source:match("@(.*/)") or "./")

S = dofile(here .. "shim.lua")

local pass, fail = 0, 0

function check(name, got, want)
  if got == want then
    pass = pass + 1
    print(("  PASS  %-56s %s"):format(name, tostring(got)))
  else
    fail = fail + 1
    print(("  FAIL  %-56s got=%s want=%s"):format(name, tostring(got), tostring(want)))
  end
end

function report()
  print(("\n  %d passed, %d failed"):format(pass, fail))
  if fail > 0 then os.exit(1) end
end

-- Pull a block out of a real repo file and translate it to stock Lua.
function extract(path, spec)
  local cmd = ("python3 %sextract.py '%s' '%s'"):format(here, path, spec)
  local h = io.popen(cmd)
  local src = h:read("*a")
  h:close()
  -- An empty extract means the extractor failed. Without this the chunk loads
  -- fine, defines nothing, and every assertion silently passes or reads zero.
  if not src or src:match("^%s*$") then
    error("EMPTY EXTRACT: " .. path .. " :: " .. spec, 2)
  end
  return src
end

-- Extract several blocks from one file and concatenate them, in order.
function extractAll(path, specs)
  local parts = {}
  for _, spec in ipairs(specs) do parts[#parts + 1] = extract(path, spec) end
  return table.concat(parts, "\n")
end

function loadchunk(src, name)
  if not src or src:match("^%s*$") then
    error("EMPTY CHUNK for " .. (name or "chunk"), 2)
  end
  local f, err = loadstring(src, name or "chunk")
  if not f then error("compile error in " .. (name or "chunk") .. ": " .. tostring(err)) end
  return f
end

-- Load one or more extracted blocks, optionally with a prelude.
function loadblocks(name, src, prelude)
  return loadchunk((prelude or "") .. "\n" .. src, name)()
end

-- Run fn, returning "ok" or the error message with its file:line prefix stripped.
function attempt(fn, ...)
  local ok, err = pcall(fn, ...)
  if ok then return "ok" end
  return (tostring(err):gsub("^.-:%d+: ", ""))
end
