local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('EUIMythicCast', hooksecurefunc, C_Timer)
local _G = _G

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local ipairs, pairs, type = ipairs, pairs, type
local format, tostring = string.format, tostring
local pcall = pcall
local hooksecurefunc = hooksecurefunc
local GetTime = GetTime
local UnitExists = UnitExists
local UnitName = UnitName
local UnitClassification = UnitClassification
local UnitEffectiveLevel = UnitEffectiveLevel

local TSB_ADDON = 'EllesmereUIMythicTimer'

local DEFAULTS = {
	hideBossCasts = false,
	spark         = false,
	sparkWidth    = 2,
	sparkColor    = { 1, 1, 1, 1 },
	sparkAlpha    = 1,
	markerPos     = 'INSIDE',
	markerX       = 0,
	markerY       = 0,
}

local function Migrate(cfg)
	cfg.scope = nil
	cfg.mplusOnly = nil
end

local function GetCfg() return ns.ModuleCfg('euiMythicCast', DEFAULTS, Migrate) end
ns.EMCGetCfg = GetCfg

ns.hasEUIMythicCast = false

local function TSBCfg()
	local db = _G._EMT_AceDB
	local prof = db and db.profile
	local tsb = prof and prof.tsb
	return type(tsb) == 'table' and tsb or nil
end

local function TSBEnabled()
	local tsb = TSBCfg()
	return (tsb and tsb.enabled == true) or false
end

local BOSS_CLASSES = { elite = true, rareelite = true, worldboss = true }

local Secret = ns.IsSecret

local function EffLevel(unit)
	local ok, lvl = pcall(UnitEffectiveLevel, unit)
	if not ok or type(lvl) ~= 'number' or Secret(lvl) then return nil end
	return lvl
end

local function IsLieutenant(unit)
	local fn = _G.UnitIsLieutenant
	if not fn then return false end
	local ok, lt = pcall(fn, unit)
	if not ok or Secret(lt) then return false end
	return lt and true or false
end

local function IsBossUnit(unit)
	if not unit then return false end
	local ok, class = pcall(UnitClassification, unit)
	if not ok or Secret(class) or not BOSS_CLASSES[class] then return false end

	local lvl = EffLevel(unit)
	if lvl == -1 then return true end
	if IsLieutenant(unit) then return false end
	if class == 'worldboss' then return true end
	if not lvl then return false end
	local plvl = EffLevel('player')
	return plvl ~= nil and lvl >= plvl + 2
end

local function FilterActive()
	return GetCfg().hideBossCasts == true
end

local MUST_HAVE = {
	'NAME_PLATE_UNIT_ADDED', 'NAME_PLATE_UNIT_REMOVED',
	'UNIT_SPELLCAST_START', 'UNIT_SPELLCAST_CHANNEL_START',
	'UNIT_SPELLCAST_STOP', 'UNIT_SPELLCAST_INTERRUPTED',
	'UNIT_SPELLCAST_CHANNEL_STOP',
}
local MUST_NOT = {
	'PLAYER_ENTERING_WORLD', 'PLAYER_TARGET_CHANGED', 'PLAYER_FOCUS_CHANGED',
	'PLAYER_LOGIN', 'ADDON_LOADED', 'PLAYER_REGEN_ENABLED', 'PLAYER_REGEN_DISABLED',
	'UNIT_HEALTH', 'UNIT_AURA', 'UNIT_SPELLCAST_SUCCEEDED', 'SPELL_UPDATE_COOLDOWN',
	'CHALLENGE_MODE_START', 'GROUP_ROSTER_UPDATE', 'NAME_PLATE_CREATED',
	'COMBAT_LOG_EVENT_UNFILTERED', 'ZONE_CHANGED_NEW_AREA',
}

local GATE_EVENT = 'UNIT_SPELLCAST_EMPOWER_STOP'

local function WhyNotTSBFrame(f)
	if f.IsForbidden and f:IsForbidden() then return 'forbidden' end
	if f:GetObjectType() ~= 'Frame' then return 'not a plain Frame' end
	if f:GetName() ~= nil then return 'named' end
	if f:GetParent() ~= nil then return 'has a parent' end
	if f:GetNumChildren() ~= 0 then return 'has children' end
	if f:GetNumRegions() ~= 0 then return 'has regions' end
	if type(f:GetScript('OnEvent')) ~= 'function' then return 'no OnEvent script' end
	for _, e in ipairs(MUST_HAVE) do
		if f:IsEventRegistered(e) ~= true then return 'missing ' .. e end
	end
	for _, e in ipairs(MUST_NOT) do
		if f:IsEventRegistered(e) == true then return 'registers ' .. e end
	end
	return nil
end

local function Candidates()
	local fn = _G.GetFramesRegisteredForEvent
	if type(fn) ~= 'function' then return nil end
	local ok, list = pcall(function() return { fn(GATE_EVENT) } end)
	if not ok or type(list) ~= 'table' then return nil end
	return list
end

local function FindTSBFrame()
	local list = Candidates()
	if not list then return nil end
	for i = 1, #list do
		local f = list[i]
		local ok, why = pcall(WhyNotTSBFrame, f)
		if ok and why == nil then return f end
	end
	return nil
end

local DROP_EVENTS = {
	NAME_PLATE_UNIT_ADDED        = true,
	UNIT_SPELLCAST_START         = true,
	UNIT_SPELLCAST_CHANNEL_START = true,
	UNIT_SPELLCAST_EMPOWER_START = true,
}

local function IsPlateToken(unit)
	return type(unit) == 'string' and unit:sub(1, 9) == 'nameplate'
end

local evtFrame, origOnEvent
local ourHandler
local debugOn = false
local lastScan = 0
local SCAN_THROTTLE = 5

local function Hooked() return (evtFrame ~= nil) and (origOnEvent ~= nil) end

local function Install(force)
	if Hooked() then return true end
	if not ns.hasEUIMythicCast then return false end
	local now = GetTime and GetTime() or 0
	if not force and lastScan > 0 and (now - lastScan) < SCAN_THROTTLE then return false end
	lastScan = now

	local f = FindTSBFrame()
	if not f then return false end

	local orig = f:GetScript('OnEvent')
	if type(orig) ~= 'function' then return false end

	evtFrame, origOnEvent = f, orig
	ourHandler = function(self, event, unit, ...)
		local drop = unit and DROP_EVENTS[event] and IsPlateToken(unit)
		if drop and debugOn then
			local active, boss = FilterActive(), IsBossUnit(unit)
			ns.Msg(format('|cff888888%s|r %s  filterActive=%s boss=%s -> %s',
				event, tostring(unit), tostring(active), tostring(boss),
				(active and boss) and '|cff55ff55DROPPED|r' or 'passed'))
		end
		if drop and FilterActive() and IsBossUnit(unit) then
			return origOnEvent(self, 'NAME_PLATE_UNIT_REMOVED', unit)
		end
		return origOnEvent(self, event, unit, ...)
	end
	f:SetScript('OnEvent', ourHandler)
	return true
end

ns.EMCRedetect = function()
	local ok = Install(true)
	if ns.Msg then
		if ok then
			ns.Msg('Boss cast filter: attached to Targeted Spell Bars.')
		elseif not TSBEnabled() then
			ns.Msg('Boss cast filter: Targeted Spell Bars is switched off in EllesmereUI - turn it on first.')
		else
			ns.Msg('Boss cast filter: could not find the Targeted Spell Bars handler. It only exists while the bars can show here (EllesmereUI\'s Where to Show); try again where they show, then /xerionmc scan.')
		end
	end
	return ok
end

local function LivePlateUnits(out)
	local np = _G.C_NamePlate
	if not (np and np.GetNamePlates) then return out end
	local ok, plates = pcall(np.GetNamePlates)
	if not ok or type(plates) ~= 'table' then return out end
	for i = 1, #plates do
		local unit = plates[i] and plates[i].namePlateUnitToken
		if unit then out[#out + 1] = unit end
	end
	return out
end

local unitScratch = {}
local function Resync()
	if not Hooked() then return end
	for i = #unitScratch, 1, -1 do unitScratch[i] = nil end
	LivePlateUnits(unitScratch)
	if #unitScratch == 0 then return end
	local filtering = FilterActive()
	for _, unit in ipairs(unitScratch) do
		if filtering and IsBossUnit(unit) then
			pcall(origOnEvent, evtFrame, 'NAME_PLATE_UNIT_REMOVED', unit)
		else
			pcall(origOnEvent, evtFrame, 'NAME_PLATE_UNIT_ADDED', unit)
		end
	end
end

-- WHY THE BARS ARE REACHED THIS WAY
--
-- Targeted Spell Bars keeps its frames in file locals like everything else in
-- that file, but two doors are open. The module publishes its namespace in
-- EllesmereUI._ModuleNS (that is how EllesmereUI's own LoadOnDemand options reach
-- TSB_Refresh and TSB_SetPreview), and unlock mode holds the group's element,
-- whose getFrame() hands back the container every bar is parented to. A bar
-- carries its parts as plain fields (sb, marker, name), so once it is found it
-- can be dressed without touching a line of EllesmereUI.
--
-- WHAT IS DONE TO A BAR
--
-- Spark: a texture pinned to the right edge of the fill texture, the anchor
-- EllesmereUI's nameplate cast spark uses. The fill runs on SetTimerDuration, so
-- the engine moves the spark with it: no OnUpdate, and no cast time is ever read
-- (they are secret in keys). SetStatusBarTexture mints a new fill texture on
-- every restyle, hence the hook that pins the spark again.
--
-- Marker: EllesmereUI anchors the marker on every restyle and the spell name on
-- every cast, so a one-off SetPoint would not survive the next pull. Post-hooks
-- on those two regions put our anchor back each time, and hand the name the room
-- EllesmereUI reserved for a marker that is no longer inside the bar. The hooks
-- work on the numbers EllesmereUI just passed, never on the current anchor, so
-- nothing can be applied twice. Whenever the layout has to be redone (a setting
-- changed, a bar was found late) TSB_Refresh is asked for a restyle and the hooks
-- ride it; that keeps EllesmereUI's name layout the only copy of that logic.
--
-- Bars are pooled and built lazily, the first time a slot is needed, and nothing
-- fires when one is created. So cast starts are watched until the pool holds
-- Max Bars frames, the container is looked at one frame later, and after the
-- first few pulls the watcher unregisters itself and costs nothing.
local TSB_UNLOCK_KEY = 'EMT_TargetedSpellBars'
local WHITE = 'Interface\\Buttons\\WHITE8x8'
local MARKER_GAP = 2

local decorated = {}
local barCount = 0
local knownChildren = 0
local reanchoring = false
local restyling = false
local emtHooked = false
local scanPending = false
local watcher = CreateFrame('Frame')
local watching = false

local function EMT()
	local eui = _G.EllesmereUI
	local reg = eui and eui._ModuleNS
	local emt = reg and reg[TSB_ADDON]
	return type(emt) == 'table' and emt or nil
end

local function Container()
	local eui = _G.EllesmereUI
	local reg = eui and eui._unlockRegisteredElements
	local elem = reg and reg[TSB_UNLOCK_KEY]
	if not (elem and type(elem.getFrame) == 'function') then return nil end
	local ok, f = pcall(elem.getFrame)
	if ok and type(f) == 'table' and f.GetChildren then return f end
	return nil
end

local function MarkerOutside()
	local pos = GetCfg().markerPos
	return pos == 'LEFT' or pos == 'RIGHT'
end

local function MarkerMoved()
	local cfg = GetCfg()
	return MarkerOutside() or (cfg.markerX or 0) ~= 0 or (cfg.markerY or 0) ~= 0
end

local function BarsWanted()
	return GetCfg().spark == true or MarkerMoved()
end

local function MarkerReserve()
	local tsb = TSBCfg()
	local size = tsb and tsb.raidMarkerSize
	return (type(size) == 'number' and size or 14) + 2
end

local function MaxBars()
	local tsb = TSBCfg()
	local n = tsb and tsb.maxBars
	return type(n) == 'number' and n or 5
end

local function StyleSpark(holder)
	local spark = decorated[holder]
	if not spark then return end
	local cfg = GetCfg()
	local fill = cfg.spark and holder.sb:GetStatusBarTexture()
	if not fill then
		spark:Hide()
		return
	end
	local c = cfg.sparkColor or DEFAULTS.sparkColor
	spark:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, cfg.sparkAlpha or 1)
	spark:SetWidth(cfg.sparkWidth or 2)
	spark:ClearAllPoints()
	spark:SetPoint('TOPRIGHT', fill, 'TOPRIGHT', 0, 0)
	spark:SetPoint('BOTTOMRIGHT', fill, 'BOTTOMRIGHT', 0, 0)
	spark:Show()
end

local function AnchorMarker(holder)
	if not MarkerMoved() then return end
	local cfg = GetCfg()
	local pos, x, y = cfg.markerPos, cfg.markerX or 0, cfg.markerY or 0
	reanchoring = true
	holder.marker:ClearAllPoints()
	if pos == 'LEFT' then
		holder.marker:SetPoint('RIGHT', holder, 'LEFT', -MARKER_GAP + x, y)
	elseif pos == 'RIGHT' then
		holder.marker:SetPoint('LEFT', holder, 'RIGHT', MARKER_GAP + x, y)
	else
		holder.marker:SetPoint('LEFT', holder.sb, 'LEFT', 3 + x, y)
	end
	reanchoring = false
end

local function NameNeedsRoom(holder)
	return not reanchoring and MarkerOutside() and holder.marker:IsShown()
end

local function Decorate(holder)
	local spark = holder.sb:CreateTexture(nil, 'OVERLAY', nil, 7)
	spark:SetTexture(WHITE)
	if spark.SetSnapToPixelGrid then
		spark:SetSnapToPixelGrid(false)
		spark:SetTexelSnappingBias(0)
	end
	spark:Hide()
	decorated[holder] = spark
	barCount = barCount + 1

	hooksecurefunc(holder.sb, 'SetStatusBarTexture', function() StyleSpark(holder) end)
	hooksecurefunc(holder.marker, 'SetPoint', function()
		if not reanchoring then AnchorMarker(holder) end
	end)
	hooksecurefunc(holder.name, 'SetPoint', function(name, point, rel, relPoint, x, y)
		if type(x) ~= 'number' or not NameNeedsRoom(holder) then return end
		reanchoring = true
		name:SetPoint(point, rel, relPoint, x - MarkerReserve(), y)
		reanchoring = false
	end)
	hooksecurefunc(holder.name, 'SetWidth', function(name, w)
		if type(w) ~= 'number' or not NameNeedsRoom(holder) then return end
		reanchoring = true
		name:SetWidth(w + MarkerReserve())
		reanchoring = false
	end)

	StyleSpark(holder)
end

local function IsBar(f)
	return type(f) == 'table' and not decorated[f]
		and type(f.sb) == 'table' and f.sb.GetStatusBarTexture
		and type(f.marker) == 'table' and f.marker.SetPoint
		and type(f.name) == 'table' and f.name.SetWidth
end

local function BarsActive()
	return ns.hasEUIMythicCast and BarsWanted() and TSBEnabled()
end

local function Scan()
	if not BarsActive() then return false end
	local c = Container()
	if not c then return false end
	local n = c:GetNumChildren()
	if n == knownChildren then return false end
	knownChildren = n
	local found = false
	local kids = { c:GetChildren() }
	for i = 1, #kids do
		if IsBar(kids[i]) then
			Decorate(kids[i])
			found = true
		end
	end
	return found
end

local function Restyle()
	if restyling then return end
	local emt = EMT()
	if not (emt and type(emt.TSB_Refresh) == 'function') then return end
	restyling = true
	pcall(emt.TSB_Refresh)
	restyling = false
end

local WATCH_EVENTS = {
	'NAME_PLATE_UNIT_ADDED', 'UNIT_SPELLCAST_START',
	'UNIT_SPELLCAST_CHANNEL_START', 'UNIT_SPELLCAST_EMPOWER_START',
}

local function SyncWatcher()
	local want = BarsActive() and barCount < MaxBars()
	want = want and true or false
	if want == watching then return end
	watching = want
	if want then
		for _, e in ipairs(WATCH_EVENTS) do watcher:RegisterEvent(e) end
	else
		watcher:UnregisterAllEvents()
	end
end

local function AfterEMT()
	if Scan() and MarkerMoved() then Restyle() end
	SyncWatcher()
end

local function ScanLive()
	scanPending = false
	AfterEMT()
end

local function QueueScan()
	if scanPending or not BarsWanted() then return end
	scanPending = true
	C_Timer.After(0, ScanLive)
end

watcher:SetScript('OnEvent', function(_, _, unit)
	if IsPlateToken(unit) then QueueScan() end
end)

local function HookEMT()
	if emtHooked then return end
	local emt = EMT()
	if not (emt and type(emt.TSB_Refresh) == 'function' and type(emt.TSB_SetPreview) == 'function') then return end
	emtHooked = true
	hooksecurefunc(emt, 'TSB_Refresh', AfterEMT)
	hooksecurefunc(emt, 'TSB_SetPreview', AfterEMT)
end

local function BarsApply()
	if not ns.hasEUIMythicCast then return end
	HookEMT()
	Scan()
	for holder in pairs(decorated) do StyleSpark(holder) end
	if barCount > 0 then Restyle() end
	SyncWatcher()
end
ns.EMCApplyBars = BarsApply

ns.EMCTSBCfg = TSBCfg

ns.EMCRefreshTSB = function()
	HookEMT()
	Restyle()
end

ns.EMCIsPreview = function()
	local emt = EMT()
	if not (emt and type(emt.TSB_IsPreview) == 'function') then return false end
	local ok, on = pcall(emt.TSB_IsPreview)
	return (ok and on) and true or false
end

ns.EMCSetPreview = function(on)
	local emt = EMT()
	if not (emt and type(emt.TSB_SetPreview) == 'function') then return end
	if on and not TSBEnabled() then
		ns.Msg('Targeted Spell Bars is switched off in EllesmereUI - turn it on there first.')
		return
	end
	HookEMT()
	pcall(emt.TSB_SetPreview, on and true or false)
end

ns.EMCApply = function()
	if GetCfg().hideBossCasts then Install(true) end
	Resync()
	BarsApply()
end

local function YN(v) return v and '|cff55ff55yes|r' or '|cffff5555no|r' end

local function Show(v)
	if v == nil then return 'nil' end
	if Secret(v) then return '|cffffd100<secret>|r' end
	local ok, str = pcall(tostring, v)
	return ok and str or '<unreadable>'
end

local function DescribeUnit(unit, label)
	local okName, name = pcall(UnitName, unit)
	local okClass, class = pcall(UnitClassification, unit)
	ns.Msg(format('  %s (%s) class=%s lvl=%s player=%s lieutenant=%s |cffffd100BOSS=%s|r',
		label or unit,
		okName and Show(name) or '?',
		okClass and Show(class) or '?',
		Show(EffLevel(unit)), Show(EffLevel('player')),
		YN(IsLieutenant(unit)), YN(IsBossUnit(unit))))
end

local function Dump()
	local cfg = GetCfg()
	ns.Msg('|cffff7d0a--- Targeted Spell Bars ---|r')
	ns.Msg('Mythic+ Tools addon loaded: ' .. YN(ns.hasEUIMythicCast))
	ns.Msg('Targeted Spell Bars enabled: ' .. YN(TSBEnabled())
		.. '   (_EMT_AceDB ' .. (_G._EMT_AceDB and 'found' or '|cffff5555MISSING|r') .. ')')

	if Hooked() then
		local live = (evtFrame:GetScript('OnEvent') == ourHandler)
		local plates = evtFrame:IsEventRegistered('NAME_PLATE_UNIT_ADDED') == true
		local casts = evtFrame:IsEventRegistered('UNIT_SPELLCAST_START') == true
		local okName, fname = pcall(evtFrame.GetDebugName, evtFrame)
		ns.Msg('Attached to handler: ' .. YN(true) .. '   (frame ' .. (okName and tostring(fname) or '?') .. ')'
			.. (live and '' or '   |cffff5555our handler was REPLACED by something else|r'))
		ns.Msg('  That frame is listening for plates: ' .. YN(plates) .. '   for casts: ' .. YN(casts)
			.. (casts and '' or '   |cffffd100- Targeted Spell Bars is not showing in this content (EllesmereUI Where to Show); nothing to filter until it does.|r'))
	else
		ns.Msg('Attached to handler: ' .. YN(false) .. '   (press Re-detect, or /xerionmc detect)')
	end

	ns.Msg('|cffffd100Hide boss casts: ' .. YN(cfg.hideBossCasts) .. '|r')

	local tsb = TSBCfg()
	ns.Msg(format('Bar look: spark %s   marker %s (%d, %d)   EllesmereUI marker shown: %s',
		YN(cfg.spark), tostring(cfg.markerPos), cfg.markerX or 0, cfg.markerY or 0,
		YN(tsb and tsb.showRaidMarker == true)))
	ns.Msg(format('  EllesmereUI namespace: %s   hooked: %s   container: %s   bars dressed: %d of %d   watching cast starts: %s',
		YN(EMT() ~= nil), YN(emtHooked), YN(TSBEnabled() and Container() ~= nil),
		barCount, MaxBars(), YN(watching)))

	local units = LivePlateUnits({})
	if #units == 0 then
		ns.Msg('No enemy nameplates on screen.')
	else
		ns.Msg(format('Nameplates (%d):', #units))
		for _, unit in ipairs(units) do DescribeUnit(unit) end
	end
	if UnitExists('target') then DescribeUnit('target', 'target') end
	ns.Msg('|cff888888/xerionmc debug|r toggles a line for every cast-admit event; |cff888888/xerionmc scan|r lists the candidate frames and why each was rejected.')
end

local function ScanReport()
	local list = Candidates()
	if not list then
		ns.Msg('GetFramesRegisteredForEvent is not available on this client - the filter has no way to find the handler.')
		return
	end
	ns.Msg(format('Frames registered for %s: %d', GATE_EVENT, #list))
	for i = 1, #list do
		local f = list[i]
		local okName, name = pcall(function() return f:GetDebugName() end)
		local ok, why = pcall(WhyNotTSBFrame, f)
		local verdict
		if not ok then
			verdict = 'error: ' .. tostring(why)
		elseif why == nil then
			verdict = '|cff55ff55MATCH|r'
		else
			verdict = why
		end
		ns.Msg(format('  %d. %s - %s', i, okName and tostring(name) or '?', verdict))
	end
end

_G.SLASH_XERIONMYTHICCAST1 = '/xerionmc'
_G.SlashCmdList.XERIONMYTHICCAST = function(msg)
	msg = (msg or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
	if msg == 'debug' then
		debugOn = not debugOn
		ns.Msg('Boss cast filter debug: ' .. YN(debugOn)
			.. (debugOn and ' - pull something and watch the events.' or ''))
		return
	end
	if msg == 'detect' then
		ns.EMCRedetect()
		return
	end
	if msg == 'scan' then
		ScanReport()
		return
	end
	Dump()
end

local BURSTY_EVENTS = {
	PLAYER_REGEN_DISABLED = true,
}

local driver = CreateFrame('Frame')
driver:RegisterEvent('ADDON_LOADED')
driver:RegisterEvent('PLAYER_LOGIN')
driver:RegisterEvent('PLAYER_ENTERING_WORLD')
driver:RegisterEvent('ZONE_CHANGED_NEW_AREA')
driver:RegisterEvent('CHALLENGE_MODE_START')
driver:RegisterEvent('CHALLENGE_MODE_COMPLETED')
driver:RegisterEvent('PLAYER_REGEN_DISABLED')
driver:SetScript('OnEvent', function(_, event, arg1)
	if event == 'ADDON_LOADED' then
		if arg1 ~= TSB_ADDON then return end
		ns.hasEUIMythicCast = true
		return
	end
	if not ns.hasEUIMythicCast then
		ns.hasEUIMythicCast = ns.IsAddOnLoaded(TSB_ADDON)
		if not ns.hasEUIMythicCast then return end
	end
	HookEMT()
	QueueScan()
	if not GetCfg().hideBossCasts then return end
	local force = not BURSTY_EVENTS[event]
	C_Timer.After(0, function()
		Install(force)
		Resync()
	end)
end)

ns.hasEUIMythicCast = ns.IsAddOnLoaded(TSB_ADDON)
