--------------------------------------------------------------------------------
-- Player Aura Bars tweaks
-- Two things EllesmereUI's Player Aura Bars cannot do on their own:
--   * Cropped icons - the same "Cropped" the action bars have under Custom
--     Button Shape: the icon is lower than it is wide and the picture is
--     trimmed top and bottom instead of squeezed.
--   * Stacks above the icon - centred just above it, like the party frame
--     debuffs.
--
-- The bars are drawn by EllesmereUI's AuraKit from style tables it keeps in
-- AuraKit.styles[key] and rebuilds on every settings change. That table is put
-- behind a proxy so each style written to a Player Aura Bars key (all of them
-- start with "playerAuraBars_") is adjusted on its way in; the styles already
-- there are adjusted in place and restyled. Nothing is written to
-- EllesmereUI's saved settings, so switching the module off puts everything
-- back. The proxy and the stack hook stay installed and do nothing while idle.
--
-- Cropped needs a bar without an icon shape (the shapes are square masks), and
-- the bar's grid still reserves a square cell per icon, so a cropped row sits
-- at the top of its cell.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI

local M = XUI:NewModule("EUIPlayerAuraBars", {
	name = "Player Aura Bars",
	desc = "Cropped icons and stacks above the icon on EllesmereUI's Player Aura Bars (buffs and debuffs).",
	category = "tweaks",
	icon = [[Interface\Icons\Spell_Holy_WordFortitude]],
	order = 80,
	requires = "EllesmereUIUnitFrames",
	defaults = {
		buffs = true,
		debuffs = false,
		crop = true,
		height = 80, -- icon height in percent of its width (EllesmereUI's cropped action buttons: 80)
		stackAbove = true,
		stackX = 0,
		stackY = 1,
	},
})

local PREFIX = "playerAuraBars_"
local active = false
local proxied = false
local realStyles
local origs = setmetatable({}, { __mode = "k" }) -- style -> { height, texCoord }
local ownCoords = setmetatable({}, { __mode = "k" }) -- texCoord tables made here

local function AK()
	local E = _G.EllesmereUI
	return type(E) == "table" and E.AuraKit or nil
end

local function IsPAB(key)
	return type(key) == "string" and key:sub(1, #PREFIX) == PREFIX
end

local function IsBuff(key)
	return not key:lower():find("debuff", 1, true)
end

local function Wanted(key)
	if not active then return false end
	if IsBuff(key) then return M.db.buffs end
	return M.db.debuffs
end

--------------------------------------------------------------------------------
-- Stacks: after EllesmereUI's own text pass, move the count when asked to
--------------------------------------------------------------------------------
local function WrapExtra(style, key)
	if style.__xuiWrapped or type(style.applyExtra) ~= "function" then return end
	local orig = style.applyExtra
	style.applyExtra = function(button, d, current)
		orig(button, d, current)
		if not (d and d.stack) then return end
		local db = M.db
		if Wanted(key) and db.stackAbove then
			-- stamped after the call: a refused SetPoint (secret auras) is retried next pass
			local want = ("%s|%s|%s"):format(tostring(d.pabStackAnchor), db.stackX, db.stackY)
			if d.xuiStackKey ~= want then
				d.stack:ClearAllPoints()
				if pcall(d.stack.SetPoint, d.stack, "BOTTOM", button, "TOP", db.stackX, db.stackY) then
					d.xuiStackKey = want
				end
			end
		elseif d.xuiStackKey then
			-- EllesmereUI only re-anchors when its own value changed: make it do so
			d.xuiStackKey = nil
			d.pabStackAnchor = nil
			orig(button, d, current)
		end
	end
	style.__xuiWrapped = true
end

--------------------------------------------------------------------------------
-- Crop: the style's height and texture coordinates, with the originals kept
--------------------------------------------------------------------------------
local function Adjust(key, style)
	if type(style) ~= "table" or not IsPAB(key) then return end
	WrapExtra(style, key)
	local o = origs[style]
	if not o then
		o = { height = style.height, texCoord = (not ownCoords[style.texCoord]) and style.texCoord or nil }
		origs[style] = o
	end
	local w = style.width
	local crop = Wanted(key) and M.db.crop and not style.iconShape and type(w) == "number" and w > 0
	if crop then
		local ratio = math.max(0.5, math.min(1, (M.db.height or 80) / 100))
		local z = style.iconZoom or 0.055
		local c = (1 - ratio) / 2
		local tc = { z, 1 - z, z + c, 1 - z - c }
		ownCoords[tc] = true
		style.height = math.floor(w * ratio + 0.5)
		style.texCoord = tc
	else
		style.height = o.height or style.height
		style.texCoord = o.texCoord
	end
end

local function Install()
	local ak = AK()
	if proxied or not (ak and type(ak.styles) == "table") then return end
	local real = ak.styles
	ak.styles = setmetatable({}, {
		__index = real,
		__newindex = function(_, key, style)
			Adjust(key, style)
			real[key] = style
		end,
	})
	realStyles = real
	proxied = true
end

local function AdjustAll()
	local ak = AK()
	if not (ak and realStyles) then return end
	for key, style in pairs(realStyles) do
		if IsPAB(key) then
			Adjust(key, style)
			if type(ak.RestyleSoon) == "function" then ak.RestyleSoon(key) end
		end
	end
end

function M:OnEnable()
	active = true
	Install()
	AdjustAll()
	-- the bars are built a moment after login
	self:After(2, AdjustAll)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() self:After(2, AdjustAll) end)
end

function M:OnDisable()
	active = false
	AdjustAll()
end

function M:OnRefresh()
	if active then AdjustAll() end
end

function M:DebugInfo()
	local n, cropped = 0, 0
	for key, style in pairs(realStyles or {}) do
		if IsPAB(key) then
			n = n + 1
			if ownCoords[style.texCoord] then cropped = cropped + 1 end
		end
	end
	return {
		"proxy installed: " .. tostring(proxied),
		("Player Aura Bars styles seen: %d, cropped: %d"):format(n, cropped),
	}
end
