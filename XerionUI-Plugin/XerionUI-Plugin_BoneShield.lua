local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('BoneShield', hooksecurefunc, C_Timer)
local _G = _G

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local GetTime = GetTime
local pairs, ipairs, type = pairs, ipairs, type
local pcall = pcall
local wipe = wipe
local tsort = table.sort

ns.hasBoneShield = true

local BONE_SHIELD = 195181

local OSSUARY = 219786
local OSSUARY_AT = 5

local REFRESH_IDS = {
	[195182] = true,
	[195292] = true,
	[108199] = true,
	[49028]  = true,
	[439843] = true,
	[49576]  = true,
}

local BUFF_VIEWERS = { 'BuffIconCooldownViewer', 'BuffBarCooldownViewer' }

local DEFAULT_SOUND = '|cFF00FF00Kira - External|r'

local secret = ns.IsSecret

local GPA = _G.C_UnitAuras and _G.C_UnitAuras.GetPlayerAuraBySpellID

local DEFAULTS = {
	enable = false,

	glow = true,
	glowThreshold = 8,
	glowColor = { 1, 0.16, 0.16, 1 },

	soundEnabled = true,
	soundThreshold = 5,
	soundInCombatOnly = true,
	sound = DEFAULT_SOUND,

	stackWarn = true,

	duration = 30,

	learnedRefresh = {},
}

local function Migrate(cfg)
	ns.GlowMigrate(cfg, { 1, 0.16, 0.16, 1 })
	cfg.glowType, cfg.glowThickness = nil, nil
	cfg.stacksEnable, cfg.stacksThreshold = nil, nil
	cfg.stackAt = nil
	if type(cfg.learnedRefresh) == 'table' then cfg.learnedRefresh[49576] = nil end
	if cfg.threshold ~= nil then
		if cfg.glowThreshold == nil then cfg.glowThreshold = cfg.threshold end
		if cfg.soundThreshold == nil then cfg.soundThreshold = cfg.threshold end
		cfg.threshold = nil
	end
end

local function GetCfg() return ns.ModuleCfg('boneShield', DEFAULTS, Migrate) end
ns.BSGetCfg = GetCfg

local function IsDeathKnight() return ns.IsClass('DEATHKNIGHT') end
local function IsBlood() return ns.IsSpec('DEATHKNIGHT', 1) end

local CooldownMatches = ns.CooldownMatches

local iconCache = {}
local function SpellIcon(spellID)
	if iconCache[spellID] then return iconCache[spellID] end
	local get = _G.C_Spell and _G.C_Spell.GetSpellTexture
	if get then
		local ok, tex = pcall(get, spellID)
		if ok and tex and not secret(tex) then iconCache[spellID] = tex end
	end
	return iconCache[spellID]
end
local function BoneShieldIcon() return SpellIcon(BONE_SHIELD) end

local function EUIFrameIs(f, spellID)
	local tex = f.Icon or f._tex
	if not tex or not tex.GetTexture then return false end
	local want = SpellIcon(spellID)
	if not want then return false end
	local ok, t = pcall(tex.GetTexture, tex)
	if not ok or t == nil or secret(t) then return false end
	return t == want
end

local targets = {}
local ossuaryFrames = {}
local sawCdmFrame
local ScanOssuary
local lastScan = 0
local DropOrphanGlows
local previewFrame

-- WHICH FRAME IS OSSUARY, REMEMBERED
-- The stack warning asks every Ossuary frame "are you still Ossuary?" ten
-- times a second, and the honest answer costs a cooldown-info table and four
-- ID comparisons. The answer only changes when the viewer hands the frame a
-- different cooldown, so it is kept per frame against the cooldownID it was
-- given for (the same trick as the `ident` cache in DRWSound). Weak keys: a
-- frame the viewer throws away takes its entry with it. The whole cache is
-- dropped by every rescan and by a spec or talent change, which is when a
-- cooldownID's spell list can move under the same number; between those, a
-- changed cooldownID simply misses and asks again. Only a readable ID is ever
-- kept - a secret one takes the old uncached road.
local ossIdentID = setmetatable({}, { __mode = 'k' })
local ossIdentIs = setmetatable({}, { __mode = 'k' })
local function ForgetOssuaryIdent()
	wipe(ossIdentID)
	wipe(ossIdentIs)
end

local function AddTarget(list, f)
	if not f then return end
	for i = 1, #list do if list[i] == f then return end end
	list[#list + 1] = f
end

local function Rescan()
	local found = {}
	ForgetOssuaryIdent()
	if ScanOssuary then ScanOssuary() end

	for v = 1, #BUFF_VIEWERS do
		local viewer = _G[BUFF_VIEWERS[v]]
		if viewer and viewer.GetItemFrames then
			local ok, frames = pcall(viewer.GetItemFrames, viewer)
			if ok and type(frames) == 'table' then
				for i = 1, #frames do
					local f = frames[i]
					if f and f.GetCooldownID then
						local okID, id = pcall(f.GetCooldownID, f)
						if okID and CooldownMatches(id, BONE_SHIELD) then AddTarget(found, f) end
					end
				end
			end
		end
	end

	local getBar = _G._ECME_GetBarFrame
	local db = _G._ECME_AceDB
	local bars = db and db.profile and db.profile.cdmBars and db.profile.cdmBars.bars
	if getBar and type(bars) == 'table' then
		for b = 1, #bars do
			local bd = bars[b]
			local bt = bd and bd.barType
			if bd and bd.key and (bt == 'buffs' or bt == 'custom_buff') then
				local okB, bar = pcall(getBar, bd.key)
				if okB and bar and bar.GetChildren then
					local kids = { bar:GetChildren() }
					for i = 1, #kids do
						local f = kids[i]
						if f and f._isCustomBuffFrame and not f._isPlaceholderFrame
							and EUIFrameIs(f, BONE_SHIELD) then
							AddTarget(found, f)
						end
					end
				end
			end
		end
	end

	targets = found
	lastScan = GetTime()
	if #found > 0 then sawCdmFrame = true end
	if DropOrphanGlows then DropOrphanGlows(found) end
	return found
end

local function FrameActive(f)
	if not f then return false end
	if f._isPlaceholderFrame then return false end
	local ok, shown = pcall(f.IsShown, f)
	if not ok or not shown then return false end
	local okA, a = pcall(f.GetAlpha, f)
	if okA and type(a) == 'number' and a < 0.05 then return false end
	return true
end

local function AnyActive(list)
	for i = 1, #list do
		if FrameActive(list[i]) then return true end
	end
	return false
end

local function AnyTargetActive() return AnyActive(targets) end

local function FrameIsOssuary(f)
	if not f then return false end
	if f.GetCooldownID then
		local ok, id = pcall(f.GetCooldownID, f)
		if ok and not secret(id) and id then
			local match
			if ossIdentID[f] == id then
				match = ossIdentIs[f]
			else
				match = CooldownMatches(id, OSSUARY)
				ossIdentID[f], ossIdentIs[f] = id, match
			end
			if match then return true end
		end
	end
	if f.GetSpellID then
		local ok, sid = pcall(f.GetSpellID, f)
		if ok and sid and not secret(sid) and sid == OSSUARY then return true end
	end
	return false
end

ScanOssuary = function()
	for v = 1, #BUFF_VIEWERS do
		local viewer = _G[BUFF_VIEWERS[v]]
		if viewer and viewer.GetChildren then
			for _, f in ipairs({ viewer:GetChildren() }) do
				if FrameIsOssuary(f) then AddTarget(ossuaryFrames, f) end
			end
		end
	end
end

local ossuaryProven = setmetatable({}, { __mode = 'k' })
local function OssuaryUp()
	local known, up, src = false, false, nil
	for i = #ossuaryFrames, 1, -1 do
		local f = ossuaryFrames[i]
		if not FrameIsOssuary(f) then
			table.remove(ossuaryFrames, i)
			ossuaryProven[f] = nil
		else
			local flag
			if f.IsActive then
				local ok, a = pcall(f.IsActive, f)
				if ok and a ~= nil and not secret(a) and type(a) == 'boolean' then flag = a end
			end

			if flag ~= nil then
				known, src = true, 'isActive'
				if flag then up = true ossuaryProven[f] = true end
			elseif FrameActive(f) then
				ossuaryProven[f] = true
				known, up = true, true
				src = src or 'drawn'
			elseif ossuaryProven[f] then
				known = true
				src = src or 'drawn'
			end
		end
	end
	if not known then return nil, 'none' end
	return up, src
end

local function StacksLow()
	local cfg = GetCfg()
	if not cfg.stackWarn then return false end

	local o = OssuaryUp()

	if GPA then
		local ok, aura = pcall(GPA, BONE_SHIELD)
		if ok and aura then
			local n = aura.applications
			if n ~= nil and not secret(n) and type(n) == 'number' then
				return n < OSSUARY_AT
			end
		end
	end

	if o ~= nil then return not o end

	return nil
end

local overlays = setmetatable({}, { __mode = 'k' })

local function EnsureOverlay(f)
	local ov = overlays[f]
	if not ov or ov:GetParent() ~= f then
		ov = CreateFrame('Frame', nil, f)
		ov:EnableMouse(false)
		overlays[f] = ov
	end
	ov:SetAllPoints(f)
	local okL, lvl = pcall(f.GetFrameLevel, f)
	if okL and type(lvl) == 'number' then ov:SetFrameLevel(lvl) end
	ov:Show()
	return ov
end

local function StopGlowOn(ov)
	if not ov then return end
	ns.GlowStop(ov)
	ov:SetAlpha(0)
	ov.__kiraLvl = nil
end

local SHAPE_STRENGTH = 2
local glowProxy = {}

-- __kiraLvl is the frame level this overlay was last lifted to, kept only
-- when that level was a readable number; KeepGlowOn below uses it to skip the
-- lift when the icon has not moved.
local function StartGlowOn(ov)
	ov:SetAlpha(1)
	ov.__kiraLvl = nil
	local okP, par = pcall(ov.GetParent, ov)
	if okP and par then
		local okL, lvl = pcall(par.GetFrameLevel, par)
		if okL and type(lvl) == 'number' and pcall(ov.SetFrameLevel, ov, lvl) and not secret(lvl) then
			ov.__kiraLvl = lvl
		end
	end
	if ov.__glow then return end
	local w, h = ov:GetSize()
	if not w or w <= 0 then
		local par = ov:GetParent()
		local okP, pw, ph = pcall(par.GetSize, par)
		w = (okP and pw and pw > 0) and pw or 36
		h = (okP and ph and ph > 0) and ph or w
	end
	local cfg = GetCfg()
	glowProxy.glow = cfg.glow
	glowProxy.glowType = 'shape'
	glowProxy.glowColor = cfg.glowColor
	glowProxy.glowThickness = SHAPE_STRENGTH
	ns.GlowStart(ov, w, h, glowProxy)
end

-- The tick asks for the glow ten times a second while it is due. An overlay
-- that is already glowing on this very icon needs none of the setup again:
-- its points, its alpha and its shown state are ours alone and nothing else
-- touches them, and its look was fixed when it started (every settings
-- change goes through RestartGlow, which stops it). The one thing that can
-- drift underneath is the icon's frame level, so that is still read each
-- time and the overlay re-lifted only when it moved - or every time, as
-- before, when the level cannot be compared.
local function KeepGlowOn(f)
	local ov = overlays[f]
	if ov and ov.__glow and ov:GetParent() == f then
		local okL, lvl = pcall(f.GetFrameLevel, f)
		if okL and type(lvl) == 'number' then
			if secret(lvl) or lvl ~= ov.__kiraLvl then
				ov.__kiraLvl = nil
				if pcall(ov.SetFrameLevel, ov, lvl) and not secret(lvl) then ov.__kiraLvl = lvl end
			end
		end
		return
	end
	StartGlowOn(EnsureOverlay(f))
end

local glowing = false
local function SetGlow(on)
	if on then
		if #targets == 0 and (GetTime() - lastScan) > 1 then Rescan() end
		local any = false
		for i = 1, #targets do
			local f = targets[i]
			local ov = overlays[f]
			if FrameActive(f) then
				KeepGlowOn(f)
				any = true
			elseif ov and ov.__glow then
				StopGlowOn(ov)
			end
		end
		glowing = any
	else
		for _, ov in pairs(overlays) do
			if ov.__glow then StopGlowOn(ov) end
		end
		glowing = false
	end
end

-- Counted for /xerionbone, which prints and zeroes them: how often the buff
-- viewers refresh, how many rescans that came to after coalescing, and how
-- many glows had to come off an icon that stopped being Bone Shield.
local viewerRefreshes, viewerRescans, glowsDropped = 0, 0, 0
local countFrom = GetTime()

DropOrphanGlows = function(list)
	for f, ov in pairs(overlays) do
		if ov.__glow and f ~= previewFrame then
			local keep = false
			for i = 1, #list do if list[i] == f then keep = true break end end
			if not keep then
				StopGlowOn(ov)
				glowsDropped = glowsDropped + 1
			end
		end
	end
end

local PREVIEW_SIZE = 48

local function EnsurePreviewIcon()
	if previewFrame then return previewFrame end
	previewFrame = CreateFrame('Frame', 'XerionUIBoneShieldPreview', _G.UIParent)
	previewFrame:SetSize(PREVIEW_SIZE, PREVIEW_SIZE)
	previewFrame:SetPoint('CENTER', _G.UIParent, 'CENTER', 0, 0)
	previewFrame:SetFrameStrata('HIGH')
	previewFrame:EnableMouse(false)
	local border = previewFrame:CreateTexture(nil, 'BACKGROUND')
	border:SetAllPoints()
	border:SetColorTexture(0, 0, 0, 1)
	local icon = previewFrame:CreateTexture(nil, 'ARTWORK')
	icon:SetPoint('TOPLEFT', 1, -1)
	icon:SetPoint('BOTTOMRIGHT', -1, 1)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	previewFrame.Icon = icon
	previewFrame:Hide()
	return previewFrame
end

local function SetPreviewGlow(on)
	if on then
		local f = EnsurePreviewIcon()
		local tex = BoneShieldIcon()
		if tex then f.Icon:SetTexture(tex) end
		f:Show()
		StartGlowOn(EnsureOverlay(f))
	elseif previewFrame then
		local ov = overlays[previewFrame]
		if ov then StopGlowOn(ov) end
		previewFrame:Hide()
	end
end

local function RestartGlow()
	for _, ov in pairs(overlays) do StopGlowOn(ov) end
	glowing = false
end

local expire = 0
local clockSetAt = 0
local soundArmed = false
local lowRang = nil
local downSince = 0
local preview = false
local SyncTicker

local function ReadRealExpire()
	if not GPA then return nil end
	local ok, aura = pcall(GPA, BONE_SHIELD)
	if not ok or not aura then return nil end
	local exp = aura.expirationTime
	if exp == nil or secret(exp) then return nil end
	if type(exp) ~= 'number' or exp <= 0 then return nil end
	return exp
end

local function TryRealSync()
	local exp = ReadRealExpire()
	if not exp then return false, false end
	local moved = (exp - expire) > 0.15 or (expire - exp) > 0.15
	expire = exp
	clockSetAt = GetTime()
	return true, moved
end

local function Refresh()
	local cfg = GetCfg()
	expire = GetTime() + (cfg.duration or 30)
	clockSetAt = GetTime()
	soundArmed = true
	downSince = 0
	C_Timer.After(0, function()
		if TryRealSync() then SyncTicker() end
	end)
	SyncTicker()
end

local function Clear()
	expire = 0
	soundArmed, lowRang = false, nil
	downSince = 0
	SetGlow(false)
	SyncTicker()
end

local function Tick()
	local cfg = GetCfg()
	if preview then return end
	if not cfg.enable or not IsBlood() then SetGlow(false) return end

	local rem = expire - GetTime()

	local up
	if sawCdmFrame then
		up = AnyTargetActive()
	else
		up = rem > 0
	end

	if not up then
		SetGlow(false)
		if downSince == 0 then downSince = GetTime() end
		if (GetTime() - downSince) < 0.5 then return end
		expire = 0
		soundArmed, lowRang = false, nil
		C_Timer.After(0, SyncTicker)
		return
	end
	downSince = 0

	if rem <= 0 then
		SetGlow(false)
		expire = 0
		soundArmed, lowRang = false, nil
		C_Timer.After(0, SyncTicker)
		return
	end

	if rem > (cfg.soundThreshold or 5) + 0.5 then soundArmed = true end

	local lowNow = StacksLow()
	local low = lowNow == true
	SetGlow(cfg.glow and (low or rem <= (cfg.glowThreshold or 8)))

	if not cfg.soundEnabled then return end

	local inCombat = _G.InCombatLockdown() or _G.UnitAffectingCombat('player')
	local mayRing = (not cfg.soundInCombatOnly) or inCombat

	local rang = false
	if lowNow == false then
		lowRang = false
	elseif lowNow == true and lowRang == false and mayRing then
		lowRang, rang = true, true
		ns.PlaySoundByName(cfg.sound)
	end

	if soundArmed and rem <= (cfg.soundThreshold or 5) and mayRing then
		soundArmed = false
		if not rang then ns.PlaySoundByName(cfg.sound) end
	end
end

local tickTicker
SyncTicker = function()
	local cfg = GetCfg()
	local want = (not preview) and cfg.enable and IsBlood() and expire > 0 and true or false
	if want and not tickTicker then
		tickTicker = C_Timer.NewTicker(0.1, Tick)
	elseif not want and tickTicker then
		tickTicker:Cancel()
		tickTicker = nil
		if not preview then SetGlow(false) end
	end
end

local LEARN_JUMP    = 1.0
local UNLEARN_AFTER = 3
local RE_OBSERVE    = 30

local misses, lastObserved = {}, {}

local function Learned()
	local cfg = GetCfg()
	local t = cfg.learnedRefresh
	if type(t) ~= 'table' then t = {} cfg.learnedRefresh = t end
	return t
end

local function IsRefresher(id)
	if REFRESH_IDS[id] then return true end
	return Learned()[id] == true
end

local function ObserveCast(spellID)
	if not GPA then return end
	if REFRESH_IDS[spellID] then return end
	local now = GetTime()
	local learned = Learned()
	if learned[spellID] and (now - (lastObserved[spellID] or 0)) < RE_OBSERVE then return end
	lastObserved[spellID] = now

	local before = ReadRealExpire()
	C_Timer.After(0, function()
		local after = ReadRealExpire()

		if after == nil or before == nil then return end

		if (after - before) > LEARN_JUMP then
			if not learned[spellID] then learned[spellID] = true end
			misses[spellID] = nil
			expire = after
			clockSetAt = GetTime()
			soundArmed = true
			downSince = 0
			SyncTicker()
			Tick()
			return
		end

		if learned[spellID] then
			local n = (misses[spellID] or 0) + 1
			if n >= UNLEARN_AFTER then
				learned[spellID] = nil
				misses[spellID] = nil
			else
				misses[spellID] = n
			end
		end
	end)
end

local hookedViewers = {}
local resyncQueued, restartQueued, fromViewer

-- NO GLOW RESTART ON A VIEWER REFRESH
-- A buff viewer refreshes as a whole on every full aura update for the player
-- or the target - a target swap usually brings one - and when a viewer set to
-- show in combat only appears, so restarting every glow here blinked the
-- warning off and back on up to a tenth of a second later each time. The
-- rescan alone already does the job: it asks every icon afresh which cooldown
-- it holds, and DropOrphanGlows takes
-- the glow off any icon that is no longer Bone Shield - including a pooled
-- frame the viewer has just handed a different buff - while an icon that
-- still is keeps its glow untouched (KeepGlowOn re-lifts it if its level
-- moved). When the viewer moved Bone Shield onto another frame, the glow is
-- relit on the new one straight after the rescan instead of on the next tick.
-- The UI skin applying its settings is rare and may restyle the icons, so
-- that path still restarts the glows as before.
local function RunQueued()
	resyncQueued = nil
	local restart, viewer = restartQueued, fromViewer
	restartQueued, fromViewer = nil, nil
	if restart then RestartGlow() end
	Rescan()
	if viewer then viewerRescans = viewerRescans + 1 end
	if glowing and not preview then SetGlow(true) end
end

-- The viewer hooks go in at every loading screen and fire on every
-- Cooldown Manager refresh, for any class; same gate as Apply, so a player
-- who is not Blood with the module on pays one settings read per refresh.
local function QueueRescan(restart)
	if resyncQueued and not restart then return end
	local cfg = GetCfg()
	if not preview and (not cfg.enable or not IsBlood()) then return end
	if restart then restartQueued = true else fromViewer = true end
	if resyncQueued then return end
	resyncQueued = true
	C_Timer.After(0, RunQueued)
end

-- Two wrappers, because a hook is handed the hooked function's arguments and
-- QueueRescan's one argument must not be the viewer.
local function OnViewerRefresh()
	viewerRefreshes = viewerRefreshes + 1
	QueueRescan(false)
end
local function OnSkinApply() QueueRescan(true) end

local function HookViewers()
	for i = 1, #BUFF_VIEWERS do
		local v = _G[BUFF_VIEWERS[i]]
		if v and v.RefreshData and not hookedViewers[v] then
			hookedViewers[v] = true
			pcall(hooksecurefunc, v, 'RefreshData', OnViewerRefresh)
		end
	end
	if type(_G._ECME_Apply) == 'function' and not hookedViewers.__ecme then
		hookedViewers.__ecme = true
		pcall(hooksecurefunc, _G, '_ECME_Apply', OnSkinApply)
	end
end

C_Timer.NewTicker(5, function()
	local cfg = GetCfg()
	if not cfg.enable or not IsBlood() then return end
	HookViewers()
	Rescan()
end)

local function Apply()
	local cfg = GetCfg()
	if not preview and (not cfg.enable or not IsBlood()) then
		SetGlow(false)
		SyncTicker()
		return
	end
	RestartGlow()
	if preview then
		SetPreviewGlow(true)
		return
	end
	HookViewers()
	Rescan()
	TryRealSync()
	SyncTicker()
	Tick()
end
ns.BSApply = ns.Coalesce(function() Apply() end)

ns.BSIsPreview = function() return preview end
ns.BSSetPreview = function(state)
	preview = state and true or false
	RestartGlow()
	if preview then
		SetPreviewGlow(true)
		SyncTicker()
	else
		SetPreviewGlow(false)
		SyncTicker()
		Tick()
	end
end

local CAST_LOG, castLog, castLogN = 8, {}, 0
local function LogCast(id, verdict)
	castLogN = castLogN % CAST_LOG + 1
	local e = castLog[castLogN]
	if not e then e = {} castLog[castLogN] = e end
	e.id, e.verdict, e.t = id, verdict, GetTime()
end

ns.BSTest = function()
	local function p(...) print('|cffff7d0aXerionUI-BoneShield|r', ...) end
	local cfg = GetCfg()
	p('--- Bone Shield diagnostics ---')
	local okC, _, cls = pcall(_G.UnitClass, 'player')
	p('class =', okC and tostring(cls) or 'CALL FAILED',
		'| Blood =', IsBlood() and 'yes' or 'NO (module refuses to draw)',
		'| enabled =', cfg.enable and 'on' or 'off',
		'| in combat =', (_G.InCombatLockdown() or _G.UnitAffectingCombat('player')) and 'yes' or 'no')

	local span = GetTime() - countFrom
	p(('buff viewer refreshes = %d in %.0fs (%.1f a minute) | rescans run = %d | glows dropped by a rescan = %d'):format(
		viewerRefreshes, span, span > 0 and viewerRefreshes * 60 / span or 0, viewerRescans, glowsDropped))
	p('   |cff777777counted since the last /xerionbone or /reload - run it again after a minute of target swaps|r')
	viewerRefreshes, viewerRescans, glowsDropped = 0, 0, 0
	countFrom = GetTime()

	local found = Rescan()
	p('CDM icons found =', #found, '| ever found this session =', sawCdmFrame and 'yes' or 'NO')
	for i = 1, #found do
		local f = found[i]
		local nm = (f.GetName and f:GetName()) or 'unnamed'
		local par = f:GetParent()
		local pn = (par and par.GetName and par:GetName()) or 'unnamed parent'
		p(('  [%d] %s  parent=%s  kind=%s  active=%s'):format(i, nm, pn,
			f._isCustomBuffFrame and 'EUI custom aura' or 'Blizzard viewer',
			FrameActive(f) and 'YES' or 'no'))
	end
	if #found == 0 then
		p('|cffff2020=> Bone Shield is not on any Cooldown Manager buff bar, so there is nothing to glow.|r')
		p('   The sound still works: it runs off the cast clock alone.')
	end

	local rem = expire > 0 and (expire - GetTime()) or nil
	p('clock =', rem and ('%.1fs left'):format(rem) or 'not running',
		'| sound armed =', soundArmed and 'yes' or 'no',
		'| low-stack sound =', lowRang == nil and 'not established'
			or (lowRang and 'already rung for this dip' or 'armed'),
		'| glowing =', glowing and 'yes' or 'no')

	p('glow =', cfg.glow and 'on' or 'off', '| style = Shape Glow')
	p('thresholds: glow at', cfg.glowThreshold, 's | sound at', cfg.soundThreshold, 's',
		cfg.soundInCombatOnly and '(in combat only)' or '(any time)',
		'| fallback duration =', cfg.duration, 's')

	local cnt
	if GPA then
		local okA, aura = pcall(GPA, BONE_SHIELD)
		if okA and aura then
			local n = aura.applications
			cnt = (n ~= nil and not secret(n) and type(n) == 'number') and n
				or '|cffffd100hidden (restricted) - Ossuary answers instead|r'
		end
	end
	local low = StacksLow()
	p('low-stack warning =', cfg.stackWarn and 'on (Ossuary up or not - always 5)' or 'off',
		'| rings too:', (cfg.stackWarn and cfg.soundEnabled) and 'yes, once per dip' or 'no')
	p('  stack count readable here =', cnt == nil and 'no Bone Shield aura' or tostring(cnt))
	local o, osrc = OssuaryUp()
	p('  Ossuary frames matched =', #ossuaryFrames, '| answered by =', tostring(osrc),
		'| believed =', o == nil and '|cffff2020NO - none of them has ever lit up|r'
			or (o and '|cff00ff00yes, and Ossuary is UP (5+ stacks)|r'
			      or '|cffffd100yes, and Ossuary is DOWN (under 5 stacks)|r'))
	p('  verdict =', low == true and '|cffff2020UNDER threshold|r'
		or (low == false and 'at or above' or '|cffffd100unknown - not warning|r'))

	p('|cff33ccffTIMER CHAIN|r')
	p('  1. gate       =', (cfg.enable and IsBlood() and not preview) and '|cff00ff00open|r'
		or ('|cffff2020shut|r - ' .. ((not cfg.enable) and 'module is off'
			or preview and 'preview is on' or 'not Blood spec')))
	p('  2. ticker     =', tickTicker and '|cff00ff00running|r'
		or '|cffffd100stopped|r (nothing to count - it only runs while a window is)')
	p('  3. clock      =', expire > 0 and ('|cff00ff00running|r, %.1fs left'):format(expire - GetTime())
		or (clockSetAt > 0
			and ('|cffffd100not running|r - last started %.0fs ago, so the chain DOES work'):format(GetTime() - clockSetAt)
			or '|cffff2020NEVER started|r - not one cast has been accepted as a refresh'))
	local realExp = ReadRealExpire()
	p('  4. real timer =', realExp and ('|cff00ff00readable|r (%.1fs left) - used as the truth'):format(realExp - GetTime())
		or ('|cffffd100not readable here|r - falling back to the ' .. tostring(cfg.duration) .. 's setting'))
	p('     |cff777777Unreadable is NORMAL in a key and is not the fault. It only means the|r')
	p('     |cff777777fallback duration has to be right for your build.|r')
	p('  5. aura api   =', GPA and 'C_UnitAuras.GetPlayerAuraBySpellID present'
		or '|cffff2020MISSING on this client|r - no real timer, no stack count, no learning')

	p('  recent casts, newest first:')
	local any = false
	for i = 0, CAST_LOG - 1 do
		local e = castLog[(castLogN - i - 1) % CAST_LOG + 1]
		if e then
			any = true
			local nm = '?'
			local CS = _G.C_Spell
			if CS and CS.GetSpellName then
				local okN, n = pcall(CS.GetSpellName, e.id)
				if okN and n then nm = n end
			end
			p(('    %5.1fs ago  %-7d %s  -> %s'):format(GetTime() - e.t, e.id, nm, e.verdict))
		end
	end
	if not any then
		p('    |cffff2020nothing at all|r - cast something and run this again. If it stays')
		p('    empty, UNIT_SPELLCAST_SUCCEEDED is not reaching this module.')
	end
	p('  |cff777777A cast reading "not a refresher" that SHOULD refresh Bone Shield is the|r')
	p('  |cff777777bug to report - with its ID. It gets learned automatically once the real|r')
	p('  |cff777777timer is readable, which is why it can work outside a key and not inside.|r')

	local remNow = expire > 0 and (expire - GetTime()) or nil
	local byTimer = cfg.glow and remNow and remNow <= (cfg.glowThreshold or 8)
	local byStacks = cfg.glow and low == true
	p('|cff33ccffGLOW OVERLAYS|r  (module glowing flag =', tostring(glowing) .. ')')
	if #targets == 0 then
		p('  no Bone Shield icon to draw on')
	end
	for i = 1, #targets do
		local f = targets[i]
		local ov = overlays[f]
		if not ov then
			p(('  [%d] no overlay built yet'):format(i))
		else
			local okA, a = pcall(ov.GetAlpha, ov)
			local okL, lvl = pcall(ov.GetFrameLevel, ov)
			local okFL, flvl = pcall(f.GetFrameLevel, f)
			local running = ov.__glow and true or false
			local bad = running and okA and a and a < 0.5
			p(('  [%d] ours: running=%s alpha=%s level=%s (icon %s) shown=%s%s'):format(i,
				tostring(running), okA and ('%.2f'):format(a) or '?',
				okL and tostring(lvl) or '?', okFL and tostring(flvl) or '?',
				tostring(ov:IsShown()),
				bad and '  |cffff2020<- RUNNING BUT INVISIBLE|r' or ''))
		end
		local others = 0
		local okC, n = pcall(function() return select('#', f:GetChildren()) end)
		if okC and n then
			for c = 1, n do
				local ch = select(c, f:GetChildren())
				if ch and ch ~= ov and ch._glowActive then others = others + 1 end
			end
		end
		p(('       other addons glowing this icon = %s%s'):format(others,
			others > 0 and ' |cffffd100(EllesmereUI Buff Glow is on for it)|r' or ''))
	end

	p('|cff33ccffWHY IT IS GLOWING RIGHT NOW =|r',
		(not glowing) and 'it is not' or (
			(byTimer and byStacks) and 'BOTH'
			or byTimer and ('the TIMER (%.1fs left vs threshold %s)'):format(remNow, tostring(cfg.glowThreshold))
			or byStacks and 'the STACK warning'
			or 'neither test says it should be - stale glow, please report this line'))
	if #ossuaryFrames > 0 then
		for i = 1, #ossuaryFrames do
			local f = ossuaryFrames[i]
			local okS, shown = pcall(f.IsShown, f)
			local okV, vis = pcall(f.IsVisible, f)
			local okA, al = pcall(f.GetAlpha, f)
			local act = 'n/a'
			if f.IsActive then
				local okI, a = pcall(f.IsActive, f)
				act = (not okI) and 'call failed' or (secret(a) and 'SECRET' or tostring(a))
			end
			p(('   frame %d: shown=%s visible=%s alpha=%s isActive=%s believed=%s'):format(i,
				okS and tostring(shown) or '?', okV and tostring(vis) or '?',
				okA and tostring(al) or '?', act, tostring(ossuaryProven[f] == true)))
		end
	end

	p('all Cooldown Manager buff icons right now:')
	local seen = 0
	for v = 1, #BUFF_VIEWERS do
		local viewer = _G[BUFF_VIEWERS[v]]
		if viewer and viewer.GetChildren then
			local kids = { viewer:GetChildren() }
			for i, f in ipairs(kids) do
				local id, sid
				if f and f.GetCooldownID then
					local ok, v2 = pcall(f.GetCooldownID, f)
					if ok and v2 and not secret(v2) then id = v2 end
				end
				if f and f.GetSpellID then
					local ok, v2 = pcall(f.GetSpellID, f)
					if ok and v2 and not secret(v2) then sid = v2 end
				end
				if id or sid then
					seen = seen + 1
					if seen <= 20 then
						local okS, shown = pcall(f.IsShown, f)
						p(('   cdID=%s spellID=%s shown=%s%s'):format(tostring(id), tostring(sid),
							okS and tostring(shown) or '?',
							FrameIsOssuary(f) and '   <- read as OSSUARY' or ''))
					end
				end
			end
		end
	end
	if seen == 0 then p('   |cffff2020none - the buff viewers are empty or unreadable|r') end

	if #ossuaryFrames == 0 then
		p('  |cffffd100=> add Ossuary (219786) to a Cooldown Manager buff bar. Without it this|r')
		p('  |cffffd100   warning cannot work in a key, where the stack count is hidden.|r')
	end

	local real = ReadRealExpire()
	p('real expiration readable here =', real and ('yes, %.1fs left'):format(real - GetTime())
		or '|cffffd100no (restricted content - the cast clock is all there is)|r')

	local names = {}
	for id in pairs(REFRESH_IDS) do names[#names + 1] = id end
	tsort(names)
	p('refresh spells, built in =', table.concat(names, ', '))
	local ln = {}
	for id in pairs(Learned()) do ln[#ln + 1] = id end
	tsort(ln)
	p('refresh spells, learned from your casts =',
		#ln > 0 and table.concat(ln, ', ') or 'none yet')
	if #ln > 0 then
		for i = 1, #ln do
			local id = ln[i]
			local m = misses[id]
			if m then p(('   %d: %d/%d clean observations - drops if it stays clean'):format(id, m, UNLEARN_AFTER)) end
		end
	end
	p('=> a spell that refreshes Bone Shield is learned the first time you cast it')
	p('   somewhere the expiration is readable, and that carries into keys.')
end

local evt = CreateFrame('Frame')
evt:RegisterEvent('PLAYER_ENTERING_WORLD')
evt:RegisterEvent('PLAYER_REGEN_DISABLED')
evt:RegisterEvent('PLAYER_REGEN_ENABLED')
evt:RegisterUnitEvent('UNIT_SPELLCAST_SUCCEEDED', 'player')
evt:RegisterUnitEvent('UNIT_AURA', 'player')
-- The player's own spec only: unfiltered, a party member's respec wiped the
-- Bone Shield clock.
evt:RegisterUnitEvent('PLAYER_SPECIALIZATION_CHANGED', 'player')
evt:RegisterEvent('TRAIT_CONFIG_UPDATED')
evt:SetScript('OnEvent', function(_, event, _, _, spellID)
	-- A talent change can move the spell list behind a cooldownID without the
	-- ID itself changing, so the remembered Ossuary answers go. Nothing else
	-- listens for it here.
	if event == 'TRAIT_CONFIG_UPDATED' then
		ForgetOssuaryIdent()
		return
	end

	local cfg = GetCfg()

	if event == 'PLAYER_ENTERING_WORLD' then
		-- Not a Death Knight: these four end at the Blood gate below every time
		-- (a cast only reaches the /xerionbone log first), so they go for the
		-- session - the class never changes. Loading screen, spec and talent
		-- stay: the preview shows on any class and they restart it.
		if not IsDeathKnight() then
			evt:UnregisterEvent('UNIT_SPELLCAST_SUCCEEDED')
			evt:UnregisterEvent('UNIT_AURA')
			evt:UnregisterEvent('PLAYER_REGEN_DISABLED')
			evt:UnregisterEvent('PLAYER_REGEN_ENABLED')
		end
		HookViewers()
		C_Timer.After(0.5, Apply)
		C_Timer.After(3, function()
			if GetCfg().enable then HookViewers() Rescan() end
		end)
		return
	end

	if event == 'PLAYER_SPECIALIZATION_CHANGED' then
		ForgetOssuaryIdent()
		Clear()
		C_Timer.After(0.5, Apply)
		return
	end

	if event == 'UNIT_SPELLCAST_SUCCEEDED' and not secret(spellID) then
		LogCast(spellID,
			(not cfg.enable) and 'module off'
			or preview and 'preview on'
			or (not IsBlood()) and 'not Blood'
			or IsRefresher(spellID) and '|cff00ff00REFRESH|r'
			or 'not a refresher')
	end

	if not cfg.enable or preview or not IsBlood() then return end

	if event == 'UNIT_SPELLCAST_SUCCEEDED' then
		if not secret(spellID) then
			if IsRefresher(spellID) then Refresh() end
			ObserveCast(spellID)
		end

	elseif event == 'UNIT_AURA' then
		if expire > 0 then
			local _, moved = TryRealSync()
			if moved then Tick() end
		end
		if expire <= 0 and TryRealSync() then
			soundArmed = true
			SyncTicker()
		end

	else
		Tick()
	end
end)

local watchUntil, watchLast, watchTicker = 0, nil, nil

local function WatchSample()
	local f = ossuaryFrames[1]
	local shown, vis, alpha, act = '-', '-', '-', '-'
	if f then
		local ok1, v1 = pcall(f.IsShown, f);   shown = ok1 and tostring(v1) or 'err'
		local ok2, v2 = pcall(f.IsVisible, f); vis   = ok2 and tostring(v2) or 'err'
		local ok3, v3 = pcall(f.GetAlpha, f)
		alpha = ok3 and type(v3) == 'number' and ('%.2f'):format(v3) or 'err'
		if f.IsActive then
			local ok4, v4 = pcall(f.IsActive, f)
			act = (not ok4) and 'err' or (secret(v4) and 'SECRET' or tostring(v4))
		end
	end
	local low = StacksLow()
	local rem = expire > 0 and (expire - GetTime()) or 0
	local o, osrc = OssuaryUp()
	return ('bsIcons=%d bsUp=%s clock=%.0fs | ossFrames=%d shown=%s vis=%s a=%s isActive=%s ossUp=%s via=%s | low=%s glowing=%s')
		:format(#targets, tostring(AnyTargetActive()), rem,
			#ossuaryFrames, shown, vis, alpha, act,
			tostring(o), tostring(osrc), tostring(low), tostring(glowing))
end

local function WatchTick()
	local function p(...) print('|cffff7d0aXerionUI-BoneShield|r', ...) end
	if GetTime() > watchUntil then
		if watchTicker then watchTicker:Cancel() watchTicker = nil end
		p('|cff33ccffwatch finished.|r Paste the lines above.')
		p('   Reading them: ossFrames=0 means Ossuary is not on a CDM buff bar at all.')
		p('   via= says which source answered - isActive is the flag Blizzard itself')
		p('   uses, drawn is the icon being on screen, none means neither could be read.')
		p('   ossUp=nil means it stood down rather than guess. low=true is the warning,')
		p('   and glowing should follow it on the very next line.')
		return
	end
	local now = WatchSample()
	if now ~= watchLast then
		watchLast = now
		p(('[%4.1fs] '):format(watchUntil - GetTime()) .. now)
	end
end

function ns.BSForgetLearned()
	local cfg = GetCfg()
	local n = 0
	if type(cfg.learnedRefresh) == 'table' then
		for _ in pairs(cfg.learnedRefresh) do n = n + 1 end
	end
	cfg.learnedRefresh = {}
	wipe(misses)
	wipe(lastObserved)
	print('|cffff7d0aXerionUI-BoneShield|r forgot', n, 'learned refresh spell(s).',
		'The five built-in ones are untouched. Anything that really does grant a',
		'stack is learned again the next time you cast it where the timer is readable.')
end

function ns.BSWatch(seconds)
	local function p(...) print('|cffff7d0aXerionUI-BoneShield|r', ...) end
	seconds = seconds or 30
	HookViewers()
	Rescan()
	watchUntil = GetTime() + seconds
	watchLast = nil
	if watchTicker then watchTicker:Cancel() end
	watchTicker = C_Timer.NewTicker(0.1, WatchTick)
	p(('|cff33ccffWATCHING %ds.|r Fight something. Let Bone Shield fall under 5 stacks and'):format(seconds))
	p('   come back up. Every state change prints one line.')
	WatchTick()
end

_G.SLASH_XERIONBONE1 = '/xerionbone'
_G.SlashCmdList.XERIONBONE = function(msg)
	msg = type(msg) == 'string' and msg:lower() or ''
	if msg:find('watch') then
		ns.BSWatch(30)
		return
	end
	if msg:find('reset') or msg:find('forget') then
		if ns.BSForgetLearned then ns.BSForgetLearned() end
		return
	end
	if ns.BSTest then ns.BSTest() end
end
