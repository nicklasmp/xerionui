--------------------------------------------------------------------------------
-- Shroud / Mass Invisibility bars
-- A rogue's Shroud of Concealment hides the party for 15 s and a mage's Mass
-- Invisibility for 12 s, and the party cannot see how long is left: the copy
-- of Shroud you get carries no timer (it lives on the rogue's own aura), and
-- in a key no addon may read either aura.
--
-- Each bar is an AuraContainer of the engine's filtered to its spell, whose
-- one button owns the bar: SetDurationBar / SetDurationText / SetIcon bind our
-- pieces to the aura and the engine fills and counts. The Shroud bar watches
-- the rogue in your group (or you), the Mass Invisibility bar watches you
-- while you are in a group. A "max duration" filter keeps the timerless
-- party copy of Shroud out of the single slot.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates
local Style = XUI.Style

local SHROUD, MASS_INVIS = 114018, 414664
local MAX_DURATION = 60

local M = XUI:NewModule("Shroud", {
	name = "Shroud / Mass Invis",
	desc = "Time left on Shroud of Concealment and Mass Invisibility.",
	category = "group",
	icon = [[Interface\Icons\Ability_Rogue_EnvelopingShadows]],
	iconSpell = SHROUD, -- Shroud of Concealment's own icon in the options
	order = 50,
	defaults = {
		bar = T.Bar(220, 22),
		border = T.Border(),
		gap = 2,
		iconGap = 2,
		showIcon = true,
		nameText = T.Font(14, { enabled = true }),
		timerText = T.Font(14, { enabled = true }),
		showShroud = true,
		color = { 0.58, 0.36, 0.86, 1 },
		selfBar = true,
		showMassInvis = true,
		miColor = { 0.25, 0.78, 0.92, 1 },
		position = T.Position(0, 120),
	},
})

function M:CanLoad()
	if not XUI.HasAuraContainers() then return false, "Needs the 12.1 aura containers." end
	return true
end

local IsSecret = XUI.IsSecret
local PARTY, RAID = {}, {}
for i = 1, 4 do PARTY[i] = "party" .. i end
for i = 1, 40 do RAID[i] = "raid" .. i end

local function ClassOf(unit)
	local ok, _, token = pcall(UnitClass, unit)
	if not ok or IsSecret(token) then return nil end
	return token
end

-- you when you are the rogue, else the first rogue; whoever is on the bar
-- keeps it while they qualify
local function FindRogue(db, current)
	if db.selfBar and ClassOf("player") == "ROGUE" then return "player" end
	local first, kept
	for _, u in ipairs(IsInRaid() and RAID or PARTY) do
		if XUI.Ask(UnitExists, u) and XUI.Ask(UnitIsUnit, u, "player") == false and ClassOf(u) == "ROGUE" then
			first = first or u
			if u == current then kept = u end
		end
	end
	return kept or first
end

local TRACKS = {
	{
		label = "Mass Invis", key = "massinvis", on = "showMassInvis", colorKey = "miColor",
		spell = MASS_INVIS, ids = { MASS_INVIS }, icon = [[Interface\Icons\Ability_Mage_Invisibility]],
		-- a party moment: watched while in a group (unreadable = watch)
		find = function() if XUI.Ask(IsInGroup) ~= false then return "player" end end,
	},
	{
		label = "Shroud", key = "shroud", on = "showShroud", colorKey = "color",
		spell = SHROUD, ids = { SHROUD, 115834 }, icon = [[Interface\Icons\Ability_Rogue_EnvelopingShadows]],
		find = FindRogue,
	},
}
for _, t in ipairs(TRACKS) do t.buttons = {} end

local holder
local stylePending = false

local function Holder()
	if holder then return holder end
	holder = CreateFrame("Frame", "XUI_Shroud", UIParent)
	holder:SetSize(220, 22)
	holder:Hide()
	XUI.Movers:Register(holder, M, "position")
	return holder
end

local function BarSize(db)
	local b = Style:Resolve("bar", db.bar)
	return b.width or 220, b.height or 22
end

-- The pieces of one bar on `parent`: an icon box and a bar box, each with
-- its border, a background and two texts. The same pieces make the preview
-- and the live bar on the engine's button.
local function MakeBar(parent)
	local p = {}
	p.iconBox = CreateFrame("Frame", nil, parent)
	p.icon = p.iconBox:CreateTexture(nil, "ARTWORK")
	p.iconBorder = Style:Border(p.iconBox)
	p.barBox = CreateFrame("Frame", nil, parent)
	p.bar = CreateFrame("StatusBar", nil, p.barBox)
	p.barBorder = Style:Border(p.barBox)
	p.text = CreateFrame("Frame", nil, parent)
	p.text:SetAllPoints(p.barBox)
	p.text:SetFrameLevel(p.bar:GetFrameLevel() + 5)
	p.name = p.text:CreateFontString(nil, "OVERLAY")
	p.name:SetWordWrap(false)
	p.timer = p.text:CreateFontString(nil, "OVERLAY")
	-- fonts first: the engine writes the timer on its own
	Style:ApplyFont(p.name, nil, 12)
	Style:ApplyFont(p.timer, nil, 12)
	return p
end

local function Inset(region, parent, inset)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -inset)
	region:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, inset)
end

local function StyleBar(p, parent, t)
	local db = M.db
	local w, h = BarSize(db)
	local r, g, b = XUI.UnpackColor(db[t.colorKey])
	local left = 0
	p.iconBox:SetShown(db.showIcon)
	if db.showIcon then
		p.iconBox:ClearAllPoints()
		p.iconBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
		p.iconBox:SetSize(h, h)
		Inset(p.icon, p.iconBox, p.iconBorder:Apply(db.border))
		Style:IconTexCoord(p.icon, h, h)
		left = h + db.iconGap
	end
	p.barBox:ClearAllPoints()
	p.barBox:SetPoint("TOPLEFT", parent, "TOPLEFT", left, 0)
	p.barBox:SetSize(math.max(1, w - left), h)
	local inset = p.barBorder:Apply(db.border)
	Inset(p.bar, p.barBox, inset)
	-- the bar's own background (Bar > Background color) sits under the fill
	Style:ApplyBar(p.bar, db.bar)
	p.bar:SetStatusBarColor(r, g, b)
	Style:ApplyFont(p.timer, db.timerText)
	p.timer:ClearAllPoints()
	p.timer:SetPoint("RIGHT", p.bar, "RIGHT", -4, 0)
	p.timer:SetJustifyH("RIGHT")
	p.timer:SetShown(db.timerText.enabled ~= false)
	Style:ApplyFont(p.name, db.nameText)
	p.name:ClearAllPoints()
	p.name:SetPoint("LEFT", p.bar, "LEFT", 4, 0)
	p.name:SetPoint("RIGHT", p.timer, "LEFT", -4, 0)
	p.name:SetJustifyH("LEFT")
	p.name:SetShown(db.nameText.enabled ~= false)
	p.name:SetText(t.label)
end

local function EnsureSlots()
	for _, t in ipairs(TRACKS) do
		if not t.slot then
			t.slot = CreateFrame("Frame", nil, holder)
			t.sample = MakeBar(t.slot)
			t.sample.bar:SetMinMaxValues(0, 1)
			t.sample.bar:SetValue(0.6)
			t.sample.icon:SetTexture(XUI.GetSpellIcon(t.spell, t.icon))
			t.sample.timer:SetText("9")
		end
	end
end

-- top to bottom in list order, only the bars switched on
local function LayoutSlots(db)
	local w, h = BarSize(db)
	local y, n = 0, 0
	for _, t in ipairs(TRACKS) do
		local on = db[t.on]
		t.slot:SetShown(on)
		if on then
			t.slot:ClearAllPoints()
			t.slot:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -y)
			t.slot:SetSize(w, h)
			y = y + h + db.gap
			n = n + 1
		end
	end
	holder:SetSize(w, n > 0 and (y - db.gap) or h)
end

local function SetSampleShown(t, on)
	local s = t.sample
	s.iconBox:SetShown(on and M.db.showIcon)
	s.barBox:SetShown(on)
	s.text:SetShown(on)
end

-- Runs inside the engine's frame batch: no scripts, and armoured.
local function InitButton(t, b)
	pcall(b.SetMouseClickEnabled, b, false)
	pcall(b.SetMouseMotionEnabled, b, false)
	local w, h = BarSize(M.db)
	b:SetSize(w, h)
	local p = MakeBar(b)
	pcall(StyleBar, p, b, t)
	b:SetIcon(p.icon)
	b:SetDurationBar(p.bar, XUI.DurationBarOptions())
	pcall(b.SetDurationText, b, p.timer, XUI.DurationTextOptions())
	t.buttons[#t.buttons + 1] = { frame = b, p = p }
end

local function EnsureContainer(t)
	if t.container or t.failed then return end
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, t.slot, "CustomAuraContainerTemplate")
	if not ok or not c then
		t.failed = true
		return
	end
	c:SetSize(1, 1)
	local include = {}
	for _, id in ipairs(t.ids) do include[id] = true end
	local w, h = BarSize(M.db)
	local okG = pcall(c.AddAuraGroup, c, t.key, "HELPFUL", {
		maxFrameCount = 1,
		candidateFilters = { includeSpellIDs = include, maxDuration = MAX_DURATION },
		initializeFrame = function(b) InitButton(t, b) end,
		layout = { elementWidth = w, elementHeight = h, elementSpacing = 0, lineSpacing = 0 },
	})
	if not okG then
		t.failed = true
		c:Hide()
		return
	end
	pcall(c.SetEnabled, c, false)
	-- anchored only now: once it has a group, its size is the engine's
	c:SetPoint("TOPLEFT", t.slot, "TOPLEFT", 0, 0)
	t.container = c
end

-- in combat the engine may refuse; the change waits for the fight to end
local function RestyleButtons()
	stylePending = false
	local w, h = BarSize(M.db)
	for _, t in ipairs(TRACKS) do
		for _, rec in ipairs(t.buttons) do
			local ok = pcall(function()
				rec.frame:SetSize(w, h)
				StyleBar(rec.p, rec.frame, t)
			end)
			if not ok then stylePending = true end
		end
		local c = t.container
		if c and not pcall(c.SetAuraGroupLayout, c, t.key, { elementWidth = w, elementHeight = h, elementSpacing = 0, lineSpacing = 0 }) then
			stylePending = true
		end
	end
end

local rereadNext = false
function M:Scan()
	local reread = rereadNext
	rereadNext = false
	local db = self.db
	local live = self.running and not self:IsPreview()
	local again = {}
	for _, t in ipairs(TRACKS) do
		local u = live and db[t.on] and t.find(db, t.unit) or nil
		local changed = u ~= t.unit
		t.unit = u
		local c = t.container
		if c then
			if u then
				if t.containerUnit ~= u then
					t.containerUnit = u
					pcall(c.SetUnit, c, u)
				end
				pcall(c.SetEnabled, c, true)
				if changed or reread then again[#again + 1] = c end
			else
				pcall(c.SetEnabled, c, false)
			end
		end
	end
	-- shown first: a container only works while visible
	if holder then holder:SetShown(self:IsPreview() or live) end
	for _, c in ipairs(again) do pcall(c.UpdateAllAuras, c) end
end

function M:OnEnable()
	Holder()
	EnsureSlots()
	local QueueScan = XUI.Coalesce(function() if M.running then M:Scan() end end)
	self:RegisterEvent("GROUP_ROSTER_UPDATE", QueueScan)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(self)
		rereadNext = true
		self:After(0.5, function() self:Scan() end)
	end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() if stylePending then RestyleButtons() end end)
	self:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", function(self)
		if stylePending then self:After(0, RestyleButtons) end
	end)
end

function M:OnDisable()
	for _, t in ipairs(TRACKS) do
		t.unit = nil
		if t.container then pcall(t.container.SetEnabled, t.container, false) end
	end
end

function M:OnRefresh()
	if not (holder or self:IsPreview()) then return end
	local h, db = Holder(), self.db
	EnsureSlots()
	XUI.Movers:Apply(h)
	LayoutSlots(db)
	local preview = self:IsPreview()
	for _, t in ipairs(TRACKS) do
		StyleBar(t.sample, t.slot, t)
		SetSampleShown(t, preview and db[t.on])
		if self.running and db[t.on] then EnsureContainer(t) end
		if t.container then t.container:SetShown(not preview) end
	end
	if self.running then RestyleButtons() end
	self:Scan()
end
