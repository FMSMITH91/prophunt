#!/usr/bin/env python3
"""Report inconsistencies between english.lua and the other translations.

Checks, per language directory:
  * keys present in a translation but missing from english.lua  (usually a typo
    in the key name, e.g. "HUD-HUD_TEAMWIN" instead of "HUD_TEAMWIN")
  * keys present in english.lua but missing from a translation   (falls back to
    english at runtime, so cosmetic)
  * a different number of printf-style specifiers than english   (a translation
    with MORE specifiers than the code supplies makes string.format error)

This is a report, not a gate: it always exits 0. Flip STRICT to True once the
existing backlog is clean if you want it to fail the build.
"""
import os
import re
import sys
import glob

STRICT = False

LANG_DIRS = [
    "gamemodes/prop_hunt/gamemode/langs",
    "gamemodes/prop_hunt/gamemode/plugins/lps/lang",
]

# Matches, on a single line:
#   L.KEY     = "..."      (gamemode/langs)
#   L["KEY"]  = "..."      (gamemode/langs)
#   ["KEY"]   = "..."      (plugins/lps/lang, which nests under L["<code>"])
ENTRY = re.compile(
    r'^\s*(?:L\s*)?(?:\.([A-Za-z_][A-Za-z0-9_]*)|\[\s*"([^"]+)"\s*\])\s*=\s*"((?:[^"\\]|\\.)*)"\s*,?\s*(?:--.*)?$'
)
SPEC = re.compile(r"%[-+ #0]*[0-9.]*[sdifgxXqc%]")


def load(path):
    entries = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = ENTRY.match(line.rstrip("\n"))
            if not m:
                continue
            key = m.group(1) or m.group(2)
            entries[key] = [s for s in SPEC.findall(m.group(3)) if s != "%%"]
    return entries


def main():
    problems = 0

    for base in LANG_DIRS:
        english = os.path.join(base, "english.lua")
        if not os.path.isfile(english):
            print("::warning::no english.lua in %s, skipping" % base)
            continue

        en = load(english)
        print("\n== %s (english.lua: %d string keys) ==" % (base, len(en)))

        for path in sorted(glob.glob(os.path.join(base, "*.lua"))):
            if os.path.basename(path) == "english.lua":
                continue

            tr = load(path)
            unknown = sorted(k for k in tr if k not in en)
            missing = sorted(k for k in en if k not in tr)
            mismatch = sorted(
                (k, len(en[k]), len(v)) for k, v in tr.items()
                if k in en and len(en[k]) != len(v)
            )

            print("  %-20s keys=%-4d missing=%-4d unknown=%-3d format-diff=%d"
                  % (os.path.basename(path), len(tr), len(missing), len(unknown), len(mismatch)))

            for key in unknown:
                problems += 1
                print("::warning file=%s::key '%s' is not in english.lua "
                      "(typo in the key name, or a leftover key)" % (path, key))

            for key, want, got in mismatch:
                problems += 1
                # Only the "translation has more than english, and english has
                # some" case can actually break string.format at runtime. A
                # translation with a specifier where english has none is almost
                # always a literal percent sign ("8% chance").
                dangerous = got > want and want > 0
                print("::%s file=%s::key '%s' has %d format specifier(s), "
                      "english.lua has %d%s"
                      % ("error" if dangerous else "warning", path, key, got, want,
                         " - string.format will error when this key is given arguments"
                         if dangerous else ""))

    print("\n%d inconsistenc%s reported." % (problems, "y" if problems == 1 else "ies"))
    return 1 if (STRICT and problems) else 0


if __name__ == "__main__":
    sys.exit(main())
