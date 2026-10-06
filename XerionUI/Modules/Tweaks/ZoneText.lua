--------------------------------------------------------------------------------
-- Zone text
-- Font, outline and size of Blizzard's zone announcements (the big "Sanctum of
-- Light" / "The Bazaar" / "(Sanctuary)" text that fades in when you cross a
-- border). The strings are Blizzard's own - ZoneTextString, SubZoneTextString,
-- PVPInfoTextString and PVPArenaTextString - so no other addon is involved.
--
-- Blizzard picks the text and its color every time a zone is entered
-- (SetZoneText), so that function is hooked and our font is applied right after
-- it; the color Blizzard chose is kept. The original font of every string is
-- remembered and put back when the module is switched off.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates
local Style = XUI.Style

local M = XUI:NewModule("ZoneText", {
	name = "Zone Text",
	desc = "Change the font, outline and size of the zone announcement text.",
	category = "tweaks",
	icon = [[Interface\Icons\INV_Misc_Map_01]],
	order = 100,
	defaults = {
		font = T.Font(12, { useGlobal = false, outline = "SLUGOUTLINE" }),
		scale = 100,
	},
})

local NAMES = { "ZoneTextString", "SubZoneTextString", "PVPInfoTextString", "PVPArenaTextString" }
local original = {}

local function Strings()
	local out = {}
	for i = 1, #NAMES do
		local fs = _G[NAMES[i]]
		if fs and fs.SetFont then out[#out + 1] = fs end
	end
	return out
end

local function Remember(fs)
	local name = fs:GetName()
	if original[name] then return original[name] end
	local path, size, flags = fs:GetFont()
	if not path then return nil end
	original[name] = { path = path, size = size, flags = flags }
	return original[name]
end

local function Apply()
	if not M.running then return end
	local scale = (M.db.scale or 100) / 100
	for _, fs in ipairs(Strings()) do
		local o = Remember(fs)
		if o then
			local r, g, b, a = fs:GetTextColor()
			Style:ApplyFont(fs, M.db.font, math.max(1, o.size * scale))
			fs:SetTextColor(r, g, b, a)
		end
	end
end

local function Restore()
	for _, fs in ipairs(Strings()) do
		local o = original[fs:GetName()]
		if o then
			fs:SetFont(o.path, o.size, o.flags)
			fs.__xuiFont = nil
		end
	end
end

function M:OnEnable()
	if type(_G.SetZoneText) == "function" then self:SecureHook("SetZoneText", Apply) end
	Apply()
end

function M:OnDisable()
	Restore()
end

function M:OnRefresh()
	Apply()
end

-- Shows a sample announcement so the choice can be judged without travelling.
function M:Test()
	local frame = _G.ZoneTextFrame
	if not frame or not _G.ZoneTextString then return end
	pcall(function()
		ZoneTextString:SetText("Sanctum of Light")
		if SubZoneTextString then SubZoneTextString:SetText("The Bazaar") end
		if PVPInfoTextString then PVPInfoTextString:SetText("(Sanctuary)") end
		Apply()
		if type(FadingFrame_Show) == "function" then FadingFrame_Show(frame) else frame:Show() end
	end)
end

function M:DebugInfo()
	local out = {}
	for _, fs in ipairs(Strings()) do
		local path, size, flags = fs:GetFont()
		out[#out + 1] = ("%s: %s %s %s"):format(fs:GetName(), tostring(path), tostring(size), tostring(flags))
	end
	if #out == 0 then out[1] = "no zone text strings found" end
	return out
end
