dofile((debug.getinfo(1, "S").source:match("@(.*/)") or "./") .. "runner.lua")

-- PHX:CanMutePlayer (base_phx cl_scores.lua): who may voice-mute whom from the
-- scoreboard and the F1 Player Muting tab. The groups ticked in the F1 Admin
-- Groups tab ("disallow Voice Mute") are PHX.IgnoreMutedUserGroup.

-- A straight ULib-style chain: each group inherits everything below it, so
-- CheckGroup(g) means "my group is g or ranks above it" - what ULib's
-- Player:CheckGroup answers by walking the UCL inheritance chain.
local RANK = { user = 1, vip = 2, operator = 3, admin = 4, superadmin = 5 }
local STAFF = { admin = true, superadmin = true }

local function Ply(group, ulib)
  local p = S.Player{ staff = STAFF[group] == true }
  p.GetUserGroup = function() return group end
  if ulib then
    p.CheckGroup = function(self, g) return RANK[self:GetUserGroup()] >= RANK[g] end
  end
  return p
end

local lp
function LocalPlayer() return lp end

loadblocks("cl_scores.lua@CanMutePlayer",
  extract("gamemodes/base_phx/gamemode/cl_scores.lua", [[^function PHX:CanMutePlayer]]))

local function can(me, them, ulib, ticked)
  PHX.IgnoreMutedUserGroup = ticked or { superadmin = true, admin = true }   -- sh_config.lua default
  lp = Ply(me, ulib)
  return PHX:CanMutePlayer(Ply(them, ulib))
end

print("\n== ULib server: the rank rule is unchanged for normal play ==")
check("user mutes user", can("user", "user", true), true)
check("user cannot mute an admin", can("user", "admin", true), false)
check("admin mutes a user", can("admin", "user", true), true)
check("superadmin mutes an admin (staff keep the rank rule)", can("superadmin", "admin", true), true)
check("admin cannot mute a superadmin", can("admin", "superadmin", true), false)
check("operator mutes an unticked vip", can("operator", "vip", true), true)

print("\n== ULib server: a ticked group is protected from non-staff ==")
local vip = { superadmin = true, admin = true, vip = true }
check("operator cannot mute a ticked vip", can("operator", "vip", true, vip), false)
check("vip cannot mute a ticked vip", can("vip", "vip", true, vip), false)
check("admin still mutes a ticked vip", can("admin", "vip", true, vip), true)
check("ticking vip leaves users mute-able", can("operator", "user", true, vip), true)

print("\n== No ULib: PH:X's own rule ==")
check("user mutes user", can("user", "user", false), true)
check("nobody mutes staff", can("superadmin", "admin", false), false)
check("ticked vip: user cannot mute", can("user", "vip", false, vip), false)
check("unticked vip: user mutes", can("user", "vip", false), true)

print("\n== Invalid players ==")
lp = Ply("admin", true)
check("NULL target", PHX:CanMutePlayer(NULL), false)
lp = NULL
check("no local player yet", PHX:CanMutePlayer(Ply("user", true)), false)

report()
