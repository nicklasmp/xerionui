local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('FieryBrand', hooksecurefunc, C_Timer)
local _G = _G

local CreateFrame = CreateFrame
local UIParent = UIParent
local issecretvalue = issecretvalue
local pairs = pairs
local pcall = pcall

local GetPlayerAuraBySpellID = _G.C_UnitAuras and _G.C_UnitAuras.GetPlayerAuraBySpellID
local GetUnitAuraBySpellID = _G.C_UnitAuras and _G.C_UnitAuras.GetUnitAuraBySpellID

ns.hasFieryBrand = true

local IS_121 = ns.IS_121

local function IsDemonHunter() return ns.IsClass('DEMONHUNTER') end

ns.FBDisabled = not IS_121

local FB_IDS = {
	[204021] = true,
	[207744] = true,
	[207771] = true,
}
local FB_ICON_FALLBACK = 1344647

local Round = ns.Round

local DEFAULTS = {
	enable = false,
	lock = true,
	iconW = 44,
	iconH = 44,
	x = 0,
	y = -120,
	strata = 'MEDIUM',
	attachFrame = '',
	attachSide = 'RIGHT',
	attachFallback = true,
	durSize = 0,
	desatDebuff = true,
	buffBorder   = { 1, 0.49, 0.04, 1 },
	debuffBorder = { 0.45, 0.45, 0.45, 1 },
	buffText   = { 1, 1, 1, 1 },
	debuffText = { 0.8, 0.8, 0.8, 1 },
}

local function GetCfg() return ns.ModuleCfg('fieryBrand', DEFAULTS) end
ns.FBGetCfg = GetCfg

local BarFont = ns.GothamNarrowBlackFont

local DurationTextOptions = ns.DurationTextOptions

local function IconTexture()
	local get = _G.C_Spell and _G.C_Spell.GetSpellTexture
	if get then
		local tex = get(204021)
		if not (issecretvalue and issecretvalue(tex)) and tex then return tex end
	end
	return FB_ICON_FALLBACK
end

local holder, previewTex, previewText, previewBorder
local preview
local ApplySettings

local function EnsureHolder()
	if holder then return end
	holder = CreateFrame('Frame', 'XerionUIFieryBrand', UIParent)
	holder:SetFrameStrata('MEDIUM')
	holder:SetClampedToScreen(true)
	holder:SetMovable(true)
	holder:EnableMouse(false)
	holder:RegisterForDrag('RightButton')
	holder:SetSize(44, 44)
	holder:Show()

	ns.MakeDraggable(holder, GetCfg, 'x', 'y',
		function() if ns.FBApply then ns.FBApply() end end,
		function(cfg) return not cfg.lock and (cfg.attachFrame or '') == '' end)
end

local anchorMode
local function PositionHolder(force)
	if not holder then return end
	local cfg = GetCfg()
	local target
	if (cfg.attachFrame or '') ~= '' then
		local t = _G[cfg.attachFrame]
		if type(t) == 'table' and t.GetObjectType and t.GetWidth then target = t end
	end

	local mode = 'free'
	if target then
		mode = 'attached'
		if cfg.attachFallback then
			local ok, shown = pcall(target.IsVisible, target)
			if not ok or not shown then mode = 'fallback' end
		end
	end
	if not force and mode == anchorMode then return end
	anchorMode = mode

	local x, y = cfg.x or 0, cfg.y or 0
	holder:ClearAllPoints()
	if mode == 'attached' then
		local side = cfg.attachSide or 'RIGHT'
		if side == 'LEFT' then
			holder:SetPoint('RIGHT', target, 'LEFT', x, y)
		elseif side == 'TOP' then
			holder:SetPoint('BOTTOM', target, 'TOP', x, y)
		elseif side == 'BOTTOM' then
			holder:SetPoint('TOP', target, 'BOTTOM', x, y)
		else
			holder:SetPoint('LEFT', target, 'RIGHT', x, y)
		end
	else
		holder:SetPoint('CENTER', UIParent, 'CENTER', x, y)
	end
end

local buffContainer, debuffContainer
local layers = { buff = {}, debuff = {} }

local function StyleLayer(refs, isDebuff)
	if not refs then return end
	if refs.frame and refs.frame.IsForbidden and refs.frame:IsForbidden() then return end
	local cfg = GetCfg()
	local w, h = cfg.iconW or 44, cfg.iconH or 44
	pcall(function()
		if refs.frame then refs.frame:SetSize(w, h) end
		if refs.border then
			local c = isDebuff and cfg.debuffBorder or cfg.buffBorder
			refs.border:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
		end
		if refs.icon then
			refs.icon:SetDesaturated(isDebuff and cfg.desatDebuff or false)
		end
		if refs.dur then
			local ds = cfg.durSize or 0
			if ds <= 0 then ds = math.max(10, Round(math.min(w, h) * 0.36)) end
			refs.dur:SetFont(BarFont(), ds, 'OUTLINE')
			local c = isDebuff and cfg.debuffText or cfg.buffText
			refs.dur:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
		end
	end)
end

if IS_121 then
	EnsureHolder()

	local function MakeLayer(containerName, slotName, filter, unit, isDebuff, level)
		local sub = CreateFrame('Frame', nil, holder)
		sub:SetAllPoints(holder)
		sub:SetFrameLevel(holder:GetFrameLevel() + level)

		local container = CreateFrame('AuraContainer', containerName, sub, 'CustomAuraContainerTemplate')
		container:SetPoint('CENTER', holder, 'CENTER', 0, 0)
		container:SetSize(1, 1)

		local refs = isDebuff and layers.debuff or layers.buff
		local slot = container:AddAuraSlot(slotName, filter, {
			candidateFilters = {
				includeSpellIDs = FB_IDS,
			},
			initializeFrame = function(auraFrame)
				refs.frame = auraFrame
				auraFrame:SetSize(GetCfg().iconW or 44, GetCfg().iconH or 44)

				pcall(auraFrame.EnableMouse, auraFrame, false)
				if auraFrame.SetMouseClickEnabled then
					pcall(auraFrame.SetMouseClickEnabled, auraFrame, false)
				end
				if auraFrame.SetMouseMotionEnabled then
					pcall(auraFrame.SetMouseMotionEnabled, auraFrame, false)
				end

				local border = auraFrame:CreateTexture(nil, 'BACKGROUND')
				border:SetAllPoints()
				refs.border = border

				local icon = auraFrame:CreateTexture(nil, 'ARTWORK')
				icon:SetPoint('TOPLEFT', 1, -1)
				icon:SetPoint('BOTTOMRIGHT', -1, 1)
				icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				auraFrame:SetIcon(icon)
				refs.icon = icon

				local cd = CreateFrame('Cooldown', nil, auraFrame, 'CooldownFrameTemplate')
				cd:SetAllPoints(icon)
				cd:SetDrawEdge(false)
				cd:SetDrawBling(false)
				cd:SetReverse(true)
				cd:SetHideCountdownNumbers(true)
				cd.noCooldownCount = true
				auraFrame:SetDurationCooldown(cd)
				refs.cd = cd

				local lvl = CreateFrame('Frame', nil, auraFrame)
				lvl:SetAllPoints()
				lvl:SetFrameLevel(cd:GetFrameLevel() + 5)
				local dur = lvl:CreateFontString(nil, 'OVERLAY', 'NumberFontNormal')
				dur:SetPoint('CENTER', auraFrame, 'CENTER', 0, 0)
				auraFrame:SetDurationText(dur, DurationTextOptions())
				refs.dur = dur

				StyleLayer(refs, isDebuff)
			end,
		})
		slot:SetPoint('CENTER', holder, 'CENTER', 0, 0)
		container:SetUnit(unit)
		container:SetEnabled(false)
		return container
	end

	buffContainer   = MakeLayer('XerionUIFBBuffContainer',   'XerionUIFBBuffSlot',   'HELPFUL',        'player', false, 16)
	debuffContainer = MakeLayer('XerionUIFBDebuffContainer', 'XerionUIFBDebuffSlot', 'HARMFUL|PLAYER', 'target', true,  1)
end

local function TargetIsHostile()
	local can = _G.UnitCanAttack('player', 'target')
	if issecretvalue and issecretvalue(can) then return true end
	return can and true or false
end

local function IsReadable(unit)
	return unit ~= nil
		and _G.UnitIsConnected(unit) == true
		and _G.UnitIsVisible(unit) == true
		and _G.UnitPhaseReason(unit) == nil
end

local function PlayerIsReadable()
	if not IsReadable('player') then return false end
	local ok, canAssist = pcall(_G.UnitCanAssist, 'player', 'player')
	if not ok or canAssist ~= true then return false end
	return true
end

local function UpdateBuffLayer()
	if not buffContainer then return end
	local cfg = GetCfg()
	local on = cfg.enable and not ns.FBDisabled and IsDemonHunter()
		and PlayerIsReadable() and true or false
	if not pcall(buffContainer.SetEnabled, buffContainer, on) then return end
	if on then pcall(buffContainer.UpdateAllAuras, buffContainer) end
end

local function UpdateDebuffLayer()
	if not debuffContainer then return end
	local cfg = GetCfg()
	local on = cfg.enable and not ns.FBDisabled and IsDemonHunter()
		and TargetIsHostile() and IsReadable('target')
	if not pcall(debuffContainer.SetEnabled, debuffContainer, on) then return end
	if on then
		debuffContainer:UpdateAllAuras()
		C_Timer.After(0, function()
			if debuffContainer then debuffContainer:UpdateAllAuras() end
		end)
	end
end

ApplySettings = function()
	EnsureHolder()
	local cfg = GetCfg()
	holder:SetSize(cfg.iconW or 44, cfg.iconH or 44)
	holder:SetFrameStrata(cfg.strata or 'MEDIUM')
	PositionHolder(true)
	StyleLayer(layers.buff, false)
	StyleLayer(layers.debuff, true)
end

-- The preview's own icon, drawn on the holder. Apart from SetPreview so Apply
-- can redraw it when a size or colour changes while it is up.
local function DrawPreview()
	holder:EnableMouse(preview)
	if preview and not previewTex then
		previewBorder = holder:CreateTexture(nil, 'BACKGROUND')
		previewBorder:SetAllPoints()
		previewTex = holder:CreateTexture(nil, 'ARTWORK')
		previewTex:SetPoint('TOPLEFT', 1, -1)
		previewTex:SetPoint('BOTTOMRIGHT', -1, 1)
		previewTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		previewTex:SetTexture(IconTexture())
		previewText = holder:CreateFontString(nil, 'OVERLAY')
		previewText:SetPoint('CENTER')
	end
	if previewTex then
		if preview then
			local cfg = GetCfg()
			previewTex:SetTexture(IconTexture())
			local c = cfg.buffBorder or DEFAULTS.buffBorder
			previewBorder:SetColorTexture(c[1] or 1, c[2] or 0.5, c[3] or 0, c[4] or 1)
			local ds = cfg.durSize or 0
			if ds <= 0 then ds = math.max(10, Round(math.min(cfg.iconW or 44, cfg.iconH or 44) * 0.36)) end
			previewText:SetFont(BarFont(), ds, 'OUTLINE')
			local tc = cfg.buffText or DEFAULTS.buffText
			previewText:SetTextColor(tc[1] or 1, tc[2] or 1, tc[3] or 1, tc[4] or 1)
			previewText:SetText('8')
			previewBorder:Show() previewTex:Show() previewText:Show()
		else
			previewBorder:Hide() previewTex:Hide() previewText:Hide()
		end
	end
end

ns.FBApply = function()
	if ns.FBDisabled or not IsDemonHunter() then
		pcall(function()
			if buffContainer then buffContainer:SetEnabled(false) end
			if debuffContainer then debuffContainer:SetEnabled(false) end
		end)
		-- The preview is only a drawing, so it still follows the sliders on a
		-- character that is not a Demon Hunter; the engine layers stay off.
		if preview then
			ApplySettings()
			DrawPreview()
		end
		if ns.FBSyncFollowTicker then ns.FBSyncFollowTicker() end
		return
	end
	ApplySettings()
	if preview then DrawPreview() end
	UpdateBuffLayer()
	UpdateDebuffLayer()
	if ns.FBSyncFollowTicker then ns.FBSyncFollowTicker() end
end

ns.FBIsPreview = function() return preview and true or false end
-- No class check: the settings window opens on every character and the user
-- tests pages on whatever alt is logged in. A gate here made the button a
-- silent no-op on anything but a Demon Hunter.
ns.FBSetPreview = function(state)
	if ns.FBDisabled then return end
	preview = state and true or false
	EnsureHolder()
	ApplySettings()
	DrawPreview()
end

ns.FBTest = function()
	local function p(...) print('|cffff7d0aXerionUI-FieryBrand|r', ...) end
	p('--- Fiery Brand diagnostics (best run OUT of combat with brand active) ---')
	if not GetPlayerAuraBySpellID then p('C_UnitAuras.GetPlayerAuraBySpellID missing') return end
	for id in pairs(FB_IDS) do
		local aura = GetPlayerAuraBySpellID(id)
		p('player buff', id, '=', aura and 'FOUND' or 'nothing')
		if GetUnitAuraBySpellID then
			local d = GetUnitAuraBySpellID('target', id, 'HARMFUL')
			p('target debuff', id, '=', d and 'FOUND' or 'nothing')
		end
	end
	if buffContainer and buffContainer.HasAuraSlot then
		p('engine accepted buff slot =', buffContainer:HasAuraSlot('XerionUIFBBuffSlot') and 'YES' or 'NO (silent slot failure - report this)')
	end
	if debuffContainer and debuffContainer.HasAuraSlot then
		p('engine accepted debuff slot =', debuffContainer:HasAuraSlot('XerionUIFBDebuffSlot') and 'YES' or 'NO (silent slot failure - report this)')
	end
	local cfg = GetCfg()
	p('enable =', cfg.enable and 'on' or 'off',
		'| 12.1+ =', IS_121 and 'yes' or 'NO (module disabled)',
		'| containers =', (buffContainer and debuffContainer) and 'built' or 'MISSING',
		'| in combat =', _G.InCombatLockdown() and 'yes' or 'no')

	local okC, _, cls = pcall(_G.UnitClass, 'player')
	p('UnitClass =', okC and tostring(cls) or 'CALL FAILED',
		'| secret =', (issecretvalue and okC and issecretvalue(cls)) and 'yes' or 'no',
		'| IsDemonHunter() =', IsDemonHunter() and 'yes' or 'NO (module refuses to draw)')
	p('player readable =', PlayerIsReadable() and 'yes' or 'NO (buff layer forced off)',
		'| target readable =', IsReadable('target') and 'yes' or 'no',
		'| target hostile =', TargetIsHostile() and 'yes' or 'no')
	p('holder =', holder and 'built' or 'MISSING',
		'| shown =', (holder and holder:IsShown()) and 'yes' or 'no',
		'| size =', holder and (Round(holder:GetWidth() or 0) .. 'x' .. Round(holder:GetHeight() or 0)) or '-',
		'| alpha =', holder and string.format('%.2f', holder:GetAlpha() or 0) or '-')
	local px, py = holder and holder:GetCenter()
	p('holder centre =', px and (Round(px) .. ', ' .. Round(py)) or 'no position',
		'| preview =', preview and 'ON' or 'off',
		'| previewTex =', previewTex and (previewTex:IsShown() and 'shown' or 'hidden') or 'not created')
	p('attachFrame =', (cfg.attachFrame or '') ~= '' and cfg.attachFrame or 'none (free placement)',
		'| that frame exists =', ((cfg.attachFrame or '') == '' or _G[cfg.attachFrame]) and 'yes' or 'NO - icon has nothing to anchor to')
	p('If a FOUND id differs from what the slots track, tell Kira/Claude which id showed FOUND.')
end

local evt = CreateFrame('Frame')
evt:RegisterEvent('PLAYER_ENTERING_WORLD')
evt:RegisterEvent('PLAYER_TARGET_CHANGED')
evt:RegisterUnitEvent('UNIT_PHASE', 'target', 'player')
evt:RegisterUnitEvent('UNIT_CONNECTION', 'target', 'player')
evt:RegisterUnitEvent('UNIT_FLAGS', 'player')
evt:RegisterUnitEvent('UNIT_FACTION', 'player')
evt:SetScript('OnEvent', function(_, event, unit)
	if ns.FBDisabled or not IsDemonHunter() then return end
	if event == 'PLAYER_TARGET_CHANGED' then
		if GetCfg().enable then UpdateDebuffLayer() end
	elseif event == 'UNIT_PHASE' or event == 'UNIT_CONNECTION'
		or event == 'UNIT_FLAGS' or event == 'UNIT_FACTION' then
		if not GetCfg().enable then return end
		if unit == 'player' then UpdateBuffLayer() end
		if unit == 'target' then UpdateDebuffLayer() end
	else
		ns.FBApply()
		C_Timer.After(2, function() if ns.FBApply then ns.FBApply() end end)
	end
end)

local followTicker
local function SyncFollowTicker()
	local cfg = GetCfg()
	local want = (not ns.FBDisabled) and IsDemonHunter() and cfg.enable
		and (cfg.attachFrame or '') ~= '' and cfg.attachFallback and true or false
	if want and not followTicker then
		followTicker = C_Timer.NewTicker(0.25, function() PositionHolder(false) end)
	elseif not want and followTicker then
		followTicker:Cancel()
		followTicker = nil
	end
end
ns.FBSyncFollowTicker = SyncFollowTicker

_G.SLASH_XERIONVDH1 = '/xerionvdh'
_G.SlashCmdList.XERIONVDH = function()
	if ns.FBTest then ns.FBTest() end
end
