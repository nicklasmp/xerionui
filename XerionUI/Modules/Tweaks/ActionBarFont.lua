--------------------------------------------------------------------------------
-- Action bar font
-- Chooses the font of EllesmereUI's action bars (keybinds, stack counts, macro
-- names, cooldown numbers and the data bar texts) separately from the font
-- EllesmereUI uses everywhere else.
--
-- EllesmereUI asks EllesmereUI.GetFontPath("actionBars") every time it styles a
-- button, so that one answer is wrapped: while this module runs it returns our
-- font for that key and passes every other key straight through. The wrapper
-- stays installed (harmless when idle) and the bars are restyled whenever the
-- choice changes or the module is switched off.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates
local Style = XUI.Style

local M = XUI:NewModule("EUIActionBarFont", {
	name = "Action Bar Font",
	desc = "A separate font for EllesmereUI's action bars (keybinds, counts, cooldown numbers).",
	category = "tweaks",
	icon = [[Interface\Icons\INV_Misc_Note_01]],
	order = 70,
	requires = "EllesmereUIActionBars",
	defaults = {
		font = T.Font(12, { useGlobal = false }),
	},
})

local KEY = "actionBars"
local wrapped = false

local function Active()
	return M.running and M.db and M.db.font
end

local function Wrap()
	if wrapped then return end
	local E = _G.EllesmereUI
	if type(E) ~= "table" or type(E.GetFontPath) ~= "function" then return end
	wrapped = true
	local path, outline = E.GetFontPath, E.GetFontOutlineFlag
	E.GetFontPath = function(key, ...)
		local block = key == KEY and Active()
		if block then
			local f = Style:Resolve("font", block)
			return XUI.Media:Fetch("font", f.face)
		end
		return path(key, ...)
	end
	if type(outline) == "function" then
		E.GetFontOutlineFlag = function(key, ...)
			local block = key == KEY and Active()
			if block then return Style:FontFlags(Style:Resolve("font", block)) end
			return outline(key, ...)
		end
	end
end

local function Restyle()
	local ns = XUI.EUI and XUI.EUI.Module("EllesmereUIActionBars")
	local EAB = ns and ns.EAB
	if EAB and type(EAB.ApplyFonts) == "function" then
		pcall(EAB.ApplyFonts, EAB)
	end
end

function M:OnEnable()
	Wrap()
	Restyle()
	-- the bars are built a moment after login
	self:After(2, Restyle)
end

function M:OnDisable()
	-- running is already false here, so the wrapper answers EllesmereUI's own font
	Restyle()
end

function M:OnRefresh()
	if self.running then Restyle() end
end

function M:DebugInfo()
	local ns = XUI.EUI and XUI.EUI.Module("EllesmereUIActionBars")
	local f = Style:Resolve("font", self.db.font)
	return {
		"wrapper installed: " .. tostring(wrapped),
		"EllesmereUI action bars reachable: " .. tostring(ns and ns.EAB and ns.EAB.ApplyFonts ~= nil),
		"font: " .. tostring(XUI.Media:Fetch("font", f.face)),
	}
end
