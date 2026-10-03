local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('EUIMeterIlvl', hooksecurefunc, C_Timer)
local _G = _G

local CreateFrame = CreateFrame
local GameTooltip = GameTooltip
local C_Timer = C_Timer
local GetTime = GetTime
local UnitGUID, UnitName = UnitGUID, UnitName
local UnitIsVisible, CanInspect, NotifyInspect = UnitIsVisible, CanInspect, NotifyInspect
local InCombatLockdown, IsInRaid = InCombatLockdown, IsInRaid
local GetAverageItemLevel = GetAverageItemLevel
local Ambiguate = Ambiguate
local hooksecurefunc = hooksecurefunc
local ipairs, pairs, type, pcall, tostring = ipairs, pairs, type, pcall, tostring
local setmetatable, wipe = setmetatable, wipe
local format, floor = string.format, math.floor

local secret = ns.IsSecret
local Ask = ns.Ask
local Msg = ns.Msg

-- WHY THIS FILE EXISTS
-- The EllesmereUI damage meter shows who did what, but not what they are
-- wearing, and "is the low bar under-geared or playing badly" is the question
-- that follows every pull. Item level is one hover away on a unit frame, never
-- on a meter row. This module puts it there: rest the pointer on the spec icon
-- at the start of a meter row and a small tooltip names the player and their
-- current equipped item level.
--
-- WHY THE ICON AND NOT THE ROW
-- Hovering the rest of the row already opens EllesmereUI's own breakdown, and
-- that stays exactly as it is. The icon is a texture, not a frame, so it gets
-- no mouse events of its own; the row's OnEnter/OnLeave are post-hooked and,
-- only while a row is under the pointer, a small ticker asks the icon texture
-- IsMouseOver(). Nothing runs while no row is hovered. The tooltip sits to the
-- left of the icon, outside the window, so it never covers the breakdown, which
-- EllesmereUI anchors above the row (or beside the window - with the breakdown
-- on the LEFT, or no room left of the window, ours goes under the icon instead).
--
-- WHERE THE NUMBER COMES FROM
-- Your own row reads GetAverageItemLevel() (equipped), live. Anyone else needs
-- an inspect: NotifyInspect(unit), then INSPECT_READY(guid) and
-- C_PaperDollInfo.GetInspectItemLevel(unit), read at that moment because the
-- client holds one inspected player at a time. Answers are cached by GUID, and
-- the cache also takes in every INSPECT_READY for a group member that other
-- addons caused, plus EllesmereUI's own tooltip cache (EllesmereUI._inspectCache,
-- read only, never written) - whichever is newer wins. A cached value younger
-- than FRESH seconds is shown without asking again; an older one is shown while
-- a fresh inspect is on its way. Inspects are sent only on hover, out of combat,
-- one at a time, never while the Blizzard inspect window is open or right after
-- the player opened it, and at most MAX_TRIES per player per hover.
--
-- The number is shown to one decimal, cut rather than rounded, so the whole
-- part always matches the character sheet (which floors it): 684.94 reads
-- 684.9, never 685.0. EllesmereUI stores its answers already floored, so its
-- cache only wins when its whole number differs from ours (the gear changed);
-- such a value is shown without a decimal and still triggers a fresh inspect,
-- which brings the decimal back.
--
-- WHO THE ROW IS
-- Out of combat the row's sourceGUID is plain and is matched against the group
-- tokens. In combat it is SECRET. The own row is still known (isLocalPlayer is
-- NeverSecret), and for group rows EllesmereUI keeps a class+spec -> GUID bridge
-- built out of combat (_ResolveGroupGUID on its module namespace; dungeons only,
-- ambiguous when two players share class and spec). A row that cannot be named
-- says so instead of guessing. No inspect is ever sent in combat: gear does not
-- change mid-pull, so the value from before the pull is the current one.

local DM_ADDON = 'EllesmereUIDamageMeters'
local TICK = 0.05
local FRESH = 120
local ANSWER_WAIT = 3
local ASK_GAP = 1.5
local MAX_TRIES = 3
local EDGE_GAP = 8

local LABEL = _G.STAT_AVERAGE_ITEM_LEVEL or 'Item Level'

local STATE_TEXT = {
	pending  = 'inspecting...',
	wait     = 'inspecting...',
	noanswer = 'no answer',
	combat   = 'after combat',
	range    = 'out of range',
	group    = 'not in your group',
	secret   = 'unknown in combat',
}

local DEFAULTS = {
	enable = true,
}

local function GetCfg() return ns.ModuleCfg('euiMeterIlvl', DEFAULTS) end
ns.EMIGetCfg = GetCfg

local function DM()
	local eui = _G.EllesmereUI
	local reg = eui and eui._ModuleNS
	local dm = reg and reg[DM_ADDON]
	return type(dm) == 'table' and dm or nil
end

local function MeterDB()
	local dm = DM()
	local edm = dm and dm.EDM
	if not (edm and type(edm.DB) == 'function') then return nil end
	local ok, db = pcall(edm.DB)
	return (ok and type(db) == 'table') and db or nil
end

-- Damage Meters is in the TOC's OptionalDeps and registers its namespace as
-- its first file loads, so this answer is final (same as Meter Stretch).
ns.hasEUIMeterIlvl = DM() ~= nil

local function Plain(v)
	if v == nil or secret(v) then return nil end
	return v
end

local function Num(v)
	return v ~= nil and not secret(v) and type(v) == 'number'
end

local function Grey(s) return '|cff808080' .. s .. '|r' end

-- Averages over 16 slots are multiples of 1/16, exact in a double, so the
-- x10 floor never lands a hair under the true tenth.
local function IlvlText(v, whole)
	if whole then return format('%d', v) end
	return format('%.1f', floor(v * 10) / 10)
end

-- ---------------------------------------------------------------------------
-- WHO AND WHAT

local cache = {}
local asked = {}
local pendingGUID, pendingAt = nil, 0
local lastAsk = 0
local userInspectUntil = 0

local function PlayerGUID() return Plain(UnitGUID('player')) end

local function RowGUID(src)
	if type(src) ~= 'table' then return nil end
	local g = src.sourceGUID
	if not secret(g) then
		return (type(g) == 'string' and g:find('^Player%-')) and g or nil
	end
	local own = src.isLocalPlayer
	if not secret(own) and own == true then return PlayerGUID() end
	local dm = DM()
	local resolve = dm and dm._ResolveGroupGUID
	if type(resolve) ~= 'function' then return nil end
	local ok, rg = pcall(resolve, src)
	if ok and not secret(rg) and type(rg) == 'string' then return rg end
	return nil
end

local function UnitForGUID(guid)
	if guid == PlayerGUID() then return 'player' end
	local prefix, n = 'party', 4
	if IsInRaid() then prefix, n = 'raid', 40 end
	for i = 1, n do
		local u = prefix .. i
		local g = UnitGUID(u)
		if g and not secret(g) and g == guid then return u end
	end
	return nil
end

local function OwnIlvl()
	local ok, _, equipped = pcall(GetAverageItemLevel)
	if ok and Num(equipped) and equipped > 0 then return equipped end
	return nil
end

local function ReadInspect(unit)
	local get = _G.C_PaperDollInfo and _G.C_PaperDollInfo.GetInspectItemLevel
	if not get then return nil end
	local ok, v = pcall(get, unit)
	if ok and Num(v) and v > 0 then return v end
	return nil
end

-- ilvl, when it was read, and true when it is a floored EllesmereUI value.
local function Known(guid)
	local mine = cache[guid]
	local eui = _G.EllesmereUI
	local shared = eui and type(eui._inspectCache) == 'table' and eui._inspectCache[guid]
	if type(shared) == 'table' and Num(shared.ilvl) and Num(shared.time)
		and (not mine or (shared.time > mine.at and floor(mine.ilvl) ~= shared.ilvl)) then
		return shared.ilvl, shared.time, true
	end
	if mine then return mine.ilvl, mine.at, false end
	return nil
end

local function InspectBusy(now)
	local f = _G.InspectFrame
	return (f and f:IsShown()) or now < userInspectUntil
end

-- Sends at most one inspect and says where that player stands. Called every
-- tick while the icon is hovered, so every gate is cheap and a 'wait' simply
-- goes out on a later tick.
local function Request(guid, unit)
	local now = GetTime()
	if pendingGUID and now - pendingAt >= ANSWER_WAIT then pendingGUID = nil end
	if pendingGUID == guid then return 'pending' end
	if (asked[guid] or 0) >= MAX_TRIES then return 'noanswer' end
	if InCombatLockdown() then return 'combat' end
	if pendingGUID or InspectBusy(now) or now - lastAsk < ASK_GAP then return 'wait' end
	if Ask(UnitIsVisible, unit) == false or Ask(CanInspect, unit) == false then return 'range' end
	if not (NotifyInspect and pcall(NotifyInspect, unit)) then return 'range' end
	asked[guid] = (asked[guid] or 0) + 1
	lastAsk, pendingGUID, pendingAt = now, guid, now
	return 'pending'
end

-- guid, name, class token, value text for one meter row.
local function Describe(bar)
	local src = bar._src
	local cls = type(src) == 'table' and Plain(src.classFilename) or nil
	if type(cls) ~= 'string' then cls = nil end
	local guid = RowGUID(src)
	if not guid then
		local g = type(src) == 'table' and src.sourceGUID
		return nil, nil, cls, Grey(STATE_TEXT[secret(g) and 'secret' or 'group'])
	end
	local unit = UnitForGUID(guid)
	local name = Plain(src.name)
	if type(name) == 'string' and name ~= '' then
		name = Ambiguate(name, 'short')
	elseif unit then
		local ok, n = pcall(UnitName, unit)
		name = ok and Plain(n) or nil
	else
		name = nil
	end
	if unit == 'player' then
		local own = OwnIlvl()
		return guid, name, cls, own and IlvlText(own) or Grey('?')
	end
	local ilvl, at, whole = Known(guid)
	local state = 'group'
	if unit and (not ilvl or whole or GetTime() - at >= FRESH) then state = Request(guid, unit) end
	if ilvl then return guid, name, cls, IlvlText(ilvl, whole) end
	return guid, name, cls, Grey(STATE_TEXT[state] or '?')
end

-- ---------------------------------------------------------------------------
-- TOOLTIP

local tipOwner, tipKey

local function HideTip()
	if tipOwner and GameTooltip:IsOwned(tipOwner) then GameTooltip:Hide() end
	tipOwner, tipKey = nil, nil
end

local function Place(bar)
	local icon = bar.classIcon
	local db = MeterDB()
	local below = db and db.breakdownAnchorPoint == 'left'
	if not below then
		local left, es = icon:GetLeft(), icon:GetEffectiveScale()
		local w, ts = GameTooltip:GetWidth(), GameTooltip:GetEffectiveScale()
		if Num(left) and Num(es) and Num(w) and Num(ts) then
			below = left * es < (w + EDGE_GAP) * ts
		end
	end
	GameTooltip:ClearAllPoints()
	if below then
		GameTooltip:SetPoint('TOPLEFT', icon, 'BOTTOMLEFT', 0, -2)
	else
		GameTooltip:SetPoint('TOPRIGHT', icon, 'TOPLEFT', -EDGE_GAP, 0)
	end
end

local function Render(bar)
	local guid, name, cls, text = Describe(bar)
	local key = tostring(guid) .. '|' .. tostring(name) .. '|' .. text
	local row = bar.row
	if tipOwner == row and tipKey == key and GameTooltip:IsOwned(row) and GameTooltip:IsShown() then return end
	GameTooltip:SetOwner(row, 'ANCHOR_NONE')
	if name then
		local c = cls and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[cls]
		GameTooltip:AddLine(name, c and c.r or 1, c and c.g or 1, c and c.b or 1)
	end
	GameTooltip:AddDoubleLine(LABEL, text, 1, 0.82, 0, 1, 1, 1)
	GameTooltip:Show()
	Place(bar)
	tipOwner, tipKey = row, key
end

-- ---------------------------------------------------------------------------
-- HOVER

local hovered
local since = 0
local watch = CreateFrame('Frame')
watch:Hide()

local function OverIcon(bar)
	local icon = bar.classIcon
	if not (icon and bar.row:IsVisible() and icon:IsVisible()) then return false end
	local ok, over = pcall(icon.IsMouseOver, icon)
	return ok and not secret(over) and over == true
end

local function Check()
	local bar = hovered
	if not (bar and GetCfg().enable) then
		hovered = nil
		HideTip()
		watch:Hide()
		return
	end
	if OverIcon(bar) then
		Render(bar)
	elseif tipOwner then
		HideTip()
	end
end

watch:SetScript('OnUpdate', function(_, elapsed)
	since = since + elapsed
	if since < TICK then return end
	since = 0
	Check()
end)

local rowBar = setmetatable({}, { __mode = 'k' })

local function OnRowEnter(row)
	local bar = rowBar[row]
	if not (bar and GetCfg().enable) then return end
	hovered = bar
	wipe(asked)
	since = TICK
	watch:Show()
end

local function OnRowLeave(row)
	if hovered and hovered.row ~= row then return end
	hovered = nil
	HideTip()
	watch:Hide()
end

local function HookBar(bar)
	local row = type(bar) == 'table' and bar.row
	if type(row) ~= 'table' or not row.HookScript or rowBar[row] then return end
	rowBar[row] = bar
	row:HookScript('OnEnter', OnRowEnter)
	row:HookScript('OnLeave', OnRowLeave)
end

-- Every window keeps its 40 rows (W.rowPool) and its pinned own row
-- (W.stickyPlayer) for its whole life; a profile swap builds new windows, and
-- every build path ends in RegisterDMUnlock, which is the re-read signal.
local function Sync()
	local dm = DM()
	local list = dm and dm._windows
	if type(list) ~= 'table' or not GetCfg().enable then return end
	for _, W in ipairs(list) do
		if type(W) == 'table' then
			if type(W.rowPool) == 'table' then
				for _, bar in ipairs(W.rowPool) do HookBar(bar) end
			end
			HookBar(W.stickyPlayer)
		end
	end
end

local dmHooked = false
local function HookDM()
	if dmHooked then return end
	local dm = DM()
	if not (dm and type(dm.RegisterDMUnlock) == 'function') then return end
	dmHooked = true
	hooksecurefunc(dm, 'RegisterDMUnlock', function() C_Timer.After(0, Sync) end)
end

local function OnInspectReady(guid)
	if guid == nil or secret(guid) then return end
	if guid == pendingGUID then pendingGUID = nil end
	local unit = UnitForGUID(guid)
	if not unit or unit == 'player' then return end
	local v = ReadInspect(unit)
	if v then
		local e = cache[guid] or {}
		e.ilvl, e.at = v, GetTime()
		cache[guid] = e
	end
	if tipOwner then Check() end
end

local evt = CreateFrame('Frame')
evt:SetScript('OnEvent', function(_, _, guid) OnInspectReady(guid) end)

if _G.InspectUnit then
	hooksecurefunc('InspectUnit', function() userInspectUntil = GetTime() + 2 end)
end

-- Off: no inspects, no INSPECT_READY, the tooltip goes. Row hooks cannot be
-- removed; they return at once while the switch is off.
local function Apply()
	if not ns.hasEUIMeterIlvl then return end
	if not GetCfg().enable then
		evt:UnregisterEvent('INSPECT_READY')
		hovered = nil
		HideTip()
		watch:Hide()
		return
	end
	evt:RegisterEvent('INSPECT_READY')
	HookDM()
	Sync()
end
ns.EMIApply = Apply

-- ---------------------------------------------------------------------------
-- /xerionilvl

local function YN(v) return v and '|cff55ff55yes|r' or '|cffff5555no|r' end

local function Dump()
	local n = 0
	for _ in pairs(rowBar) do n = n + 1 end
	local dm = DM()
	local wins = dm and type(dm._windows) == 'table' and #dm._windows or 0
	Msg('|cffff7d0a--- Meter Item Level ---|r')
	Msg(format('Damage Meters loaded %s   enabled %s   windows %d   rows hooked %d   window hook %s   in combat %s',
		YN(ns.hasEUIMeterIlvl), YN(GetCfg().enable), wins, n, YN(dmHooked), YN(InCombatLockdown())))
	local now = GetTime()
	Msg(format('Inspect pending %s   last sent %s   inspect window busy %s',
		pendingGUID and format('%s (%.1f s)', pendingGUID, now - pendingAt) or 'none',
		lastAsk > 0 and format('%.1f s ago', now - lastAsk) or 'never', YN(InspectBusy(now))))
	local own = OwnIlvl()
	Msg('You: ' .. (own and IlvlText(own) or 'not known'))
	local prefix, count = 'party', 4
	if IsInRaid() then prefix, count = 'raid', 40 end
	for i = 1, count do
		local u = prefix .. i
		local g = Plain(UnitGUID(u))
		if g then
			local ok, name = pcall(UnitName, u)
			local ilvl, at, whole = Known(g)
			Msg(format(' %s %s: %s', u, tostring(ok and Plain(name) or '?'),
				ilvl and format('%s (%d s old)', IlvlText(ilvl, whole), floor(now - at)) or 'not known'))
		end
	end
end

_G.SLASH_XERIONILVL1 = '/xerionilvl'
_G.SlashCmdList.XERIONILVL = function(msg)
	msg = ns.Trim(msg):lower()
	if msg == 'sync' then
		Apply()
		Msg('Meter Item Level: rows re-read.')
		return
	end
	Dump()
end
