local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('EUI', hooksecurefunc, C_Timer)
local _G = _G

local EUF = _G.EllesmereUF
local EUI = _G.EllesmereUI

local function UnitFramesLoaded()
	if EUF and EUF.Tags and type(EUF.Tags.Methods) == 'table' then return true end
	if ns.IsAddOnLoaded('EllesmereUIUnitFrames') then return true end
	local Lite = EUI and EUI.Lite
	if Lite and Lite.GetAddon then
		local ok, obj = pcall(Lite.GetAddon, 'EllesmereUIUnitFrames', true)
		if ok and obj then return true end
	end
	return false
end

local hasEUI = (EUI ~= nil) and UnitFramesLoaded()

ns.hasEUI = hasEUI

ns.hasEUICore = (EUI ~= nil)

if not hasEUI then return end

local issecretvalue = issecretvalue
local UnitExists = UnitExists
local GetRaidTargetIndex = GetRaidTargetIndex
local SetRaidTargetIconTexture = SetRaidTargetIconTexture
local RAID_ICON_TEXTURE = [[Interface\TargetingFrame\UI-RaidTargetingIcons]]
local ipairs = ipairs
local pairs = pairs
local pcall = pcall
local wipe = wipe
local hooksecurefunc = hooksecurefunc
local CreateFrame = CreateFrame
local C_Timer = C_Timer

local FOCUS_MARK_DEFAULTS  = { enable = false, size = 40, x = -40, y = 0 }
local FOCUS_CASTBAR_BG_DEFAULTS = {
	enable = false,
	color = { 0.08, 0.08, 0.08 },
	alpha = 0.75,
}

local function GetFocusMarkCfg() return ns.ModuleCfg('euiFocusMark', FOCUS_MARK_DEFAULTS) end
local function GetFocusCastbarBgCfg() return ns.ModuleCfg('euiFocusCastbarBg', FOCUS_CASTBAR_BG_DEFAULTS) end

ns.EUIGetFocusMarkCfg = GetFocusMarkCfg
ns.EUIGetFocusCastbarBgCfg = GetFocusCastbarBgCfg

local UNIT_GLOBAL = {
	player = 'EllesmereUIUnitFrames_Player',
	focus  = 'EllesmereUIUnitFrames_Focus',
}
local function GetUnitFrame(unit)
	local g = UNIT_GLOBAL[unit]
	if g and _G[g] then return _G[g] end
	if EUF and EUF.objects then
		for _, obj in ipairs(EUF.objects) do
			if obj.unit == unit then return obj end
		end
	end
end

local focusMark, markCastbar
-- The requested bar is Mythic+ Tools' standalone focus cast bar, not
-- EllesmereUI UnitFrames' focus cast bar. The Mythic+ module keeps its bar
-- object private, so find its holder by its saved position/size and its
-- distinctive direct StatusBar child, then recolor the holder's bg region.
local function UpdateFocusCastbarBackground()
	local eui = _G.EllesmereUI
	local modules = eui and eui._ModuleNS
	local mod = modules and modules.EllesmereUIMythicTimer
	local db = _G._EMT_AceDB
	local prof = db and db.profile
	local tfb = prof and prof.tfb
	local focus = tfb and tfb.focus
	local cfg = GetFocusCastbarBgCfg()
	if not (mod and focus and focus.enabled == true and UIParent) then return end
	local pos = focus.pos
	local x = pos and pos.centerX or 0
	local y = pos and pos.centerY or -310
	local width, height = focus.width or 260, focus.height or 22
	local children = { UIParent:GetChildren() }
	for _, frame in ipairs(children) do
		if frame and frame.GetWidth and math.abs((frame:GetWidth() or 0) - width) < 0.1
			and math.abs((frame:GetHeight() or 0) - height) < 0.1 then
			local point, relative, relativePoint, fx, fy = frame:GetPoint(1)
			local isFocusPosition = point == 'CENTER' and relative == UIParent and relativePoint == 'CENTER'
				and math.abs((fx or 0) - x) < 0.1 and math.abs((fy or 0) - y) < 0.1
			if isFocusPosition then
				local hasStatusBar = false
				for _, child in ipairs({ frame:GetChildren() }) do
					if child.GetObjectType and child:GetObjectType() == 'StatusBar' then hasStatusBar = true; break end
				end
				if hasStatusBar then
					local bg = frame:GetRegions()
					if bg and bg.SetColorTexture then
						if cfg.enable then
							local c = cfg.color or FOCUS_CASTBAR_BG_DEFAULTS.color
							bg:SetColorTexture(c[1] or 0.08, c[2] or 0.08, c[3] or 0.08, cfg.alpha or 0.75)
						else
							bg:SetColorTexture(0, 0, 0, 0.45)
						end
					end
					return
				end
			end
		end
	end
end

local function HookMythicFocusBar()
	local eui = _G.EllesmereUI
	local modules = eui and eui._ModuleNS
	local mod = modules and modules.EllesmereUIMythicTimer
	if mod and type(mod.TFB_Refresh) == 'function' and not mod._XerionFocusBgHooked then
		mod._XerionFocusBgHooked = true
		hooksecurefunc(mod, 'TFB_Refresh', function()
			C_Timer.After(0, UpdateFocusCastbarBackground)
		end)
	end
	UpdateFocusCastbarBackground()
end
local focusBarHookFrame = CreateFrame('Frame')
focusBarHookFrame:RegisterEvent('ADDON_LOADED')
focusBarHookFrame:SetScript('OnEvent', function(_, _, addon)
	if addon == 'EllesmereUIMythicTimer' then HookMythicFocusBar() end
end)
C_Timer.After(1, HookMythicFocusBar)

local function UpdateFocusMark()
	local ff = GetUnitFrame('focus')
	local cb = ff and ff.Castbar
	if not cb then return end

	if not focusMark or markCastbar ~= cb then
		markCastbar = cb
		focusMark = cb:CreateTexture(nil, 'OVERLAY', nil, 7)
		focusMark:SetTexture(RAID_ICON_TEXTURE)
		focusMark:Hide()
	end

	local cfg = GetFocusMarkCfg()
	if not cfg.enable or not UnitExists('focus') then focusMark:Hide() return end

	local idx = GetRaidTargetIndex('focus')
	if idx then
		local sz = cfg.size or 20
		focusMark:SetSize(sz, sz)
		focusMark:ClearAllPoints()
		focusMark:SetPoint('RIGHT', cb, 'LEFT', (cfg.x or 2), cfg.y or 0)
		SetRaidTargetIconTexture(focusMark, idx)
		focusMark:Show()
	else
		focusMark:Hide()
	end
end
-- The events only matter while the mark is on; ApplyAllSettings runs this at
-- PLAYER_LOGIN (before the first PLAYER_ENTERING_WORLD) and on every change.
local markFrame = CreateFrame('Frame')
markFrame:SetScript('OnEvent', function()
	UpdateFocusMark()
	C_Timer.After(0, UpdateFocusMark)
end)
ns.EUIApplyFocusMark = function()
	local wantMark = GetFocusMarkCfg().enable
	local wantBackground = GetFocusCastbarBgCfg().enable
	if wantMark or wantBackground then
		markFrame:RegisterEvent('RAID_TARGET_UPDATE')
		markFrame:RegisterEvent('PLAYER_FOCUS_CHANGED')
		markFrame:RegisterEvent('PLAYER_ENTERING_WORLD')
		markFrame:RegisterEvent('ADDON_LOADED')
		if wantMark then
			markFrame:RegisterUnitEvent('UNIT_SPELLCAST_START', 'focus')
			markFrame:RegisterUnitEvent('UNIT_SPELLCAST_CHANNEL_START', 'focus')
		else
			markFrame:UnregisterEvent('UNIT_SPELLCAST_START')
			markFrame:UnregisterEvent('UNIT_SPELLCAST_CHANNEL_START')
		end
	else
		markFrame:UnregisterAllEvents()
	end
	UpdateFocusMark()
	C_Timer.After(0, UpdateFocusMark)
end
ns.EUIApplyFocusCastbar = function()
	HookMythicFocusBar()
	C_Timer.After(0, UpdateFocusCastbarBackground)
end

local FOCUS_RANGE_DEFAULTS = { enable = false, alpha = 0.5 }
local function GetFocusRangeCfg() return ns.ModuleCfg('euiFocusRange', FOCUS_RANGE_DEFAULTS) end
ns.EUIGetFocusRangeCfg = GetFocusRangeCfg

local FADE_RANGE = 40
local MAX_PROBES = 4
local RANGE_ITEMS_40 = { 28767, 18640 }

local RANGE_HEAL = {
	DRUID   = 8936,
	EVOKER  = 361469,
	MONK    = 116670,
	PALADIN = 19750,
	PRIEST  = 2061,
	SHAMAN  = 8004,
}

local frExact, frNear = {}, {}
local frHelp
local frDirty = true

local function FRResolveSpells()
	frDirty = false
	wipe(frExact)
	wipe(frNear)
	frHelp = nil
	local CSB, CS, E = _G.C_SpellBook, _G.C_Spell, _G.Enum
	local bank = E and E.SpellBookSpellBank and E.SpellBookSpellBank.Player
	local spellType = E and E.SpellBookItemType and E.SpellBookItemType.Spell
	if CSB and CSB.GetNumSpellBookSkillLines and CSB.GetSpellBookSkillLineInfo
		and CSB.GetSpellBookItemType and CS and CS.GetSpellInfo and bank and spellType then
		local nearDist
		pcall(function()
			for li = 1, CSB.GetNumSpellBookSkillLines() do
				local line = CSB.GetSpellBookSkillLineInfo(li)
				if line and not (line.offSpecID and line.offSpecID ~= 0) and not line.shouldHide
					and line.itemIndexOffset and line.numSpellBookItems then
					for si = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
						local itemType, actionID, spellID = CSB.GetSpellBookItemType(si, bank)
						local sid = spellID or actionID
						if itemType == spellType and sid
							and not (CS.IsSpellPassive and CS.IsSpellPassive(sid))
							and (not CS.IsSpellHarmful or CS.IsSpellHarmful(sid)) then
							local info = CS.GetSpellInfo(sid)
							local maxR = info and info.maxRange
							if maxR and maxR > 0 and (info.minRange or 0) == 0 then
								if maxR == FADE_RANGE then
									if #frExact < MAX_PROBES then frExact[#frExact + 1] = sid end
								else
									local d = math.abs(maxR - FADE_RANGE)
									if not nearDist or d < nearDist then
										nearDist = d
										wipe(frNear)
									end
									if d == nearDist and #frNear < MAX_PROBES then frNear[#frNear + 1] = sid end
								end
							end
						end
					end
				end
			end
		end)
	end
	local okC, _, pClass = pcall(_G.UnitClass, 'player')
	if not okC or (issecretvalue and issecretvalue(pClass)) then return end
	local spec = _G.GetSpecialization and _G.GetSpecialization()
	local role = spec and _G.GetSpecializationRole and _G.GetSpecializationRole(spec)
	if role == 'HEALER' then frHelp = RANGE_HEAL[pClass] end
end

local function FRProbeSpells(ff, list, oor)
	local CS = _G.C_Spell
	if not (CS and CS.IsSpellInRange) then return false end
	local FindOvr = _G.C_SpellBook and _G.C_SpellBook.FindSpellOverrideByID
	for i = 1, #list do
		local sid = list[i]
		local live = (FindOvr and FindOvr(sid)) or sid
		local inRange = CS.IsSpellInRange(live, 'focus')
		if (issecretvalue and issecretvalue(inRange)) or inRange ~= nil then
			ff:SetAlphaFromBoolean(inRange, 1, oor)
			return true
		end
	end
	return false
end

local function FRProbeItems(ff, oor)
	local CI = _G.C_Item
	if not (CI and CI.IsItemInRange) then return false end
	for i = 1, #RANGE_ITEMS_40 do
		local inRange = CI.IsItemInRange(RANGE_ITEMS_40[i], 'focus')
		if (issecretvalue and issecretvalue(inRange)) or inRange ~= nil then
			ff:SetAlphaFromBoolean(inRange, 1, oor)
			return true
		end
	end
	return false
end

-- EllesmereUI sets the focus frame's alpha itself (Fade Out of Combat, the
-- visibility options), so with the feature off this leaves it alone. The one
-- write is the 1 on the way from on to off, so turning the feature off does
-- not leave the frame dimmed; frOwned says we have been writing it.
local frOwned = false
local function FocusRangeTick()
	local ff = GetUnitFrame('focus')
	if not ff then return end
	local cfg = GetFocusRangeCfg()
	if not cfg.enable then
		if frOwned then
			frOwned = false
			ff:SetAlpha(1)
		end
		return
	end
	frOwned = true
	if not UnitExists('focus') or not ff.SetAlphaFromBoolean then
		ff:SetAlpha(1)
		return
	end
	if frDirty then FRResolveSpells() end
	local oor = cfg.alpha or 0.5
	local canAtk = _G.UnitCanAttack('player', 'focus')
	local atkSecret = (issecretvalue and issecretvalue(canAtk)) and true or false
	if atkSecret then canAtk = true end
	if canAtk then
		if FRProbeSpells(ff, frExact, oor) then return end
		if not atkSecret and FRProbeItems(ff, oor) then return end
		if FRProbeSpells(ff, frNear, oor) then return end
		ff:SetAlpha(1)
	elseif frHelp and _G.C_Spell and _G.C_Spell.IsSpellInRange then
		local inRange = _G.C_Spell.IsSpellInRange(frHelp, 'focus')
		if (issecretvalue and issecretvalue(inRange)) or inRange ~= nil then
			ff:SetAlphaFromBoolean(inRange, 1, oor)
		else
			ff:SetAlpha(1)
		end
	elseif _G.UnitInRange then
		local inR, checked = _G.UnitInRange('focus')
		local secretIn = issecretvalue and issecretvalue(inR)
		local secretChk = issecretvalue and issecretvalue(checked)
		if not secretChk and not secretIn and checked then
			ff:SetAlphaFromBoolean(inR, 1, oor)
		else
			ff:SetAlpha(1)
		end
	else
		ff:SetAlpha(1)
	end
end

local frTicker
local function FRUpdateTicker()
	local cfg = GetFocusRangeCfg()
	local want = (cfg.enable and UnitExists('focus')) and true or false
	if want and not frTicker then
		frTicker = C_Timer.NewTicker(0.4, FocusRangeTick)
	elseif not want and frTicker then
		frTicker:Cancel()
		frTicker = nil
	end
	FocusRangeTick()
end
ns.EUIApplyFocusRange = function()
	frDirty = true
	FRUpdateTicker()
end

-- A spec or talent change is a burst of SPELLS_CHANGED / TRAIT_CONFIG_UPDATED.
-- Each one only marks the spell list dirty; the one update on the next frame
-- walks the spellbook once for all of them.
local QueueFRUpdate = ns.Coalesce(FRUpdateTicker)
local frEvt = CreateFrame('Frame')
frEvt:RegisterEvent('PLAYER_FOCUS_CHANGED')
frEvt:RegisterEvent('PLAYER_ENTERING_WORLD')
frEvt:RegisterEvent('SPELLS_CHANGED')
frEvt:RegisterEvent('TRAIT_CONFIG_UPDATED')
frEvt:RegisterUnitEvent('PLAYER_SPECIALIZATION_CHANGED', 'player')
frEvt:SetScript('OnEvent', function(_, event)
	if event == 'PLAYER_FOCUS_CHANGED' then
		FRUpdateTicker()
	else
		frDirty = true
		QueueFRUpdate()
	end
end)

local DEBUFF_COLOR_DEFAULTS = { enable = false, thick = false, aboveSwipe = false }
local function GetDebuffColorCfg()
	return ns.ModuleCfg('euiDebuffColors', DEBUFF_COLOR_DEFAULTS)
end
ns.EUIGetDebuffColorCfg = GetDebuffColorCfg

local function DispelTypeOf(btn)
	local info = btn.buttonInfo
	local dt = type(info) == 'table' and info.debuffType or nil
	if not (issecretvalue and issecretvalue(dt)) then
		if dt ~= nil then return dt end
		if type(info) == 'table' then return nil end
	end
	local border = btn.DebuffBorder
	local atlas = border and border.GetAtlas and border:GetAtlas()
	if atlas and not (issecretvalue and issecretvalue(atlas)) then
		local t = atlas:match('ui%-debuff%-border%-(%a+)%-')
		if t == 'default' then return nil end
		if t then return t:sub(1, 1):upper() .. t:sub(2) end
	end
	return false
end

local FALLBACK_COLORS = {
	Magic   = { 0.20, 0.60, 1.00 },
	Curse   = { 0.60, 0.00, 1.00 },
	Disease = { 0.60, 0.40, 0.00 },
	Poison  = { 0.00, 0.60, 0.00 },
	Bleed   = { 0.80, 0.00, 0.00 },
	None    = { 0.80, 0.00, 0.00 },
}
local function DispelColor(dt)
	local AU = _G.AuraUtil
	if AU and AU.GetAuraBorderColor then
		local ok, c = pcall(AU.GetAuraBorderColor, dt)
		if ok and c and c.GetRGB then return c:GetRGB() end
	end
	local f = FALLBACK_COLORS[dt] or FALLBACK_COLORS.None
	return f[1], f[2], f[3]
end

local function OwnEdges(btn)
	local e = btn.__kiraDCEdges
	if e then return e end
	local anchor = btn.Icon or btn
	local function tex() return btn:CreateTexture(nil, 'OVERLAY', nil, 7) end
	e = { top = tex(), bottom = tex(), left = tex(), right = tex() }
	e.top:SetPoint('TOPLEFT', anchor, 'TOPLEFT', 0, 0)
	e.top:SetPoint('TOPRIGHT', anchor, 'TOPRIGHT', 0, 0)
	e.top:SetHeight(1)
	e.bottom:SetPoint('BOTTOMLEFT', anchor, 'BOTTOMLEFT', 0, 0)
	e.bottom:SetPoint('BOTTOMRIGHT', anchor, 'BOTTOMRIGHT', 0, 0)
	e.bottom:SetHeight(1)
	e.left:SetPoint('TOPLEFT', anchor, 'TOPLEFT', 0, 0)
	e.left:SetPoint('BOTTOMLEFT', anchor, 'BOTTOMLEFT', 0, 0)
	e.left:SetWidth(1)
	e.right:SetPoint('TOPRIGHT', anchor, 'TOPRIGHT', 0, 0)
	e.right:SetPoint('BOTTOMRIGHT', anchor, 'BOTTOMRIGHT', 0, 0)
	e.right:SetWidth(1)
	btn.__kiraDCEdges = e
	return e
end

local function ApplyDebuffColors()
	local cfg = GetDebuffColorCfg()
	local DF = _G.DebuffFrame
	if not (DF and DF.auraFrames) then return end
	for _, btn in pairs(DF.auraFrames) do
		if btn and btn.Icon and not btn.isAuraAnchor then
			if not cfg.enable then
				if btn.__kiraDCEdges then
					for _, t in pairs(btn.__kiraDCEdges) do t:Hide() end
				end
			else
				local dt = DispelTypeOf(btn)
				if dt then
					local r, g, b = DispelColor(dt)
					local getFFD = _G.EllesmereUI and _G.EllesmereUI._GetFFD
					local ffd = getFFD and getFFD(btn)
					local edges = ffd and ffd._paEdges or OwnEdges(btn)
					for _, t in pairs(edges) do
						t:SetColorTexture(r, g, b, 1)
						t:Show()
					end
				elseif dt == nil and btn.__kiraDCEdges then
					-- A pooled button now holding a debuff without a dispel type
					-- looks like one that never had a colour: no edges. false is
					-- "could not read it", which keeps what is there.
					for _, t in pairs(btn.__kiraDCEdges) do t:Hide() end
				end
			end
		end
	end
end
local tbCurve
local function TypeBorderCurve()
	if tbCurve then return tbCurve end
	local CU, En, CC = _G.C_CurveUtil, _G.Enum, _G.CreateColor
	if not (CU and CU.CreateColorCurve and En and En.LuaCurveType and CC) then return nil end
	local c = CU.CreateColorCurve()
	c:SetType(En.LuaCurveType.Step)
	c:AddPoint(0,  CC(0.00, 0.00, 0.00, 0))
	c:AddPoint(1,  CC(0.20, 0.60, 1.00, 1))
	c:AddPoint(2,  CC(0.60, 0.00, 1.00, 1))
	c:AddPoint(3,  CC(0.60, 0.40, 0.00, 1))
	c:AddPoint(4,  CC(0.00, 0.60, 0.00, 1))
	c:AddPoint(5,  CC(0.00, 0.00, 0.00, 0))
	c:AddPoint(11, CC(0.80, 0.00, 0.00, 1))
	tbCurve = c
	return c
end

local function ConvertUFButton(btn)
	if btn.__kiraTBDone or not btn.Overlay then return end
	btn.__kiraTBDone = true
	local ov = btn.Overlay
	ov:SetTexture(nil)
	local holder = CreateFrame('Frame', nil, btn)
	holder:SetAllPoints(btn)
	holder:SetFrameLevel((btn.Cooldown and btn.Cooldown:GetFrameLevel() or btn:GetFrameLevel()) + 3)
	btn.__kiraTBHolder = holder
	local function tex()
		local t = holder:CreateTexture(nil, 'OVERLAY', nil, 7)
		t:SetColorTexture(1, 1, 1, 1)
		t:Hide()
		return t
	end
	local e = { top = tex(), bottom = tex(), left = tex(), right = tex() }
	e.top:SetPoint('TOPLEFT', btn, 'TOPLEFT', 0, 0)
	e.top:SetPoint('TOPRIGHT', btn, 'TOPRIGHT', 0, 0)
	e.top:SetHeight(1)
	e.bottom:SetPoint('BOTTOMLEFT', btn, 'BOTTOMLEFT', 0, 0)
	e.bottom:SetPoint('BOTTOMRIGHT', btn, 'BOTTOMRIGHT', 0, 0)
	e.bottom:SetHeight(1)
	e.left:SetPoint('TOPLEFT', btn, 'TOPLEFT', 0, 0)
	e.left:SetPoint('BOTTOMLEFT', btn, 'BOTTOMLEFT', 0, 0)
	e.left:SetWidth(1)
	e.right:SetPoint('TOPRIGHT', btn, 'TOPRIGHT', 0, 0)
	e.right:SetPoint('BOTTOMRIGHT', btn, 'BOTTOMRIGHT', 0, 0)
	e.right:SetWidth(1)
	btn.__kiraTBEdges = e

	hooksecurefunc(ov, 'SetVertexColor', function(_, r, g, b, a)
		e.top:SetVertexColor(r, g, b, a)
		e.bottom:SetVertexColor(r, g, b, a)
		e.left:SetVertexColor(r, g, b, a)
		e.right:SetVertexColor(r, g, b, a)
	end)
	hooksecurefunc(ov, 'Show', function()
		e.top:Show() e.bottom:Show() e.left:Show() e.right:Show()
	end)
	hooksecurefunc(ov, 'Hide', function()
		e.top:Hide() e.bottom:Hide() e.left:Hide() e.right:Hide()
	end)
end

local function PlayerDebuffsElement()
	local pf = GetUnitFrame('player')
	local el = pf and pf.Debuffs
	if el then return el end
	if EUF and EUF.objects then
		for _, obj in ipairs(EUF.objects) do
			if obj.unit == 'player' and obj.Debuffs then return obj.Debuffs end
		end
	end
end

local function ApplyUnitframeDebuffColors()
	local cfg = GetDebuffColorCfg()
	local el = PlayerDebuffsElement()
	if not el then return end
	el.showDebuffType = (cfg.enable and true) or nil
	local curve = TypeBorderCurve()
	if curve then el.dispelColorCurve = curve end
	for i = 1, #el do
		local b = el[i]
		if b then ConvertUFButton(b) end
	end
	if not el.__kiraTBPostHook then
		el.__kiraTBPostHook = true
		local orig = el.PostCreateButton
		el.PostCreateButton = function(self, button, ...)
			if orig then orig(self, button, ...) end
			ConvertUFButton(button)
		end
	end
	if el.ForceUpdate then pcall(el.ForceUpdate, el) end
	for i = 1, #el do
		local b = el[i]
		if b then
			if not cfg.enable and b.__kiraTBEdges then
				for _, t in pairs(b.__kiraTBEdges) do t:Hide() end
			end
		end
	end
end

local KV_BORDER = 'Interface\\AddOns\\XerionUI-Plugin\\Media\\KiraSquareBorder.tga'
local KV_BORDER_THICK = 'Interface\\AddOns\\XerionUI-Plugin\\Media\\KiraSquareBorderThick.tga'

local KIRA_STYLE_KEYS = { ['uf:player:HARMFUL'] = true }

local function GetAuraKit()
	local E = _G.EllesmereUI
	return E and E.AuraKit
end

local kiraTBButtons = setmetatable({}, { __mode = 'k' })

local function ChildrenOf(f) return { f:GetChildren() } end

local function FindCooldown(button)
	local cd = button.Cooldown
	if type(cd) == 'table' and cd.GetFrameLevel then return cd end
	local ok, kids = pcall(ChildrenOf, button)
	if not ok then return nil end
	for _, child in ipairs(kids) do
		if child and child.GetObjectType and child:GetObjectType() == 'Cooldown' then
			return child
		end
	end
	return nil
end

local function BorderHost(button)
	local host = button.__kiraCBHost
	if not host then
		host = CreateFrame('Frame', nil, button)
		host:SetAllPoints(button)
		button.__kiraCBHost = host
	end
	local cd = FindCooldown(button)
	local base = (cd and cd.GetFrameLevel and cd:GetFrameLevel()) or button:GetFrameLevel()
	if host:GetFrameLevel() ~= base + 1 then host:SetFrameLevel(base + 1) end
	return host
end

local function PushBorderCfg(button)
	local tex = button.__kiraCBBorder
	if not tex then return end
	local cfg = GetDebuffColorCfg()
	tex:SetTexture((cfg.thick and KV_BORDER_THICK) or KV_BORDER)
	tex:SetAlpha(cfg.enable and 1 or 0)

	local want = cfg.aboveSwipe and true or false
	local parent = want and BorderHost(button) or button
	if want ~= (button.__kiraCBAbove or false) then
		local ok = pcall(function()
			tex:SetParent(parent)
			tex:SetDrawLayer('OVERLAY', 7)
			tex:ClearAllPoints()
			tex:SetAllPoints(button)
		end)
		if ok then
			button.__kiraCBAbove = want
			button.__kiraCBAboveFailed = nil
		elseif want then
			button.__kiraCBAboveFailed = true
		end
	end
end

local function RegisterKiraBorder(button)
	if not button.SetAuraBorder or button.__kiraCBActive then return end
	local tex = button.__kiraCBBorder
	if not tex then
		tex = button:CreateTexture(nil, 'OVERLAY', nil, 7)
		button.__kiraCBBorder = tex
	end
	tex:SetAllPoints(button)
	local ABS = _G.AuraButtonBorderStyle
	local ok, err = pcall(button.SetAuraBorder, button, tex, {
		style = (ABS and ABS.Color) or 1,
		showIcon = false,
		showWhenHarmful = true,
		showWhenHelpful = false,
	})
	button.__kiraCBActive = ok or nil
	if not ok then _G.__kiraTBLastErr = tostring(err) end
	kiraTBButtons[button] = true
	PushBorderCfg(button)
end

local function InstallInitializerHook()
	local AK = GetAuraKit()
	if not AK or not AK.MakeInitializer then return false end
	if AK.__kiraTBWrapped then return true end
	local orig = AK.MakeInitializer
	AK.MakeInitializer = function(styleKey, extra)
		local init = orig(styleKey, extra)
		if not KIRA_STYLE_KEYS[styleKey] then return init end
		return function(button)
			init(button)
			pcall(RegisterKiraBorder, button)
		end
	end
	AK.__kiraTBWrapped = true
	return true
end
InstallInitializerHook()

local function ApplyContainerDebuffColors()
	InstallInitializerHook()
	for button in pairs(kiraTBButtons) do pcall(PushBorderCfg, button) end
end

C_Timer.NewTicker(2, function(t)
	if InstallInitializerHook() then t:Cancel() end
end)

local TB_PREVIEW_TYPES = {
	{ 'Magic',   'ui-debuff-border-magic-noicon' },
	{ 'Curse',   'ui-debuff-border-curse-noicon' },
	{ 'Disease', 'ui-debuff-border-disease-noicon' },
	{ 'Poison',  'ui-debuff-border-poison-noicon' },
	{ 'Bleed',   'ui-debuff-border-bleed-noicon' },
}
local TB_PREVIEW_ICON = 134400
local tbPreview
local tbPreviewActive = false
local tbHintOnly = false
local EDIT_MODE_SAMPLE_DEBUFFS = 4

local function EUIPlayerAuraSettings()
	local root = _G.EllesmereUIDB
	local profiles = root and root.profiles
	if not profiles then return nil end
	local pdata = profiles[root.activeProfile or 'Default']
	local addons = pdata and pdata.addons
	local uf = addons and addons.EllesmereUIUnitFrames
	return uf and uf.player
end

local EUI_ANCHOR_IA = {
	topleft = 'BOTTOMLEFT', topright = 'BOTTOMRIGHT',
	bottomleft = 'TOPLEFT', bottomright = 'TOPRIGHT',
	left = 'RIGHT', right = 'LEFT',
}
local EUI_ANCHOR_FP = {
	topleft = { 'TOPLEFT', 0, 1 }, topright = { 'TOPRIGHT', 0, 1 },
	bottomleft = { 'BOTTOMLEFT', 0, -1 }, bottomright = { 'BOTTOMRIGHT', 0, -1 },
	left = { 'LEFT', -1, 0 }, right = { 'RIGHT', 1, 0 },
}
local EUI_AUTO_GROWTH = {
	topleft = { 'RIGHT', 'UP' }, topright = { 'LEFT', 'UP' },
	bottomleft = { 'RIGHT', 'DOWN' }, bottomright = { 'LEFT', 'DOWN' },
	left = { 'LEFT', 'DOWN' }, right = { 'RIGHT', 'DOWN' },
}
local EUI_EXPLICIT_GROWTH = {
	right = { 'RIGHT', 'UP' }, left = { 'LEFT', 'UP' },
	up = { 'RIGHT', 'UP' }, down = { 'RIGHT', 'DOWN' },
}
local function EUIResolveDebuffLayout(anchor, growth)
	if not anchor or anchor == 'none' then anchor = 'topright' end
	local ia = EUI_ANCHOR_IA[anchor] or 'BOTTOMLEFT'
	local fp = EUI_ANCHOR_FP[anchor] or EUI_ANCHOR_FP.topleft
	local g
	if growth and growth ~= 'auto' then g = EUI_EXPLICIT_GROWTH[growth] end
	g = g or EUI_AUTO_GROWTH[anchor] or EUI_AUTO_GROWTH.topleft
	return ia, fp[1], fp[2], fp[3], g[1], g[2]
end

local function PlayerDebuffAnchor()
	local pf = GetUnitFrame('player')
	if pf then
		for _, c in ipairs({ pf:GetChildren() }) do
			if c.AddAuraSlot and c.GetUnit and c.UpdateAllAuras then return c end
		end
	end
	return PlayerDebuffsElement() or pf
end

local function LiveDebuffMetrics(anchor)
	local s = EUIPlayerAuraSettings()
	local w = s and s.debuffSize
	if not (type(w) == 'number' and w > 4) then
		w = nil
		if anchor and anchor.GetChildren then
			for _, btn in ipairs({ anchor:GetChildren() }) do
				local ok, bw = pcall(btn.GetWidth, btn)
				if ok and type(bw) == 'number' and bw > 4 then w = bw break end
			end
		end
	end
	w = math.floor((w or 32) + 0.5)
	local h = w
	if s and s.debuffCropIcons then h = math.floor(w * 0.80 + 0.5) end
	return w, h,
		(s and s.debuffSpacingX) or 1,
		(s and s.debuffSpacingY) or 1,
		(s and s.debuffAnchor) or 'topleft',
		(s and s.debuffGrowth) or 'auto',
		s and s.debuffMaxPerRow,
		(s and s.debuffOffsetX) or 0,
		(s and s.debuffOffsetY) or 0
end

local function EnsureTBPreview()
	if tbPreview then return tbPreview end
	local f = CreateFrame('Frame', 'XerionUITBPreview', _G.UIParent)
	f:SetFrameStrata('MEDIUM')
	f:SetSize(1, 1)
	f:Hide()
	local buttons = {}
	for i, info in ipairs(TB_PREVIEW_TYPES) do
		local b = CreateFrame('Frame', nil, f)
		b.Icon = b:CreateTexture(nil, 'ARTWORK')
		b.Icon:SetAllPoints()
		b.Icon:SetTexture(TB_PREVIEW_ICON)
		b.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		b.border = b:CreateTexture(nil, 'OVERLAY', nil, 7)
		b.label = b:CreateFontString(nil, 'OVERLAY')
		b.label:SetFont(ns.GetFont(), 10, 'OUTLINE')
		b.label:SetPoint('TOP', b, 'BOTTOM', 0, -3)
		b.label:SetText(info[1])
		local r, g, bl = DispelColor(info[1])
		b.label:SetTextColor(r, g, bl)
		buttons[i] = b
	end
	f.hint = f:CreateFontString(nil, 'OVERLAY')
	f.hint:SetFont(ns.GetFont(), 11, 'OUTLINE')
	f.hint:SetJustifyH('CENTER')
	f.hint:SetText('To move these:  |cffffd200/eui|r  >  Unit Frames  >  Buffs and Debuffs')
	f.hint:SetTextColor(0.82, 0.82, 0.82)

	tbPreview = { frame = f, buttons = buttons }
	return tbPreview
end

local function StyleTBPreview()
	if not (tbPreview and (tbPreviewActive or tbHintOnly)) then return end
	local cfg = GetDebuffColorCfg()
	local liveAnchor = PlayerDebuffAnchor()
	local pf = GetUnitFrame('player')
	local w, h, spX, spY, anchorSet, growth, maxPerRow, offX, offY = LiveDebuffMetrics(liveAnchor)
	local ia, fpPoint, ox, oy, gX, gY = EUIResolveDebuffLayout(anchorSet, growth)
	local s = EUIPlayerAuraSettings()

	local n = #tbPreview.buttons
	if not tbPreviewActive then
		local cap = s and s.maxDebuffs
		n = EDIT_MODE_SAMPLE_DEBUFFS
		if type(cap) == 'number' and cap >= 0 and cap < n then n = cap end
		if not (pf and cfg.enable) or (s and s.debuffAnchor == 'none') then n = 0 end
		tbPreview.frame:SetShown(n > 0)
		if n == 0 then return end
	end
	local cols = n
	if maxPerRow and maxPerRow >= 1 and maxPerRow < n then
		cols = maxPerRow
	elseif growth == 'up' or growth == 'down' then
		cols = 1
	end
	local rows = math.ceil(n / cols)

	local dx = (gX == 'LEFT') and -(w + spX) or (w + spX)
	local dy = (gY == 'DOWN') and -(h + spY) or (h + spY)

	local fW = cols * w + (cols - 1) * spX
	local fH = rows * h + (rows - 1) * spY

	local cbOff = 0
	if s and s.showPlayerCastbar
		and (anchorSet == 'bottomleft' or anchorSet == 'bottomright'
			or anchorSet == 'left' or anchorSet == 'right') then
		local cbH = s.playerCastbarHeight
		if not cbH or cbH <= 0 then cbH = 14 end
		cbOff = -cbH
	end

	local f = tbPreview.frame
	f:SetSize(fW, fH)
	f:ClearAllPoints()

	-- The hint goes UNDER the icons: the edit mode overlay puts its own name
	-- above this frame. With the preview icons up, each one hangs its type
	-- name (Bleed, Poison...) 3px below itself, so the hint drops past the
	-- tallest of those names - measured, because the font differs per client.
	if f.hint then
		local drop = 4
		if tbPreviewActive then
			local lh = 0
			for _, b in ipairs(tbPreview.buttons) do
				local sh = b.label:GetStringHeight()
				if type(sh) == 'number' and sh > lh then lh = sh end
			end
			if lh <= 0 then lh = 10 end
			drop = drop + 3 + math.ceil(lh)
		end
		f.hint:ClearAllPoints()
		f.hint:SetPoint('TOP', f, 'BOTTOM', 0, -drop)
	end

	if pf then
		f:SetPoint(ia, pf, fpPoint, ox + offX, oy + cbOff + offY)
	else
		f:SetPoint('CENTER', _G.UIParent, 'CENTER', 0, 120)
	end

	if not tbPreviewActive then
		for _, b in ipairs(tbPreview.buttons) do b:Hide() end
		return
	end

	for i, b in ipairs(tbPreview.buttons) do
		local idx = i - 1
		local col = idx % cols
		local row = math.floor(idx / cols)
		b:SetSize(w, h)
		b:ClearAllPoints()
		b:SetPoint(ia, f, ia, col * dx, row * dy)
		b.border:ClearAllPoints()
		b.border:SetPoint('TOPLEFT', b, 'TOPLEFT', 0, 0)
		b.border:SetPoint('BOTTOMRIGHT', b, 'BOTTOMRIGHT', 0, 0)
		b.border:SetTexture(cfg.thick and KV_BORDER_THICK or KV_BORDER)
		local r, g, bl = DispelColor(TB_PREVIEW_TYPES[i][1])
		b.border:SetVertexColor(r, g, bl, 1)
		b.border:Show()
		b:Show()
	end
end

ns.EUITBIsPreview = function() return tbPreviewActive end
-- One frame serves both the settings preview and the Blizzard edit mode hint;
-- either flag keeps it up, and the preview is the one that forces it shown.
local function SyncTBPreview()
	if tbPreviewActive or tbHintOnly then
		EnsureTBPreview()
		StyleTBPreview()
		if tbPreviewActive then tbPreview.frame:Show() end
	elseif tbPreview then
		tbPreview.frame:Hide()
	end
end

ns.EUITBSetPreview = function(state)
	tbPreviewActive = state and true or false
	SyncTBPreview()
end

local function SetTBHintOnly(state)
	tbHintOnly = state and true or false
	SyncTBPreview()
end

if _G.EventRegistry and _G.EventRegistry.RegisterCallback then
	local owner = {}
	_G.EventRegistry:RegisterCallback('EditMode.Enter', function()
		-- The debuff colour ticker restyles the hint from here on; with the
		-- colours off it shows no icons at all.
		SetTBHintOnly(true)
	end, owner)
	_G.EventRegistry:RegisterCallback('EditMode.Exit', function()
		SetTBHintOnly(false)
	end, owner)
end

ns.EUIApplyDebuffColors = function()
	ApplyDebuffColors()
	ApplyUnitframeDebuffColors()
	ApplyContainerDebuffColors()
	StyleTBPreview()
	if ns.EUISyncDebuffColorTicker then ns.EUISyncDebuffColorTicker() end
end

SLASH_XERIONTB1 = '/xeriontb'
SlashCmdList.XERIONTB = function()
	local function p(...) print('|cffff7d0aKiraTB|r', ...) end
	local cfg = GetDebuffColorCfg()
	p('enabled:', cfg.enable and 'yes' or 'NO')
	p('edit mode hint:', tbHintOnly and 'armed' or 'off',
		'| hint frame:', (tbPreview and tbPreview.frame:IsShown()) and 'shown' or 'hidden')
	do
		local want, moved, failed, total = cfg.aboveSwipe and true or false, 0, 0, 0
		for b in pairs(kiraTBButtons) do
			total = total + 1
			if b.__kiraCBAbove then moved = moved + 1 end
			if b.__kiraCBAboveFailed then failed = failed + 1 end
		end
		p(('above swipe: setting=%s | borders moved=%d/%d | refused=%d')
			:format(want and 'on' or 'off', moved, total, failed))
		if want and failed > 0 then
			p('|cffff5555some borders could not be re-parented - turn the option off to restore the default look.|r')
		end
	end
	local pf = _G.EllesmereUIUnitFrames_Player
	if not pf then p('player frame: MISSING (EllesmereUIUnitFrames_Player)') return end
	do
		local rows, btns, conv, forb, maxd = 0, 0, 0, 0, 0
		local function walk(f, d)
			if d > 6 or not f then return end
			if d > maxd then maxd = d end
			local ok, kids = pcall(function() return { f:GetChildren() } end)
			if not ok then return end
			for _, c in ipairs(kids) do
				if c.IsForbidden and c:IsForbidden() then
					forb = forb + 1
				else
					local ok2, ck = pcall(function() return { c:GetChildren() } end)
					if ok2 and ck[1] and ck[1].SetAuraBorder then
						rows = rows + 1
						for _, b in ipairs(ck) do
							if b.SetAuraBorder then
								btns = btns + 1
								if b.__kiraCBActive then conv = conv + 1 end
							end
						end
					end
					walk(c, d + 1)
				end
			end
		end
		walk(pf, 0)
		p(('container path: rows=%d borderButtons=%d converted=%d forbiddenSkipped=%d depth<=%d')
			:format(rows, btns, conv, forb, maxd))
		local AKh = GetAuraKit()
		p('initializer hook:', (AKh and AKh.__kiraTBWrapped) and 'wrapped' or 'NOT WRAPPED')
		local reg = 0
		for _ in pairs(kiraTBButtons) do reg = reg + 1 end
		p('registered borders:', reg)
		if _G.__kiraTBLastErr then p('SetAuraBorder error:', _G.__kiraTBLastErr) end
		local AK = _G.EllesmereUI and _G.EllesmereUI.AuraKit
		if AK and AK.styles then
			local keys = {}
			for k in pairs(AK.styles) do keys[#keys + 1] = tostring(k) end
			table.sort(keys)
			p('AuraKit styles:', table.concat(keys, ', '))
		else
			p('AuraKit: not reachable (EllesmereUI.AuraKit.styles nil)')
		end
	end
	local el = pf.Debuffs
	if not el then
		p('player frame found, Debuffs element: MISSING - scanning for candidates...')
		if EUF and EUF.objects then
			for i, obj in ipairs(EUF.objects) do
				if obj.unit == 'player' then
					p(('  oUF object %d: %s | Debuffs: %s | Buffs: %s'):format(
						i, obj.GetDebugName and obj:GetDebugName() or '?',
						obj.Debuffs and ('yes (' .. #obj.Debuffs .. ' buttons)') or 'no',
						obj.Buffs and ('yes (' .. #obj.Buffs .. ' buttons)') or 'no'))
					if obj.Debuffs then el = obj.Debuffs end
				end
			end
		end
		for k, v in pairs(pf) do
			if type(v) == 'table' and type(k) == 'string' and v.PostCreateButton ~= nil then
				p('  player frame field with PostCreateButton:', k)
			end
		end
		if not el then
			p('fingerprinting player frame children (shown only):')
			local kids = { pf:GetChildren() }
			for i = 1, math.min(#kids, 15) do
				local c = kids[i]
				if c and c:IsShown() then
					local keys = {}
					for k in pairs(c) do
						if type(k) == 'string' then keys[#keys + 1] = k end
					end
					table.sort(keys)
					local okW, w = pcall(c.GetWidth, c)
					local okH, h = pcall(c.GetHeight, c)
					local dims = (okW and okH and not (issecretvalue and (issecretvalue(w) or issecretvalue(h))))
						and (math.floor((w or 0) + 0.5) .. 'x' .. math.floor((h or 0) + 0.5)) or '?x?'
					local nkids = select('#', c:GetChildren())
					p(('  child %d: %s %s subframes=%d'):format(i, c:GetObjectType(), dims, nkids))
					if #keys > 0 then p('    keys: ' .. table.concat(keys, ', ')) end
					local g = select(1, c:GetChildren())
					if g then
						local gk = {}
						for k in pairs(g) do
							if type(k) == 'string' then gk[#gk + 1] = k end
						end
						table.sort(gk)
						if #gk > 0 then p('    first subframe keys: ' .. table.concat(gk, ', ')) end
					end
				end
			end
			p('=> screenshot/paste ALL of this to Claude')
			return
		end
		p('=> found a Debuffs element on an oUF object - retrying attach through it')
	end
	p('Debuffs element: found | buttons created:', #el,
		'| showDebuffType:', tostring(el.showDebuffType),
		'| curve set:', el.dispelColorCurve ~= nil and 'yes' or 'NO',
		'| post-hook:', el.__kiraTBPostHook and 'yes' or 'NO')
	local shown = 0
	for i = 1, #el do
		local b = el[i]
		if b and b:IsShown() then
			shown = shown + 1
			local conv = b.__kiraTBDone and 'converted' or 'NOT converted'
			local ovShown = b.Overlay and (b.Overlay:IsShown() and 'shown' or 'hidden') or 'NO Overlay'
			local edge = b.__kiraTBEdges and (b.__kiraTBEdges.top:IsShown() and 'shown' or 'hidden') or 'none'
			p(('  button %d: %s | Overlay: %s | edges: %s'):format(i, conv, ovShown, edge))
		end
	end
	p('buttons currently shown:', shown)
	if shown == 0 then p('=> no debuff buttons visible right now - get a debuff on you and rerun') end
end

-- Every player aura change fires both the DebuffFrame layout hook and our own
-- UNIT_AURA, so both go through this one queue: one pass per burst, and none
-- at all while the setting is off (turning it off hides the edges through
-- ns.EUIApplyDebuffColors, which calls ApplyDebuffColors directly). A hidden
-- DebuffFrame (EUI's player aura bars can hide it) is skipped; the 0.3s
-- ticker repaints within a moment of it showing again.
local dcPending
local function FlushDebuffColors()
	dcPending = nil
	local DF = _G.DebuffFrame
	if DF and DF:IsShown() then ApplyDebuffColors() end
end
local function QueueDebuffColors()
	if dcPending or not GetDebuffColorCfg().enable then return end
	dcPending = true
	C_Timer.After(0.05, FlushDebuffColors)
end

local dcEvt = CreateFrame('Frame')
dcEvt:RegisterEvent('PLAYER_ENTERING_WORLD')
dcEvt:SetScript('OnEvent', function(_, event)
	QueueDebuffColors()
	if event == 'PLAYER_ENTERING_WORLD' then
		local function attach()
			ApplyUnitframeDebuffColors()
			ApplyContainerDebuffColors()
		end
		C_Timer.After(1, attach)
		C_Timer.After(3, attach)
		C_Timer.After(7, attach)
	end
end)

C_Timer.After(2, function()
	local DF = _G.DebuffFrame
	if DF and DF.AuraContainer and DF.AuraContainer.UpdateGridLayout then
		hooksecurefunc(DF.AuraContainer, 'UpdateGridLayout', QueueDebuffColors)
	end
	ApplyDebuffColors()
	ApplyUnitframeDebuffColors()
end)
local dcTicker
local function SyncDebuffColorTicker()
	local want = GetDebuffColorCfg().enable and true or false
	if want then
		dcEvt:RegisterUnitEvent('UNIT_AURA', 'player')
	else
		dcEvt:UnregisterEvent('UNIT_AURA')
	end
	if want and not dcTicker then
		dcTicker = C_Timer.NewTicker(0.3, function()
			local DF = _G.DebuffFrame
			if DF and DF:IsShown() then ApplyDebuffColors() end
			if tbHintOnly and not tbPreviewActive then StyleTBPreview() end
		end)
	elseif not want and dcTicker then
		dcTicker:Cancel()
		dcTicker = nil
	end
end
ns.EUISyncDebuffColorTicker = SyncDebuffColorTicker
SyncDebuffColorTicker()

-- PLAYER DEBUFF TIMER (min:sec). EUI writes a debuff's time left as bare
-- seconds under a minute ("45") and whole minutes above it ("4m"). Its Player
-- Aura Bars already know the clock style ("4:32") below a chosen time: the
-- built-in Debuffs bar's durationPrecisionThreshold, in seconds, which EUI's own
-- settings keep in that bar's Duration cog ("Precise Below"). This is a front
-- door to that same saved value, not a copy: the page reads and writes the
-- bar's EUI settings and asks EUI to restyle, so the two controls never
-- disagree and the choice rides the EUI profile. The text is formatted
-- engine-side against the secret remaining time, so nothing is read here and it
-- works in keys. Only the minutes the slider last held live in the plugin, so
-- switching off and on again brings them back. Debuffs bar only, on purpose:
-- that is where the player's debuffs sit (EllesmereUIPlayerAuraBars_Debuffs);
-- the unit frame's own debuff row has a separate key and is left alone.
do
	local TIMER_DEFAULTS = { minutes = 5 }
	local function GetTimerCfg() return ns.ModuleCfg('euiDebuffTimer', TIMER_DEFAULTS) end

	-- The bar code lives in the unit-frames module, so its namespace holds
	-- both the settings and the restyle. Resolved at call time: an EUI profile
	-- switch swaps db.profile. PAB_DefaultDebuffsCfg creates the bar's table on
	-- first use, exactly as EUI's own page does.
	local function DebuffBarCfg()
		local mns = EUI._ModuleNS and EUI._ModuleNS.EllesmereUIUnitFrames
		local prof = mns and mns.db and mns.db.profile
		local s = prof and prof.playerAuraBars
		if not (s and mns.PAB_DefaultDebuffsCfg) then return nil end
		return mns.PAB_DefaultDebuffsCfg(s), mns
	end

	-- EUI treats one minute or less as off (its m:ss band would be empty).
	local function HeldMinutes(bar)
		local v = tonumber(bar.durationPrecisionThreshold)
		if v and v > 60 then return math.floor(v / 60 + 0.5) end
	end

	-- on, minutes. on is nil when the bar's settings cannot be found.
	function ns.EUIGetDebuffTimer()
		local bar = DebuffBarCfg()
		if not bar then return nil, GetTimerCfg().minutes end
		local m = HeldMinutes(bar)
		if m then return true, m end
		return false, GetTimerCfg().minutes
	end

	function ns.EUISetDebuffTimer(on, minutes)
		local bar, mns = DebuffBarCfg()
		if not bar then return end
		local cfg = GetTimerCfg()
		-- EUI's own slider may have moved it since; keep that for the next "on".
		cfg.minutes = minutes or HeldMinutes(bar) or cfg.minutes
		bar.durationPrecisionThreshold = on and cfg.minutes * 60 or nil
		-- EUI's re-skin for style-only fields: it rebuilds the bar styles and
		-- rebinds the duration formatter; a rebind the client refuses while
		-- auras are secret is retried on the next restyle.
		if mns.PAB_Restyle then mns.PAB_Restyle() end
	end
end

-- The Player and Focus options were removed from the XerionUI plugin.
-- Clear their plugin-owned settings and undo the EUI duration setting this plugin exposed.
GetDebuffColorCfg().enable = false
ns.EUIApplyDebuffColors()
GetFocusMarkCfg().enable = false
ns.EUIApplyFocusMark()
GetFocusRangeCfg().enable = false
ns.EUIApplyFocusRange()
ns.EUISetDebuffTimer(false)
local loginFrame = CreateFrame('Frame')
loginFrame:RegisterEvent('PLAYER_ENTERING_WORLD')
loginFrame:SetScript('OnEvent', function()
	C_Timer.After(1, UpdateFocusMark)
end)
