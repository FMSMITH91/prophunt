#!/usr/bin/env python3
"""Report inconsistencies between english.lua and the other translations.

Checks, per language directory:
  * keys present in a translation but missing from english.lua  (usually a typo
    in the key name, e.g. "HUD-HUD_TEAMWIN" instead of "HUD_TEAMWIN")
  * keys present in english.lua but missing from a translation   (falls back to
    english at runtime, so cosmetic)
  * a different number of printf-style specifiers than english   (a translation
    with MORE specifiers than the code supplies makes string.format error)

This is a gate: with STRICT set it exits non-zero on any inconsistency. The
backlog it was written to report is clear, so anything it finds now is drift.
"""
import os
import re
import sys
import glob

STRICT = True

LANG_DIRS = [
    "gamemodes/prop_hunt/gamemode/langs",
    "gamemodes/prop_hunt/gamemode/plugins/lps/lang",
]

# Matches:
#   L.KEY     = "..."      (gamemode/langs)
#   L["KEY"]  = "..."      (gamemode/langs)
#   ["KEY"]   = "..."      (plugins/lps/lang, which nests under L["<code>"])
# and the same with the value on the FOLLOWING line, which korean.lua uses for
# 22 of its entries:
#   L["KEY"] =
#       "..."
# Missing that form made the checker report those 22 as untranslated.
KEY_PART = r'(?:L\s*)?(?:\.([A-Za-z_][A-Za-z0-9_]*)|\[\s*"([^"]+)"\s*\])'
VALUE_PART = r'"((?:[^"\\]|\\.)*)"'
ENTRY = re.compile(r'^\s*' + KEY_PART + r'\s*=\s*' + VALUE_PART + r'\s*,?\s*(?:--.*)?$')
ENTRY_OPEN = re.compile(r'^\s*' + KEY_PART + r'\s*=\s*(?:--.*)?$')
VALUE_ONLY = re.compile(r'^\s*' + VALUE_PART + r'\s*,?\s*(?:--.*)?$')
SPEC = re.compile(r"%[-+ #0]*[0-9.]*[sdifgxXqc%]")

# Header metadata, not translatable phrases. english.lua declares AuthorURL as a
# multi-line table, which the single-line matcher cannot see, so files that use a
# plain string for it were reported as having a key english lacks.
METADATA = {"code", "Name", "NameEnglish", "Author", "AuthorURL"}


def load(path):
    entries = {}
    pending = None          # key whose value is on a following line
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.rstrip("\n")

            if pending is not None:
                m = VALUE_ONLY.match(line)
                if m:
                    if pending not in METADATA:
                        entries[pending] = [s for s in SPEC.findall(m.group(1)) if s != "%%"]
                    pending = None
                    continue
                pending = None      # not a value line after all; fall through

            m = ENTRY.match(line)
            if m:
                key = m.group(1) or m.group(2)
                if key not in METADATA:
                    entries[key] = [s for s in SPEC.findall(m.group(3)) if s != "%%"]
                continue

            m = ENTRY_OPEN.match(line)
            if m:
                pending = m.group(1) or m.group(2)
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

            # Counted now that the backlog is clear. A missing key falls back to
            # english at runtime rather than erroring, so it annotates as a
            # warning - but it is still a regression, and letting it slide is how
            # 39 keys per language accumulated in the first place.
            for key in missing:
                problems += 1
                print("::warning file=%s::key '%s' is in english.lua but missing here "
                      "(falls back to english at runtime)" % (path, key))

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
