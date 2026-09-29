"""Reading and comparing PH:X language files, for check_langs.py.

Kept in its own module because Codacy grades each file on its total complexity.
"""
import glob
import os
import re

# Whitespace that stays on one line.
SP = r"[^\S\n]*"

# Matches:
#   L.KEY     = "..."      (gamemode/langs)
#   L["KEY"]  = "..."      (gamemode/langs)
#   ["KEY"]   = "..."      (plugins/lps/lang, which nests under L["<code>"])
# and the same with the value on the FOLLOWING line, which korean.lua uses for
# 22 of its entries:
#   L["KEY"] =
#       "..."
# Missing that form made the checker report those 22 as untranslated.
KEY_PART = r'(?:L' + SP + r')?(?:\.([A-Za-z_][A-Za-z0-9_]*)|\[' + SP + r'"([^"\n]+)"' + SP + r'\])'
VALUE_PART = r'"((?:[^"\\\n]|\\.)*)"'
ENTRY = re.compile(
    r"^" + SP + KEY_PART + SP + r"=" + SP + r"(?:(?:--[^\n]*)?\n" + SP + r")?"
    + VALUE_PART + SP + r",?" + SP + r"(?:--[^\n]*)?$", re.M)
SPEC = re.compile(r"%[-+ #0]*[0-9.]*[sdifgxXqc%]")

# Language codes: `L.code = "tr"` in gamemode/langs, `L["tr"] = {` in a plugin.
MAIN_CODE = re.compile(r'^\s*L\s*\.\s*code\s*=\s*"([^"]+)"', re.M)
PLUGIN_CODE = re.compile(r'^\s*L\s*\[\s*"([^"]+)"\s*\]\s*=\s*\{', re.M)

# What string.format needs in each slot: an integer, a float, or anything
# printable. %d handed a string raises; %s handed a number does not, but it
# still means the sentence reads its arguments in the wrong order.
SPEC_CLASS = {"d": "int", "i": "int", "x": "int", "X": "int", "c": "int",
              "f": "float", "g": "float"}

# Header metadata, not translatable phrases. english.lua declares AuthorURL as a
# multi-line table, which the single-line matcher cannot see, so files that use a
# plain string for it were reported as having a key english lacks.
METADATA = {"code", "Name", "NameEnglish", "Author", "AuthorURL"}


def load(path):
    """{key: [format specifiers]} for every translatable string in a lang file."""
    with open(path, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    return {m.group(1) or m.group(2): [s for s in SPEC.findall(m.group(3)) if s != "%%"]
            for m in ENTRY.finditer(text) if (m.group(1) or m.group(2)) not in METADATA}


def classes(specs):
    """The argument type each specifier asks string.format for, in order."""
    return [SPEC_CLASS.get(s[-1], "any") for s in specs]


def format_issues(en, tr):
    """(level, message) for each key whose specifiers differ from english.lua's."""
    issues = []
    for key in sorted(k for k in tr if k in en):
        want, got = en[key], tr[key]
        if len(want) != len(got):
            # Only "more than english, and english has some" can break
            # string.format. A specifier where english has none is almost
            # always a literal percent sign ("8% chance").
            dangerous = len(got) > len(want) > 0
            issues.append(("error" if dangerous else "warning",
                           f"key '{key}' has {len(got)} format specifier(s), english.lua has "
                           f"{len(want)}" + (" - string.format will error when this key is "
                                             "given arguments" if dangerous else "")))
        elif classes(want) != classes(got):
            issues.append(("error",
                           f"key '{key}' has format specifiers {' '.join(got)} where english.lua "
                           f"has {' '.join(want)} - string.format has no positional arguments, "
                           "so keep english's order and reword the sentence around it"))
    return issues


def codes(directory, pattern):
    """{language code: path of the file declaring it} for the lang files in directory."""
    found = {}
    for path in sorted(glob.glob(os.path.join(directory, "*.lua"))):
        with open(path, encoding="utf-8", errors="replace") as fh:
            for code in pattern.findall(fh.read()):
                found[code] = path
    return found
