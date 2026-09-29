#!/usr/bin/env python3
"""Report inconsistencies between english.lua and the other translations."""
# Checks, per language directory:
#   * keys present in a translation but missing from english.lua  (usually a typo
#     in the key name, e.g. "HUD-HUD_TEAMWIN" instead of "HUD_TEAMWIN")
#   * keys present in english.lua but missing from a translation   (players using
#     that language get english, or error text where the code calls
#     PHX:Translate, depending on which helper looks the key up)
#   * printf-style specifiers that differ from english in number, order or type.
#     string.format has no positional arguments, so a translation that reorders
#     "%s ... %d" to "%d ... %s" hands the string to %d and errors
# and across directories:
#   * a language the gamemode ships (gamemode/langs) with no file in a plugin's
#     lang directory, or a plugin file for a language code the gamemode never
#     declares (PHX:InsertToLanguage silently skips it)
#
# Parsing lives in langcheck_parse.py. This is a gate: with STRICT set it exits
# non-zero on any inconsistency. The backlog it was written to report is clear,
# so anything it finds now is drift.
import glob
import os
import sys

from langcheck_parse import MAIN_CODE, PLUGIN_CODE, codes, format_issues, load

STRICT = True

# Paths are resolved from this file, not the working directory: run from
# anywhere else, a relative path finds no files and the gate passes vacuously.
REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

MAIN_DIR = "gamemodes/prop_hunt/gamemode/langs"
LANG_DIRS = [
    MAIN_DIR,
    "gamemodes/prop_hunt/gamemode/plugins/lps/lang",
]

# Gaps that are reported but not counted, each with its reason. Remove an entry
# once the file exists - the run prints a notice when one goes stale.
KNOWN_MISSING = {
    ("gamemodes/prop_hunt/gamemode/plugins/lps/lang", "tr"):
        "Last Prop Standing has no Turkish translation yet",
}


def rel(path):
    """Repo-relative path, as GitHub annotations want it."""
    return os.path.relpath(path, REPO).replace(os.sep, "/")


def annotate(level, path, message):
    """Print a GitHub annotation and count it as one problem."""
    print(f"::{level} file={path}::{message}")
    return 1


def check_file(path, en):
    """Compare one translation with english; return its problem count."""
    tr = load(path)
    missing = sorted(k for k in en if k not in tr)
    unknown = sorted(k for k in tr if k not in en)
    formats = format_issues(en, tr)
    print(f"  {os.path.basename(path):<20} keys={len(tr):<4d} missing={len(missing):<4d} "
          f"unknown={len(unknown):<3d} format-diff={len(formats)}")

    # A missing key does not error at runtime, so it annotates as a warning -
    # but it is still a regression, and letting it slide is how 39 keys per
    # language accumulated in the first place.
    notes = ([("warning", f"key '{k}' is in english.lua but missing here (players "
                          "using this language see english or error text)") for k in missing]
             + [("warning", f"key '{k}' is not in english.lua (typo in the key name, "
                            "or a leftover key)") for k in unknown]
             + formats)
    return sum(annotate(level, rel(path), message) for level, message in notes)


def check_dir(base):
    """Compare every translation in base with its english.lua; return problems."""
    english = os.path.join(REPO, base, "english.lua")
    if not os.path.isfile(english):
        return annotate("error", base, "no english.lua here - if the directory moved, update "
                                       "LANG_DIRS in check_langs.py, or this gate checks nothing")
    en = load(english)
    if not en:
        return annotate("error", base, "english.lua has no string keys that check_langs.py "
                                       "can read, so this gate would check nothing")

    print(f"\n== {base} (english.lua: {len(en)} string keys) ==")
    return sum(check_file(path, en)
               for path in sorted(glob.glob(os.path.join(REPO, base, "*.lua")))
               if os.path.basename(path) != "english.lua")


def missing_language(base, code, source):
    """Report a plugin lang directory with no file for `code`; return problems."""
    message = (f"no translation for language '{code}' (declared by {rel(source)}) - "
               "players using it see these strings in english or as error text")
    reason = KNOWN_MISSING.get((base, code))
    if reason:
        print(f"::notice file={base}::{message}. Allowed for now: {reason}")
        return 0
    return annotate("warning", base, message)


def check_coverage():
    """Every plugin lang directory must cover exactly the gamemode's languages."""
    shipped = codes(os.path.join(REPO, MAIN_DIR), MAIN_CODE)
    if not shipped:
        return annotate("error", MAIN_DIR, "no L.code declarations found, so language "
                                           "coverage cannot be checked")
    problems = 0
    for base in LANG_DIRS[1:]:
        plugin = codes(os.path.join(REPO, base), PLUGIN_CODE)
        problems += sum(missing_language(base, code, shipped[code])
                        for code in sorted(set(shipped) - set(plugin)))
        problems += sum(annotate("warning", rel(plugin[code]),
                                 f"L[\"{code}\"] matches no L.code in {MAIN_DIR}, so "
                                 "PHX:InsertToLanguage skips these strings")
                        for code in sorted(set(plugin) - set(shipped)))
        for code in sorted(c for d, c in KNOWN_MISSING if d == base and c in plugin):
            print(f"::notice file={rel(plugin[code])}::'{code}' is translated now - remove "
                  "its KNOWN_MISSING entry from check_langs.py")
    return problems


def main():
    """Run every check and return the exit status."""
    problems = sum(check_dir(base) for base in LANG_DIRS) + check_coverage()
    print(f"\n{problems} inconsistenc{'y' if problems == 1 else 'ies'} reported.")
    return 1 if STRICT and problems else 0


if __name__ == "__main__":
    sys.exit(main())
