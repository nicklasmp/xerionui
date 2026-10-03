--------------------------------------------------------------------------------
-- Defensive indicator (every class)
-- One ring (or bar) in the middle of your screen while a defensive of yours is
-- up, coloured by how big it is (Massive, Major, Minor, External) with its name
-- and the seconds left. The lists of defensives per class are in
-- DefensiveData.lua; each can be switched off.
-- Ported from ItruliaQoL (MIT, (c) Itrulia).
--
-- Where the live display comes from: addon code cannot read a player's auras in
-- combat on 12.1, so presence comes from the engine. An aura container shows
-- and hides a button per matching aura entirely engine side, and the engine
-- drives a cooldown of ours, so the swipe runs on times we are never allowed to
-- read. Nothing may ask which buttons the engine is showing either, so the
-- display narrows by construction instead:
--  * One container per tier draws the ring or bar. The tiers stack on the same
--    spot, each on a higher frame level than the last over an opaque base, so
--    when several are up only the biggest one is visible.
--  * One more container holds every tracked ID in a one-frame group, so the
--    engine itself picks a single aura (the newest). That button carries the
--    name (SetSpellName) and the seconds (SetDurationText), so two defensives
--    can never put two readouts on screen.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates
local Style = XUI.Style

local Data = XUI.DefensiveData
local RING = [[Interface\AddOns\XerionUI\Media\ring.tga]]
local TIERS = { "MINOR", "MAJOR", "EXTERNAL", "MASSIVE" } -- draw order is priority
local TIER_STEP = 10
local NO_MATCH = { [0] = true } -- an empty include map matches every buff

local CATEGORY, DEFAULT_ON = {}, {}
for _, entries in pairs(Data.defensive) do
	for _, e in ipairs(entries) do
		CATEGORY[e.auraId] = e.category or "MAJOR"
		DEFAULT_ON[e.auraId] = not e.defaultOff
	end
end
for _, e in ipairs(Data.external) do
	CATEGORY[e.auraId] = "EXTERNAL"
	DEFAULT_ON[e.auraId] = not e.defaultOff
end

local M = XUI:NewModule("DefensiveIndicator", {
	name = "Defensive Indicator",
	desc = "A ring or bar with the seconds left while one of your defensives is up.",
	category = "class",
	icon = [[Interface\Icons\Spell_Holy_DivineProtection]],
	order = 130,
	untested = true,
	defaults = {
		display = "CIRCLE",
		size = 46,
		bar = T.Bar(160, 14),
		colors = {
			MASSIVE = { 0.925, 0.353, 0.353, 1 },
			MAJOR = { 0.451, 0.741, 0.522, 1 },
			MINOR = { 0.400, 0.616, 0.855, 1 },
			EXTERNAL = { 0.949, 0.769, 0.318, 1 },
		},
		backgroundColor = { 0, 0, 0, 0.6 },
		showName = true,
		showDuration = true,
		precision = 0,
		textColor = { 1, 1, 1, 1 },
		textX = 0,
		textY = 0,
		font = T.Font(12),
		border = T.Border(),
		trackedAuras = {},
		position = T.Position(0, -140),
	},
})
M.DISPLAYS = { { value = "CIRCLE", text = "Ring" }, { value = "BAR", text = "Bar" }, { value = "NONE", text = "Text only" } }
M.CATEGORIES = { "MASSIVE", "MAJOR", "MINOR", "EXTERNAL" }
M.CATEGORY, M.DEFAULT_ON = CATEGORY, DEFAULT_ON

function M:CanLoad()
	if not XUI.HasAuraContainers() then return false, "Needs the 12.1 aura containers." end
	return true
end

local IsSecret = XUI.IsSecret
local frame, containers, winnerContainer, rings, winners
local known, tracked
local carried, stylePending = nil, false
local previewTicker

--------------------------------------------------------------------------------
-- What is tracked
--------------------------------------------------------------------------------
function M:IsTracked(auraId)
	local v = self.db.trackedAuras[auraId]
	if v == nil then return DEFAULT_ON[auraId] or false end
	return v == true
end

function M:SetTracked(auraId, on)
	self.db.trackedAuras[auraId] = on and true or false
	tracked = nil
	self:UpdateFilters()
end

local function CacheKnown()
	local changed = known == nil
	local previous = known or {}
	local out = {}
	for _, e in ipairs(Data.defensive[XUI.playerClass] or {}) do
		if XUI.IsSpellKnown(e.spellId or e.auraId) then
			out[e.auraId] = true
			if not previous[e.auraId] then changed = true end
		elseif previous[e.auraId] then
			changed = true
		end
	end
	known = out
	return changed
end

local function IsKnown(auraId)
	if CATEGORY[auraId] == "EXTERNAL" then return true end
	if not known then CacheKnown() end
	return known[auraId] or false
end

-- tracked, known auras of one category (nil = none), or all (a list) when category is nil
local function Entries()
	local out = {}
	for _, e in ipairs(Data.defensive[XUI.playerClass] or {}) do out[#out + 1] = e end
	for _, e in ipairs(Data.external) do out[#out + 1] = e end
	return out
end

local function TrackedIds(category)
	local ids
	for _, e in ipairs(Entries()) do
		if (not category or CATEGORY[e.auraId] == category) and M:IsTracked(e.auraId) and IsKnown(e.auraId) then
			ids = ids or {}
			ids[e.auraId] = true
		end
	end
	return ids
end

local function IncludeFilter(ids) return { includeSpellIDs = ids or NO_MATCH } end

local function SampleSpell()
	for _, e in ipairs(Entries()) do
		if M:IsTracked(e.auraId) and IsKnown(e.auraId) then return e.auraId end
	end
	local list = Data.defensive[XUI.playerClass]
	return list and list[1] and list[1].auraId or 871
end

--------------------------------------------------------------------------------
-- The ring: swipe ring or bar, built the same for live buttons and the sample
--------------------------------------------------------------------------------
local function CreateRing(parent)
	local r = CreateFrame("Frame", nil, parent)
	r.base = r:CreateTexture(nil, "BACKGROUND", nil, -8)
	r.base:SetAllPoints()
	r.track = r:CreateTexture(nil, "BACKGROUND")
	r.track:SetAllPoints()
	r.swipe = CreateFrame("Cooldown", nil, r, "CooldownFrameTemplate")
	r.swipe:SetAllPoints()
	r.swipe:SetDrawBling(false)
	r.swipe:SetDrawEdge(false)
	r.swipe:SetReverse(false)
	r.swipe:SetHideCountdownNumbers(true)
	r.bar = CreateFrame("StatusBar", nil, r)
	r.bar:SetAllPoints()
	r.bar:SetMinMaxValues(0, 1)
	r.barBase = r.bar:CreateTexture(nil, "BACKGROUND", nil, -8)
	r.barBase:SetAllPoints()
	r.barBase:SetColorTexture(0, 0, 0, 1)
	r.barBackground = r.bar:CreateTexture(nil, "BACKGROUND")
	r.barBackground:SetAllPoints()
	r.border = Style:Border(r.bar)
	return r
end

local function DisplaySize()
	local db = M.db
	if db.display == "BAR" then
		local b = Style:Resolve("bar", db.bar)
		return b.width or 160, b.height or 14
	end
	return db.size, db.size
end

local function StyleRing(r)
	local db = M.db
	local circle = db.display == "CIRCLE"
	r:SetSize(DisplaySize())
	r.base:SetTexture(RING)
	r.base:SetVertexColor(0, 0, 0, 1)
	r.base:SetShown(circle)
	r.track:SetTexture(RING)
	r.track:SetVertexColor(XUI.UnpackColor(db.backgroundColor))
	r.track:SetShown(circle)
	r.swipe:SetSwipeTexture(RING)
	r.swipe:SetDrawSwipe(circle)
	r.swipe:SetShown(circle)
	r.bar:SetShown(db.display == "BAR")
	local path = XUI.Media:Fetch("statusbar", Style:Resolve("bar", db.bar).texture)
	r.bar:SetStatusBarTexture(path)
	r.barBackground:SetTexture(path)
	r.bar:ClearAllPoints()
	r.bar:SetAllPoints()
	r.border:Apply(db.border)
end

local function ColorRing(r, category)
	local c = M.db.colors[category] or M.db.colors.MAJOR
	local red, green, blue, alpha = XUI.UnpackColor(c)
	r.swipe:SetSwipeColor(red, green, blue, alpha)
	r.bar:SetStatusBarColor(red, green, blue, alpha)
	r.barBackground:SetVertexColor(red * 0.25, green * 0.25, blue * 0.25, 0.9)
end

--------------------------------------------------------------------------------
-- Text offsets and the engine-driven readouts
--------------------------------------------------------------------------------
local function TextOffsets()
	local db = M.db
	if db.showName and db.showDuration then
		local gap = ((Style:Resolve("font", db.font).size or 12) + 2) / 2
		return db.textY + gap, db.textY - gap
	end
	return db.textY, db.textY
end

local function StyleText(fs, offsetY)
	local db = M.db
	Style:ApplyFont(fs, db.font)
	fs:ClearAllPoints()
	fs:SetPoint("CENTER", frame, "CENTER", db.textX, offsetY)
	fs:SetJustifyH("CENTER")
	fs:SetTextColor(XUI.UnpackColor(db.textColor))
end

local function StyleWinner(w)
	local nameY, durationY = TextOffsets()
	StyleText(w.name, nameY)
	StyleText(w.duration, durationY)
	-- alpha as well as the shown flag: the engine writes into these strings
	w.name:SetShown(M.db.showName)
	w.name:SetAlpha(M.db.showName and 1 or 0)
	w.duration:SetShown(M.db.showDuration)
	w.duration:SetAlpha(M.db.showDuration and 1 or 0)
end

local function BindDuration(button, text)
	local opts = M.db.precision > 0 and XUI.TenthsTextOptions() or XUI.DurationTextOptions()
	pcall(button.SetDurationText, button, text, opts)
end

-- neither clicks nor tooltips: the display is a readout
local function Silence(button)
	pcall(button.SetMouseClickEnabled, button, false)
	pcall(button.SetMouseMotionEnabled, button, false)
end

local function InitRingButton(button, category)
	Silence(button)
	local r = CreateRing(button)
	r.category = category
	-- anchored to our own frame so the mover owns where it sits
	pcall(button.SetScale, button, 1)
	r:SetPoint("CENTER", frame, "CENTER", 0, 0)
	pcall(button.SetSize, button, DisplaySize())
	r.button = button
	-- the button expects an icon to be registered although the ring draws none
	r.icon = r:CreateTexture(nil, "BACKGROUND")
	r.icon:Hide()
	pcall(button.SetIcon, button, r.icon)
	pcall(button.SetDurationCooldown, button, r.swipe)
	local opts = {}
	if Enum.StatusBarInterpolation then
		opts.interpolation = Enum.StatusBarInterpolation.ExponentialEaseOut or Enum.StatusBarInterpolation.Immediate
	end
	if Enum.StatusBarTimerDirection then opts.direction = Enum.StatusBarTimerDirection.RemainingTime end
	if not pcall(button.SetDurationBar, button, r.bar, opts) then pcall(button.SetDurationBar, button, r.bar) end
	rings[#rings + 1] = r
	StyleRing(r)
	ColorRing(r, category)
end

local function InitWinnerButton(button)
	Silence(button)
	pcall(button.SetScale, button, 1)
	local carrier = CreateFrame("Frame", nil, button)
	carrier:SetPoint("CENTER", frame, "CENTER", 0, 0)
	carrier:SetSize(1, 1)
	carrier:EnableMouse(false)
	local w = { button = button, name = carrier:CreateFontString(nil, "OVERLAY"), duration = carrier:CreateFontString(nil, "OVERLAY") }
	w.icon = carrier:CreateTexture(nil, "BACKGROUND")
	w.icon:Hide()
	pcall(button.SetIcon, button, w.icon)
	winners[#winners + 1] = w
	-- fonts before the bindings: the engine writes into these strings, and SetText
	-- on one with no font throws, which inside the frame batch takes every button down
	StyleWinner(w)
	pcall(button.SetSpellName, button, w.name)
	BindDuration(button, w.duration)
end

local function Shell(level)
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, frame, "CustomAuraContainerTemplate")
	if not ok or not c then return nil end
	c:SetScale(1)
	c:SetPoint("CENTER", frame, "CENTER")
	c:SetSize(1, 1)
	c:SetFrameLevel(level)
	return c
end

local function EnsureContainers()
	if containers then return end
	if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then C_AddOns.LoadAddOn("Blizzard_AuraContainer") end
	containers, rings, winners = {}, rings or {}, winners or {}
	for index, category in ipairs(TIERS) do
		local c = Shell(frame:GetFrameLevel() + index * TIER_STEP)
		if not c then containers = nil return end
		pcall(c.AddAuraGroup, c, "defensive", "HELPFUL", {
			maxFrameCount = 1,
			candidateFilters = IncludeFilter(TrackedIds(category)),
			initializeFrame = function(button) InitRingButton(button, category) end,
		})
		pcall(c.SetUnit, c, "player")
		pcall(c.UpdateAllAuras, c)
		containers[category] = c
	end
	local w = Shell(frame:GetFrameLevel() + (#TIERS + 1) * TIER_STEP)
	if w then
		pcall(w.AddAuraGroup, w, "defensive", "HELPFUL", {
			maxFrameCount = 1,
			sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.AuraInstanceIDOnly,
			sortDirection = AuraContainerSortDirection and AuraContainerSortDirection.Reverse,
			candidateFilters = IncludeFilter(TrackedIds()),
			initializeFrame = InitWinnerButton,
		})
		pcall(w.SetUnit, w, "player")
		pcall(w.UpdateAllAuras, w)
		winnerContainer = w
	end
end

function M:UpdateFilters()
	if not containers then return end
	for category, c in pairs(containers) do
		local ids = TrackedIds(category)
		pcall(c.SetAuraGroupCandidateFilters, c, "defensive", IncludeFilter(ids))
		pcall(c.SetAuraGroupMaxFrameCount, c, "defensive", ids and 1 or 0)
		pcall(c.UpdateAllAuras, c)
	end
	if winnerContainer then
		local ids = TrackedIds()
		pcall(winnerContainer.SetAuraGroupCandidateFilters, winnerContainer, "defensive", IncludeFilter(ids))
		pcall(winnerContainer.SetAuraGroupMaxFrameCount, winnerContainer, "defensive", ids and 1 or 0)
		pcall(winnerContainer.UpdateAllAuras, winnerContainer)
	end
end

local function SetContainersShown(shown)
	local alpha = shown and 1 or 0
	for _, c in pairs(containers or {}) do
		c:SetAlpha(alpha)
		c:SetShown(shown)
	end
	if winnerContainer then
		winnerContainer:SetAlpha(alpha)
		winnerContainer:SetShown(shown)
	end
end

local function Restyle()
	local landed = true
	for _, r in ipairs(rings or {}) do
		if r.button then landed = pcall(r.button.SetSize, r.button, DisplaySize()) and landed end
		landed = pcall(StyleRing, r) and landed
		landed = pcall(ColorRing, r, r.category) and landed
	end
	for _, w in ipairs(winners or {}) do
		landed = pcall(StyleWinner, w) and landed
		BindDuration(w.button, w.duration)
	end
	stylePending = not landed
end

local function UpdateCarried()
	local now = (XUI.Ask(UnitOnTaxi, "player") or XUI.Ask(UnitInVehicle, "player")) and true or false
	if now == carried then return end
	carried = now
	SetContainersShown(M.running and not now and not M:IsPreview())
	if now then return end
	for _, c in pairs(containers or {}) do pcall(c.UpdateAllAuras, c) end
	if winnerContainer then pcall(winnerContainer.UpdateAllAuras, winnerContainer) end
end

--------------------------------------------------------------------------------
-- The sample the settings are tuned on
--------------------------------------------------------------------------------
local sample
local function Sample()
	if sample then return sample end
	sample = { ring = CreateRing(frame) }
	sample.ring:SetPoint("CENTER", frame, "CENTER", 0, 0)
	sample.text = frame:CreateFontString(nil, "OVERLAY")
	Style:ApplyFont(sample.text, nil, 12)
	sample.ring:Hide()
	return sample
end

local function PaintSample()
	local s = Sample()
	local db = M.db
	local category = CATEGORY[SampleSpell()] or "MAJOR"
	StyleRing(s.ring)
	ColorRing(s.ring, category)
	s.ring.swipe:SetCooldown(GetTime(), 8)
	s.ring.bar:SetMinMaxValues(0, 1)
	s.ring.bar:SetValue(0.7)
	local nameY, durationY = TextOffsets()
	Style:ApplyFont(s.text, db.font)
	s.text:ClearAllPoints()
	s.text:SetPoint("CENTER", frame, "CENTER", db.textX, (nameY + durationY) / 2)
	s.text:SetJustifyH("CENTER")
	s.text:SetTextColor(XUI.UnpackColor(db.textColor))
	local text = ""
	if db.showName then text = XUI.GetSpellName(SampleSpell()) end
	if db.showDuration then text = text .. (text ~= "" and "\n" or "") .. (db.precision > 0 and "5.6" or "6") end
	s.text:SetText(text)
	s.text:SetShown(db.showName or db.showDuration)
	s.ring:SetShown(db.display ~= "NONE")
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------
local function Frame()
	if frame then return frame end
	frame = CreateFrame("Frame", "XUI_DefensiveIndicator", UIParent)
	frame:SetSize(46, 46)
	frame:Hide()
	XUI.Movers:Register(frame, M, "position")
	return frame
end

function M:OnEnable()
	Frame()
	known, tracked, carried = nil, nil, nil
	rings, winners = rings or {}, winners or {}
	EnsureContainers()
	local function recache(self)
		if CacheKnown() then
			self:UpdateFilters()
		end
	end
	for _, e in ipairs({ "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED", "PLAYER_ENTERING_WORLD" }) do
		self:RegisterEvent(e, recache)
	end
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() if stylePending then Restyle() end end)
	for _, e in ipairs({ "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED" }) do self:RegisterEvent(e, UpdateCarried) end
	for _, e in ipairs({ "UNIT_ENTERING_VEHICLE", "UNIT_ENTERED_VEHICLE", "UNIT_EXITING_VEHICLE", "UNIT_EXITED_VEHICLE" }) do
		self:RegisterUnitEvent(e, "player", UpdateCarried)
	end
	self:UpdateFilters()
end

function M:OnDisable()
	SetContainersShown(false)
	carried = nil
	if previewTicker then previewTicker:Cancel() previewTicker = nil end
	if frame and not self:IsPreview() then frame:Hide() end
end

function M:OnRefresh()
	if not (frame or self:IsPreview()) then return end
	local f = Frame()
	XUI.Movers:Apply(f)
	f:SetSize(DisplaySize())
	local preview = self:IsPreview()
	if self.running then
		EnsureContainers()
		Restyle()
		UpdateCarried()
	end
	SetContainersShown(self.running and not preview and not carried)
	if preview then
		PaintSample()
		if not previewTicker then
			-- the sample loops its 8 seconds
			previewTicker = C_Timer.NewTicker(8, function()
				if M:IsPreview() then PaintSample() elseif previewTicker then previewTicker:Cancel() previewTicker = nil end
			end)
		end
	elseif sample then
		sample.ring:Hide()
		sample.text:Hide()
	end
	f:SetShown(preview or self.running)
end

function M:DebugInfo()
	local n = 0
	for _ in pairs(TrackedIds() or {}) do n = n + 1 end
	return {
		("tracked and known auras: %d, containers: %s, winner container: %s"):format(n, containers and "built" or "no", winnerContainer and "yes" or "no"),
		("rings %d, readouts %d, restyle waiting: %s"):format(rings and #rings or 0, winners and #winners or 0, tostring(stylePending)),
	}
end

-- for the options: the entries of the player's class and the externals
function M:Entries() return Entries() end
