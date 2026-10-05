--------------------------------------------------------------------------------
-- Forbidden Sacrifice (Unholy, Putrefy)
-- Unholy's Forbidden Knowledge talent grants Forbidden Sacrifice, Mastery for
-- 12 seconds per stack. Stacks come from a Putrefy press (one press can bring
-- two) and from Dread Plague's Lesser Ghoul, which putrefies with no press at
-- all, and each stack runs out on its own 12 seconds. This shows one bar per
-- stack, each draining over its own 12 seconds, the oldest nearest the anchor.
--
-- WHY THE BARS RUN ON OUR OWN CLOCK
-- The game keeps Forbidden Sacrifice as ONE aura with a stack count; its one
-- timer restarts with every new stack and the time each stack has left is not
-- in the aura data at all. So each new stack is noticed and timed from that
-- moment, and a stack is gone 12 seconds later.
--
-- Noticing a new stack, in order of preference:
-- 1. The stack count. Out of combat always; in combat only if the game flags
--    the spell as never secret (C_Secrets). Each UNIT_AURA compares the count
--    with the bars running: more starts bars, fewer ends the oldest.
-- 2. The echo: an aura cast on you by a hidden triggered spell shows up in
--    SPELL_UPDATE_COOLDOWN with that spell's ID in plain numbers. One echo of
--    the aura's ID = one new stack.
-- 3. Neither known to work yet: the engine draws the one aura as one bar with
--    its stack count on the icon, the only view that needs no numbers. The
--    first echo seen switches to per-stack bars for the rest of the session.
-- /xui debug ForbiddenSacrifice shows what arrives.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates
local Style = XUI.Style

local AURA = 1256576
local AURA_IDS = { 1256576, 1256565 }
local DURATION, MAX_BARS, MAX_DURATION, PREVIEW_EVERY, SAME_CAST = 12, 8, 60, 4, 0.3
local GROUP = "forbiddenSacrifice"
local DEFAULT_ICON = 136157

local M = XUI:NewModule("ForbiddenSacrifice", {
	name = "Forbidden Sacrifice",
	desc = "One bar per Forbidden Sacrifice stack, each draining over its own 12 seconds.",
	category = "class",
	icon = DEFAULT_ICON,
	order = 90,
	classes = { "DEATHKNIGHT" },
	specs = { 252 },
	untested = true,
	defaults = {
		bar = T.Bar(200, 20, { color = { 0.44, 0.76, 0.22, 1 } }),
		border = T.Border(),
		grow = "DOWN",
		spacing = 2,
		showIcon = true,
		timerText = T.Font(12, { enabled = true }),
		stackText = T.Font(12, { enabled = true }),
		position = T.Position(0, -180),
	},
})
M.GROW = { { value = "DOWN", text = "Down" }, { value = "UP", text = "Up" } }

local IsSecret = XUI.IsSecret
local AXIS = AnchorUtil and AnchorUtil.FlowLayoutAxis
local DIR = AnchorUtil and AnchorUtil.FlowDirection

local holder, stackLayer, container
local slots, buttons = {}, {}
local starts, fake = {}, {}
local echoSeen, lastCastAt, lastRead = false, {}, nil
local useEngine, stylePending, rereadNext = false, false, false
local failed, bindFailed
local ticker, lastFake = nil, 0
local LOG_MAX = 40
local logAt, logWhat, logN = {}, {}, 0

local function Log(what)
	logN = logN % LOG_MAX + 1
	logAt[logN], logWhat[logN] = GetTime(), what
end

local function Holder()
	if holder then return holder end
	holder = CreateFrame("Frame", "XUI_ForbiddenSacrifice", UIParent)
	holder:SetSize(200, 20)
	holder:Hide()
	stackLayer = CreateFrame("Frame", nil, holder)
	stackLayer:SetAllPoints(holder)
	stackLayer:Hide()
	XUI.Movers:Register(holder, M, "position")
	return holder
end

local function Up() return M.db.grow == "UP" end
local function Corner() return Up() and "BOTTOMLEFT" or "TOPLEFT" end
local function Size()
	local b = Style:Resolve("bar", M.db.bar)
	return b.width or 200, b.height or 20
end

--------------------------------------------------------------------------------
-- One bar (icon, bar, texts): the per-stack bars and the engine's button share it
--------------------------------------------------------------------------------
local function MakeFace(parent)
	local p = {}
	p.root = CreateFrame("Frame", nil, parent)
	p.root:SetAllPoints(parent)
	p.iconBox = CreateFrame("Frame", nil, p.root)
	p.icon = p.iconBox:CreateTexture(nil, "ARTWORK")
	p.iconBorder = Style:Border(p.iconBox)
	p.barBox = CreateFrame("Frame", nil, p.root)
	p.bar = CreateFrame("StatusBar", nil, p.barBox)
	p.barBorder = Style:Border(p.barBox)
	p.texts = CreateFrame("Frame", nil, p.root)
	p.texts:SetAllPoints(p.root)
	p.texts:SetFrameLevel(p.bar:GetFrameLevel() + 5)
	p.timer = p.texts:CreateFontString(nil, "OVERLAY")
	p.stack = p.texts:CreateFontString(nil, "OVERLAY")
	Style:ApplyFont(p.timer, nil, 12)
	Style:ApplyFont(p.stack, nil, 12)
	return p
end

local function Inset(region, parent, inset)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -inset)
	region:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, inset)
end

local function StyleFace(p)
	local db = M.db
	local w, h = Size()
	local corner = Corner()
	p.root:ClearAllPoints()
	p.root:SetPoint(corner, p.root:GetParent(), corner, 0, 0)
	p.root:SetSize(w, h)
	local left = 0
	p.iconBox:SetShown(db.showIcon)
	if db.showIcon then
		p.iconBox:ClearAllPoints()
		p.iconBox:SetPoint("TOPLEFT", p.root, "TOPLEFT", 0, 0)
		p.iconBox:SetSize(h, h)
		Inset(p.icon, p.iconBox, p.iconBorder:Apply(db.border))
		Style:IconTexCoord(p.icon, h, h)
		p.icon:SetTexture(XUI.GetSpellIcon(AURA, DEFAULT_ICON))
		left = h + 2
	end
	p.barBox:ClearAllPoints()
	p.barBox:SetPoint("TOPLEFT", p.root, "TOPLEFT", left, 0)
	p.barBox:SetSize(math.max(1, w - left), h)
	Inset(p.bar, p.barBox, p.barBorder:Apply(db.border))
	Style:ApplyBar(p.bar, db.bar)
	local r, g, b = XUI.UnpackColor(Style:Resolve("bar", db.bar).color, 0.44, 0.76, 0.22)
	p.bar:SetStatusBarColor(r, g, b)
	Style:ApplyFont(p.timer, db.timerText)
	p.timer:ClearAllPoints()
	p.timer:SetPoint("RIGHT", p.bar, "RIGHT", -4, 0)
	p.timer:SetJustifyH("RIGHT")
	p.timer:SetShown(db.timerText.enabled ~= false)
	Style:ApplyFont(p.stack, db.stackText)
	p.stack:ClearAllPoints()
	if db.showIcon then
		p.stack:SetPoint("CENTER", p.iconBox, "CENTER", 0, 0)
		p.stack:SetJustifyH("CENTER")
	else
		p.stack:SetPoint("LEFT", p.bar, "LEFT", 4, 0)
		p.stack:SetJustifyH("LEFT")
	end
	p.stack:SetShown(db.stackText.enabled ~= false)
end

--------------------------------------------------------------------------------
-- The stack clock
--------------------------------------------------------------------------------
local function Prune(now)
	for i = #starts, 1, -1 do
		if now - starts[i] >= DURATION then
			table.remove(starts, i)
			table.remove(fake, i)
		end
	end
end

local function Add(isFake, at)
	local now = GetTime()
	Prune(now)
	if #starts >= MAX_BARS then
		table.remove(starts, 1)
		table.remove(fake, 1)
	end
	starts[#starts + 1] = at or now
	fake[#fake + 1] = isFake and true or false
end

local function ClearWhere(fakeOnes)
	for i = #starts, 1, -1 do
		if fake[i] == fakeOnes then
			table.remove(starts, i)
			table.remove(fake, i)
		end
	end
end

local function RealCount()
	local n = 0
	for i = 1, #starts do if not fake[i] then n = n + 1 end end
	return n
end

local function DropOldestReal(count)
	local i = 1
	while count > 0 and i <= #starts do
		if not fake[i] then
			table.remove(starts, i)
			table.remove(fake, i)
			count = count - 1
		else
			i = i + 1
		end
	end
end

local function AuraSecret()
	local S = C_Secrets
	if S and S.ShouldSpellAuraBeSecret then
		local ok, v = pcall(S.ShouldSpellAuraBeSecret, AURA)
		if ok and type(v) == "boolean" then return v end
	end
	if S and S.ShouldAurasBeSecret then
		local ok, v = pcall(S.ShouldAurasBeSecret)
		if ok and type(v) == "boolean" then return v end
	end
	return false
end

-- the stack count in the clear, or nil
local function ReadStacks()
	if AuraSecret() then return nil end
	local U = C_UnitAuras
	if not (U and U.GetPlayerAuraBySpellID) then return nil end
	local ok, a = pcall(U.GetPlayerAuraBySpellID, AURA)
	if not ok then return nil end
	if a == nil then return 0 end
	if IsSecret(a) then return nil end
	local n = a.applications
	if IsSecret(n) then return nil end
	n = tonumber(n) or 0
	return n < 1 and 1 or n
end

local function Reconcile()
	local n = ReadStacks()
	if n == nil then return false end
	Prune(GetTime())
	local have = RealCount()
	if n > have then
		for _ = 1, n - have do Add(false) end
	elseif n < have then
		DropOldestReal(have - n)
	end
	if n ~= lastRead then lastRead = n Log("stacks " .. n) end
	return true
end

-- one echo (or cast) of the aura's ID = one new stack, when the count is secret
local function OnEcho(id, fromCast)
	local now = GetTime()
	if not fromCast then
		local c = lastCastAt[id]
		if c and now - c < SAME_CAST then return false end
		Log("echo " .. id)
	end
	if id ~= AURA then return false end
	echoSeen = true
	if AuraSecret() then Add(false) end
	return true
end

--------------------------------------------------------------------------------
-- Drawing the per-stack bars
--------------------------------------------------------------------------------
local function LayoutSlot(s, i)
	local corner = Corner()
	local w, h = Size()
	local step = (Up() and 1 or -1) * (h + M.db.spacing)
	s.anchor:ClearAllPoints()
	s.anchor:SetPoint(corner, holder, corner, 0, (i - 1) * step)
	s.anchor:SetSize(w, h)
	StyleFace(s.p)
	s.p.bar:SetMinMaxValues(0, DURATION)
	s.p.stack:SetText("")
	s.tenth = nil
end

local function Slot(i)
	local s = slots[i]
	if not s then
		local anchor = CreateFrame("Frame", nil, stackLayer)
		anchor:Hide()
		s = { anchor = anchor, p = MakeFace(anchor) }
		slots[i] = s
		LayoutSlot(s, i)
	end
	return s
end

local function Render()
	local now = GetTime()
	Prune(now)
	if M:IsPreview() and now - lastFake >= PREVIEW_EVERY then
		lastFake = now
		Add(true)
	end
	local n = #starts
	for i = 1, n do
		local s = Slot(i)
		local left = math.max(0, DURATION - (now - starts[i]))
		s.p.bar:SetValue(left)
		local tenth = math.ceil(left * 10)
		if tenth ~= s.tenth then
			s.tenth = tenth
			s.p.timer:SetText(("%.1f"):format(tenth / 10))
		end
		if not s.anchor:IsShown() then s.anchor:Show() end
	end
	for i = n + 1, #slots do
		if slots[i].anchor:IsShown() then slots[i].anchor:Hide() end
	end
end

-- the clock redraws ten times a second, only while there is something to draw
local function SyncTicker()
	local want = holder and stackLayer:IsShown() and not useEngine
	if want and not ticker then
		ticker = M:NewTicker(0.1, function() Render() end)
	elseif not want and ticker then
		M:CancelTicker(ticker)
		ticker = nil
	end
end

--------------------------------------------------------------------------------
-- The engine's one-bar fallback
--------------------------------------------------------------------------------
local function GroupLayout()
	local w, h = Size()
	return { elementWidth = w, elementHeight = h + M.db.spacing, elementSpacing = 0, lineSpacing = 0 }
end

local function Flow(c)
	local up = Up()
	c:SetFlowLayoutAxis(AXIS.Vertical)
	c:SetFlowLayoutAnchorPoint(Corner())
	c:SetFlowLayoutGrowthDirection(DIR.Right, up and DIR.Up or DIR.Down)
	c:SetFlowLayoutPadding(0, 0, up and 1 or 0, up and 0 or 1)
end

local function InitButton(b)
	XUI.Engine.Silence(b)
	pcall(b.SetSize, b, 1, 1)
	local p = MakeFace(b)
	pcall(StyleFace, p)
	local ok, err = pcall(b.SetDurationBar, b, p.bar, XUI.DurationBarOptions())
	if not ok then bindFailed = "bar: " .. tostring(err) end
	ok, err = pcall(b.SetDurationText, b, p.timer, XUI.TenthsTextOptions())
	if not ok then bindFailed = "timer: " .. tostring(err) end
	ok, err = pcall(b.SetApplicationCount, b, p.stack)
	if not ok then bindFailed = "stacks: " .. tostring(err) end
	buttons[#buttons + 1] = p
end

local function EnsureContainer()
	if container or failed then return end
	if not (XUI.HasAuraContainers() and AXIS and DIR) then failed = "aura containers unavailable" return end
	local c, why = XUI.Engine.NewContainer(holder, "XUI_ForbiddenSacrificeContainer")
	if not c then failed = why return end
	local okF, errF = pcall(Flow, c)
	if not okF then failed = "column layout refused: " .. tostring(errF) c:Hide() return end
	local include = {}
	for _, id in ipairs(AURA_IDS) do include[id] = true end
	local SM, SD = AuraContainerSortMethod, AuraContainerSortDirection
	local okG, errG = pcall(c.AddAuraGroup, c, GROUP, "HELPFUL", {
		maxFrameCount = MAX_BARS,
		-- the duration cap keeps out a permanent aura under the talent's ID
		candidateFilters = { includeSpellIDs = include, maxDuration = MAX_DURATION },
		sortMethod = SM and SM.ExpirationOnly or 5,
		sortDirection = SD and SD.Normal or 0,
		initializeFrame = InitButton,
		layout = GroupLayout(),
	})
	if not okG then failed = tostring(errG) c:Hide() return end
	pcall(c.SetEnabled, c, false)
	c:SetPoint(Corner(), holder, Corner(), 0, 0)
	c:Hide()
	container = c
end

local function Restyle()
	stylePending = false
	for i, s in ipairs(slots) do LayoutSlot(s, i) end
	for _, p in ipairs(buttons) do
		if not pcall(StyleFace, p) then stylePending = true end
	end
	local c = container
	if c then
		if not pcall(c.SetAuraGroupLayout, c, GROUP, GroupLayout()) then stylePending = true end
		if not pcall(Flow, c) then stylePending = true end
		if not pcall(function() c:ClearAllPoints() c:SetPoint(Corner(), holder, Corner(), 0, 0) end) then stylePending = true end
	end
end

local function UpdateShown()
	if not holder then return end
	useEngine = M.running and not M:IsPreview() and container ~= nil and not echoSeen and AuraSecret()
	if container then container:SetShown(useEngine) end
	stackLayer:SetShown((M:IsPreview() or (M.running and #starts > 0)) and not useEngine)
	SyncTicker()
end

local function Refresh()
	if not holder then return end
	UpdateShown()
	if stackLayer:IsShown() then Render() end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------
function M:OnEnable()
	Holder()
	self:RegisterUnitEvent("UNIT_AURA", "player", function()
		if Reconcile() then Refresh() else UpdateShown() end
	end)
	self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, _, _, _, spellID)
		if spellID == nil or IsSecret(spellID) then return end
		lastCastAt[spellID] = GetTime()
		Log("cast " .. spellID)
		if OnEcho(spellID, true) then Refresh() end
	end)
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN", function(_, _, spellID)
		if spellID == nil or IsSecret(spellID) then return end
		if OnEcho(spellID, false) then Refresh() end
	end)
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function() UpdateShown() end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if stylePending then Restyle() end
		Reconcile()
		Refresh()
	end)
	self:RegisterEvent("PLAYER_DEAD", function() ClearWhere(false) Refresh() end)
	self:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", function(self)
		if stylePending then self:After(0, Restyle) end
	end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(self)
		rereadNext = true
		self:After(0.5, function(self) self:Refresh() end)
	end)
end

function M:OnDisable()
	ClearWhere(false)
	if container then pcall(container.SetEnabled, container, false) end
	ticker = nil
	if holder and not self:IsPreview() then holder:Hide() end
end

function M:OnRefresh()
	if not (holder or self:IsPreview()) then return end
	local h = Holder()
	XUI.Movers:Apply(h)
	local w, ht = Size()
	h:SetSize(w, ht)
	local preview = self:IsPreview()
	ClearWhere(true)
	if preview then
		local now = GetTime()
		for k = 2, 0, -1 do Add(true, now - k * PREVIEW_EVERY) end
		lastFake = now
	end
	if self.running then EnsureContainer() end
	Restyle()
	h:SetShown(preview or self.running)
	local c = container
	if c then
		if self.running and not preview then
			pcall(c.SetUnit, c, "player")
			pcall(c.SetEnabled, c, true)
			if rereadNext then pcall(c.UpdateAllAuras, c) end
		else
			pcall(c.SetEnabled, c, false)
		end
	end
	rereadNext = false
	if self.running and not preview then Reconcile() end
	Refresh()
end

function M:DebugInfo()
	local out = {
		("stacks readable now: %s, echo seen: %s, stack bars running: %d"):format(tostring(not AuraSecret()), tostring(echoSeen), RealCount()),
		("showing: %s; container %s, buttons %d, failure: %s, binding: %s"):format(
			useEngine and "the one engine bar" or "a bar per stack", container and "built" or "not built", #buttons, tostring(failed), tostring(bindFailed)),
	}
	local parts, now = {}, GetTime()
	for k = LOG_MAX - 1, 0, -1 do
		local j = (logN - k - 1) % LOG_MAX + 1
		if logAt[j] then parts[#parts + 1] = ("%s (%.1fs ago)"):format(logWhat[j], now - logAt[j]) end
	end
	out[#out + 1] = "log: " .. (#parts > 0 and table.concat(parts, ", ") or "empty")
	return out
end
