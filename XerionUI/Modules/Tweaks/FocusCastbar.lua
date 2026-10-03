--------------------------------------------------------------------------------
-- Focus Cast Bar background
-- Tints the empty background behind EllesmereUI Mythic+ Tools' standalone
-- focus cast bar (not the unit frames' one). The module keeps its bar object
-- private, so the holder is found by its saved position and size and its
-- StatusBar child, and its first region (the background) is recoloured after
-- every refresh of that module.
--
-- EllesmereUI recolours the background itself whenever the bar is rebuilt or
-- starts a cast, so the tint is also re-applied a moment after the focus
-- changes or casts.
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

local found -- why FindBar last failed, for /xui debug

local function Matches(frame, width, height, x, y)
	if not (frame and frame.GetWidth) then return false end
	if math.abs((frame:GetWidth() or 0) - width) >= 0.5 or math.abs((frame:GetHeight() or 0) - height) >= 0.5 then return false end
	local point, relative, relativePoint, fx, fy = frame:GetPoint(1)
	if not (point == "CENTER" and relative == UIParent and relativePoint == "CENTER") then return false end
	if math.abs((fx or 0) - x) >= 0.5 or math.abs((fy or 0) - y) >= 0.5 then return false end
	for _, child in ipairs({ frame:GetChildren() }) do
		if child.GetObjectType and child:GetObjectType() == "StatusBar" then return true end
	end
	return false
end

local bar
local function FindBar()
	local focus = FocusSettings()
	if not focus then found = "EllesmereUI Mythic+ Tools has no focus cast bar settings" return nil end
	if focus.enabled ~= true then found = "the focus cast bar is switched off in EllesmereUI" return nil end
	local pos = focus.pos
	local x, y = pos and pos.centerX or 0, pos and pos.centerY or -310
	local width, height = focus.width or 260, focus.height or 22
	if bar and Matches(bar, width, height, x, y) then return bar end
	bar = nil
	for _, frame in ipairs({ UIParent:GetChildren() }) do
		if Matches(frame, width, height, x, y) then
			bar = frame
			found = "found"
			return bar
		end
	end
	found = ("no frame of %dx%d at %d,%d"):format(width, height, x, y)
	return nil
end

local function Paint(on)
	local holder = FindBar()
	local bg = holder and holder:GetRegions()
	if not (bg and bg.SetColorTexture) then return end
	if on then
		bg:SetColorTexture(XUI.UnpackColor(M.db.color))
	else
		bg:SetColorTexture(0, 0, 0, 0.45) -- EllesmereUI's own
	end
end

-- EllesmereUI repaints on its own schedule; look again right after and once
-- more a moment later
local function PaintSoon(self)
	self:After(0, function() Paint(true) end)
	self:After(0.3, function() Paint(true) end)
end

function M:OnEnable()
	local mod = XUI.EUI and XUI.EUI.Module("EllesmereUIMythicTimer")
	if mod and type(mod.TFB_Refresh) == "function" then
		self:SecureHook(mod, "TFB_Refresh", PaintSoon)
	end
	-- the bar may only be built a moment after login
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(self) self:After(1, function() Paint(true) end) end)
	self:RegisterEvent("PLAYER_FOCUS_CHANGED", PaintSoon)
	self:RegisterUnitEvent("UNIT_SPELLCAST_START", "focus", PaintSoon)
	self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "focus", PaintSoon)
	Paint(true)
end

function M:OnDisable()
	Paint(false)
end

-- The sample: a bar of our own in the middle of the screen with the chosen
-- background, because EllesmereUI's real bar only exists with a focus.
local sample
local function Sample()
	if sample then return sample end
	sample = CreateFrame("Frame", "XUI_FocusCastbarSample", UIParent)
	sample:SetFrameStrata("HIGH")
	sample.bg = sample:CreateTexture(nil, "BACKGROUND")
	sample.bg:SetAllPoints()
	sample.bar = CreateFrame("StatusBar", nil, sample)
	sample.bar:SetStatusBarTexture([[Interface\Buttons\WHITE8X8]])
	sample.bar:SetStatusBarColor(0.85, 0.85, 0.2, 1)
	sample.bar:SetMinMaxValues(0, 1)
	sample.bar:SetValue(0.6)
	sample.bar:SetAllPoints()
	sample.border = XUI.Style:Border(sample.bar)
	sample.text = sample.bar:CreateFontString(nil, "OVERLAY")
	XUI.Style:ApplyFont(sample.text, nil, 12)
	sample.text:SetPoint("LEFT", 6, 0)
	sample.text:SetText("Polymorph")
	sample:Hide()
	return sample
end

function M:OnRefresh()
	if self.running then Paint(true) end
	if not (sample or self:IsPreview()) then return end
	local s = Sample()
	local focus = FocusSettings()
	local w, h = focus and focus.width or 260, focus and focus.height or 22
	s:SetSize(w, h)
	s:ClearAllPoints()
	s:SetPoint("CENTER", UIParent, "CENTER", 0, -250)
	s.bg:SetColorTexture(XUI.UnpackColor(self.db.color))
	s.border:Apply({ useGlobal = false, style = "SOLID", size = 1, color = { 0, 0, 0, 1 } })
	s:SetShown(self:IsPreview())
end

function M:DebugInfo()
	local mod = XUI.EUI and XUI.EUI.Module("EllesmereUIMythicTimer")
	FindBar()
	return {
		("EllesmereUIMythicTimer namespace: %s, TFB_Refresh: %s"):format(tostring(mod ~= nil), tostring(mod and type(mod.TFB_Refresh))),
		("focus bar: %s"):format(tostring(found)),
	}
end
