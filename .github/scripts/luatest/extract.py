#!/usr/bin/env python3
"""Pull a function (or line range) out of a GLua file and translate it to stock Lua.

The point is to execute the SHIPPED bytes under a test harness, not a retyped
approximation of them. glualint and Codacy both pass code that errors the moment
a player touches it; this is what catches that.

Usage:
    extract.py <repo-relative path> '<python regex matching the first line>'
    extract.py <repo-relative path> 12-48

The regex form walks the block to its matching `end`, so tests bind to code
rather than line numbers and do not rot when the file above them changes.

Four things this gets right, each of which silently broke an earlier version and
made tests pass against broken code:

  * String and comment bodies are masked before any operator rewriting, so
    `["!unstuck"]` does not become `[" not unstuck"]`.
  * `for ... do` is ONE block opener, not two.
  * `continue` is GLua-only. It is neutralised only for parse checks
    (EXTRACT_PARSE_ONLY=1); for behaviour tests it warns loudly instead, because
    dropping it would run loop bodies that should have been skipped.
  * An extraction that matches nothing exits non-zero rather than printing "".
"""
import os
import re
import sys

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..")


def split_code_and_literals(src):
    """Yield (kind, text) where kind is 'code' | 'lit'. 'lit' is never rewritten."""
    out, i, n, buf = [], 0, len(src), []

    def flush():
        if buf:
            out.append(("code", "".join(buf)))
            buf.clear()

    while i < n:
        c = src[i]
        two = src[i:i + 2]

        m = re.match(r'(--)?\[(=*)\[', src[i:])
        if m and (m.group(1) or c == '['):
            close = ']' + m.group(2) + ']'
            end = src.find(close, i + m.end())
            end = n if end == -1 else end + len(close)
            flush()
            out.append(("lit", src[i:end]))
            i = end
            continue

        if two == '--' or (two == '//' and src[i - 1:i] != ':'):
            end = src.find('\n', i)
            end = n if end == -1 else end
            flush()
            body = src[i:end]
            if body.startswith('//'):
                body = '--' + body[2:]
            out.append(("lit", body))
            i = end
            continue

        if two == '/*':
            end = src.find('*/', i + 2)
            end = n if end == -1 else end + 2
            flush()
            out.append(("lit", '--[[' + src[i + 2:end - 2] + ']]'))
            i = end
            continue

        if c in '"\'':
            j = i + 1
            while j < n:
                if src[j] == '\\':
                    j += 2
                    continue
                if src[j] == c or src[j] == '\n':
                    break
                j += 1
            flush()
            out.append(("lit", src[i:j + 1]))
            i = j + 1
            continue

        buf.append(c)
        i += 1

    flush()
    return out


def rewrite_code(code):
    code = code.replace("!=", "~=").replace("&&", " and ").replace("||", " or ")
    return re.sub(r'!(?=[A-Za-z_(])', ' not ', code)


def translate(src, parse_only=False):
    out = "".join(t if k == "lit" else rewrite_code(t)
                  for k, t in split_code_and_literals(src))
    if re.search(r'(?<![\w.])continue(?![\w])', out):
        if parse_only:
            out = re.sub(r'(?<![\w.])continue(?![\w])', '_CONTINUE_ = 1', out)
        else:
            sys.stderr.write("extract: WARNING - extracted code uses `continue`; "
                             "stock Lua cannot express it, results may be wrong\n")
    return out


KW = {k: re.compile(r'(?<![\w.:])%s(?![\w])' % k)
      for k in ("function", "if", "for", "while", "do")}


def count_opens(line):
    n = {k: len(rx.findall(line)) for k, rx in KW.items()}
    # `for ... do` / `while ... do` open ONE block; the `do` belongs to the header.
    standalone_do = max(0, n["do"] - n["for"] - n["while"])
    return (n["function"] + n["if"] + n["for"] + n["while"]
            + standalone_do + line.count('{'))


CLOSE = re.compile(r'(?<![\w.:])end(?![\w])')


def count_closes(line):
    return len(CLOSE.findall(line)) + line.count('}')


def block(masked, raw_lines, start):
    depth = 0
    for i in range(start, len(masked)):
        depth += count_opens(masked[i]) - count_closes(masked[i])
        if depth <= 0:
            return raw_lines[start:i + 1]
    return raw_lines[start:]


def main():
    path, spec = sys.argv[1], sys.argv[2]
    raw = open(os.path.join(REPO, path), encoding="utf-8", errors="replace").read()
    raw_lines = raw.split("\n")
    parse_only = os.environ.get("EXTRACT_PARSE_ONLY") == "1"

    if re.fullmatch(r"\d+-\d+", spec):
        a, b = spec.split("-")
        text = translate("\n".join(raw_lines[int(a) - 1:int(b)]), parse_only)
        if not text.strip():
            sys.stderr.write("extract: empty range %s in %s\n" % (spec, path))
            sys.exit(2)
        sys.stdout.write(text)
        return

    masked = "".join(t if k == "code" else re.sub(r"[^\n]", " ", t)
                     for k, t in split_code_and_literals(raw)).split("\n")
    rx = re.compile(spec)
    for i, line in enumerate(raw_lines):
        if rx.search(line):
            sys.stdout.write(translate("\n".join(block(masked, raw_lines, i)), parse_only))
            return

    sys.stderr.write("extract: no line matched %r in %s\n" % (spec, path))
    sys.exit(2)


main()
