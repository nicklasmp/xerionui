--------------------------------------------------------------------------------
-- Stoneform Bleed Alert
-- Dwarves: shows the Stoneform icon (and optionally speaks or plays a sound)
-- while you have a bleed on you and Stoneform is ready to remove it.
--
-- Midnight: an aura's dispel type or the spell's cooldown can be secret in
-- restricted content. A secret reads as "unknown" and the alert stays hidden
-- rather than guessing.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates

local STONEFORM = 20594
local FALLBACK_ICON = 132275

local M = XUI:NewModule("Stoneform", {
	name = "Stoneform Bleed Alert",
	desc = "Shows Stoneform when you have a bleed and Stoneform is ready.",
	category = "combat",
	icon = FALLBACK_ICON,
	iconSpell = STONEFORM, -- the dwarf racial's own icon in the options
	order = 50,
	defaults = {
		icon = T.Icon(48),
		border = T.Border(),
		glow = T.Glow(false),
		alert = T.Alert("TTS", { text = "Bleed detected" }),
		position = T.Position(0, 140, "HIGH"),
	},
})

function M:CanLoad()
	if not XUI.IsSpellKnown(STONEFORM) then
		return false, "Requires the Dwarf racial Stoneform."
	end
	return true
end

local Readable, IsSecret = XUI.Readable, XUI.IsSecret
local GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
local GetSpellCooldown = C_Spell and C_Spell.GetSpellCooldown

local display
local bleeding, shown = false, false

local function Display()
	if display then return display end
	display = XUI.Widgets:CreateIcon("XUI_Stoneform")
	display:SetIcon(XUI.GetSpellIcon(STONEFORM, FALLBACK_ICON))
	display:Hide()
	XUI.Movers:Register(display, M, "position")
	return display
end

local function ScanBleed()
	for i = 1, 40 do
		local aura = GetAuraDataByIndex("player", i, "HARMFUL")
		if IsSecret(aura) or aura == nil then return false end
		local dispel = aura.dispelName
		if not IsSecret(dispel) and dispel == "Bleed" then return true end
	end
	return false
end

local function HasBleed()
	if not GetAuraDataByIndex then return false end
	local ok, found = pcall(ScanBleed)
	return ok and found or false
end

-- Whether Stoneform is off cooldown (a rolling global cooldown counts as
-- ready). The cooldown record has had different fields over the builds, so each
-- is tried; an answer the client will not give counts as ready - a reminder that
-- stays silent is worse than one that is sometimes early.
local function StoneformReady()
	if not GetSpellCooldown then return true end
	local info = XUI.Probe(GetSpellCooldown, STONEFORM)
	if type(info) ~= "table" then return true end
	local onGCD = Readable(info.isOnGCD)
	local active = Readable(info.isActive)
	if type(active) == "boolean" then return not active or onGCD == true end
	local remaining = Readable(info.timeUntilEndOfStartRecovery)
	if type(remaining) == "number" then return remaining <= 0 or onGCD == true end
	local duration = Readable(info.duration)
	if type(duration) == "number" then return duration <= 0 or onGCD == true end
	return true
end

function M:Update(fromAura)
	local want = bleeding and StoneformReady()
	if want and not shown and fromAura then
		XUI.Audio:Play(self.db.alert)
	end
	shown = want
	self:Refresh()
end

function M:OnEnable()
	Display()
	self:RegisterUnitEvent("UNIT_AURA", "player", function(self)
		local was = bleeding
		bleeding = HasBleed()
		-- the cooldown only matters while something bleeds
		if bleeding and not was then
			self:RegisterEvent("SPELL_UPDATE_COOLDOWN", function(self) self:Update(false) end)
		elseif was and not bleeding then
			self:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
		end
		self:Update(true)
	end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(self)
		bleeding = HasBleed()
		self:Update(false)
	end)
	bleeding = HasBleed()
	shown = bleeding and StoneformReady()
end

function M:OnDisable()
	bleeding, shown = false, false
end

function M:OnRefresh()
	if not (display or self:IsPreview()) then return end
	local d = Display()
	local db = self.db
	XUI.Movers:Apply(d)
	d:ApplyLayout(db.icon, db.border)
	local visible = self:IsPreview() or (self:IsRunning() and shown)
	d:SetGlow(db.glow, visible)
	d:SetShown(visible)
end

function M:DebugInfo()
	local out = {
		("bleeding: %s, icon showing: %s, Stoneform ready: %s"):format(tostring(bleeding), tostring(shown), tostring(StoneformReady())),
	}
	local info = GetSpellCooldown and XUI.Probe(GetSpellCooldown, STONEFORM)
	if type(info) == "table" then
		local parts = {}
		for k, v in pairs(info) do parts[#parts + 1] = k .. "=" .. (IsSecret(v) and "<secret>" or tostring(v)) end
		table.sort(parts)
		out[#out + 1] = "cooldown record: " .. table.concat(parts, ", ")
	else
		out[#out + 1] = "cooldown record: unreadable"
	end
	-- what the harmful auras on you look like to this addon
	for i = 1, 12 do
		local ok, aura = pcall(GetAuraDataByIndex, "player", i, "HARMFUL")
		if not ok or aura == nil then break end
		if IsSecret(aura) then out[#out + 1] = ("  debuff %d: secret"):format(i) break end
		local dispel = aura.dispelName
		out[#out + 1] = ("  debuff %d: %s, dispel type %s"):format(i, IsSecret(aura.name) and "<secret name>" or tostring(aura.name), IsSecret(dispel) and "<secret>" or tostring(dispel))
	end
	return out
end

-- Options test button.
function M:TestAlert()
	XUI.Audio:Play(self.db.alert, nil, true)
end
