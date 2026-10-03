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

local function StoneformReady()
	if not GetSpellCooldown then return false end
	local info = XUI.Probe(GetSpellCooldown, STONEFORM)
	if type(info) ~= "table" then return false end
	local active = Readable(info.isActive)
	if active == nil then return false end
	local onGCD = Readable(info.isOnGCD)
	return not active or onGCD == true
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

-- Options test button.
function M:TestAlert()
	XUI.Audio:Play(self.db.alert, nil, true)
end
