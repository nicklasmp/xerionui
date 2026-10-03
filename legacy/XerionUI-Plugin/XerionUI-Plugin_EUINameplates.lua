local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('EUINameplates', hooksecurefunc, C_Timer)
local _G = _G

local hooksecurefunc = hooksecurefunc
local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame
local UIParent = UIParent
local C_Timer = C_Timer
local GetTime = GetTime
local pairs, next = pairs, next
local type, pcall = type, pcall
local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit
local UnitCanAttack = UnitCanAttack
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local AbbreviateNumbers = AbbreviateNumbers
local secret = ns.IsSecret

local ARROW_PATH = 'Interface\\AddOns\\XerionUI-Plugin\\Media\\EthricArrow10.tga'

local ENP

ns.hasEUINP = false

local HEALTH_DEFAULTS = { enable = false }
local NAME_DEFAULTS   = { enable = false, alpha = 50 }
local ARROW_DEFAULTS  = { enable = false, size = 24, x = -24, y = 0 }
local SHIELD_DEFAULTS = { enable = false, enemyOnly = true, cn = false, size = 11, offX = 0, offY = 0, color = { 1, 0.82, 0.25, 1 } }

local function GetHealthCfg() return ns.ModuleCfg('euiNpHealth', HEALTH_DEFAULTS) end
local function GetNameCfg()   return ns.ModuleCfg('euiNpName',   NAME_DEFAULTS) end
local function GetArrowCfg()  return ns.ModuleCfg('euiNpArrow',  ARROW_DEFAULTS) end
-- The draining-bar mode was removed the day it was built (2026-09-21), and the
-- free position (anchor dropdown, X/Y offsets) gave way to pinning the text
-- after EllesmereUI's health text (2026-09-23); their keys are cleared so saved
-- tables and exports stop carrying them. The offsets that came back afterwards
-- nudge the pinned spot, so they live under new keys (offX/offY): an old x/y
-- was measured from a different anchor and must not return with a profile.
local function MigrateShield(cfg)
	cfg.display, cfg.barText, cfg.barMatch, cfg.barScale = nil, nil, nil, nil
	cfg.barWidth, cfg.barHeight, cfg.barColor = nil, nil, nil
	cfg.anchor, cfg.x, cfg.y = nil, nil, nil
end
local function GetShieldCfg() return ns.ModuleCfg('euiNpShield', SHIELD_DEFAULTS, MigrateShield) end

ns.EUINPGetHealthCfg = GetHealthCfg
ns.EUINPGetNameCfg   = GetNameCfg
ns.EUINPGetArrowCfg  = GetArrowCfg
ns.EUINPGetShieldCfg = GetShieldCfg

local DISPEL_GLOW_DEFAULTS = { always = true }
local function GetDispelGlowCfg() return ns.ModuleCfg('euiNpDispelGlow', DISPEL_GLOW_DEFAULTS) end
ns.EUINPGetDispelGlowCfg = GetDispelGlowCfg

-- EllesmereUI's dispel glow is gated by the character's offensive purge /
-- soothe capability. When enabled, report both aura types as supported so
-- its native engine-filtered groups still identify Magic and Enrage effects,
-- including in restricted content where per-aura inspection is unavailable.
local function ApplyDispelGlowOverride()
	local np = _G.EllesmereNameplates_NS
	if not np then return false end
	if not np.__xerionDispelGlowHook and type(np.GetOffensiveDispelTypes) == 'function' then
		local original = np.GetOffensiveDispelTypes
		np.GetOffensiveDispelTypes = function(...)
			if GetDispelGlowCfg().always then return true, true end
			return original(...)
		end
		np.__xerionDispelGlowHook = true
	end
	if type(np.NPC_ReloadAll) == 'function' then
		pcall(np.NPC_ReloadAll)
	elseif type(np.RefreshAllSettings) == 'function' then
		pcall(np.RefreshAllSettings)
	end
	return np.__xerionDispelGlowHook and true or false
end
ns.EUINPApplyDispelGlowOverride = ApplyDispelGlowOverride

-- Health text brackets, enemy name fading and target arrows were removed
-- from the plugin's Nameplates page. Clear their old saved switches so an
-- earlier profile cannot keep any of those tweaks active.
GetHealthCfg().enable = false
GetNameCfg().enable = false
GetArrowCfg().enable = false

local refreshPending = false
local refreshFrame = CreateFrame('Frame')
refreshFrame:SetScript('OnEvent', function(self)
	self:UnregisterEvent('PLAYER_REGEN_ENABLED')
	refreshPending = false
	local reload = _G._ENP_RefreshAllSettings
	if type(reload) == 'function' then pcall(reload) end
end)

local function RefreshNPGlobal()
	local reload = _G._ENP_RefreshAllSettings
	if type(reload) ~= 'function' then return end
	if InCombatLockdown() then
		if not refreshPending then
			refreshPending = true
			refreshFrame:RegisterEvent('PLAYER_REGEN_ENABLED')
		end
	else
		pcall(reload)
	end
end

local function RepaintHealth(plate)
	if not (plate and plate.unit and type(plate.UpdateHealth) == 'function') then return false end
	pcall(plate.UpdateHealth, plate)
	return true
end

-- Brackets on/off, read by the health-text hook on every paint of every
-- plate (in a key EUI repaints on every health event). The hook only goes on
-- while brackets are on; RefreshNP (ApplyAllSettings and the options toggle)
-- keeps the flag current and hooks the plates already up when they turn on.
local healthOn = false
local HookHealthText

local function RefreshNP()
	healthOn = GetHealthCfg().enable and true or false
	if not (ENP and ENP.plates) then return end
	local asked = false
	for _, plate in pairs(ENP.plates) do
		if healthOn then HookHealthText(plate) end
		if RepaintHealth(plate) then asked = true end
	end
	if not asked and next(ENP.plates) then RefreshNPGlobal() end
end
ns.EUINPRefresh = RefreshNP

local function NameAlpha()
	local cfg = GetNameCfg()
	if cfg.enable then return (cfg.alpha or 50) / 100 end
	return 1
end

local function ApplyNameAlphaToPlate(plate)
	if plate and plate.name and plate.name.SetAlpha then
		plate.name:SetAlpha(NameAlpha())
	end
end

local function ApplyNameAlphaAll()
	if not (ENP and ENP.plates) then return end
	for _, plate in pairs(ENP.plates) do
		ApplyNameAlphaToPlate(plate)
	end
end
ns.EUINPApplyNameAlpha = ApplyNameAlphaAll

local COMBO_FORMATS = { ['%s | %s'] = true, ['%s - %s'] = true }
local BRACKET_FORMAT = '%s (%s)'

-- The format is swapped BEFORE the text is drawn, not redrawn after it: a
-- post-hook painted every health update twice (EUI's format, then ours), and
-- in a key that is every health event of every plate. hpText is EUI's own
-- font string, so wrapping its method on the instance is what hooksecurefunc
-- did anyway. Only EUI's literal format is looked at; the values (secret in
-- a key) pass through untouched to the C-side formatter.
HookHealthText = function(plate)
	local fs = plate and plate.hpText
	if not (fs and fs.SetFormattedText) or fs.__kiraNPHealthHook then return false end
	fs.__kiraNPHealthHook = true
	local orig = fs.SetFormattedText
	fs.SetFormattedText = function(self, fmt, ...)
		if healthOn and type(fmt) == 'string' and not secret(fmt) and COMBO_FORMATS[fmt] then
			fmt = BRACKET_FORMAT
		end
		return orig(self, fmt, ...)
	end
	return true
end

local function SameUnit(a, b)
	local same = UnitIsUnit(a, b)
	if secret(same) then return nil end
	return same and true or false
end

local function FindPlate(unit)
	local np = ENP or _G.EllesmereNameplates_NS
	if not (np and np.plates) then return nil end
	local cached = (unit == 'focus' and np._cachedFocusPlate) or (unit == 'target' and np._cachedTargetPlate)
	if cached and cached.unit and SameUnit(cached.unit, unit) ~= false then return cached end
	for _, p in pairs(np.plates) do
		if p.unit and SameUnit(p.unit, unit) then return p end
	end
end
ns.EUINPFindPlate = FindPlate

local arrowFrame, leftTex, rightTex

local function EnsureArrows()
	if arrowFrame then return end
	arrowFrame = CreateFrame('Frame', nil, _G.UIParent)
	arrowFrame:SetSize(1, 1)
	arrowFrame:Hide()
	leftTex = arrowFrame:CreateTexture(nil, 'OVERLAY')
	leftTex:SetTexture(ARROW_PATH)
	leftTex:SetTexCoord(0, 1, 0, 1)
	rightTex = arrowFrame:CreateTexture(nil, 'OVERLAY')
	rightTex:SetTexture(ARROW_PATH)
	rightTex:SetTexCoord(1, 0, 0, 1)
end

-- What the last pass that showed the arrows hung them on and with which
-- settings; host is nil while they are hidden.
local arrowAt = {}

local function AttachArrows()
	if not ENP then return end
	EnsureArrows()
	-- Set again only once the pass below has run to the end.
	arrowAt.host = nil
	local cfg = GetArrowCfg()
	if not cfg.enable then arrowFrame:Hide() return end
	local plate = UnitExists('target') and FindPlate('target')
	if not (plate and plate.health) then arrowFrame:Hide() return end

	local base = plate.health:GetFrameLevel() or 1
	arrowFrame:SetParent(plate)
	arrowFrame:ClearAllPoints()
	arrowFrame:SetAllPoints(plate.health)
	arrowFrame:SetFrameLevel(base + 6)

	local sz = cfg.size or 16
	local half = sz / 2
	local gap = cfg.x or 2
	local y = cfg.y or 0
	leftTex:SetWidth(sz)
	leftTex:ClearAllPoints()
	leftTex:SetPoint('TOP',    plate.health, 'LEFT',  -(gap + half), y + half)
	leftTex:SetPoint('BOTTOM', plate.health, 'LEFT',  -(gap + half), y - half)
	rightTex:SetWidth(sz)
	rightTex:ClearAllPoints()
	rightTex:SetPoint('TOP',    plate.health, 'RIGHT',  gap + half,   y + half)
	rightTex:SetPoint('BOTTOM', plate.health, 'RIGHT',  gap + half,   y - half)
	arrowFrame:Show()
	arrowAt.host, arrowAt.health, arrowAt.base = plate, plate.health, base
	arrowAt.size, arrowAt.gap, arrowAt.y = cfg.size, cfg.x, cfg.y
end

-- True when AttachArrows would set every piece back to what it already is:
-- EllesmereUI's cached target plate is still the one the arrows hang on and
-- still the target (so FindPlate answers it on its first line), the same
-- health bar at the same level, our frame at the level it was given, and the
-- same settings.
local function ArrowsCurrent()
	local host = arrowAt.host
	if not (host and ENP and ENP.plates and ENP._cachedTargetPlate == host and host.unit) then return false end
	if host.health ~= arrowAt.health or SameUnit(host.unit, 'target') ~= true then return false end
	local cfg = GetArrowCfg()
	if not cfg.enable or cfg.size ~= arrowAt.size or cfg.x ~= arrowAt.gap or cfg.y ~= arrowAt.y then return false end
	return (host.health:GetFrameLevel() or 1) == arrowAt.base and arrowFrame:GetFrameLevel() == arrowAt.base + 6
end

-- SHIELD TEXT
--
-- WHY THIS EXISTS
-- EllesmereUI draws a mob's absorb as a segment on the health bar but never
-- says how big it is, and the "Absorb Short" text its unit frames offer has no
-- nameplate twin. In a key the question is "how much shield is left to burn",
-- so this prints the amount as a number next to the plate.
--
-- HOW IT STAYS LEGAL IN A KEY
-- In restricted content UnitGetTotalAbsorbs hands back a SECRET number. It is
-- never compared, never divided and never formatted in Lua here: it goes
-- straight into AbbreviateNumbers, FontString:SetText and StatusBar:SetValue,
-- all three documented SecretArguments = 'AllowedWhenTainted'.
--
-- That is also why there is no "percent of the full shield" mode. A percentage
-- is current / initial, Lua may not divide a secret, and the client ships
-- UnitHealthPercent and UnitPowerPercent but no absorb twin (the heal
-- prediction calculator only evaluates HEALTH percentages against a curve).
--
-- HIDING AT ZERO
-- "Is there a shield at all" is a comparison too, so the text cannot be blanked
-- from Lua. Same trick EllesmereUI's unit frames use: an invisible StatusBar
-- with a 0..1 range is fed the raw absorb, so its fill is full width with any
-- shield and zero width with none; a clipping frame is pinned to that fill and
-- owns the FontString. No shield, no fill, nothing left to draw the text in.
--
-- WHERE IT SITS
-- Right after EllesmereUI's own health text - "5.2M (100%)" becomes
-- "5.2M (100%) 5.5M" - in whichever slot that text lives, instead of a free
-- position with offsets. EllesmereUI anchors its health text by one point and
-- leaves its width on auto, so the FontString ends where the text ends and the
-- client keeps the gap as the digits change (a "Width %" below 100 in
-- EllesmereUI boxes it, and the gap then runs to the box edge instead). In a
-- key that text is secret, which makes our frames' geometry secret as well
-- (SecretWhenAnchoringSecret): harmless, nothing here reads it back, and
-- EllesmereUI hangs its own top aura row off the same FontString. With no
-- health text on the plate the number goes to the right of the bar. Offset
-- X/Y nudge it from that spot; the anchor itself stays pinned.
local SHIELD_GAP = 3

-- Hide/Show are only ever called with plain arguments, but a secret answer
-- must not reach the boolean test.
local function Showing(r)
	if not r then return false end
	local shown = r:IsShown()
	return not secret(shown) and shown and true or false
end

-- The percent text first: that is the "(100%)" the number is meant to follow.
local function ShieldAnchor(plate)
	if Showing(plate.hpText) then return plate.hpText end
	if Showing(plate.hpNumber) then return plate.hpNumber end
	return plate.health
end

-- The anchor's own text host, so the number shares its strata and level (the
-- top slot and every non-MEDIUM slot get their own host frame in EllesmereUI).
local function ShieldHost(plate, anchor)
	local host = anchor ~= plate.health and anchor:GetParent()
	return host or plate.healthTextFrame or plate
end

-- CN STYLE (30万 instead of 300K)
-- Chinese groups big numbers by ten-thousands (万) and hundred-millions (亿).
-- The client's abbreviator takes its own breakpoint table, and the table is
-- the whole trick: the call still does the dividing in C, so it stays
-- 'AllowedWhenTainted' with a secret amount exactly like the plain call.
-- Largest first, as the API asks; each unit comes as a pair so a small
-- multiple keeps one decimal (1.2万) and a larger one drops it (30万).
local CN_BREAKPOINTS = {
	{ breakpoint = 1e9, abbreviation = '亿', significandDivisor = 1e8, fractionDivisor = 1,  abbreviationIsGlobal = false },
	{ breakpoint = 1e8, abbreviation = '亿', significandDivisor = 1e7, fractionDivisor = 10, abbreviationIsGlobal = false },
	{ breakpoint = 1e5, abbreviation = '万', significandDivisor = 1e4, fractionDivisor = 1,  abbreviationIsGlobal = false },
	{ breakpoint = 1e4, abbreviation = '万', significandDivisor = 1e3, fractionDivisor = 10, abbreviationIsGlobal = false },
	{ breakpoint = 1,   abbreviation = '',   significandDivisor = 1,   fractionDivisor = 1,  abbreviationIsGlobal = false },
}

-- Raw breakpoint data is validated and turned into a config on every call; a
-- plate's shield text changes on every absorb event, so the config is built
-- once, the way EllesmereUI_NumberFormat.lua does for its own CJK table. The
-- raw table stays as the fallback should the builder ever refuse it.
local cnAbbrev
local function CNAbbrev()
	if not cnAbbrev then
		local ok, c = pcall(_G.CreateAbbreviateConfig, CN_BREAKPOINTS)
		cnAbbrev = (ok and c) and { config = c } or { breakpointData = CN_BREAKPOINTS }
	end
	return cnAbbrev
end

-- A font file only draws the glyphs it carries, and a missing one is simply
-- not drawn: GothamNarrowBlack, Friz and most number fonts have no 万, so "30万"
-- would come out as "30". Measure the glyph once per font on a throwaway
-- FontString; if it has no width, the text switches to the client's own
-- Chinese font, which every client ships and which has Latin digits too.
local CJK_FONT = 'Fonts\\ARHei.ttf'
local glyphProbe
local glyphOk = {}
local function CNFont(path)
	if glyphOk[path] == nil then
		if not glyphProbe then
			glyphProbe = UIParent:CreateFontString(nil, 'BACKGROUND')
			glyphProbe:SetPoint('TOPLEFT', UIParent, 'BOTTOMRIGHT', 100, -100)
			glyphProbe:SetAlpha(0)
		end
		local w = 0
		if glyphProbe:SetFont(path, 14, '') then
			glyphProbe:SetText('万')
			w = glyphProbe:GetStringWidth() or 0
			glyphProbe:SetText('')
		end
		glyphOk[path] = w > 1
	end
	return glyphOk[path] and path or CJK_FONT
end

-- The preview runs through the same abbreviator as a live shield (5.5M, or
-- 550万 in CN style); the gate's 0..1 range caps it at "shown".
local SHIELD_PREVIEW_AMOUNT = 5500000
local shieldPreview = false
-- Bumped by ApplyShield. The layout depends on the settings alone, so a plate
-- whose widget carries the current number only needs painting - a new plate is
-- stamped twice (SetUnit hook, then NAME_PLATE_UNIT_ADDED).
local shieldGen = 0

local function BuildShield(plate)
	local w = plate.__kiraShield
	if w then return w end
	-- EllesmereUI's own text tier (MEDIUM strata, level 900): anything parented
	-- lower renders under the aura icons.
	local host = plate.healthTextFrame or plate
	w = {}
	w.gate = CreateFrame('StatusBar', nil, host)
	w.gate:SetStatusBarTexture('Interface\\Buttons\\WHITE8X8')
	w.gate:SetStatusBarColor(1, 1, 1, 0) -- geometry only, never drawn
	w.gate:SetMinMaxValues(0, 1)
	w.gate:SetValue(0)
	w.clip = CreateFrame('Frame', nil, host)
	w.clip:SetClipsChildren(true)
	w.clip:SetPoint('TOPLEFT', w.gate, 'TOPLEFT', 0, 0)
	w.clip:SetPoint('BOTTOMRIGHT', w.gate:GetStatusBarTexture(), 'BOTTOMRIGHT', 0, 0)
	w.fs = w.clip:CreateFontString(nil, 'OVERLAY')
	plate.__kiraShield = w
	return w
end

local function LayoutShield(w, cfg, anchor, host)
	local size = cfg.size or 11
	if w.gate:GetParent() ~= host then
		w.gate:SetParent(host)
		w.clip:SetParent(host)
	end
	-- A fixed box, not the text's own rect: the text is secret in a key, and the
	-- gate is all-or-nothing anyway, so it only has to be roomy enough.
	w.gate:ClearAllPoints()
	w.gate:SetSize(size * 6, size + 6)
	w.gate:SetPoint('LEFT', anchor, 'RIGHT', SHIELD_GAP + (cfg.offX or 0), cfg.offY or 0)
	local font = ns.GetFont()
	if cfg.cn then font = CNFont(font) end
	w.fs:SetFont(font, size, 'OUTLINE')
	w.fs:ClearAllPoints()
	w.fs:SetPoint('LEFT', w.gate, 'LEFT', 0, 0)
	w.fs:SetJustifyH('LEFT')
	local c = cfg.color or SHIELD_DEFAULTS.color
	w.fs:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, 1)
end

-- Unreadable means "allow", as everywhere else in the plugin.
local function ShieldWanted(unit, cfg)
	if not cfg.enemyOnly then return true end
	local ok, can = pcall(UnitCanAttack, 'player', unit)
	if not ok or secret(can) then return true end
	return can and true or false
end

local function PushShield(w, amt, cn)
	w.gate:SetValue(amt)
	w.fs:SetText(AbbreviateNumbers(amt, cn and CNAbbrev() or nil))
end

local function PaintShield(plate)
	local w = plate.__kiraShield
	if not w then return end
	local cfg = GetShieldCfg()
	local unit = plate.unit
	local amt = 0
	if shieldPreview then
		amt = SHIELD_PREVIEW_AMOUNT
	elseif unit and ShieldWanted(unit, cfg) then
		local ok, v = pcall(UnitGetTotalAbsorbs, unit)
		if ok and (secret(v) or type(v) == 'number') then amt = v end
	end
	if not pcall(PushShield, w, amt, cfg.cn) then pcall(PushShield, w, 0) end
end

-- ONE PAINT PER PLATE THAT COMES UP
-- A plate that comes up is stamped twice in the same frame: the SetUnit hook
-- (from = 'unit') inside EllesmereUI's own NAME_PLATE_UNIT_ADDED, then our
-- handler for the same event (from = 'added'). The hook's paint has already
-- read this unit's absorb, and any change after it fires
-- UNIT_ABSORB_AMOUNT_CHANGED, which the watcher below paints on its own; so the
-- 'added' pass skips its paint when the hook painted the same unit this frame
-- (GetTime is fixed for a frame). The layout still runs on both. A plate
-- whose SetUnit came earlier, later or never has no fresh mark and is painted
-- as before; a settings change (from = nil) always paints.
local function ApplyShieldToPlate(plate, from)
	if not (plate and plate.health) then return end
	local cfg = GetShieldCfg()
	if not cfg.enable then
		local w = plate.__kiraShield
		if w then w.gate:Hide() w.clip:Hide() end
		return
	end
	local w = BuildShield(plate)
	-- EllesmereUI moves and re-hosts its health text on every settings change,
	-- and this runs right after it (SetUnit and RefreshAllSettings hooks).
	local anchor = ShieldAnchor(plate)
	local host = ShieldHost(plate, anchor)
	if w.gen ~= shieldGen or w.anchor ~= anchor or w.host ~= host then
		w.gen, w.anchor, w.host = shieldGen, anchor, host
		LayoutShield(w, cfg, anchor, host)
	end
	w.gate:Show()
	w.clip:Show()
	if from == 'added' then
		local unit = plate.unit
		local fresh = unit and w.hookUnit == unit and w.hookAt == GetTime()
		w.hookUnit = nil
		if fresh then return end
	elseif from == 'unit' then
		w.hookUnit, w.hookAt = plate.unit, GetTime()
	end
	PaintShield(plate)
end

-- One watcher for every plate instead of a RegisterUnitEvent per plate. The
-- event also fires for the player and the party, and a plate's unit is always
-- a nameplate token, so everything else is turned away before any lookup.
local shieldWatcher = CreateFrame('Frame')
shieldWatcher:SetScript('OnEvent', function(_, _, unit)
	local plates = ENP and ENP.plates
	if not (plates and unit) or unit:sub(1, 9) ~= 'nameplate' then return end
	local plate = plates[unit]
	if plate and plate.unit == unit then PaintShield(plate) return end
	-- EllesmereUI re-points a plate at a new token without an add/remove
	-- cycle, which leaves the table key behind the plate's real unit.
	for _, p in pairs(plates) do
		if p.unit == unit then PaintShield(p) return end
	end
end)

local shieldWatching = false
local function SyncShieldWatcher()
	local want = (ENP and GetShieldCfg().enable) and true or false
	if want == shieldWatching then return end
	shieldWatching = want
	if want then
		shieldWatcher:RegisterEvent('UNIT_ABSORB_AMOUNT_CHANGED')
	else
		shieldWatcher:UnregisterAllEvents()
	end
end

local function ApplyShield()
	shieldGen = shieldGen + 1
	if not GetShieldCfg().enable then shieldPreview = false end
	SyncShieldWatcher()
	if not (ENP and ENP.plates) then return end
	for _, plate in pairs(ENP.plates) do
		ApplyShieldToPlate(plate)
	end
end
ns.EUINPApplyShield = ApplyShield
ns.EUINPShieldIsPreview = function() return shieldPreview end
ns.EUINPShieldSetPreview = function(on)
	shieldPreview = (on and GetShieldCfg().enable) and true or false
	ApplyShield()
end

-- from: 'added' for NAME_PLATE_UNIT_ADDED, nil for a pass over every plate.
local function StampPlate(plate, from)
	if not plate then return end
	ApplyNameAlphaToPlate(plate)
	ApplyShieldToPlate(plate, from)
	if healthOn and HookHealthText(plate) then
		RepaintHealth(plate)
	end

	if not plate.__kiraNPUnitHook and type(plate.SetUnit) == 'function' then
		plate.__kiraNPUnitHook = true
		hooksecurefunc(plate, 'SetUnit', function(self)
			ApplyNameAlphaToPlate(self)
			ApplyShieldToPlate(self, 'unit')
			if healthOn and HookHealthText(self) then RepaintHealth(self) end
		end)
	end
end

local function StampAllPlates()
	if not (ENP and ENP.plates) then return end
	for _, plate in pairs(ENP.plates) do
		StampPlate(plate)
	end
	AttachArrows()
end

local function OnPlateAdded(unit)
	local plate = ENP and ENP.plates and ENP.plates[unit]
	if not plate then return false end
	StampPlate(plate, 'added')
	return true
end

local stamper = CreateFrame('Frame')
stamper:SetScript('OnEvent', function(_, _, unit)
	if not OnPlateAdded(unit) then
		C_Timer.After(0, function() OnPlateAdded(unit) end)
	end
end)

local QueueArrowPass = ns.Coalesce(function() AttachArrows() end)

-- Two passes per event: one now, for the frame the event lands in, and one on
-- the next frame, for whatever EllesmereUI finishes after our handler (the
-- order handlers run in is not ours to pick). A pull adds and removes 10-30
-- plates, and for all but the target's the pass now would put the arrows back
-- exactly where they are; ArrowsCurrent proves that with a few reads, so only
-- then is it skipped. The next-frame pass always runs in full.
local arrowWatcher = CreateFrame('Frame')
arrowWatcher:SetScript('OnEvent', function(_, event)
	if event == 'PLAYER_TARGET_CHANGED' or not ArrowsCurrent() then AttachArrows() end
	QueueArrowPass()
end)

local arrowsWatching = false
local function SyncArrowWatcher()
	local want = (ENP and GetArrowCfg().enable) and true or false
	if want == arrowsWatching then return end
	arrowsWatching = want
	if want then
		arrowWatcher:RegisterEvent('PLAYER_TARGET_CHANGED')
		arrowWatcher:RegisterEvent('NAME_PLATE_UNIT_ADDED')
		arrowWatcher:RegisterEvent('NAME_PLATE_UNIT_REMOVED')
	else
		arrowWatcher:UnregisterAllEvents()
	end
end

local function ApplyArrows()
	SyncArrowWatcher()
	AttachArrows()
end
ns.EUINPApplyArrow = ApplyArrows

_G.SLASH_XERIONNP1 = '/xerionnp'
_G.SlashCmdList.XERIONNP = function()
	local Msg = ns.Msg
	if not ENP then
		Msg('Nameplates: NOT active - EllesmereUI Nameplates namespace not found.')
		return
	end
	local n = 0
	if ENP.plates then for _ in pairs(ENP.plates) do n = n + 1 end end
	Msg(('Nameplates: active, %d plates | brackets %s | name alpha %s | arrows %s (watcher %s)'):format(
		n, tostring(GetHealthCfg().enable), tostring(GetNameCfg().enable), tostring(GetArrowCfg().enable),
		arrowsWatching and 'on' or 'off'))
	local hasTarget = UnitExists('target') and true or false
	local plate = hasTarget and FindPlate('target') or nil
	Msg('target plate: ' .. (plate and 'found' or (hasTarget and 'NONE for this target' or 'no target'))
		.. ' | EllesmereUI cache: ' .. (ENP._cachedTargetPlate and 'set' or 'empty'))
	local sw = plate and plate.__kiraShield
	Msg(('shield text: %s (CN %s, watcher %s, preview %s) | target plate widget: %s, after %s'):format(
		tostring(GetShieldCfg().enable), tostring(GetShieldCfg().cn), shieldWatching and 'on' or 'off', tostring(shieldPreview),
		sw and (sw.clip:IsShown() and 'built, shown' or 'built, hidden') or 'none',
		not sw and '-' or (sw.anchor == plate.hpText and 'health text')
			or (sw.anchor == plate.hpNumber and 'health number') or 'the bar'))
	if hasTarget then
		local ok, v = pcall(UnitGetTotalAbsorbs, 'target')
		Msg('target absorb: ' .. ((not ok and 'read failed') or (secret(v) and 'secret (shown as text only)') or tostring(v)))
	end
	if not arrowFrame then
		Msg('arrow frame: not created yet')
	else
		Msg('arrow frame: ' .. (arrowFrame:IsShown() and 'shown' or 'hidden')
			.. ', parented to the target plate: ' .. tostring(plate ~= nil and arrowFrame:GetParent() == plate))
	end
end

local function Activate()
	if ENP then return true end

	local np  = _G.EllesmereNameplates_NS
	local eui = _G.EllesmereUI
	if not (np and eui) then return false end

	ENP = np
	ns.hasEUINP = true
	ApplyDispelGlowOverride()

	stamper:RegisterEvent('NAME_PLATE_UNIT_ADDED')
	SyncArrowWatcher()
	SyncShieldWatcher()

	if type(np.RefreshAllSettings) == 'function' then
		hooksecurefunc(np, 'RefreshAllSettings', function()
			StampAllPlates()
			C_Timer.After(0, StampAllPlates)
		end)
	end

	StampAllPlates()
	C_Timer.After(0, StampAllPlates)
	return true
end

local loader = CreateFrame('Frame')
loader:SetScript('OnEvent', function(self, event, arg1)
	if event == 'ADDON_LOADED' then
		if arg1 ~= 'EllesmereUI' and arg1 ~= 'EllesmereUINameplates' then return end
		if Activate() then self:UnregisterEvent('ADDON_LOADED') end
		return
	end

	if Activate() then self:UnregisterEvent('ADDON_LOADED') end
	ApplyDispelGlowOverride()
	SyncArrowWatcher()
	SyncShieldWatcher()
	StampAllPlates()
	C_Timer.After(0, StampAllPlates)
end)
loader:RegisterEvent('ADDON_LOADED')
loader:RegisterEvent('PLAYER_LOGIN')
loader:RegisterEvent('PLAYER_ENTERING_WORLD')

if Activate() then loader:UnregisterEvent('ADDON_LOADED') end
