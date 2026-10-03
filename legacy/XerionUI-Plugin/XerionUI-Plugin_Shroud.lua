-- WHY THIS FILE EXISTS
--
-- A rogue's Shroud of Concealment hides the whole party for fifteen seconds,
-- and the party has no idea how many of those are left. The buff you get as a
-- non-rogue (115834) carries no timer - the rogue sustains it, so your copy
-- is "on" or "off" and nothing else. The timer lives on the rogue's own aura
-- (114018), which is why EllesmereUI's party frames show a countdown on the
-- rogue's frame and on nobody else's. Inside a key no addon may read that
-- aura either way.
--
-- A mage's Mass Invisibility is the same moment for the same party, and the
-- easy one of the two: every player it lands on gets the buff (414664) with
-- its own twelve-second timer, so that bar just watches you.
--
-- WHAT IT DOES
--
-- Two bars stacked in one frame, Mass Invisibility on top and Shroud under
-- it: the spell's icon on the left, a fill that drains as the seconds go, a
-- short name in the bar and the seconds left on the right. Each bar is its
-- own aura container filtered to its spell - the Shroud one pointed at the
-- rogue in your party (or you, when you are the rogue), the Mass
-- Invisibility one at you while you are in a group - whose one button owns
-- the bar. `SetDurationBar`, `SetDurationText` and `SetIcon` bind our regions
-- to the aura's duration object, the engine fills and counts, and this file
-- never learns a number.
-- Spell-ID filters are honoured for helpful auras on a unit you can assist
-- (AuraContainerUtil.CanApplyIdentityCandidateFilters), and a party member
-- is one.
--
-- The stack is laid out from the switches, not from which aura is up: Lua
-- cannot know that, so each bar keeps its place and is simply empty while
-- its spell is down.
--
-- WHAT IT CANNOT DO
--
-- * Warn at "three seconds left" or change colour by time in Lua: the seconds
--   only ever exist inside the engine.
-- * Show two rogues at once. The first rogue found is the one on the bar and
--   stays there while they remain in the group.
-- * Tell the party in chat. An addon may not write to chat inside a key, and a
--   text countdown would need a line every second, which a macro cannot do.
--   A party countdown and a macro line were tried here and removed: the bars
--   are the whole feature.

local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('Shroud', hooksecurefunc, C_Timer)
local _G = _G

local CreateFrame = CreateFrame
local UIParent = UIParent
local C_Timer = C_Timer
local C_Spell = C_Spell
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit
local UnitName = UnitName
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local ipairs, pcall, type, tostring = ipairs, pcall, type, tostring
local mmax, mmin, mfloor = math.max, math.min, math.floor

local secret = ns.IsSecret
local IS_121 = ns.IS_121

ns.hasShroud = true

-- The cast is 114018 and so is the rogue's own aura; 115834 is the copy the
-- party gets. Both are on the list, because which one the rogue's own frame
-- carries the timer on is not something the docs say, and a duration cap in
-- the filter keeps the timerless copy out of the bar's single slot: a "max
-- duration" candidate filter always rejects a permanent aura.
local SHROUD = 114018
local MASS_INVIS = 414664
local MAX_DURATION = 60

ns.SHUnavailable = not (IS_121 and ns.HasTemplate('CustomAuraContainerTemplate'))

local DEFAULTS = {
	enable = false,
	lock = false,
	x = 0,
	y = 120,

	width = 220,
	height = 22,
	texture = '',
	-- Between the Mass Invisibility bar and the Shroud bar.
	gap = 2,
	bgAlpha = 0.6,
	customBgColor = false,
	bgColor = { 0.087, 0.054, 0.129, 1 },
	-- An outline round each bar and its icon, inside the bar's own size.
	border = true,
	borderSize = 1,
	borderColor = { 0, 0, 0, 1 },
	showIcon = true,
	showName = true,
	showTimer = true,
	textSize = 14,

	showShroud = true,
	color = { 0.58, 0.36, 0.86, 1 },
	-- Your own Shroud on the bar when you are the rogue.
	selfBar = true,

	showMassInvis = true,
	-- The mage class colour.
	miColor = { 0.25, 0.78, 0.92, 1 },
}

-- An older feature left a table under the same key (channel, duration,
-- dungeonOnly, groupOnly, spellID: a chat announce). Its switch must not
-- turn this bar on by itself, so the leftovers go and Enable starts off.
-- Settings of parts this bar has since dropped (sounds, the rogue's party
-- countdown and macro text) go as well.
local function Migrate(cfg)
	cfg.sound, cfg.endSound, cfg.countdownSeconds = nil, nil, nil
	cfg.countdown, cfg.partyText = nil, nil
	if cfg.channel == nil and cfg.dungeonOnly == nil and cfg.spellID == nil then return end
	cfg.channel, cfg.duration, cfg.dungeonOnly, cfg.groupOnly, cfg.spellID = nil, nil, nil, nil, nil
	cfg.enable = false
end

local function GetCfg() return ns.ModuleCfg('shroud', DEFAULTS, Migrate) end
ns.SHGetCfg = GetCfg

-- ---------------------------------------------------------------------------
-- Who the rogue is
-- ---------------------------------------------------------------------------

local PARTY, RAID = {}, {}
for i = 1, 4 do PARTY[i] = 'party' .. i end
for i = 1, 40 do RAID[i] = 'raid' .. i end

-- Class tokens of group members are readable in keys (identity is only
-- restricted for units outside the group); a secret answer is "not a rogue".
local function ClassOf(unit)
	local ok, _, token = pcall(UnitClass, unit)
	if not ok or secret(token) then return nil end
	return token
end

local function Exists(unit)
	local ok, v = pcall(UnitExists, unit)
	return ok and v == true
end

-- You first when you are the rogue, otherwise the first rogue in group order.
-- Whoever is already on the bar keeps it while they still qualify, so a
-- roster event does not hop between two rogues.
local function FindRogue(cfg, current)
	if cfg.selfBar ~= false and ClassOf('player') == 'ROGUE' then return 'player' end
	local list = IsInRaid() and RAID or PARTY
	local first, kept
	for _, u in ipairs(list) do
		if Exists(u) then
			local okS, same = pcall(UnitIsUnit, u, 'player')
			if okS and not secret(same) and not same and ClassOf(u) == 'ROGUE' then
				first = first or u
				if u == current then kept = u end
			end
		end
	end
	return kept or first
end

-- ---------------------------------------------------------------------------
-- The two bars, top first. Everything that differs between them is here; the
-- rest of the file walks this list. The names are short on purpose: the full
-- spell names crowd the timer on a short bar.
-- ---------------------------------------------------------------------------

local TRACKS = {
	{
		label = 'Mass Invis', group = 'massinvis', frame = 'XerionUIMassInvisContainer',
		on = 'showMassInvis', colorKey = 'miColor', spell = MASS_INVIS, ids = { MASS_INVIS },
		icon = 'Interface\\Icons\\Ability_Mage_Invisibility',
		-- Everyone it lands on carries the timed buff, so the one to watch is you
		-- - in a group only: it is a party moment, and solo the container would
		-- sit live on your auras all day for nothing. GROUP_ROSTER_UPDATE asks
		-- again on joining and leaving, in combat too (nothing under the holder
		-- is secure, so the switch is allowed then). An unreadable answer means
		-- watch.
		find = function()
			if ns.Ask(IsInGroup) ~= false then return 'player' end
		end,
	},
	{
		label = 'Shroud', group = 'shroud', frame = 'XerionUIShroudContainer',
		on = 'showShroud', colorKey = 'color', spell = SHROUD, ids = { SHROUD, 115834 },
		icon = 'Interface\\Icons\\Ability_Rogue_EnvelopingShadows',
		find = FindRogue,
	},
}
for _, t in ipairs(TRACKS) do t.buttons = {} end

local function TrackOn(cfg, t) return cfg[t.on] ~= false end

-- ---------------------------------------------------------------------------
-- Drawing a bar
-- ---------------------------------------------------------------------------

local holder
local preview = false
local stylePending = false

local function ApplyPosition()
	if not holder then return end
	local cfg = GetCfg()
	holder:ClearAllPoints()
	holder:SetPoint('CENTER', UIParent, 'CENTER', cfg.x or 0, cfg.y or 120)
end

local function BarColor(cfg, t)
	local c = cfg[t.colorKey] or DEFAULTS[t.colorKey]
	local d = DEFAULTS[t.colorKey]
	return c[1] or d[1], c[2] or d[2], c[3] or d[3]
end

local function SpellIcon(t)
	local get = C_Spell and C_Spell.GetSpellTexture
	if get then
		local ok, tex = pcall(get, t.spell)
		if ok and tex and not secret(tex) then return tex end
	end
	return t.icon
end

local function Layout(cfg)
	-- The layout's element size is what the engine lays out, not the button's
	-- own (CustomAuraContainerFlowLayoutMixin:GetElementSize).
	return { elementWidth = cfg.width or 220, elementHeight = cfg.height or 22,
		elementSpacing = 0, lineSpacing = 0 }
end

local function BorderSize(cfg)
	if cfg.border == false then return 0 end
	return mmax(1, mmin(4, mfloor(cfg.borderSize or 1)))
end

local function BarTexture(cfg)
	local name = cfg.texture
	if type(name) == 'string' and name ~= '' then
		local lib = ns.LSM()
		if lib and lib.Fetch then
			local ok, path = pcall(lib.Fetch, lib, 'statusbar', name, true)
			if ok and path then return path end
		end
	end
	return ns.BarTexture()
end

-- The pieces of one bar on `parent`: background, the outline, icon at the
-- left, the fill, and a text layer above it with the name on the left and the
-- timer on the right. The same pieces make the preview on the holder and the
-- live bar on the engine's button.
local function MakeBar(parent)
	local p = {}
	p.bg = parent:CreateTexture(nil, 'BACKGROUND')
	-- The outline is five strips - the four sides and the line between the icon
	-- and the fill - rather than one plate under everything, which would show
	-- through the see-through back and make it solid.
	p.edges = {}
	for i = 1, 5 do p.edges[i] = parent:CreateTexture(nil, 'BORDER') end
	p.icon = parent:CreateTexture(nil, 'ARTWORK')
	p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	p.bar = CreateFrame('StatusBar', nil, parent)
	p.text = CreateFrame('Frame', nil, parent)
	p.text:SetAllPoints()
	p.text:SetFrameLevel(p.bar:GetFrameLevel() + 5)
	p.name = p.text:CreateFontString(nil, 'OVERLAY')
	p.name:SetWordWrap(false)
	p.timer = p.text:CreateFontString(nil, 'OVERLAY')
	return p
end

-- The strips a bar shows: none without an outline, and no divider without an
-- icon to divide off.
local function ShowEdges(p, cfg, on)
	local s = BorderSize(cfg)
	for i = 1, 5 do
		p.edges[i]:SetShown(on and s > 0 and (i < 5 or cfg.showIcon ~= false))
	end
end

local function StyleBar(p, cfg, t)
	local h = cfg.height or 22
	local r, g, b = BarColor(cfg, t)
	local font, size = ns.GetFont(), cfg.textSize or 14
	local showIcon = cfg.showIcon ~= false
	-- The outline takes `s` pixels inside the bar's own size - round the edge
	-- and between the icon and the fill - so the stack keeps its size and its
	-- spacing whatever the outline is. Without one the icon keeps its old
	-- one-pixel gap to the fill.
	local s = BorderSize(cfg)
	local inH = mmax(1, h - 2 * s)
	local left = showIcon and (s + inH + mmax(1, s)) or s
	p.bg:ClearAllPoints()
	p.bg:SetPoint('TOPLEFT', s, -s)
	p.bg:SetPoint('BOTTOMRIGHT', -s, s)
	local br, bg, bb = r * 0.15, g * 0.15, b * 0.15
	if cfg.customBgColor then
		local bgc = cfg.bgColor or DEFAULTS.bgColor
		br, bg, bb = bgc[1] or 0, bgc[2] or 0, bgc[3] or 0
	end
	p.bg:SetColorTexture(br, bg, bb, cfg.bgAlpha or 0.6)
	local bc = cfg.borderColor
	if type(bc) ~= 'table' then bc = DEFAULTS.borderColor end
	local e, edgeW = p.edges, mmax(1, s)
	for i = 1, 5 do
		e[i]:ClearAllPoints()
		e[i]:SetColorTexture(bc[1] or 0, bc[2] or 0, bc[3] or 0, bc[4] or 1)
	end
	e[1]:SetPoint('TOPLEFT')
	e[1]:SetPoint('TOPRIGHT')
	e[1]:SetHeight(edgeW)
	e[2]:SetPoint('BOTTOMLEFT')
	e[2]:SetPoint('BOTTOMRIGHT')
	e[2]:SetHeight(edgeW)
	e[3]:SetPoint('TOPLEFT', 0, -s)
	e[3]:SetPoint('BOTTOMLEFT', 0, s)
	e[3]:SetWidth(edgeW)
	e[4]:SetPoint('TOPRIGHT', 0, -s)
	e[4]:SetPoint('BOTTOMRIGHT', 0, s)
	e[4]:SetWidth(edgeW)
	e[5]:SetPoint('TOPLEFT', s + inH, -s)
	e[5]:SetPoint('BOTTOMLEFT', s + inH, s)
	e[5]:SetWidth(edgeW)
	ShowEdges(p, cfg, true)
	p.icon:ClearAllPoints()
	p.icon:SetPoint('TOPLEFT', s, -s)
	p.icon:SetSize(inH, inH)
	p.icon:SetShown(showIcon)
	p.bar:ClearAllPoints()
	p.bar:SetPoint('TOPLEFT', left, -s)
	p.bar:SetPoint('BOTTOMRIGHT', -s, s)
	p.bar:SetStatusBarTexture(BarTexture(cfg))
	p.bar:SetStatusBarColor(r, g, b)
	-- Font before anything writes text: SetText on an unfonted fontstring is
	-- a hard error, and the engine writes the timer on its own.
	p.name:SetFont(font, size, 'OUTLINE')
	p.timer:SetFont(font, size, 'OUTLINE')
	p.timer:ClearAllPoints()
	p.timer:SetPoint('RIGHT', p.bar, 'RIGHT', -4, 0)
	p.timer:SetJustifyH('RIGHT')
	p.timer:SetShown(cfg.showTimer ~= false)
	p.name:ClearAllPoints()
	p.name:SetPoint('LEFT', p.bar, 'LEFT', 4, 0)
	p.name:SetPoint('RIGHT', p.timer, 'LEFT', -4, 0)
	p.name:SetJustifyH('LEFT')
	p.name:SetShown(cfg.showName ~= false)
	p.name:SetText(t.label)
end

local function EnsureFrame()
	if holder then return end
	-- Named, because edit mode looks the frame up by this exact string. It
	-- covers both bars, so edit mode and a right-drag move the stack as one.
	holder = CreateFrame('Frame', 'XerionUIShroud', UIParent)
	holder:SetFrameStrata('MEDIUM')
	holder:SetSize(220, 22)
	holder:SetClampedToScreen(true)
	holder:SetMovable(true)
	holder:EnableMouse(false)
	holder:RegisterForDrag('RightButton')
	holder:Hide()
	ns.MakeDraggable(holder, GetCfg, 'x', 'y', ApplyPosition)

	for _, t in ipairs(TRACKS) do
		-- One slot per bar: its place in the stack, holding the preview and,
		-- once built, the engine's container.
		t.slot = CreateFrame('Frame', nil, holder)
		t.slot:SetSize(220, 22)
		-- The preview: a bar Lua fills itself, since the engine only draws while
		-- the real aura is up.
		t.sample = MakeBar(t.slot)
		t.sample.bar:SetMinMaxValues(0, 1)
		t.sample.bar:SetValue(0.6)
	end
	ApplyPosition()
end

-- Top to bottom in list order, only the bars that are switched on, and the
-- holder sized to exactly what is stacked in it.
local function LayoutSlots(cfg)
	local w, h = cfg.width or 220, cfg.height or 22
	local gap = cfg.gap or 2
	local y, n = 0, 0
	for _, t in ipairs(TRACKS) do
		local on = TrackOn(cfg, t)
		t.slot:SetShown(on)
		if on then
			t.slot:ClearAllPoints()
			t.slot:SetPoint('TOPLEFT', holder, 'TOPLEFT', 0, -y)
			t.slot:SetSize(w, h)
			y = y + h + gap
			n = n + 1
		end
	end
	holder:SetSize(w, n > 0 and (y - gap) or h)
end

local function SetSampleShown(t, on)
	local s = t.sample
	if not s then return end
	s.bg:SetShown(on)
	ShowEdges(s, GetCfg(), on)
	s.icon:SetShown(on and GetCfg().showIcon ~= false)
	s.bar:SetShown(on)
	s.text:SetShown(on)
end

-- The engine's button for a bar's one aura. Everything the bar is made of
-- hangs under it, so it comes and goes with the aura and the engine never has
-- to answer whether the aura is there. This runs once per button the engine
-- prebuilds, inside its frame batch: an error here would take the batch and
-- the slot down with it, so the optional text binding is armoured.
local function InitButton(t, b)
	local cfg = GetCfg()
	-- Display only. A Button takes the mouse by default and would swallow
	-- clicks meant for the world for as long as the aura is up.
	pcall(b.SetMouseClickEnabled, b, false)
	pcall(b.SetMouseMotionEnabled, b, false)
	b:SetSize(cfg.width or 220, cfg.height or 22)
	local p = MakeBar(b)
	StyleBar(p, cfg, t)
	b:SetIcon(p.icon)
	local E = _G.Enum
	local opts = {}
	if E and E.StatusBarInterpolation then opts.interpolation = E.StatusBarInterpolation.Immediate end
	if E and E.StatusBarTimerDirection then opts.direction = E.StatusBarTimerDirection.RemainingTime end
	b:SetDurationBar(p.bar, opts)
	local okT, errT = pcall(b.SetDurationText, b, p.timer, ns.DurationTextOptions())
	if not okT then
		t.textFailed = tostring(errT)
		p.timer:SetText('')
	end
	t.buttons[#t.buttons + 1] = { frame = b, p = p }
end

local function EnsureContainer(t)
	if t.container or t.failed or ns.SHUnavailable then return end
	local ok, c = pcall(CreateFrame, 'AuraContainer', t.frame, t.slot, 'CustomAuraContainerTemplate')
	if not ok or not c then
		t.failed = 'the client refused the AuraContainer frame'
		return
	end
	c:SetSize(1, 1)
	local include = {}
	for _, id in ipairs(t.ids) do include[id] = true end
	local okG, err = pcall(c.AddAuraGroup, c, t.group, 'HELPFUL', {
		maxFrameCount = 1,
		candidateFilters = { includeSpellIDs = include, maxDuration = MAX_DURATION },
		initializeFrame = function(b) InitButton(t, b) end,
		layout = Layout(GetCfg()),
	})
	if not okG then
		t.failed = tostring(err)
		c:Hide()
		return
	end
	pcall(c.SetEnabled, c, false)
	-- Anchored only now: once a container has a group its size is the engine's
	-- business, its position stays ours.
	c:SetPoint('TOPLEFT', t.slot, 'TOPLEFT', 0, 0)
	t.container = c
end

-- Settings work on the engine's buttons. In combat the client may refuse to
-- let us touch them; the change waits for the fight to end.
local function RestyleButtons(cfg)
	stylePending = false
	for _, t in ipairs(TRACKS) do
		for _, rec in ipairs(t.buttons) do
			local ok = pcall(function()
				rec.frame:SetSize(cfg.width or 220, cfg.height or 22)
				StyleBar(rec.p, cfg, t)
			end)
			if not ok then stylePending = true end
		end
		local c = t.container
		if c and not pcall(c.SetAuraGroupLayout, c, t.group, Layout(cfg)) then stylePending = true end
	end
end

-- ---------------------------------------------------------------------------
-- Keeping it current
-- ---------------------------------------------------------------------------

local function UpdateVisibility()
	if not holder then return end
	local cfg = GetCfg()
	local live = false
	for _, t in ipairs(TRACKS) do
		SetSampleShown(t, preview and TrackOn(cfg, t))
		if t.container then t.container:SetShown(not preview) end
		if t.unit then live = true end
	end
	live = live and cfg.enable and not ns.SHUnavailable and not preview
	holder:SetShown(preview or live)
	holder:EnableMouse(preview and not cfg.lock or false)
end

-- Roster level: who each bar watches, and is the stack up. `reread` is a
-- loading screen, which rebuilds the client's aura data behind a SetUnit that
-- would otherwise be a no-op.
local rereadNext = false
local function Refresh()
	local reread = rereadNext
	rereadNext = false
	local cfg = GetCfg()
	local want = cfg.enable and not ns.SHUnavailable and not preview
	local again = {}
	for _, t in ipairs(TRACKS) do
		local u = want and TrackOn(cfg, t) and t.find(cfg, t.unit) or nil
		local changed = u ~= t.unit
		t.unit = u
		local c = t.container
		if c then
			if u then
				-- Unit before enable: enabling registers the unit's aura events.
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
	UpdateVisibility()
	-- Shown first: a container only works while visible.
	for _, c in ipairs(again) do pcall(c.UpdateAllAuras, c) end
end

local evt = CreateFrame('Frame')

local function Apply()
	local cfg = GetCfg()
	local wanted = cfg.enable and not ns.SHUnavailable
	if cfg.enable then
		evt:RegisterEvent('GROUP_ROSTER_UPDATE')
		evt:RegisterEvent('PLAYER_REGEN_ENABLED')
		evt:RegisterEvent('ADDON_RESTRICTION_STATE_CHANGED')
	else
		evt:UnregisterEvent('GROUP_ROSTER_UPDATE')
		evt:UnregisterEvent('PLAYER_REGEN_ENABLED')
		evt:UnregisterEvent('ADDON_RESTRICTION_STATE_CHANGED')
	end
	if not (wanted or preview) then
		for _, t in ipairs(TRACKS) do
			t.unit = nil
			if t.container then pcall(t.container.SetEnabled, t.container, false) end
		end
		if holder then holder:Hide() end
		return
	end

	EnsureFrame()
	ApplyPosition()
	LayoutSlots(cfg)
	for _, t in ipairs(TRACKS) do
		StyleBar(t.sample, cfg, t)
		t.sample.icon:SetTexture(SpellIcon(t))
		t.sample.timer:SetText('9')
		if wanted and TrackOn(cfg, t) then EnsureContainer(t) end
	end
	if wanted then RestyleButtons(cfg) end
	Refresh()
end

-- A dragged slider asks many times a frame; one Apply answers all of them.
ns.SHApply = ns.Coalesce(Apply)
-- Same for a raid's burst of roster events.
local QueueRefresh = ns.Coalesce(Refresh)

ns.SHIsPreview = function() return preview end
ns.SHSetPreview = function(state)
	preview = state and true or false
	Apply()
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

evt:RegisterEvent('PLAYER_ENTERING_WORLD')
-- A key whose last fight ended before the timer stopped lifts its restriction
-- with no PLAYER_REGEN_ENABLED after it, so a refused restyle also retries on
-- the restriction's own change event - on the next frame, because the state
-- still reads the old value while that event is handed out (LustPots).
local QueueRestyle = ns.Coalesce(function()
	if stylePending and not preview and GetCfg().enable then RestyleButtons(GetCfg()) end
end)

evt:SetScript('OnEvent', function(_, event)
	if event == 'PLAYER_ENTERING_WORLD' then
		rereadNext = true
		C_Timer.After(0.5, ns.SHApply)
		return
	end
	if preview or not GetCfg().enable then return end
	if event == 'PLAYER_REGEN_ENABLED' then
		-- First moment the engine's buttons are ours to touch again.
		if stylePending then RestyleButtons(GetCfg()) end
		return
	end
	if event == 'ADDON_RESTRICTION_STATE_CHANGED' then
		if stylePending then QueueRestyle() end
		return
	end
	QueueRefresh()
end)

-- ---------------------------------------------------------------------------
-- Diagnostics
--
-- Whether an aura is up is the one thing that cannot be printed - that is the
-- secret. Everything around it can: who each bar watches, whether its
-- container was built and why not.
-- ---------------------------------------------------------------------------

_G.SLASH_XERIONSHROUD1 = '/xerionshroud'
_G.SlashCmdList.XERIONSHROUD = function()
	local function p(...) print('|cffff7d0aXerionUI-Shroud|r', ...) end
	local cfg = GetCfg()
	p('enable =', cfg.enable and 'on' or 'off', '| preview =', preview and 'ON' or 'off',
		'| aura containers =', ns.SHUnavailable and '|cffff5555unavailable|r' or 'ok',
		'| you =', tostring(ClassOf('player')), '| own Shroud =', cfg.selfBar ~= false and 'on' or 'off',
		stylePending and '| |cffff5555restyle waits for combat to end|r' or '')
	for _, t in ipairs(TRACKS) do
		local who = t.unit
		if who then
			local ok, name = pcall(UnitName, who)
			if ok and type(name) == 'string' and not secret(name) then who = who .. ' (' .. name .. ')' end
		elseif not TrackOn(cfg, t) then
			who = 'switched off'
		elseif t.group == 'shroud' then
			who = '|cffff5555nobody|r (no rogue in the group)'
		else
			who = '|cffff5555nobody|r' .. (ns.Ask(IsInGroup) == false and ' (not in a group)' or '')
		end
		p(t.label .. ': watching =', who,
			'| auras =', table.concat(t.ids, ', '), 'under', MAX_DURATION, 's',
			'| container =', t.container and 'built' or 'not built', '| buttons =', #t.buttons)
		if t.failed then p('|cffff5555' .. t.label .. ' stopped: ' .. t.failed .. '|r') end
		if t.textFailed then p(t.label .. ' timer text refused: ' .. t.textFailed .. ' (the bar still fills)') end
	end
	p('bars: |cff66dd66up to the engine|r - each is drawn while its aura is up; whether it is up right now is the one thing this cannot print')
end
