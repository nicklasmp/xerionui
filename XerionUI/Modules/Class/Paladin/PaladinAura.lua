--------------------------------------------------------------------------------
-- Paladin aura reminder (every spec), one icon at a time:
--   * Crusader Aura on (mounted or not): the Devotion Aura icon with
--     "Devotion Aura missing", so the switch back is not forgotten.
--   * Mounted and Crusader Aura NOT on: the Crusader Aura icon, a hint to
--     switch for the faster mount speed.
-- Anything else shows nothing. "Only in Mythic+" keeps it to a key (or a
-- Mythic dungeon before the key goes in).
--
-- The answers do not come from the buff (Devotion Aura is contextually secret
-- on 12.x): paladin auras are shapeshift forms, so the active one is read off
-- the stance bar - GetShapeshiftFormInfo(i) gives each slot's spell ID and
-- whether it is on. The bar also says which auras the paladin has at all. A
-- secret answer shows nothing: a warning that fails open would shout at a
-- paladin who did nothing wrong. The Mythic+ gate is the other way round: an
-- unclear answer counts as "in a key".
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates
local Style = XUI.Style

local DEVOTION, CRUSADER = 465, 32223
local TEXTS = { [DEVOTION] = "Devotion Aura missing", [CRUSADER] = "Switch to Crusader Aura" }
local ICONS = {
	[DEVOTION] = [[Interface\Icons\Spell_Holy_DevotionAura]],
	[CRUSADER] = [[Interface\Icons\Spell_Holy_CrusaderAura]],
}
-- [side] = { text point, icon point, x gap, y gap }
local TEXT_ANCHORS = {
	BOTTOM = { "TOP", "BOTTOM", 0, -4 },
	TOP = { "BOTTOM", "TOP", 0, 4 },
	LEFT = { "RIGHT", "LEFT", -6, 0 },
	RIGHT = { "LEFT", "RIGHT", 6, 0 },
	CENTER = { "CENTER", "CENTER", 0, 0 },
}
local SIDES = {
	{ value = "BOTTOM", text = "Below" }, { value = "TOP", text = "Above" },
	{ value = "LEFT", text = "Left" }, { value = "RIGHT", text = "Right" }, { value = "CENTER", text = "On the icon" },
}
local MYTHIC_DIFFICULTY = { [8] = true, [23] = true }

local M = XUI:NewModule("PaladinAura", {
	name = "Paladin Aura Reminder",
	desc = "Reminds you of Devotion Aura after Crusader Aura, and of Crusader Aura on a mount.",
	category = "class",
	icon = [[Interface\Icons\Spell_Holy_DevotionAura]],
	order = 30,
	classes = { "PALADIN" },
	untested = true,
	defaults = {
		mplusOnly = true,
		icon = T.Icon(48),
		border = T.Border(),
		text = T.Font(18, { color = { 0.96, 0.55, 0.73, 1 } }),
		textSide = "BOTTOM",
		textX = 0,
		textY = 0,
		position = T.Position(0, 160, "HIGH"),
	},
})
M.SIDES = SIDES

local IsSecret = XUI.IsSecret
local display

local function Display()
	if display then return display end
	display = XUI.Widgets:CreateIcon("XUI_PaladinAura")
	display:Hide()
	display.label = display.overlay:CreateFontString(nil, "OVERLAY")
	Style:ApplyFont(display.label, nil, 12)
	XUI.Movers:Register(display, M, "position")
	return display
end

-- ok, active aura's spell ID (nil = none on), Devotion on the bar, Crusader on the bar
local function ReadBar()
	local okN, n = pcall(GetNumShapeshiftForms)
	if not okN or IsSecret(n) or not n then return false end
	local active, hasDevo, hasCrus
	for i = 1, n do
		local ok, _, isActive, _, spellID = pcall(GetShapeshiftFormInfo, i)
		if not ok or IsSecret(isActive) or IsSecret(spellID) then return false end
		if spellID == DEVOTION then hasDevo = true elseif spellID == CRUSADER then hasCrus = true end
		if isActive then active = spellID end
	end
	return true, active, hasDevo, hasCrus
end

local function InMythicPlus()
	local CM = C_ChallengeMode
	if CM and CM.IsChallengeModeActive then
		local ok, v = pcall(CM.IsChallengeModeActive)
		if ok and (IsSecret(v) or v) then return true end
	end
	local ok, _, kind, difficulty = pcall(GetInstanceInfo)
	if not ok or IsSecret(kind) or IsSecret(difficulty) then return true end
	return kind == "party" and MYTHIC_DIFFICULTY[difficulty] or false
end

-- the spell ID whose icon should show, or nil
local function Wanted()
	if M:IsPreview() then return DEVOTION end
	if not M.running then return nil end
	if XUI.Ask(UnitIsDeadOrGhost, "player") or XUI.Ask(UnitOnTaxi, "player") then return nil end
	if M.db.mplusOnly and not InMythicPlus() then return nil end
	local ok, active, hasDevo, hasCrus = ReadBar()
	if not ok then return nil end
	if active == CRUSADER then return hasDevo and DEVOTION or nil end
	local mounted = XUI.Probe(IsMounted)
	if not mounted then return nil end
	return hasCrus and CRUSADER or nil
end

function M:Update()
	if not display then return end
	local id = Wanted()
	if id then
		display:SetIcon(XUI.GetSpellIcon(id, ICONS[id]))
		display.label:SetText(TEXTS[id])
	end
	display:SetShown(id ~= nil)
end

function M:OnEnable()
	Display()
	for _, e in ipairs({
		"PLAYER_ENTERING_WORLD", "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS", "PLAYER_MOUNT_DISPLAY_CHANGED",
		"PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
		"ZONE_CHANGED_NEW_AREA", "PLAYER_DIFFICULTY_CHANGED", "CHALLENGE_MODE_START", "CHALLENGE_MODE_RESET",
	}) do
		self:RegisterEvent(e, function(self) self:RefreshSoon() end)
	end
end

function M:OnRefresh()
	if not (display or self:IsPreview()) then return end
	local d, db = Display(), self.db
	XUI.Movers:Apply(d)
	d:ApplyLayout(db.icon, db.border)
	Style:ApplyFont(d.label, db.text)
	d.label:SetTextColor(XUI.UnpackColor(Style:Resolve("font", db.text).color))
	local a = TEXT_ANCHORS[db.textSide] or TEXT_ANCHORS.BOTTOM
	d.label:ClearAllPoints()
	d.label:SetPoint(a[1], d, a[2], a[3] + db.textX, a[4] + db.textY)
	self:Update()
end

function M:DebugInfo()
	local ok, active, hasDevo, hasCrus = ReadBar()
	return {
		("stance bar: %s, active aura %s (465 Devotion, 32223 Crusader), Devotion on bar %s, Crusader on bar %s"):format(
			ok and "readable" or "UNREADABLE", tostring(active), tostring(hasDevo), tostring(hasCrus)),
		("mounted %s, in Mythic+ %s, wanted %s"):format(tostring(XUI.Probe(IsMounted)), tostring(InMythicPlus()), tostring(Wanted())),
	}
end
