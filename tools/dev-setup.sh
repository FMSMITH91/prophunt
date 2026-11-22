#!/usr/bin/env bash
# Installs the local editing tools for this repo. Safe to rerun.
#
#   glualint             -> ~/.local/bin/glualint, the same pinned build CI uses.
#                           Version and SHA-256 are read from
#                           .github/workflows/glualint.yml, so a bump there is
#                           the only bump needed.
#   Garry's Mod API defs -> .luals/glua-api/ (gitignored), the type annotations
#                           .luarc.json points lua-language-server at.
#
# Both are pinned and checked by SHA-256 before use (OWASP Software Supply Chain
# Security Cheat Sheet: Lockfile/Version Pinning). Neither project publishes
# signatures or build attestations, so a pinned checksum is the strongest check
# available. To bump the defs, take the tag and the .lua.zip digest from
#   gh release view -R luttje/glua-api-snippets --json tagName,assets
set -euo pipefail

GLUA_API_TAG='2026-11-16_17-28-50'
GLUA_API_SHA256='43cfeb108deb94372f5ce02481bd117e36cae7c6fc0dccd8438fb96b7c4b4864'

repo=$(cd "$(dirname "$0")/.." && pwd)
bindir="${HOME}/.local/bin"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fetch() { # url sha256 dest
    curl -fsSL --retry 3 -o "$3" "$1"
    echo "$2  $3" | sha256sum --check --strict --quiet
}

# --- glualint ---------------------------------------------------------------
wf="$repo/.github/workflows/glualint.yml"
gl_ver=$(sed -nE "s/^ *GLUALINT_VERSION: *'([^']+)'.*/\1/p" "$wf")
gl_sha=$(sed -nE "s/^ *GLUALINT_SHA256: *'([0-9a-f]{64})'.*/\1/p" "$wf")
[[ -n "$gl_ver" && -n "$gl_sha" ]] || { echo "Could not read the glualint pin from $wf" >&2; exit 1; }

if [[ -x "$bindir/glualint" ]] && "$bindir/glualint" --version 2>/dev/null | grep -qF "$gl_ver"; then
    echo "glualint $gl_ver already installed"
else
    fetch "https://github.com/FPtje/GLuaFixer/releases/download/${gl_ver}/glualint-${gl_ver}-x86_64-linux.zip" \
          "$gl_sha" "$tmp/glualint.zip"
    unzip -q -o "$tmp/glualint.zip" -d "$tmp/glualint"
    mkdir -p "$bindir"
    install -m 0755 "$tmp/glualint/glualint" "$bindir/glualint"
    echo "Installed glualint $gl_ver to $bindir"
fi

# --- Garry's Mod API definitions ---------------------------------------------
dest="$repo/.luals/glua-api"
if [[ -f "$dest/.tag" && "$(cat "$dest/.tag")" == "$GLUA_API_TAG" ]]; then
    echo "Garry's Mod API defs $GLUA_API_TAG already installed"
else
    fetch "https://github.com/luttje/glua-api-snippets/releases/download/${GLUA_API_TAG}/${GLUA_API_TAG}.lua.zip" \
          "$GLUA_API_SHA256" "$tmp/defs.zip"
    rm -rf "$dest"
    mkdir -p "$dest"
    unzip -q "$tmp/defs.zip" -d "$dest"
    echo "$GLUA_API_TAG" > "$dest/.tag"
    echo "Installed Garry's Mod API defs $GLUA_API_TAG to $dest"
fi
