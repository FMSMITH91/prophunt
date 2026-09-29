#!/usr/bin/env python3
"""Pull a function (or line range) out of a GLua file and translate it to stock Lua.

The point is to execute the SHIPPED bytes under a test harness, not a retyped
approximation of them. glualint and Codacy both pass code that errors the moment
a player touches it; this is what catches that.

Usage:
    extract.py <repo-relative path> '<python regex matching the first line>'
    extract.py <repo-relative path> 12-48

The regex form walks the block to its matching `end`, so tests bind to code
rather than line numbers and do not rot when the file above them changes. A
match that starts inside a comment is skipped (it is commented-out code, never
what a test means), and a spec that matches more than one line warns.

Things this gets right, each of which silently broke an earlier version or
could make a test run different code from what GMod runs:

  * String and comment bodies are masked before any operator rewriting, so
    `["!unstuck"]` does not become `[" not unstuck"]`.
  * `for ... do` is ONE block opener, not two.
  * `continue` is GLua-only. It is neutralised only for parse checks
    (EXTRACT_PARSE_ONLY=1); for behaviour tests it warns loudly instead, because
    dropping it would run loop bodies that should have been skipped.
  * An extraction that matches nothing exits non-zero rather than printing "".
  * `//[[ note` stays a LINE comment. Turned into `--[[` it would open a long
    comment and swallow real code up to the next `]]`, with no parse error.
  * A `/* */` body containing `]]` gets a long-bracket level that it does not
    contain, so the comment cannot end early.
  * `! x`, with a space, is negation as well as `!x`.
"""
import os
import re
import sys

# Run as a script, so this directory is on sys.path. pylint pointed at all of
# .github/scripts treats luatest/ as a package and cannot see that.
from glua_lexer import split_code_and_literals  # pylint: disable=import-error

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..")

CONTINUE = re.compile(r'(?<![\w.])continue(?![\w])')


def rewrite_code(code, parse_only=False):
    """GLua operators to stock Lua: != && || and ! (with or without a space)."""
    code = code.replace("!=", "~=").replace("&&", " and ").replace("||", " or ")
    if parse_only:
        code = CONTINUE.sub('_CONTINUE_ = 1', code)
    return re.sub(r'![ \t]*(?=[A-Za-z_(!#])', ' not ', code)


def translate(src, parse_only=False):
    """The GLua text src as stock Lua that LuaJIT can load."""
    parts = split_code_and_literals(src)
    # Only code counts: "continue" in a string or a comment is just a word.
    if not parse_only and any(k == "code" and CONTINUE.search(t) for k, t, _ in parts):
        sys.stderr.write("extract: WARNING - extracted code uses `continue`; "
                         "stock Lua cannot express it, results may be wrong\n")
    return "".join(rewrite_code(t, parse_only) if k == "code" else t for k, t, _ in parts)


KW = {k: re.compile(rf'(?<![\w.:]){k}(?![\w])')
      for k in ("function", "if", "for", "while", "do")}


def count_opens(line):
    """Blocks a (masked) line opens: function/if/for/while/do and `{`."""
    n = {k: len(rx.findall(line)) for k, rx in KW.items()}
    # `for ... do` / `while ... do` open ONE block; the `do` belongs to the header.
    standalone_do = max(0, n["do"] - n["for"] - n["while"])
    return (n["function"] + n["if"] + n["for"] + n["while"]
            + standalone_do + line.count('{'))


CLOSE = re.compile(r'(?<![\w.:])end(?![\w])')


def count_closes(line):
    """Blocks a (masked) line closes: `end` and `}`."""
    return len(CLOSE.findall(line)) + line.count('}')


def block(masked, raw_lines, start):
    """Raw lines from `start` to the line that closes the block opened there."""
    depth = 0
    for i in range(start, len(masked)):
        depth += count_opens(masked[i]) - count_closes(masked[i])
        if depth <= 0:
            return raw_lines[start:i + 1]
    return raw_lines[start:]


def code_hits(raw, spec):
    """(masked lines, indexes of lines where spec matches outside a comment).

    Masked lines have every string and comment blanked, for block() to count
    keywords in. A match counts from its first non-blank character, so a
    leading `\\s*` in the spec cannot smuggle a commented-out line in.
    """
    parts = split_code_and_literals(raw)
    masked = "".join(r if k == "code" else re.sub(r"[^\n]", " ", r) for k, _, r in parts)
    comments = "".join(re.sub(r"[^\n]", "#" if k == "comment" else " ", r)
                       for k, _, r in parts).split("\n")
    rx = re.compile(spec)
    hits = []
    for i, line in enumerate(raw.split("\n")):
        m = rx.search(line)
        if m:
            first = m.start() + len(m.group(0)) - len(m.group(0).lstrip())
            if comments[i][first:first + 1] != "#":
                hits.append(i)
    return masked.split("\n"), hits


def fail(message):
    """Exit non-zero, so runner.lua reports an EMPTY EXTRACT instead of passing."""
    sys.stderr.write(f"extract: {message}\n")
    sys.exit(2)


def main():
    """Print the translated block (or line range) the command line names."""
    path, spec = sys.argv[1], sys.argv[2]
    with open(os.path.join(REPO, path), encoding="utf-8", errors="replace") as fh:
        raw = fh.read()
    raw_lines = raw.split("\n")
    parse_only = os.environ.get("EXTRACT_PARSE_ONLY") == "1"

    if re.fullmatch(r"\d+-\d+", spec):
        a, b = spec.split("-")
        text = translate("\n".join(raw_lines[int(a) - 1:int(b)]), parse_only)
        if not text.strip():
            fail(f"empty range {spec} in {path}")
        sys.stdout.write(text)
        return

    masked, hits = code_hits(raw, spec)
    if not hits:
        fail(f"no line matched {spec!r} in {path}")
    if len(hits) > 1:
        sys.stderr.write(f"extract: WARNING - {spec!r} matches {len(hits)} lines in {path} "
                         f"(using line {hits[0] + 1}); make it specific enough to match one\n")
    sys.stdout.write(translate("\n".join(block(masked, raw_lines, hits[0])), parse_only))


main()
