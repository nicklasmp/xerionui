local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('CDMAnchor', hooksecurefunc, C_Timer)
local _G = _G

local EUI_CDM = 'EllesmereUICooldownManager'

local function EUIGroups()
	local E = _G.EllesmereUI
	if not E then return nil end

	local lite = E.Lite
	if lite and lite.GetAddon then
		local ok, addon = pcall(lite.GetAddon, EUI_CDM, true)
		if ok and addon then
			local db = addon.db
			local p = db and db.profile
			local cb = p and p.cdmBars
			if cb and cb.bars then return cb.bars end
		end
	end

	local mod = E._ModuleNS and E._ModuleNS[EUI_CDM]
	local ecme = mod and mod.ECME
	local db = ecme and ecme.db
	local p = db and db.profile
	local cb = p and p.cdmBars
	return cb and cb.bars or nil
end

local function GroupFrame(key)
	if not key or key == '' then return nil end
	local get = _G._ECME_GetBarFrame
	if get then
		local ok, f = pcall(get, key)
		if ok and f then return f end
	end
	return _G['ECME_CDMBar_' .. key]
end

local function IsAuraGroup(bd)
	local t = bd and bd.barType
	return t == 'buffs' or t == 'custom_buff'
end

local function ResolveGroup(cfg)
	if not cfg then return nil, nil end
	local bars = EUIGroups()

	if not bars then
		local f = GroupFrame(cfg.euiBarKey)
		if f then return f, nil end
		return nil, nil
	end

	local want = cfg.euiBarKey
	if want and want ~= '' then
		for _, bd in ipairs(bars) do
			if bd and bd.key == want then
				local f = GroupFrame(want)
				if f then return f, bd end
				break
			end
		end
	end

	for _, bd in ipairs(bars) do
		if bd and bd.enabled and not bd.isGhostBar
			and bd.key ~= 'focuskick' and IsAuraGroup(bd) then
			local f = GroupFrame(bd.key)
			if f then return f, bd end
		end
	end
	return nil, nil
end

function ns.CDMGroupOptions()
	local out = { { value = '', text = 'Auto - first buff group' } }
	local bars = EUIGroups()
	if not bars then return out end
	for _, bd in ipairs(bars) do
		if bd and bd.key and IsAuraGroup(bd) then
			local label = bd.name or bd.key
			if not bd.enabled then label = label .. ' (disabled)' end
			out[#out + 1] = { value = bd.key, text = label }
		end
	end
	return out
end

function ns.CDMPlaceOptions(cfg)
	local _, bd = ResolveGroup(cfg)
	local grow = (bd and bd.growDirection) or 'CENTER'
	local afterSide, beforeSide
	if (bd and bd.verticalOrientation) or grow == 'UP' or grow == 'DOWN' then
		if grow == 'UP' then afterSide, beforeSide = 'above the group', 'below the group'
		else afterSide, beforeSide = 'below the group', 'above the group' end
	elseif grow == 'LEFT' then
		afterSide, beforeSide = 'left side', 'right side'
	else
		afterSide, beforeSide = 'right side', 'left side'
	end
	return {
		{ value = 'CENTER', text = 'Centred on the group' },
		{ value = 'AFTER',  text = 'Tail - ' .. afterSide },
		{ value = 'BEFORE', text = 'Tail - ' .. beforeSide },
	}
end

function ns.CDMAnchorStatus(cfg)
	if not _G.EllesmereUI then return 'EllesmereUI is not loaded - it uses its free screen position.' end
	local bar, bd = ResolveGroup(cfg)
	if not bar then
		return 'No EllesmereUI buff group found - it uses its free screen position.'
	end
	local name = (bd and (bd.name or bd.key)) or 'unnamed group'
	local grow = (bd and bd.growDirection) or 'CENTER'
	local auto = (not cfg.euiBarKey or cfg.euiBarKey == '') and ' (auto)' or ''
	return 'Anchored to: |cff0CD29D' .. name .. '|r' .. auto .. '  -  grows ' .. string.lower(grow) .. '.'
end

local function GroupIconSize(bd)
	if not bd then return nil, nil end
	local w = bd.iconSize or 36
	local h = w
	if (bd.iconShape or 'none') == 'cropped' then
		h = math.floor(w * 0.80 + 0.5)
	end
	return w, h
end

local function AnchorToGroup(f, cfg)
	if not f then return false end
	local bar, bd = ResolveGroup(cfg)
	if not bar then return false end

	local ox    = cfg.euiOffsetX or 0
	local oy    = cfg.euiOffsetY or 0
	local place = cfg.euiPlace or 'CENTER'
	local grow  = (bd and bd.growDirection) or 'CENTER'
	local vert  = bd and bd.verticalOrientation
	local gap   = (bd and bd.spacing) or 2
	local iw, ih = GroupIconSize(bd)
	iw, ih = iw or 36, ih or 36
	local empty = (bar._acLiveW ~= nil and bar._acLiveW <= 0.5)

	f:ClearAllPoints()

	if place == 'CENTER' then
		if grow == 'CENTER' or (grow ~= 'RIGHT' and grow ~= 'LEFT' and grow ~= 'UP' and grow ~= 'DOWN') then
			f:SetPoint('CENTER', bar, 'CENTER', ox, oy)
		elseif grow == 'RIGHT' then
			f:SetPoint('CENTER', bar, 'LEFT', iw / 2 + ox, oy)
		elseif grow == 'LEFT' then
			f:SetPoint('CENTER', bar, 'RIGHT', -iw / 2 + ox, oy)
		elseif grow == 'DOWN' then
			f:SetPoint('CENTER', bar, 'TOP', ox, -ih / 2 + oy)
		else
			f:SetPoint('CENTER', bar, 'BOTTOM', ox, ih / 2 + oy)
		end
		return true
	end

	local after = (place == 'AFTER')

	if vert or grow == 'UP' or grow == 'DOWN' then
		local up = (grow == 'UP')
		if up == after then
			if empty then f:SetPoint('BOTTOM', bar, 'BOTTOM', ox, oy)
			else f:SetPoint('BOTTOM', bar, 'TOP', ox, gap + oy) end
		else
			if empty then f:SetPoint('TOP', bar, 'TOP', ox, oy)
			else f:SetPoint('TOP', bar, 'BOTTOM', ox, -gap + oy) end
		end
		return true
	end

	if grow == 'CENTER' and empty then
		f:SetPoint('CENTER', bar, 'CENTER', ox, oy)
		return true
	end

	local left = (grow == 'LEFT')
	if left == after then
		if empty then f:SetPoint('RIGHT', bar, 'RIGHT', ox, oy)
		else f:SetPoint('RIGHT', bar, 'LEFT', -gap + ox, oy) end
	else
		if empty then f:SetPoint('LEFT', bar, 'LEFT', ox, oy)
		else f:SetPoint('LEFT', bar, 'RIGHT', gap + ox, oy) end
	end
	return true
end

ns.CDMResolveGroup  = ResolveGroup
ns.CDMAnchorTo      = AnchorToGroup
