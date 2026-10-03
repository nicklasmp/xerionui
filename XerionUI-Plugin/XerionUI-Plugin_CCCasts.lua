-- Short, independent notifications for major party CC casts. Unlike the CC
-- Tracker, this reports the cast event itself and does not inspect enemy auras.
local _, ns = ...
local CreateFrame, UIParent, GetTime = CreateFrame, UIParent, GetTime
local UnitName, IsInRaid, IsInGroup, GetNumGroupMembers = UnitName, IsInRaid, IsInGroup, GetNumGroupMembers
local ipairs, pairs, type, tonumber, unpack = ipairs, pairs, type, tonumber, unpack
local format, max, min = string.format, math.max, math.min
local IsSecret = ns.IsSecret

local DURATION = 5
local SPELLS = {
	[192058] = { key = 'cap', label = 'Cap Totem', color = { 0.22, 0.24, 0.83 } },
	[202137] = { key = 'silence', label = 'DH Silence', color = { 0.09, 0.75, 0.83 } },
	[30283]  = { key = 'fury', label = 'Shadowfury', color = { 0.47, 0.31, 0.70 } },
}
-- Aura IDs are included too in case a client reports the debuff identity for
-- UNIT_SPELLCAST_SUCCEEDED in a compatibility path.
SPELLS[118905] = SPELLS[192058]
SPELLS[204490] = SPELLS[202137]
local DEFAULTS = { enable = false, lock = false, x = 0, y = -30, duration = DURATION, width = 250, height = 24, spacing = 3, grow = 'DOWN' }
local function GetCfg() return ns.ModuleCfg('ccCastNotices', DEFAULTS) end
ns.hasCCCastNotices = true
ns.CCCastGetCfg = GetCfg

local rows, frame, preview = {}, nil, false
local order = { 'cap', 'silence', 'fury' }
local byKey = { cap = SPELLS[192058], silence = SPELLS[202137], fury = SPELLS[30283] }

local function Tick()
	local now, any, cfg = GetTime(), false, GetCfg()
	for _, key in ipairs(order) do
		local row = rows[key]
		if row and row.expires then
			local left = row.expires - now
			if left <= 0 and not preview then
				row.expires = nil
				row:Hide()
			else
				any = true
				row.timer:SetText(format('%.1f', max(0, left)))
				row.bar:SetMinMaxValues(0, max(1, cfg.duration or DURATION))
				row.bar:SetValue(max(0, left))
			end
		end
	end
	if any or preview then
		frame:Show()
	else
		frame:SetScript('OnUpdate', nil)
		frame:Hide()
	end
end

local function EnsureFrame()
	if frame then return end
	frame = CreateFrame('Frame', 'XerionUI_CCCastNotices', UIParent)
	frame:SetSize(250, 24)
	frame:SetFrameStrata('MEDIUM')
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:RegisterForDrag('RightButton')
	for i, key in ipairs(order) do
		local info = byKey[key]
		local row = CreateFrame('Frame', nil, frame)
		row:Hide()
		row.bg = row:CreateTexture(nil, 'BACKGROUND')
		row.bg:SetAllPoints()
		row.bg:SetColorTexture(0, 0, 0, 0.8)
		row.bar = CreateFrame('StatusBar', nil, row)
		row.bar:SetAllPoints(row)
		row.bar:SetStatusBarTexture('Interface\\Buttons\\WHITE8x8')
		row.bar:SetStatusBarColor(info.color[1], info.color[2], info.color[3], 0.55)
		row.name = row:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
		row.name:SetPoint('LEFT', 6, 0)
		row.caster = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
		row.caster:SetPoint('LEFT', row.name, 'RIGHT', 8, 0)
		row.timer = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
		row.timer:SetPoint('RIGHT', -6, 0)
		row:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, -(i - 1) * 27)
		rows[key] = row
	end
	ns.MakeDraggable(frame, GetCfg, 'x', 'y', function()
		local cfg = GetCfg()
		frame:ClearAllPoints()
		frame:SetPoint('CENTER', UIParent, 'CENTER', cfg.x or 0, cfg.y or -30)
	end)
end

local function Layout()
	local cfg = GetCfg()
	EnsureFrame()
	frame:ClearAllPoints()
	frame:SetPoint('CENTER', UIParent, 'CENTER', cfg.x or 0, cfg.y or -30)
	frame:SetSize(cfg.width or 250, cfg.height or 24)
	frame:EnableMouse(preview and not cfg.lock or false)
	local y = 0
	for _, key in ipairs(order) do
		local row = rows[key]
		row:ClearAllPoints()
		row:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, -y)
		row:SetSize(cfg.width or 250, cfg.height or 24)
		y = y + (cfg.height or 24) + (cfg.spacing or 3)
		if preview then
			local info = byKey[key]
			row.name:SetText(info.label)
			row.caster:SetText('Playername')
			row.timer:SetText(format('%.1f', cfg.duration or DURATION))
			row.expires = GetTime() + (cfg.duration or DURATION)
		row:Show()
		end
	end
	frame:SetHeight(max(1, y - (cfg.spacing or 3)))
	local active = preview
	for _, row in pairs(rows) do
		if row.expires then active = true break end
	end
	if not cfg.enable and not preview then
		for _, row in pairs(rows) do row.expires = nil; row:Hide() end
		active = false
	end
	if active then
		frame:SetScript('OnUpdate', Tick)
	else
		frame:SetScript('OnUpdate', nil)
		frame:Hide()
	end
end

ns.CCCastApply = Layout
ns.CCCastIsPreview = function() return preview end
ns.CCCastSetPreview = function(on)
	preview = on == true
	if preview then
		Layout()
	else
		for _, row in pairs(rows) do row.expires = nil; row:Hide() end
		Layout()
	end
end

local function Tokens()
	local out = {}
	if IsInRaid() then
		for i = 1, min(40, GetNumGroupMembers() or 0) do out[#out + 1] = 'raid' .. i end
	else
		out[1] = 'player'
		if IsInGroup() then
		for i = 1, 4 do out[#out + 1] = 'party' .. i end
		end
	end
	return out
end

local watch = CreateFrame('Frame')
local function Register()
	watch:UnregisterAllEvents()
	if not GetCfg().enable then return end
	local tokens = Tokens()
	watch:RegisterEvent('GROUP_ROSTER_UPDATE')
	watch:RegisterUnitEvent('UNIT_SPELLCAST_SUCCEEDED', unpack(tokens))
end
watch:SetScript('OnEvent', function(_, event, unit, _, spellID)
	if event == 'GROUP_ROSTER_UPDATE' then Register(); return end
	if not GetCfg().enable then return end
	-- Midnight can redact cast identifiers for party units. Never use one of
	-- those secret values as a Lua table key (or pass it through tonumber).
	if IsSecret and IsSecret(spellID) then return end
	if type(spellID) ~= 'number' then spellID = tonumber(spellID) end
	if IsSecret and IsSecret(spellID) then return end
	local info = spellID and SPELLS[spellID]
	if not info then return end
	Layout()
	local row = rows[info.key]
	local caster = UnitName(unit) or unit
	local duration = GetCfg().duration or DURATION
	row.name:SetText(info.label)
	row.caster:SetText(caster)
	row.timer:SetText(format('%.1f', duration))
	row.expires = GetTime() + duration
	row:Show()
	frame:SetScript('OnUpdate', Tick)
	frame:Show()
end)
ns.CCCastApply = function()
	Layout()
	Register()
end
Register()
