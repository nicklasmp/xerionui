local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('PaladinAura', hooksecurefunc, C_Timer)
local _G = _G

-- WHAT IT DOES
-- A paladin aura reminder for every spec, one icon at a time:
--   * Crusader Aura on, mounted or not - the Devotion Aura icon with
--     "Devotion Aura missing", so the switch back is not forgotten when the
--     ride ends (the user asked for it on the mount too, 2026-09-29).
--   * Mounted (any mount) and Crusader Aura NOT on - the Crusader Aura icon,
--     a hint to switch to it for the faster mount speed.
-- Anything else (Devotion or another aura on while on foot) shows nothing.
-- "Only in Mythic+" (on by default, asked for the same day) keeps it to a
-- Mythic dungeon: the key running, or the dungeon on Mythic before the key
-- goes in - walking in with Crusader still on is the moment it is for. Most
-- dungeons allow no mount, so there it is the Devotion line that fires.
-- Icon size, text size, colour and placement and the position are the
-- player's; right-drag moves it while previewing.
--
-- WHERE THE ANSWERS COME FROM
-- Not from the buff: Devotion Aura is ContextuallySecret on 12.x (EllesmereUI's
-- Buff Reminders says so and gives up on it in combat and PvP). Paladin auras
-- are shapeshift forms, so the active one is read off the stance bar -
-- GetShapeshiftFormInfo(i) gives each slot's spell ID and whether it is on,
-- the same read EllesmereUI falls back to in combat and in PvP. The bar also
-- says which auras the paladin has at all: a reminder for an aura that is not
-- on it is never shown. Mounted is IsMounted() (no secret annotation; EUI
-- reads it in combat), and a flight path counts as neither: nothing can be
-- cast there. Should any of these come back secret, nothing is shown - a
-- warning that fails open would shout at a paladin who did nothing wrong.
-- The Mythic+ gate is the other way round: C_ChallengeMode and the instance's
-- difficulty (8 keystone, 23 Mythic; DifficultyUtil.ID) read unclear count as
-- "in a key", so a gate the client will not answer never hides the reminder.
--
-- COST
-- Nothing listens unless the box is ticked on a paladin. Every event only asks
-- for one refresh on the next frame; the bar has three or four slots. The icon
-- never takes the mouse outside preview, so it cannot block a click.

local CreateFrame = CreateFrame
local UIParent = UIParent
local IsMounted = IsMounted
local UnitOnTaxi = UnitOnTaxi
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local GetNumShapeshiftForms = GetNumShapeshiftForms
local GetShapeshiftFormInfo = GetShapeshiftFormInfo
local GetInstanceInfo = GetInstanceInfo
local ipairs, pcall, tostring, print = ipairs, pcall, tostring, print
local secret = ns.IsSecret

ns.hasPaladinAura = true

local DEVOTION = 465
local CRUSADER = 32223

local TEXTS = {
	[DEVOTION] = 'Devotion Aura missing',
	[CRUSADER] = 'Switch to Crusader Aura',
}
-- Used only if the client will not name the spell's own icon.
local ICONS = {
	[DEVOTION] = [[Interface\Icons\Spell_Holy_DevotionAura]],
	[CRUSADER] = [[Interface\Icons\Spell_Holy_CrusaderAura]],
}

-- [textPos] = { text point, icon point, x gap, y gap }
local TEXT_ANCHORS = {
	BOTTOM = { 'TOP',    'BOTTOM',  0, -4 },
	TOP    = { 'BOTTOM', 'TOP',     0,  4 },
	LEFT   = { 'RIGHT',  'LEFT',   -6,  0 },
	RIGHT  = { 'LEFT',   'RIGHT',   6,  0 },
	CENTER = { 'CENTER', 'CENTER',  0,  0 },
}

-- DungeonChallenge (the key running) and DungeonMythic (before it goes in).
local MYTHIC_DIFFICULTY = { [8] = true, [23] = true }

local DEFAULTS = {
	enable    = true,
	mplusOnly = true,
	iconSize  = 48,
	textSize  = 18,
	textColor = { 0.96, 0.55, 0.73, 1 },
	textPos   = 'BOTTOM',
	textX     = 0,
	textY     = 0,
	lock      = false,
	x         = 0,
	y         = 160,
}

local function GetCfg() return ns.ModuleCfg('paladinAura', DEFAULTS) end
ns.PAUGetCfg = GetCfg

local frame, icon, text
local preview = false
local live = false

-- ok, active aura's spell ID (nil = none on), Devotion on the bar, Crusader
-- on the bar. ok is false when the bar could not be read in the clear.
local function ReadBar()
	local okN, n = pcall(GetNumShapeshiftForms)
	if not okN or secret(n) or not n then return false end
	local active, hasDevo, hasCrus
	for i = 1, n do
		local ok, _, isActive, _, spellID = pcall(GetShapeshiftFormInfo, i)
		if not ok or secret(isActive) or secret(spellID) then return false end
		if spellID == DEVOTION then hasDevo = true
		elseif spellID == CRUSADER then hasCrus = true end
		if isActive then active = spellID end
	end
	return true, active, hasDevo, hasCrus
end

local function Clear(fn, ...)
	local ok, v = pcall(fn, ...)
	return ok and not secret(v) and v and true or false
end

-- An unclear answer counts as yes (see the top of the file).
local function InMythicPlus()
	local CM = _G.C_ChallengeMode
	if CM and CM.IsChallengeModeActive then
		local ok, v = pcall(CM.IsChallengeModeActive)
		if ok and (secret(v) or v) then return true end
	end
	local ok, _, kind, difficulty = pcall(GetInstanceInfo)
	if not ok or secret(kind) or secret(difficulty) then return true end
	return kind == 'party' and MYTHIC_DIFFICULTY[difficulty] or false
end

-- The spell ID whose icon should show, or nil.
local function Wanted()
	if preview then return DEVOTION end
	if not live then return nil end
	if Clear(UnitIsDeadOrGhost, 'player') or Clear(UnitOnTaxi, 'player') then return nil end
	if GetCfg().mplusOnly and not InMythicPlus() then return nil end
	local ok, active, hasDevo, hasCrus = ReadBar()
	if not ok then return nil end
	if active == CRUSADER then
		return hasDevo and DEVOTION or nil
	end
	local okM, mounted = pcall(IsMounted)
	if not okM or secret(mounted) or not mounted then return nil end
	return hasCrus and CRUSADER or nil
end

local function SpellIcon(id)
	local CS = _G.C_Spell
	if CS and CS.GetSpellTexture then
		local ok, tex = pcall(CS.GetSpellTexture, id)
		if ok and tex and not secret(tex) then return tex end
	end
	return ICONS[id]
end

local function EnsureFrame()
	if frame then return end
	frame = CreateFrame('Frame', 'XerionUIPaladinAura', UIParent)
	frame:SetFrameStrata('HIGH')
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(false)
	frame:RegisterForDrag('RightButton')
	ns.MakeDraggable(frame, GetCfg, 'x', 'y')
	icon = ns.PixelBorderIcon(frame)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	text = frame:CreateFontString(nil, 'OVERLAY')
	frame:Hide()
end

local function Refresh()
	if not frame then return end
	local id = Wanted()
	if id then
		icon:SetTexture(SpellIcon(id))
		text:SetText(TEXTS[id])
	end
	frame:SetShown(id ~= nil)
end
local RefreshSoon = ns.Coalesce(Refresh)

local EVENTS = {
	'PLAYER_ENTERING_WORLD', 'UPDATE_SHAPESHIFT_FORM', 'UPDATE_SHAPESHIFT_FORMS',
	'PLAYER_MOUNT_DISPLAY_CHANGED', 'PLAYER_CONTROL_LOST', 'PLAYER_CONTROL_GAINED',
	'PLAYER_DEAD', 'PLAYER_ALIVE', 'PLAYER_UNGHOST',
	'ZONE_CHANGED_NEW_AREA', 'PLAYER_DIFFICULTY_CHANGED', 'CHALLENGE_MODE_START', 'CHALLENGE_MODE_RESET',
}
local evt = CreateFrame('Frame')
evt:SetScript('OnEvent', function() RefreshSoon() end)

local function SetLive(on)
	on = on and true or false
	if on == live then return end
	live = on
	for _, e in ipairs(EVENTS) do
		if on then evt:RegisterEvent(e) else evt:UnregisterEvent(e) end
	end
end

-- Nothing is built while the module is off (or the player is not a paladin)
-- and not previewing; a frame built earlier is only hidden.
local function Apply()
	local cfg = GetCfg()
	local on = cfg.enable and ns.IsClass('PALADIN')
	SetLive(on)
	if not (on or preview) then
		Refresh()
		return
	end
	EnsureFrame()
	local size = cfg.iconSize or DEFAULTS.iconSize
	frame:SetSize(size, size)
	frame:ClearAllPoints()
	frame:SetPoint('CENTER', UIParent, 'CENTER', cfg.x or 0, cfg.y or 0)
	local c = cfg.textColor or DEFAULTS.textColor
	text:SetFont(ns.GothamNarrowBlackFont(), cfg.textSize or DEFAULTS.textSize, 'OUTLINE')
	text:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
	local a = TEXT_ANCHORS[cfg.textPos] or TEXT_ANCHORS.BOTTOM
	text:ClearAllPoints()
	text:SetPoint(a[1], frame, a[2], a[3] + (cfg.textX or 0), a[4] + (cfg.textY or 0))
	frame:EnableMouse(preview and not cfg.lock or false)
	Refresh()
end
ns.PAUApply = ns.Coalesce(Apply)

ns.PAUIsPreview = function() return preview end
ns.PAUSetPreview = function(v)
	preview = v and true or false
	Apply()
end

-- /xerionaura          - state dump
-- /xerionaura test     - toggle the preview so the icon can be placed
_G.SLASH_XERIONAURA1 = '/xerionaura'
_G.SlashCmdList.XERIONAURA = function(msg)
	local function p(...) print('|cffF48CBAXerionUI Paladin Aura|r', ...) end
	msg = (msg or ''):lower()
	if msg:find('test') or msg:find('preview') then
		ns.PAUSetPreview(not preview)
		p('preview', preview and 'on' or 'off')
		return
	end
	local cfg = GetCfg()
	local okM, mounted = pcall(IsMounted)
	local ok, active, hasDevo, hasCrus = ReadBar()
	p('enabled =', cfg.enable and '|cff00ff00yes|r' or '|cff777777no|r',
		'| paladin =', tostring(ns.IsClass('PALADIN')),
		'| listening =', tostring(live), '| preview =', tostring(preview))
	p('mounted =', not okM and 'error' or (secret(mounted) and 'secret' or tostring(mounted)),
		'| taxi =', tostring(Clear(UnitOnTaxi, 'player')),
		'| only in M+ =', tostring(cfg.mplusOnly), '| in M+ =', tostring(InMythicPlus()))
	p('stance bar =', ok and 'readable' or '|cffff5555unreadable|r',
		'| active aura =', tostring(active), '(465 Devotion, 32223 Crusader)',
		'| has Devotion =', tostring(hasDevo), '| has Crusader =', tostring(hasCrus))
	p('showing =', tostring(Wanted()), '| shown =', tostring(frame and frame:IsShown() or false))
	p('|cff999999/xerionaura test|r toggles the preview.')
end
