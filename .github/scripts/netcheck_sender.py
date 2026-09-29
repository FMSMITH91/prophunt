"""Does a net.Receive handler validate its sender? Used by check_net_receivers.py.

Kept in its own module because Codacy grades each file on its total complexity.
"""
import re

from netcheck_lua import find_function, find_table, table_entries

# What counts as validating the sender, roughly in decreasing order of strength.
# %s stands for the sender's parameter name. The rank check is tied to it:
# `target:IsAdmin()` says nothing about who sent the message, and passing the
# sender to an allow-list like PCR:CheckUserGroup( ply ) is not a rank check.
CHECKS = [
    ("admin",      r"%s\s*:\s*(?:PHXIsStaff|IsSuperAdmin|IsAdmin|CheckUserGroup|CheckGroup)\s*\("
                   r"|util\.IsStaff\s*\(\s*%s"),
    ("validity",   r"IsValid\s*\(\s*%s\s*\)"),
    ("team",       r"%s\s*:\s*Team\s*\("),
    ("alive",      r"%s\s*:\s*Alive\s*\("),
    ("rate-limit", r"CurTime\s*\(\)|LastUsed|waitTime|HasTauntScannedData|pcrHasPropData|Delay"),
]
GATES = ("admin", "team", "alive")

# Calls that take the player but are plainly not permission checks, so seeing
# them must not make a handler look like it delegates its validation.
NOT_DELEGATION = {
    "IsValid", "isentity", "IsEntity", "tostring", "tonumber", "type", "print",
    "Msg", "MsgN", "MsgC", "ipairs", "pairs", "ErrorNoHalt", "unpack", "Format",
}
NOT_DELEGATION_LIBS = ("net", "timer", "hook", "table", "util")


def sender(arg):
    """Regex for the parameter `arg` used as a whole name (not `myply`, `x.ply`)."""
    return r"(?<![\w.:])" + re.escape(arg) + r"(?!\w)"


def found_checks(body, arg):
    """Labels of every CHECKS entry that `body` applies to `arg`."""
    return [label for label, pattern in CHECKS
            if re.search(pattern.replace("%s", sender(arg)), body)]


def delegation_targets(body, arg):
    """Functions that `body` hands `arg` to as their first argument."""
    for call in re.finditer(r"\b([A-Za-z_][\w.:]*)\s*\(\s*" + sender(arg), body):
        fn = call.group(1)
        if fn not in NOT_DELEGATION and fn.split(".")[0] not in NOT_DELEGATION_LIBS:
            yield fn


def helper_checked(src, name, arg, depth, seen):
    """Is the function called `name`, defined in src, a sender check?"""
    if name in seen:
        return False
    hargs, hbody = find_function(src, name)
    if hbody is None:
        return False
    return sender_checked(src, hbody, (hargs or [arg])[0], depth + 1, seen | {name})


def entries_checked(src, tbl, arg, depth, seen):
    """Does every handler in the dispatch table literal `tbl` check its sender?"""
    anonymous, named = table_entries(tbl)
    if not anonymous and not named:
        return False
    # set(seen) per entry: the visited set guards against recursion cycles
    # along one path, so sharing it between siblings would let the first
    # entry consume a helper and make every later entry "already seen" and
    # therefore unchecked.
    return (all(sender_checked(src, body, (args or [arg])[0], depth + 1, set(seen))
                for args, body in anonymous)
            and all(helper_checked(src, name, arg, depth, set(seen)) for name in named))


def dispatch_checked(src, body, arg, depth, seen):
    """Does `body` dispatch `arg` through a table - TBL[key](ply, ...) - whose
    every entry checks it?"""
    for disp in re.finditer(r"\b([A-Za-z_][\w.]*)\s*\[[^\]]+\]\s*\(\s*" + sender(arg), body):
        tbl = find_table(src, disp.group(1))
        if tbl and entries_checked(src, tbl, arg, depth, seen):
            return True
    return False


def sender_checked(src, body, arg, depth=0, seen=None):
    """Does `body` validate `arg`, directly or through the helpers it calls?

    Follows three shapes, because real handlers rarely check inline:
      1. a direct rank/team/alive test
      2. a call to a named helper that checks (possibly itself via a helper)
      3. dispatch through a table of handlers - TBL[key](ply, ...) - which
         counts only if EVERY entry in that table validates, named ones too

    Shape 3 is what sv_admin.lua uses: the receiver hands off to
    ManageNetMessages, which dispatches through net_functions, whose every
    entry calls doAdminStrictCheck, which calls ply:PHXIsStaff(). Without
    following that, seven safe handlers sit permanently in the review list and
    drown out anything real.
    """
    if depth > 4:
        return False
    seen = set() if seen is None else seen
    return (any(label in GATES for label in found_checks(body, arg))
            or dispatch_checked(src, body, arg, depth, seen)
            or any(helper_checked(src, fn, arg, depth, seen)
                   for fn in delegation_targets(body, arg)))
