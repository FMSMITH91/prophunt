#!/usr/bin/env bash
# Run the PH:X Lua behaviour tests, then parse-check every gamemode file.
#
# These execute the SHIPPED functions under a stubbed Garry's Mod (see shim.lua)
# using LuaJIT, which is the same Lua 5.1 dialect GMod runs. glualint and Codacy
# both pass code that errors the instant a player touches it; this is the layer
# that catches that.
set -uo pipefail
cd "$(dirname "$0")" || exit 1

LUA=${LUA:-luajit}
if ! command -v "$LUA" >/dev/null 2>&1; then
  if command -v lua5.1 >/dev/null 2>&1; then LUA=lua5.1
  else echo "::error::no luajit or lua5.1 on PATH"; exit 1; fi
fi
# Some LuaJIT builds accept GLua's != && || ! themselves. Under one of those a
# gap in extract.py's translation cannot fail here, only later in CI.
if echo 'return 1 != 2' | "$LUA" - >/dev/null 2>&1; then
  echo "::warning::$LUA accepts GLua syntax, so translation mistakes pass here; rerun with LUA=lua5.1 to catch them"
fi

tmp=$(mktemp) || exit 1
trap 'rm -f "$tmp"' EXIT

rc=0

echo "=== behaviour tests ($LUA) ==="
for t in t_*.lua; do
  out=$("$LUA" "$t" 2>&1)
  status=$?
  # The exit status as well as the output: an interpreter that dies without
  # printing a FAIL line (a crash, an os.exit(1)) must not read as a pass.
  if [ "$status" -ne 0 ] || echo "$out" | grep -qE "^  FAIL|^${LUA}:|EMPTY (EXTRACT|CHUNK)"; then
    # Indent via parameter expansion rather than sed (ShellCheck SC2001).
    echo "--- $t (exit $status)"; echo "  ${out//$'\n'/$'\n'  }"; rc=1
  else
    printf '  ok  %-20s %s\n' "$t" "$(echo "$out" | grep -E 'passed,' | tr -d ' ')"
  fi
done

echo
echo "=== parse check (every gamemode + autorun Lua file) ==="
# Compile without running, through loadfile rather than `luajit -bl`, which
# lua5.1 does not have. The path goes in via the environment, never the code.
parse='local f, e = loadfile(os.getenv("PHX_PARSE_FILE")) if not f then io.stderr:write(e, "\n") os.exit(1) end'
bad=0
while IFS= read -r f; do
  if ! EXTRACT_PARSE_ONLY=1 python3 extract.py "$f" 1-999999 > "$tmp" 2>/dev/null; then
    echo "  ::error file=$f::could not extract"; bad=$((bad + 1)); rc=1; continue
  fi
  [ -s "$tmp" ] || continue
  if ! err=$(PHX_PARSE_FILE="$tmp" "$LUA" -e "$parse" 2>&1); then
    echo "  ::error file=$f::$(echo "$err" | head -1)"; bad=$((bad + 1)); rc=1
  fi
done < <(cd ../../.. && find gamemodes lua -name '*.lua' | sort)
[ "$bad" -eq 0 ] && echo "  all files parse"

exit $rc
