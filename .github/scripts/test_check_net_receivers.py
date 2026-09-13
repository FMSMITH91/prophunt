#!/usr/bin/env python3
"""Regression tests for check_net_receivers.py.

The checker follows delegation chains so that safe handlers do not sit in the
review list forever. That makes it more permissive, and a permissive security
checker that has quietly gone blind is worse than none at all - these cases pin
down both halves: it still flags an unguarded handler, and it refuses to call a
chain safe when any branch of it skips the check.

Run directly: python3 .github/scripts/test_check_net_receivers.py
"""
import importlib.util
import io
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))

spec = importlib.util.spec_from_file_location(
    "checker", os.path.join(HERE, "check_net_receivers.py"))
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


LUA = r'''
-- 1. no sender check at all
net.Receive("Ungated", function(len, ply)
    RunConsoleCommand(net.ReadString())
end)

-- 2. checks inline
net.Receive("Inline", function(len, ply)
    if ( ply:PHXIsStaff() ) then RunConsoleCommand("ph_x", net.ReadString()) end
end)

-- 3. checks one call away
local function gate(p) return p:PHXIsStaff() end
net.Receive("ViaHelper", function(len, ply)
    if ( gate(ply) ) then RunConsoleCommand("ph_y", net.ReadString()) end
end)

-- 4. dispatch through a table where every entry checks
local safe_fns = {
    ["a"] = function(ply, d) if gate(ply) then RunConsoleCommand("ph_a", d) end end,
    ["b"] = function(ply, d) if gate(ply) then RunConsoleCommand("ph_b", d) end end,
}
local function safeDispatch(ply, k, d) safe_fns[k](ply, d) end
net.Receive("SafeDispatch", function(len, ply)
    safeDispatch(ply, "a", net.ReadString())
end)

-- 5. same shape, but one entry forgets the check
local leaky_fns = {
    ["a"] = function(ply, d) if gate(ply) then RunConsoleCommand("ph_a", d) end end,
    ["b"] = function(ply, d) RunConsoleCommand("ph_b", d) end,
}
local function leakyDispatch(ply, k, d) leaky_fns[k](ply, d) end
net.Receive("LeakyDispatch", function(len, ply)
    leakyDispatch(ply, "b", net.ReadString())
end)

-- 6. client-side receiver: no sender argument, must not be counted at all
net.Receive("ClientSide", function(len)
    local x = net.ReadString()
end)
'''

# name -> verdict the checker must reach
EXPECTED = {
    "Ungated":       "UNGATED",
    "Inline":        "ok",
    "ViaHelper":     "ok",
    "SafeDispatch":  "ok",
    "LeakyDispatch": "REVIEW",
}


def verdicts():
    """Run the checker over LUA in a scratch dir and return {name: verdict}."""
    out = {}
    with tempfile.TemporaryDirectory() as tmp:
        io.open(os.path.join(tmp, "cases.lua"), "w", encoding="utf-8").write(LUA)

        cwd, stdout = os.getcwd(), sys.stdout
        os.chdir(tmp)
        sys.stdout = io.StringIO()
        try:
            checker.main()
            text = sys.stdout.getvalue()
        finally:
            sys.stdout = stdout
            os.chdir(cwd)

    for name, verdict in re.findall(r"^\s{2}(\S+)\s+(ok|REVIEW|UNGATED)\s", text, re.M):
        out[name] = verdict
    return out


def main():
    got = verdicts()
    failures = []

    for name, want in sorted(EXPECTED.items()):
        have = got.get(name)
        status = "PASS" if have == want else "FAIL"
        if have != want:
            failures.append("%s: expected %s, got %s" % (name, want, have))
        print("  %-16s %-8s %s" % (name, have or "MISSING", status))

    # A client-side handler has no sender to validate; counting it would inflate
    # the report with entries nobody can act on.
    if "ClientSide" in got:
        failures.append("ClientSide: client-side receiver should not be reported")
        print("  %-16s %-8s FAIL (should not be reported)" % ("ClientSide", got["ClientSide"]))
    else:
        print("  %-16s %-8s PASS" % ("ClientSide", "skipped"))

    if failures:
        print("\n%d failure(s):" % len(failures))
        for f in failures:
            print("  - " + f)
        return 1

    print("\nall %d cases pass" % (len(EXPECTED) + 1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
