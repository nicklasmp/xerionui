local _, ns = ...
local _G = _G

local hasElvUI = _G.ElvUI ~= nil
local E = hasElvUI and unpack(_G.ElvUI) or nil

local format, next, pcall, time = format, next, pcall, time
local ipairs, pairs, tonumber, tostring = ipairs, pairs, tonumber, tostring
local wipe = wipe
local strfind = string.find
local GetTime = GetTime
local CreateFrame = CreateFrame
local IsInInstance = IsInInstance
local GetInstanceInfo = GetInstanceInfo
local ResetInstances = ResetInstances
local GetGameTime = GetGameTime
local SendChatMessage = SendChatMessage
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local UnitIsGroupLeader = UnitIsGroupLeader
local UnitClass = UnitClass
local date = date

local issecretvalue = issecretvalue

local GetSpellCooldownDuration = C_Spell and C_Spell.GetSpellCooldownDuration
local GetSpellChargeDuration = C_Spell and C_Spell.GetSpellChargeDuration

local cdDebugOn = false

local PREFIX = '|cffff7d0aXerionUI|r '
local function Msg(text) print(PREFIX .. text) end
local function Round(n) return math.floor((n or 0) + 0.5) end
ns.Round = Round

local function IsSecret(v) return issecretvalue and issecretvalue(v) end
ns.IsSecret = IsSecret

-- KIRAFPS PROBES
-- KiraFPS (Dev_wow\KiraFPS, a profiler that never ships) times the plugin's frame
-- scripts by itself, but a module's C_Timer callbacks and its hooks on EllesmereUI
-- and Blizzard functions are not frames of the plugin's and stay out of its reach:
-- in a +20 on 2026-09-28 they were ~85% of the plugin's cost. So every file takes
-- hooksecurefunc and C_Timer through ns.Probe on its second line. Without KiraFPS -
-- every player - Probe hands back the client's own two and nothing changes. With it
-- (it loads before the plugin on purpose, so _G.KiraFPS is there by now) the pair it
-- hands back names each hook and timer after its module - 'EUI:hook|Name',
-- 'Crosshair:timer|Ticker 0.10' - and lets KiraFPS time the call. One-shot timers
-- are wrapped only while KiraFPS is recording (K.live); tickers and hooks, made once
-- and living on, always are, and KiraFPS passes them straight through when idle.
-- ns.Coalesce is named by the line that made it, 'Trinkets:577|Coalesce'.
do
	local K = _G.KiraFPS
	local Measure = type(K) == 'table' and type(K.Measure) == 'function' and K.Measure or nil
	local mfloor = math.floor

	local function Tag(d)
		if type(d) ~= 'number' or IsSecret(d) or d <= 0 then return '0' end
		if d < 1 then return format('%.2f', d) end
		if d < 10 then return tostring(mfloor(d + 0.5)) end
		return '10+'
	end

	local function Wrap(key, fn)
		if type(fn) ~= 'function' then return fn end
		return function(...) return Measure(key, fn, ...) end
	end

	function ns.Probe(module, hsf, timer)
		if not Measure then return hsf, timer end
		local keys = {}
		local function Key(kind, d)
			local t = kind .. ' ' .. Tag(d)
			local k = keys[t]
			if not k then
				k = module .. ':timer|' .. t
				keys[t] = k
			end
			return k
		end
		local proxy = setmetatable({}, { __index = timer })
		proxy.After = function(d, fn)
			if not K.live then return timer.After(d, fn) end
			return timer.After(d, Wrap(Key('After', d), fn))
		end
		proxy.NewTimer = function(d, fn)
			if not K.live then return timer.NewTimer(d, fn) end
			return timer.NewTimer(d, Wrap(Key('Timer', d), fn))
		end
		proxy.NewTicker = function(d, fn, n)
			return timer.NewTicker(d, Wrap(Key('Ticker', d), fn), n)
		end
		local function Hook(a, b, c)
			if type(a) == 'string' then return hsf(a, Wrap(module .. ':hook|' .. a, b)) end
			return hsf(a, b, Wrap(module .. ':hook|' .. tostring(b), c))
		end
		return Hook, proxy
	end

	-- The line that called ns.Coalesce. The top of the stack holds this function and
	-- Coalesce (both in this file), so the third plugin file:line on it is the
	-- caller's; counting matches instead of trusting a level number keeps it right
	-- whatever the client puts at level 1.
	function ns.ProbeCoalesced(fn)
		local ds = _G.debugstack
		if not Measure or not ds or type(fn) ~= 'function' then return fn end
		local ok, where = pcall(ds, 1, 4, 0)
		local mod, line, n = nil, nil, 0
		if ok and type(where) == 'string' then
			for m, l in where:gmatch('XerionUI%-Plugin_?(%w*)%.lua"?%]?:(%d+)') do
				n = n + 1
				mod, line = m, l
				if n == 3 then break end
			end
		end
		if mod == '' then mod = 'Core' end
		return Wrap((mod or 'Plugin') .. ':' .. (line or '?') .. '|Coalesce', fn)
	end
end
local hooksecurefunc, C_Timer = ns.Probe('Core', hooksecurefunc, C_Timer)

-- A yes/no question put to the client: true, false, or nil when it errored or
-- answered with a secret. The caller decides which way nil points, which under
-- the rule above is almost always "allow".
function ns.Ask(fn, ...)
	if not fn then return nil end
	local ok, v = pcall(fn, ...)
	if not ok or IsSecret(v) then return nil end
	return v and true or false
end

-- Could this UNIT_AURA payload have added or dropped an aura? An update-only
-- payload (a refresh or a stack change on an aura already there) cannot, and
-- that is most of what fires in combat. The table and each of its fields can
-- arrive secret in restricted content and a secret cannot be tested, so an
-- unreadable payload - or one that errors - counts as yes, and so does a
-- missing one (Blizzard treats nil as a full update).
do
	local issecrettable = _G.issecrettable
	local function Churns(info)
		if IsSecret(info) or info == nil or (issecrettable and issecrettable(info)) then return true end
		local full, added, removed = info.isFullUpdate, info.addedAuras, info.removedAuraInstanceIDs
		if IsSecret(full) or IsSecret(added) or IsSecret(removed) then return true end
		return (full or added or removed) and true or false
	end
	function ns.AuraPayloadChurns(info)
		local ok, churns = pcall(Churns, info)
		return not ok or churns
	end
end

ns.IS_121 = (select(4, _G.GetBuildInfo()) or 0) >= 120100

function ns.IsAddOnLoaded(name)
	local f = (_G.C_AddOns and _G.C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
	if not f then return false end
	local ok, loaded = pcall(f, name)
	return (ok and loaded) and true or false
end

local function PlainName(s)
	s = tostring(s or '')
	s = s:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', ''):gsub('|T.-|t', '')
	return (s:gsub('^%s+', ''):gsub('%s+$', '')):lower()
end
ns.PlainName = PlainName

function ns.Trim(s)
	return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

local PARENT

local function PlayerClassToken()
	local _, token = UnitClass('player')
	return token or 'UNKNOWN'
end
local function PlayerClassLocalized()
	local localized = UnitClass('player')
	return localized or PlayerClassToken()
end

local playerClassToken
function ns.IsClass(token)
	if playerClassToken == nil then
		local ok, _, cls = pcall(UnitClass, 'player')
		if not ok or IsSecret(cls) then return true end
		if cls then playerClassToken = cls end
	end
	return playerClassToken == nil or playerClassToken == token
end

function ns.PlayerSpec()
	local CSI = _G.C_SpecializationInfo
	local get = (CSI and CSI.GetSpecialization) or _G.GetSpecialization
	if not get then return nil, false end
	local ok, spec = pcall(get)
	if not ok then return nil, false end
	if IsSecret(spec) then return nil, true end
	return spec, false
end

function ns.IsSpec(token, specIndex)
	if not ns.IsClass(token) then return false end
	local spec, secretRead = ns.PlayerSpec()
	if secretRead then return true end
	return spec == specIndex
end

local defaults = {
	font = '',
}
-- Read-only, for XerionUI Copy: tells "never placed on this profile" (still at defaults) from a real position.
ns.coreDefaults = defaults

local function LSM()
	return _G.LibStub and _G.LibStub('LibSharedMedia-3.0', true)
end
ns.LSM = LSM

local fontPathCache = {}

function ns.GetFont(fallback)
	local db = _G.XerionUIChangesDB
	local name = db and db.font
	if name and name ~= '' then
		local cached = fontPathCache[name]
		if cached then return cached end
		local lib = LSM()
		if lib and lib.Fetch then
			local ok, path = pcall(lib.Fetch, lib, 'font', name, true)
			if ok and type(path) == 'string' and path ~= '' then
				fontPathCache[name] = path
				return path
			end
		end
	end
	return fallback or _G.STANDARD_TEXT_FONT
end

function ns.FontOptions()
	local out = { { value = '', text = 'Default (per module)' } }
	local lib = LSM()
	local hash = lib and lib.HashTable and lib:HashTable('font')
	if hash then
		local names = {}
		for name in pairs(hash) do names[#names + 1] = name end
		table.sort(names, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
		for _, name in ipairs(names) do out[#out + 1] = { value = name, text = name } end
	end
	return out
end

function ns.FontApply()
	wipe(fontPathCache)
	ns.ApplyAllSettings()
end

function ns.SoundOptions(current)
	local out = { { value = 'None', text = 'None' } }
	local lib = LSM()
	local hash = lib and lib.HashTable and lib:HashTable('sound')
	if hash then
		-- Each name's sort key is worked out once here rather than twice per
		-- comparison (PlainName is five gsubs). Same keys, same comparator
		-- answers, so the same order. Built per call: LibSharedMedia can
		-- register a sound at any time.
		local names, plain = {}, {}
		for name in pairs(hash) do
			names[#names + 1] = name
			plain[name] = PlainName(name)
		end
		table.sort(names, function(a, b) return plain[a] < plain[b] end)
		for _, name in ipairs(names) do out[#out + 1] = { value = name, text = name } end
	end
	if current and current ~= 'None' then
		local found = false
		for _, o in ipairs(out) do if o.value == current then found = true break end end
		if not found then table.insert(out, 2, { value = current, text = current }) end
	end
	return out
end

-- A sound's file path from its LibSharedMedia name, or nil for "None".
function ns.SoundPath(name)
	if type(name) ~= 'string' or name == '' or name == 'None' then return nil end
	local lib = LSM()
	return lib and lib.Fetch and lib:Fetch('sound', name, true) or nil
end

function ns.PlaySoundByName(name)
	local path = ns.SoundPath(name)
	if path then PlaySoundFile(path, 'Master') end
end

function ns.GothamNarrowBlackFont()
	local lib = LSM()
	local font = lib and lib.Fetch and lib:Fetch('font', 'GothamNarrowBlack', true)
	return ns.GetFont(font or _G.STANDARD_TEXT_FONT)
end

function ns.BarTexture()
	local lib = LSM()
	local tex = lib and lib.Fetch and lib:Fetch('statusbar', 'Clean', true)
	return tex or 'Interface\\Buttons\\WHITE8X8'
end

local function DeepCopy(v)
	if type(v) ~= 'table' then return v end
	local r = {}
	for k, val in pairs(v) do r[k] = DeepCopy(val) end
	return r
end

ns.CopyValue = DeepCopy

local wholeSecondsFmt
function ns.WholeSecondsFormatter()
	if wholeSecondsFmt == nil then
		wholeSecondsFmt = false
		local CSU = _G.C_StringUtil
		if CSU and CSU.CreateNumericRuleFormatter then
			local f = CSU.CreateNumericRuleFormatter()
			if f and f.SetBreakpoints then
				local up = (_G.Enum and _G.Enum.NumericRuleFormatRounding
					and _G.Enum.NumericRuleFormatRounding.Up) or 1
				local ok = pcall(f.SetBreakpoints, f, {
					{ threshold = 0, format = '%d', components = { { step = 1, rounding = up } } },
				})
				if ok then wholeSecondsFmt = f end
			end
		end
	end
	return wholeSecondsFmt or nil
end

function ns.DurationTextOptions()
	local f = ns.WholeSecondsFormatter()
	if f then return { formatter = f, textFormatter = f } end
	if _G.C_AuraContainerUtil then return {} end
	return { textFormat = '%d' }
end

function ns.ZoomCoords(zoomPct)
	local z = (zoomPct or 0) / 100
	if z < 0 then z = 0 elseif z > 0.45 then z = 0.45 end
	return z, 1 - z
end

-- The one palette for the four secondary stats. Secondary Stats paints its
-- rows with these and the inspect panel colours its stat letters from the
-- same table, so the two read as one set without anybody keeping two copies
-- in step.
ns.STAT_COLORS = {
	crit    = { 0.878, 0.110, 0.110 },
	haste   = { 0.835, 0.780, 0.000 },
	mastery = { 0.573, 0.337, 1.000 },
	vers    = { 0.749, 0.749, 0.749 },
}

-- The 1px black outline every icon in this addon wears. It is a black texture
-- filling the frame with the icon inset one pixel on each side, so the border
-- lives INSIDE the icon's own footprint: it never eats into the spacing between
-- neighbouring icons and it cannot be clipped by whatever the icon sits on.
-- BuffWatch, Trinkets, Externals, FieryBrand, Potion and friends each wrote
-- these six lines out by hand before this helper existed; they are left alone
-- because several of them recolour or resize the border afterwards and a shared
-- refactor buys nothing. New code should call this and keep the two returns.
function ns.PixelBorderIcon(frame, layer, sublayer)
	local border = frame:CreateTexture(nil, 'BACKGROUND')
	border:SetColorTexture(0, 0, 0, 1)
	border:SetAllPoints()
	local icon = frame:CreateTexture(nil, layer or 'ARTWORK', nil, sublayer)
	icon:SetPoint('TOPLEFT', 1, -1)
	icon:SetPoint('BOTTOMRIGHT', -1, 1)
	return icon, border
end

-- Runs fn once on the next frame however many times it is asked this frame. A
-- dragged slider calls a module's Apply on every step and a pull is a burst of
-- plate events; one pass on the next frame answers all of them.
-- The raw C_Timer, not the probed one: KiraFPS times fn itself under the line that
-- made it (see KIRAFPS PROBES), and a second wrapper around run would add nothing.
function ns.Coalesce(fn)
	fn = ns.ProbeCoalesced(fn)
	local queued = false
	local function run()
		queued = false
		fn()
	end
	return function()
		if queued then return end
		queued = true
		_G.C_Timer.After(0, run)
	end
end

-- The aura-sensor kit (Augment Rune, DoT Coverage). Asked of the client rather
-- than read off a build number: the template is the feature. The tail template
-- is what lets a frame of ours hang off a container at all - once a container
-- has an aura group its size is the engine's business, and only a frame that
-- gave up its own layout scripts may be anchored to it (see the comment in
-- CustomAuraContainerSharedMixin:AddAuraGroup).
function ns.HasTemplate(name)
	local X = _G.C_XMLUtil
	if not (X and X.GetTemplateInfo) then return false end
	local ok, info = pcall(X.GetTemplateInfo, name)
	return ok and info ~= nil
end

ns.TAIL_TEMPLATE = 'DisableUntrustedLayoutScriptsTemplate'

-- The lust lockout: Sated and each class's twin of it. Bloodlust reads them off
-- the player; Co-Tank keeps them out of the other tank's debuff row, where after
-- the first lust of the night they sit on both tanks for ten minutes.
ns.SATED_IDS = { 57723, 57724, 80354, 95809, 160455, 264689, 390435, 428628 }

do
	local function InitSensorButton(b)
		-- The engine's button is here to take up room and for nothing else. It
		-- draws nothing unless it is handed an icon, and it must not take the
		-- mouse: lit, its slot is a whole stride of play field.
		pcall(b.SetSize, b, 1, 1)
		pcall(b.SetMouseClickEnabled, b, false)
		pcall(b.SetMouseMotionEnabled, b, false)
	end

	-- One aura group, room for one aura, laid out `stride` pixels wide: lit, the
	-- container is `stride` wide; bare, it is one pixel. Returns pcall's answer.
	function ns.AddSensorGroup(container, key, filter, include, stride)
		return pcall(container.AddAuraGroup, container, key, filter, {
			maxFrameCount = 1,
			candidateFilters = { includeSpellIDs = include },
			initializeFrame = InitSensorButton,
			-- The stride is the whole point; the button's own size plays no part
			-- (CustomAuraContainerFlowLayoutMixin:GetElementSize).
			layout = { elementWidth = stride, elementHeight = 1, elementSpacing = 0, lineSpacing = 0 },
		})
	end
end

function ns.IconCoords(w, h, crop)
	local l, r, t, b = crop, 1 - crop, crop, 1 - crop
	if w > h then
		local inset = (1 - h / w) * (b - t) / 2
		t, b = t + inset, b - inset
	elseif h > w then
		local inset = (1 - w / h) * (r - l) / 2
		l, r = l + inset, r - inset
	end
	return l, r, t, b
end

local function IdMatches(v, want) return not IsSecret(v) and v == want end

function ns.CooldownMatches(cooldownID, want)
	if not cooldownID or IsSecret(cooldownID) then return false end
	local get = _G.C_CooldownViewer and _G.C_CooldownViewer.GetCooldownViewerCooldownInfo
	if not get then return false end
	local ok, info = pcall(get, cooldownID)
	if not ok or not info then return false end
	if IdMatches(info.spellID, want) or IdMatches(info.linkedSpellID, want)
		or IdMatches(info.overrideSpellID, want) or IdMatches(info.overrideTooltipSpellID, want) then
		return true
	end
	local linked = info.linkedSpellIDs
	if type(linked) == 'table' then
		for i = 1, #linked do
			if IdMatches(linked[i], want) then return true end
		end
	end
	return false
end

local cfgCache = {}

-- Each module's DEFAULTS by db key, recorded on first use. Read-only; XerionUI Copy (a separate
-- addon, via _G.XerionUIPlugin.__ns) compares against it to find modules never placed on a profile.
ns.moduleDefaults = {}

function ns.InvalidateModuleCfg() wipe(cfgCache) wipe(fontPathCache) end

-- The defaults are recorded after the cache check: the cache is only ever
-- filled below, so the first call for a key (and the first after a profile
-- switch wipes the cache) still records them, and every module passes the
-- same file-level DEFAULTS table each time.
function ns.ModuleCfg(key, moduleDefaults, migrate)
	local cached = cfgCache[key]
	if cached then return cached end
	if moduleDefaults then ns.moduleDefaults[key] = moduleDefaults end
	local db = _G.XerionUIChangesDB
	if not db then return moduleDefaults end
	local cfg = db[key]
	if not cfg then
		cfg = {}
		db[key] = cfg
	end
	for k, v in pairs(moduleDefaults) do
		if cfg[k] == nil then cfg[k] = DeepCopy(v) end
	end
	if migrate then migrate(cfg) end
	cfgCache[key] = cfg
	return cfg
end

local function NotLocked(cfg) return not cfg.lock end

-- DRAG ANYTHING THE PREVIEW SHOWS
-- A module's draggable frame is often only the first piece of what it draws.
-- Interrupts is one row tall and hangs its other rows under it; Externals and
-- DoT Coverage pin the FIRST icon to the saved spot and let the row run out of
-- the frame (why is in LayoutCells there); Co-Tank's debuffs sit beside its bar.
-- The mouse only ever reached the frame's own rect, so a five-row preview had
-- one row that moved and four that did nothing, and nothing said which. Growing
-- those frames over their content would move what gets saved (the frame's
-- CENTER), so the frames stay as they are and the content is measured instead:
--   * ns.ContentBounds(frame) - the frame plus everything visible under it, in
--     screen pixels. Move mode (XerionUI-Plugin_EditMode.lua) sizes its overlays
--     with it.
--   * ns.DragAnywhere(frame) - a catcher child stretched over those bounds that
--     hands its drag to the frame. ns.MakeDraggable adds one to every frame it
--     is given; a module with its own drag scripts calls it after setting them.
--     The catcher shows only while the frame takes the mouse (Preview and
--     unlocked, in the modules), sits at the frame's own level so a clickable
--     child keeps its clicks, and re-measures every 0.25 s while the settings
--     window is open, where previews add and drop bars. With the window shut it
--     measures once when shown and stops, so nothing ticks in play. It takes
--     the right button only: every drag in the plugin is a right-drag, and the
--     settings hints say so.
-- The walk only reads rects. It skips forbidden frames and anything whose rect,
-- visibility or children come back secret, measures nothing in combat (engine
-- aura buttons are forbidden there), stops MAX_DEPTH levels down and gives up
-- after MAX_NODES objects. Frames already protected get no catcher.
do
	local mmin, mmax = math.min, math.max
	local MAX_DEPTH, MAX_NODES, MIN_PX = 5, 300, 2
	local L, B, R, T, nodes
	local catchers = setmetatable({}, { __mode = 'k' })
	local catchOf = setmetatable({}, { __mode = 'k' })

	-- Every method call goes through one of these, so pcall also catches a
	-- forbidden object at the index, not only at the call.
	local function Forbidden(o) return o:IsForbidden() end
	local function Visible(o) return o:IsVisible() end
	local function ScaledRect(o) return o:GetScaledRect() end
	local function EffScale(o) return o:GetEffectiveScale() end
	local function FrameAlpha(o) return o:GetEffectiveAlpha() end
	local function RegionAlpha(o) return o:GetAlpha() end
	local function Regions(o) return { o:GetRegions() } end
	local function Children(o) return { o:GetChildren() } end

	local function Shown(o)
		local ok, v = pcall(Visible, o)
		return ok and not IsSecret(v) and v and true or false
	end

	-- A secret alpha counts as shown: it may well be.
	local function Faded(ok, a)
		return ok and not IsSecret(a) and type(a) == 'number' and a < 0.05
	end

	-- Adds o's rect. False when it cannot be read (secret anchoring, no anchor
	-- yet); the caller then leaves o's children out too.
	local function Add(o)
		local ok, l, b, w, h = pcall(ScaledRect, o)
		if not ok or IsSecret(l) or IsSecret(b) or IsSecret(w) or IsSecret(h) then return false end
		if not (l and b and w and h) then return false end
		if w >= MIN_PX and h >= MIN_PX then
			if L then
				L, B, R, T = mmin(L, l), mmin(B, b), mmax(R, l + w), mmax(T, b + h)
			else
				L, B, R, T = l, b, l + w, b + h
			end
		end
		return true
	end

	local function Walk(o, depth)
		nodes = nodes + 1
		if nodes > MAX_NODES or catchers[o] then return end
		local okF, forbidden = pcall(Forbidden, o)
		if not okF or IsSecret(forbidden) or forbidden then return end
		if not Shown(o) or Faded(pcall(FrameAlpha, o)) or not Add(o) then return end
		local ok, list = pcall(Regions, o)
		if ok then
			for i = 1, #list do
				local r = list[i]
				if not IsSecret(r) and Shown(r) and not Faded(pcall(RegionAlpha, r)) then Add(r) end
			end
		end
		if depth >= MAX_DEPTH then return end
		ok, list = pcall(Children, o)
		if ok then
			for i = 1, #list do
				local k = list[i]
				if not IsSecret(k) then Walk(k, depth + 1) end
			end
		end
	end

	-- left, bottom, right, top in screen pixels, or nil when nothing under the
	-- frame could be measured (hidden, faded out, secret anchoring).
	function ns.ContentBounds(frame)
		if not frame then return nil end
		L, B, R, T, nodes = nil, nil, nil, nil, 0
		Walk(frame, 0)
		return L, B, R, T
	end

	local function Fit(c)
		local f = c:GetParent()
		local l, b, r, t = ns.ContentBounds(f)
		local okR, fl, fb = pcall(ScaledRect, f)
		local okS, s = pcall(EffScale, f)
		c:ClearAllPoints()
		c:SetFrameLevel(f:GetFrameLevel())
		if not (l and okR and okS) or IsSecret(fl) or IsSecret(fb) or IsSecret(s)
			or not (fl and fb and s) or s <= 0 then
			c:SetAllPoints(f)
			return
		end
		-- the catcher is the frame's child, so its units are the frame's
		c:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', (l - fl) / s, (b - fb) / s)
		c:SetSize((r - l) / s, (t - b) / s)
	end

	local function WindowOpen()
		local w = _G.KiraPluginConfig
		return w and w:IsShown() and true or false
	end

	local function Tick(c, elapsed)
		c.__acc = c.__acc + elapsed
		if c.__acc < 0.25 then return end
		c.__acc = 0
		if not _G.InCombatLockdown() then Fit(c) end
		if not WindowOpen() then c:SetScript('OnUpdate', nil) end
	end

	-- Measures on the next frame, once the layout that caused this has settled.
	local function Arm(c)
		c.__acc = 1
		c:SetScript('OnUpdate', Tick)
	end

	local function Sync(frame)
		local c = catchOf[frame]
		if not c then return end
		local on = frame:IsMouseEnabled()
		if IsSecret(on) then return end
		if on then
			c:Show()
			Arm(c)
		elseif c:IsShown() then
			c:Hide()
		end
	end

	function ns.DragAnywhere(frame)
		if not frame or catchOf[frame] then return end
		local okP, protected = pcall(frame.IsProtected, frame)
		if not okP or protected then return end
		local c = CreateFrame('Frame', nil, frame)
		catchers[c], catchOf[frame] = true, c
		c:SetAllPoints(frame)
		c:SetFrameLevel(frame:GetFrameLevel())
		c:EnableMouse(true)
		c:RegisterForDrag('RightButton')
		-- looked up at drag time, so a module that replaces its scripts later
		-- still gets the drag
		c:SetScript('OnDragStart', function()
			local fn = frame:GetScript('OnDragStart')
			if fn then fn(frame) end
		end)
		c:SetScript('OnDragStop', function()
			local fn = frame:GetScript('OnDragStop')
			if fn then fn(frame) end
		end)
		c:SetScript('OnShow', Arm)
		c:Hide()
		hooksecurefunc(frame, 'EnableMouse', Sync)
		Sync(frame)
	end

	function ns.MakeDraggable(frame, getCfg, xKey, yKey, onMoved, canDrag)
		canDrag = canDrag or NotLocked
		frame:SetScript('OnDragStart', function(self)
			if not canDrag(getCfg()) then return end
			self:StartMoving()
		end)
		frame:SetScript('OnDragStop', function(self)
			self:StopMovingOrSizing()
			local cx, cy = self:GetCenter()
			local ux, uy = _G.UIParent:GetCenter()
			if cx and ux then
				local cfg = getCfg()
				cfg[xKey] = Round(cx - ux)
				cfg[yKey] = Round(cy - uy)
			end
			if onMoved then onMoved() end
		end)
		ns.DragAnywhere(frame)
	end
end

-- A text beat that grows out of the middle of the words: scales up to scaleTo
-- and dims to alphaTo over `half` seconds, then back, until Stop. Scale
-- ANIMATIONS grew out of a corner on the 12.x client whatever SetOrigin said -
-- on the message frame, on a 1x1 centred frame and on the font string itself,
-- three builds in a row (Wrong Target, Didn't kick). This goes through layout
-- instead: the text sits on a 1x1 holder hung by its CENTER with no offset,
-- and SetScale on such a frame keeps its centre where it is (only an anchor
-- OFFSET would be scaled with it). The dim is on the font string, so it
-- multiplies with any alpha the frames above carry, a secret one included.
-- OnUpdate runs only while playing, and not at all while the holder is hidden.
-- Returns { text = font string, Play, Stop, IsPlaying }.
function ns.TextPulse(parent, scaleTo, alphaTo, half)
	local holder = CreateFrame('Frame', nil, parent)
	holder:SetSize(1, 1)
	holder:SetPoint('CENTER', parent, 'CENTER', 0, 0)
	local fs = holder:CreateFontString(nil, 'OVERLAY')
	fs:SetPoint('CENTER', holder, 'CENTER', 0, 0)
	local t = 0
	local function Beat(_, elapsed)
		t = t + elapsed
		local k = (1 - math.cos(math.pi * t / half)) / 2
		holder:SetScale(1 + (scaleTo - 1) * k)
		fs:SetAlpha(1 - (1 - alphaTo) * k)
	end
	local p = { text = fs }
	function p.Play()
		t = 0
		holder:SetScript('OnUpdate', Beat)
	end
	function p.Stop()
		holder:SetScript('OnUpdate', nil)
		holder:SetScale(1)
		fs:SetAlpha(1)
	end
	function p.IsPlaying() return holder:GetScript('OnUpdate') ~= nil end
	return p
end

local MDI_DUNGEONS = {
	{ name = 'Altar of Fangs',              short = 'Altar',      mapID = 588 },
	{ name = 'Voidscar Arena',              short = 'Arena',      mapID = 585 },
	{ name = 'Den of Nalorakk',             short = 'Den',        mapID = 586 },
	{ name = 'Murder Row',                  short = 'Murder Row', mapID = 587 },
	{ name = 'The Blinding Vale',           short = 'Vale',       mapID = 584 },
	{ name = "Kings' Rest",                 short = 'Kings',      mapID = 249 },
	{ name = 'Temple of Sethraliss',        short = 'Temple',     mapID = 250 },
	{ name = 'Ruby Life Pools',             short = 'Ruby',       mapID = 399 },
	{ name = "Eco-Dome Al'dani",            short = 'Eco-Dome' },
	{ name = 'Operation: Floodgate',        short = 'Floodgate' },
	{ name = 'Ara-Kara, City of Echoes',    short = 'Ara-Kara' },
	{ name = 'Priory of the Sacred Flame',  short = 'Priory' },
	{ name = 'Tazavesh: Streets of Wonder', short = 'Streets' },
	{ name = "Tazavesh: So'leah's Gambit",  short = 'Gambit' },
	{ name = 'Halls of Atonement',          short = 'Halls' },
}

local function MDINormalize(text)
	if type(text) ~= 'string' then return nil end
	local key = text:lower():gsub('%W', '')
	return (key ~= '') and key or nil
end

local mdiOrder
local function MDIOrder()
	if not mdiOrder then
		mdiOrder = {}
		for i, dungeon in ipairs(MDI_DUNGEONS) do
			dungeon.key = dungeon.key or MDINormalize(dungeon.name)
			mdiOrder[i] = dungeon
		end
		table.sort(mdiOrder, function(a, b) return #(a.key or '') > #(b.key or '') end)
	end
	return mdiOrder
end

function ns.MDIFindDungeon(text)
	local key = MDINormalize(text)
	if not key then return nil end
	for _, dungeon in ipairs(MDIOrder()) do
		if dungeon.key and key:find(dungeon.key, 1, true) then return dungeon end
	end
	return nil
end

function ns.MDIShortName(text)
	local dungeon = ns.MDIFindDungeon(text)
	return dungeon and (dungeon.short or dungeon.name) or nil
end

local mdiResolved = false
function ns.MDIResolveMapIDs()
	if mdiResolved then return end
	local CM = _G.C_ChallengeMode
	if not (CM and CM.GetMapTable and CM.GetMapUIInfo) then return end
	local ok, maps = pcall(CM.GetMapTable)
	if not ok or type(maps) ~= 'table' or #maps == 0 then return end
	mdiResolved = true
	for _, mapID in ipairs(maps) do
		local okName, name = pcall(CM.GetMapUIInfo, mapID)
		local dungeon = okName and ns.MDIFindDungeon(name)
		if dungeon and dungeon.mapID ~= mapID then
			dungeon.mapID = mapID
		end
	end
end

_G.SLASH_XERIONMDIMAPS1 = '/xerionmaps'
_G.SlashCmdList.XERIONMDIMAPS = function()
	local function p(...) print('|cffff7d0aKiraMDI|r', ...) end
	local CM = _G.C_ChallengeMode
	local ok, maps = pcall(CM and CM.GetMapTable or function() end)
	if not ok or type(maps) ~= 'table' or #maps == 0 then
		p('no challenge-mode maps available yet - open the keystone UI or the group finder once, then retry.')
		return
	end
	ns.MDIResolveMapIDs()
	p(('%d challenge-mode map(s):'):format(#maps))
	for _, mapID in ipairs(maps) do
		local okName, name = pcall(CM.GetMapUIInfo, mapID)
		if not okName or type(name) ~= 'string' then name = '?' end
		local known = ns.MDIFindDungeon(name)
		p(('    { name = "%s", short = "%s", mapID = %d },%s'):format(
			name, known and (known.short or name) or name, mapID,
			known and ' |cff888888(in roster)|r' or ' |cff00ff00(new)|r'))
	end
end

_G.SLASH_XERIONZONE1 = '/xerionzone'
_G.SlashCmdList.XERIONZONE = function()
	local function p(...) print('|cffff7d0aKiraZone|r', ...) end
	local CMap = _G.C_Map
	if not (CMap and CMap.GetBestMapForUnit and CMap.GetMapInfo) then
		p('C_Map is unavailable on this client.')
		return
	end
	local ok, uiMapID = pcall(CMap.GetBestMapForUnit, 'player')
	if not ok or type(uiMapID) ~= 'number' then
		p('no map for the player right now.')
		return
	end
	local depth = 0
	while uiMapID and uiMapID > 0 and depth < 16 do
		local okI, info = pcall(CMap.GetMapInfo, uiMapID)
		info = (okI and type(info) == 'table') and info or nil
		p(('%suiMapID %d    %s'):format(('  '):rep(depth), uiMapID, info and info.name or '?'))
		uiMapID = info and info.parentMapID
		depth = depth + 1
	end
end

local function DeepMerge(dst, src)
	for k, v in pairs(src) do
		if type(v) == 'table' then
			if type(dst[k]) ~= 'table' then dst[k] = {} end
			DeepMerge(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

local function GetCfg() return _G.XerionUIChangesDB or defaults end
local function DebugStatus()
	Msg('status:')
	print('  ElvUI detected:', hasElvUI and 'yes' or 'no')
	print('  XerionUI QoL features are active; open /xui for settings.')
end

do
	local OPTIONS_ADDON = 'XerionUI-Plugin_Options'

	local function LoadOptions()
		if C_AddOns.IsAddOnLoaded(OPTIONS_ADDON) then return true end
		local loaded, reason = C_AddOns.LoadAddOn(OPTIONS_ADDON)
		if not loaded and reason == 'DISABLED' then
			C_AddOns.EnableAddOn(OPTIONS_ADDON, UnitName('player'))
			loaded, reason = C_AddOns.LoadAddOn(OPTIONS_ADDON)
		end
		if loaded then return true end
		local why = _G['ADDON_' .. tostring(reason)] or tostring(reason)
		Msg(('the settings window could not load (%s). Make sure the "XerionUI-Plugin Options" addon is installed and enabled.'):format(why))
		return false
	end

	function ns.ShowConfig(page)
		local wasLoaded = C_AddOns.IsAddOnLoaded(OPTIONS_ADDON)
		if not LoadOptions() then return end
		local function Open()
			if page and ns.ShowConfigPage then ns.ShowConfigPage(page)
			elseif ns.OpenConfig then ns.OpenConfig()
			else Msg('config window failed to load.') end
		end
		if wasLoaded then Open() else C_Timer.After(0, Open) end
	end
end
ns.Msg = Msg

local function HandleSlash(msg)
	msg = msg or ''
	local cmd, rest = msg:match('^%s*(%S*)%s*(.-)%s*$')
	cmd = cmd and cmd:lower() or ''
	local sub, rest2 = rest:match('^(%S*)%s*(.-)%s*$')
	if sub == '' then sub = nil end

	if cmd == '' or cmd == 'config' or cmd == 'options' then
		ns.ShowConfig()
	elseif cmd == 'status' then
		DebugStatus()
	elseif cmd == 'version' or cmd == 'ver' then
		if sub == 'off' or sub == 'on' then
			if ns.SetVersionNotice then ns.SetVersionNotice(sub == 'on') end
		elseif ns.PrintVersionInfo then
			ns.PrintVersionInfo()
		end
	elseif cmd == 'help' or cmd == '?' then
		Msg('commands:')
		print('  /xqol            - open the Xerion feature settings')
		print('  /xqol status     - print current state')
		print('  /xqol cd debug             - toggle debug prints')
		print('  /xqol break summary        - M+ break stats')
		print('  /xqol version              - addon + XerionUI Installer versions')
		print('  /xqol version off|on       - silence/restore the out-of-date notice')
		print('  (everything else is in the window)')
	else
		ns.ShowConfig()
	end
end

local PROFILE_DEFAULT = 'Default'

local PROFILE_EXCLUDE = {
	dungeonAlerts = true,
	kiraDungeonProfiles = true,
}

local function FeatureKeys(db)
	local keys = {}
	for k in pairs(db) do
		if k ~= 'kiraProfiles' and not PROFILE_EXCLUDE[k]
			and not (type(k) == 'string' and k:sub(1, 2) == '__') then
			keys[#keys + 1] = k
		end
	end
	return keys
end

local function SnapshotToProfile(name)
	local db = _G.XerionUIChangesDB
	if not db or not name then return end
	db.kiraProfiles = db.kiraProfiles or {}
	local snap = {}
	for _, k in ipairs(FeatureKeys(db)) do snap[k] = DeepCopy(db[k]) end
	db.kiraProfiles[name] = snap
end

local function LoadProfileIntoRoot(name)
	local db = _G.XerionUIChangesDB
	local prof = db and db.kiraProfiles and db.kiraProfiles[name]
	if not prof then return end
	for _, k in ipairs(FeatureKeys(db)) do db[k] = nil end
	for k, v in pairs(prof) do
		if not PROFILE_EXCLUDE[k] then db[k] = DeepCopy(v) end
	end
	DeepMerge(db, defaults)
	ns.InvalidateModuleCfg()
end

function ns.GetCurrentProfile()
	local db = _G.XerionUIChangesDB
	if db and db.__activeProfile then return db.__activeProfile end
	local c = _G.XerionUIChangesCharDB
	return (c and c.profile) or PROFILE_DEFAULT
end

function ns.GetProfileNames()
	local db = _G.XerionUIChangesDB
	local out = {}
	if db and db.kiraProfiles then
		for name in pairs(db.kiraProfiles) do out[#out + 1] = name end
	end
	table.sort(out)
	return out
end

function ns.ApplyAllSettings()
	local names = {
		'ExtApply', 'CTApply', 'BWApply', 'CHApply', 'SSApply', 'RMApply', 'BLApply', 'PTApply', 'RecupApply', 'BMApply', 'CDSApply', 'SLApply', 'PAUApply', 'KVApply', 'INSApply', 'RCApply',
		'FBApply', 'MageApply', 'SHMApply', 'WHIApply', 'BFRApply', 'RFLApply', 'CUApply', 'BPApply', 'BILApply', 'BBApply', 'RKMApply', 'BLFApply', 'PFApply', 'DRWApply', 'DRWSApply', 'BSApply', 'TSApply',
		'EUIApplyFocusMark', 'EUIApplyFocusCastbar', 'EUIApplyDebuffColors', 'EUIApplyFocusRange',
		'EUIIntApply', 'EFKApply', 'EUINPRefresh', 'EUINPApplyNameAlpha', 'EUINPApplyArrow', 'EUINPApplyShield', 'ABRApply', 'EMCApply', 'EMSApply', 'EMIApply', 'ECUApply', 'EPHApply',
		'DAApply', 'IKApply', 'HXApply', 'CoTApply', 'DoTApply', 'SQApply', 'AGCApply', 'ARApply', 'SHApply',
		'CCBApply', 'CCCastApply',
	}
	for _, n in ipairs(names) do
		local f = ns[n]
		if type(f) == 'function' then pcall(f) end
	end
end

function ns.SwitchProfile(name)
	local db = _G.XerionUIChangesDB
	if not db or not name then return end
	local cur = ns.GetCurrentProfile()
	if name == cur then return end
	db.kiraProfiles = db.kiraProfiles or {}
	SnapshotToProfile(cur)
	if not db.kiraProfiles[name] then SnapshotToProfile(name) end
	LoadProfileIntoRoot(name)
	db.__activeProfile = name
	ns.ApplyAllSettings()
end

function ns.NewProfile(name)
	local db = _G.XerionUIChangesDB
	if not db or not name or name == '' then return end
	db.kiraProfiles = db.kiraProfiles or {}
	SnapshotToProfile(ns.GetCurrentProfile())
	SnapshotToProfile(name)
	db.__activeProfile = name
end

function ns.DeleteProfile(name)
	local db = _G.XerionUIChangesDB
	if not db or not db.kiraProfiles then return end
	if name == PROFILE_DEFAULT or name == ns.GetCurrentProfile() then return end
	db.kiraProfiles[name] = nil
end

local DUNGEON_PROFILE_DEFAULT = 'Default'

local function DungeonStore()
	local db = _G.XerionUIChangesDB
	if not db then return nil end
	db.kiraDungeonProfiles = db.kiraDungeonProfiles or {}
	return db.kiraDungeonProfiles
end

local function SnapshotDungeon(name)
	local db, store = _G.XerionUIChangesDB, DungeonStore()
	if not (db and store and name) then return end
	store[name] = DeepCopy(db.dungeonAlerts or {})
end

local function LoadDungeonIntoRoot(name)
	local db, store = _G.XerionUIChangesDB, DungeonStore()
	local prof = store and store[name]
	if not (db and prof) then return end
	db.dungeonAlerts = DeepCopy(prof)
	ns.InvalidateModuleCfg()
end

function ns.GetDungeonProfile()
	local db = _G.XerionUIChangesDB
	return (db and db.__dungeonProfile) or DUNGEON_PROFILE_DEFAULT
end

function ns.GetDungeonProfileNames()
	local store = DungeonStore()
	local out = {}
	if store then
		for name in pairs(store) do out[#out + 1] = name end
	end
	table.sort(out)
	return out
end

local function ReapplyDungeon()
	if type(ns.DAApply) == 'function' then pcall(ns.DAApply) end
end

function ns.SwitchDungeonProfile(name)
	local db, store = _G.XerionUIChangesDB, DungeonStore()
	if not (db and store and name) then return end
	local cur = ns.GetDungeonProfile()
	if name == cur then return end
	SnapshotDungeon(cur)
	if not store[name] then SnapshotDungeon(name) end
	LoadDungeonIntoRoot(name)
	db.__dungeonProfile = name
	ReapplyDungeon()
end

function ns.NewDungeonProfile(name)
	local db, store = _G.XerionUIChangesDB, DungeonStore()
	if not (db and store) or not name or name == '' then return end
	SnapshotDungeon(ns.GetDungeonProfile())
	SnapshotDungeon(name)
	db.__dungeonProfile = name
end

function ns.DeleteDungeonProfile(name)
	local store = DungeonStore()
	if not store then return end
	if name == DUNGEON_PROFILE_DEFAULT or name == ns.GetDungeonProfile() then return end
	store[name] = nil
end

local EXPORT_PREFIX = '!XerionUI:1!'
local DUNGEON_EXPORT_PREFIX = '!XerionUIDR:1!'

local function GetSerializeLibs()
	local LS = _G.LibStub and _G.LibStub('LibSerialize', true)
	local LD = _G.LibStub and _G.LibStub('LibDeflate', true)
	return LS, LD
end

local function EncodeProfile(prefix, data)
	local LS, LD = GetSerializeLibs()
	if not (LS and LD) then return nil, 'needs LibSerialize + LibDeflate' end
	local ok, serialized = pcall(LS.Serialize, LS, data)
	if not ok or not serialized then return nil, 'serialize failed' end
	local compressed = LD:CompressDeflate(serialized, { level = 9 })
	if not compressed then return nil, 'compress failed' end
	return prefix .. LD:EncodeForPrint(compressed)
end

local function DecodeProfile(str, payloadPattern, describe)
	local LS, LD = GetSerializeLibs()
	if not (LS and LD) then return nil, 'needs LibSerialize + LibDeflate' end
	if type(str) ~= 'string' then return nil, 'no string' end
	str = str:gsub('%s', '')
	local payload = str:match(payloadPattern)
	if not payload then return nil, describe(str) end
	local decoded = LD:DecodeForPrint(payload)
	if not decoded then return nil, 'decode failed' end
	local decompressed = LD:DecompressDeflate(decoded)
	if not decompressed then return nil, 'decompress failed' end
	local ok, data = LS:Deserialize(decompressed)
	if not ok or type(data) ~= 'table' then return nil, 'deserialize failed' end
	return data
end

function ns.ExportCurrentProfile()
	local db = _G.XerionUIChangesDB
	if not db then return nil, 'no settings' end
	local data = {}
	for _, k in ipairs(FeatureKeys(db)) do data[k] = DeepCopy(db[k]) end
	return EncodeProfile(EXPORT_PREFIX, data)
end

local function DecodeProfileString(str)
	return DecodeProfile(str, '^!XerionUI:%d+!(.+)$',
		function() return 'not a XerionUI profile string' end)
end

function ns.ImportProfile(str, name)
	local data, err = DecodeProfileString(str)
	if not data then return false, err end
	if not name or name == '' then name = 'Imported' end
	local db = _G.XerionUIChangesDB
	if not db then return false, 'no settings' end
	db.kiraProfiles = db.kiraProfiles or {}
	SnapshotToProfile(ns.GetCurrentProfile())
	db.kiraProfiles[name] = DeepCopy(data)
	LoadProfileIntoRoot(name)
	db.__activeProfile = name
	ns.ApplyAllSettings()
	return true, name
end

function ns.ExportDungeonProfile()
	local db = _G.XerionUIChangesDB
	if not db then return nil, 'no settings' end
	return EncodeProfile(DUNGEON_EXPORT_PREFIX, DeepCopy(db.dungeonAlerts or {}))
end

local function DecodeDungeonString(str)
	return DecodeProfile(str, '^!XerionUIDR:%d+!(.+)$', function(s)
		if s:match('^!XerionUI:%d+!') then
			return 'that is a full addon profile string, not a Dungeon reminders one'
		end
		return 'not a Dungeon reminders string'
	end)
end

function ns.ImportDungeonProfile(str, name)
	local data, err = DecodeDungeonString(str)
	if not data then return false, err end
	if not name or name == '' then name = 'Imported' end
	local db, store = _G.XerionUIChangesDB, DungeonStore()
	if not (db and store) then return false, 'no settings' end
	SnapshotDungeon(ns.GetDungeonProfile())
	store[name] = DeepCopy(data)
	LoadDungeonIntoRoot(name)
	db.__dungeonProfile = name
	ReapplyDungeon()
	return true, name
end

_G.XerionUIPlugin = _G.XerionUIPlugin or {}
_G.XerionUIPlugin.OpenConfig = function(page) return ns.ShowConfig(page) end
_G.XerionUIPlugin.ImportProfile = function(str, name) return ns.ImportProfile(str, name) end
_G.XerionUIPlugin.ExportCurrentProfile = function() return ns.ExportCurrentProfile() end
_G.XerionUIPlugin.ImportDungeonProfile = function(str, name) return ns.ImportDungeonProfile(str, name) end
_G.XerionUIPlugin.ExportDungeonProfile = function() return ns.ExportDungeonProfile() end
_G.XerionUIPlugin.__ns = ns

local function Initialize()
	_G.XerionUIChangesDB = _G.XerionUIChangesDB or {}
	DeepMerge(_G.XerionUIChangesDB, defaults)
	-- Drop saved configuration for legacy features removed from this build.
	_G.XerionUIChangesDB.reset = nil
	_G.XerionUIChangesDB.cdPulse = nil
	_G.XerionUIChangesDB.history = nil
	_G.XerionUIChangesDB.breakTimer = nil
	for _, profile in pairs(_G.XerionUIChangesDB.kiraProfiles or {}) do
		if type(profile) == 'table' then
			profile.reset, profile.cdPulse, profile.history, profile.breakTimer = nil, nil, nil, nil
		end
	end

	_G.XerionUIChangesCharDB = _G.XerionUIChangesCharDB or {}
	charDB = _G.XerionUIChangesCharDB
	-- Old reset-button and break-timer character data is no longer used.
	charDB.pending, charDB.breaks, charDB.breakStart = nil, nil, nil

	do
		local db = _G.XerionUIChangesDB
		db.kiraProfiles = db.kiraProfiles or {}
		db.__activeProfile = db.__activeProfile or charDB.profile or PROFILE_DEFAULT
		charDB.profile = nil
		if not db.kiraProfiles[db.__activeProfile] then SnapshotToProfile(db.__activeProfile) end

		db.kiraDungeonProfiles = db.kiraDungeonProfiles or {}
		db.__dungeonProfile = db.__dungeonProfile or DUNGEON_PROFILE_DEFAULT
		if not db.kiraDungeonProfiles[db.__dungeonProfile] then
			SnapshotDungeon(db.__dungeonProfile)
		end

		if not db.__dungeonPresetRetired then
			db.__dungeonPresetRetired = true
			local function StripSeededPreset(alerts)
				local d = alerts and alerts.dungeons and alerts.dungeons['2521']
				if type(d) ~= 'table' then return end
				d.seeded = nil
				if type(d.spells) ~= 'table' then return end
				for i = #d.spells, 1, -1 do
					local e = d.spells[i]
					if type(e) == 'table' and e.kind == 'announce'
						and tonumber(e.id) == 381862 then
						table.remove(d.spells, i)
					end
				end
			end
			StripSeededPreset(db.kiraDungeonProfiles[DUNGEON_PROFILE_DEFAULT])
			if db.__dungeonProfile == DUNGEON_PROFILE_DEFAULT then
				StripSeededPreset(db.dungeonAlerts)
			end
		end

		-- Keys of retired features, cleared from the root and from every
		-- profile snapshot (a snapshot would put them back on the next
		-- switch), so one list serves both. ccTracker is the CC Tracker's icon
		-- row, removed; its bars (ccBars) stay.
		local RETIRED = { 'euiName', 'hideZeroText', 'reversedAbsorb', 'uufAbsorb', 'ccTracker' }
		for _, k in ipairs(RETIRED) do db[k] = nil end
		for _, prof in pairs(db.kiraProfiles) do
			if type(prof) == 'table' then
				prof.dungeonAlerts = nil
				for _, k in ipairs(RETIRED) do prof[k] = nil end
			end
		end
	end

	PARENT = (E and E.UIParent) or _G.UIParent

	ns.ApplyAllSettings()

	_G.SLASH_XERIONUIPLUGIN1 = '/xqol'
	_G.SLASH_XERIONUIPLUGIN2 = '/xerion'
	_G.SLASH_XERIONUIPLUGIN3 = '/kc'
	_G.SLASH_XERIONUIPLUGIN4 = '/xerionplugin'
	_G.SlashCmdList.XERIONUIPLUGIN = HandleSlash
	_G.SLASH_XERIONFEATURES1 = '/xui'
	_G.SlashCmdList.XERIONFEATURES = function(input)
		local arg = input and input:lower():match('^%s*(%S*)') or ''
		local featureAddon = _G.XerionUIFeatures
		if featureAddon and featureAddon.MySlashProcessorFunc and
			(arg == '' or arg == 'config' or arg == 'c' or arg == 'elvui' or arg == 'eui' or arg == 'standalone' or arg == 'ace' or arg == 'test' or arg == 't' or arg == 'help') then
			featureAddon:MySlashProcessorFunc(input)
		else
			HandleSlash(input)
		end
	end
end

local loader = CreateFrame('Frame')
loader:RegisterEvent('PLAYER_LOGIN')
loader:SetScript('OnEvent', function(self)
	self:UnregisterEvent('PLAYER_LOGIN')
	Initialize()
end)
