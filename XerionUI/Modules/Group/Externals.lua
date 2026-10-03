--------------------------------------------------------------------------------
-- Externals
-- A row of icons for the external defensives on you (Pain Suppression,
-- Ironbark, Blessing of Sacrifice ...) with their time left, and a sound when
-- one lands.
--
-- Two ways, by client:
--   * 12.0: the player's auras are readable, so Lua scans the
--     HELPFUL|EXTERNAL_DEFENSIVE filter and fills its own icons.
--   * 12.1: they are secret in keys, so an AuraContainer of the engine's fills
--     icons we build, and the sound is the engine's too
--     (C_UnitAuras.AddAuraSound, registered per spell ID).
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates
local Style = XUI.Style

local FILTER = "HELPFUL|EXTERNAL_DEFENSIVE"
local MAX_ICONS = 8
local UNIT = "player"
local PREVIEW_ICONS = { [[Interface\Icons\Spell_Holy_PainSupression]] }

local M = XUI:NewModule("Externals", {
	name = "Externals",
	desc = "Shows the external defensives on you, with their time left.",
	category = "group",
	icon = [[Interface\Icons\Spell_Holy_PainSupression]],
	order = 20,
	defaults = {
		icon = T.Icon(40),
		border = T.Border(),
		glow = T.Glow(true),
		timerText = T.Font(16, { anchor = "CENTER", x = 0, y = 0 }),
		spacing = 4,
		grow = "RIGHT",
		alert = T.Alert("SOUND", { sound = "Xerion: External" }),
		-- spells the 12.1 engine sound is registered for
		soundSpells = { 33206, 47788, 197268, 1022, 6940, 204018, 102342, 116849, 357170, 147833, 3411, 223658, 53480 },
		position = T.Position(0, 200),
	},
})

M.GROW = {
	{ value = "RIGHT", text = "Right" },
	{ value = "LEFT", text = "Left" },
	{ value = "UP", text = "Up" },
}

function M:CanLoad()
	local A = C_UnitAuras
	if not (A and A.GetAuraSlots and A.GetAuraDataBySlot and A.GetAuraDuration) then
		return false, "Not supported by this client."
	end
	return true
end

local IS_121 = XUI.IS_121
local holder
local pool = {}          -- our own icons: preview and the 12.0 path
local engineButtons = {} -- our pieces on the engine's buttons (12.1)
local container, layout

local function Holder()
	if holder then return holder end
	holder = CreateFrame("Frame", "XUI_Externals", UIParent)
	holder:SetSize(40, 40)
	holder:Hide()
	XUI.Movers:Register(holder, M, "position")
	return holder
end

local function Size(db)
	local i = Style:Resolve("icon", db.icon)
	return i.width or 40, i.height or i.width or 40
end

--------------------------------------------------------------------------------
-- Our own icons
--------------------------------------------------------------------------------
local function PoolIcon(i)
	local b = pool[i]
	if b then return b end
	b = XUI.Widgets:CreateIcon(nil, holder)
	local cd = b:GetCooldown()
	cd:SetReverse(true)
	cd:SetDrawBling(false)
	pool[i] = b
	return b
end

-- laid out again only when the settings or the number of icons changed
local layoutGen, laidGen, laidCount = 0, -1, -1

local function LayoutPool(db)
	if laidGen == layoutGen and laidCount == #pool then return end
	laidGen, laidCount = layoutGen, #pool
	local w, h = Size(db)
	local gap = db.spacing
	for i, b in ipairs(pool) do
		b:ApplyLayout(db.icon, db.border)
		b:StyleCooldownText(db.timerText)
		b:ClearAllPoints()
		local off = (i - 1)
		if db.grow == "LEFT" then
			b:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -off * (w + gap), 0)
		elseif db.grow == "UP" then
			b:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, off * (h + gap))
		else
			b:SetPoint("TOPLEFT", holder, "TOPLEFT", off * (w + gap), 0)
		end
	end
end

local function HidePool()
	for _, b in ipairs(pool) do
		b:SetGlow(nil, false)
		b:Hide()
	end
end

--------------------------------------------------------------------------------
-- 12.0: Lua reads the auras
--------------------------------------------------------------------------------
local auraCache, seen, played = {}, {}, {}

local function ScanSlots()
	return { C_UnitAuras.GetAuraSlots(UNIT, FILTER) }
end

local function SortAuras(a, b) return a.auraInstanceID < b.auraInstanceID end

function M:ScanAuras()
	wipe(auraCache)
	wipe(seen)
	local ok, slots = pcall(ScanSlots)
	if not ok or not slots then return end
	local n = 0
	for i = 2, #slots do
		local okD, data = pcall(C_UnitAuras.GetAuraDataBySlot, UNIT, slots[i])
		if okD and data and data.auraInstanceID and not seen[data.auraInstanceID] then
			seen[data.auraInstanceID] = true
			n = n + 1
			auraCache[n] = data
		end
	end
	for id in pairs(played) do
		if not seen[id] then played[id] = nil end
	end
	if n > 1 then table.sort(auraCache, SortAuras) end
	local db = self.db
	local show = math.min(n, MAX_ICONS)
	for i = 1, show do PoolIcon(i) end
	LayoutPool(db)
	for i, b in ipairs(pool) do
		local data = i <= show and auraCache[i]
		if data then
			b:SetIcon(data.icon)
			local okDur, dur = pcall(C_UnitAuras.GetAuraDuration, UNIT, data.auraInstanceID)
			if okDur and dur then
				b.cooldown:SetCooldownFromDurationObject(dur)
				b.cooldown:Show()
			else
				b.cooldown:Hide()
			end
			b:Show()
			b:SetGlow(db.glow, true)
			if not played[data.auraInstanceID] then
				played[data.auraInstanceID] = true
				XUI.Audio:Play(db.alert)
			end
		else
			b:SetGlow(nil, false)
			b:Hide()
		end
	end
	holder:SetShown(show > 0)
end

--------------------------------------------------------------------------------
-- 12.1: the engine fills icons we build
--------------------------------------------------------------------------------
local function StyleEngineButton(rec, db)
	local w, h = Size(db)
	rec.frame:SetSize(w, h)
	local inset = rec.border:Apply(db.border)
	for _, r in ipairs({ rec.icon, rec.cooldown }) do
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", inset, -inset)
		r:SetPoint("BOTTOMRIGHT", -inset, inset)
	end
	Style:IconTexCoord(rec.icon, w, h, Style:Resolve("icon", db.icon).zoom)
	Style:ApplyFont(rec.text, db.timerText)
	rec.text:ClearAllPoints()
	local a = db.timerText.anchor or "CENTER"
	rec.text:SetPoint(a, rec.textHost, a, db.timerText.x or 0, db.timerText.y or 0)
	rec.textHost:SetAlpha(db.timerText.enabled == false and 0 or 1)
	Style:SetGlow(rec.frame, db.glow, true, true)
end

-- Runs inside the engine's frame batch: nothing here may register scripts
-- or events, and an error would take the batch down, so the styling is
-- armoured.
local function InitEngineButton(b)
	local db = M.db
	pcall(b.SetMouseMotionEnabled, b, false)
	pcall(b.SetMouseClickEnabled, b, false)
	local rec = { frame = b }
	rec.border = Style:Border(b)
	rec.icon = b:CreateTexture(nil, "ARTWORK")
	b:SetIcon(rec.icon)
	local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	cd:SetReverse(true)
	cd:SetDrawEdge(false)
	cd:SetDrawBling(false)
	cd:SetHideCountdownNumbers(true)
	cd.noCooldownCount = true
	rec.cooldown = cd
	b:SetDurationCooldown(cd)
	rec.textHost = CreateFrame("Frame", nil, b)
	rec.textHost:SetAllPoints()
	rec.textHost:SetFrameLevel(cd:GetFrameLevel() + 5)
	rec.text = rec.textHost:CreateFontString(nil, "OVERLAY")
	-- a font before handing the string over: the engine writes to it at once
	Style:ApplyFont(rec.text, db.timerText)
	b:SetDurationText(rec.text, XUI.DurationTextOptions())
	engineButtons[#engineButtons + 1] = rec
	pcall(StyleEngineButton, rec, db)
end

local function EngineLayout(db)
	local w, h = Size(db)
	return { elementWidth = w, elementHeight = h, elementSpacing = db.spacing, lineSpacing = db.spacing, layoutIndex = 0 }
end

local function EnsureContainer()
	if container or not XUI.HasAuraContainers() then return end
	local ok, c = pcall(CreateFrame, "AuraContainer", "XUI_ExternalsEngine", holder, "CustomAuraContainerTemplate")
	if not ok or not c then return end
	c:SetSize(1, 1)
	local okG = pcall(c.AddAuraGroup, c, "ext", FILTER, {
		maxFrameCount = MAX_ICONS,
		layout = EngineLayout(M.db),
		initializeFrame = InitEngineButton,
	})
	if not okG then
		c:Hide()
		return
	end
	pcall(c.SetEnabled, c, false)
	pcall(c.SetUnit, c, UNIT)
	container = c
end

function M:ApplyEngine(live)
	if not container then return end
	local db = self.db
	for _, rec in ipairs(engineButtons) do pcall(StyleEngineButton, rec, db) end
	layout = EngineLayout(db)
	pcall(container.SetAuraGroupLayout, container, "ext", layout)
	local FD = AnchorUtil and AnchorUtil.FlowDirection
	local AX = AnchorUtil and AnchorUtil.FlowLayoutAxis
	container:ClearAllPoints()
	local corner, h, v, axis = "TOPLEFT", FD and FD.Right, FD and FD.Down, AX and AX.Horizontal
	if db.grow == "LEFT" then
		corner, h = "TOPRIGHT", FD and FD.Left
	elseif db.grow == "UP" then
		corner, v, axis = "BOTTOMLEFT", FD and FD.Up, AX and AX.Vertical
	end
	XUI.ContainerFlow(container, "SetFlowLayoutAnchorPoint", "SetAuraLayoutAnchorPoint", corner)
	XUI.ContainerFlow(container, "SetFlowLayoutGrowthDirection", "SetAuraLayoutGrowthDirection", h, v)
	if axis then XUI.ContainerFlow(container, "SetFlowLayoutAxis", nil, axis) end
	container:SetPoint(corner, holder, corner, 0, 0)
	pcall(container.SetEnabled, container, live and true or false)
	if live then pcall(container.UpdateAllAuras, container) end
end

--------------------------------------------------------------------------------
-- 12.1 sound: registered with the engine per spell
--------------------------------------------------------------------------------
local registered, soundSig, soundPending = {}, nil, false

local function ClearSounds()
	local remove = C_UnitAuras.RemoveAuraSound or C_UnitAuras.RemoveAuraAppliedSound
	for i = #registered, 1, -1 do
		if remove then pcall(remove, registered[i]) end
		registered[i] = nil
	end
end

function M:SyncSounds()
	local A = C_UnitAuras
	local addNew, addOld = A.AddAuraSound, A.AddAuraAppliedSound
	if not (IS_121 and (addNew or addOld)) then return end
	local db = self.db
	local path = self.running and db.alert.mode == "SOUND" and XUI.Audio:SoundFile(db.alert.sound)
	local sig = path and (path .. "|" .. (db.alert.channel or "Master") .. "|" .. table.concat(db.soundSpells, ",")) or ""
	if sig == soundSig then return end
	if InCombatLockdown() then
		soundPending = true
		return
	end
	soundPending = false
	ClearSounds()
	soundSig = sig
	if sig == "" then return end
	local added = Enum and Enum.UnitAuraSoundTrigger and Enum.UnitAuraSoundTrigger.Added or 0
	for _, id in ipairs(db.soundSpells) do
		local info = { unitToken = UNIT, spellID = id, soundFileName = path, outputChannel = db.alert.channel or "Master" }
		local ok, soundID
		if addNew then ok, soundID = pcall(addNew, added, info) else ok, soundID = pcall(addOld, info) end
		if ok and soundID then registered[#registered + 1] = soundID end
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------
local pending, fullPending = false, false

-- 12.1: the container refreshes itself, but its flow layout does not always
-- re-pack when an aura drops. Handing the group its own layout again re-packs
-- cheaply; a full re-read runs at most once a second while auras change.
local function Flush()
	pending = false
	if not M.running or M:IsPreview() then return end
	if IS_121 then
		if not container then return end
		if not (layout and pcall(container.SetAuraGroupLayout, container, "ext", layout)) then
			pcall(container.UpdateAllAuras, container)
			return
		end
		if not fullPending then
			fullPending = true
			M:After(1, function()
				fullPending = false
				if container and not M:IsPreview() then pcall(container.UpdateAllAuras, container) end
			end)
		end
	else
		M:ScanAuras()
	end
end

function M:OnEnable()
	Holder()
	if IS_121 then EnsureContainer() end
	self:RegisterUnitEvent("UNIT_AURA", UNIT, function(self, _, _, info)
		if pending or self:IsPreview() then return end
		if IS_121 and not XUI.AuraPayloadChurns(info) then return end
		pending = true
		self:After(0.05, Flush)
	end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function(self)
		if soundPending then self:SyncSounds() end
	end)
	self:SyncSounds()
end

function M:OnDisable()
	pending, fullPending = false, false
	self:SyncSounds()
	if container then pcall(container.SetEnabled, container, false) end
end

function M:OnRefresh()
	layoutGen = layoutGen + 1
	if not (holder or self:IsPreview()) then return end
	local h, db = Holder(), self.db
	XUI.Movers:Apply(h)
	local w, ht = Size(db)
	h:SetSize(w, ht)
	if self:IsPreview() then
		if container then self:ApplyEngine(false) end
		PoolIcon(1)
		LayoutPool(db)
		for i, b in ipairs(pool) do
			if i == 1 then
				b:SetIcon(PREVIEW_ICONS[1])
				b.cooldown:SetCooldown(GetTime() - 3, 12)
				b.cooldown:Show()
				b:Show()
				b:SetGlow(db.glow, true)
			else
				b:SetGlow(nil, false)
				b:Hide()
			end
		end
		h:Show()
		return
	end
	if not self.running then
		HidePool()
		if container then pcall(container.SetEnabled, container, false) end
		h:Hide()
		return
	end
	self:SyncSounds()
	if IS_121 then
		HidePool()
		h:Show()
		self:ApplyEngine(true)
	else
		self:ScanAuras()
	end
end

function M:TestAlert()
	XUI.Audio:Play(self.db.alert, nil, true)
end
