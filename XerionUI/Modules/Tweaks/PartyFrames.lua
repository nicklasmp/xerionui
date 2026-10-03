--------------------------------------------------------------------------------
-- EllesmereUI party frame tweaks
--
-- Health + shield %: (health + absorbs) / max health as a number on each
-- party frame. Every input is secret in keys, so nothing is divided in Lua:
-- two invisible status bars are fed health and absorb against max health, the
-- width of their combined fill IS the percentage (100 units wide), and the
-- text prints that width. Read one frame later, once the fills have settled.
--
-- Colour by value: Lua cannot compare the total either, so the colour is
-- picked by clipping. A second, wider sensor pair puts the end of its fill K
-- units right of the number's centre per percent; each step T has an edge
-- K*T left of that end, and four clip frames between the edges each hold a
-- copy of the number in its band's colour - only one copy is ever visible.
--
-- Debuff stack placement: wraps EllesmereUI's party debuff aura styles so the
-- stack count can sit elsewhere (Top is centred just above the icon).
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates
local Style = XUI.Style

local M = XUI:NewModule("EUIPartyFrames", {
	name = "Party Frames",
	desc = "Health + shield percent and debuff stack placement on EllesmereUI party frames.",
	category = "tweaks",
	icon = [[Interface\Icons\Spell_Holy_PrayerOfHealing]],
	order = 50,
	requires = "EllesmereUIRaidFrames",
	defaults = {
		health = {
			enabled = false,
			anchor = "RIGHT",
			x = -4,
			y = 0,
			matchName = true,
			byValue = true,
			t1 = 35, t2 = 70, t3 = 100,
			c1 = { 1, 0.25, 0.25, 1 },
			c2 = { 1, 0.82, 0.2, 1 },
			c3 = { 1, 1, 1, 1 },
			c4 = { 0.35, 1, 0.35, 1 },
			color = { 1, 1, 1, 1 },
		},
		healthText = T.Font(12),
		stack = { placement = "BOTTOMRIGHT", x = 0, y = 0 },
	},
})

M.ANCHORS = {
	{ value = "LEFT", text = "Left" }, { value = "CENTER", text = "Center" }, { value = "RIGHT", text = "Right" },
	{ value = "TOP", text = "Top" }, { value = "BOTTOM", text = "Bottom" },
}
M.STACK_PLACES = {
	{ value = "BOTTOMRIGHT", text = "Bottom right (EllesmereUI)" }, { value = "TOPLEFT", text = "Top left" },
	{ value = "TOP", text = "Top" }, { value = "TOPRIGHT", text = "Top right" },
}

local IsSecret = XUI.IsSecret
local WHITE = [[Interface\Buttons\WHITE8X8]]
local SPAN, K, BANDS = 100, 40, 4
local FAR = K * 300
local JUSTIFY = { LEFT = "LEFT", RIGHT = "RIGHT", CENTER = "CENTER", TOP = "CENTER", BOTTOM = "CENTER" }

local function RF()
	return XUI.EUI and XUI.EUI.Module("EllesmereUIRaidFrames")
end

--------------------------------------------------------------------------------
-- Health + shield %
--------------------------------------------------------------------------------
local widgets = setmetatable({}, { __mode = "k" })
local gen = 0

local function Sensor(parent, width, height)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(WHITE)
	bar:SetStatusBarColor(1, 1, 1, 0) -- geometry only
	bar:SetSize(width, height)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	return bar
end

local function Build(btn)
	local w = widgets[btn]
	if w then return w end
	local rf = RF()
	local ok, d = pcall(rf.GetFFD, btn)
	if not (ok and d and d.health) then return nil end
	-- EllesmereUI's text carrier, so the number shares the name's band
	local carrier = (d.nameText and d.nameText:GetParent()) or btn
	w = { d = d, clip = {}, text = {} }
	w.host = CreateFrame("Frame", nil, carrier)
	w.host:SetAllPoints(d.health)
	w.hp = Sensor(w.host, SPAN, 1)
	w.hp:SetPoint("TOPLEFT", w.host, "TOPLEFT", 0, 0)
	w.abs = Sensor(w.host, SPAN, 1)
	w.abs:SetPoint("TOPLEFT", w.hp:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
	w.span = CreateFrame("Frame", nil, w.host)
	w.span:SetPoint("TOPLEFT", w.hp, "TOPLEFT", 0, 0)
	w.span:SetPoint("BOTTOMRIGHT", w.abs:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
	w.ref = w.host:CreateFontString(nil, "OVERLAY")
	w.ref:SetAlpha(0)
	w.chp = Sensor(w.host, K * SPAN, 200)
	w.chp:SetPoint("LEFT", w.ref, "CENTER", 0, 0)
	w.cabs = Sensor(w.host, K * SPAN, 200)
	w.cabs:SetPoint("TOPLEFT", w.chp:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
	for i = 1, BANDS do
		w.clip[i] = CreateFrame("Frame", nil, w.host)
		w.text[i] = w.clip[i]:CreateFontString(nil, "OVERLAY")
	end
	widgets[btn] = w
	return w
end

-- half a percent early, so the colour changes where the rounded number does
local function Edge(t) return -K * (t - 0.5) end

local function LayoutBands(w, h)
	local t = { h.t1, h.t2, h.t3 }
	table.sort(t)
	local fill = w.cabs:GetStatusBarTexture()
	local c = w.clip
	for i = 1, BANDS do
		c[i]:ClearAllPoints()
		c[i]:SetClipsChildren(true)
		c[i]:Show()
		w.text[i]:SetTextColor(XUI.UnpackColor(h["c" .. i]))
	end
	c[1]:SetPoint("TOPLEFT", fill, "TOPRIGHT", Edge(t[1]), 0)
	c[1]:SetPoint("BOTTOMRIGHT", w.chp, "BOTTOMLEFT", FAR, 0)
	for i = 2, BANDS - 1 do
		c[i]:SetPoint("TOPLEFT", fill, "TOPRIGHT", Edge(t[i]), 0)
		c[i]:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", Edge(t[i - 1]), 0)
	end
	c[BANDS]:SetPoint("TOPLEFT", w.chp, "TOPLEFT", -FAR, 0)
	c[BANDS]:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", Edge(t[BANDS - 1]), 0)
end

local function Layout(w)
	local db = M.db
	local h = db.health
	local all = { w.ref, w.text[1], w.text[2], w.text[3], w.text[4] }
	local nameFS = w.d.nameText
	local path, flags, sx, sy, sr, sg, sb, sa
	if h.matchName and nameFS then
		local ok, p, _, f = pcall(nameFS.GetFont, nameFS)
		if ok and type(p) == "string" then path, flags = p, f end
		local okS, x, y = pcall(nameFS.GetShadowOffset, nameFS)
		if okS and type(x) == "number" then sx, sy = x, y end
		local okC, r, g, b, a = pcall(nameFS.GetShadowColor, nameFS)
		if okC and type(r) == "number" then sr, sg, sb, sa = r, g or 0, b or 0, a or 1 end
	end
	local size = Style:Resolve("font", db.healthText).size or 12
	local a = JUSTIFY[h.anchor] and h.anchor or "RIGHT"
	for _, fs in ipairs(all) do
		if path then
			fs:SetFont(path, size, flags or "")
			if sx then
				fs:SetShadowOffset(sx, sy)
				fs:SetShadowColor(sr, sg, sb, sa)
			end
		else
			Style:ApplyFont(fs, db.healthText)
		end
		fs:ClearAllPoints()
		fs:SetPoint(a, w.host, a, h.x, h.y)
		fs:SetJustifyH(JUSTIFY[a])
	end
	w.byValue = h.byValue and true or false
	if w.byValue then
		LayoutBands(w, h)
	else
		local clip = w.clip[1]
		clip:ClearAllPoints()
		clip:SetAllPoints(w.host)
		clip:SetClipsChildren(false)
		clip:Show()
		for i = 2, BANDS do w.clip[i]:Hide() end
		w.text[1]:SetTextColor(XUI.UnpackColor(h.color))
		w.ref:SetText("")
	end
end

-- unreadable counts as alive and online
local function Gone(unit)
	local dead = UnitIsDeadOrGhost(unit)
	if IsSecret(dead) then dead = false end
	local online = UnitIsConnected(unit)
	if IsSecret(online) then online = true end
	return dead or not online
end

local function Feed(w, unit)
	local maxHP, hp, abs = UnitHealthMax(unit), UnitHealth(unit), UnitGetTotalAbsorbs(unit)
	w.hp:SetMinMaxValues(0, maxHP)
	w.hp:SetValue(hp)
	w.abs:SetMinMaxValues(0, maxHP)
	w.abs:SetValue(abs)
	if w.byValue then
		w.chp:SetMinMaxValues(0, maxHP)
		w.chp:SetValue(hp)
		w.cabs:SetMinMaxValues(0, maxHP)
		w.cabs:SetValue(abs)
	end
end

local function Blank(w)
	w.live = false
	w.ref:SetText("")
	for i = 1, BANDS do w.text[i]:SetText("") end
end

local function Read(w)
	if not w.live then return end
	local ok, width = pcall(w.span.GetWidth, w.span)
	if not ok then return end
	local n = 1
	if w.byValue then
		n = BANDS
		pcall(w.ref.SetFormattedText, w.ref, "%.0f", width)
	end
	for i = 1, n do pcall(w.text[i].SetFormattedText, w.text[i], "%.0f", width) end
end

-- the fills settle on the next layout pass: read once, one frame later
local dirty = {}
local QueueFlush = XUI.Coalesce(function()
	for w in pairs(dirty) do
		dirty[w] = nil
		Read(w)
	end
end)

local function Paint(btn)
	local w = Build(btn)
	if not w then return end
	if w.gen ~= gen then
		w.gen = gen
		Layout(w)
	end
	w.host:Show()
	local unit = btn:GetAttribute("unit")
	if not (unit and UnitExists(unit)) or Gone(unit) or not pcall(Feed, w, unit) then
		Blank(w)
		return
	end
	w.live = true
	dirty[w] = true
	QueueFlush()
end

local function PaintAll()
	local rf = RF()
	local list = rf and rf._partyAllButtons
	if not (list and M.running and M.db.health.enabled) then return end
	for _, btn in ipairs(list) do
		if btn:IsVisible() then Paint(btn) end
	end
end

local function HideAll()
	for _, w in pairs(widgets) do
		w.live = false
		w.host:Hide()
	end
end

--------------------------------------------------------------------------------
-- Debuff stack placement
--------------------------------------------------------------------------------
local function StackPoint()
	local p = M.db.stack.placement
	if p ~= "TOPLEFT" and p ~= "TOP" and p ~= "TOPRIGHT" then p = "BOTTOMRIGHT" end
	return p
end

local function InstallStackStyle(key)
	local ak = _G.EllesmereUI and _G.EllesmereUI.AuraKit
	local style = ak and ak.styles and ak.styles[key]
	if not (style and type(style.applyExtra) == "function") or style.__xuiStackHook then return end
	local applyExtra = style.applyExtra
	style.applyExtra = function(button, data, current)
		applyExtra(button, data, current)
		if not (M.running and data and data.stack) then return end
		local point = StackPoint()
		local s = M.db.stack
		local ap, rp = point, point
		local x = (current.stackOffX or 0) + s.x
		local y = (current.stackOffY or 0) + s.y
		if point == "TOP" then
			-- our own placement: just above the icon, EllesmereUI's offsets ignored
			ap, rp, x, y = "BOTTOM", "TOP", s.x, s.y
		end
		data.stack:ClearAllPoints()
		data.stack:SetPoint(ap, button, rp, x, y)
	end
	style.__xuiStackHook = true
end

local function InstallStackStyles()
	InstallStackStyle("rf:debuff:party")
	InstallStackStyle("rf:debuffcc:party")
end

local function RestyleStacks()
	InstallStackStyles()
	local ak = _G.EllesmereUI and _G.EllesmereUI.AuraKit
	if ak and type(ak.RestyleSoon) == "function" then
		ak.RestyleSoon("rf:debuff:party")
		ak.RestyleSoon("rf:debuffcc:party")
	end
end

-- a sample debuff over the first party frame, to judge the placement
local sample
local function Sample()
	if sample then return sample end
	sample = XUI.Widgets:CreateIcon(nil, UIParent)
	sample:SetFrameStrata("HIGH")
	sample:SetIcon([[Interface\Icons\Spell_Frost_FrostBolt02]])
	sample:Hide()
	return sample
end

local function UpdateSample()
	local s = Sample()
	if not M:IsPreview() then s:Hide() return end
	local rf = RF()
	local target
	for _, b in ipairs(rf and rf._partyAllButtons or {}) do
		if b.IsVisible and b:IsVisible() then target = b break end
	end
	if not target then s:Hide() return end
	s:ApplyLayout({ width = 24, height = 24 }, nil)
	s:ClearAllPoints()
	s:SetPoint("TOPLEFT", target, "TOPLEFT", 8, -8)
	local point = StackPoint()
	local st = M.db.stack
	s:ApplyCountText({ size = 11, anchor = point == "TOP" and "BOTTOM" or point })
	s.count:ClearAllPoints()
	if point == "TOP" then
		s.count:SetPoint("BOTTOM", s, "TOP", st.x, st.y)
	else
		s.count:SetPoint(point, s, point, st.x, st.y)
	end
	s.count:SetText("5")
	s:Show()
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------
local function ScheduleRefresh()
	M:After(0, PaintAll)
	M:After(0.5, PaintAll)
end

function M:OnEnable()
	local rf = RF()
	InstallStackStyles()
	if rf then
		if type(rf.RFC_SetupButton) == "function" then self:SecureHook(rf, "RFC_SetupButton", InstallStackStyles) end
		if type(rf.RFC_ReloadAll) == "function" then self:SecureHook(rf, "RFC_ReloadAll", InstallStackStyles) end
		-- the secure header moves units between buttons; EllesmereUI repaints
		-- on a zero timer, so look twice
		if type(rf._RebuildPartyUnitMap) == "function" then self:SecureHook(rf, "_RebuildPartyUnitMap", ScheduleRefresh) end
	end
	self:RegisterEvent("GROUP_ROSTER_UPDATE", ScheduleRefresh)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", ScheduleRefresh)
	-- unit-filtered (two units per frame), so nameplate health traffic never
	-- reaches the handler
	if not self.unitFrames then
		self.unitFrames = {}
		for _, pair in ipairs({ { "player", "party1" }, { "party2", "party3" }, { "party4" } }) do
			local f = CreateFrame("Frame")
			f.units = pair
			f:SetScript("OnEvent", function(_, _, unit)
				local r = RF()
				local btn = r and r._partyUnitToButton and r._partyUnitToButton[unit]
				if btn and M.db.health.enabled then Paint(btn) end
			end)
			self.unitFrames[#self.unitFrames + 1] = f
		end
	end
	for _, f in ipairs(self.unitFrames) do
		for _, e in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_CONNECTION" }) do
			f:RegisterUnitEvent(e, f.units[1], f.units[2])
		end
	end
end

function M:OnDisable()
	for _, f in ipairs(self.unitFrames or {}) do f:UnregisterAllEvents() end
	HideAll()
	RestyleStacks()
	if sample then sample:Hide() end
end

-- The sample: the number in each colour step, so the thresholds and colours
-- can be judged without a party in combat.
local numbers
local function PreviewNumbers()
	if numbers then return numbers end
	numbers = CreateFrame("Frame", "XUI_PartyHealthSample", UIParent)
	numbers:SetSize(260, 40)
	numbers:SetFrameStrata("HIGH")
	numbers.fs = {}
	for i = 1, 4 do
		numbers.fs[i] = numbers:CreateFontString(nil, "OVERLAY")
		Style:ApplyFont(numbers.fs[i], nil, 12)
		numbers.fs[i]:SetPoint("LEFT", numbers, "LEFT", (i - 1) * 64, 0)
	end
	numbers:Hide()
	return numbers
end

local function PaintNumbers()
	local n = PreviewNumbers()
	local h = M.db.health
	local steps = { h.t1, h.t2, h.t3 }
	table.sort(steps)
	-- one value inside each colour band
	local values = { math.max(1, steps[1] - 10), math.floor((steps[1] + steps[2]) / 2), math.floor((steps[2] + steps[3]) / 2), steps[3] + 15 }
	n:ClearAllPoints()
	n:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
	for i, fs in ipairs(n.fs) do
		Style:ApplyFont(fs, M.db.healthText)
		fs:SetText(("%d"):format(values[i]))
		fs:SetTextColor(XUI.UnpackColor(h.byValue and h["c" .. i] or h.color))
		fs:SetShown(h.byValue or i == 1)
	end
	n:Show()
end

function M:OnRefresh()
	if self:IsPreview() and self.db.health.enabled then PaintNumbers() elseif numbers then numbers:Hide() end
	gen = gen + 1
	if self.running and self.db.health.enabled then PaintAll() else HideAll() end
	if self.running then RestyleStacks() end
	UpdateSample()
end

function M:DebugInfo()
	local rf = RF()
	local out = {
		("EllesmereUIRaidFrames namespace: %s, GetFFD: %s"):format(tostring(rf ~= nil), tostring(rf and type(rf.GetFFD))),
		("health text on: %s, in combat: %s"):format(tostring(self.db.health.enabled), tostring(InCombatLockdown())),
	}
	local list = rf and rf._partyAllButtons
	out[#out + 1] = ("party buttons: %s, unit map: %s"):format(list and tostring(#list) or "none", tostring(rf and rf._partyUnitToButton ~= nil))
	for i, btn in ipairs(list or {}) do
		local ok, unit = pcall(btn.GetAttribute, btn, "unit")
		local w = widgets[btn]
		local width = w and select(2, pcall(w.span.GetWidth, w.span))
		out[#out + 1] = ("  button %d: unit %s, visible %s, widget %s, live %s, span width %s%s"):format(
			i, tostring(ok and unit or "?"), tostring(btn:IsVisible()), tostring(w ~= nil), tostring(w and w.live),
			width ~= nil and (IsSecret(width) and "secret" or tostring(width)) or "-",
			w and w.host:IsShown() and "" or " (host hidden)")
	end
	return out
end
