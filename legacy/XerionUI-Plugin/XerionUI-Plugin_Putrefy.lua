local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('Putrefy', hooksecurefunc, C_Timer)
local _G = _G

local CreateFrame = CreateFrame
local UIParent = UIParent
local GetTime = GetTime
local C_Timer = C_Timer
local ipairs, pcall, type, tonumber, tostring = ipairs, pcall, type, tonumber, tostring
local format = string.format
local mmax, mfloor, mceil = math.max, math.floor, math.ceil
local tremove, tconcat = table.remove, table.concat

-- WHY THIS FILE EXISTS
-- Unholy's Forbidden Knowledge talent grants Forbidden Sacrifice, Mastery for
-- 12 seconds per stack. Stacks come from a Putrefy press (one press can bring
-- two) and from Dread Plague's random Lesser Ghoul, which putrefies with no
-- press at all, and each stack runs out on its own 12 seconds. Lining
-- Apocalypse or Dark Transformation up inside those windows means seeing when
-- each stack ends.
--
-- WHAT IT DOES
-- One bar per stack, each draining over its own 12 seconds, the oldest
-- nearest the anchor and every new stack added under (or above) the rest.
--
-- WHY THE BARS RUN ON OUR OWN CLOCK
-- The game keeps Forbidden Sacrifice as ONE aura with a stack count (the
-- user's screenshot, 2026-09-26: "5" on one icon). Its one timer restarts
-- with every new stack; the time each stack has left is not in the aura data
-- at all, secret or not. So this file notices each new stack and times it
-- from that moment, and a stack is gone 12 seconds later.
--
-- Noticing a new stack, in order of preference:
-- 1. Reading the stack count. Out of combat always; in combat only if the
--    game flags the spell as never secret (C_Secrets.ShouldSpellAuraBeSecret
--    says which). Each UNIT_AURA compares the count with the bars running:
--    more stacks start bars, fewer end the oldest.
-- 2. The echo: when an aura is cast on you by a hidden triggered spell,
--    SPELL_UPDATE_COOLDOWN carries that spell's ID, in plain numbers, even
--    though the spell has no cooldown (the Elixir and Boiling Point modules
--    live on it). One echo of the aura's ID = one new stack.
-- 3. Neither known to work yet: the game's aura engine draws the one aura as
--    one bar with its stack count on the icon, exactly as before - the only
--    view that needs no numbers. The first echo seen switches to per-stack
--    bars for the rest of the session.
-- /xerionputrefy keeps a short log of what arrives, so one fight shows which
-- door the client really opens.
--
-- The file, the saved key, the PF prefix and /xerionputrefy are named after
-- Putrefy because the first version drew a bar per press - wrong, since one
-- press can bring two stacks and Dread Plague brings them with no press.

ns.hasPutrefy = true

local secret = ns.IsSecret

-- 1256576 is the aura (the ID its tooltip shows). 1256565 is what the
-- Cooldown Manager files it under; it is in the engine's filter only, with a
-- duration cap that keeps out a permanent aura under that ID (a talent
-- passive: a "max duration" candidate filter always rejects permanent auras).
local AURA = 1256576
local AURA_IDS = { 1256576, 1256565 }
local DURATION = 12
local MAX_BARS = 8
local MAX_DURATION = 60
local PREVIEW_EVERY = 4
-- A cast and the cooldown echo of the same spell land within this.
local SAME_CAST = 0.3
local GROUP = 'forbiddenSacrifice'
local DEFAULT_ICON = 136157
local WHITE = 'Interface\\Buttons\\WHITE8X8'

local AXIS = _G.AnchorUtil and _G.AnchorUtil.FlowLayoutAxis
local DIR = _G.AnchorUtil and _G.AnchorUtil.FlowDirection
-- Only the one-bar fallback needs the engine; the stack bars are ours.
ns.PFUnavailable = not (ns.IS_121 and AXIS and DIR and ns.HasTemplate('CustomAuraContainerTemplate'))

local DEFAULTS = {
	enable = false,
	lock = true,
	width = 200,
	height = 20,
	grow = 'DOWN',
	spacing = 2,
	showIcon = true,
	iconID = DEFAULT_ICON,
	showTimer = true,
	textSize = 12,
	color = { 0.44, 0.76, 0.22 },
	bgAlpha = 0.6,
	x = 0,
	y = -180,
}

local function Migrate(cfg)
	if cfg.grow ~= 'UP' and cfg.grow ~= 'DOWN' then cfg.grow = 'DOWN' end
	local id = tonumber(cfg.iconID)
	cfg.iconID = (id and id > 0) and mfloor(id) or DEFAULT_ICON
	if type(cfg.color) ~= 'table' then cfg.color = { DEFAULTS.color[1], DEFAULTS.color[2], DEFAULTS.color[3] } end
	-- A bar is one stack now; the count only shows on the fallback bar.
	cfg.showStacks = nil
end

local function GetCfg() return ns.ModuleCfg('putrefy', DEFAULTS, Migrate) end
ns.PFGetCfg = GetCfg
ns.PFDefaultIcon = DEFAULT_ICON

local function IsUnholy() return ns.IsSpec('DEATHKNIGHT', 3) end
local function Up(cfg) return cfg.grow == 'UP' end
local function Corner(cfg) return Up(cfg) and 'BOTTOMLEFT' or 'TOPLEFT' end
local function Width(cfg) return mmax(20, tonumber(cfg.width) or 200) end
local function Height(cfg) return mmax(4, tonumber(cfg.height) or 20) end
local function Gap(cfg) return mmax(0, tonumber(cfg.spacing) or 0) end

local function Color(cfg)
	local c = cfg.color
	if type(c) ~= 'table' then c = DEFAULTS.color end
	return c[1] or 0.44, c[2] or 0.76, c[3] or 0.22
end

-- "4.2": tenths, rounded up so a bar never reads 0.0 while it still runs
-- (the CC Bars formatter), for the engine's bar. Ours round the same way.
local tenthsFmt
local function TimerOptions()
	if tenthsFmt == nil then
		tenthsFmt = false
		local CSU, E = _G.C_StringUtil, _G.Enum
		if CSU and CSU.CreateNumericRuleFormatter then
			local ok, f = pcall(CSU.CreateNumericRuleFormatter)
			if ok and f and f.SetBreakpoints then
				local up = (E and E.NumericRuleFormatRounding and E.NumericRuleFormatRounding.Up) or 1
				if pcall(f.SetBreakpoints, f, {
					{ threshold = 0, step = 0.1, rounding = up, format = '%.1f' },
				}) then
					tenthsFmt = f
				end
			end
		end
	end
	if tenthsFmt then return { textFormatter = tenthsFmt } end
	return ns.DurationTextOptions()
end

-- The engine's fill drains as the seconds go.
local BAR_OPTIONS = {}
do
	local E = _G.Enum
	if E and E.StatusBarInterpolation then BAR_OPTIONS.interpolation = E.StatusBarInterpolation.Immediate end
	if E and E.StatusBarTimerDirection then BAR_OPTIONS.direction = E.StatusBarTimerDirection.RemainingTime end
end

-- ---------------------------------------------------------------------------
-- One bar: the same pieces for our stack bars and the engine's fallback bar
-- ---------------------------------------------------------------------------

-- `parent` is a 1x1 frame at the corner of the bar's place: one of ours, or
-- an engine button. `root` is pinned over it once, here: on an engine button
-- a SetPoint that names the BUTTON is refused while auras are secret (see CC
-- Bars), one that names our own frame is not, so everything after this hangs
-- off root and face only.
local function MakeFace(parent)
	local p = {}
	p.root = CreateFrame('Frame', nil, parent)
	p.root:SetAllPoints(parent)
	p.face = CreateFrame('Frame', nil, p.root)
	p.bg = p.face:CreateTexture(nil, 'BACKGROUND')
	-- A one-pixel black outline inside the bar's own size, the Shroud bar's
	-- look: four sides and the icon/fill divider, not one black plate under
	-- the see-through background, which would make it solid.
	p.edges = {}
	for k = 1, 5 do
		local e = p.face:CreateTexture(nil, 'BORDER')
		e:SetColorTexture(0, 0, 0, 1)
		p.edges[k] = e
	end
	local e = p.edges
	e[1]:SetPoint('TOPLEFT')
	e[1]:SetPoint('TOPRIGHT')
	e[1]:SetHeight(1)
	e[2]:SetPoint('BOTTOMLEFT')
	e[2]:SetPoint('BOTTOMRIGHT')
	e[2]:SetHeight(1)
	e[3]:SetPoint('TOPLEFT')
	e[3]:SetPoint('BOTTOMLEFT')
	e[3]:SetWidth(1)
	e[4]:SetPoint('TOPRIGHT')
	e[4]:SetPoint('BOTTOMRIGHT')
	e[4]:SetWidth(1)
	e[5]:SetWidth(1)
	p.icon = p.face:CreateTexture(nil, 'ARTWORK')
	p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	p.bar = CreateFrame('StatusBar', nil, p.face)
	-- Layers of their own for the seconds and the stacks: the engine owns the
	-- alpha of a fontstring it writes (a secret aspect), so "hide" dims these.
	p.timerHost = CreateFrame('Frame', nil, p.face)
	p.timerHost:SetAllPoints(p.face)
	p.timerHost:SetFrameLevel(p.bar:GetFrameLevel() + 5)
	p.timer = p.timerHost:CreateFontString(nil, 'OVERLAY')
	p.stackHost = CreateFrame('Frame', nil, p.face)
	p.stackHost:SetAllPoints(p.face)
	p.stackHost:SetFrameLevel(p.bar:GetFrameLevel() + 6)
	p.stack = p.stackHost:CreateFontString(nil, 'OVERLAY')
	-- A font straight away: SetText on an unfonted fontstring is a hard error,
	-- and the engine writes on its own even if styling failed.
	p.timer:SetFont(_G.STANDARD_TEXT_FONT, 12, 'OUTLINE')
	p.stack:SetFont(_G.STANDARD_TEXT_FONT, 12, 'OUTLINE')
	return p
end

local function SetFont(fs, size)
	local ok, valid = pcall(fs.SetFont, fs, ns.GetFont(), size, 'OUTLINE')
	if not ok or valid == false then pcall(fs.SetFont, fs, _G.STANDARD_TEXT_FONT, size, 'OUTLINE') end
end

-- The face hangs from the root's corner the stack grows away from, so the bar
-- sits at the near end of its place and the gap at the far end.
local function StyleFace(p, cfg)
	local corner = Corner(cfg)
	local w, h = Width(cfg), Height(cfg)
	p.face:ClearAllPoints()
	p.face:SetPoint(corner, p.root, corner, 0, 0)
	p.face:SetSize(w, h)

	local r, g, b = Color(cfg)
	local inner = mmax(1, h - 2)
	p.bg:ClearAllPoints()
	p.bg:SetPoint('TOPLEFT', 1, -1)
	p.bg:SetPoint('BOTTOMRIGHT', -1, 1)
	p.bg:SetColorTexture(r * 0.15, g * 0.15, b * 0.15, cfg.bgAlpha or 0.6)

	local showIcon = cfg.showIcon ~= false
	p.icon:ClearAllPoints()
	p.icon:SetPoint('TOPLEFT', 1, -1)
	p.icon:SetSize(inner, inner)
	if not p.icon:SetTexture(tonumber(cfg.iconID) or DEFAULT_ICON) then
		p.icon:SetTexture(DEFAULT_ICON)
	end
	p.icon:SetShown(showIcon)

	-- With the icon on, a one-pixel black line parts it from the fill.
	local div = p.edges[5]
	div:ClearAllPoints()
	div:SetPoint('TOPLEFT', inner + 1, -1)
	div:SetPoint('BOTTOMLEFT', inner + 1, 1)
	div:SetShown(showIcon)
	p.bar:ClearAllPoints()
	p.bar:SetPoint('TOPLEFT', showIcon and (inner + 2) or 1, -1)
	p.bar:SetPoint('BOTTOMRIGHT', -1, 1)
	p.bar:SetStatusBarTexture(ns.BarTexture() or WHITE)
	p.bar:SetStatusBarColor(r, g, b)

	local size = mmax(6, tonumber(cfg.textSize) or 12)
	SetFont(p.timer, size)
	p.timer:ClearAllPoints()
	p.timer:SetPoint('RIGHT', p.bar, 'RIGHT', -4, 0)
	p.timer:SetJustifyH('RIGHT')
	p.timerHost:SetAlpha(cfg.showTimer ~= false and 1 or 0)

	-- The fallback bar's count: on the icon's centre, or on the fill's left
	-- end when the icon is off. Our stack bars leave it empty.
	SetFont(p.stack, size)
	p.stack:ClearAllPoints()
	if showIcon then
		p.stack:SetPoint('CENTER', p.icon, 'CENTER', 0, 0)
		p.stack:SetJustifyH('CENTER')
	else
		p.stack:SetPoint('LEFT', p.bar, 'LEFT', 4, 0)
		p.stack:SetJustifyH('LEFT')
	end
end

-- ---------------------------------------------------------------------------
-- The stacks: one start time each, oldest first
-- ---------------------------------------------------------------------------

-- fake[i] marks the preview's made-up stacks, so leaving the preview takes
-- only those away and switching the module off only the real ones.
local starts, fake = {}, {}
local preview, lastFake = false, 0

local function Prune(now)
	for i = #starts, 1, -1 do
		if now - starts[i] >= DURATION then
			tremove(starts, i)
			tremove(fake, i)
		end
	end
end

local function Add(isFake, at)
	local now = GetTime()
	Prune(now)
	if #starts >= MAX_BARS then
		tremove(starts, 1)
		tremove(fake, 1)
	end
	starts[#starts + 1] = at or now
	fake[#fake + 1] = isFake and true or false
end

local function ClearWhere(fakeOnes)
	for i = #starts, 1, -1 do
		if fake[i] == fakeOnes then
			tremove(starts, i)
			tremove(fake, i)
		end
	end
end

local function RealCount()
	local n = 0
	for i = 1, #starts do if not fake[i] then n = n + 1 end end
	return n
end

-- The oldest real stacks first: they are the ones the game drops first.
local function DropOldestReal(count)
	local i = 1
	while count > 0 and i <= #starts do
		if not fake[i] then
			tremove(starts, i)
			tremove(fake, i)
			count = count - 1
		else
			i = i + 1
		end
	end
end

-- ---------------------------------------------------------------------------
-- Noticing stacks
-- ---------------------------------------------------------------------------

-- The last few things that could have been a new stack, for /xerionputrefy.
local LOG_MAX = 40
local logAt, logWhat, logN = {}, {}, 0
local function Log(what)
	logN = logN % LOG_MAX + 1
	logAt[logN], logWhat[logN] = GetTime(), what
end

-- Whether a read of the aura would come back secret right now. The spell's
-- own flag wins over the general restriction, which is the whole point of
-- asking per spell. No C_Secrets at all is a client without secrets.
local function AuraSecret()
	local S = _G.C_Secrets
	if S and S.ShouldSpellAuraBeSecret then
		local ok, v = pcall(S.ShouldSpellAuraBeSecret, AURA)
		if ok and type(v) == 'boolean' then return v end
	end
	if S and S.ShouldAurasBeSecret then
		local ok, v = pcall(S.ShouldAurasBeSecret)
		if ok and type(v) == 'boolean' then return v end
	end
	return false
end

-- The stack count, 0 when the aura is not on you, or nil when it cannot be
-- read. GetPlayerAuraBySpellID answers nothing for a secret aura (the
-- RequiresNonSecretAura rule), so the question goes to C_Secrets first:
-- otherwise "secret" and "not there" would look the same.
local function ReadStacks()
	if AuraSecret() then return nil end
	local U = _G.C_UnitAuras
	if not (U and U.GetPlayerAuraBySpellID) then return nil end
	local ok, a = pcall(U.GetPlayerAuraBySpellID, AURA)
	if not ok then return nil end
	if a == nil then return 0 end
	if secret(a) then return nil end
	local n = a.applications
	if secret(n) then return nil end
	n = tonumber(n) or 0
	-- An aura that does not stack reports 0 applications.
	if n < 1 then n = 1 end
	return n
end

-- Door 1: the count is readable, so the bars follow it. New stacks start
-- now: UNIT_AURA arrives in the same frame as the stack. Returns whether the
-- count could be read.
local lastRead
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
	if n ~= lastRead then
		lastRead = n
		Log('stacks ' .. n)
	end
	return true
end

-- Door 2: the echo. A cast and its cooldown echo arrive together, so a
-- cooldown echo right after a cast of the same spell is the same stack.
local echoSeen = false
local lastCastAt = {}

local function OnEcho(id, fromCast)
	local now = GetTime()
	if not fromCast then
		local c = lastCastAt[id]
		if c and now - c < SAME_CAST then return false end
		Log('echo ' .. id)
	end
	if id ~= AURA then return false end
	echoSeen = true
	-- A readable count already covers it (door 1, on UNIT_AURA).
	if AuraSecret() then Add(false) end
	return true
end

-- ---------------------------------------------------------------------------
-- Frames
-- ---------------------------------------------------------------------------

local holder, stackLayer, container
local slots = {}
-- One record per engine button; the engine builds them as it needs them.
local buttons = {}
local live, useEngine = false, false
local stylePending, rereadNext = false, false
local failed, barFailed, textFailed, stackFailed

local function LayoutSlot(s, i, cfg)
	local corner = Corner(cfg)
	local step = (Up(cfg) and 1 or -1) * (Height(cfg) + Gap(cfg))
	s.anchor:ClearAllPoints()
	s.anchor:SetPoint(corner, holder, corner, 0, (i - 1) * step)
	StyleFace(s.p, cfg)
	s.p.bar:SetMinMaxValues(0, DURATION)
	s.p.stack:SetText('')
	s.tenth = nil
end

local function Slot(i)
	local s = slots[i]
	if not s then
		local anchor = CreateFrame('Frame', nil, stackLayer)
		anchor:SetSize(1, 1)
		anchor:Hide()
		s = { anchor = anchor, p = MakeFace(anchor) }
		slots[i] = s
		LayoutSlot(s, i, GetCfg())
	end
	return s
end

-- Every frame while a stack bar is up: the fill, the seconds, and bars
-- coming and going. Runs on stackLayer, which is shown only while it has
-- something to draw.
local function Render()
	local now = GetTime()
	Prune(now)
	if preview and now - lastFake >= PREVIEW_EVERY then
		lastFake = now
		Add(true)
	end
	local n = #starts
	for i = 1, n do
		local s = Slot(i)
		local left = DURATION - (now - starts[i])
		if left < 0 then left = 0 end
		s.p.bar:SetValue(left)
		-- The text only changes ten times a second; SetText is skipped between.
		local tenth = mceil(left * 10)
		if tenth ~= s.tenth then
			s.tenth = tenth
			s.p.timer:SetText(format('%.1f', tenth / 10))
		end
		if not s.anchor:IsShown() then s.anchor:Show() end
	end
	for i = n + 1, #slots do
		if slots[i].anchor:IsShown() then slots[i].anchor:Hide() end
	end
	if n == 0 and not preview then stackLayer:Hide() end
end

local function EnsureFrame()
	if holder then return end
	-- Named, because edit mode looks the frame up by this exact string. One
	-- bar's size, where the first bar goes; the stack grows away from it.
	holder = CreateFrame('Frame', 'XerionUIPutrefy', UIParent)
	holder:SetFrameStrata('MEDIUM')
	holder:SetClampedToScreen(true)
	holder:SetMovable(true)
	holder:EnableMouse(false)
	holder:RegisterForDrag('RightButton')
	ns.MakeDraggable(holder, GetCfg, 'x', 'y', function() if ns.PFApply then ns.PFApply() end end)
	holder:Hide()
	stackLayer = CreateFrame('Frame', nil, holder)
	stackLayer:SetAllPoints(holder)
	stackLayer:Hide()
	stackLayer:SetScript('OnUpdate', Render)
end

local function PlaceHolder(cfg)
	holder:ClearAllPoints()
	holder:SetPoint('CENTER', UIParent, 'CENTER', cfg.x or 0, cfg.y or DEFAULTS.y)
	holder:SetSize(Width(cfg), Height(cfg))
end

-- The fallback: one engine element per aura, the bar and the gap after it
-- (the layout's element size is what the engine lays out, not the button's
-- own - CustomAuraContainerFlowLayoutMixin:GetElementSize).
local function GroupLayout(cfg)
	return { elementWidth = Width(cfg), elementHeight = Height(cfg) + Gap(cfg),
		elementSpacing = 0, lineSpacing = 0 }
end

-- One column growing away from the holder's corner, with the one pixel an
-- empty container is at the far end (padding: left, right, top, bottom).
local function Flow(c, cfg)
	local up = Up(cfg)
	c:SetFlowLayoutAxis(AXIS.Vertical)
	c:SetFlowLayoutAnchorPoint(Corner(cfg))
	c:SetFlowLayoutGrowthDirection(DIR.Right, up and DIR.Up or DIR.Down)
	c:SetFlowLayoutPadding(0, 0, up and 1 or 0, up and 0 or 1)
end

-- Once a container has a group its size is the engine's business; its
-- position stays ours.
local function PlaceContainer(c, cfg)
	local corner = Corner(cfg)
	c:ClearAllPoints()
	c:SetPoint(corner, holder, corner, 0, 0)
end

-- Runs once per button the engine builds, inside its frame batch: an error
-- here would take the batch down with it, so everything is armoured.
local function InitButton(b)
	local cfg = GetCfg()
	-- Display only. A Button takes the mouse by default and would swallow
	-- clicks meant for the world for as long as the aura is up.
	pcall(b.SetMouseClickEnabled, b, false)
	pcall(b.SetMouseMotionEnabled, b, false)
	pcall(b.SetSize, b, 1, 1)
	local p = MakeFace(b)
	pcall(StyleFace, p, cfg)
	local okB, errB = pcall(b.SetDurationBar, b, p.bar, BAR_OPTIONS)
	if not okB then barFailed = tostring(errB) end
	local okT, errT = pcall(b.SetDurationText, b, p.timer, TimerOptions())
	if not okT then textFailed = tostring(errT) end
	-- No formatter: the engine writes the count from 2 up and nothing for 1.
	local okS, errS = pcall(b.SetApplicationCount, b, p.stack)
	if not okS then stackFailed = tostring(errS) end
	buttons[#buttons + 1] = p
end

local function EnsureContainer(cfg)
	if container or failed or ns.PFUnavailable then return end
	local ok, c = pcall(CreateFrame, 'AuraContainer', 'XerionUIPutrefyContainer', holder, 'CustomAuraContainerTemplate')
	if not ok or not c then
		failed = 'the client refused the AuraContainer frame'
		return
	end
	c:SetSize(1, 1)
	local okF, errF = pcall(Flow, c, cfg)
	if not okF then
		failed = 'column layout refused: ' .. tostring(errF)
		c:Hide()
		return
	end
	local include = {}
	for _, id in ipairs(AURA_IDS) do include[id] = true end
	local SM, SD = _G.AuraContainerSortMethod, _G.AuraContainerSortDirection
	local okG, errG = pcall(c.AddAuraGroup, c, GROUP, 'HELPFUL', {
		maxFrameCount = MAX_BARS,
		candidateFilters = { includeSpellIDs = include, maxDuration = MAX_DURATION },
		sortMethod = SM and SM.ExpirationOnly or 5,
		sortDirection = SD and SD.Normal or 0,
		initializeFrame = InitButton,
		layout = GroupLayout(cfg),
	})
	if not okG then
		failed = tostring(errG)
		c:Hide()
		return
	end
	pcall(c.SetEnabled, c, false)
	PlaceContainer(c, cfg)
	c:Hide()
	container = c
end

-- Settings for everything drawn. Our own pieces take them at any time; should
-- the client refuse something on the engine's side mid-fight, it is tried
-- again when combat ends.
local function Restyle(cfg)
	stylePending = false
	for i, s in ipairs(slots) do LayoutSlot(s, i, cfg) end
	for _, p in ipairs(buttons) do
		if not pcall(StyleFace, p, cfg) then stylePending = true end
	end
	local c = container
	if c then
		if not pcall(c.SetAuraGroupLayout, c, GROUP, GroupLayout(cfg)) then stylePending = true end
		if not pcall(Flow, c, cfg) then stylePending = true end
		if not pcall(PlaceContainer, c, cfg) then stylePending = true end
	end
end

-- Which view is up. The engine's one bar only while the stacks cannot be
-- seen at all: reads secret and no echo met yet this session.
local function UpdateShown()
	if not holder then return end
	useEngine = live and container ~= nil and not echoSeen and AuraSecret()
	if container then container:SetShown(useEngine) end
	stackLayer:SetShown((preview or (live and #starts > 0)) and not useEngine)
end

-- After the stacks changed.
local function Refresh()
	if not holder then return end
	UpdateShown()
	if stackLayer:IsShown() then Render() end
end

-- ---------------------------------------------------------------------------
-- Keeping it current
-- ---------------------------------------------------------------------------

local evt = CreateFrame('Frame')
local LIVE_EVENTS = { 'SPELL_UPDATE_COOLDOWN', 'PLAYER_REGEN_DISABLED', 'PLAYER_REGEN_ENABLED', 'PLAYER_DEAD',
	'ADDON_RESTRICTION_STATE_CHANGED' }
local listening = false

-- Registered only for an enabled Unholy Death Knight, so every other
-- character pays nothing per aura change or cast.
local function Listen(on)
	if on == listening then return end
	listening = on
	if on then
		evt:RegisterUnitEvent('UNIT_AURA', 'player')
		evt:RegisterUnitEvent('UNIT_SPELLCAST_SUCCEEDED', 'player')
		for _, e in ipairs(LIVE_EVENTS) do evt:RegisterEvent(e) end
	else
		evt:UnregisterEvent('UNIT_AURA')
		evt:UnregisterEvent('UNIT_SPELLCAST_SUCCEEDED')
		for _, e in ipairs(LIVE_EVENTS) do evt:UnregisterEvent(e) end
	end
end

local function Apply()
	local cfg = GetCfg()
	local on = cfg.enable and IsUnholy() and true or false
	live = on and not preview
	Listen(on)
	if not on then ClearWhere(false) end
	if not (on or preview) then
		if container then pcall(container.SetEnabled, container, false) end
		if holder then holder:Hide() end
		rereadNext = false
		return
	end

	EnsureFrame()
	PlaceHolder(cfg)
	if on then EnsureContainer(cfg) end
	Restyle(cfg)
	holder:Show()
	holder:EnableMouse(preview and not cfg.lock)

	local c = container
	if c then
		if live then
			-- Unit before enable: enabling registers the unit's aura events.
			-- Both rescan your auras by themselves when they change something
			-- (AuraContainerSharedMixin); a loading screen needs it asked.
			pcall(c.SetUnit, c, 'player')
			pcall(c.SetEnabled, c, true)
			if rereadNext then pcall(c.UpdateAllAuras, c) end
		else
			pcall(c.SetEnabled, c, false)
		end
	end
	rereadNext = false
	if live then Reconcile() end
	Refresh()
end

-- A dragged slider asks many times a frame; one Apply answers all of them.
ns.PFApply = ns.Coalesce(Apply)

ns.PFIsPreview = function() return preview end
ns.PFSetPreview = function(state)
	preview = state and true or false
	ClearWhere(true)
	if preview then
		-- Three stacks four seconds apart, then one more every four seconds,
		-- so the stack is always full and moving.
		local now = GetTime()
		for k = 2, 0, -1 do Add(true, now - k * PREVIEW_EVERY) end
		lastFake = now
	end
	Apply()
end

evt:RegisterEvent('PLAYER_ENTERING_WORLD')
evt:RegisterUnitEvent('PLAYER_SPECIALIZATION_CHANGED', 'player')
-- A key whose last fight ended before the timer stopped lifts its restriction
-- with no PLAYER_REGEN_ENABLED after it, so a refused restyle also retries on
-- the restriction's own change event - on the next frame, because the state
-- still reads the old value while that event is handed out (LustPots).
local QueueRestyle = ns.Coalesce(function()
	if stylePending then Restyle(GetCfg()) end
end)

evt:SetScript('OnEvent', function(_, event, a1, _, a3)
	if event == 'UNIT_AURA' then
		if Reconcile() then Refresh() else UpdateShown() end
	elseif event == 'SPELL_UPDATE_COOLDOWN' then
		if a1 == nil or secret(a1) then return end
		if OnEcho(a1, false) then Refresh() end
	elseif event == 'UNIT_SPELLCAST_SUCCEEDED' then
		if a3 == nil or secret(a3) then return end
		lastCastAt[a3] = GetTime()
		Log('cast ' .. a3)
		if OnEcho(a3, true) then Refresh() end
	elseif event == 'PLAYER_REGEN_DISABLED' then
		UpdateShown()
	elseif event == 'PLAYER_REGEN_ENABLED' then
		-- Readable again: square the bars with the real count, and anything
		-- refused in combat is ours to touch.
		if stylePending then Restyle(GetCfg()) end
		Reconcile()
		Refresh()
	elseif event == 'ADDON_RESTRICTION_STATE_CHANGED' then
		if stylePending then QueueRestyle() end
	elseif event == 'PLAYER_DEAD' then
		ClearWhere(false)
		Refresh()
	elseif event == 'PLAYER_ENTERING_WORLD' then
		rereadNext = true
		C_Timer.After(0.5, ns.PFApply)
	else
		ns.PFApply()
	end
end)

-- ---------------------------------------------------------------------------
-- Diagnostics
-- ---------------------------------------------------------------------------

local function Watched(id)
	for _, a in ipairs(AURA_IDS) do if a == id then return true end end
	return false
end

-- Out of combat your own buffs are readable: every aura under the two IDs,
-- with its stacks and time left. In combat it can only say "secret".
local function AuraLines()
	local U = _G.C_UnitAuras
	if not (U and U.GetAuraDataByIndex) then return { 'no aura API on this client' } end
	local out, now = {}, GetTime()
	for i = 1, 80 do
		local ok, a = pcall(U.GetAuraDataByIndex, 'player', i, 'HELPFUL')
		if not ok then out[#out + 1] = 'buff ' .. i .. ': read refused' break end
		if a == nil then break end
		if secret(a) or secret(a.spellId) then
			out[#out + 1] = 'buff ' .. i .. ': secret (in combat)'
			break
		end
		if Watched(a.spellId) then
			local apps, dur, exp = a.applications, a.duration, a.expirationTime
			if secret(apps) or secret(dur) or secret(exp) then
				out[#out + 1] = format('%d: up, values secret', a.spellId)
			else
				out[#out + 1] = format('%d: %s stack(s), %.1f of %.1f s left, instance %s', a.spellId,
					tostring(apps), (exp or 0) - now, dur or 0, tostring(a.auraInstanceID))
			end
		end
	end
	if #out == 0 then out[1] = 'none on you right now' end
	return out
end

local function Slash(msg)
	msg = type(msg) == 'string' and msg:lower() or ''
	if msg:find('opt') or msg:find('config') or msg:find('setting') then
		if ns.ShowConfig then ns.ShowConfig('class_dk') end
		C_Timer.After(0.2, function()
			if ns.ShowConfigSubTab then ns.ShowConfigSubTab('class_dk', 'Forbidden Sacrifice') end
		end)
		return
	end
	if msg:find('clear') then
		logN, logAt, logWhat = 0, {}, {}
		ns.Msg('Forbidden Sacrifice log cleared.')
		return
	end
	local cfg = GetCfg()
	local function yn(v) return v and 'yes' or 'no' end
	local S = _G.C_Secrets
	local level = 'n/a'
	if S and S.GetSpellAuraSecrecy then
		local ok, v = pcall(S.GetSpellAuraSecrecy, AURA)
		if ok then level = tostring(v) end
	end
	ns.Msg(format('Forbidden Sacrifice: enabled %s, Unholy %s, listening %s, preview %s, stack bars running %d',
		yn(cfg.enable), yn(IsUnholy()), yn(listening), yn(preview), RealCount()))
	ns.Msg(format('stacks readable now %s (aura secrecy level %s), echo seen %s, showing %s',
		yn(not AuraSecret()), level, yn(echoSeen),
		useEngine and 'the one engine bar (stacks not visible yet)' or 'a bar per stack'))
	ns.Msg(format('fallback: aura containers %s, container %s, buttons %d',
		ns.PFUnavailable and 'unavailable' or 'ok', container and 'built' or 'not built', #buttons))
	if failed then ns.Msg('|cffff5555fallback stopped: ' .. failed .. '|r') end
	if barFailed then ns.Msg('bar binding refused: ' .. barFailed) end
	if textFailed then ns.Msg('timer text refused: ' .. textFailed) end
	if stackFailed then ns.Msg('stack count refused: ' .. stackFailed) end
	for _, line in ipairs(AuraLines()) do ns.Msg('on you: ' .. line) end
	-- Newest last, in lines of eight.
	local parts, now = {}, GetTime()
	for k = LOG_MAX - 1, 0, -1 do
		local j = (logN - k - 1) % LOG_MAX + 1
		if logAt[j] then parts[#parts + 1] = format('%s (%.1fs ago)', logWhat[j], now - logAt[j]) end
	end
	if #parts == 0 then
		ns.Msg('log: empty')
	else
		for i = 1, #parts, 8 do
			ns.Msg('log: ' .. tconcat(parts, ', ', i, math.min(#parts, i + 7)))
		end
	end
end

_G.SLASH_XERIONPUTREFY1 = '/xerionputrefy'
_G.SLASH_XERIONPUTREFY2 = '/xerionsacrifice'
_G.SlashCmdList.XERIONPUTREFY = Slash
