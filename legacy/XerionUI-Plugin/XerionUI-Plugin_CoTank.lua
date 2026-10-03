-- WHY THIS FILE EXISTS
--
-- Tanking a raid boss means watching one health bar that is not yours, and the
-- raid frames are the wrong tool for it: the co-tank is one row among twenty,
-- wherever the sort order put them this week. This is that one bar, where you
-- want it, at the size you want, with the boss's debuffs on them next to it -
-- which is the whole of a taunt swap: their stacks, their timer.
--
-- WHAT IT DOES
--
-- In a raid group, while you are tank-specced (a switch, on by default), it
-- finds the other tank, draws their health as a class-coloured bar and hangs a
-- row of their debuffs off it. The debuffs are never read by this addon - in an encounter they are
-- secret - so the row is an AuraContainer the engine fills in by itself.
--
-- It is a display, not a unit frame: it cannot be clicked to target. A
-- clickable unit frame is a secure frame, its unit cannot change in combat,
-- and a tank dying mid-pull is exactly when the unit would need to change.
--
-- WHAT THE FIRST VERSION GOT WRONG (it was retired to _to_delete for it)
--
-- 1. It did its work in the wrong place. Every UNIT_HEALTH tick and a
--    half-second ticker re-walked all forty raid slots, re-anchored the debuff
--    row and re-pushed the container's settings. Now the roster is walked on
--    roster events, the health events touch the bar and nothing else, and the
--    row is only ever laid out by a settings change.
-- 2. It failed closed. A role the client would not read counted as "not a
--    tank", so the one moment the answer went unreadable the bar hid itself.
--    An unreadable answer now keeps whoever was already on the bar.
-- 3. It ran everywhere. Frames, the container and its ten engine buttons were
--    built at login and poked on every group event in a five-man, where there
--    is no co-tank to find - a key is where its errors came from. Nothing is
--    built now until a raid actually has a second tank in it, and battlegrounds
--    (raid groups too) are skipped outright.
-- 4. "Boss debuffs only" could not be switched. Candidate filters are fixed
--    when a group is declared; SetAuraGroupCandidateFilters on a live group
--    does not retake (EllesmereUI documents the same from the field). There
--    are two groups now, one filtered and one not, and the setting moves the
--    frame budget between them, which does take effect live.
-- 5. The dispel border asked for the engine's Border style while the comment
--    described PreserveAsset, so Blizzard's atlas was stamped over our art,
--    and showWithoutDispelType was off - boss tank debuffs almost never carry
--    a dispel type, so the border showed on next to nothing.
-- 6. The layout stride (elementWidth/Height, spacing) was set once at creation,
--    so changing the icon size left the icons spaced for the old size.
-- 7. On a client without the AuraContainer frame type the failed creation was
--    retried on every tick, leaking a named holder frame each time.
-- 8. The icons took mouse clicks, in the middle of the play field, to show a
--    tooltip. They take motion only now, so a click goes through to the world.
-- 9. A raid token is a slot, not a person: after a roster change raid7 can be
--    somebody else, and SetUnit with the same string is a no-op. The container
--    is told to re-read on every roster change.
-- 10. Growing up or down set the flow axis to vertical AND a line size of 1.
--    The line size is measured along the primary axis, so on a vertical axis
--    it means "one icon per column" - the two cancelled out and the row came
--    out horizontal. The line size is only the fallback now, for a client
--    that has no axis call.
--
-- WHY THE ROW WATCHES THE ENGINE
--
-- A raid reported the row working through the first boss and never again.
-- Blizzard's container does its work in a one-shot OnUpdate that it arms only
-- on the step from clean to dirty (DirtyPhaseMixin, RunWhenVisibleOnce - which
-- resets itself to Disabled before it runs). If anything in that pass throws,
-- the container is left dirty and unarmed: every later aura marks it dirty
-- again, which is no step, so nothing re-arms it and the row stays frozen
-- until a reload. That state has one readable sign - dirty but not armed - and
-- the slow ticker looks for it: it asks for a layout, which marks the
-- container dirty, and reads GetOnUpdateMode. A working container is armed
-- after that request; a frozen one still says Disabled and is replaced by a
-- new one. The old one is hidden, never reused: a pass that died half-way can
-- leave buttons shown that nothing will ever release.
--
-- Two quieter ways the row went stale are closed beside it. The container's
-- own unit is compared now, not our note of what we last sent it, so a
-- refused SetUnit is retried instead of remembered as done. And a co-tank who
-- comes back into sight (a runback, a disconnect, out of range) gets a
-- re-read, because UNIT_AURA stops for a unit nobody can see and nothing is
-- sent when they reappear - EllesmereUI's raid frames run the same net.
--
-- The same report was on "Boss debuffs only", and that filter was the other
-- half of it: it asked for isBossAura alone. Blizzard marks a tank debuff as a
-- tank ROLE aura at least as often as a boss aura, and everything Blizzard
-- draws big - raid frames, private aura anchors, ProcessAura - tests the two
-- together (AuraUtil.IsRoleAura). So a fight whose tank debuff was flagged
-- boss worked, and the next one's, flagged role, never reached the row. The
-- group now asks isBossOrRoleAura, the engine's own name for that pair,
-- which is also what EllesmereUI's boss tile uses.

local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('CoTank', hooksecurefunc, C_Timer)
local _G = _G

local CreateFrame = CreateFrame
local UIParent = UIParent
local C_Timer = C_Timer
local C_ClassColor = C_ClassColor
local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit
local UnitName = UnitName
local UnitClass = UnitClass
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitHealthPercent = UnitHealthPercent
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsConnected = UnitIsConnected
local UnitIsVisible = UnitIsVisible
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local GetPartyAssignment = GetPartyAssignment
local IsInRaid = IsInRaid
local IsInInstance = IsInInstance
local GetTime = GetTime
local ipairs, pairs, pcall, type, tostring = ipairs, pairs, pcall, type, tostring
local sformat = string.format
local mmax = math.max

local secret = ns.IsSecret
local IS_121 = ns.IS_121

-- Group roles are how the OTHER tank is identified; a client without that call
-- cannot answer the only question this module asks.
ns.hasCoTank = UnitGroupRolesAssigned and true or false
if not ns.hasCoTank then return end

-- The bar works on 12.0. The debuff row needs CustomAuraContainerTemplate,
-- which is 12.1, and there is no fallback: reading the co-tank's debuffs from
-- Lua is exactly what an encounter forbids.
ns.CoTNoDebuffs = not IS_121

local WHITE = 'Interface\\Buttons\\WHITE8X8'

local DEFAULTS = {
	enable = false,
	lock = false,
	x = 0,
	y = 200,
	width = 200,
	height = 22,
	-- Blank is automatic. A name here wins over the role walk, for the night
	-- three people carry the tank role or the roles were never set at all.
	pinName = '',
	-- On, the bar only exists while you are tank-specced - it is for the swap.
	-- Off, a healer or a raid lead gets it on the first tank that is not them.
	tankOnly = true,

	nameSize = 12,
	namePoint = 'LEFT',
	nameX = 4,
	nameY = 0,

	healthShow = true,
	healthSize = 12,
	healthPoint = 'RIGHT',
	healthX = -4,
	healthY = 0,

	bgAlpha = 0.25,

	debuffEnable = true,
	debuffBossOnly = false,
	debuffMax = 5,
	debuffSize = 26,
	debuffSpacing = 3,
	debuffGrow = 'RIGHT',
	debuffAttach = 'BOTTOMLEFT',
	debuffX = 0,
	debuffY = -4,
	debuffBorder = true,
	debuffBorderSize = 2,
	debuffTooltip = true,

	durShow = true,
	durSize = 12,
	durPoint = 'CENTER',
	durX = 0,
	durY = 0,

	stackShow = true,
	stackSize = 11,
	stackPoint = 'BOTTOMRIGHT',
	stackX = 0,
	stackY = 0,
}

local function GetCfg() return ns.ModuleCfg('cotank', DEFAULTS) end
ns.CoTGetCfg = GetCfg

-- ---------------------------------------------------------------------------
-- Who the co-tank is
-- ---------------------------------------------------------------------------

local RAID = {}
for i = 1, 40 do RAID[i] = 'raid' .. i end

-- The token the bar is on. Re-derived by the roster events and the slow
-- ticker, never by a health tick.
local coUnit

-- YOUR role comes from your spec, not from the group. The role you listed a
-- group under sticks server-side through a respec, so UnitGroupRolesAssigned
-- on 'player' can say TANK for a dps, and says NONE in a raid nobody ran a
-- role check in. Unreadable means allow - the addon's rule everywhere.
local function PlayerIsTank()
	local spec, unreadable = ns.PlayerSpec()
	if unreadable then return true end
	if not spec then return false end
	local get = _G.GetSpecializationRole
	if not get then return true end
	local ok, role = pcall(get, spec)
	if not ok or secret(role) then return true end
	return role == 'TANK'
end

-- true, false, or nil when the client would not say. For everyone else the
-- group role is all there is: the spec API answers for the player only. The
-- raid leader's Main Tank mark covers the guild raid that never set roles.
local function IsTankUnit(unit)
	local ok, role = pcall(UnitGroupRolesAssigned, unit)
	if not ok or secret(role) then return nil end
	if role == 'TANK' then return true end
	if role == 'NONE' and GetPartyAssignment then
		local okA, mt = pcall(GetPartyAssignment, 'MAINTANK', unit)
		if okA and not secret(mt) and mt then return true end
	end
	return false
end

local function PinnedName(cfg)
	local want = ns.Trim(cfg.pinName)
	if want == '' then return nil end
	-- "Name-Realm" is how it reads in chat; UnitName hands back the name alone
	return want:match('^[^%-]+') or want
end

local function NameMatches(unit, want)
	local name = UnitName(unit)
	if secret(name) or type(name) ~= 'string' then return false end
	return name == want or name:lower() == want:lower()
end

local function FindCoTank()
	if not IsInRaid() then return nil end
	-- A battleground is a raid group too, and the health calls below take a
	-- PvP-restricted unit token there.
	local _, itype = IsInInstance()
	if itype == 'pvp' or itype == 'arena' then return nil end

	local cfg = GetCfg()
	local want = PinnedName(cfg)
	local tankGate = cfg.tankOnly ~= false
	-- Without a pinned name the walk below can only ever feed the tank branch
	-- after the PlayerIsTank() check, so a dps asks that first and skips forty
	-- slots of reads on every roster event of the night. Same answer: the walk
	-- only reads, and PlayerIsTank reads nothing the walk would change.
	if not want and tankGate and not PlayerIsTank() then return nil end
	local pinned, first, kept, unknown
	for i = 1, 40 do
		local u = RAID[i]
		if UnitExists(u) then
			-- Against 'player' is the one comparison the client always permits.
			-- A secret answer is skipped, not guessed: the bar must never be you.
			local same = UnitIsUnit(u, 'player')
			if not secret(same) and not same then
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
	if want and tankGate and not PlayerIsTank() then return nil end -- unpinned: asked above
	-- Whoever is already on the bar stays on it while they still qualify, so
	-- three tank roles in the raid do not make it hop on every roster event.
	if kept or first then return kept or first end
	if unknown and coUnit and UnitExists(coUnit) then return coUnit end
	return nil
end

local function ClassColor(unit)
	local _, class = UnitClass(unit)
	-- secret() FIRST: `not class` on a secret value is itself the error
	if secret(class) or not class then return 0.6, 0.6, 0.6 end
	if C_ClassColor and C_ClassColor.GetClassColor then
		local cc = C_ClassColor.GetClassColor(class)
		if cc and cc.r then return cc.r, cc.g, cc.b end
	end
	local t = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]
	if t and t.r then return t.r, t.g, t.b end
	return 0.6, 0.6, 0.6
end

-- ---------------------------------------------------------------------------
-- The bar
-- ---------------------------------------------------------------------------

local frame, bar, bg, nameFS, hpFS
local holder
local preview = false
-- `/xerioncotank test`: the live bar and the real engine row on your target (or
-- you), no raid and no second tank needed. Session only, never saved.
local testMode = false
-- What PaintIdentity last put on the bar, so the 2 s ticker does not repaint
-- the same name and colour every run. Readable values only: a secret name is
-- written through and leaves paintedName nil. ApplyVisual clears both,
-- because a settings pass re-textures the bar and changes bgAlpha.
local paintedName, paintedR, paintedG, paintedB, paintedA

local POINTS = {
	TOPLEFT = { 1, -1 }, TOP = { 0, -1 }, TOPRIGHT = { -1, -1 },
	LEFT = { 1, 0 }, CENTER = { 0, 0 }, RIGHT = { -1, 0 },
	BOTTOMLEFT = { 1, 1 }, BOTTOM = { 0, 1 }, BOTTOMRIGHT = { -1, 1 },
}

-- Validated, not trusted: an unknown point reaching SetPoint is a hard error,
-- and an imported profile is exactly where one comes from.
local function Point(p, fallback) return POINTS[p] and p or fallback end

local function ApplyPosition()
	if not frame then return end
	local cfg = GetCfg()
	frame:ClearAllPoints()
	frame:SetPoint('CENTER', UIParent, 'CENTER', cfg.x or 0, cfg.y or 200)
end

local function ApplyVisual()
	if not frame then return end
	local cfg = GetCfg()
	paintedName, paintedR = nil, nil -- the next PaintIdentity paints in full
	frame:SetSize(mmax(40, cfg.width or 200), mmax(6, cfg.height or 22))
	bar:SetStatusBarTexture(ns.BarTexture())
	bg:SetTexture(ns.BarTexture())

	local font = ns.GothamNarrowBlackFont()
	nameFS:SetFont(font, cfg.nameSize or 12, 'OUTLINE')
	hpFS:SetFont(font, cfg.healthSize or 12, 'OUTLINE')

	local np, hp = Point(cfg.namePoint, 'LEFT'), Point(cfg.healthPoint, 'RIGHT')
	nameFS:ClearAllPoints()
	nameFS:SetPoint(np, bar, np, cfg.nameX or 4, cfg.nameY or 0)
	hpFS:ClearAllPoints()
	hpFS:SetPoint(hp, bar, hp, cfg.healthX or -4, cfg.healthY or 0)
	-- Off means transparent: the fill is the reading, the number is a second
	-- opinion on it.
	hpFS:SetAlpha(cfg.healthShow == false and 0 or 1)

	ApplyPosition()
end

local function EnsureFrame()
	if frame then return end
	-- Named, because edit mode looks the frame up by this exact string.
	frame = CreateFrame('Frame', 'XerionUICoTank', UIParent)
	frame:SetFrameStrata('MEDIUM')
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(false)
	frame:RegisterForDrag('RightButton')
	frame:Hide()
	ns.MakeDraggable(frame, GetCfg, 'x', 'y', ApplyPosition)

	-- One black rectangle with the bar inset a pixel over it: four edge strips
	-- can show a gap in a corner, a single texture cannot.
	bg = ns.PixelBorderIcon(frame, 'BACKGROUND', 1)

	bar = CreateFrame('StatusBar', nil, frame)
	bar:SetPoint('TOPLEFT', 1, -1)
	bar:SetPoint('BOTTOMRIGHT', -1, 1)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)

	nameFS = bar:CreateFontString(nil, 'OVERLAY')
	hpFS = bar:CreateFontString(nil, 'OVERLAY')

	-- The debuff row is a CHILD of the bar. Hiding the bar hides the row, and
	-- a container that is not visible drops its aura events by itself
	-- (AuraContainerPrivateMixin:ShouldRegisterForDynamicEvents), so there is
	-- no second show/hide to keep in step with the first.
	holder = CreateFrame('Frame', 'XerionUICoTankDebuffs', frame)
	holder:SetSize(1, 1)
	holder:SetFrameLevel(frame:GetFrameLevel() + 5)

	ApplyVisual()
end

-- UnitHealthPercent hands back 0..1, still secret; scaling it is arithmetic we
-- may not do, so the client does it through a curve. Blizzard ships the one we
-- want, and EllesmereUI prints its health text the same way.
local pctCurve
local function HealthCurve()
	if pctCurve ~= nil then return pctCurve or nil end
	local CC = _G.CurveConstants
	pctCurve = (CC and CC.ScaleTo100) or false
	return pctCurve or nil
end

-- THE HEALTH NEVER BECOMES A NUMBER THIS ADDON CAN SEE. UnitHealth is secret
-- for every caller, so it goes straight into the widget: SetValue,
-- SetMinMaxValues and SetFormattedText all accept secrets from addon code.
-- The consequence is no branching on health - no "red below 35%".
local function PaintHealth(unit)
	bar:SetMinMaxValues(0, UnitHealthMax(unit))
	bar:SetValue(UnitHealth(unit))

	local connected = UnitIsConnected(unit)
	local dead = UnitIsDeadOrGhost(unit)
	if not secret(connected) and connected == false then
		hpFS:SetText('|cff888888off|r')
	elseif not secret(dead) and dead then
		hpFS:SetText('|cffff4444dead|r')
	else
		local curve = UnitHealthPercent and HealthCurve()
		if curve then
			hpFS:SetFormattedText('%d%%', UnitHealthPercent(unit, true, curve))
		else
			hpFS:SetText('')
		end
	end
end

local healthErr
local function UpdateHealth()
	if preview or not (frame and coUnit) then return end
	local ok, err = pcall(PaintHealth, coUnit)
	if not ok then
		healthErr = err
		hpFS:SetText('')
	end
end

local function PaintIdentity(unit)
	local cfg = GetCfg()
	-- ClassColor only hands back numbers it read in the clear (grey for a
	-- secret class), so comparing them is safe
	local r, g, b = ClassColor(unit)
	local a = cfg.bgAlpha or 0.25
	if r ~= paintedR or g ~= paintedG or b ~= paintedB or a ~= paintedA then
		paintedR, paintedG, paintedB, paintedA = r, g, b, a
		bar:SetStatusBarColor(r, g, b, 1)
		bg:SetVertexColor(r * 0.35, g * 0.35, b * 0.35, a)
	end
	-- SetText takes a secret as it is; only a missing name needs a stand-in
	local name = UnitName(unit)
	if secret(name) then
		paintedName = nil
		nameFS:SetText(name)
	else
		local text = name or _G.UNKNOWN or '?'
		if text ~= paintedName then
			paintedName = text
			nameFS:SetText(text)
		end
	end
end

-- ---------------------------------------------------------------------------
-- The boss debuffs
--
-- We never see them. C_UnitAuras hands back secrets for the whole of an
-- encounter, so the row is built the other way round: we make the widgets, the
-- engine decides which aura goes in which button, sets the icon, runs the
-- swipe, writes the stacks and tints the border. Per-spell anything is out of
-- reach - spell ID filters are skipped for debuffs on a unit you can assist,
-- bar the few never-secret ones (see NoiseFilter) - so boss-or-role-or-not is
-- the finest grain there is.
-- ---------------------------------------------------------------------------

local container, containerFailed
local groupOK = {}
-- Why the client said no, kept for the readout: "refused" alone sent the last
-- report round in circles.
local containerErr
local groupErr = {}
-- Our own records of the engine's buttons. The records are ours and always
-- readable; the frames inside them turn forbidden while auras are secret, so
-- every touch goes through a pcall and a refused pass is retried after combat.
local buttons = {}
local stylePending = false
local styledLast = 0
-- Containers replaced after a stall (see WHY THE ROW WATCHES THE ENGINE). Each
-- one leaves its frames behind for good, so the automatic replacements are
-- spaced out and capped: an error that kills every pass would otherwise leak
-- a row every few seconds all night.
local rebuilds, lastRebuild = 0, -math.huge
local MAX_REBUILDS, REBUILD_GAP = 10, 10

local function Layout(cfg)
	local sp = cfg.debuffSpacing or 3
	local sz = cfg.debuffSize or 26
	-- elementWidth/Height are the layout STRIDE; the size in InitButton is only
	-- how big each icon draws.
	return { elementSpacing = sp, lineSpacing = sp, elementWidth = sz, elementHeight = sz }
end

local function PlaceText(fs, host, point, dx, dy, size, show, alphaTarget)
	local pt = Point(point, 'CENTER')
	local inset = POINTS[pt]
	fs:SetFont(ns.GothamNarrowBlackFont(), size, 'OUTLINE')
	fs:ClearAllPoints()
	fs:SetPoint(pt, host, pt, inset[1] + (dx or 0), inset[2] + (dy or 0))
	-- The host's alpha, not the fontstring's: the engine stamps a secret Alpha
	-- aspect on the duration text and owns the shown state of both strings. A
	-- plain frame of ours in between is a knob it never turns. The preview's
	-- strings are ours alone and pass themselves as the target.
	local target = alphaTarget or host
	target:SetAlpha(show == false and 0 or 1)
end

local function StyleOne(rec, cfg)
	local sz = cfg.debuffSize or 26
	local px = (cfg.debuffBorder == false) and 1 or mmax(1, cfg.debuffBorderSize or 2)
	rec.frame:SetSize(sz, sz)
	rec.icon:ClearAllPoints()
	rec.icon:SetPoint('TOPLEFT', rec.ihost, 'TOPLEFT', px, -px)
	rec.icon:SetPoint('BOTTOMRIGHT', rec.ihost, 'BOTTOMRIGHT', -px, px)
	rec.bhost:SetAlpha(cfg.debuffBorder == false and 0 or 1)
	PlaceText(rec.dur, rec.durHost, cfg.durPoint, cfg.durX, cfg.durY, cfg.durSize or 12, cfg.durShow)
	PlaceText(rec.stack, rec.stackHost, cfg.stackPoint, cfg.stackX, cfg.stackY, cfg.stackSize or 11, cfg.stackShow)
	-- Motion only. The tooltip is the button's own OnEnter, run inside the
	-- secure environment - the one way a tooltip for an aura we cannot read can
	-- exist - but a click would be eaten in the middle of the play field.
	rec.frame:SetMouseClickEnabled(false)
	rec.frame:SetMouseMotionEnabled(cfg.debuffTooltip ~= false)
end

local function InitButton(b)
	local cfg = GetCfg()
	local sz = cfg.debuffSize or 26
	b:SetSize(sz, sz)
	pcall(b.SetTooltipAnchorPoint, b, 'ANCHOR_RIGHT')

	-- Everything below is parented to the aura button: an engine-owned button
	-- refuses layout work for frames it does not parent.
	local backdrop = b:CreateTexture(nil, 'BACKGROUND')
	backdrop:SetColorTexture(0, 0, 0, 1)
	backdrop:SetAllPoints()

	-- The border is one solid square BEHIND an inset icon. The engine tints it
	-- by dispel type (PreserveAsset leaves our art alone and only colours it)
	-- and shows or hides it per aura; when it is hidden the black backdrop is
	-- the border. showWithoutDispelType is on because a boss's tank debuff
	-- nearly never has a type, and those are the debuffs this row is for.
	local bhost = CreateFrame('Frame', nil, b)
	bhost:SetAllPoints()
	local tint = bhost:CreateTexture(nil, 'BACKGROUND')
	tint:SetAllPoints()
	tint:SetTexture(WHITE)
	tint:Hide()

	local ihost = CreateFrame('Frame', nil, b)
	ihost:SetAllPoints()
	ihost:SetFrameLevel(bhost:GetFrameLevel() + 1)
	local icon = ihost:CreateTexture(nil, 'ARTWORK')
	icon:SetPoint('TOPLEFT', 1, -1)
	icon:SetPoint('BOTTOMRIGHT', -1, 1)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b:SetIcon(icon)

	local cd = CreateFrame('Cooldown', nil, ihost, 'CooldownFrameTemplate')
	cd:SetAllPoints(icon)
	cd:SetReverse(true)
	cd:SetDrawEdge(false)
	cd:SetDrawBling(false)
	cd:SetHideCountdownNumbers(true)
	cd.noCooldownCount = true
	b:SetDurationCooldown(cd)

	local durHost = CreateFrame('Frame', nil, b)
	durHost:SetAllPoints()
	durHost:SetFrameLevel(cd:GetFrameLevel() + 5)
	local stackHost = CreateFrame('Frame', nil, b)
	stackHost:SetAllPoints()
	stackHost:SetFrameLevel(cd:GetFrameLevel() + 6)

	-- FONT BEFORE HANDOVER. SetDurationText and SetApplicationCount write to the
	-- fontstring there and then, and SetText on a fontstring with no font is a
	-- hard error that takes the whole AddAuraGroup call down with it.
	local dur = durHost:CreateFontString(nil, 'OVERLAY')
	local stack = stackHost:CreateFontString(nil, 'OVERLAY')
	PlaceText(dur, durHost, cfg.durPoint, cfg.durX, cfg.durY, cfg.durSize or 12, cfg.durShow)
	PlaceText(stack, stackHost, cfg.stackPoint, cfg.stackX, cfg.stackY, cfg.stackSize or 11, cfg.stackShow)
	b:SetDurationText(dur, ns.DurationTextOptions())
	b:SetApplicationCount(stack)

	local style = _G.Enum and _G.Enum.CustomAuraButtonDispelTypeTextureStyle
	if b.AddDispelTypeTexture and style and style.PreserveAsset ~= nil then
		pcall(b.AddDispelTypeTexture, b, tint, {
			style = style.PreserveAsset,
			showWhenHarmful = true,
			showWhenHelpful = false,
			showWithoutDispelType = true,
		})
	end

	local rec = {
		frame = b, bhost = bhost, ihost = ihost, icon = icon,
		dur = dur, durHost = durHost, stack = stack, stackHost = stackHost,
	}
	buttons[#buttons + 1] = rec
	pcall(StyleOne, rec, cfg)
end

-- Debuffs a tank carries that say nothing about the boss. A spell filter on a
-- friendly unit's debuffs is ignored for every spell except the ones Blizzard
-- marks never-secret (AuraContainerUtil.CanApplyIdentityCandidateFilters), and
-- this list is what that exemption exists for: after the first lust of the
-- night Sated sits on both tanks for ten minutes and takes a slot from the
-- boss on every pull. Stagger is a Brewmaster's own damage and always up.
-- A spell the client does not mark never-secret is simply not excluded.
local NOISE_EXTRA = {
	26013, 71041,                   -- Deserter, Dungeon Deserter
	124255, 124273, 124274, 124275, -- Stagger, and its heavy / moderate / light
}
local noise
local function NoiseFilter()
	if not noise then
		noise = {}
		for _, id in ipairs(ns.SATED_IDS or {}) do noise[id] = true end
		for _, id in ipairs(NOISE_EXTRA) do noise[id] = true end
	end
	return { excludeSpellIDs = noise }
end

local function AddGroup(c, key, candidates)
	local SM, SD = _G.AuraContainerSortMethod, _G.AuraContainerSortDirection
	local ok, err = pcall(c.AddAuraGroup, c, key, 'HARMFUL', {
		-- Declared empty; ApplyDebuffLook hands the budget to whichever of the
		-- two groups the setting picks.
		maxFrameCount = 0,
		candidateFilters = candidates,
		-- soonest to expire first: the debuff about to fall off is the swap
		sortMethod = SM and SM.Expiration or 4,
		sortDirection = SD and SD.Normal or 0,
		layout = Layout(GetCfg()),
		initializeFrame = InitButton,
	})
	if ok then groupOK[key] = true else groupErr[key] = err end
end

-- The 2026-07 PTR renamed the flow-layout API (SetAuraLayout* -> SetFlowLayout*).
local function Flow(c, new, old, ...)
	local f = c[new] or (old and c[old])
	if f then pcall(f, c, ...) end
end

local function ApplyGrowth(cfg)
	local AU = _G.AnchorUtil
	local FD = AU and AU.FlowDirection
	if not FD then return end
	local grow = cfg.debuffGrow or 'RIGHT'
	local vertical = (grow == 'UP' or grow == 'DOWN')
	local corner = (grow == 'LEFT' and 'TOPRIGHT') or (grow == 'UP' and 'BOTTOMLEFT') or 'TOPLEFT'

	Flow(container, 'SetFlowLayoutAnchorPoint', 'SetAuraLayoutAnchorPoint', corner)
	Flow(container, 'SetFlowLayoutGrowthDirection', 'SetAuraLayoutGrowthDirection',
		grow == 'LEFT' and FD.Left or FD.Right, grow == 'UP' and FD.Up or FD.Down)
	-- The axis is a separate setting from the direction. The line size is
	-- measured ALONG the axis, so it is only a stand-in for it: a horizontal
	-- flow one pixel wide wraps every icon onto its own row, while the same
	-- limit on a vertical axis would put every icon in its own column.
	local hasAxis = AU.FlowLayoutAxis and container.SetFlowLayoutAxis and true or false
	if hasAxis then
		Flow(container, 'SetFlowLayoutAxis', nil,
			vertical and AU.FlowLayoutAxis.Vertical or AU.FlowLayoutAxis.Horizontal)
	end
	Flow(container, 'SetFlowLayoutMaximumLineSize', 'SetAuraLayoutRowWidth',
		(vertical and not hasAxis) and 1 or nil)

	-- Pin the container corner that matches the layout anchor, so the icons
	-- grow AWAY from the anchor instead of over it.
	container:ClearAllPoints()
	container:SetPoint(corner, holder, corner, 0, 0)
end

-- The row is the size of the row: every offset in the settings is measured
-- from this frame's corner.
local function SizeHolder(cfg)
	local n = mmax(1, cfg.debuffMax or 5)
	local sz, sp = cfg.debuffSize or 26, cfg.debuffSpacing or 3
	local run = n * sz + (n - 1) * sp
	if cfg.debuffGrow == 'UP' or cfg.debuffGrow == 'DOWN' then
		holder:SetSize(sz, run)
	else
		holder:SetSize(run, sz)
	end
	local pt = Point(cfg.debuffAttach, 'BOTTOMLEFT')
	holder:ClearAllPoints()
	holder:SetPoint(pt, frame, pt, cfg.debuffX or 0, cfg.debuffY or -4)
end

-- Settings work, and only settings work: nothing here runs from a health tick.
local function ApplyDebuffLook()
	if not frame then return end
	local cfg = GetCfg()
	SizeHolder(cfg)
	if not container then return end

	styledLast, stylePending = 0, false
	for _, rec in ipairs(buttons) do
		if pcall(StyleOne, rec, cfg) then
			styledLast = styledLast + 1
		else
			stylePending = true
		end
	end

	local n = (cfg.debuffEnable ~= false) and mmax(0, cfg.debuffMax or 5) or 0
	local bossOnly = cfg.debuffBossOnly ~= false and groupOK.boss
	if not groupOK.all then bossOnly = true end
	for key in pairs(groupOK) do
		pcall(container.SetAuraGroupLayout, container, key, Layout(cfg))
		local mine = (key == 'boss') == (bossOnly and true or false)
		pcall(container.SetAuraGroupMaxFrameCount, container, key, mine and n or 0)
	end
	ApplyGrowth(cfg)
end

local function EnsureContainer()
	if container or containerFailed or not IS_121 then return end
	-- Twenty engine buttons are not worth building for a row that is off.
	if GetCfg().debuffEnable == false then return end
	EnsureFrame()
	-- Only the first one gets the name: a replacement must not take the global
	-- from the frozen container it replaces while /fstack is being read.
	local ok, c = pcall(CreateFrame, 'AuraContainer',
		rebuilds == 0 and 'XerionUICoTankDebuffContainer' or nil,
		holder, 'CustomAuraContainerTemplate')
	-- Remembered, so a client that refuses the frame type is asked once.
	if not ok or not c then
		containerFailed, containerErr = true, ok and 'no frame came back' or c
		return
	end
	c:SetSize(1, 1)
	-- Aura groups cannot be removed (the engine pools their frames), so both
	-- are declared here, once, and everything that changes later is a property
	-- of a group rather than a reason to rebuild one.
	-- Boss OR role aura: a tank debuff is flagged one or the other (see the
	-- header). A client that does not know the field ignores it, and the
	-- group then shows every debuff rather than none.
	AddGroup(c, 'boss', { isBossOrRoleAura = true })
	AddGroup(c, 'all', NoiseFilter())
	if not (groupOK.boss or groupOK.all) then
		containerFailed = true
		c:Hide()
		return
	end
	pcall(c.SetEnabled, c, false)
	container = c
	ApplyDebuffLook()
end

-- Returns whether the row is meant to be live, for the stall check.
local function SyncDebuffs()
	if not container then return false end
	local cfg = GetCfg()
	local on = (cfg.enable or testMode) and cfg.debuffEnable ~= false and coUnit and not preview
	if on then
		-- Unit before enable: enabling registers unit events, and there is no
		-- unit to register them for on a container that was never given one.
		-- The container's own answer, not a note of what was last sent: a call
		-- the client refused must be made again, not remembered as done.
		local okU, bound = pcall(container.GetUnit, container)
		if not okU or secret(bound) or bound ~= coUnit then
			pcall(container.SetUnit, container, coUnit)
		end
		pcall(container.SetEnabled, container, true)
	else
		pcall(container.SetEnabled, container, false)
	end
	return on and true or false
end

-- true = frozen, false = working, nil + the reason = the client would not say.
-- Asking for a layout marks the container dirty; a working one is armed after
-- that (it either just stepped from clean to dirty or was already armed and
-- waiting to be seen), a frozen one was left dirty by the pass that died and
-- never re-arms. The request itself is harmless: one extra layout pass.
local MODE_OFF = _G.Enum and _G.Enum.OnUpdateMode and _G.Enum.OnUpdateMode.Disabled or 0
local function EngineStalled()
	if not container then return nil, 'no container' end
	local key = groupOK.all and 'all' or 'boss'
	local okL, errL = pcall(container.SetAuraGroupLayout, container, key, Layout(GetCfg()))
	if not okL then return nil, 'layout refused: ' .. tostring(errL) end
	if not container.GetOnUpdateMode then return nil, 'no GetOnUpdateMode on this client' end
	local ok, mode = pcall(container.GetOnUpdateMode, container)
	if not ok then return nil, 'mode refused: ' .. tostring(mode) end
	if secret(mode) then return nil, 'mode is secret' end
	if type(mode) ~= 'number' then return nil, 'mode = ' .. tostring(mode) end
	return mode == MODE_OFF
end

-- A frozen container is dropped, not repaired. Hidden, its buttons hide with it;
-- disabled, it lets go of its unit events. Everything we kept about it goes too,
-- so the next EnsureContainer builds the replacement from scratch.
local function RebuildContainer()
	local old = container
	if not old then return end
	container = nil
	pcall(old.SetEnabled, old, false)
	pcall(old.Hide, old)
	for k in pairs(groupOK) do groupOK[k] = nil end
	for k in pairs(groupErr) do groupErr[k] = nil end
	for i = #buttons, 1, -1 do buttons[i] = nil end
	containerErr, stylePending = nil, false
	rebuilds, lastRebuild = rebuilds + 1, GetTime()
	EnsureContainer()
	SyncDebuffs()
end

local function Watchdog()
	if not (container and frame:IsVisible()) then return end
	if rebuilds >= MAX_REBUILDS or GetTime() - lastRebuild < REBUILD_GAP then return end
	if EngineStalled() then RebuildContainer() end
end

-- ---------------------------------------------------------------------------
-- Keeping it current
-- ---------------------------------------------------------------------------

local hpEvt = CreateFrame('Frame')
hpEvt:SetScript('OnEvent', UpdateHealth)

local watched
local function Rewatch(unit)
	if unit == watched then return end
	watched = unit
	hpEvt:UnregisterAllEvents()
	if unit then
		hpEvt:RegisterUnitEvent('UNIT_HEALTH', unit)
		hpEvt:RegisterUnitEvent('UNIT_MAXHEALTH', unit)
		hpEvt:RegisterUnitEvent('UNIT_CONNECTION', unit)
		hpEvt:RegisterUnitEvent('UNIT_FLAGS', unit)
	end
end

-- A slow safety net, running only while a bar is up: death and coming back are
-- not reliably one event each, and a respec announces itself to nobody else.
local ticker
local Refresh
local function SyncTicker()
	local want = frame and frame:IsShown() and not preview
	if want and not ticker then
		ticker = C_Timer.NewTicker(2, function() Refresh() end)
	elseif not want and ticker then
		ticker:Cancel()
		ticker = nil
	end
end

-- In sight and online. A secret answer counts as seen: it only ever adds a
-- re-read, never withholds one that was due.
local function UnitSeen(unit)
	local vis, con = UnitIsVisible(unit), UnitIsConnected(unit)
	if secret(vis) or secret(con) then return true end
	return (vis and con) and true or false
end

-- Roster level: who is on the bar, and is the bar up. `reread` is a roster
-- change - the same token can be a different person afterwards - and a loading
-- screen asks for the same thing through `rereadNext`.
local rereadNext = false
local unitSeen = true
function Refresh(reread)
	if preview then return end
	reread = reread or rereadNext
	rereadNext = false
	local unit
	if testMode then
		unit = UnitExists('target') and 'target' or 'player'
	else
		unit = GetCfg().enable and FindCoTank() or nil
	end
	local changed = unit ~= coUnit
	coUnit = unit
	Rewatch(unit)
	if not unit then
		-- Nothing is built for a character who never had a co-tank.
		if frame then frame:Hide() end
		SyncDebuffs()
		SyncTicker()
		return
	end
	EnsureFrame()
	EnsureContainer()
	PaintIdentity(unit)
	UpdateHealth()
	frame:Show()
	local live = SyncDebuffs()
	-- UNIT_AURA stops for a unit out of sight, and coming back into sight sends
	-- nothing, so the row would keep whatever it read before they left.
	local seen = UnitSeen(unit)
	local regained = seen and not unitSeen
	unitSeen = seen
	-- A new unit was re-read by SetUnit already.
	if container and (reread or regained) and not changed then
		pcall(container.UpdateAllAuras, container)
	end
	if live then Watchdog() end
	SyncTicker()
end

-- ---------------------------------------------------------------------------
-- Preview
-- ---------------------------------------------------------------------------

-- Fake icons, and they have to be: the engine only fills a button when a real
-- aura exists. The dispel colours are real ones so the border can be judged.
local previewIcons = {}
local PREVIEW_TINT = {
	{ 0.80, 0.00, 0.00 }, { 0.20, 0.60, 1.00 }, { 0.60, 0.00, 1.00 },
	{ 0.60, 0.40, 0.00 }, { 0.00, 0.60, 0.00 },
}
local PREVIEW_ICON = 134400

local function HidePreviewIcons()
	for _, b in ipairs(previewIcons) do b:Hide() end
end

local function ShowPreview()
	EnsureFrame()
	ApplyVisual()
	local cfg = GetCfg()
	-- Your own class through the same lookup the live bar uses, so a wrong
	-- colour in the preview is a wrong colour in the raid.
	PaintIdentity('player')
	bar:SetMinMaxValues(0, 100)
	bar:SetValue(64)
	hpFS:SetText('64%')
	frame:Show()

	SizeHolder(cfg)
	if cfg.debuffEnable == false then HidePreviewIcons() return end
	local n = mmax(1, cfg.debuffMax or 5)
	local sz, sp = cfg.debuffSize or 26, cfg.debuffSpacing or 3
	local px = (cfg.debuffBorder == false) and 1 or mmax(1, cfg.debuffBorderSize or 2)
	local grow = cfg.debuffGrow or 'RIGHT'
	local dx = (grow == 'LEFT' and -(sz + sp)) or (grow == 'RIGHT' and (sz + sp)) or 0
	local dy = (grow == 'UP' and (sz + sp)) or (grow == 'DOWN' and -(sz + sp)) or 0
	local corner = (grow == 'LEFT' and 'TOPRIGHT') or (grow == 'UP' and 'BOTTOMLEFT') or 'TOPLEFT'

	for i = 1, n do
		local b = previewIcons[i]
		if not b then
			b = CreateFrame('Frame', nil, holder)
			b.bd = b:CreateTexture(nil, 'BACKGROUND')
			b.bd:SetAllPoints()
			b.icon = b:CreateTexture(nil, 'ARTWORK')
			b.icon:SetTexture(PREVIEW_ICON)
			b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			b.text = b:CreateFontString(nil, 'OVERLAY')
			b.stack = b:CreateFontString(nil, 'OVERLAY')
			previewIcons[i] = b
		end
		b:SetSize(sz, sz)
		b:ClearAllPoints()
		b:SetPoint(corner, holder, corner, (i - 1) * dx, (i - 1) * dy)
		b.icon:ClearAllPoints()
		b.icon:SetPoint('TOPLEFT', px, -px)
		b.icon:SetPoint('BOTTOMRIGHT', -px, px)
		local c = PREVIEW_TINT[((i - 1) % #PREVIEW_TINT) + 1]
		if cfg.debuffBorder == false then
			b.bd:SetColorTexture(0, 0, 0, 1)
		else
			b.bd:SetColorTexture(c[1], c[2], c[3], 1)
		end
		-- the same placement as the live strings; their own alpha is the switch
		PlaceText(b.text, b, cfg.durPoint, cfg.durX, cfg.durY, cfg.durSize or 12, cfg.durShow, b.text)
		b.text:SetText(tostring(4 + i * 3))
		PlaceText(b.stack, b, cfg.stackPoint, cfg.stackX, cfg.stackY, cfg.stackSize or 11, cfg.stackShow, b.stack)
		b.stack:SetText(tostring(i))
		b:Show()
	end
	for i = n + 1, #previewIcons do previewIcons[i]:Hide() end
end

-- ---------------------------------------------------------------------------
-- Apply, and the options-side entry points
-- ---------------------------------------------------------------------------

local function Apply()
	local cfg = GetCfg()
	if frame then
		ApplyVisual()
		ApplyDebuffLook()
		frame:EnableMouse(preview and not cfg.lock or false)
	end
	if preview then
		SyncDebuffs()
		ShowPreview()
		frame:EnableMouse(not cfg.lock)
		SyncTicker()
		return
	end
	HidePreviewIcons()
	Refresh()
end

-- A dragged slider asks many times a frame; one Apply answers all of them.
ns.CoTApply = ns.Coalesce(Apply)
-- Same for a raid's burst of roster and role events.
local QueueReread = ns.Coalesce(function() Refresh(true) end)

ns.CoTIsPreview = function() return preview end
ns.CoTSetPreview = function(state)
	preview = state and true or false
	if preview then
		coUnit = nil
		Rewatch(nil)
	end
	Apply()
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local evt = CreateFrame('Frame')
evt:RegisterEvent('PLAYER_ENTERING_WORLD')
evt:RegisterEvent('GROUP_ROSTER_UPDATE')
evt:RegisterEvent('PLAYER_ROLES_ASSIGNED')
evt:RegisterEvent('PLAYER_REGEN_ENABLED')
evt:RegisterEvent('ADDON_RESTRICTION_STATE_CHANGED')
-- Every pull starts from a fresh read of the co-tank's debuffs, whatever the
-- row made of the trash and the runback before it.
evt:RegisterEvent('ENCOUNTER_START')
evt:RegisterUnitEvent('PLAYER_SPECIALIZATION_CHANGED', 'player')
-- A key whose last fight ended before the timer stopped lifts its restriction
-- with no PLAYER_REGEN_ENABLED after it, so a refused restyle also retries on
-- the restriction's own change event - on the next frame, because the state
-- still reads the old value while that event is handed out (LustPots).
local QueueRestyle = ns.Coalesce(function()
	if stylePending and not preview and (testMode or GetCfg().enable) then ApplyDebuffLook() end
end)

evt:SetScript('OnEvent', function(_, event)
	if event == 'PLAYER_ENTERING_WORLD' then
		-- A loading screen rebuilds the client's aura data. SetUnit with the
		-- same token would be a no-op, so the next Refresh asks for a re-read.
		rereadNext = true
		C_Timer.After(0.5, ns.CoTApply)
		return
	end
	if preview or not (testMode or GetCfg().enable) then return end
	if event == 'PLAYER_REGEN_ENABLED' then
		-- First moment the engine's buttons are ours to touch again.
		if stylePending then ApplyDebuffLook() end
		return
	end
	if event == 'ADDON_RESTRICTION_STATE_CHANGED' then
		if stylePending then QueueRestyle() end
		return
	end
	-- The whole cost of this module in a five-man: one IsInRaid() per event.
	-- PLAYER_TARGET_CHANGED is only registered while the test runs.
	if not (testMode or coUnit) and not IsInRaid() then return end
	QueueReread()
end)

-- ---------------------------------------------------------------------------
-- Diagnostics
--
-- "There is no bar" has five causes that look identical from the outside. This
-- prints every link of the chain that IS readable, so the next report is about
-- a line instead of a feeling.
--
-- Whether an icon drew can be asked only while the unit's auras are not secret:
-- the engine locks its buttons then, because a shown-count would leak how many
-- auras the unit carries. Out of combat and outside an encounter the counts are
-- real, and they split "the engine placed nothing" from "it placed icons we
-- cannot see". The frame lines do the rest: the engine sizes the container
-- from what it placed, and every frame's corner is printed in screen units.
--
-- The debuff row went unexplained in two versions of this module, both built
-- for a raid nobody could test in. `test` puts the live bar and the real row on
-- your target, so a DoT on a training dummy answers "does the row draw at all"
-- in a minute, alone.
-- ---------------------------------------------------------------------------

local function Rect(f)
	if not f then return 'not built' end
	local ok, vis, w, h, l, b = pcall(function()
		return f:IsVisible(), f:GetWidth(), f:GetHeight(), f:GetLeft(), f:GetBottom()
	end)
	if not ok then return '|cffff5555refused|r' end
	if secret(vis) or secret(w) or secret(h) or secret(l) or secret(b) then return '|cff888888secret|r' end
	local where = l and sformat('at %d,%d', l, b or 0) or '|cffff5555not anchored|r'
	return sformat('%s %dx%d %s', vis and 'visible' or '|cffff5555HIDDEN|r', w, h, where)
end

local function GroupLine(key)
	if not groupOK[key] then
		return key .. ' |cffff5555refused:|r ' .. tostring(groupErr[key] or '?')
	end
	local okN, n = pcall(container.GetAuraGroupFrameCount, container, key)
	if not okN or type(n) ~= 'number' then return key .. ' = ?' end
	local shown, hidden, locked = 0, 0, 0
	for i = 1, n do
		local okS, s = pcall(function()
			local f = container:GetAuraGroupFrame(key, i)
			return f and f:IsShown()
		end)
		if not okS or secret(s) then
			locked = locked + 1
		elseif s then
			shown = shown + 1
		else
			hidden = hidden + 1
		end
	end
	return sformat('%s = %d buttons, %d shown, %d idle%s', key, n, shown, hidden,
		locked > 0 and sformat(', %d locked (auras secret)', locked) or '')
end

_G.SLASH_XERIONCOTANK1 = '/xerioncotank'
_G.SlashCmdList.XERIONCOTANK = function(msg)
	local function p(...) print('|cffff7d0aXerionUI-CoTank|r', ...) end
	local function yn(v) return v and 'yes' or 'no' end

	if (msg or ''):lower():match('^%s*test') then
		testMode = not testMode
		if testMode then
			evt:RegisterEvent('PLAYER_TARGET_CHANGED')
			p('test ON: the bar and the real debuff row follow your target (you, with no target).'
				.. ' Put a DoT on a training dummy - its icon must show in the row. /xerioncotank test again to stop.')
			if preview then p('|cffff5555preview is on - switch it off, the test draws under it|r') end
		else
			evt:UnregisterEvent('PLAYER_TARGET_CHANGED')
			p('test off')
		end
		ns.CoTApply()
		return
	end

	-- By hand, past the cap and the spacing: if the row comes back after this,
	-- the engine had stopped and the watchdog missed it.
	if (msg or ''):lower():match('^%s*rebuild') then
		if not container then p('no debuff row built yet') return end
		RebuildContainer()
		p(container and 'debuff row rebuilt' or '|cffff5555the replacement was refused - see /xerioncotank|r')
		return
	end

	local cfg = GetCfg()
	local _, itype = IsInInstance()
	p('enable =', cfg.enable and 'on' or 'off', '| in raid =', yn(IsInRaid()),
		'| instance =', tostring(itype), '| you tank-specced =', yn(PlayerIsTank()),
		'| tank only =', yn(cfg.tankOnly ~= false),
		'| pinned name =', PinnedName(cfg) or '(automatic)', '| test =', testMode and 'ON' or 'off')

	if IsInRaid() then
		local found = 0
		for i = 1, 40 do
			local u = RAID[i]
			if UnitExists(u) then
				local tank = IsTankUnit(u)
				local same = UnitIsUnit(u, 'player')
				if tank ~= false then
					found = found + 1
					local name = UnitName(u)
					local okR, role = pcall(UnitGroupRolesAssigned, u)
					p(sformat('  %s  %s  role=%s  %s%s', u,
						secret(name) and '|cffff5555secret|r' or tostring(name),
						(not okR or secret(role)) and '|cffff5555secret|r' or tostring(role),
						tank == nil and '|cffff5555unreadable|r' or 'tank',
						(not secret(same) and same) and '  (you)' or ''))
				end
			end
		end
		if found == 0 then p('  no raid member carries the TANK role or the Main Tank mark') end
	end

	p('co-tank =', coUnit or '|cff888888none|r', '| health events on =', tostring(watched),
		'| bar =', frame and (frame:IsShown() and 'shown' or 'hidden') or 'not built',
		'| preview =', preview and 'ON' or 'off')
	if healthErr then p('|cffff5555last health error:|r', tostring(healthErr)) end

	if not IS_121 then
		p('debuffs = unavailable (needs the 12.1 aura container)')
	elseif containerFailed then
		p('|cffff5555debuffs = the client refused the AuraContainer or both of its groups|r')
		if containerErr then p('  container:', tostring(containerErr)) end
		for key, err in pairs(groupErr) do p('  group', key .. ':', tostring(err)) end
	elseif not container then
		p('debuffs = not built yet (built the first time a co-tank is found)',
			cfg.debuffEnable == false and '|cffff5555- "Show debuffs" is off|r' or '')
	else
		local okE, en = pcall(container.IsEnabled, container)
		local okU, u = pcall(container.GetUnit, container)
		-- the same choice ApplyDebuffLook makes
		local bossOnly = (cfg.debuffBossOnly ~= false and groupOK.boss) or not groupOK.all
		p('debuffs: enabled =', okE and tostring(en) or '?', '| unit =', okU and tostring(u) or '?',
			'| showing =', bossOnly and '|cffffff00boss + role debuffs only|r' or 'every debuff',
			'| max =', cfg.debuffEnable == false and '|cffff5555off|r' or tostring(cfg.debuffMax or 5))
		p('  ' .. GroupLine('boss') .. ' | ' .. GroupLine('all'))
		local stalled, why = EngineStalled()
		p('  engine =', stalled and '|cffff5555FROZEN (dirty, never re-armed)|r'
				or stalled == false and 'working' or ('|cff888888unknown - ' .. tostring(why) .. '|r'),
			'| rows replaced =', rebuilds,
			rebuilds >= MAX_REBUILDS and '|cffff5555(cap reached - /xerioncotank rebuild still works)|r' or '')
		p('  styled =', #buttons, '| on the last pass =', styledLast,
			stylePending and '|cffff5555(rest refused - retried after combat)|r' or '')
		p('  bar', Rect(frame), '| row', Rect(holder), '| engine', Rect(container),
			'| screen', sformat('%dx%d', UIParent:GetWidth(), UIParent:GetHeight()))
		p('  |cff888888Icons "shown" but none on screen: a placement problem. "0 shown" on a unit that has debuffs: the engine placed nothing.'
			.. (bossOnly and ' Boss + role only is on - if a tank debuff is missing, turn it off and look again.' or '') .. '|r')
	end
end
