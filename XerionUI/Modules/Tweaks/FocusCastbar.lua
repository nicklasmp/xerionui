--------------------------------------------------------------------------------
-- Focus Cast Bar background
-- Tints the empty background behind EllesmereUI Mythic+ Tools' standalone
-- focus cast bar - NOT the focus cast bar of the unit frames. The Mythic+ Tools
-- module keeps its bar object private, so the bar is found from its saved
-- settings (width, height and the screen position of its centre) and its
-- StatusBar child, wherever and however it is anchored.
--
-- The background is the large texture behind the fill. Rather than painting it
-- once and hoping, the texture's own color setters are hooked, so whenever
-- EllesmereUI recolors it (a rebuild, a new cast, a profile change) our color
-- goes straight back on. The hook is installed once per texture and does
-- nothing while the module is off.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI

local M = XUI:NewModule("EUIFocusCastbar", {
	name = "Focus Cast Bar",
	desc = "A custom background color for the Mythic+ Tools focus cast bar (not the unit frames' one).",
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

local why -- why the bar was not found, for /xui debug
local bar, bgTexture

-- the centre of a frame as an offset from the centre of the screen, in UIParent units
local function CenterOffset(frame)
	local cx, cy = frame:GetCenter()
	local ux, uy = UIParent:GetCenter()
	if not (cx and ux) then return nil end
	local k = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return cx * k - ux, cy * k - uy
end

local function HasStatusBar(frame)
	for _, child in ipairs({ frame:GetChildren() }) do
		if child.GetObjectType and child:GetObjectType() == "StatusBar" then return true end
	end
	return false
end

local function Matches(frame, width, height, x, y)
	if not frame.GetWidth or (frame.IsForbidden and frame:IsForbidden()) then return false end
	if math.abs((frame:GetWidth() or 0) - width) > 1 or math.abs((frame:GetHeight() or 0) - height) > 1 then return false end
	local fx, fy = CenterOffset(frame)
	if not fx or math.abs(fx - x) > 3 or math.abs(fy - y) > 3 then return false end
	return HasStatusBar(frame)
end

local function FindBar()
	local focus = FocusSettings()
	if not focus then why = "EllesmereUI Mythic+ Tools has no focus cast bar settings" return nil end
	if focus.enabled == false then why = "the focus cast bar is switched off in EllesmereUI" return nil end
	local pos = focus.pos
	local x, y = pos and pos.centerX or 0, pos and pos.centerY or -310
	local width, height = focus.width or 260, focus.height or 22
	if bar and Matches(bar, width, height, x, y) then return bar end
	bar, bgTexture = nil, nil
	-- every frame, not only UIParent's children: the bar may hang off a holder
	local frame = EnumerateFrames()
	while frame do
		if Matches(frame, width, height, x, y) then
			bar = frame
			why = "found"
			return bar
		end
		frame = EnumerateFrames(frame)
	end
	why = ("no frame of %dx%d centred at %d,%d with a status bar"):format(width, height, x, y)
	return nil
end

-- The background: the biggest texture of the holder that is not the fill,
-- lowest layer first.
local LAYER_RANK = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
local function FindBackground(holder)
	local best, bestRank
	local w, h = holder:GetWidth(), holder:GetHeight()
	for _, region in ipairs({ holder:GetRegions() }) do
		if region.SetColorTexture and region.GetDrawLayer then
			local rw, rh = region:GetWidth(), region:GetHeight()
			if rw and rh and rw >= w * 0.9 and rh >= h * 0.9 then
				local rank = LAYER_RANK[region:GetDrawLayer()] or 9
				if not best or rank < bestRank then best, bestRank = region, rank end
			end
		end
	end
	if best then return best end
	-- the original assumption: the first region is the background
	local first = holder:GetRegions()
	if first and first.SetColorTexture then return first end
	return nil
end

local hooked = setmetatable({}, { __mode = "k" })
local guard = false

local function Apply(tex)
	guard = true
	tex:SetColorTexture(XUI.UnpackColor(M.db.color))
	guard = false
end

local function Hook(tex)
	if hooked[tex] then return end
	hooked[tex] = true
	local function reapply(t)
		if guard or not M.running then return end
		Apply(t)
	end
	hooksecurefunc(tex, "SetColorTexture", reapply)
	hooksecurefunc(tex, "SetVertexColor", reapply)
	hooksecurefunc(tex, "SetTexture", reapply)
end

local function Paint(on)
	local holder = FindBar()
	if not holder then return end
	if not (bgTexture and bgTexture:GetParent() == holder) then bgTexture = FindBackground(holder) end
	if not bgTexture then why = "found the bar but not its background texture" return end
	if on then
		Hook(bgTexture)
		Apply(bgTexture)
	else
		guard = true
		bgTexture:SetColorTexture(0, 0, 0, 0.45) -- EllesmereUI's own
		guard = false
	end
end

-- the bar may be built a moment after the focus changes or after login
local function PaintSoon(self)
	self:After(0, function() Paint(true) end)
	self:After(0.3, function() Paint(true) end)
	self:After(1, function() Paint(true) end)
end

function M:OnEnable()
	local mod = XUI.EUI and XUI.EUI.Module("EllesmereUIMythicTimer")
	if mod and type(mod.TFB_Refresh) == "function" then
		self:SecureHook(mod, "TFB_Refresh", PaintSoon)
	end
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(self) self:After(1, function() Paint(true) end) end)
	self:RegisterEvent("PLAYER_FOCUS_CHANGED", PaintSoon)
	self:RegisterUnitEvent("UNIT_SPELLCAST_START", "focus", PaintSoon)
	self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "focus", PaintSoon)
	Paint(true)
	PaintSoon(self)
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
	s:SetSize(focus and focus.width or 260, focus and focus.height or 22)
	s:ClearAllPoints()
	s:SetPoint("CENTER", UIParent, "CENTER", 0, -250)
	s.bg:SetColorTexture(XUI.UnpackColor(self.db.color))
	s.border:Apply({ useGlobal = false, style = "SOLID", size = 1, color = { 0, 0, 0, 1 } })
	s:SetShown(self:IsPreview())
end

function M:DebugInfo()
	local mod = XUI.EUI and XUI.EUI.Module("EllesmereUIMythicTimer")
	local holder = FindBar()
	local focus = FocusSettings()
	local out = {
		("Mythic+ Tools namespace: %s, TFB_Refresh: %s"):format(tostring(mod ~= nil), tostring(mod and type(mod.TFB_Refresh))),
		("settings: enabled %s, size %sx%s, centre %s,%s"):format(
			tostring(focus and focus.enabled), tostring(focus and focus.width), tostring(focus and focus.height),
			tostring(focus and focus.pos and focus.pos.centerX), tostring(focus and focus.pos and focus.pos.centerY)),
		("bar: %s"):format(tostring(why)),
	}
	if holder then
		local bg = bgTexture or FindBackground(holder)
		out[#out + 1] = ("background texture: %s, hooked: %s"):format(tostring(bg ~= nil), tostring(bg and hooked[bg] or false))
	end
	return out
end
