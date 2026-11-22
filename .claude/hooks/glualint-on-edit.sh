#!/usr/bin/env bash
# PostToolUse hook: lint a .lua file right after Claude edits it, with the same
# glualint build and glualint.json that CI uses. Only errors are reported (CI
# fails on errors only; warnings stay annotations), and they reach Claude via
# exit code 2. Install glualint with tools/dev-setup.sh.
set -uo pipefail

file=$(python3 -I -c 'import json,sys; print((json.load(sys.stdin).get("tool_input") or {}).get("file_path") or "")') || exit 0
[[ "$file" == *.lua && -f "$file" ]] || exit 0

project="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
case "$(realpath "$file")" in "$(realpath "$project")"/*) ;; *) exit 0 ;; esac

glualint=$(command -v glualint || echo "${HOME}/.local/bin/glualint")
if [[ ! -x "$glualint" ]]; then
    echo "glualint is not installed; run tools/dev-setup.sh" >&2
    exit 0
fi

cd "$project" || exit 0
if ! out=$("$glualint" --config glualint.json lint "$file" 2>&1); then
    { echo "glualint found errors in $file (CI will fail on these):"
      grep -F '[Error]' <<<"$out" || echo "$out"; } >&2
    exit 2
fi
exit 0
