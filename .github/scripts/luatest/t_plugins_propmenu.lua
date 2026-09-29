dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- Prop Menu (PCR), server side: picking a prop, the ban lists and sending the prop list.
-- The editor lock and saves are in t_plugins_propmenu_editor.lua; set-up in propmenu_env.lua.
local E = dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "propmenu_env.lua")
local set, player, pick, said, counts, resetCounts = E.set, E.player, E.pick, E.said, E.counts, E.resetCounts
local mapProps, disconnect, sentTo = E.mapProps, E.disconnect, E.sentTo

print("\n== a living prop in a round: the normal path must not change ==")
resetCounts()
local p = player()
check("pick: no error", pick(p, "models/props/a.mdl"), "ok")
check("pick: disguise changed", p.ph_prop:GetModel(), "models/props/a.mdl")
check("pick: one use spent (3 -> 2)", p:CheckUsage(), 2)
check("pick: told how many uses are left", said(p, "PCR_USAGE_COUNT"), true)
check("pick: temp prop created", created, 1)
check("pick: temp prop removed", removed, 1)
check("pick: delay stamped", p:GetNWFloat("pcr.LastUsedTime"), CurTime())
p.chat = {}
check("second pick inside the delay: no error", pick(p, "models/props/b.mdl"), "ok")
check("second pick inside the delay: asked to wait", said(p, "PCR_PLS_WAIT"), true)
check("second pick inside the delay: no temp prop", created, 1)
check("second pick inside the delay: still a", p.ph_prop:GetModel(), "models/props/a.mdl")
S.pump(3)
pick(p, "models/props/b.mdl")
check("pick after the delay: changes to b", p.ph_prop:GetModel(), "models/props/b.mdl")
check("pick after the delay: 2 -> 1", p:CheckUsage(), 1)
S.pump(3); p.chat = {}
pick(p, "models/props/c.mdl")
check("last use: 1 -> 0", p:CheckUsage(), 0)
S.pump(3); p.chat = {}; resetCounts()
pick(p, "models/props/a.mdl")
check("no uses left: refused", said(p, "PCR_REACHED_LIMIT"), true)
check("no uses left: no temp prop", created, 0)
check("no uses left: still c", p.ph_prop:GetModel(), "models/props/c.mdl")

set("pcr_max_use", -1)
resetCounts()
p = player()
check("unlimited: allowance is -1", p:CheckUsage(), -1)
pick(p, "models/props/a.mdl")
check("unlimited: disguise changed", p.ph_prop:GetModel(), "models/props/a.mdl")
check("unlimited: allowance untouched", p:CheckUsage(), -1)
check("unlimited: told it is unlimited", said(p, "PCR_USAGE_UNLIMIT"), true)
check("unlimited: temp prop removed", select(2, counts()), 1)
set("pcr_max_use", 3)

S.traceHits = true                      -- no room for the new prop
resetCounts()
p = player()
pick(p, "models/props/a.mdl")
check("no room: told so", said(p, "PCR_NOROOM"), true)
check("no room: disguise unchanged", p.ph_prop:GetModel(), "models/start.mdl")
check("no room: use kept", p:CheckUsage(), 3)
check("no room: temp prop created and removed", created == 1 and removed == 1, true)
check("no room: delay stamped", p:GetNWFloat("pcr.LastUsedTime"), CurTime())
S.traceHits = false

-- The delay is the only throttle on the temp prop, so it must hold even if the exchange throws.
local realExchange = GAMEMODE.PlayerExchangeProp
GAMEMODE.PlayerExchangeProp = function() error("exchange failed") end
resetCounts()
p = player()
check("exchange throws: error surfaces", pick(p, "models/props/a.mdl"), "exchange failed")
check("exchange throws: delay already stamped", p:GetNWFloat("pcr.LastUsedTime"), CurTime())
pick(p, "models/props/b.mdl")
check("exchange throws: next rapid pick makes no temp prop", created, 1)
GAMEMODE.PlayerExchangeProp = realExchange
S.pump(3)
S.entsCreateFails = true
p = player()
check("ents.Create fails: no error", pick(p, "models/props/a.mdl"), "ok")
check("ents.Create fails: use kept", p:CheckUsage(), 3)
S.entsCreateFails = false

print("\n== a pick that changes nothing spends no use and claims no success ==")
p = player{ mdl = "models/props/a.mdl" }
check("same model: no error", pick(p, "models/props/a.mdl"), "ok")
check("same model: use kept (3)", p:CheckUsage(), 3)
check("same model: no 'uses left' message", said(p, "PCR_USAGE_COUNT"), false)
check("same model: delay still stamped (throttles the temp prop)", p:GetNWFloat("pcr.LastUsedTime"), CurTime())
S.pump(3); p.chat = {}
p.ph_prop:SetSkin(1)
pick(p, "models/props/a.mdl")
check("same model, other skin: that is a change (skin -> 0)", p.ph_prop:GetSkin(), 0)
check("same model, other skin: use spent (3 -> 2)", p:CheckUsage(), 2)
S.pump(3); p.chat = {}
pick(p, "models/thin.mdl")
check("too thin: PlayerExchangeProp refuses", said(p, "PHX_PROP_TOO_THIN"), true)
check("too thin: use kept (2)", p:CheckUsage(), 2)
check("too thin: no 'uses left' message", said(p, "PCR_USAGE_COUNT"), false)

print("\n== only a living prop in a round reaches the temp prop ==")
set("ph_prop_must_standing", 0)         -- the only thing that used to stop a dead prop
resetCounts()
p = player{ alive = false }
check("dead prop: no server error", pick(p, "models/props/a.mdl"), "ok")
check("dead prop: no temp prop created", created, 0)
check("dead prop: use kept (3)", p:CheckUsage(), 3)
set("pcr_max_use", -1)
p = player{ alive = false }
for _ = 1, 5 do pick(p, "models/props/b.mdl") end
check("dead prop, unlimited, 5 rapid picks: no temp props", created, 0)
set("pcr_max_use", 3)
local h = player{ team = TEAM_HUNTERS }
check("hunter: no error", pick(h, "models/props/a.mdl"), "ok")
check("hunter: no temp prop", created, 0)
check("hunter: use kept", h:CheckUsage(), 3)
check("hunter: no false success", said(h, "PCR_USAGE_COUNT"), false)
SetGlobalBool("InRound", false)
p = player()
pick(p, "models/props/a.mdl")
check("between rounds: no temp prop", created, 0)
check("between rounds: use kept", p:CheckUsage(), 3)
SetGlobalBool("InRound", true)
pick(p, "models/props/a.mdl")
check("must_standing 0, living prop: still works", p.ph_prop:GetModel(), "models/props/a.mdl")
set("ph_prop_must_standing", 1)

print("\n== pcr_enable is enforced by the server ==")
set("pcr_enable", 0)
resetCounts()
p = player()
check("disabled: no error", pick(p, "models/props/a.mdl"), "ok")
check("disabled: no temp prop", created, 0)
check("disabled: disguise unchanged", p.ph_prop:GetModel(), "models/start.mdl")
check("disabled: use kept", p:CheckUsage(), 3)
set("pcr_enable", 1)
pick(p, "models/props/a.mdl")
check("re-enabled: works again", p.ph_prop:GetModel(), "models/props/a.mdl")

print("\n== invalid-model kick matches its '( n / 4 )' counter ==")
p = player()
for _ = 1, 3 do pick(p, "models/not/in/list.mdl") end
check("3 invalid picks: not kicked", p.kicked == true, false)
pick(p, "models/not/in/list.mdl")
check("4th invalid pick (shows 4 / 4): kicked", p.kicked == true, true)
set("pcr_kick_invalid", 0)
p = player()
for _ = 1, 6 do pick(p, "models/not/in/list.mdl") end
check("pcr_kick_invalid 0: never kicked", p.kicked == true, false)
check("pcr_kick_invalid 0: warned", said(p, "PCR_NOT_EXIST"), true)
set("pcr_kick_invalid", 1)

print("\n== a mid-round joiner starts with the round's allowance ==")
p = S.Player{}
S.fire("PlayerInitialSpawn", p)
check("joiner: pcr_max_use uses (3), not 0", p:CheckUsage(), 3)
set("pcr_max_use", -1)
p = S.Player{}
S.fire("PlayerInitialSpawn", p)
check("joiner, unlimited: -1", p:CheckUsage(), -1)
set("pcr_max_use", 3)
check("joiner: prop data not yet sent", p.pcrHasPropData, false)

print("\n== prop-list send survives the requester leaving ==")
S.net.sent = {}
p = S.Player{}
S.fire("PlayerInitialSpawn", p)
S.receivers["pcr.ClientRequestPropData"](0, p)
check("request: no error on the next tick", #S.pump(0), 0)
check("request: prop list sent", sentTo("pcr.PropListData", p), 1)
check("request: marked as sent", p.pcrHasPropData, true)
p = S.Player{}
S.fire("PlayerInitialSpawn", p)
S.receivers["pcr.ClientRequestPropData"](0, p)
disconnect(p)
local errs = S.pump(0)
check("request then leave: no timer error", errs[1], nil)

print("\n== #211 a prop list too big for one net message is refused, not sent ==")
local function requestSized(size)
  local data = PCR.propDatajson
  PCR.propDatajson, PCR.propDataSize, S.net.sent, S.errors = string.rep("x", size), size, {}, 0
  local pl = S.Player{}
  S.fire("PlayerInitialSpawn", pl); S.receivers["pcr.ClientRequestPropData"](0, pl); S.pump(0)
  PCR.propDatajson, PCR.propDataSize = data, #data
  return sentTo("pcr.PropListData", pl), S.errors
end
local n, e = requestSized(60001)
check("60001 bytes: not sent", n, 0)
check("60001 bytes: the server logs why", e, 1)
n, e = requestSized(60000)
check("60000 bytes: sent, no error (normal play)", n .. "/" .. e, "1/0")

print("\n== the ban list matches map models whatever their case ==")
set("pcr_enable_prop_ban", 1)
S.fileExists["phx_data/prop_model_bans/model_bans.txt"] = true
S.fileExists["phx_data/prop_model_bans/pcr_bans.txt"] = true
S.json = { ["phx_data/prop_model_bans/model_bans.txt"] = { "models/props_c17/furniturecouch001a.mdl" },
           ["phx_data/prop_model_bans/pcr_bans.txt"] = { "models/props_c17/OilDrum001.mdl" } }
mapProps{ "models/props_c17/FurnitureCouch001a.mdl", "models/props_c17/oildrum001.mdl", "models/props/a.mdl" }
PCR._INIT_STORED = false
PCR:PopulateProp()
check("lowercase ban, mixed-case map model: not listed",
  table.HasValue(PCR.PropList, "models/props_c17/furniturecouch001a.mdl"), false)
check("mixed-case ban, lowercase map model: not listed", table.HasValue(PCR.PropList, "models/props_c17/oildrum001.mdl"), false)
check("unbanned prop: still listed", table.HasValue(PCR.PropList, "models/props/a.mdl"), true)
check("ban list: banned prop's pick is refused", (function()
  local pl = player(); pick(pl, "models/props_c17/oildrum001.mdl"); return pl.ph_prop:GetModel() end)(), "models/start.mdl")
set("pcr_enable_prop_ban", 0)
PCR._INIT_STORED = false
PCR:PopulateProp()
check("ban off: couch listed (lowercased)", table.HasValue(PCR.PropList, "models/props_c17/furniturecouch001a.mdl"), true)

print("\n== custom props get the crash-model filter ==")
set("pcr_allow_custom", 1)
S.fileExists["phx_data/prop_chooser_custom/models.txt"] = true
S.json["phx_data/prop_chooser_custom/models.txt"] = { "models/balloons/balloon_dog.mdl", "models/props_collectables/PiePan.mdl" }
PCR:PopulateProp()
check("custom prop: listed", table.HasValue(PCR.PropList, "models/balloons/balloon_dog.mdl"), true)
check("prohibited custom prop: not listed", table.HasValue(PCR.PropList, "models/props_collectables/piepan.mdl"), false)

print("\n== #34 the server ban list stops a model whatever its case ==")
-- A custom prop keeps the case the editor saved it with, and so does the temp prop's GetModel().
local MIXED = "models/props_junk/Mixed_Case.mdl"
table.insert(PCR.PropList, MIXED); S.fileExists[MIXED] = true
PHX.BANNED_PROP_MODELS = { "models/banned.mdl", string.lower(MIXED) }
p = player(); pick(p, MIXED)
check("mixed-case model on the ban list: refused as banned", said(p, "PCR_PROPBANNED"), true)
check("mixed-case model on the ban list: disguise and use kept", p.ph_prop:GetModel() .. p:CheckUsage(), "models/start.mdl3")
set("ph_banned_models", 0)
p = player(); pick(p, MIXED)
check("ph_banned_models 0: the same model is used (normal play)", p.ph_prop:GetModel(), MIXED)
set("ph_banned_models", 1)
table.insert(PCR.PropList, "models/banned.mdl"); S.fileExists["models/banned.mdl"] = true
p = player(); pick(p, "models/banned.mdl")
check("lowercase model on the ban list: refused (normal play)", said(p, "PCR_PROPBANNED"), true)

print("\n== the refusals before the temp prop still refuse (normal play) ==")
resetCounts()
set("pcr_only_allow_certain_groups", 1)
p = player(); pick(p, "models/props/a.mdl")
check("group-only menu, player in no group: told so", said(p, "PCR_ONLY_GROUP"), true)
set("pcr_only_allow_certain_groups", 0)
S.fileExists["models/props/a.mdl"] = false
p = player(); pick(p, "models/props/a.mdl")
check("model missing from the server: told so", said(p, "PCR_MODEL_DONT_EXISTS"), true)
S.fileExists["models/props/a.mdl"] = true
p = player(); p.Crouching = function() return true end; pick(p, "models/props/a.mdl")
check("crouching prop, must stand: told to stand", said(p, "PCR_STAY_ON_GROUND"), true)
check("none of these made a temp prop", created, 0)

print("\n== AddToGroup matches CheckUserGroup's lowercase lookup ==")
p = S.Player{}
p.GetUserGroup = function() return "Supporter" end
check("unknown group: refused", PCR:CheckUserGroup(p), false)
PCR:AddToGroup("Supporter")
check("AddToGroup('Supporter'): member accepted", PCR:CheckUserGroup(p), true)
p.GetUserGroup = function() return "VIP" end
check("preset group, any case: accepted", PCR:CheckUserGroup(p), true)

report()
