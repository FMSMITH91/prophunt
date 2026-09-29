"""Lua source helpers for check_net_receivers.py."""
# Everything here works on text that strip_noise() has already cleaned, so a
# keyword inside a comment or a string can never open or close a block. Kept in
# its own module because Codacy grades each file on its total complexity.
import re

OPENERS = re.compile(r"\b(function|do|if)\b")
CLOSERS = re.compile(r"\bend\b")

FUNC_LITERAL = re.compile(r"\bfunction\s*\(([^)]*)\)")
# `["b"] = Helper,` in a dispatch table, minus values that are not functions.
NAMED_ENTRY = re.compile(r"=\s*([A-Za-z_][\w.:]*)\s*[,;}]")
LUA_VALUES = {"true", "false", "nil"}

NOISE = re.compile(
    r"--\[(?P<a>=*)\[.*?\](?P=a)\]"     # --[[ long comment ]]
    r"|/\*.*?\*/"                        # /* C-style comment */
    r"|--[^\n]*"                          # -- line comment
    r"|(?<!:)//[^\n]*"                    # // line comment (not a URL)
    r"|\[(?P<b>=*)\[.*?\](?P=b)\]"       # [[ long string ]]
    r'|"(?:[^"\\\n]|\\.)*"'              # "string"
    r"|'(?:[^'\\\n]|\\.)*'",             # 'string'
    re.S,
)


def strip_noise(src):
    """Blank comments and string bodies, keeping every offset and line intact."""
    # Length-preserving, so offsets in the stripped text still line up with the
    # original file - that is what lets us report accurate line numbers.
    def blank(m):
        text = m.group(0)
        # Keep the quotes themselves so `net.Receive("x", ...)` still parses.
        # Only the two quoted alternatives start with a quote, and both end
        # with the same one.
        if text[0] in "\"'":
            return text[0] + " " * (len(text) - 2) + text[-1]
        return re.sub(r"[^\n]", " ", text)

    return NOISE.sub(blank, src)


def body_of(src, start):
    """Return the text of the callback that begins at `start` (the 'function' kw)."""
    depth = 0
    i = start
    while i < len(src):
        nxt_open = OPENERS.search(src, i)
        nxt_close = CLOSERS.search(src, i)
        if not nxt_close:
            break
        if nxt_open and nxt_open.start() < nxt_close.start():
            depth += 1
            i = nxt_open.end()
        else:
            depth -= 1
            i = nxt_close.end()
            if depth == 0:
                return src[start:i]
    return src[start:start + 4000]


def params(text):
    """Parameter names from the text between a function's parentheses."""
    return [a.strip() for a in text.split(",") if a.strip()]


def find_function(src, name):
    """(args, body) for `function name(...)` defined anywhere in src, else (None, None)."""
    m = re.search(rf"\bfunction\s+{re.escape(name)}\s*\(([^)]*)\)", src)
    if not m:
        return None, None
    return params(m.group(1)), body_of(src, m.start())


def find_table(src, name):
    """Text of the table literal assigned to `name`, braces included, else None."""
    m = re.search(rf"\b{re.escape(name)}\s*=\s*\{{", src)
    if not m:
        return None
    start = m.end() - 1
    depth = 0
    for i in range(start, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[start:i + 1]
    return None


def table_entries(tbl):
    """(anonymous, named) handlers of a dispatch table literal."""
    # anonymous: (params, body) of every function literal in it.
    # named:     identifiers assigned at its top level, `["b"] = Helper`. Missing
    #            these let one unchecked helper hide behind checked siblings.
    anonymous, masked = [], list(tbl)
    for entry in FUNC_LITERAL.finditer(tbl):
        body = body_of(tbl, entry.start())
        anonymous.append((params(entry.group(1)), body))
        end = min(entry.start() + len(body), len(tbl))
        masked[entry.start():end] = " " * (end - entry.start())
    outer = "".join(masked)
    named = [m.group(1) for m in NAMED_ENTRY.finditer(outer)
             if m.group(1) not in LUA_VALUES
             and outer.count("{", 0, m.start()) - outer.count("}", 0, m.start()) == 1]
    return anonymous, named
