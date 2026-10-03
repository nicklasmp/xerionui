--------------------------------------------------------------------------------
-- Focus Cast Bar background
-- Tints the empty background behind EllesmereUI Mythic+ Tools' standalone
-- focus cast bar (not the unit frames' one). The module keeps its bar object
-- private, so the holder is found by its saved position and size and its
-- StatusBar child, and its first region (the background) is recoloured after
-- every refresh of that module.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI

local M = XUI:NewModule("EUIFocusCastbar", {
	name = "Focus Cast Bar",
	desc = "A custom background colour for EllesmereUI Mythic+ Tools' focus cast bar.",
	category = "tweaks",
	icon = [[Interface\Icons\Spell_Nature_Polymorph]],
	order = 30,
	requires = "EllesmereUIMythicTimer",
	defaults = {
		color = { 0.08, 0.08, 0.08, 0.75 },
	},
})

local function FocusSettings()
	local db = _G._EMT_AceDB
	local prof = db and db.profile
	local tfb = prof and prof.tfb
	return tfb and tfb.focus
end

local function FindBar()
	local focus = FocusSettings()
	if not (focus and focus.enabled == true) then return nil end
	local pos = focus.pos
	local x, y = pos and pos.centerX or 0, pos and pos.centerY or -310
	local width, height = focus.width or 260, focus.height or 22
	for _, frame in ipairs({ UIParent:GetChildren() }) do
		if frame and frame.GetWidth and math.abs((frame:GetWidth() or 0) - width) < 0.1
			and math.abs((frame:GetHeight() or 0) - height) < 0.1 then
			local point, relative, relativePoint, fx, fy = frame:GetPoint(1)
			if point == "CENTER" and relative == UIParent and relativePoint == "CENTER"
				and math.abs((fx or 0) - x) < 0.1 and math.abs((fy or 0) - y) < 0.1 then
				for _, child in ipairs({ frame:GetChildren() }) do
					if child.GetObjectType and child:GetObjectType() == "StatusBar" then return frame end
				end
			end
		end
	end
	return nil
end

local function Paint(on)
	local bar = FindBar()
	local bg = bar and bar:GetRegions()
	if not (bg and bg.SetColorTexture) then return end
	if on then
		bg:SetColorTexture(XUI.UnpackColor(M.db.color))
	else
		bg:SetColorTexture(0, 0, 0, 0.45) -- EllesmereUI's own
	end
end

function M:OnEnable()
	local mod = XUI.EUI and XUI.EUI.Module("EllesmereUIMythicTimer")
	if mod and type(mod.TFB_Refresh) == "function" then
		self:SecureHook(mod, "TFB_Refresh", function(self) self:After(0, function() Paint(true) end) end)
	end
	-- the bar may only be built a moment after login
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(self) self:After(1, function() Paint(true) end) end)
end

function M:OnDisable()
	Paint(false)
end

function M:OnRefresh()
	if self.running then Paint(true) end
end
