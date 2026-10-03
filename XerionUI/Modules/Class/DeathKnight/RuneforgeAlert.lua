--------------------------------------------------------------------------------
-- Runeforge alert (Death Knight)
-- "Check Runeforge" when a weapon carries a rune you did not pick for your
-- current spec and hero talent. Each spec/hero setup has a list of accepted
-- runes per weapon slot, edited in the options; a weapon with no accepted rune
-- picked, or none equipped, is not checked. Never shown in combat, while dead
-- or in a key.
-- Ported from ItruliaQoL (MIT, (c) Itrulia).
--
-- An equipped weapon carries its runeforge as the enchant field of its item
-- link, which is what the check compares.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates

local BLOOD, FROST, UNHOLY = 250, 251, 252
-- hero talent subtree IDs, as C_ClassTalents.GetActiveHeroTalentSpec returns
local SANLAYN, RIDER, DEATHBRINGER = 31, 32, 33
local FROSTBANE_TALENT = 455993

local RUNES = {
	{ enchantId = 3368, spellId = 53344, name = "Rune of the Fallen Crusader" },
	{ enchantId = 3370, spellId = 53343, name = "Rune of Razorice" },
	{ enchantId = 3847, spellId = 62158, name = "Rune of the Stoneskin Gargoyle" },
	{ enchantId = 6241, spellId = 326801, name = "Rune of Sanguination" },
	{ enchantId = 6245, spellId = 327082, name = "Rune of the Apocalypse" },
	{ enchantId = 6244, spellId = 326977, name = "Rune of Unending Thirst" },
	{ enchantId = 6243, spellId = 326911, name = "Rune of Hysteria" },
	{ enchantId = 6242, spellId = 326855, name = "Rune of Spellwarding" },
}
local FALLEN, RAZORICE, STONESKIN, SANGUINATION, APOCALYPSE = 3368, 3370, 3847, 6241, 6245

local function MH(d) return { key = "mainHand", label = "Main hand", slot = INVSLOT_MAINHAND, defaults = d } end
local function OH(d) return { key = "offHand", label = "Off hand", slot = INVSLOT_OFFHAND, defaults = d } end

local SETUPS = {
	{ key = "bloodSanlayn", label = "Blood - San'layn", spec = BLOOD, hero = SANLAYN, slots = { MH({ SANGUINATION }) } },
	{ key = "bloodDeathbringer", label = "Blood - Deathbringer", spec = BLOOD, hero = DEATHBRINGER, slots = { MH({ SANGUINATION }) } },
	{
		key = "frostFrostbane", label = "Frost - Frostbane", spec = FROST,
		matches = function() return XUI.IsSpellKnown(FROSTBANE_TALENT) end,
		slots = { MH({ RAZORICE }), OH({ FALLEN }) },
	},
	{ key = "frostWeapons", label = "Frost", spec = FROST, slots = { MH({ FALLEN, STONESKIN }), OH({ FALLEN, STONESKIN }) } },
	{ key = "unholySanlayn", label = "Unholy - San'layn", spec = UNHOLY, hero = SANLAYN, slots = { MH({ APOCALYPSE }) } },
	{ key = "unholyRider", label = "Unholy - Rider of the Apocalypse", spec = UNHOLY, hero = RIDER, slots = { MH({ APOCALYPSE }) } },
}

local function DefaultSetups()
	local out = {}
	for _, setup in ipairs(SETUPS) do
		local slots = {}
		for _, slot in ipairs(setup.slots) do
			local runes = {}
			for _, id in ipairs(slot.defaults) do runes[id] = true end
			slots[slot.key] = runes
		end
		out[setup.key] = slots
	end
	return out
end

local M = XUI:NewModule("RuneforgeAlert", {
	name = "Runeforge Alert",
	desc = "Warns when your weapon carries a runeforge you did not pick for this build.",
	category = "class",
	icon = [[Interface\Icons\Spell_Deathknight_RuneTap]],
	order = 100,
	classes = { "DEATHKNIGHT" },
	untested = true,
	defaults = {
		text = "Check Runeforge",
		color = { 1, 1, 1, 1 },
		font = T.Font(14),
		setups = DefaultSetups(),
		position = T.Position(0, 25),
	},
})
M.RUNES, M.SETUPS = RUNES, SETUPS

local display

local function Display()
	if display then return display end
	display = XUI.Widgets:CreateText("XUI_RuneforgeAlert")
	display:Hide()
	XUI.Movers:Register(display, M, "position")
	return display
end

local function EquippedRune(slot)
	local link = GetInventoryItemLink("player", slot)
	if not link then return nil end
	return tonumber(link:match("item:%d+:(%d*)"))
end

-- accepted runes of a slot: a set of enchant IDs
function M:Accepted(setupKey, slotKey)
	local setup = self.db.setups and self.db.setups[setupKey]
	return setup and setup[slotKey]
end

function M:SetAccepted(setupKey, slotKey, enchantId, on)
	local setups = self.db.setups
	setups[setupKey] = setups[setupKey] or {}
	setups[setupKey][slotKey] = setups[setupKey][slotKey] or {}
	-- false, not nil: a default that was switched off has to stay off
	setups[setupKey][slotKey][enchantId] = on and true or false
end

function M:ActiveSetup()
	local spec = XUI.GetSpecID()
	if not spec then return nil end
	local CT = C_ClassTalents
	local hero = CT and CT.GetActiveHeroTalentSpec and XUI.Probe(CT.GetActiveHeroTalentSpec)
	for _, setup in ipairs(SETUPS) do
		if setup.spec == spec and (not setup.hero or setup.hero == hero) and (not setup.matches or setup.matches()) then
			return setup
		end
	end
	return nil
end

local function AnyAccepted(runes)
	if not runes then return false end
	for _, accepted in pairs(runes) do
		if accepted == true then return true end
	end
	return false
end

function M:IsWrong()
	if XUI.Ask(UnitAffectingCombat, "player") or XUI.Ask(UnitIsDeadOrGhost, "player") then return false end
	if XUI.KeyActive() then return false end
	local setup = self:ActiveSetup()
	if not setup then return false end
	for _, slot in ipairs(setup.slots) do
		local runes = self:Accepted(setup.key, slot.key)
		if AnyAccepted(runes) and GetInventoryItemID("player", slot.slot) then
			local equipped = EquippedRune(slot.slot)
			if not equipped or runes[equipped] ~= true then return true end
		end
	end
	return false
end

function M:Update()
	if not display then return end
	display:SetShown(self:IsPreview() or (self.running and self:IsWrong()))
end

function M:OnEnable()
	Display()
	for _, e in ipairs({
		"PLAYER_ENTERING_WORLD", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED",
		"PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "CHALLENGE_MODE_START",
		"CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET",
	}) do
		self:RegisterEvent(e, function(self) self:RefreshSoon() end)
	end
	self:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player", function(self) self:RefreshSoon() end)
end

function M:OnDisable()
	if display and not self:IsPreview() then display:Hide() end
end

function M:OnRefresh()
	if not (display or self:IsPreview()) then return end
	local d, db = Display(), self.db
	XUI.Movers:Apply(d)
	d:ApplyStyle(db.font)
	d:SetText(db.text)
	d:SetTextColor(XUI.UnpackColor(db.color))
	self:Update()
end

function M:DebugInfo()
	local setup = self:ActiveSetup()
	local out = { ("active setup: %s, wrong runeforge: %s"):format(setup and setup.label or "none for this spec/hero tree", tostring(self:IsWrong())) }
	if setup then
		for _, slot in ipairs(setup.slots) do
			out[#out + 1] = ("  %s: equipped rune %s"):format(slot.label, tostring(EquippedRune(slot.slot)))
		end
	end
	return out
end
