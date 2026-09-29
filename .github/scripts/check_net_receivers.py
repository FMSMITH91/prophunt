#!/usr/bin/env python3
"""Report server-side net.Receive handlers that do not validate their sender.

Anything a client sends over the net library is attacker-controlled. A handler
that acts on it without checking who sent it - and whether that player is even
allowed to do the thing - is how GMod servers get taken over.

The realm comes from the file first: cl_ files are client-side; sv_ files,
init.lua and lua/autorun/server are server-side. Anywhere else (sh_ files,
weapons, shared.lua) the callback signature decides: the server gets
`function( len, ply )`, the client only `function( len )`. A receiver passed by
reference - net.Receive( "x", HandleX ) - is resolved to its definition in the
same file.

Each handler is reported as one of:

  ok      - checks the sender's rank, team or alive state, inline or through
            helpers and dispatch tables defined in the same file
  REVIEW  - hands the sender to a helper this script cannot resolve (defined in
            another file, or a table entry it cannot see), so check by hand
            whether that helper validates anything
  UNGATED - acts on client data with no sender check at all. A server-side
            callback with no player parameter lands here too: it cannot check
            its sender even if it wanted to.

A rank check only counts when it is made on the sender - `ply:IsAdmin()`,
`util.IsStaff( ply )`. Checking some other player's rank, or passing the
sender to an allow-list like PCR:CheckUserGroup( ply ), is not a permission
gate. The detection logic lives in netcheck_sender.py and netcheck_lua.py.

This is a report, not a gate: it always exits 0. Some handlers legitimately need
no permission check (a client asking for data it is allowed to have), so treat
the output as a review list rather than a bug list. Flip STRICT to make UNGATED
handlers fail the build.
"""
import os
import re
import sys

from netcheck_lua import body_of, find_function, params, strip_noise
from netcheck_sender import GATES, delegation_targets, found_checks, sender_checked

STRICT = False

# Scanned from the repo root wherever this is run from, so running it from the
# wrong directory cannot quietly report "0 handlers".
REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

# The callback is either inline or a reference to a function defined elsewhere.
RECEIVE = re.compile(
    r'net\.Receive\s*\(\s*(?:(?P<q>["\'])(?P<name>[^"\']*)(?P=q)|(?P<var>[A-Za-z_][\w.]*))'
    r'\s*,\s*(?:function\s*\(\s*(?P<args>[^)]*)\)|(?P<ref>[A-Za-z_][\w.:]*)\s*\))'
)


def realm_of(path):
    """'client', 'server', or None when only the callback's signature can tell."""
    name = os.path.basename(path)
    unix = "/" + path.replace(os.sep, "/")
    if name.startswith("cl_") or "/autorun/client/" in unix:
        return "client"
    if name.startswith("sv_") or name == "init.lua" or "/autorun/server/" in unix:
        return "server"
    return None


def callback_of(src, m):
    """(params, body) of the receiver's callback; (None, None) when it is a
    reference to a function this file does not define."""
    if m.group("ref") is not None:
        return find_function(src, m.group("ref"))
    return params(m.group("args")), body_of(src, src.rfind("function", m.start(), m.start("args")))


def verdict_for(src, body, ply):
    """(verdict, checks found) for a server callback whose sender is `ply`."""
    present = found_checks(body, ply)
    if any(label in GATES for label in present):
        return "ok", present
    # Not gated inline - try to resolve the chain it delegates to before
    # writing it off as needing a human.
    if sender_checked(src, body, ply):
        return "ok", present + ["sender check (resolved through helpers)"]
    if any(True for _ in delegation_targets(body, ply)):
        return "REVIEW", present
    return "UNGATED", present


def classify(src, m, realm):
    """(verdict, checks found) for one receiver, or None if it is client-side."""
    args, body = callback_of(src, m)
    if realm == "client":
        return None
    if body is None:
        return "REVIEW", ["callback is defined in another file"]
    if len(args) >= 2:
        return verdict_for(src, body, args[1])
    if realm == "server":
        return "UNGATED", ["none - the callback has no player parameter to check"]
    return None


def lua_files(root):
    """Every .lua file under root, skipping dot-directories (.git, .github)."""
    for dirpath, dirs, files in os.walk(root):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        for fname in sorted(files):
            if fname.endswith(".lua"):
                yield os.path.join(dirpath, fname)


def scan(path, realm):
    """Yield (name, line, verdict, checks found) for each server receiver in path."""
    with open(path, encoding="utf-8", errors="replace") as fh:
        raw = fh.read()
    src = strip_noise(raw)
    if len(src) != len(raw):
        raise RuntimeError(f"strip_noise changed the length of {path}; offsets would drift")

    for m in RECEIVE.finditer(src):
        result = classify(src, m, realm)
        if result is None:
            continue
        name = m.group("var")
        if m.group("name") is not None:
            # The string literal is blanked in `src`, so recover it from `raw`.
            lit = RECEIVE.match(raw, m.start())
            name = lit.group("name") if lit else "?"
        yield name, src.count("\n", 0, m.start()) + 1, result[0], result[1]


def main(root=REPO):
    """Print a verdict for every server-side receiver under root."""
    counts = {"ok": 0, "REVIEW": 0, "UNGATED": 0}
    for path in lua_files(root):
        rel = os.path.relpath(path, root).replace(os.sep, "/")
        for name, line, verdict, present in scan(path, realm_of(rel)):
            counts[verdict] += 1
            found = ", ".join(present) or "none"
            print(f"  {name:<34} {verdict:<8} {rel}:{line}\n      checks: {found}")
            if verdict == "UNGATED":
                print(f"::warning file={rel},line={line}::net.Receive '{name}' acts on client "
                      f"data without checking the sender's rank, team or alive state "
                      f"(found: {found})")

    print(f"\n{sum(counts.values())} server-side handler(s): {counts['UNGATED']} ungated, "
          f"{counts['REVIEW']} need a manual look, {counts['ok']} ok.")
    return 1 if (STRICT and counts["UNGATED"]) else 0


if __name__ == "__main__":
    sys.exit(main())
