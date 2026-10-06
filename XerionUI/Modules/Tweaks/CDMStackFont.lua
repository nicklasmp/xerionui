--------------------------------------------------------------------------------
-- Cooldown Manager stack font
-- A separate font for the stack and charge counts of EllesmereUI's Cooldown
-- Manager: the icon bars (buff stacks, spell charges, item counts), the
-- Tracked Buff Bars and the custom buff bars. The cooldown numbers, keybinds
-- and names keep EllesmereUI's font.
--
-- EllesmereUI styles every one of those texts through two global helpers,
-- EllesmereUI.ApplyIconTextFont and EllesmereUI.ApplyModuleFont, with the same
-- "cdm" font for all of them. Both are wrapped: for the "cdm" key, and only
-- when the text is recognised as a stack text, our font replaces the path;
-- size, outline and color stay EllesmereUI's. A text is a stack text when it
--   * is a Blizzard CDM frame's Applications / ChargeCount.Current text,
--   * is an item or custom-spell count text of an icon,
--   * is the stacks text of a Tracked Buff Bar, or
--   * is the first of the two texts on an AuraKit carrier (stack, duration) -
--     the custom buff bars.
-- The wrappers stay installed and pass everything through while idle; the bars
-- are restyled when the choice changes or the module is switched off.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI

local M = XUI:NewModule("EUICDMStackFont", {
	name = "Cooldown Manager Stack Font",
	desc = "A separate font for the stack and charge counts of EllesmereUI's Cooldown Manager bars.",
	category = "tweaks",
	icon = [[Interface\Icons\INV_Misc_Gear_01]],
	order = 90,
	requires = "EllesmereUICooldownManager",
	defaults = {
		face = "GothamNarrowBlack",
	},
})

local KEY = "cdm"
local active = false
local wrapped = false
local seen = 0

local function OurPath()
	return XUI.Media:Fetch("font", M.db.face)
end

local function IsStackText(fs)
	local ok, result = pcall(function()
		local p = fs:GetParent()
		if not p then return false end
		if p.Applications == fs or p.Current == fs or p._itemCountText == fs or p._castCountText == fs then
			return true
		end
		local gp = p:GetParent()
		if gp and (gp._itemCountText == fs or gp._castCountText == fs) then return true end
		-- the Tracked Buff Bar's text overlay hangs off the bar's wrapper frame
		if gp and gp._stacksText == fs then return true end
		-- AuraKit carrier: stack text first, duration text second
		if p:GetNumRegions() == 2 and (p:GetRegions()) == fs then return true end
		return false
	end)
	return ok and result
end

local function Wrap()
	if wrapped then return end
	local E = _G.EllesmereUI
	if type(E) ~= "table" or type(E.ApplyIconTextFont) ~= "function" then return end
	wrapped = true
	local icon, module = E.ApplyIconTextFont, E.ApplyModuleFont
	E.ApplyIconTextFont = function(fs, path, size, key, ...)
		if active and key == KEY and fs and IsStackText(fs) then
			path = OurPath()
			seen = seen + 1
		end
		return icon(fs, path, size, key, ...)
	end
	if type(module) == "function" then
		E.ApplyModuleFont = function(fs, path, size, key, ...)
			if active and key == KEY and fs and IsStackText(fs) then
				path = OurPath()
				seen = seen + 1
			end
			return module(fs, path, size, key, ...)
		end
	end
end

local function Restyle()
	local ns = XUI.EUI and XUI.EUI.Module("EllesmereUICooldownManager")
	if not ns then return end
	if type(ns.RefreshCDMIconAppearance) == "function" and type(ns.barDataByKey) == "table" then
		for barKey in pairs(ns.barDataByKey) do
			pcall(ns.RefreshCDMIconAppearance, barKey)
		end
	end
	if type(ns.BuildTrackedBuffBars) == "function" then
		pcall(ns.BuildTrackedBuffBars)
	end
end

function M:OnEnable()
	active = true
	Wrap()
	Restyle()
	-- the bars are built a moment after login
	self:After(2, Restyle)
end

function M:OnDisable()
	active = false
	Restyle()
end

function M:OnRefresh()
	if active then Restyle() end
end

function M:DebugInfo()
	local ns = XUI.EUI and XUI.EUI.Module("EllesmereUICooldownManager")
	return {
		"wrappers installed: " .. tostring(wrapped),
		"stack texts given our font so far: " .. seen,
		"bar data reachable: " .. tostring(ns and type(ns.barDataByKey) == "table"),
		"font: " .. tostring(OurPath()),
	}
end
