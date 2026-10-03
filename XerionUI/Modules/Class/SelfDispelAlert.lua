--------------------------------------------------------------------------------
-- Self dispel alert (every class)
-- An icon (and a line of text) when you carry a debuff you can dispel off
-- yourself and the spell that does it is ready: Magic, Curse, Disease, Poison
-- or Bleed, whichever of your class dispels, a talent or the dwarf racials
-- covers. Each type resolves to the first known source covering it, class
-- dispels first.
-- Ported from ItruliaQoL (MIT, (c) Itrulia).
--
-- The auras are secret in keys, so the engine does the looking: one aura
-- container per dispel type holds one slot filtered to that type on you
-- (includeDispelTypes), and its button carries our icon and text, so it shows
-- exactly while you have such a debuff. Whether the dispel is ready is read off
-- the spell's cooldown (a rolling global cooldown counts as ready); an
-- unreadable cooldown falls back to the cooldown duration object, whose
-- zero-ness the client turns into the container's alpha. Layout is measured
-- from a parked font string, since the live copies hang off engine buttons that
-- refuse reads while auras are secret. A restyle the client refuses waits for
-- the fight to end.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates
local Style = XUI.Style

local FALLBACK_SPELL = 20594 -- Stoneform, for characters with no self dispel
local RACIAL_TYPES = { Magic = true, Curse = true, Disease = true, Poison = true, Bleed = true }
local TYPES = { "Magic", "Curse", "Disease", "Poison", "Bleed" }
local GAP = 4

-- class dispels first, spec versions before base ones, the dwarf racials last
local SOURCES = {
	{ key = "DRUID", spellId = 88423, types = { Magic = true, Curse = true, Poison = true } }, -- Nature's Cure
	{ key = "DRUID", spellId = 2782, types = { Curse = true, Poison = true } }, -- Remove Corruption
	{ key = "EVOKER", spellId = 374251, types = { Bleed = true, Curse = true, Disease = true, Poison = true } }, -- Cauterizing Flame
	{ key = "EVOKER", spellId = 360823, types = { Magic = true, Poison = true } }, -- Naturalize
	{ key = "EVOKER", spellId = 365585, types = { Poison = true } }, -- Expunge
	{ key = "HUNTER", spellId = 5384, talentSpellId = 459517, types = { Poison = true, Disease = true } }, -- Feign Death via Emergency Salve
	{ key = "MAGE", spellId = 475, types = { Curse = true } }, -- Remove Curse
	{ key = "MONK", spellId = 115450, types = { Magic = true, Poison = true, Disease = true } }, -- Detox (Mistweaver)
	{ key = "MONK", spellId = 218164, types = { Poison = true, Disease = true } }, -- Detox
	{ key = "PALADIN", spellId = 4987, types = { Magic = true, Poison = true, Disease = true } }, -- Cleanse
	{ key = "PALADIN", spellId = 213644, types = { Poison = true, Disease = true } }, -- Cleanse Toxins
	{ key = "PRIEST", spellId = 527, types = { Magic = true, Disease = true } }, -- Purify
	{ key = "PRIEST", spellId = 213634, types = { Disease = true } }, -- Purify Disease
	{ key = "SHAMAN", spellId = 77130, types = { Magic = true, Curse = true } }, -- Purify Spirit
	{ key = "SHAMAN", spellId = 51886, types = { Curse = true } }, -- Cleanse Spirit
	{ key = "RACIAL", spellId = 20594, types = RACIAL_TYPES }, -- Stoneform
	{ key = "RACIAL", spellId = 265221, types = RACIAL_TYPES }, -- Fireblood
}
local SOURCE_KEYS = {
	{ value = "DRUID", text = "Druid" }, { value = "EVOKER", text = "Evoker" }, { value = "HUNTER", text = "Hunter" },
	{ value = "MAGE", text = "Mage" }, { value = "MONK", text = "Monk" }, { value = "PALADIN", text = "Paladin" },
	{ value = "PRIEST", text = "Priest" }, { value = "SHAMAN", text = "Shaman" }, { value = "RACIAL", text = "Racials (Stoneform, Fireblood)" },
}

local M = XUI:NewModule("SelfDispelAlert", {
	name = "Self Dispel Alert",
	desc = "Shows when you have a dispellable debuff and your dispel is ready.",
	category = "class",
	icon = [[Interface\Icons\Spell_Holy_DispelMagic]],
	order = 120,
	untested = true,
	defaults = {
		text = "",
		showText = true,
		showIcon = true,
		hideOnCooldown = true,
		disableInRaid = false,
		enabledSources = {},
		color = { 1, 1, 1, 1 },
		icon = T.Icon(28),
		border = T.Border(),
		font = T.Font(14),
		position = T.Position(0, -100),
	},
})
M.SOURCES, M.SOURCE_KEYS = SOURCES, SOURCE_KEYS

function M:CanLoad()
	if not XUI.HasAuraContainers() then return false, "Needs the 12.1 aura containers." end
	return true
end

local IsSecret = XUI.IsSecret
local gate, preview, containers, alerts
local typeSources, primary, signature
local stylePending = false

-- a parked font string measures the text, away from the engine's buttons
local measureHost = CreateFrame("Frame")
measureHost:Hide()
local measure = measureHost:CreateFontString(nil, "BACKGROUND")
measure:SetPoint("CENTER")

function M:IsSourceEnabled(key) return self.db.enabledSources[key] ~= false end
function M:SetSourceEnabled(key, on) self.db.enabledSources[key] = on and true or false end

-- cached: the spellbook is not necessarily readable at login
function M:Resolve()
	local map, first = {}, nil
	for _, s in ipairs(SOURCES) do
		if self:IsSourceEnabled(s.key) and (not s.talentSpellId or XUI.IsSpellKnown(s.talentSpellId)) and XUI.IsSpellKnown(s.spellId) then
			for _, token in ipairs(TYPES) do
				if s.types[token] and not map[token] then
					map[token] = s
					first = first or s
				end
			end
		end
	end
	typeSources, primary = map, first
	local parts = {}
	for _, token in ipairs(TYPES) do parts[#parts + 1] = token .. "=" .. (map[token] and map[token].spellId or 0) end
	signature = table.concat(parts, ",")
end

local function SourceFor(display)
	local token = display and display.dispelType
	return (token and typeSources and typeSources[token]) or primary
end

local function SpellFor(display)
	local s = SourceFor(display)
	return s and s.spellId or FALLBACK_SPELL
end

local function TextFor(display)
	if not M.db.showText then return "" end
	local t = M.db.text
	if t and t ~= "" then return t end
	return XUI.GetSpellName(SpellFor(display))
end

local function IconSize()
	local i = Style:Resolve("icon", M.db.icon)
	return i.width or i.size or 28
end

local function DisplaySize(display)
	local db = M.db
	local text = TextFor(display)
	local showText = text ~= ""
	local tw, th = 0, 0
	if showText then
		Style:ApplyFont(measure, db.font)
		measure:SetText(text)
		tw, th = measure:GetStringWidth(), measure:GetStringHeight()
	end
	local icon = db.showIcon and IconSize() or 0
	local w = icon + (showText and (tw + (db.showIcon and GAP or 0)) or 0)
	return math.max(w, 1), math.max(icon, th, 1)
end

-- Shared by the preview and the live copies on engine buttons: no scripts, no events.
local function CreateDisplay(parent)
	local d = CreateFrame("Frame", nil, parent)
	d:EnableMouse(false)
	d.icon = CreateFrame("Frame", nil, d)
	d.icon.tex = d.icon:CreateTexture(nil, "ARTWORK")
	d.icon.border = Style:Border(d.icon)
	d.text = d:CreateFontString(nil, "OVERLAY")
	Style:ApplyFont(d.text, nil, 12)
	return d
end

local function StyleDisplay(d)
	local db = M.db
	local text = TextFor(d)
	local showText, showIcon = text ~= "", db.showIcon
	local width = DisplaySize(d)
	Style:ApplyFont(d.text, db.font)
	d.text:SetText(text)
	d.text:SetJustifyH("LEFT")
	d.text:SetTextColor(XUI.UnpackColor(db.color))
	d.text:SetShown(showText)
	d.icon:SetShown(showIcon)
	local size = IconSize()
	d.icon:SetSize(size, size)
	local inset = d.icon.border:Apply(db.border)
	d.icon.tex:ClearAllPoints()
	d.icon.tex:SetPoint("TOPLEFT", d.icon, "TOPLEFT", inset, -inset)
	d.icon.tex:SetPoint("BOTTOMRIGHT", d.icon, "BOTTOMRIGHT", -inset, inset)
	Style:IconTexCoord(d.icon.tex, size, size)
	d.icon.tex:SetTexture(XUI.GetSpellIcon(SpellFor(d), 134400))
	d.icon:ClearAllPoints()
	d.text:ClearAllPoints()
	if showIcon then d.icon:SetPoint("LEFT", d, "CENTER", -width / 2, 0) end
	if showText and showIcon then
		d.text:SetPoint("LEFT", d.icon, "RIGHT", GAP, 0)
	elseif showText then
		d.text:SetPoint("LEFT", d, "CENTER", -width / 2, 0)
	end
end

local function Gate()
	if gate then return gate end
	gate = CreateFrame("Frame", "XUI_SelfDispelAlert", UIParent)
	gate:SetSize(28, 28)
	gate:Hide()
	gate.preview = CreateDisplay(gate)
	gate.preview:SetAllPoints(gate)
	gate.preview:Hide()
	XUI.Movers:Register(gate, M, "position")
	return gate
end

local function InitButton(token, button)
	pcall(button.SetMouseClickEnabled, button, false)
	pcall(button.SetMouseMotionEnabled, button, false)
	pcall(button.SetScale, button, 1)
	button:SetSize(1, 1)
	button:SetPoint("CENTER", gate, "CENTER")
	local d = CreateDisplay(button)
	d.dispelType = token
	-- rect from the gate, visibility from the button's parent chain
	d:SetAllPoints(gate)
	alerts[#alerts + 1] = d
	pcall(StyleDisplay, d)
end

local function EnsureContainers()
	if containers then return end
	if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then C_AddOns.LoadAddOn("Blizzard_AuraContainer") end
	containers, alerts = {}, {}
	for _, token in ipairs(TYPES) do
		local ok, c = pcall(CreateFrame, "AuraContainer", nil, gate, "CustomAuraContainerTemplate")
		if ok and c then
			c:SetPoint("CENTER", gate, "CENTER")
			c:SetSize(1, 1)
			c:SetScale(1)
			pcall(c.AddAuraSlot, c, "dispel", "HARMFUL", {
				candidateFilters = { includeDispelTypes = { [token] = true } },
				initializeFrame = function(button) InitButton(token, button) end,
			})
			pcall(c.SetUnit, c, "player")
			pcall(c.UpdateAllAuras, c)
			containers[token] = c
		end
	end
end

-- true, false, or nil for unreadable. A rolling GCD counts as ready, or the
-- alert would flicker with the rotation.
local function IsReady(source)
	if not source then return nil end
	local ok, info = pcall(C_Spell.GetSpellCooldown, source.spellId)
	if not ok or IsSecret(info) or type(info) ~= "table" then return nil end
	local remaining, onGCD = info.timeUntilEndOfStartRecovery, info.isOnGCD
	if IsSecret(remaining) or IsSecret(onGCD) or type(remaining) ~= "number" then return nil end
	return remaining == 0 or onGCD == true
end

local function ApplyCooldownAlpha(target, source)
	local ready = IsReady(source)
	if ready ~= nil then
		target:SetAlpha(ready and 1 or 0)
		return
	end
	local ok, duration = pcall(function()
		return C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(source.spellId)
	end)
	if ok and not IsSecret(duration) and duration ~= nil and target.SetAlphaFromBoolean then
		if pcall(function() target:SetAlphaFromBoolean(duration:IsZero()) end) then return end
	end
	target:SetAlpha(1)
end

function M:ApplyGates()
	if not containers then return end
	local gated = self.db.hideOnCooldown and not self:IsPreview()
	local shown = self.running and not (XUI.Ask(UnitOnTaxi, "player") or XUI.Ask(UnitInVehicle, "player"))
		and not (self.db.disableInRaid and IsInRaid())
	for token, c in pairs(containers) do
		local source = typeSources and typeSources[token]
		if not source then
			c:SetAlpha(0)
		elseif not gated then
			c:SetAlpha(1)
		else
			ApplyCooldownAlpha(c, source)
		end
		c:SetShown(shown and not self:IsPreview())
	end
end

local function Restyle()
	if not alerts then return end
	local denied = false
	for _, d in ipairs(alerts) do
		if not pcall(StyleDisplay, d) then denied = true end
	end
	stylePending = denied
end

function M:OnEnable()
	Gate()
	self:Resolve()
	EnsureContainers()
	local function resolve(self)
		local previous = signature
		self:Resolve()
		if signature ~= previous then self:Refresh() end
		self:ApplyGates()
	end
	for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED" }) do
		self:RegisterEvent(e, resolve)
	end
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function(self)
		if stylePending then Restyle() end
		self:ApplyGates()
	end)
	for _, e in ipairs({ "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED" }) do
		self:RegisterEvent(e, "ApplyGates")
	end
	self:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player", "ApplyGates")
	self:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player", "ApplyGates")
	-- the cooldown gate follows the dispel's cooldown
	self:NewTicker(0.2, function(self) self:ApplyGates() end)
end

function M:OnDisable()
	if containers then
		for _, c in pairs(containers) do c:SetShown(false) end
	end
	if gate and not self:IsPreview() then gate:Hide() end
end

function M:OnRefresh()
	if not (gate or self:IsPreview()) then return end
	local g = Gate()
	XUI.Movers:Apply(g)
	if not typeSources then self:Resolve() end
	g:SetSize(DisplaySize(g.preview))
	StyleDisplay(g.preview)
	g.preview:SetShown(self:IsPreview())
	if self.running then
		EnsureContainers()
		Restyle()
	end
	g:SetShown(self:IsPreview() or self.running)
	self:ApplyGates()
end

function M:DebugInfo()
	return {
		("dispel sources by type: %s"):format(signature or "not resolved"),
		("containers: %s, restyle waiting: %s"):format(containers and "built" or "no", tostring(stylePending)),
	}
end
