local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('Shaman', hooksecurefunc, C_Timer)
local _G = _G

-- WHAT IT DOES
-- Elemental Blast leaves one of three buffs - Critical Strike, Haste or
-- Mastery - and the Cooldown Manager tracks each as a buff of its own. The
-- icons do not say which stat you got at a glance, so this puts a letter above
-- each one: C, H or M, with its own colour, size and height.
--
-- WHY IT ADDS NO ICONS
-- Buff Watch could show the three buffs, but as new icons beside the ones the
-- Cooldown Manager already draws. Here the letter hangs off the Cooldown
-- Manager's own icon frame (BuffIconCooldownViewer). EllesmereUI restyles
-- those same frames in place and anchors them into its bars rather than
-- drawing copies, so the letter follows the icon wherever either addon puts it
-- and shows and hides with it: nothing of ours decides when the buff is up.
--
-- WHICH ICON IS WHICH
-- The viewer hands its pooled frames a cooldownID in exactly one place, its
-- RefreshData (CooldownViewer.lua: layout changes, spec and talent swaps, edit
-- mode, a full aura update), so a hook there is the whole resync road. It runs
-- in the same frame as the hand-out, so a pooled frame that moves to another
-- buff never shows the old letter. The cooldownID and its cooldown info are
-- layout data and plain in combat; the frame's live spell ID is not (it reads
-- secret while the aura is up), which is why the match is made on the
-- cooldown info and never on the aura.
--
-- The frames come from the viewer's pool, not GetItemFrames(): that one lists
-- SHOWN frames only, and with "hide when inactive" a buff that is down is a
-- hidden frame - it would get its letter only at the next refresh, after it
-- popped. EllesmereUI walks the same pool (EllesmereUICdmBuffBars.lua).

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local hooksecurefunc = hooksecurefunc
local pairs, pcall, type, tostring = pairs, pcall, type, tostring
local tconcat = table.concat
local secret = ns.IsSecret

local CDV = _G.C_CooldownViewer
local GetInfo = CDV and CDV.GetCooldownViewerCooldownInfo
ns.hasElementalBlast = GetInfo and true or false
if not GetInfo then return end

local VIEWER = 'BuffIconCooldownViewer'
local WHITE = { 1, 1, 1, 1 }

-- The buff spell IDs as the Cooldown Manager lists them.
local LETTERS = {
	{ id = 118522, text = 'C', color = 'critColor' },
	{ id = 173183, text = 'H', color = 'hasteColor' },
	{ id = 173184, text = 'M', color = 'masteryColor' },
}

local DEFAULTS = {
	enable = true,
	size = 14,
	offsetY = 2,
	critColor = { 1, 1, 1, 1 },
	hasteColor = { 1, 1, 1, 1 },
	masteryColor = { 1, 1, 1, 1 },
}

local function GetCfg() return ns.ModuleCfg('elementalBlast', DEFAULTS) end
ns.SHMGetCfg = GetCfg

local function IsShaman() return ns.IsClass('SHAMAN') end

-- Secret first: even an equality test on a secret is an error.
local function Plain(v, want) return not secret(v) and v == want end

-- Which of the three buffs a cooldownID is: its own spell first, then its
-- linked spells. A cooldown whose linked list holds two of the three would be
-- one icon standing for several buffs, and the viewer's own answer there (the
-- aura's spell) is secret in combat - so it gets no letter rather than a
-- wrong one, and the second return says why for /xerioneb.
local function Identify(cdID)
	if secret(cdID) or cdID == nil then return nil end
	local ok, info = pcall(GetInfo, cdID)
	if not ok or type(info) ~= 'table' then return nil end
	for i = 1, #LETTERS do
		local id = LETTERS[i].id
		if Plain(info.spellID, id) or Plain(info.overrideSpellID, id)
			or Plain(info.overrideTooltipSpellID, id) then
			return LETTERS[i]
		end
	end
	local found
	local linked = info.linkedSpellIDs
	if type(linked) == 'table' then
		for j = 1, #linked do
			for i = 1, #LETTERS do
				if Plain(linked[j], LETTERS[i].id) then
					if found and found ~= LETTERS[i] then return nil, 'ambiguous' end
					found = LETTERS[i]
				end
			end
		end
	end
	return found
end

local function FrameLetter(f)
	if not f.GetCooldownID then return nil end
	local ok, id = pcall(f.GetCooldownID, f)
	if not ok then return nil end
	return Identify(id)
end

-- One label per pooled frame, made the first time that frame carries one of
-- the buffs and kept for good: the pool reuses its frames, so this never grows
-- past the few frames the viewer owns.
local recs = {}

-- The one look of a letter, shared by the real icons and the preview so the
-- preview cannot drift from what the settings do.
local function Style(fs, anchor, L, cfg)
	local c = cfg[L.color] or WHITE
	fs:SetFont(ns.GetFont(), cfg.size or 14, 'OUTLINE')
	fs:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
	fs:ClearAllPoints()
	fs:SetPoint('BOTTOM', anchor, 'TOP', 0, cfg.offsetY or 2)
	fs:SetText(L.text)
end

local function Paint(f, L, cfg)
	local rec = recs[f]
	if not rec then
		local holder = CreateFrame('Frame', nil, f)
		holder:SetAllPoints(f)
		rec = { holder = holder, fs = holder:CreateFontString(nil, 'OVERLAY') }
		recs[f] = rec
	end
	-- Above EllesmereUI's border (+13) and its text overlay (+23).
	local ok, lvl = pcall(f.GetFrameLevel, f)
	if ok and not secret(lvl) and lvl then rec.holder:SetFrameLevel(lvl + 30) end
	Style(rec.fs, rec.holder, L, cfg)
	rec.holder:Show()
	rec.want = true
end

local hooked

local function Sync()
	local cfg = GetCfg()
	for _, rec in pairs(recs) do rec.want = nil end
	if cfg.enable and IsShaman() then
		local viewer = _G[VIEWER]
		local pool = viewer and viewer.itemFramePool
		if pool and pool.EnumerateActive then
			for f in pool:EnumerateActive() do
				local L = FrameLetter(f)
				if L then Paint(f, L, cfg) end
			end
		elseif viewer and viewer.GetItemFrames then
			local ok, frames = pcall(viewer.GetItemFrames, viewer)
			if ok and type(frames) == 'table' then
				for i = 1, #frames do
					local L = FrameLetter(frames[i])
					if L then Paint(frames[i], L, cfg) end
				end
			end
		end
	end
	for _, rec in pairs(recs) do
		if not rec.want then rec.holder:Hide() end
	end
end

local function HookViewer()
	if hooked then return end
	local v = _G[VIEWER]
	if not (v and v.RefreshData) then return end
	hooked = true
	hooksecurefunc(v, 'RefreshData', Sync)
end

-- PREVIEW
-- Three Elemental Blast icons of our own, one per buff, lettered by Style like
-- the real ones, so the settings can be tuned without casting. The row sits
-- over the real buff icons: centred on the first EllesmereUI buff group (the
-- same lookup the other CDM-anchored modules use), else on Blizzard's buff
-- viewer, else below the middle of the screen. The real letter is a child of
-- the icon and grows with its scale, so the preview icons copy the size and
-- the effective scale of a real buff icon on screen; with none showing, the
-- EllesmereUI group's icon size, else 36. Shown whatever the class and the
-- Enable box say - it is there to look at.
local preview, pvRow
local AUTO_GROUP = {}

local function Positive(v) return not secret(v) and type(v) == 'number' and v > 0 end

-- width, height, effective scale, gap and the frame to centre on
local function PreviewLayout()
	local bar, bd
	if ns.CDMResolveGroup then bar, bd = ns.CDMResolveGroup(AUTO_GROUP) end
	local viewer = _G[VIEWER]
	local anchor = bar or (viewer and viewer:IsVisible() and viewer) or nil
	local gap = (bd and type(bd.spacing) == 'number' and bd.spacing) or 2
	local pool = viewer and viewer.itemFramePool
	if pool and pool.EnumerateActive then
		for f in pool:EnumerateActive() do
			if f:IsVisible() then
				local okS, w, h = pcall(f.GetSize, f)
				local okE, es = pcall(f.GetEffectiveScale, f)
				if okS and okE and Positive(w) and Positive(h) and Positive(es) then
					return w, h, es, gap, anchor
				end
			end
		end
	end
	local es = (anchor or _G.UIParent):GetEffectiveScale()
	local w = (bd and Positive(bd.iconSize) and bd.iconSize) or 36
	return w, w, es, gap, anchor
end

local function BuildPreview()
	pvRow = CreateFrame('Frame', 'XerionUIElementalBlastPreview', _G.UIParent)
	pvRow:SetFrameStrata('HIGH')
	pvRow.icons = {}
	for i = 1, #LETTERS do
		local b = CreateFrame('Frame', nil, pvRow)
		b.tex = ns.PixelBorderIcon(b)
		b.tex:SetTexture(ns.CdSpellTexture(LETTERS[i].id))
		b.fs = b:CreateFontString(nil, 'OVERLAY')
		pvRow.icons[i] = b
	end
end

local function RefreshPreview()
	if not preview then
		if pvRow then pvRow:Hide() end
		return
	end
	if not pvRow then BuildPreview() end
	local cfg = GetCfg()
	local w, h, es, gap, anchor = PreviewLayout()
	local ups = _G.UIParent:GetEffectiveScale()
	pvRow:SetScale((Positive(es) and Positive(ups)) and es / ups or 1)
	pvRow:SetSize(#LETTERS * w + (#LETTERS - 1) * gap, h)
	for i = 1, #LETTERS do
		local b = pvRow.icons[i]
		b:SetSize(w, h)
		b:ClearAllPoints()
		b:SetPoint('LEFT', pvRow, 'LEFT', (i - 1) * (w + gap), 0)
		b.tex:SetTexCoord(ns.IconCoords(w, h, 0.08))
		Style(b.fs, b, LETTERS[i], cfg)
	end
	pvRow:ClearAllPoints()
	if anchor then
		pvRow:SetPoint('CENTER', anchor, 'CENTER', 0, 0)
	else
		pvRow:SetPoint('CENTER', _G.UIParent, 'CENTER', 0, -150)
	end
	pvRow:Show()
end

ns.SHMIsPreview = function() return preview and true or false end
ns.SHMSetPreview = function(state)
	preview = state and true or false
	RefreshPreview()
end

local function Apply()
	if GetCfg().enable and IsShaman() then HookViewer() end
	Sync()
	RefreshPreview()
end
-- Coalesced: a dragged slider asks on every step.
ns.SHMApply = ns.Coalesce(Apply)

-- The first pass is ours: the viewer may have filled its frames before the hook
-- existed. Asked again a second later for a viewer that fills late. Anyone who
-- is not a shaman drops the events for the session - the class never changes.
local evt = CreateFrame('Frame')
evt:RegisterEvent('PLAYER_ENTERING_WORLD')
evt:RegisterUnitEvent('PLAYER_SPECIALIZATION_CHANGED', 'player')
evt:SetScript('OnEvent', function(self)
	if not IsShaman() then
		self:UnregisterAllEvents()
		return
	end
	Apply()
	C_Timer.After(1, Apply)
end)

local function Str(v)
	if secret(v) then return '<secret>' end
	return tostring(v)
end

_G.SLASH_XERIONEB1 = '/xerioneb'
_G.SlashCmdList.XERIONEB = function()
	local function p(...) print('|cffff7d0aXerionUI-ElementalBlast|r', ...) end
	local cfg = GetCfg()
	p('enable =', cfg.enable and 'on' or 'off', '| shaman =', IsShaman() and 'yes' or 'no',
		'| hooked =', hooked and 'yes' or 'no', '| preview =', preview and 'ON' or 'off')
	local viewer = _G[VIEWER]
	local pool = viewer and viewer.itemFramePool
	if not (pool and pool.EnumerateActive) then
		p('|cffff5555no ' .. VIEWER .. ' frame pool|r')
		return
	end
	local n = 0
	for f in pool:EnumerateActive() do
		n = n + 1
		-- No `a and b or nil` below: that tests b, and b may be secret.
		local cdID
		if f.GetCooldownID then
			local okID, id = pcall(f.GetCooldownID, f)
			if okID then cdID = id end
		end
		local sid, ovr, linked = nil, nil, {}
		if not secret(cdID) and cdID ~= nil then
			local ok, info = pcall(GetInfo, cdID)
			if ok and type(info) == 'table' then
				sid, ovr = info.spellID, info.overrideSpellID
				if type(info.linkedSpellIDs) == 'table' then
					for i = 1, #info.linkedSpellIDs do linked[#linked + 1] = Str(info.linkedSpellIDs[i]) end
				end
			end
		end
		local L, why = Identify(cdID)
		local rec = recs[f]
		p(('cd %s | spell %s | override %s | linked {%s} -> %s%s'):format(
			Str(cdID), Str(sid), Str(ovr),
			tconcat(linked, ','),
			L and L.text or (why or '-'),
			rec and rec.holder:IsShown() and ' (label on)' or ''))
	end
	if n == 0 then p('the buff viewer has no icons') end
end
