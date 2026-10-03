-- WHY THIS FILE EXISTS
--
-- Reaper's Mark (Deathbringer) is a debuff on one enemy: it gathers stacks and
-- bursts after its time runs out or at 40 stacks. The cooldown manager, and
-- EllesmereUI's bars built on it, read auras off two units only - the player
-- and the target (CooldownViewerItemData.lua, `scanUnits`) - so the moment you
-- switch targets the mark's seconds and stacks vanish from them, though the
-- mob still carries it.
--
-- WHAT IT DOES
--
-- One icon that shows YOUR mark wherever it is: the seconds left, the stack
-- count and a swipe, whichever enemy carries it, as long as that enemy has a
-- nameplate or is your target. It sits on screen or on an EllesmereUI buff
-- group, with the same anchor The Blood is Life uses (CDMAnchor.lua).
--
-- HOW, WITH THE AURA SECRET
--
-- Inside a key or a raid an enemy's auras are secret: Lua never learns the
-- seconds, the stacks or which mob. The engine draws them. Every enemy
-- nameplate token, and the target, gets an aura container holding ONE aura
-- slot, filtered to the debuff's ID and to auras you applied (HARMFUL|PLAYER).
-- A slot is one button, shown only while its unit carries the aura, and every
-- slot is pinned to the holder's centre - so whichever mob carries the mark
-- lights the icon in that one spot. The engine binds the swipe
-- (SetDurationCooldown), the seconds (SetDurationText) and the stacks
-- (SetApplicationCount); the frame, the border and the art are ours.
--
-- The spell filter only holds on units you cannot assist
-- (AuraContainerUtil.CanApplyIdentityCandidateFilters). On a friendly unit
-- the engine would skip it and light the slot for any debuff of yours, so a
-- container is only switched on for a unit that plainly answers "cannot
-- assist" (Verdict, the CC Tracker's rule).
--
-- The target's slot is for a target without a nameplate. Were it on while
-- the target's nameplate slot also lit, the two swipes would stack on one
-- spot and read darker, so it is only switched on when the client plainly
-- says no nameplate is the target. UnitIsUnit goes secret where unit
-- comparison is restricted, and then the nameplate alone carries it.
--
-- WHY SETTINGS ONLY TOUCH OUR OWN PIECES
--
-- The CC Tracker's rule (CCBars.lua): once its initializer returns, the engine
-- locks a button against addon code for as long as auras are secret - in
-- combat and for the whole of a key. So the button stays 1x1 on the holder's
-- centre, pinned there once inside its initializer, and every piece hangs off
-- a frame of ours with a size of its own. A restyle the client refuses waits
-- for the fight, or the key, to end.
--
-- WHAT IT CANNOT DO
--
-- * Glow or play a sound at a stack count, or say which mob carries the mark:
--   that needs the numbers in Lua. /xerionreaper prints the debuff's secrecy
--   level; 0 (never secret) would open that door.
-- * Show a mark on a mob that has no nameplate and is not your target.

local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('ReapersMark', hooksecurefunc, C_Timer)
local _G = _G

local CreateFrame = CreateFrame
local UIParent = UIParent
local GetTime = GetTime
local C_Timer = C_Timer
local UnitExists = UnitExists
local UnitCanAttack = UnitCanAttack
local UnitCanAssist = UnitCanAssist
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsUnit = UnitIsUnit
local UnitName = UnitName
local ipairs, pairs, pcall, type, tostring = ipairs, pairs, pcall, type, tostring
local tconcat, wipe = table.concat, wipe
local mmax, mmin = math.max, math.min

local Round = ns.Round
local secret = ns.IsSecret
local Ask = ns.Ask

ns.hasReapersMark = true
ns.RKMUnavailable = not (ns.IS_121 and ns.HasTemplate('CustomAuraContainerTemplate'))

-- The debuff on the mob, and the button that casts it (the talent check).
local DEBUFF = 434765
local CAST   = 439843
local PAGE_TITLE = 'Reaper\'s Mark'
local SLOT_KEY = 'rkm'
local FILTER = 'HARMFUL|PLAYER'
-- Containers the background builder makes per frame. A slot is a single
-- button, so this is cheap; spread out only so a login never builds all 41 in
-- one frame.
local BUILD_STEP = 6
-- The preview: 8 seconds of 12 left, 23 stacks.
local PREVIEW_SECS, PREVIEW_STACKS, PREVIEW_DURATION = 8, 23, 12

-- nameplate1..40 is every enemy token the client has; the target covers a mob
-- without a nameplate. One container each, bound for good.
local UNITS = {}
for i = 1, 40 do UNITS[i] = 'nameplate' .. i end
UNITS[#UNITS + 1] = 'target'
local TARGET_SLOT = #UNITS
local SLOT_OF = {}
for i, u in ipairs(UNITS) do SLOT_OF[u] = i end

local DEFAULTS = {
	enable = false,
	lock = true,
	width = 44,
	height = 44,
	x = 0,
	y = -160,
	strata = 'MEDIUM',
	border = { 0, 0, 0, 1 },
	showSwipe = true,
	-- Percent of the art trimmed off each edge; 8 is the addon's usual.
	zoom = 8,

	durText = true,
	-- 0 follows the icon's short side.
	durSize = 0,

	stackSize = 16,
	-- From the icon's centre.
	stackX = 0,
	stackY = 0,
	stackColor = { 1, 1, 1, 1 },

	euiAnchor = false,
	euiBarKey = '',
	euiPlace = 'CENTER',
	euiOffsetX = 0,
	euiOffsetY = 0,
}

local function Migrate(cfg)
	-- The first build measured the stack offsets from the icon's bottom right
	-- corner; they are from its centre now, so old ones start again at 0, 0.
	if not cfg.stackCentred then
		cfg.stackX, cfg.stackY, cfg.stackCentred = 0, 0, true
	end
end

local function GetCfg() return ns.ModuleCfg('reapersMark', DEFAULTS, Migrate) end
ns.RKMGetCfg = GetCfg

local function IsDeathKnight() return ns.IsClass('DEATHKNIGHT') end

-- Everything that decides whether the containers run. The talent check is the
-- cast's, so a San'layn Death Knight builds nothing; an unreadable answer
-- counts as talented (ns.SpellKnown).
local function Wanted(cfg)
	return cfg.enable and not ns.RKMUnavailable and IsDeathKnight() and ns.SpellKnown(CAST)
		and true or false
end

local function Width(cfg) return mmax(8, cfg.width or 44) end
local function Height(cfg) return mmax(8, cfg.height or 44) end

-- The trim per edge as a fraction for ns.IconCoords, which also evens out a
-- non-square icon on top of it.
local function Zoom(cfg)
	local z = (cfg.zoom or DEFAULTS.zoom) / 100
	if z < 0 then z = 0 elseif z > 0.4 then z = 0.4 end
	return z
end

local function DurSize(cfg, w, h)
	local s = cfg.durSize or 0
	if s <= 0 then s = mmax(10, Round(mmin(w, h) * 0.36)) end
	return s
end

local function Color(c, fallback)
	if type(c) ~= 'table' then c = fallback end
	return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
end

-- The debuff's own art, or the cast's should the debuff have none.
local iconTex
local function IconTexture()
	if iconTex then return iconTex end
	local CS = _G.C_Spell
	if CS and CS.GetSpellTexture then
		local ok, tex = pcall(CS.GetSpellTexture, DEBUFF)
		if not (ok and tex and not secret(tex)) then ok, tex = pcall(CS.GetSpellTexture, CAST) end
		if ok and tex and not secret(tex) then
			iconTex = tex
			return tex
		end
	end
	return ns.CdSpellTexture(CAST)
end

-- ---------------------------------------------------------------------------
-- The icon
-- ---------------------------------------------------------------------------

-- The pieces of one icon on `parent`: a frame of ours over it, the icon's own
-- frame centred on that, the border, the art, the swipe and one layer each
-- for the seconds and the stacks. The same pieces make the preview and the
-- face of every engine button.
local function MakeFace(parent)
	local p = {}
	p.root = CreateFrame('Frame', nil, parent)
	p.root:SetAllPoints(parent)
	p.face = CreateFrame('Frame', nil, p.root)
	p.face:SetPoint('CENTER', p.root, 'CENTER', 0, 0)
	p.face:SetSize(44, 44)
	p.border = p.face:CreateTexture(nil, 'BACKGROUND')
	p.border:SetAllPoints(p.face)
	p.icon = p.face:CreateTexture(nil, 'ARTWORK')
	p.icon:SetPoint('TOPLEFT', p.face, 'TOPLEFT', 1, -1)
	p.icon:SetPoint('BOTTOMRIGHT', p.face, 'BOTTOMRIGHT', -1, 1)
	p.icon:SetTexture(IconTexture())
	p.cd = CreateFrame('Cooldown', nil, p.face, 'CooldownFrameTemplate')
	p.cd:SetAllPoints(p.icon)
	p.cd:SetDrawEdge(false)
	p.cd:SetDrawBling(false)
	p.cd:SetReverse(true)
	if p.cd.SetHideCountdownNumbers then p.cd:SetHideCountdownNumbers(true) end
	p.cd.noCooldownCount = true
	-- Layers of their own, because the engine owns the seconds' alpha and the
	-- stacks' shown state (secret aspects): "hide the seconds" dims a frame of
	-- ours instead.
	p.durHost = CreateFrame('Frame', nil, p.face)
	p.durHost:SetAllPoints(p.face)
	p.stackHost = CreateFrame('Frame', nil, p.face)
	p.stackHost:SetAllPoints(p.face)
	p.dur = p.durHost:CreateFontString(nil, 'OVERLAY')
	p.dur:SetPoint('CENTER', p.face, 'CENTER', 0, 0)
	p.stack = p.stackHost:CreateFontString(nil, 'OVERLAY')
	-- A font straight away: the engine writes to both the moment they are
	-- handed over, and SetText on a fontstring with no font is a hard error
	-- that takes the whole AddAuraSlot call down with it.
	p.dur:SetFont(_G.STANDARD_TEXT_FONT, 14, 'OUTLINE')
	p.stack:SetFont(_G.STANDARD_TEXT_FONT, 14, 'OUTLINE')
	return p
end

-- Sizes, colours and fonts of one icon. Every anchor names a frame of ours;
-- the stacks' anchor is set again only when it changed, stamped after the
-- calls so a refused one is tried again next time.
local function StyleFace(p, cfg)
	local w, h = Width(cfg), Height(cfg)
	p.face:SetSize(w, h)
	p.border:SetColorTexture(Color(cfg.border, DEFAULTS.border))
	p.icon:SetTexCoord(ns.IconCoords(w, h, Zoom(cfg)))
	p.cd:SetAlpha(cfg.showSwipe ~= false and 1 or 0)
	local lvl = p.cd:GetFrameLevel()
	p.durHost:SetFrameLevel(lvl + 5)
	p.stackHost:SetFrameLevel(lvl + 6)

	local font = ns.GothamNarrowBlackFont()
	p.durHost:SetAlpha(cfg.durText ~= false and 1 or 0)
	p.dur:SetFont(font, DurSize(cfg, w, h), 'OUTLINE')
	p.stack:SetFont(font, mmax(6, cfg.stackSize or DEFAULTS.stackSize), 'OUTLINE')
	p.stack:SetTextColor(Color(cfg.stackColor, DEFAULTS.stackColor))

	local sx, sy = cfg.stackX or 0, cfg.stackY or 0
	local key = sx .. '|' .. sy
	if p.stackAt ~= key then
		p.stack:ClearAllPoints()
		p.stack:SetPoint('CENTER', p.face, 'CENTER', sx, sy)
		p.stack:SetJustifyH('CENTER')
		p.stackAt = key
	end
end

-- ---------------------------------------------------------------------------
-- The holder and where it sits
-- ---------------------------------------------------------------------------

local holder, sample
-- [i] = the container bound to UNITS[i], in build order.
local containers = {}
-- [i] = true while that container is switched on.
local enabledOn = {}
-- Our face on every engine button.
local buttons = {}
local failed, bindFailed
local preview = false
local stylePending = false
local tracking = false
local lastWanted
local QueueScan

local function TailAnchored(cfg)
	return cfg.euiAnchor and (cfg.euiPlace or 'CENTER') ~= 'CENTER'
end

-- On an EllesmereUI buff group when that is asked for and one is found, on
-- its free screen position otherwise - The Blood is Life's rule.
local function Place(cfg)
	local grp = cfg.euiAnchor and ns.CDMResolveGroup(cfg) or nil
	local placed = false
	if grp then
		local ok, done = pcall(ns.CDMAnchorTo, holder, cfg)
		placed = ok and done and true or false
	end
	if not placed then
		holder:ClearAllPoints()
		holder:SetPoint('CENTER', UIParent, 'CENTER', cfg.x or 0, cfg.y or DEFAULTS.y)
	end
	if grp then
		local okL, lvl = pcall(grp.GetFrameLevel, grp)
		if okL and lvl and holder:GetFrameLevel() ~= lvl + 10 then
			pcall(holder.SetFrameLevel, holder, lvl + 10)
		end
	end
end

local function EnsureHolder()
	if holder then return end
	-- Named, like every movable frame in the addon.
	holder = CreateFrame('Frame', 'XerionUIReapersMark', UIParent)
	holder:SetFrameStrata('MEDIUM')
	holder:SetSize(44, 44)
	holder:SetClampedToScreen(true)
	holder:SetMovable(true)
	holder:EnableMouse(false)
	holder:RegisterForDrag('RightButton')

	-- A drag writes the group offsets while the icon rides a group, the free
	-- position otherwise (The Blood is Life's drag).
	local dragCX, dragCY
	holder:SetScript('OnDragStart', function(self)
		if GetCfg().lock then return end
		dragCX, dragCY = self:GetCenter()
		self:StartMoving()
	end)
	holder:SetScript('OnDragStop', function(self)
		self:StopMovingOrSizing()
		local cfg = GetCfg()
		local cx, cy = self:GetCenter()
		if cfg.euiAnchor then
			if cx and dragCX then
				cfg.euiOffsetX = (cfg.euiOffsetX or 0) + Round(cx - dragCX)
				cfg.euiOffsetY = (cfg.euiOffsetY or 0) + Round(cy - dragCY)
			end
		elseif cx then
			local ux, uy = UIParent:GetCenter()
			if ux then
				cfg.x = Round(cx - ux)
				cfg.y = Round(cy - uy)
			end
		end
		dragCX, dragCY = nil, nil
		if ns.RKMApply then ns.RKMApply() end
	end)
	-- the holder is one icon; the rest of the row is grabbable through this
	ns.DragAnywhere(holder)
	holder:Hide()
end

-- TAIL RE-ANCHOR, RATIONED (The Blood is Life's ticker)
-- A tail placement uses a different point of the group's bar when the bar
-- goes empty or fills up again, and Lua never learns when the mark itself is
-- up, so the check runs whenever a tail placement is on: each tick reads one
-- field off the bar found last time and re-anchors at once when it flipped; a
-- full re-anchor, which also catches a different bar, runs at most every
-- ANCHOR_EVERY seconds.
local ANCHOR_EVERY = 0.5
local anchorBar, anchorEmpty
local anchorAt = 0
local ticker

local function BarEmpty(bar)
	local w = bar._acLiveW
	if secret(w) then return nil end
	if w == nil then return false end
	return w <= 0.5
end

local function ForgetAnchor() anchorBar, anchorEmpty, anchorAt = nil, nil, 0 end

local function Tick()
	if not holder then return end
	local cfg = GetCfg()
	if not TailAnchored(cfg) then return end
	local now = GetTime()
	local stale = (now - anchorAt) >= ANCHOR_EVERY
	if not stale and anchorBar then
		local empty = BarEmpty(anchorBar)
		stale = empty == nil or empty ~= anchorEmpty
	end
	if stale then
		Place(cfg)
		anchorBar = ns.CDMResolveGroup(cfg)
		anchorEmpty = anchorBar and BarEmpty(anchorBar)
		anchorAt = now
	end
end

local function SyncTicker(want)
	if want and not ticker then
		Tick()
		ticker = C_Timer.NewTicker(0.1, Tick)
	elseif not want and ticker then
		ticker:Cancel()
		ticker = nil
	end
end

-- ---------------------------------------------------------------------------
-- The engine's part
-- ---------------------------------------------------------------------------

-- Runs inside the engine's frame creation: an error here would take the slot
-- down with it, so everything optional is armoured.
local function InitSlot(b)
	-- Display only. A button takes the mouse by default and would swallow
	-- clicks on the play field while the mark is up.
	pcall(b.SetMouseClickEnabled, b, false)
	pcall(b.SetMouseMotionEnabled, b, false)
	-- Nothing hangs off this size; the face carries its own.
	pcall(b.SetSize, b, 1, 1)
	-- Placed here, once, while it is still ours to place: every unit's slot on
	-- the holder's centre, so any mob's mark lights the same icon.
	pcall(b.SetPoint, b, 'CENTER', holder, 'CENTER', 0, 0)
	local p = MakeFace(b)
	pcall(StyleFace, p, GetCfg())
	local ok, err = pcall(b.SetDurationCooldown, b, p.cd)
	if not ok then bindFailed = 'swipe: ' .. tostring(err) end
	ok, err = pcall(b.SetDurationText, b, p.dur, ns.DurationTextOptions())
	if not ok then bindFailed = 'seconds: ' .. tostring(err) end
	ok, err = pcall(b.SetApplicationCount, b, p.stack)
	if not ok then bindFailed = 'stacks: ' .. tostring(err) end
	buttons[#buttons + 1] = p
end

-- The container for UNITS[i], switched off; a slot takes no part in any
-- layout, so the container itself is just a 1x1 point on the holder.
local function Build(i)
	local ok, c = pcall(CreateFrame, 'AuraContainer', nil, holder, 'CustomAuraContainerTemplate')
	if not ok or not c then
		failed = 'the client refused the AuraContainer frame'
		return false
	end
	c:SetSize(1, 1)
	c:SetPoint('CENTER', holder, 'CENTER', 0, 0)
	pcall(c.SetEnabled, c, false)
	local okS, errS = pcall(c.AddAuraSlot, c, SLOT_KEY, FILTER, {
		candidateFilters = { includeSpellIDs = { [DEBUFF] = true } },
		initializeFrame = InitSlot,
	})
	if not okS then
		failed = 'aura slot refused: ' .. tostring(errS)
		c:Hide()
		return false
	end
	local okU, errU = pcall(c.SetUnit, c, UNITS[i])
	if not okU then
		failed = 'unit ' .. UNITS[i] .. ' refused: ' .. tostring(errU)
		c:Hide()
		return false
	end
	containers[i] = c
	return true
end

-- The background builder: BUILD_STEP containers a frame until every unit has
-- one. Only runs while the icon is wanted.
local builder = CreateFrame('Frame')
builder:Hide()
builder:SetScript('OnUpdate', function(self)
	if failed or not holder or not Wanted(GetCfg()) then
		self:Hide()
		return
	end
	for _ = 1, BUILD_STEP do
		local i = #containers + 1
		if i > #UNITS then
			self:Hide()
			break
		end
		if not Build(i) then
			self:Hide()
			break
		end
	end
	QueueScan()
end)

-- ---------------------------------------------------------------------------
-- Which units are watched
-- ---------------------------------------------------------------------------

-- Why a unit's container stays off, or nil when it is switched on. An
-- unreadable answer lets the unit through (the addon's rule), except for "can
-- I assist it": on a unit you can assist the engine skips the spell filter
-- and ANY debuff of yours would light the icon, so only a plain "no" counts.
local function Verdict(unit)
	if Ask(UnitExists, unit) ~= true then return 'no such unit' end
	if Ask(UnitCanAttack, 'player', unit) == false then return 'not attackable' end
	if Ask(UnitCanAssist, 'player', unit) ~= false then return 'friendly, or the client would not say' end
	if Ask(UnitIsDeadOrGhost, unit) == true then return 'dead' end
	return nil
end

-- Whether some enemy nameplate is the target - or might be: an unreadable
-- comparison counts as yes, which leaves the target to its nameplate.
local function TargetHasPlate()
	for i = 1, TARGET_SLOT - 1 do
		local plate = UNITS[i]
		if Ask(UnitExists, plate) == true and Ask(UnitIsUnit, 'target', plate) ~= false then
			return true
		end
	end
	return false
end

local function Why(i)
	local why = Verdict(UNITS[i])
	if why then return why end
	if i == TARGET_SLOT and TargetHasPlate() then
		return 'its nameplate shows the mark (or the client would not say)'
	end
	return nil
end

-- Switches container i on or off. `reread` asks an already running container
-- to read its unit again: the token now points at another mob. Switching on
-- reads the unit by itself (AuraContainerSharedMixin:SetEnabled), and
-- UpdateAllAuras is the engine's own door for "the target changed".
local function Refresh(i, reread)
	local c = containers[i]
	if not c then return end
	local on = tracking and Why(i) == nil
	if on then
		if not enabledOn[i] then
			if pcall(c.SetEnabled, c, true) then enabledOn[i] = true end
		elseif reread then
			pcall(c.UpdateAllAuras, c)
		end
	elseif enabledOn[i] then
		pcall(c.SetEnabled, c, false)
		enabledOn[i] = nil
	end
end

local function Rescan()
	for i = 1, #containers do Refresh(i, false) end
end
QueueScan = ns.Coalesce(Rescan)

-- UNIT_FLAGS names one unit and fires on every combat flip, stun or death;
-- only that unit's container can change, asked once on the next frame.
local flagged = {}
local function RecheckFlagged()
	for i in pairs(flagged) do Refresh(i, false) end
	wipe(flagged)
end
local QueueFlagged = ns.Coalesce(RecheckFlagged)

-- A target change is read again on the next frame too, the way Fiery Brand's
-- target slot does it: the first read can land before the unit has settled.
local function RereadTarget() Refresh(TARGET_SLOT, true) end
-- A nameplate coming or going may be the target's: the target's slot is
-- asked again once, on the next frame, for a whole burst of plate events.
local QueueTarget = ns.Coalesce(function() Refresh(TARGET_SLOT, false) end)

local watch = CreateFrame('Frame')
watch:SetScript('OnEvent', function(_, event, unit)
	if event == 'PLAYER_TARGET_CHANGED' then
		Refresh(TARGET_SLOT, true)
		C_Timer.After(0, RereadTarget)
		return
	end
	local i = unit and SLOT_OF[unit]
	if not i then return end
	if event == 'NAME_PLATE_UNIT_REMOVED' then
		-- Off at once, not on the next frame: the token can be handed to a
		-- different mob within this one, and the flip back on is what makes the
		-- container read the new mob.
		if enabledOn[i] then
			pcall(containers[i].SetEnabled, containers[i], false)
			enabledOn[i] = nil
		end
		QueueTarget()
	elseif event == 'NAME_PLATE_UNIT_ADDED' then
		Refresh(i, true)
		QueueTarget()
	else
		flagged[i] = true
		QueueFlagged()
	end
end)

local WATCH_EVENTS = { 'NAME_PLATE_UNIT_ADDED', 'NAME_PLATE_UNIT_REMOVED', 'UNIT_FLAGS', 'PLAYER_TARGET_CHANGED' }

local function StartTracking()
	if tracking then return end
	tracking = true
	for _, e in ipairs(WATCH_EVENTS) do watch:RegisterEvent(e) end
end

local function StopTracking()
	if not tracking then return end
	tracking = false
	watch:UnregisterAllEvents()
	wipe(flagged)
	for i = 1, #containers do Refresh(i, false) end
end

-- ---------------------------------------------------------------------------
-- Apply, the preview and the options-side entry points
-- ---------------------------------------------------------------------------

-- Settings changes reach our faces only. Should the client refuse one, it
-- waits for the fight or the key to end.
local function Restyle(cfg)
	stylePending = false
	for _, p in ipairs(buttons) do
		if not pcall(StyleFace, p, cfg) then stylePending = true end
	end
end

-- A key whose last fight ended before the timer stopped lifts its restriction
-- with no PLAYER_REGEN_ENABLED after it, so a refused restyle also retries on
-- the restriction's own change event. On the next frame: the state still reads
-- the old value while that event is being handed out (LustPots' sounds).
local QueueRestyle = ns.Coalesce(function()
	if stylePending and holder then Restyle(GetCfg()) end
end)

-- The preview: a face of our own over the engine's, frozen at 8 of 12 seconds
-- and 23 stacks, since the engine only draws while a real mark is up.
local function StyleSample(cfg)
	-- Built the first time the preview is asked for: with it off the sample is
	-- only ever hidden, and the preview's own Apply comes through here with it
	-- on, before the holder is shown.
	if not sample and not preview then return end
	if not sample then
		local f = CreateFrame('Frame', nil, holder)
		f:SetSize(1, 1)
		f:SetPoint('CENTER', holder, 'CENTER', 0, 0)
		sample = MakeFace(f)
		sample.host = f
	end
	sample.host:SetFrameLevel(holder:GetFrameLevel() + 20)
	StyleFace(sample, cfg)
	sample.dur:SetText(tostring(PREVIEW_SECS))
	sample.stack:SetText(tostring(PREVIEW_STACKS))
	sample.host:SetShown(preview)
	if preview then
		sample.cd:SetCooldown(GetTime() - (PREVIEW_DURATION - PREVIEW_SECS), PREVIEW_DURATION)
		if sample.cd.Pause then pcall(sample.cd.Pause, sample.cd) end
	end
end

local function Apply()
	local cfg = GetCfg()
	local wanted = Wanted(cfg)
	lastWanted = wanted
	if not (wanted or preview) then
		StopTracking()
		builder:Hide()
		SyncTicker(false)
		if holder then holder:Hide() end
		return
	end

	EnsureHolder()
	holder:SetSize(Width(cfg), Height(cfg))
	pcall(holder.SetFrameStrata, holder, cfg.strata or 'MEDIUM')
	Place(cfg)
	ForgetAnchor()
	StyleSample(cfg)
	if wanted then
		Restyle(cfg)
		if not failed and #containers < #UNITS then builder:Show() end
	end

	local live = wanted and not preview
	-- Shown while live even though it draws nothing itself: a container only
	-- works while it is visible (ShouldRegisterForDynamicEvents).
	holder:Show()
	holder:EnableMouse(preview and not cfg.lock or false)
	if live then
		StartTracking()
		Rescan()
	else
		StopTracking()
	end
	SyncTicker(TailAnchored(cfg))
end

-- A dragged slider asks many times a frame; one Apply answers all of them.
ns.RKMApply = ns.Coalesce(Apply)

ns.RKMIsPreview = function() return preview end
-- No class check: the preview is only a drawing and the user tests pages on
-- whatever alt is logged in. Apply already keeps the live path off for anyone
-- but a Death Knight (Wanted asks the class).
ns.RKMSetPreview = function(state)
	preview = state and true or false
	Apply()
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local evt = CreateFrame('Frame')
evt:RegisterEvent('PLAYER_ENTERING_WORLD')
evt:RegisterEvent('PLAYER_REGEN_ENABLED')
pcall(evt.RegisterEvent, evt, 'ADDON_RESTRICTION_STATE_CHANGED')
evt:RegisterEvent('SPELLS_CHANGED')
pcall(evt.RegisterEvent, evt, 'TRAIT_CONFIG_UPDATED')
evt:RegisterUnitEvent('PLAYER_SPECIALIZATION_CHANGED', 'player')
evt:SetScript('OnEvent', function(self, event)
	-- Not a Death Knight: Wanted() asks the class, so every event here would be
	-- a no-op (the preview needs none of them). They go for the session - the
	-- class never changes (Shaman.lua's rule).
	if not IsDeathKnight() then
		self:UnregisterAllEvents()
		return
	end
	if event == 'PLAYER_ENTERING_WORLD' then
		-- A loading screen hands out every nameplate token afresh, and leaving a
		-- key is when the engine's buttons take changes again. EllesmereUI
		-- builds its groups late, so a group anchor is asked again after that.
		C_Timer.After(0.5, ns.RKMApply)
		C_Timer.After(3, function()
			if GetCfg().euiAnchor then ns.RKMApply() end
		end)
	elseif event == 'PLAYER_REGEN_ENABLED' then
		if stylePending and holder then Restyle(GetCfg()) end
	elseif event == 'ADDON_RESTRICTION_STATE_CHANGED' then
		if stylePending then QueueRestyle() end
	else
		-- A talent or spec change: only a change of "is it wanted" needs work.
		if Wanted(GetCfg()) ~= lastWanted then ns.RKMApply() end
	end
end)

-- ---------------------------------------------------------------------------
-- Diagnostics
--
-- Whether a mob carries the mark is the one thing this cannot print - that is
-- the secret. Everything around it can: the gates, how far the builder got,
-- which units are watched and why the others are not, the anchor, and the
-- debuff's secrecy level.
-- ---------------------------------------------------------------------------

local SECRECY = { [0] = 'never secret', [1] = 'always secret', [2] = 'secret in keys and raids' }

_G.SLASH_XERIONREAPER1 = '/xerionreaper'
_G.SlashCmdList.XERIONREAPER = function(msg)
	msg = type(msg) == 'string' and msg:lower() or ''
	if msg:find('opt') or msg:find('config') or msg:find('setting') then
		if ns.ShowConfig then ns.ShowConfig('class_dk') end
		C_Timer.After(0.2, function()
			if ns.ShowConfigSubTab then ns.ShowConfigSubTab('class_dk', PAGE_TITLE) end
		end)
		return
	end

	local function p(...) print('|cffff7d0aXerionUI-ReapersMark|r', ...) end
	local cfg = GetCfg()
	p('enable =', cfg.enable and 'on' or 'off', '| preview =', preview and 'ON' or 'off',
		'| death knight =', IsDeathKnight() and 'yes' or 'no',
		'| talented =', ns.SpellKnown(CAST) and 'yes' or '|cffff5555no|r',
		'| aura containers =', ns.RKMUnavailable and '|cffff5555unavailable|r' or 'ok',
		'| tracking =', tracking and 'yes' or 'no')
	p('containers =', #containers, 'of', #UNITS, '| builder =', builder:IsShown() and 'running' or 'idle',
		'| engine buttons =', #buttons,
		stylePending and '|cffff5555(restyle waits for the fight or the key to end)|r' or '')

	local on = {}
	for i = 1, #containers do
		if enabledOn[i] then
			local unit = UNITS[i]
			local ok, name = pcall(UnitName, unit)
			on[#on + 1] = (ok and type(name) == 'string' and not secret(name)) and (unit .. ' (' .. name .. ')') or unit
		end
	end
	p('watching:', #on > 0 and tconcat(on, ', ') or '|cff888888nothing|r')
	for i, unit in ipairs(UNITS) do
		if not enabledOn[i] and Ask(UnitExists, unit) == true then
			local why = Why(i)
			if not why then
				why = not containers[i] and 'its container is not built yet'
					or (not tracking and 'not tracking') or 'waiting for the next scan'
			end
			p('  not watched:', unit, '|cffff5555' .. why .. '|r')
		end
	end

	if cfg.euiAnchor then
		p('position:', ns.CDMAnchorStatus(cfg), '| placement', cfg.euiPlace or 'CENTER')
	else
		p('position: free,', cfg.x or 0, cfg.y or 0)
	end

	local CS = _G.C_Secrets
	if CS and CS.GetSpellAuraSecrecy then
		local ok, lvl = pcall(CS.GetSpellAuraSecrecy, DEBUFF)
		local text = (ok and not secret(lvl)) and (tostring(lvl) .. ' = ' .. (SECRECY[lvl] or 'unknown')) or 'unreadable'
		p('debuff ' .. DEBUFF .. ' aura secrecy:', text)
	end
	if failed then p('|cffff5555stopped: ' .. failed .. '|r') end
	if bindFailed then p('|cffff5555binding refused: ' .. bindFailed .. '|r') end
	p('the icon is |cff66dd66up to the engine|r - drawn while your mark is up on a watched unit')
end
