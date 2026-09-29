dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- Prop Menu (PCR) custom-prop editor, server side: the edit lock and saving the custom list,
-- from the shipped sv_customprop.lua. Set-up in propmenu_env.lua.
local E = dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "propmenu_env.lua")
local set, said, disconnect, sentTo = E.set, E.said, E.disconnect, E.sentTo
set("pcr_allow_custom", 1)   -- the editor only opens with custom props allowed
S.json = {}

print("\n== custom-prop editor lock ==")
local A, B = S.Player{ staff = true, name = "A" }, S.Player{ staff = true, name = "B" }
local function request(pl) S.net.sent = {}; pl.chat = {}; S.receivers["phxpm.fb_RequestOpen_w"](0, pl)
  return sentTo("phxpm.fb_openPM_Editor", pl) == 1 end
local function done(pl) S.receivers["PCR.DoneEditing"](0, pl) end
local function editing()
  local c = S.Player{ staff = true }; S.concommands["is_someone_editing"].fn(c); return c.chat[1] and c.chat[1][1] end
check("A opens: granted", request(A), true)
check("B while A edits: refused", request(B), false)
check("B while A edits: told it is in use", said(B, "PCR_EDT_IN_USE"), true)
check("is_someone_editing: true", editing(), "Is someone editing?: true")
local C = S.Player{}
check("non-staff: refused", request(C), false)
check("non-staff: no rights", said(C, "PCR_EDT_NO_RIGHTS"), true)
done(B)
check("B's Close does not free A's lock", request(B), false)
done(A)
check("A closes, B opens: granted", request(B), true)
check("holder re-requests (window never opened): granted", request(B), true)
S.fire("PlayerDisconnected", B)         -- still a valid entity while the hook runs
check("holder disconnecting: A granted", request(A), true)
done(A)
B = S.Player{ staff = true, name = "B" }  -- back under a new entity
check("B rejoined: granted", request(B), true)
disconnect(B)
check("holder gone (entity invalid): A granted", request(A), true)
S.pump(599)
B = S.Player{ staff = true, name = "B" }
check("599 s later: still A's", request(B), false)
S.pump(2)
check("after the 600 s timeout: B granted", request(B), true)
done(B)
check("is_someone_editing after release: false", editing(), "Is someone editing?: false")

-- Saving counts as activity and refreshes the lock.
local function save(pl, list)
  S.json["saved"] = list
  S.net.readq = { "PCR", "CustomProp", 5, "saved" }
  return attempt(S.receivers["PCR.EditedCustomPropData"], 0, pl)
end
S.fileExists["phx_data/prop_chooser_custom"] = true
for _, m in ipairs{ "models/balloons/balloon_dog.mdl", "models/props_collectables/piepan.mdl" } do S.fileExists[m] = true end
check("A opens again", request(A), true)
S.pump(500)
check("A saves: no error", save(A, { "models/balloons/balloon_dog.mdl", "models/props_collectables/piepan.mdl" }), "ok")
check("save drops the prohibited model", table.HasValue(PCR.CustomProp, "models/props_collectables/piepan.mdl"), false)
check("save keeps the normal model", table.HasValue(PCR.CustomProp, "models/balloons/balloon_dog.mdl"), true)
S.net.sent = {}
check("save: confirmation timer has no error", #S.pump(1), 0)
check("save: editor told it succeeded", sentTo("phxpm.fb_UpdateConfirmed_Editor", A), 1)
S.pump(199)
check("700 s after opening, 200 s after saving: still A's", request(B), false)
S.pump(402)
check("600 s after the save: B granted", request(B), true)
done(B)
check("A re-opens", request(A), true)
save(A, { "models/balloons/balloon_dog.mdl" })
disconnect(A)
S.net.sent = {}
check("editor leaves before the confirmation: no timer error", S.pump(1)[1], nil)
check("editor leaves before the confirmation: nothing sent to them", sentTo("phxpm.fb_UpdateConfirmed_Editor", A), 0)
check("editor left: lock free", request(B), true)

print("\n== only the lock holder's save is kept ==")
-- Every save replaces the whole list, so once a lapsed window and a new holder's window are
-- both open, the lapsed one must not overwrite the holder's work.
local function confirmation(pl)             -- the error flag of pl's last save confirmation
  for i = #S.net.sent, 1, -1 do
    local m = S.net.sent[i]
    if m.name == "phxpm.fb_UpdateConfirmed_Editor" and m.to == pl then return m.data[1] end
  end
end
local LA, LB = "models/props_junk/from_a.mdl", "models/props_junk/from_b.mdl"
S.fileExists[LA], S.fileExists[LB] = true, true
done(B)
A = S.Player{ staff = true, name = "A" }
check("A opens (new entity)", request(A), true)
S.pump(601)
check("A idle past the timeout: B granted", request(B), true)
S.net.sent, A.chat = {}, {}
check("lapsed editor saves: no error", save(A, { LA }), "ok")
check("lapsed editor's save: not written", table.HasValue(PCR.CustomProp, LA), false)
check("lapsed editor's save: told it failed", confirmation(A), true)
check("lapsed editor's save: told someone else is editing", said(A, "PCR_EDT_IN_USE"), true)
S.net.sent = {}
check("holder saves: no error", save(B, { LB }), "ok")
check("holder's save: written", table.HasValue(PCR.CustomProp, LB), true)
S.pump(1)
check("holder's save: told it succeeded", confirmation(B), false)
-- Normal play: a holder whose lock lapsed with nobody taking over still saves.
done(B)
check("A re-opens after B closes", request(A), true)
S.pump(900)
S.net.sent = {}
save(A, { LA })
check("long session, nobody else: save written", table.HasValue(PCR.CustomProp, LA), true)
S.pump(1)
check("long session, nobody else: told it succeeded", confirmation(A), false)
-- With the lock free (holder closed), a save is taken as before.
done(A)
S.net.sent = {}
save(B, { LB })
check("lock free: save written", table.HasValue(PCR.CustomProp, LB), true)
S.pump(1)
check("lock free: told it succeeded", confirmation(B), false)
check("lock free: the new list is broadcast (normal play)", sentTo("pcr.PropListData", "all"), 1)

print("\n== #211 a save whose list is too big to send is reported as failed ==")
util.Compress = function() return string.rep("x", 60001) end
S.net.sent = {}
save(B, { LB }); S.pump(1)
check("oversized list after a save: not broadcast", sentTo("pcr.PropListData", "all"), 0)
check("oversized list after a save: the editor is told it failed", confirmation(B), true)
util.Compress = function(s) return s end

report()
