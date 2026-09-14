#!/usr/bin/env bash
# Run the PH:X Lua behaviour tests, then parse-check every gamemode file.
#
# These execute the SHIPPED functions under a stubbed Garry's Mod (see shim.lua)
# using LuaJIT, which is the same Lua 5.1 dialect GMod runs. glualint and Codacy
# both pass code that errors the instant a player touches it; this is the layer
# that catches that.
set -uo pipefail
cd "$(dirname "$0")"

LUA=${LUA:-luajit}
if ! command -v "$LUA" >/dev/null 2>&1; then
  if command -v lua5.1 >/dev/null 2>&1; then LUA=lua5.1
  else echo "::error::no luajit or lua5.1 on PATH"; exit 1; fi
fi

rc=0

echo "=== behaviour tests ($LUA) ==="
for t in t_*.lua; do
  out=$("$LUA" "$t" 2>&1)
  if echo "$out" | grep -qE "^  FAIL|^${LUA}:|EMPTY (EXTRACT|CHUNK)"; then
    echo "--- $t"; echo "$out" | sed 's/^/  /'; rc=1
  else
    printf '  ok  %-20s %s\n' "$t" "$(echo "$out" | grep -E 'passed,' | tr -d ' ')"
  fi
done

echo
echo "=== parse check (every gamemode + autorun Lua file) ==="
bad=0
while IFS= read -r f; do
  if ! EXTRACT_PARSE_ONLY=1 python3 extract.py "$f" 1-999999 > /tmp/phx_parse.lua 2>/dev/null; then
    echo "  ::error file=$f::could not extract"; bad=$((bad + 1)); rc=1; continue
  fi
  [ -s /tmp/phx_parse.lua ] || continue
  if ! err=$("$LUA" -bl /tmp/phx_parse.lua /dev/null 2>&1); then
    echo "  ::error file=$f::$(echo "$err" | head -1)"; bad=$((bad + 1)); rc=1
  fi
done < <(cd ../../.. && find gamemodes lua -name '*.lua' | sort)
[ "$bad" -eq 0 ] && echo "  all files parse"

exit $rc
