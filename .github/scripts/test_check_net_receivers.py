#!/usr/bin/env python3
"""Regression tests for check_net_receivers.py."""
# The checker follows delegation chains so that safe handlers do not sit in the
# review list forever. That makes it more permissive, and a permissive security
# checker that has quietly gone blind is worse than none at all - these cases pin
# down both halves: it still flags an unguarded handler, and it refuses to call a
# chain safe when any branch of it skips the check.
#
# Run directly: python3 .github/scripts/test_check_net_receivers.py
import contextlib
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


# Realm decided by the callback signature: the file name says nothing.
SHARED = r'''
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

-- 7. checks a rank, but the TARGET's, not the sender's
net.Receive("KickTarget", function(len, ply)
    local target = Player(net.ReadUInt(16))
    if target:IsAdmin() then return end
    target:Kick("bye")
end)

-- 8. a named table entry that skips the check hides behind a checked sibling
local function DangerousHelper(ply, d) RunConsoleCommand("ph_c", d) end
local mixed_fns = {
    ["a"] = function(ply, d) if gate(ply) then RunConsoleCommand("ph_a", d) end end,
    ["b"] = DangerousHelper,
}
local function mixedDispatch(ply, k, d) mixed_fns[k](ply, d) end
net.Receive("NamedDispatch", function(len, ply)
    mixedDispatch(ply, "b", net.ReadString())
end)

-- 9. named entries that all check are still fine
local function CheckedHelper(ply, d) if gate(ply) then RunConsoleCommand("ph_d", d) end end
local named_fns = { ["a"] = CheckedHelper, ["b"] = CheckedHelper }
local function namedDispatch(ply, k, d) named_fns[k](ply, d) end
net.Receive("NamedSafeDispatch", function(len, ply)
    namedDispatch(ply, "a", net.ReadString())
end)

-- 10. a space-indented helper whose body used to run on into the next function
if SERVER then
    local function LogIt(p) print(p) end
    local function Unrelated(q)
        if q:IsSuperAdmin() then print("hi") end
    end
end
net.Receive("RunawayHelper", function(len, ply)
    LogIt(ply)
    RunConsoleCommand(net.ReadString())
end)

-- 11. an allow-list such as PCR:CheckUserGroup( ply ) is not a rank check, and
--     is optional besides
PCR = PCR or {}
function PCR:CheckUserGroup(ply) return PCR.Groups[ply:GetUserGroup()] end
net.Receive("GroupAllowList", function(len, ply)
    if PHX:GetCVar("pcr_only_allow_certain_groups") and !PCR:CheckUserGroup(ply) then return end
    ents.Create("prop_physics"):SetModel(net.ReadString())
end)

-- 12. the sender's own group check does count
net.Receive("OwnGroup", function(len, ply)
    if !ply:CheckUserGroup() then return end
    RunConsoleCommand(net.ReadString())
end)
'''

# sv_ file: server-side whatever the callback looks like.
SERVER = r'''
-- 13. no player parameter at all: it cannot check its sender
net.Receive("NoPlayerParam", function(len)
    RunConsoleCommand(net.ReadString(), net.ReadString())
end)

-- 14. passed by reference to an unchecked function
local function HandleRunCmd(len, ply)
    RunConsoleCommand(net.ReadString())
end
net.Receive("ByRefUngated", HandleRunCmd)

-- 15. passed by reference to a checked function
local function HandleStaffCmd(len, ply)
    if !ply:PHXIsStaff() then return end
    RunConsoleCommand(net.ReadString())
end
net.Receive("ByRefChecked", HandleStaffCmd)

-- 16. passed by reference to something another file defines
net.Receive("ByRefElsewhere", SomeOtherFile.Handle)
'''

# cl_ file: client-side whatever the callback looks like.
CLIENT = r'''
-- 17. a client file never receives a sender, whatever the signature says
net.Receive("ClientFile", function(len, ply)
    print(net.ReadString())
end)
net.Receive("ClientFileByRef", SomeHandler)
'''

FILES = {"cases.lua": SHARED, "sv_cases.lua": SERVER, "cl_cases.lua": CLIENT}

# name -> verdict the checker must reach
EXPECTED = {
    "Ungated":           "UNGATED",
    "Inline":            "ok",
    "ViaHelper":         "ok",
    "SafeDispatch":      "ok",
    "LeakyDispatch":     "REVIEW",
    "KickTarget":        "UNGATED",
    "NamedDispatch":     "REVIEW",
    "NamedSafeDispatch": "ok",
    "RunawayHelper":     "REVIEW",
    "GroupAllowList":    "REVIEW",
    "OwnGroup":          "ok",
    "NoPlayerParam":     "UNGATED",
    "ByRefUngated":      "UNGATED",
    "ByRefChecked":      "ok",
    "ByRefElsewhere":    "REVIEW",
}

# Client-side receivers have no sender to validate; counting them would inflate
# the report with entries nobody can act on.
NOT_REPORTED = ("ClientSide", "ClientFile", "ClientFileByRef")


def verdicts():
    """Run the checker over FILES in a scratch dir and return {name: verdict}."""
    with tempfile.TemporaryDirectory() as tmp:
        for fname, text in FILES.items():
            with open(os.path.join(tmp, fname), "w", encoding="utf-8") as fh:
                fh.write(text)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            checker.main(tmp)
    text = out.getvalue()
    return dict(re.findall(r"^\s{2}(\S+)\s+(ok|REVIEW|UNGATED)\s", text, re.M))


def main():
    """Print PASS/FAIL per case and return non-zero on any failure."""
    got = verdicts()
    failures = []

    for name, want in sorted(EXPECTED.items()):
        have = got.get(name)
        if have != want:
            failures.append(f"{name}: expected {want}, got {have}")
        print(f"  {name:<18} {have or 'MISSING':<8} {'PASS' if have == want else 'FAIL'}")

    for name in NOT_REPORTED:
        if name in got:
            failures.append(f"{name}: client-side receiver should not be reported")
            print(f"  {name:<18} {got[name]:<8} FAIL (should not be reported)")
        else:
            print(f"  {name:<18} {'skipped':<8} PASS")

    if failures:
        print(f"\n{len(failures)} failure(s):")
        for f in failures:
            print("  - " + f)
        return 1

    print(f"\nall {len(EXPECTED) + len(NOT_REPORTED)} cases pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
