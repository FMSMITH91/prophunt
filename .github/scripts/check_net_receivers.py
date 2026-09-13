#!/usr/bin/env python3
"""Report server-side net.Receive handlers that do not validate their sender.

Anything a client sends over the net library is attacker-controlled. A handler
that acts on it without checking who sent it - and whether that player is even
allowed to do the thing - is how GMod servers get taken over.

Server-side receivers are identified by their callback signature: the server
gets `function( len, ply )`, the client only gets `function( len )`.

Each handler is reported as one of:

  ok      - checks the sender's rank, team or alive state inline
  REVIEW  - hands the sender to another function; this script cannot follow
            that, so check by hand whether the helper validates anything
  UNGATED - acts on client data with no sender check at all

This is a report, not a gate: it always exits 0. Some handlers legitimately need
no permission check (a client asking for data it is allowed to have), so treat
the output as a review list rather than a bug list. Flip STRICT to make UNGATED
handlers fail the build.
"""
import io
import os
import re
import sys

STRICT = False

# Server handlers take a second parameter (the sending player); clients do not.
RECEIVE = re.compile(
    r'net\.Receive\s*\(\s*(?:(?P<q>["\'])(?P<name>[^"\']*)(?P=q)|(?P<var>[A-Za-z_][\w.]*))'
    r'\s*,\s*function\s*\(\s*(?P<args>[^)]*)\)'
)

# What counts as validating the sender, roughly in decreasing order of strength.
CHECKS = [
    ("admin",      r"PHXIsStaff|util\.IsStaff|IsSuperAdmin|IsAdmin|CheckUserGroup|CheckUserGroup"),
    ("validity",   r"IsValid\s*\(\s*%s\s*\)"),
    ("team",       r"%s\s*:\s*Team\s*\("),
    ("alive",      r"%s\s*:\s*Alive\s*\("),
    ("rate-limit", r"CurTime\s*\(\)|LastUsed|waitTime|HasTauntScannedData|pcrHasPropData|Delay"),
]

# Calls that take the player but are plainly not permission checks, so seeing
# them must not make a handler look like it delegates its validation.
NOT_DELEGATION = {
    "IsValid", "isentity", "IsEntity", "tostring", "tonumber", "type", "print",
    "Msg", "MsgN", "MsgC", "ipairs", "pairs", "ErrorNoHalt", "unpack", "Format",
}

OPENERS = re.compile(r"\b(function|do|if)\b")
CLOSERS = re.compile(r"\bend\b")


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
    """Blank comments and string bodies, keeping every offset and line intact.

    Length-preserving, so offsets in the stripped text still line up with the
    original file - that is what lets us report accurate line numbers.
    """
    def blank(m):
        text = m.group(0)
        # Keep the quotes themselves so `net.Receive("x", ...)` still parses.
        if text[0] in "\"'" and len(text) >= 2 and text[0] == text[-1]:
            return text[0] + " " * (len(text) - 2) + text[-1]
        return "".join(c if c == "\n" else " " for c in text)

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


def find_function(src, name):
    """(args, body) for `function name(...)` defined anywhere in src, else (None, None)."""
    m = re.search(r"\bfunction\s+%s\s*\(([^)]*)\)" % re.escape(name), src)
    if not m:
        return None, None
    args = [a.strip() for a in m.group(1).split(",") if a.strip()]
    return args, body_of(src, m.start())


def find_table(src, name):
    """Text of the table literal assigned to `name`, braces included, else None."""
    m = re.search(r"\b%s\s*=\s*\{" % re.escape(name), src)
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


def sender_checked(src, body, arg, depth=0, seen=None):
    """Does `body` validate `arg`, directly or through the helpers it calls?

    Follows three shapes, because real handlers rarely check inline:
      1. a direct rank/team/alive test
      2. a call to a named helper that checks (possibly itself via a helper)
      3. dispatch through a table of handlers - TBL[key](ply, ...) - which
         counts only if EVERY function in that table validates

    Shape 3 is what sv_admin.lua uses: the receiver hands off to
    ManageNetMessages, which dispatches through net_functions, whose every
    entry calls doAdminStrictCheck, which calls ply:PHXIsStaff(). Without
    following that, seven safe handlers sit permanently in the review list and
    drown out anything real.
    """
    if depth > 4:
        return False
    seen = set() if seen is None else seen
    argre = re.escape(arg)

    if re.search(CHECKS[0][1], body):
        return True
    if re.search(r"%s\s*:\s*(Team|Alive)\s*\(" % argre, body):
        return True

    for disp in re.finditer(r"\b([A-Za-z_][\w.]*)\s*\[[^\]]+\]\s*\(\s*%s\b" % argre, body):
        tbl = find_table(src, disp.group(1))
        if not tbl:
            continue
        entries = list(re.finditer(r"\bfunction\s*\(([^)]*)\)", tbl))
        if not entries:
            continue
        # set(seen) per entry: the visited set guards against recursion cycles
        # along one path, so sharing it between siblings would let the first
        # entry consume a helper and make every later entry "already seen" and
        # therefore unchecked.
        if all(
            sender_checked(
                src,
                body_of(tbl, e.start()),
                ([a.strip() for a in e.group(1).split(",") if a.strip()] or [arg])[0],
                depth + 1, set(seen))
            for e in entries
        ):
            return True

    for call in re.finditer(r"\b([A-Za-z_][\w.:]*)\s*\(\s*%s\b" % argre, body):
        fn = call.group(1)
        if fn in NOT_DELEGATION or fn.split(".")[0] in ("net", "timer", "hook", "table", "util"):
            continue
        if fn in seen:
            continue
        hargs, hbody = find_function(src, fn)
        if hbody is None:
            continue
        if sender_checked(src, hbody, (hargs or [arg])[0], depth + 1, seen | {fn}):
            return True

    return False


def main():
    findings = 0
    review = 0
    handlers = 0

    for root, _dirs, files in os.walk("."):
        if ".git" in root:
            continue
        for fname in sorted(files):
            if not fname.endswith(".lua"):
                continue
            path = os.path.join(root, fname).lstrip("./")
            raw = io.open(path, encoding="utf-8", errors="replace").read()
            src = strip_noise(raw)
            assert len(src) == len(raw)      # offsets must stay aligned

            for m in RECEIVE.finditer(src):
                args = [a.strip() for a in m.group("args").split(",") if a.strip()]
                if len(args) < 2:
                    continue                      # client-side receiver
                handlers += 1

                ply = re.escape(args[1])
                # The string literal is blanked in `src`, so recover it from `raw`.
                if m.group("name") is not None:
                    name = RECEIVE.match(raw, m.start()).group("name")
                else:
                    name = m.group("var")
                line = src[:m.start()].count("\n") + 1
                body = body_of(src, src.index("function", m.start()))

                present = []
                for label, pattern in CHECKS:
                    if re.search(pattern % ply if "%s" in pattern else pattern, body):
                        present.append(label)

                # Handlers that hand `ply` straight to a helper may well be
                # validated in there; this script cannot follow that, so flag
                # them for a human rather than crying wolf.
                delegated = False
                for call in re.finditer(r"\b([A-Za-z_][\w.:]*)\s*\(\s*%s\b" % ply, body):
                    fn = call.group(1)
                    if fn in NOT_DELEGATION or fn.split(".")[0] in ("net", "timer", "hook", "table", "util"):
                        continue
                    # Follow one level: if the helper is defined in this file and
                    # itself checks the player, the handler is gated after all.
                    # Without this, wrappers like CheckUser() leave a permanent
                    # backlog of "review" entries that nobody ends up reading.
                    helper = re.search(
                        r"function\s+%s\s*\(([^)]*)\)(.*?)\n(?:end|\tend)" % re.escape(fn),
                        src, re.S)
                    if helper:
                        hargs = [a.strip() for a in helper.group(1).split(",") if a.strip()]
                        harg = re.escape(hargs[0]) if hargs else ply
                        hbody = helper.group(2)
                        if re.search(CHECKS[0][1], hbody) or re.search(r"%s\s*:\s*(Team|Alive)\s*\(" % harg, hbody):
                            present.append("admin (via %s)" % fn)
                            break
                    delegated = True
                    break

                gated = any(p.split(" ")[0] in ("admin","team","alive") for p in present)

                # Not gated inline - try to resolve the chain it delegates to
                # before writing it off as needing a human.
                if not gated and sender_checked(src, body, args[1]):
                    present.append("admin (resolved through helpers)")
                    gated = True

                if gated:
                    verdict = "ok"
                elif delegated:
                    verdict = "REVIEW (passes sender to a helper)"
                    review += 1
                else:
                    verdict = "UNGATED"
                    findings += 1

                print("  %-34s %-8s %s:%d\n      checks: %s"
                      % (name, verdict.split()[0], path, line,
                         ", ".join(present) or "none"))

                if verdict == "UNGATED":
                    print("::warning file=%s,line=%d::net.Receive '%s' acts on client "
                          "data without checking the sender's rank, team or alive "
                          "state (found: %s)"
                          % (path, line, name, ", ".join(present) or "no checks at all"))

    print("\n%d server-side handler(s): %d ungated, %d need a manual look, "
          "%d gated inline." % (handlers, findings, review, handlers - findings - review))
    return 1 if (STRICT and findings) else 0


if __name__ == "__main__":
    sys.exit(main())
