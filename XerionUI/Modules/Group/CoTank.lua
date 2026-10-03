--------------------------------------------------------------------------------
-- Co-Tank
-- In a raid, the other tank's health as one bar where you want it, with
-- their (boss) debuffs beside it - the whole of a taunt swap.
--
-- * Health never becomes a number here: UnitHealth is secret, so it goes
--   straight into the widget (SetValue / SetFormattedText take secrets), and
--   the percentage goes through Blizzard's ScaleTo100 curve.
-- * The debuffs are never read: an AuraContainer of the engine's fills icons
--   we build (12.1). Two groups are declared once (boss-or-role auras, and
--   all minus noise like Sated); the setting moves the frame budget between
--   them, which does take effect live.
-- * The container can freeze (a pass that throws leaves it dirty and never
--   re-armed). A slow watchdog asks for a layout and reads GetOnUpdateMode; a
--   frozen container is replaced (spaced out and capped).
-- * An unreadable role keeps whoever is already on the bar.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates
local Style = XUI.Style

local M = XUI:NewModule("CoTank", {
	name = "Co-Tank",
	desc = "The other tank's health and debuffs in raids.",
	category = "group",
	icon = [[Interface\Icons\Ability_Warrior_DefensiveStance]],
	order = 40,
	defaults = {
		tankOnly = true,
		pinName = "",
		bar = T.Bar(200, 22),
		border = T.Border(),
		bgAlpha = 0.25,
		nameText = T.Font(12, { anchor = "LEFT", x = 4, y = 0 }),
		healthText = T.Font(12, { anchor = "RIGHT", x = -4, y = 0 }),
		debuffs = {
			enabled = true,
			bossOnly = false,
			max = 5,
			spacing = 3,
			grow = "RIGHT",
			attach = "BOTTOMLEFT",
			x = 0,
			y = -4,
			tooltip = true,
			dispelBorder = true,
			borderSize = 2,
		},
		debuffIcon = T.Icon(26),
		durText = T.Font(12, { anchor = "CENTER", x = 0, y = 0 }),
		stackText = T.Font(11, { anchor = "BOTTOMRIGHT", x = 0, y = 0 }),
		position = T.Position(0, 200),
	},
})

M.GROW = {
	{ value = "RIGHT", text = "Right" }, { value = "LEFT", text = "Left" },
	{ value = "UP", text = "Up" }, { value = "DOWN", text = "Down" },
}

local IsSecret = XUI.IsSecret
local WHITE = [[Interface\Buttons\WHITE8X8]]
local RAID = {}
for i = 1, 40 do RAID[i] = "raid" .. i end

--------------------------------------------------------------------------------
-- Who the co-tank is
--------------------------------------------------------------------------------
local coUnit

local function IsTankUnit(unit)
	local ok, role = pcall(UnitGroupRolesAssigned, unit)
	if not ok or IsSecret(role) then return nil end
	if role == "TANK" then return true end
	if role == "NONE" and GetPartyAssignment then
		if XUI.Ask(GetPartyAssignment, "MAINTANK", unit) then return true end
	end
	return false
end

local function PinnedName(db)
	local want = (db.pinName or ""):match("^%s*(.-)%s*$")
	if want == "" then return nil end
	return want:match("^[^%-]+") or want
end

local function NameMatches(unit, want)
	local name = UnitName(unit)
	if IsSecret(name) or type(name) ~= "string" then return false end
	return name == want or name:lower() == want:lower()
end

local function FindCoTank()
	if not IsInRaid() then return nil end
	local _, itype = IsInInstance()
	if itype == "pvp" or itype == "arena" then return nil end
	local db = M.db
	local want = PinnedName(db)
	local gate = db.tankOnly
	if not want and gate and not XUI.PlayerIsTank(true) then return nil end
	local pinned, first, kept, unknown
	for i = 1, 40 do
		local u = RAID[i]
		if UnitExists(u) then
			-- the bar must never be you; a secret answer is skipped
			local same = UnitIsUnit(u, "player")
			if not IsSecret(same) and not same then
				if want and not pinned and NameMatches(u, want) then pinned = u end
				local tank = IsTankUnit(u)
				if tank then
					first = first or u
					if u == coUnit then kept = u end
				elseif tank == nil then
					unknown = true
				end
			end
		end
	end
	if pinned then return pinned end
	if want and gate and not XUI.PlayerIsTank(true) then return nil end
	if kept or first then return kept or first end
	if unknown and coUnit and UnitExists(coUnit) then return coUnit end
	return nil
end

--------------------------------------------------------------------------------
-- The bar
--------------------------------------------------------------------------------
local frame, holder
local painted = {}

local function EnsureFrame()
	if frame then return end
	frame = XUI.Widgets:CreateBar("XUI_CoTank")
	frame:Hide()
	frame.name:SetWordWrap(false)
	holder = CreateFrame("Frame", nil, frame)
	holder:SetSize(1, 1)
	holder:SetFrameLevel(frame:GetFrameLevel() + 5)
	XUI.Movers:Register(frame, M, "position")
end

local function PlaceText(fs, host, block, defaultAnchor)
	Style:ApplyFont(fs, block)
	local a = block.anchor or defaultAnchor
	fs:ClearAllPoints()
	fs:SetPoint(a, host, a, block.x or 0, block.y or 0)
end

local function ApplyVisual()
	local db = M.db
	painted = {}
	frame:ApplyLayout(db.bar, db.border, "NONE")
	PlaceText(frame.name, frame.bar, db.nameText, "LEFT")
	PlaceText(frame.time, frame.bar, db.healthText, "RIGHT")
	frame.name:SetShown(db.nameText.enabled ~= false)
	frame.time:SetAlpha(db.healthText.enabled == false and 0 or 1)
end

local function PaintIdentity(unit)
	local _, class = UnitClass(unit)
	local r, g, b = XUI.ClassColor(class)
	local a = M.db.bgAlpha
	if r ~= painted.r or g ~= painted.g or b ~= painted.b or a ~= painted.a then
		painted.r, painted.g, painted.b, painted.a = r, g, b, a
		frame:SetColor(r, g, b, 1)
		if frame.bar.__xuiBarBg then frame.bar.__xuiBarBg:SetVertexColor(r * 0.35, g * 0.35, b * 0.35, a) end
	end
	local name = UnitName(unit)
	if IsSecret(name) then
		painted.name = nil
		frame.name:SetText(name)
	elseif name ~= painted.name then
		painted.name = name
		frame.name:SetText(name or UNKNOWN or "?")
	end
end

local function PaintHealth(unit)
	frame.bar:SetMinMaxValues(0, UnitHealthMax(unit))
	frame.bar:SetValue(UnitHealth(unit))
	local connected, dead = UnitIsConnected(unit), UnitIsDeadOrGhost(unit)
	if not IsSecret(connected) and connected == false then
		frame.time:SetText("|cff888888off|r")
	elseif not IsSecret(dead) and dead then
		frame.time:SetText("|cffff4444dead|r")
	else
		local curve = UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100
		if curve then
			frame.time:SetFormattedText("%d%%", UnitHealthPercent(unit, true, curve))
		else
			frame.time:SetText("")
		end
	end
end

local function UpdateHealth()
	if M:IsPreview() or not (frame and coUnit) then return end
	if not pcall(PaintHealth, coUnit) then frame.time:SetText("") end
end

--------------------------------------------------------------------------------
-- The debuff row
--------------------------------------------------------------------------------
local container, containerFailed
local groupOK = {}
local buttons = {}
local stylePending = false
local rebuilds, lastRebuild = 0, -math.huge
local MAX_REBUILDS, REBUILD_GAP = 10, 10

local function IconSize(db)
	local i = Style:Resolve("icon", db.debuffIcon)
	return i.width or 26, i.height or i.width or 26
end

local function Layout(db)
	local w, h = IconSize(db)
	local sp = db.debuffs.spacing
	return { elementSpacing = sp, lineSpacing = sp, elementWidth = w, elementHeight = h }
end

-- the engine owns the shown state and alpha of its strings, so "hide" dims a
-- frame of ours in between
local function PlaceIconText(fs, host, block, defaultAnchor, alphaTarget)
	Style:ApplyFont(fs, block)
	local a = block.anchor or defaultAnchor
	fs:ClearAllPoints()
	fs:SetPoint(a, host, a, block.x or 0, block.y or 0)
	local target = alphaTarget or host
	target:SetAlpha(block.enabled == false and 0 or 1)
end

local function StyleOne(rec, db)
	local w, h = IconSize(db)
	local px = db.debuffs.dispelBorder and math.max(1, db.debuffs.borderSize) or 1
	px = Style:Pixels(rec.frame, px)
	rec.frame:SetSize(w, h)
	rec.icon:ClearAllPoints()
	rec.icon:SetPoint("TOPLEFT", rec.ihost, "TOPLEFT", px, -px)
	rec.icon:SetPoint("BOTTOMRIGHT", rec.ihost, "BOTTOMRIGHT", -px, px)
	Style:IconTexCoord(rec.icon, w, h, Style:Resolve("icon", db.debuffIcon).zoom)
	rec.bhost:SetAlpha(db.debuffs.dispelBorder and 1 or 0)
	PlaceIconText(rec.dur, rec.durHost, db.durText, "CENTER")
	PlaceIconText(rec.stack, rec.stackHost, db.stackText, "BOTTOMRIGHT")
	-- motion only: a click in the play field must reach the world
	rec.frame:SetMouseClickEnabled(false)
	rec.frame:SetMouseMotionEnabled(db.debuffs.tooltip)
end

local function InitButton(b)
	local db = M.db
	local w, h = IconSize(db)
	b:SetSize(w, h)
	pcall(b.SetTooltipAnchorPoint, b, "ANCHOR_RIGHT")
	local backdrop = b:CreateTexture(nil, "BACKGROUND")
	backdrop:SetColorTexture(0, 0, 0, 1)
	backdrop:SetAllPoints()
	-- one solid square behind an inset icon; the engine tints it by dispel
	-- type and shows it per aura, and the black backdrop is the border when
	-- it is hidden
	local bhost = CreateFrame("Frame", nil, b)
	bhost:SetAllPoints()
	local tint = bhost:CreateTexture(nil, "BACKGROUND")
	tint:SetAllPoints()
	tint:SetTexture(WHITE)
	tint:Hide()
	local ihost = CreateFrame("Frame", nil, b)
	ihost:SetAllPoints()
	ihost:SetFrameLevel(bhost:GetFrameLevel() + 1)
	local icon = ihost:CreateTexture(nil, "ARTWORK")
	b:SetIcon(icon)
	local cd = CreateFrame("Cooldown", nil, ihost, "CooldownFrameTemplate")
	cd:SetAllPoints(icon)
	cd:SetReverse(true)
	cd:SetDrawEdge(false)
	cd:SetDrawBling(false)
	cd:SetHideCountdownNumbers(true)
	cd.noCooldownCount = true
	b:SetDurationCooldown(cd)
	local durHost = CreateFrame("Frame", nil, b)
	durHost:SetAllPoints()
	durHost:SetFrameLevel(cd:GetFrameLevel() + 5)
	local stackHost = CreateFrame("Frame", nil, b)
	stackHost:SetAllPoints()
	stackHost:SetFrameLevel(cd:GetFrameLevel() + 6)
	local dur = durHost:CreateFontString(nil, "OVERLAY")
	local stack = stackHost:CreateFontString(nil, "OVERLAY")
	-- fonts before handover: the engine writes to the strings at once
	PlaceIconText(dur, durHost, db.durText, "CENTER")
	PlaceIconText(stack, stackHost, db.stackText, "BOTTOMRIGHT")
	b:SetDurationText(dur, XUI.DurationTextOptions())
	b:SetApplicationCount(stack)
	local style = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
	if b.AddDispelTypeTexture and style and style.PreserveAsset ~= nil then
		pcall(b.AddDispelTypeTexture, b, tint, {
			style = style.PreserveAsset, showWhenHarmful = true, showWhenHelpful = false, showWithoutDispelType = true,
		})
	end
	local rec = { frame = b, bhost = bhost, ihost = ihost, icon = icon, dur = dur, durHost = durHost, stack = stack, stackHost = stackHost }
	buttons[#buttons + 1] = rec
	pcall(StyleOne, rec, db)
end

-- Sated and friends sit on both tanks for ten minutes after the first lust;
-- Stagger is a Brewmaster's own. Only never-secret spells can be excluded.
local NOISE = { 26013, 71041, 124255, 124273, 124274, 124275 }
local function NoiseFilter()
	local set = {}
	for _, id in ipairs(XUI.SATED_IDS) do set[id] = true end
	for _, id in ipairs(NOISE) do set[id] = true end
	return { excludeSpellIDs = set }
end

local function AddGroup(c, key, candidates)
	local SM, SD = AuraContainerSortMethod, AuraContainerSortDirection
	local ok = pcall(c.AddAuraGroup, c, key, "HARMFUL", {
		maxFrameCount = 0,
		candidateFilters = candidates,
		-- the debuff about to fall off is the swap
		sortMethod = SM and SM.Expiration or 4,
		sortDirection = SD and SD.Normal or 0,
		layout = Layout(M.db),
		initializeFrame = InitButton,
	})
	if ok then groupOK[key] = true end
end

local function ApplyGrowth(db)
	local FD = AnchorUtil and AnchorUtil.FlowDirection
	if not FD then return end
	local grow = db.debuffs.grow
	local vertical = grow == "UP" or grow == "DOWN"
	local corner = (grow == "LEFT" and "TOPRIGHT") or (grow == "UP" and "BOTTOMLEFT") or "TOPLEFT"
	XUI.ContainerFlow(container, "SetFlowLayoutAnchorPoint", "SetAuraLayoutAnchorPoint", corner)
	XUI.ContainerFlow(container, "SetFlowLayoutGrowthDirection", "SetAuraLayoutGrowthDirection",
		grow == "LEFT" and FD.Left or FD.Right, grow == "UP" and FD.Up or FD.Down)
	local hasAxis = AnchorUtil.FlowLayoutAxis and container.SetFlowLayoutAxis and true or false
	if hasAxis then
		XUI.ContainerFlow(container, "SetFlowLayoutAxis", nil,
			vertical and AnchorUtil.FlowLayoutAxis.Vertical or AnchorUtil.FlowLayoutAxis.Horizontal)
	end
	XUI.ContainerFlow(container, "SetFlowLayoutMaximumLineSize", "SetAuraLayoutRowWidth", (vertical and not hasAxis) and 1 or nil)
	container:ClearAllPoints()
	container:SetPoint(corner, holder, corner, 0, 0)
end

local function SizeHolder(db)
	local d = db.debuffs
	local n = math.max(1, d.max)
	local w, h = IconSize(db)
	if d.grow == "UP" or d.grow == "DOWN" then
		holder:SetSize(w, n * h + (n - 1) * d.spacing)
	else
		holder:SetSize(n * w + (n - 1) * d.spacing, h)
	end
	holder:ClearAllPoints()
	holder:SetPoint(d.attach, frame, d.attach, d.x, d.y)
end

local function ApplyDebuffLook()
	if not frame then return end
	local db = M.db
	SizeHolder(db)
	if not container then return end
	stylePending = false
	for _, rec in ipairs(buttons) do
		if not pcall(StyleOne, rec, db) then stylePending = true end
	end
	local n = db.debuffs.enabled and math.max(0, db.debuffs.max) or 0
	local bossOnly = db.debuffs.bossOnly and groupOK.boss
	if not groupOK.all then bossOnly = true end
	for key in pairs(groupOK) do
		pcall(container.SetAuraGroupLayout, container, key, Layout(db))
		local mine = (key == "boss") == (bossOnly and true or false)
		pcall(container.SetAuraGroupMaxFrameCount, container, key, mine and n or 0)
	end
	ApplyGrowth(db)
end

local function EnsureContainer()
	if container or containerFailed or not XUI.HasAuraContainers() then return end
	if not M.db.debuffs.enabled then return end
	EnsureFrame()
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, holder, "CustomAuraContainerTemplate")
	if not ok or not c then
		containerFailed = true
		return
	end
	c:SetSize(1, 1)
	AddGroup(c, "boss", { isBossOrRoleAura = true })
	AddGroup(c, "all", NoiseFilter())
	if not (groupOK.boss or groupOK.all) then
		containerFailed = true
		c:Hide()
		return
	end
	pcall(c.SetEnabled, c, false)
	container = c
	ApplyDebuffLook()
end

local function SyncDebuffs()
	if not container then return false end
	local on = M.running and M.db.debuffs.enabled and coUnit and not M:IsPreview()
	if on then
		-- the container's own answer, so a refused SetUnit is tried again
		local okU, bound = pcall(container.GetUnit, container)
		if not okU or IsSecret(bound) or bound ~= coUnit then pcall(container.SetUnit, container, coUnit) end
		pcall(container.SetEnabled, container, true)
	else
		pcall(container.SetEnabled, container, false)
	end
	return on and true or false
end

local MODE_OFF = Enum and Enum.OnUpdateMode and Enum.OnUpdateMode.Disabled or 0
local function EngineStalled()
	if not container then return nil end
	local key = groupOK.all and "all" or "boss"
	if not pcall(container.SetAuraGroupLayout, container, key, Layout(M.db)) then return nil end
	if not container.GetOnUpdateMode then return nil end
	local ok, mode = pcall(container.GetOnUpdateMode, container)
	if not ok or IsSecret(mode) or type(mode) ~= "number" then return nil end
	return mode == MODE_OFF
end

local function RebuildContainer()
	local old = container
	if not old then return end
	container = nil
	pcall(old.SetEnabled, old, false)
	pcall(old.Hide, old)
	wipe(groupOK)
	wipe(buttons)
	stylePending = false
	rebuilds, lastRebuild = rebuilds + 1, GetTime()
	EnsureContainer()
	SyncDebuffs()
end

local function Watchdog()
	if not (container and frame:IsVisible()) then return end
	if rebuilds >= MAX_REBUILDS or GetTime() - lastRebuild < REBUILD_GAP then return end
	if EngineStalled() then RebuildContainer() end
end

--------------------------------------------------------------------------------
-- Keeping it current
--------------------------------------------------------------------------------
local hpFrame = CreateFrame("Frame")
hpFrame:SetScript("OnEvent", UpdateHealth)
local watched
local function Rewatch(unit)
	if unit == watched then return end
	watched = unit
	hpFrame:UnregisterAllEvents()
	if unit then
		hpFrame:RegisterUnitEvent("UNIT_HEALTH", unit)
		hpFrame:RegisterUnitEvent("UNIT_MAXHEALTH", unit)
		hpFrame:RegisterUnitEvent("UNIT_CONNECTION", unit)
		hpFrame:RegisterUnitEvent("UNIT_FLAGS", unit)
	end
end

local ticker
local rereadNext, unitSeen = false, true

local function UnitSeen(unit)
	local vis, con = UnitIsVisible(unit), UnitIsConnected(unit)
	if IsSecret(vis) or IsSecret(con) then return true end
	return (vis and con) and true or false
end

function M:Scan(reread)
	if self:IsPreview() then return end
	reread = reread or rereadNext
	rereadNext = false
	local unit
	if self.running then
		if self.testMode then
			unit = UnitExists("target") and "target" or "player"
		else
			unit = FindCoTank()
		end
	end
	local changed = unit ~= coUnit
	coUnit = unit
	Rewatch(unit)
	if not unit then
		if frame then frame:Hide() end
		SyncDebuffs()
		if ticker then self:CancelTicker(ticker) ticker = nil end
		return
	end
	EnsureFrame()
	EnsureContainer()
	PaintIdentity(unit)
	UpdateHealth()
	frame:Show()
	local live = SyncDebuffs()
	-- UNIT_AURA stops for a unit out of sight and nothing is sent when they
	-- come back, so a regained unit is re-read
	local seen = UnitSeen(unit)
	local regained = seen and not unitSeen
	unitSeen = seen
	if container and (reread or regained) and not changed then pcall(container.UpdateAllAuras, container) end
	if live then Watchdog() end
	-- a slow safety net while the bar is up: deaths and respecs are not
	-- reliably one event each
	if not ticker then ticker = self:NewTicker(2, function() self:Scan() end) end
end

local QueueReread = XUI.Coalesce(function() if M.running then M:Scan(true) end end)

function M:OnEnable()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(self)
		rereadNext = true
		self:After(0.5, function() self:Scan() end)
	end)
	local function roster(self)
		if self:IsPreview() then return end
		if not coUnit and not IsInRaid() and not self.testMode then return end
		QueueReread()
	end
	self:RegisterEvent("GROUP_ROSTER_UPDATE", roster)
	self:RegisterEvent("PLAYER_ROLES_ASSIGNED", roster)
	self:RegisterEvent("ENCOUNTER_START", roster)
	self:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player", roster)
	-- engine buttons take changes again after combat or the restriction lifts
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() if stylePending then ApplyDebuffLook() end end)
	self:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", function(self)
		if stylePending then self:After(0, ApplyDebuffLook) end
	end)
	self:Scan()
end

-- Test on your target (or you): the live bar and the real engine row, no
-- raid needed. Session only.
function M:SetTest(on)
	self.testMode = on and true or false
	if not self.running then return end
	if self.testMode then
		self:RegisterEvent("PLAYER_TARGET_CHANGED", function(self) self:Scan(true) end)
	else
		self:UnregisterEvent("PLAYER_TARGET_CHANGED")
	end
	self:Scan(true)
end

function M:OnDisable()
	self.testMode = false
	ticker = nil
	coUnit = nil
	Rewatch(nil)
	SyncDebuffs()
end

--------------------------------------------------------------------------------
-- Preview: fake icons (the engine only fills a button for a real aura), with
-- real dispel colours so the border can be judged.
--------------------------------------------------------------------------------
local previewIcons = {}
local TINTS = { { 0.8, 0, 0 }, { 0.2, 0.6, 1 }, { 0.6, 0, 1 }, { 0.6, 0.4, 0 }, { 0, 0.6, 0 } }

local function HidePreviewIcons()
	for _, b in ipairs(previewIcons) do b:Hide() end
end

local function ShowPreview()
	local db = M.db
	PaintIdentity("player")
	frame.bar:SetMinMaxValues(0, 100)
	frame.bar:SetValue(64)
	frame.time:SetText("64%")
	frame:Show()
	SizeHolder(db)
	if not db.debuffs.enabled then HidePreviewIcons() return end
	local n = math.max(1, db.debuffs.max)
	local w, h = IconSize(db)
	local sp, grow = db.debuffs.spacing, db.debuffs.grow
	local dx = (grow == "LEFT" and -(w + sp)) or (grow == "RIGHT" and (w + sp)) or 0
	local dy = (grow == "UP" and (h + sp)) or (grow == "DOWN" and -(h + sp)) or 0
	local corner = (grow == "LEFT" and "TOPRIGHT") or (grow == "UP" and "BOTTOMLEFT") or "TOPLEFT"
	local px = db.debuffs.dispelBorder and math.max(1, db.debuffs.borderSize) or 1
	for i = 1, n do
		local b = previewIcons[i]
		if not b then
			b = CreateFrame("Frame", nil, holder)
			b.bd = b:CreateTexture(nil, "BACKGROUND")
			b.bd:SetAllPoints()
			b.icon = b:CreateTexture(nil, "ARTWORK")
			b.icon:SetTexture(134400)
			b.text = b:CreateFontString(nil, "OVERLAY")
			b.stack = b:CreateFontString(nil, "OVERLAY")
			previewIcons[i] = b
		end
		b:SetSize(w, h)
		b:ClearAllPoints()
		b:SetPoint(corner, holder, corner, (i - 1) * dx, (i - 1) * dy)
		local p = Style:Pixels(b, px)
		b.icon:ClearAllPoints()
		b.icon:SetPoint("TOPLEFT", p, -p)
		b.icon:SetPoint("BOTTOMRIGHT", -p, p)
		Style:IconTexCoord(b.icon, w, h, Style:Resolve("icon", db.debuffIcon).zoom)
		local c = TINTS[((i - 1) % #TINTS) + 1]
		if db.debuffs.dispelBorder then b.bd:SetColorTexture(c[1], c[2], c[3], 1) else b.bd:SetColorTexture(0, 0, 0, 1) end
		PlaceIconText(b.text, b, db.durText, "CENTER", b.text)
		b.text:SetText(tostring(4 + i * 3))
		PlaceIconText(b.stack, b, db.stackText, "BOTTOMRIGHT", b.stack)
		b.stack:SetText(tostring(i))
		b:Show()
	end
	for i = n + 1, #previewIcons do previewIcons[i]:Hide() end
end

function M:OnRefresh()
	if not (frame or self:IsPreview()) then return end
	EnsureFrame()
	XUI.Movers:Apply(frame)
	ApplyVisual()
	ApplyDebuffLook()
	if self:IsPreview() then
		coUnit = nil
		Rewatch(nil)
		SyncDebuffs()
		ShowPreview()
		return
	end
	HidePreviewIcons()
	if self.running then
		self:Scan()
	else
		frame:Hide()
	end
end
