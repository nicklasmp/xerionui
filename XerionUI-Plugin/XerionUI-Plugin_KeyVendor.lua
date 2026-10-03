local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('KeyVendor', hooksecurefunc, C_Timer)
local _G = _G

local hooksecurefunc = hooksecurefunc
local ipairs, type, tonumber = ipairs, type, tonumber
local strsplit = strsplit
local mmin = math.min

ns.hasKeyVendor = true

local secret = ns.IsSecret

local DEFAULTS = {
	enable = false,
	npcID = 123227,
	minLevel = 17,
	maxLevel = 25,
	textSize = 18,
	mapSize = 13,
}

local function GetCfg() return ns.ModuleCfg('keyVendor', DEFAULTS) end
ns.KVGetCfg = GetCfg

local COLOR_UTIL = { 0x27 / 255, 0x9d / 255, 0xff / 255 }
local COLOR_MAP  = { 0xff / 255, 0x16 / 255, 0x54 / 255 }
local COLOR_LVL  = { 0x3b / 255, 0xb2 / 255, 0x73 / 255 }

local AFFIX_SHORT = {
	["Xal'atath's Guile"] = 'Guile',
}

local function ShortAffix(affix)
	local short = AFFIX_SHORT[affix]
	if short then return short end
	return affix:match('.*:%s*(.+)$')
		or affix:match("^%S*['\226\128\153]%S*%s+(.+)$")
		or affix
end

local function Classify(name)
	if name == 'Keystone Container' then return 'Keystone', COLOR_UTIL end
	local lvl = name:match('^Set Keystone Level: (%d+)$')
	if lvl then
		local n = tonumber(lvl)
		local cfg = GetCfg()
		local hot = n and n >= (cfg.minLevel or 17) and n <= (cfg.maxLevel or 25)
		return lvl, hot and COLOR_LVL or nil
	end
	local map = name:match('^Set Keystone Map: (.+)$')
	if map then return ns.MDIShortName(map) or map, COLOR_MAP end
	local affix = name:match('^Add Keystone Affix: (.+)$')
	if affix then return ShortAffix(affix), COLOR_UTIL end
	return nil, nil
end

local function MerchantItemName(index)
	local CMF = _G.C_MerchantFrame
	if CMF and CMF.GetItemInfo then
		local ok, info = pcall(CMF.GetItemInfo, index)
		local nm = ok and type(info) == 'table' and info.name or nil
		if nm ~= nil and not secret(nm) and type(nm) == 'string' then return nm end
		if CMF.GetItemInfo then return nil end
	end
	local nm = _G.GetMerchantItemInfo and _G.GetMerchantItemInfo(index)
	if nm ~= nil and not secret(nm) and type(nm) == 'string' then return nm end
	return nil
end

local function IsKeyVendor()
	local cfg = GetCfg()
	local guid = _G.UnitGUID and _G.UnitGUID('npc')
	if guid and not secret(guid) and (cfg.npcID or 0) > 0 then
		local unitType, _, _, _, _, id = strsplit('-', guid)
		if unitType == 'Creature' then
			return tonumber(id or 0) == cfg.npcID
		end
	end
	local hits = 0
	local n = (_G.GetMerchantNumItems and _G.GetMerchantNumItems()) or 0
	for i = 1, mmin(n, 60) do
		local nm = MerchantItemName(i)
		if nm and nm:find('Set Keystone Map:', 1, true) then
			hits = hits + 1
			if hits >= 2 then return true end
		end
	end
	return false
end

local skinnedActive = false

local function SaveOrig(button)
	if button.__kiraKVOrig then return button.__kiraKVOrig end
	local o = {}
	if button.Name then
		local font, size, flags = button.Name:GetFont()
		local r, g, b = button.Name:GetTextColor()
		o.font, o.size, o.flags = font, size, flags
		o.r, o.g, o.b = r, g, b
	end
	button.__kiraKVOrig = o
	return o
end

local function RestoreButton(button)
	local o = button.__kiraKVOrig
	if not o then return end
	button:SetAlpha(1)
	if button.icon then button.icon:SetDesaturated(false) end
	if button.Name then
		if o.font then button.Name:SetFont(ns.GetFont(o.font), o.size or 12, o.flags) end
		button.Name:SetTextColor(o.r or 1, o.g or 0.82, o.b or 0)
	end
end

local function ResetMerchantButtons()
	if not skinnedActive then return end
	skinnedActive = false
	local per = _G.MERCHANT_ITEMS_PER_PAGE or 12
	for i = 1, per do
		local button = _G['MerchantItem' .. i]
		if button then RestoreButton(button) end
	end
end

local function SkinMerchant()
	local cfg = GetCfg()
	if not cfg.enable then ResetMerchantButtons() return end
	local mf = _G.MerchantFrame
	if mf and mf.selectedTab and mf.selectedTab ~= 1 then ResetMerchantButtons() return end
	if not IsKeyVendor() then ResetMerchantButtons() return end
	skinnedActive = true
	local per = _G.MERCHANT_ITEMS_PER_PAGE or 12
	for i = 1, per do
		local button = _G['MerchantItem' .. i]
		-- The button's ID, not page * per + i: Vendor Search refills these
		-- tiles with its results, and the ID is the item a tile really shows.
		local ib = _G['MerchantItem' .. i .. 'ItemButton']
		local index = ib and ib:IsShown() and ib:GetID()
		local itemName = index and index > 0 and MerchantItemName(index)
		if button and itemName then
			local orig = SaveOrig(button)
			local rename, color = Classify(itemName)
			if rename and button.Name then button.Name:SetText(rename) end
			if color then
				button:SetAlpha(1)
				if button.icon then button.icon:SetDesaturated(false) end
				if button.Name then
					button.Name:SetTextColor(color[1], color[2], color[3])
					local size = (color == COLOR_MAP) and (cfg.mapSize or 13) or (cfg.textSize or 18)
					if orig.font then button.Name:SetFont(ns.GetFont(orig.font), size, orig.flags) end
				end
			else
				button:SetAlpha(0.2)
				if button.icon then button.icon:SetDesaturated(true) end
				if button.Name then
					button.Name:SetTextColor(0.5, 0.5, 0.5)
					if orig.font then button.Name:SetFont(ns.GetFont(orig.font), orig.size or 12, orig.flags) end
				end
			end
		end
	end
end

ns.KVApply = function()
	if _G.MerchantFrame and _G.MerchantFrame:IsShown() then
		pcall(SkinMerchant)
	elseif not GetCfg().enable then
		ResetMerchantButtons()
	end
end

-- MerchantFrame_Update also runs on every BAG_UPDATE and UNIT_INVENTORY_CHANGED
-- while the vendor is CLOSED (the frame keeps its events registered), and each
-- of those read up to 60 item names for nothing: OnHide already put the tiles
-- back. Opening the vendor still skins it - MerchantFrame_OnShow calls
-- MerchantFrame_Update with the frame shown, and MerchantFrame_MerchantShow
-- calls it again once ShowUIPanel has shown it.
local function OnMerchantUpdate()
	if not (_G.MerchantFrame and _G.MerchantFrame:IsShown()) then return end
	pcall(SkinMerchant)
end

if type(_G.MerchantFrame_Update) == 'function' then
	hooksecurefunc('MerchantFrame_Update', OnMerchantUpdate)
end
if type(_G.MerchantFrame_UpdateItemQualityBorders) == 'function' then
	hooksecurefunc('MerchantFrame_UpdateItemQualityBorders', OnMerchantUpdate)
end
if _G.MerchantFrame and _G.MerchantFrame.HookScript then
	_G.MerchantFrame:HookScript('OnHide', function() pcall(ResetMerchantButtons) end)
end

SLASH_XERIONKV1 = '/xerionkv'
SlashCmdList.XERIONKV = function()
	local function p(...) print('|cffff7d0aKiraKV|r', ...) end
	local guid = _G.UnitGUID and _G.UnitGUID('npc')
	if guid and not secret(guid) then
		local unitType, _, _, _, _, id = strsplit('-', guid)
		p('npc:', unitType or '?', '- npcID:', tostring(id))
	else
		p('npc GUID:', guid == nil and 'nil (no vendor open?)' or 'SECRET')
	end
	local n = (_G.GetMerchantNumItems and _G.GetMerchantNumItems()) or 0
	p('merchant items:', n)
	for i = 1, n do
		local nm = MerchantItemName(i)
		if nm then
			local rename, color = Classify(nm)
			p(('  %d: %s%s'):format(i, nm,
				color and (' |cff00ff00-> ' .. tostring(rename) .. '|r')
				or (rename and (' -> ' .. tostring(rename) .. ' (dimmed)') or '')))
		else
			p(('  %d: <name unavailable>'):format(i))
		end
	end
	local CG = _G.C_GossipInfo
	local opts = CG and CG.GetOptions and CG.GetOptions()
	if opts and #opts > 0 then
		p('gossip options:')
		for _, o in ipairs(opts) do
			p(('  id=%s  %s'):format(tostring(o.gossipOptionID), tostring(o.name)))
		end
	end
end
