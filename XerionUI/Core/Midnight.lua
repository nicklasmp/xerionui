--------------------------------------------------------------------------------
-- XerionUI - Core/Midnight.lua
-- Shared answers to the questions Midnight (12.x) made hard: is this value
-- readable, could this aura event matter, is the client restricting addons
-- right now, and the bits the engine's AuraContainer frames need.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI

local IsSecret = XUI.IsSecret

XUI.BUILD = select(4, GetBuildInfo()) or 0
-- 12.1 brought the AuraContainer frame type and secret player auras in keys.
XUI.IS_121 = XUI.BUILD >= 120100

-- A yes/no question to the client: true, false, or nil when it errored or
-- answered with a secret. The caller decides which way nil points.
function XUI.Ask(fn, ...)
	if not fn then return nil end
	local ok, v = pcall(fn, ...)
	if not ok or IsSecret(v) then return nil end
	return v and true or false
end

-- Could this UNIT_AURA payload have added or removed an aura? A refresh or a
-- stack change cannot, and that is most of what fires in combat. A secret,
-- missing or unreadable payload counts as yes.
do
	local issecrettable = _G.issecrettable
	local function Churns(info)
		if IsSecret(info) or info == nil or (issecrettable and issecrettable(info)) then return true end
		local full, added, removed = info.isFullUpdate, info.addedAuras, info.removedAuraInstanceIDs
		if IsSecret(full) or IsSecret(added) or IsSecret(removed) then return true end
		return (full or added or removed) and true or false
	end
	function XUI.AuraPayloadChurns(info)
		local ok, churns = pcall(Churns, info)
		return not ok or churns
	end
end

-- Whether the client knows an XML template (the AuraContainer kit is asked
-- for, not assumed from a build number).
function XUI.HasTemplate(name)
	local X = C_XMLUtil
	if not (X and X.GetTemplateInfo) then return false end
	local ok, info = pcall(X.GetTemplateInfo, name)
	return ok and info ~= nil
end

-- The aspect a frame needs to hang off a container that has an aura group.
XUI.TAIL_TEMPLATE = "DisableUntrustedLayoutScriptsTemplate"

function XUI.HasAuraContainers()
	return XUI.IS_121 and XUI.HasTemplate("CustomAuraContainerTemplate")
end

-- The lust lockouts: Sated and every class's twin of it.
XUI.SATED_IDS = { 57723, 57724, 80354, 95809, 160455, 264689, 390435, 428628 }

--------------------------------------------------------------------------------
-- Duration text formats for engine-written timers.
--------------------------------------------------------------------------------
local function RuleFormatter(breakpoint)
	local CSU = C_StringUtil
	if not (CSU and CSU.CreateNumericRuleFormatter) then return nil end
	local ok, f = pcall(CSU.CreateNumericRuleFormatter)
	if not (ok and f and f.SetBreakpoints) then return nil end
	if pcall(f.SetBreakpoints, f, { breakpoint }) then return f end
	return nil
end

local wholeFmt, tenthsFmt
local function RoundingUp()
	return (Enum and Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Up) or 1
end

-- Whole seconds, rounded up.
function XUI.DurationTextOptions()
	if wholeFmt == nil then
		wholeFmt = RuleFormatter({ threshold = 0, format = "%d", components = { { step = 1, rounding = RoundingUp() } } }) or false
	end
	if wholeFmt then return { formatter = wholeFmt, textFormatter = wholeFmt } end
	if C_AuraContainerUtil then return {} end
	return { textFormat = "%d" }
end

-- "4.2": tenths, rounded up so a running timer never reads 0.0.
function XUI.TenthsTextOptions()
	if tenthsFmt == nil then
		tenthsFmt = RuleFormatter({ threshold = 0, step = 0.1, rounding = RoundingUp(), format = "%.1f" }) or false
	end
	if tenthsFmt then return { textFormatter = tenthsFmt } end
	return XUI.DurationTextOptions()
end

--------------------------------------------------------------------------------
-- Player state
--------------------------------------------------------------------------------
-- Role from the SPEC (the role a group was joined under sticks through a
-- respec). `unreadable` is returned when the client would not say.
function XUI.PlayerIsTank(unreadable)
	local CSI = C_SpecializationInfo
	local getIndex = (CSI and CSI.GetSpecialization) or _G.GetSpecialization
	local index = getIndex and XUI.Probe(getIndex)
	if index == nil then return unreadable end
	local getRole = (CSI and CSI.GetSpecializationRole) or _G.GetSpecializationRole
	if not getRole then return unreadable end
	local role = XUI.Probe(getRole, index)
	if role == nil then return unreadable end
	return role == "TANK"
end

function XUI.KeyActive()
	local CM = C_ChallengeMode
	if not CM then return false end
	if CM.IsChallengeModeActive and XUI.Ask(CM.IsChallengeModeActive) then return true end
	if CM.GetActiveChallengeMapID and XUI.Probe(CM.GetActiveChallengeMapID) then return true end
	return false
end

function XUI.ClassColor(class)
	if type(class) ~= "string" or IsSecret(class) then return 0.6, 0.6, 0.6 end
	local c = C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class)
	if not c and RAID_CLASS_COLORS then c = RAID_CLASS_COLORS[class] end
	if c and c.r then return c.r, c.g, c.b end
	return 0.6, 0.6, 0.6
end

-- Whether the client restricts addons right now (a fight, a key, a boss, a
-- match). Engine buttons refuse changes then; work waits for it to lift,
-- which ends with PLAYER_REGEN_ENABLED or ADDON_RESTRICTION_STATE_CHANGED.
local HOLD_TYPES = { "Combat", "Encounter", "ChallengeMode", "PvPMatch" }
function XUI.Restricted(types)
	if InCombatLockdown() then return true end
	local R = C_RestrictedActions
	local T = Enum and Enum.AddOnRestrictionType
	if not (R and R.IsAddOnRestrictionActive and T) then return false end
	for _, name in ipairs(types or HOLD_TYPES) do
		local t = T[name]
		if t ~= nil and XUI.Ask(R.IsAddOnRestrictionActive, t) then return true end
	end
	return false
end

-- Sound registrations (C_UnitAuras.AddAuraSound) are refused during a boss
-- encounter and in combat inside a key.
function XUI.AuraSoundsBlocked()
	local R = C_RestrictedActions
	local T = Enum and Enum.AddOnRestrictionType
	if not (R and R.IsAddOnRestrictionActive and T) then return InCombatLockdown() end
	return XUI.Ask(R.IsAddOnRestrictionActive, T.Encounter)
		or (XUI.Ask(R.IsAddOnRestrictionActive, T.Combat) and XUI.Ask(R.IsAddOnRestrictionActive, T.ChallengeMode))
		or false
end

--------------------------------------------------------------------------------
-- AuraContainer helpers
--------------------------------------------------------------------------------
-- The 2026-07 PTR renamed the flow layout calls (SetAuraLayout* to
-- SetFlowLayout*); both are tried.
function XUI.ContainerFlow(c, new, old, ...)
	local f = c[new] or (old and c[old])
	if f then return pcall(f, c, ...) end
	return false
end

-- Bar fill options for SetDurationBar: drain as the seconds go.
function XUI.DurationBarOptions()
	local o = {}
	if Enum and Enum.StatusBarInterpolation then o.interpolation = Enum.StatusBarInterpolation.Immediate end
	if Enum and Enum.StatusBarTimerDirection then o.direction = Enum.StatusBarTimerDirection.RemainingTime end
	return o
end
