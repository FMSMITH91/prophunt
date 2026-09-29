"""Split GLua source into code, strings and comments, for extract.py."""
# Only the code parts may be rewritten (GLua operators to stock Lua), and a
# comment must stay a comment of the same extent: `//[[ note` is a LINE comment
# in GLua, so it must not turn into a Lua long comment that swallows real code.
# Kept in its own module because Codacy grades each file on its total complexity.
import re


# Matched at an offset with .match(src, i) rather than against src[i:] - slicing
# inside a per-character loop copies the rest of the file on every character,
# which is quadratic on the larger gamemode files.
LONG_BRACKET = re.compile(r'(--)?\[(=*)\[')


def long_bracket(src, i, m):
    """A Lua [[string]] or --[[comment]] at i, whatever its level."""
    close = ']' + m.group(2) + ']'
    end = src.find(close, m.end())   # m.end() is absolute here
    end = len(src) if end == -1 else end + len(close)
    return ("comment" if m.group(1) else "lit"), src[i:end], end


def line_comment(src, i):
    """A -- or // comment running to the end of the line."""
    end = src.find('\n', i)
    end = len(src) if end == -1 else end
    # The space keeps `//[[` a line comment instead of a long-comment opener.
    body = '-- ' + src[i + 2:end] if src.startswith('//', i) else src[i:end]
    return "comment", body, end


def block_comment(src, i):
    """A C-style /* */ comment, as a Lua long comment it cannot close early."""
    end = src.find('*/', i + 2)
    end = len(src) if end == -1 else end + 2
    body = src[i + 2:end - 2]
    level = 0
    while ']' + '=' * level + ']' in body:
        level += 1
    eq = '=' * level
    return "comment", '--[' + eq + '[' + body + ']' + eq + ']', end


def quoted(src, i):
    """A "string" or 'string' (an unterminated one stops at the newline)."""
    j = i + 1
    while j < len(src) and src[j] not in (src[i], '\n'):
        j += 2 if src[j] == '\\' else 1
    return "lit", src[i:j + 1], j + 1


def literal_at(src, i):
    """(kind, text, end) of the string or comment starting at i, else None."""
    m = LONG_BRACKET.match(src, i)
    if m and (m.group(1) or src[i] == '['):
        return long_bracket(src, i, m)
    two = src[i:i + 2]
    if two == '--' or (two == '//' and src[i - 1:i] != ':'):
        return line_comment(src, i)
    if two == '/*':
        return block_comment(src, i)
    if src[i] in '"\'':
        return quoted(src, i)
    return None


def split_code_and_literals(src):
    """List of (kind, text, raw), kind 'code' | 'lit' | 'comment'."""
    # text is what translate() emits (only code is rewritten, later); raw is the
    # original span, so masks built from it keep every column where it was.
    out, i, start = [], 0, 0
    while i < len(src):
        found = literal_at(src, i)
        if found is None:
            i += 1
            continue
        if start < i:
            out.append(("code", src[start:i], src[start:i]))
        out.append((found[0], found[1], src[i:found[2]]))
        i = start = found[2]
    if start < len(src):
        out.append(("code", src[start:], src[start:]))
    return out
