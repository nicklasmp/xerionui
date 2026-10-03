local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('Externals', hooksecurefunc, C_Timer)
local _G = _G

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local C_UnitAuras = C_UnitAuras
local GetTime = GetTime
local pairs, ipairs = pairs, ipairs
local wipe = wipe
local tsort = table.sort
local tconcat = table.concat
local mmin = math.min
local mfloor = math.floor
local secret = ns.IsSecret
local hooksecurefunc = hooksecurefunc

local EXTERNAL_FILTER = 'HELPFUL|EXTERNAL_DEFENSIVE'
local MAX_ICONS = 8
local DEFAULT_SOUND = '|cFF00FF00Kira - External|r'

local hasExt = C_UnitAuras and C_UnitAuras.GetAuraSlots and C_UnitAuras.GetAuraDataBySlot
	and C_UnitAuras.GetAuraDuration and true or false
ns.hasExternals = hasExt
if not hasExt then return end

local IS_121 = ns.IS_121

local UNIT = 'player'
local PREVIEW_ICONS = { 135936, 135966, 627485, 237542, 136120, 615341 }

local LSM = ns.LSM

local DEFAULTS = {
	enable = false,
	lock = false,
	iconSize = 40,
	borderSize = 1,
	textSize = 16,
	spacing = 4,
	grow = 'RIGHT',
	soundEnabled = true,
	sound = DEFAULT_SOUND,
	x = 0,
	y = 200,
	glow = true,
	glowType = 'pixel',
	glowColor = { 242 / 255, 242 / 255, 82 / 255, 1 },
	glowThickness = 2,
	borderColor = { 0, 0, 0, 1 },
}

local function Migrate(cfg)
	if cfg.sound == 'External' then cfg.sound = DEFAULT_SOUND end
	if cfg.grow ~= 'LEFT' and cfg.grow ~= 'RIGHT' and cfg.grow ~= 'UP' then cfg.grow = 'RIGHT' end
	local glowType = cfg.glowType
	ns.GlowMigrate(cfg, { 242 / 255, 242 / 255, 82 / 255, 1 })
	if glowType == 'autoshine' then cfg.glowType = glowType end
end

local function GetCfg() return ns.ModuleCfg('externals', DEFAULTS, Migrate) end
ns.ExtGetCfg = GetCfg

local function BorderSize(cfg)
	return mmin(8, math.max(0, mfloor((cfg.borderSize or DEFAULTS.borderSize) + 0.5)))
end

local function Inset(region, amount)
	region:ClearAllPoints()
	if amount > 0 then
		region:SetPoint('TOPLEFT', amount, -amount)
		region:SetPoint('BOTTOMRIGHT', -amount, amount)
	else
		region:SetAllPoints()
	end
end

local lastRing = 0
local function PlayExtSound()
	local cfg = GetCfg()
	if not cfg.soundEnabled then return end
	if GetTime() - lastRing < 1 then return end
	lastRing = GetTime()
	ns.PlaySoundByName(cfg.sound)
end

local function StopAutoCastShine(b)
	local glows = b.__extAutoCastGlows
	if glows and glows.StopAutoCastShine then
		pcall(glows.StopAutoCastShine, b)
		b.__extAutoCastGlows = nil
	end
	local overlay = b.__extAutoCastOverlay
	if overlay then
		if overlay.ShowAutoCastEnabled then pcall(overlay.ShowAutoCastEnabled, overlay, false) end
		overlay:Hide()
	end
end

local function StopGlow(b)
	StopAutoCastShine(b)
	ns.GlowStop(b)
end

local function StartGlow(b)
	local cfg = GetCfg()
	if cfg.glow and cfg.glowType == 'autoshine' then
		StopAutoCastShine(b)
		ns.GlowStop(b)
		local eui = _G.EllesmereUI
		local glows = eui and eui.Glows
		if glows and glows.StartAutoCastShine and glows.StopAutoCastShine then
			local c = cfg.glowColor or DEFAULTS.glowColor
			local size = cfg.iconSize or DEFAULTS.iconSize
			local ok = pcall(glows.StartAutoCastShine, b, size,
				c[1] or 1, c[2] or 1, c[3] or 1, 1, size)
			if ok then b.__extAutoCastGlows = glows return end
		end
		if ns.HasTemplate and ns.HasTemplate('AutoCastOverlayTemplate') then
			local overlay = b.__extAutoCastOverlay
			if not overlay then
				overlay = CreateFrame('Frame', nil, b, 'AutoCastOverlayTemplate')
				overlay:SetAllPoints(b)
				overlay:SetFrameLevel(b:GetFrameLevel() + 5)
				pcall(overlay.SetMouseMotionEnabled, overlay, false)
				pcall(overlay.SetMouseClickEnabled, overlay, false)
				b.__extAutoCastOverlay = overlay
			end
			overlay:Show()
			if overlay.ShowAutoCastEnabled then pcall(overlay.ShowAutoCastEnabled, overlay, true) end
			return
		end
	end
	StopAutoCastShine(b)
	local sz = cfg.iconSize or 40
	ns.GlowStart(b, sz, sz, cfg)
end

local frame
local pool = {}
local previewActive = false
local pendingUpdate = false
local soundPlayedFor = {}
local auraCache = {}
local seen = {}
local evt = CreateFrame('Frame')

local function EnforceCDFont(fs, want)
	if not (fs and fs.GetFont and fs.SetFont) then return end
	if not fs.__kiraExtHook then
		fs.__kiraExtHook = true
		hooksecurefunc(fs, 'SetFont', function(self)
			if self.__kiraExtGuard then return end
			local font, size, flags = self:GetFont()
			local w = self.__kiraExtWant or 16
			if font and size ~= w then
				self.__kiraExtGuard = true
				self:SetFont(ns.GetFont(font), w, flags)
				self.__kiraExtGuard = false
			end
		end)
	end
	fs.__kiraExtWant = want
	local font, size, flags = fs:GetFont()
	if font and size ~= want then fs:SetFont(ns.GetFont(font), want, flags) end
end

local function StyleCD(cd, textSize)
	if not cd then return end
	for _, r in ipairs({ cd:GetRegions() }) do
		if r and r.GetFont and r.SetFont then EnforceCDFont(r, textSize) end
	end
end

local function MakeButton()
	local b = CreateFrame('Frame', nil, frame)
	b.border = b:CreateTexture(nil, 'BACKGROUND')
	local bc = GetCfg().borderColor or DEFAULTS.borderColor
	b.border:SetColorTexture(bc[1] or 0, bc[2] or 0, bc[3] or 0, bc[4] or 1)
	b.border:SetAllPoints()
	b.Icon = b:CreateTexture(nil, 'ARTWORK')
	Inset(b.Icon, BorderSize(GetCfg()))
	b.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.Cooldown = CreateFrame('Cooldown', nil, b, 'CooldownFrameTemplate')
	Inset(b.Cooldown, BorderSize(GetCfg()))
	b.Cooldown:SetDrawEdge(false)
	b.Cooldown:SetDrawBling(false)
	b.Cooldown:SetReverse(true)
	b:Hide()
	pool[#pool + 1] = b
	return b
end

local function Layout()
	local cfg = GetCfg()
	local size, gap, dir = cfg.iconSize or 40, cfg.spacing or 4, cfg.grow or 'RIGHT'
	local borderSize = BorderSize(cfg)
	frame:SetSize(size, size)
	for i, b in ipairs(pool) do
		b:SetSize(size, size)
		local bc = cfg.borderColor or DEFAULTS.borderColor
		b.border:SetColorTexture(bc[1] or 0, bc[2] or 0, bc[3] or 0, bc[4] or 1)
		Inset(b.Icon, borderSize)
		Inset(b.Cooldown, borderSize)
		b:ClearAllPoints()
		local off = (i - 1) * (size + 2 + gap)
		if dir == 'LEFT' then
			b:SetPoint('CENTER', frame, 'CENTER', -off, 0)
		elseif dir == 'UP' then
			b:SetPoint('CENTER', frame, 'CENTER', 0, off)
		else
			b:SetPoint('CENTER', frame, 'CENTER', off, 0)
		end
		b.Cooldown:SetReverse(true)
		StyleCD(b.Cooldown, cfg.textSize or 16)
	end
end

local function ApplyPosition()
	if not frame then return end
	local cfg = GetCfg()
	frame:ClearAllPoints()
	frame:SetPoint('CENTER', _G.UIParent, 'CENTER', cfg.x or 0, cfg.y or 200)
end

local function FillButton(b, data)
	b.auraInstanceID = data.auraInstanceID
	b.Icon:SetTexture(data.icon)
	local okDur, dur = pcall(C_UnitAuras.GetAuraDuration, UNIT, data.auraInstanceID)
	dur = okDur and dur or nil
	if dur then
		b.Cooldown:SetCooldownFromDurationObject(dur)
		b.Cooldown:Show()
	else
		b.Cooldown:Hide()
	end
	b:Show()
	StartGlow(b)
	if not soundPlayedFor[data.auraInstanceID] then
		soundPlayedFor[data.auraInstanceID] = true
		PlayExtSound()
	end
end

local function SortAuras(a, b) return a.auraInstanceID < b.auraInstanceID end

local function UpdateAuras()
	if IS_121 then return end
	if not frame or previewActive then return end
	local cfg = GetCfg()
	if not cfg.enable then frame:Hide() return end

	wipe(auraCache)
	wipe(seen)
	local n = 0
	local okS, slots = pcall(function() return { C_UnitAuras.GetAuraSlots(UNIT, EXTERNAL_FILTER) } end)
	if not okS or not slots then return end
	for i = 2, #slots do
		local okD, data = pcall(C_UnitAuras.GetAuraDataBySlot, UNIT, slots[i])
		if okD and data and data.auraInstanceID and not seen[data.auraInstanceID] then
			seen[data.auraInstanceID] = true
			n = n + 1
			auraCache[n] = data
		end
	end

	for id in pairs(soundPlayedFor) do
		if not seen[id] then soundPlayedFor[id] = nil end
	end

	if n > 1 then tsort(auraCache, SortAuras) end
	local show = mmin(n, MAX_ICONS)
	if #pool < show then
		while #pool < show do MakeButton() end
		Layout()
	end

	for i = 1, #pool do
		if i <= show and auraCache[i] then
			FillButton(pool[i], auraCache[i])
		else
			StopGlow(pool[i])
			pool[i]:Hide()
		end
	end
	frame:SetShown(show > 0)
end

local function ShowPreview()
	local n = 1
	while #pool < n do MakeButton() end
	Layout()
	for i = 1, #pool do
		if i <= n then
			local b = pool[i]
			b.auraInstanceID = nil
			b.Icon:SetTexture(PREVIEW_ICONS[((i - 1) % #PREVIEW_ICONS) + 1])
			local duration = 8 + i * 4
			b.Cooldown:SetCooldown(GetTime() - (duration * 0.25 * i), duration)
			b.Cooldown:Show()
			b:Show()
			StartGlow(b)
		else
			StopGlow(pool[i])
			pool[i]:Hide()
		end
	end
	frame:Show()
end

local engineButtons = {}
local extContainer

local ExtDurationTextOptions = ns.DurationTextOptions

local function InitializeEngineFrame(auraFrame)
	local cfg = GetCfg()
	local sz = cfg.iconSize or 40
	auraFrame:SetSize(sz, sz)
	pcall(auraFrame.SetMouseMotionEnabled, auraFrame, false)
	pcall(auraFrame.SetMouseClickEnabled, auraFrame, false)
	local border = auraFrame:CreateTexture(nil, 'BACKGROUND')
	local bc = cfg.borderColor or DEFAULTS.borderColor
	border:SetColorTexture(bc[1] or 0, bc[2] or 0, bc[3] or 0, bc[4] or 1)
	border:SetAllPoints()
	local icon = auraFrame:CreateTexture(nil, 'ARTWORK')
	Inset(icon, BorderSize(cfg))
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	auraFrame:SetIcon(icon)
	local cd = CreateFrame('Cooldown', nil, auraFrame, 'CooldownFrameTemplate')
	Inset(cd, BorderSize(cfg))
	cd:SetReverse(true)
	cd:SetDrawEdge(false)
	cd:SetDrawBling(false)
	cd:SetHideCountdownNumbers(true)
	cd.noCooldownCount = true
	auraFrame:SetDurationCooldown(cd)
	local lvl = CreateFrame('Frame', nil, auraFrame)
	lvl:SetAllPoints()
	lvl:SetFrameLevel(cd:GetFrameLevel() + 5)
	local txt = lvl:CreateFontString(nil, 'OVERLAY')
	txt:SetPoint('CENTER')
	txt:SetFont(ns.GetFont(), cfg.textSize or 16, 'OUTLINE')
	auraFrame:SetDurationText(txt, ExtDurationTextOptions())
	StartGlow(auraFrame)
	engineButtons[#engineButtons + 1] = { frame = auraFrame, text = txt, border = border, icon = icon, cooldown = cd }
end

local function AuraLayout(cfg, index)
	local size, gap = cfg.iconSize or 40, (cfg.spacing or 4) + 2
	return { elementWidth = size, elementHeight = size, elementSpacing = gap,
		lineSpacing = gap, layoutIndex = index }
end

local function MakeExtContainer()
	local cfg = GetCfg()
	local c = CreateFrame('AuraContainer', 'XerionUIExternalsEngine', frame, 'CustomAuraContainerTemplate')
	c:SetSize(1, 1)
	c:AddAuraGroup('ext', EXTERNAL_FILTER, {
		maxFrameCount = MAX_ICONS,
		layout = AuraLayout(cfg, 0),
		initializeFrame = InitializeEngineFrame,
	})
	c:SetEnabled(false)
	c:SetUnit(UNIT)
	return c
end

local function CAnchor(c, p)
	local f = c.SetFlowLayoutAnchorPoint or c.SetAuraLayoutAnchorPoint
	if f then f(c, p) end
end
local function CGrowth(c, h, v)
	local f = c.SetFlowLayoutGrowthDirection or c.SetAuraLayoutGrowthDirection
	if f then f(c, h, v) end
end

local function StyleEngineButton(b, sz, textSize, borderColor, borderSize)
	b.frame:SetSize(sz, sz)
	b.text:SetFont(ns.GetFont(), textSize, 'OUTLINE')
	local bc = borderColor or DEFAULTS.borderColor
	b.border:SetColorTexture(bc[1] or 0, bc[2] or 0, bc[3] or 0, bc[4] or 1)
	Inset(b.icon, borderSize)
	Inset(b.cooldown, borderSize)
	StartGlow(b.frame)
end

-- the layout the 'ext' group was last given; the UNIT_AURA re-pack hands the
-- same table back (see FlushAuraUpdate)
local extLayout

local function ApplyEngine()
	if not (extContainer and frame) then return end
	local cfg = GetCfg()
	local sz = cfg.iconSize or 40
	local borderSize = BorderSize(cfg)
	frame:SetSize(sz, sz)
	for _, b in ipairs(engineButtons) do
		pcall(StyleEngineButton, b, sz, cfg.textSize or 16, cfg.borderColor, borderSize)
	end
	extLayout = AuraLayout(cfg, 0)
	pcall(extContainer.SetAuraGroupLayout, extContainer, 'ext', extLayout)
	local AU = _G.AnchorUtil
	local FD = AU.FlowDirection
	extContainer:ClearAllPoints()
	if (cfg.grow or 'RIGHT') == 'LEFT' then
		CAnchor(extContainer, 'TOPRIGHT')
		CGrowth(extContainer, FD.Left, FD.Down)
		extContainer:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 0, 0)
	elseif (cfg.grow or 'RIGHT') == 'UP' then
		CAnchor(extContainer, 'BOTTOMLEFT')
		CGrowth(extContainer, FD.Right, FD.Up)
		if AU.FlowLayoutAxis and extContainer.SetFlowLayoutAxis then
			pcall(extContainer.SetFlowLayoutAxis, extContainer, AU.FlowLayoutAxis.Vertical)
		end
		extContainer:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 0, 0)
	else
		CAnchor(extContainer, 'TOPLEFT')
		CGrowth(extContainer, FD.Right, FD.Down)
		extContainer:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
	end
	if (cfg.grow or 'RIGHT') ~= 'UP' and AU.FlowLayoutAxis and extContainer.SetFlowLayoutAxis then
		pcall(extContainer.SetFlowLayoutAxis, extContainer, AU.FlowLayoutAxis.Horizontal)
	end
	local on = (cfg.enable and not previewActive) and true or false
	extContainer:SetEnabled(on)
	if on then pcall(extContainer.UpdateAllAuras, extContainer) end
	frame:SetShown((cfg.enable or previewActive) and true or false)
end

local DEFAULT_SOUND_SPELLS = {
	33206,
	47788,
	197268,
	1022,
	6940,
	204018,
	102342,
	116849,
	357170,
	147833,
	3411,
	223658,
	53480,
}
local SOUND_SEED_VERSION = 3

function ns.ExtSoundSpells()
	local cfg = GetCfg()
	if type(cfg.soundSpells) ~= 'table' then cfg.soundSpells = {} end
	if (cfg.soundSeedVersion or 0) < SOUND_SEED_VERSION then
		cfg.soundSeedVersion = SOUND_SEED_VERSION
		local retired = { [432496] = true, [432502] = true, [443113] = true, [360827] = true }
		for i = #cfg.soundSpells, 1, -1 do
			if retired[cfg.soundSpells[i]] then table.remove(cfg.soundSpells, i) end
		end
		local have = {}
		for _, id in ipairs(cfg.soundSpells) do have[id] = true end
		for _, id in ipairs(DEFAULT_SOUND_SPELLS) do
			if not have[id] then cfg.soundSpells[#cfg.soundSpells + 1] = id end
		end
	end
	return cfg.soundSpells
end

local AddAuraSoundNew   = IS_121 and C_UnitAuras.AddAuraSound or nil
local AddAuraSoundOld   = IS_121 and C_UnitAuras.AddAuraAppliedSound or nil
local RemoveAuraSoundFn = IS_121 and (C_UnitAuras.RemoveAuraSound
	or C_UnitAuras.RemoveAuraAppliedSound) or nil
local HAS_APPLIED_SOUND = (AddAuraSoundNew or AddAuraSoundOld)
	and RemoveAuraSoundFn and true or false

local InCombatLockdown = _G.InCombatLockdown
local registeredSoundIDs = {}
local failedSoundIDs = {}
local registerPending = false
local lastSoundSig

local function ClearAuraSounds()
	for i = #registeredSoundIDs, 1, -1 do
		pcall(RemoveAuraSoundFn, registeredSoundIDs[i])
		registeredSoundIDs[i] = nil
	end
end

local function SoundSignature()
	local cfg = GetCfg()
	if not (cfg.enable and cfg.soundEnabled) then return '', nil end
	if not cfg.sound or cfg.sound == 'None' then return '', nil end
	local lib = LSM()
	local path = lib and lib.Fetch and lib:Fetch('sound', cfg.sound, true)
	if not path then return '', nil end
	local parts = { path }
	for _, id in ipairs(ns.ExtSoundSpells()) do parts[#parts + 1] = tostring(id) end
	return tconcat(parts, '|'), path
end

local function RegisterAuraSounds()
	if not HAS_APPLIED_SOUND then return end
	local sig, path = SoundSignature()
	if sig == lastSoundSig then
		registerPending = false
		return
	end
	if InCombatLockdown and InCombatLockdown() then
		registerPending = true
		return
	end
	registerPending = false
	ClearAuraSounds()
	wipe(failedSoundIDs)
	lastSoundSig = sig
	if sig == '' then return end
	local trigAdded = (_G.Enum and _G.Enum.UnitAuraSoundTrigger
		and _G.Enum.UnitAuraSoundTrigger.Added) or 0
	for _, id in ipairs(ns.ExtSoundSpells()) do
		local info = {
			unitToken = UNIT,
			spellID = id,
			soundFileName = path,
			outputChannel = 'Master',
		}
		local ok, soundID
		if AddAuraSoundNew then
			ok, soundID = pcall(AddAuraSoundNew, trigAdded, info)
		else
			ok, soundID = pcall(AddAuraSoundOld, info)
		end
		if ok and soundID then
			registeredSoundIDs[#registeredSoundIDs + 1] = soundID
		else
			failedSoundIDs[#failedSoundIDs + 1] = id
		end
	end
end

ns.ExtRebuildSoundSet = RegisterAuraSounds

SLASH_XERIONEXT1 = '/xerionext'
SlashCmdList.XERIONEXT = function()
	local cfg = GetCfg()
	local lib = LSM()
	local path = lib and lib.Fetch and lib:Fetch('sound', cfg.sound, true)
	print('|cffff7d0aKiraExt|r module enable=' .. tostring(cfg.enable)
		.. '  sound enable=' .. tostring(cfg.soundEnabled)
		.. '  sound file=' .. (path and 'OK' or 'MISSING'))
	if HAS_APPLIED_SOUND then
		print('|cffff7d0aKiraExt|r engine sound registrations: '
			.. #registeredSoundIDs .. ' of ' .. #ns.ExtSoundSpells() .. ' spell(s)'
			.. (registerPending
				and ' |cffff5555(pending - re-registers when combat ends)|r' or ''))
		if #failedSoundIDs > 0 then
			print('|cffff7d0aKiraExt|r the engine refused ' .. #failedSoundIDs
				.. ' spell ID(s): ' .. tconcat(failedSoundIDs, ', ')
				.. ' - those buffs still show an icon but stay silent. Remove them from the list or check the ID.')
		end
	elseif IS_121 then
		print('|cffff7d0aKiraExt|r AddAuraSound/AddAuraAppliedSound not available on this client'
			.. ' - and the pre-12.1 aura scan is disabled on 12.1, so no external can ring here until the API returns')
	else
		print('|cffff7d0aKiraExt|r AddAuraSound/AddAuraAppliedSound not available on this client'
			.. ' - sound rides the pre-12.1 aura-scan path')
	end
	if not path then
		print('|cffff7d0aKiraExt|r the sound "' .. tostring(cfg.sound)
			.. '" does not resolve - LibSharedMedia or the Kiratank_SharedMedia pack is not loaded. Pick any other sound in the Externals tab and it will ring.')
	elseif cfg.soundEnabled then
		ns.PlaySoundByName(cfg.sound)
		print('|cffff7d0aKiraExt|r played the configured sound just now - if you heard nothing, check the Master sound channel / game audio.')
	end
	print('|cffff7d0aKiraExt|r combat-log watching is unavailable on this client: addons may no longer register COMBAT_LOG_EVENT_UNFILTERED. Externals detects auras through the aura API instead, so use the sound test above to check the audio chain.')
end

local function EnsureFrame()
	if frame then return end
	frame = CreateFrame('Frame', 'XerionUIExternals', _G.UIParent)
	frame:SetFrameStrata('MEDIUM')
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(false)
	frame:RegisterForDrag('RightButton')
	ns.MakeDraggable(frame, GetCfg, 'x', 'y', function() ApplyPosition() end)
end

local function Apply()
	EnsureFrame()
	local cfg = GetCfg()
	if IS_121 and not extContainer and cfg.enable then extContainer = MakeExtContainer() end
	RegisterAuraSounds()
	ApplyPosition()
	if cfg.enable and not previewActive then
		evt:RegisterUnitEvent('UNIT_AURA', UNIT)
	else
		evt:UnregisterEvent('UNIT_AURA')
	end
	frame:EnableMouse(previewActive and not cfg.lock or false)
	if previewActive then
		if extContainer then ApplyEngine() end
		ShowPreview()
	elseif IS_121 then
		for _, b in ipairs(pool) do StopGlow(b) b:Hide() end
		if extContainer then ApplyEngine() else frame:Hide() end
	else
		Layout()
		UpdateAuras()
	end
end

ns.ExtApply = ns.Coalesce(function() Apply() end)

ns.ExtIsPreview = function() return previewActive end
ns.ExtSetPreview = function(state)
	previewActive = state and true or false
	Apply()
end

-- RE-PACK ON UNIT_AURA (12.1)
-- The container refreshes its own contents, but its flow layout does not
-- reliably re-pack when an aura drops, so icons would keep their old spot
-- instead of sliding toward the anchor. That used to be fixed with a full
-- UpdateAllAuras (re-read every player aura, re-bind every frame) on every
-- aura burst. The re-pack only needs the layout pass: handing the group its
-- own layout again marks the layout groups dirty (rebuild + apply), and the
-- group reads its frames through a closure, so the pass sees the icons that
-- are left. The full rebuild still runs, at most once a second while auras
-- keep changing, so the row always settles even if the layout pass alone
-- ever falls short.
local FULL_REBUILD_EVERY = 1
local fullPending = false

local function FlushFullRebuild()
	fullPending = false
	if not previewActive and extContainer and GetCfg().enable then
		pcall(extContainer.UpdateAllAuras, extContainer)
	end
end

local function FlushAuraUpdate()
	pendingUpdate = false
	if previewActive then return end
	if IS_121 then
		if not (extContainer and GetCfg().enable) then return end
		if not (extLayout and pcall(extContainer.SetAuraGroupLayout, extContainer, 'ext', extLayout)) then
			pcall(extContainer.UpdateAllAuras, extContainer)
			return
		end
		if not fullPending then
			fullPending = true
			C_Timer.After(FULL_REBUILD_EVERY, FlushFullRebuild)
		end
	else
		UpdateAuras()
	end
end

evt:RegisterEvent('PLAYER_ENTERING_WORLD')
evt:RegisterEvent('PLAYER_REGEN_ENABLED')
evt:SetScript('OnEvent', function(_, event, _, updateInfo)
	if event == 'PLAYER_ENTERING_WORLD' then
		C_Timer.After(0.5, Apply)
		return
	end
	if event == 'PLAYER_REGEN_ENABLED' then
		if registerPending then RegisterAuraSounds() end
		return
	end
	if previewActive or pendingUpdate then return end
	-- 12.1: only an aura added or dropped moves the row; a refresh or a stack
	-- change does not (a secret payload counts as a change). The pre-12.1
	-- path redraws its own buttons, so it keeps every event.
	if IS_121 and not ns.AuraPayloadChurns(updateInfo) then return end
	pendingUpdate = true
	C_Timer.After(0.05, FlushAuraUpdate)
end)
