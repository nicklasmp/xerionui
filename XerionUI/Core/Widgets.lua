--------------------------------------------------------------------------------
-- XerionUI - Core/Widgets.lua
-- The building blocks modules draw with: a text, an icon and a bar. Each one
-- takes its look from style blocks (Core/Style.lua), so two modules that show
-- an icon offer the same options and look alike out of the box.
--
-- Element settings, as stored in a module's db:
--   text:  font block                     { size, color, useGlobal, face, outline, ... }
--   icon:  { width, height, useGlobal, zoom }
--   bar:   { width, height, color, useGlobal, texture, bgColor }
--   border / glow / background: their style blocks
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local Style = XUI.Style

local Widgets = {}
XUI.Widgets = Widgets

local max = math.max

local function TextWidth(fs)
	return fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
end

--------------------------------------------------------------------------------
-- Text: a frame that is exactly as large as its text, so movers outline it.
--------------------------------------------------------------------------------
local TextMixin = {}

function TextMixin:Fit()
	local w = max(1, TextWidth(self.text) or 0)
	local h = max(1, self.text:GetStringHeight() or 0)
	if self.__w ~= w or self.__h ~= h then
		self.__w, self.__h = w, h
		self:SetSize(w, h)
	end
end

function TextMixin:SetText(s)
	self.text:SetText(s)
	self:Fit()
end

function TextMixin:SetTextColor(r, g, b, a)
	self.text:SetTextColor(r, g, b, a)
end

function TextMixin:ApplyStyle(fontBlock)
	Style:ApplyFont(self.text, fontBlock)
	self:Fit()
end

function Widgets:CreateText(name, parent)
	local f = CreateFrame("Frame", name, parent or UIParent)
	f:SetSize(1, 1)
	f.text = f:CreateFontString(nil, "OVERLAY")
	f.text:SetPoint("CENTER")
	f.text:SetWordWrap(false)
	Mixin(f, TextMixin)
	-- give the string a font before anything sets text on it
	Style:ApplyFont(f.text, nil, 12)
	return f
end

--------------------------------------------------------------------------------
-- Icon: art + optional cooldown swipe + border + glow + timer/count texts.
--------------------------------------------------------------------------------
local IconMixin = {}

function IconMixin:SetIcon(texture)
	self.icon:SetTexture(texture)
end

function IconMixin:SetDesaturated(on)
	self.icon:SetDesaturated(on and true or false)
end

-- The cooldown swipe, made on first use.
function IconMixin:GetCooldown()
	local cd = self.cooldown
	if not cd then
		cd = CreateFrame("Cooldown", nil, self, "CooldownFrameTemplate")
		cd:SetDrawEdge(false)
		cd:SetHideCountdownNumbers(true)
		self.cooldown = cd
		self:LayoutContent()
	end
	return cd
end

function IconMixin:LayoutContent()
	local inset = self.border:GetInset()
	self.icon:ClearAllPoints()
	self.icon:SetPoint("TOPLEFT", inset, -inset)
	self.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
	if self.cooldown then
		self.cooldown:ClearAllPoints()
		self.cooldown:SetPoint("TOPLEFT", inset, -inset)
		self.cooldown:SetPoint("BOTTOMRIGHT", -inset, inset)
	end
	self.overlay:SetFrameLevel(self:GetFrameLevel() + 5)
end

-- iconBlock: { width, height, useGlobal, zoom }; borderBlock: border style block.
function IconMixin:ApplyLayout(iconBlock, borderBlock)
	local i = Style:Resolve("icon", iconBlock)
	local w = i.width or i.size or 36
	local h = i.height or i.size or w
	self:SetSize(w, h)
	self.border:Apply(borderBlock)
	self:LayoutContent()
	Style:IconTexCoord(self.icon, w, h, i.zoom)
end

function IconMixin:SetGlow(glowBlock, shown)
	Style:SetGlow(self, glowBlock, shown)
end

-- fontBlock may carry enabled/anchor/x/y next to its font fields.
local function ApplyIconText(self, fs, block, defaultAnchor)
	if type(block) == "table" and block.enabled == false then
		fs:Hide()
		return false
	end
	Style:ApplyFont(fs, block)
	local anchor = (type(block) == "table" and block.anchor) or defaultAnchor
	fs:ClearAllPoints()
	fs:SetPoint(anchor, self, anchor, type(block) == "table" and block.x or 0, type(block) == "table" and block.y or 0)
	fs:Show()
	return true
end

function IconMixin:ApplyTimerText(block)
	return ApplyIconText(self, self.timer, block, "CENTER")
end

function IconMixin:ApplyCountText(block)
	return ApplyIconText(self, self.count, block, "BOTTOMRIGHT")
end

function Widgets:CreateIcon(name, parent)
	local f = CreateFrame("Frame", name, parent or UIParent)
	f:SetSize(36, 36)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetTexture(134400)
	f.border = Style:Border(f)
	-- texts sit above the swipe and the border
	f.overlay = CreateFrame("Frame", nil, f)
	f.overlay:SetAllPoints()
	f.timer = f.overlay:CreateFontString(nil, "OVERLAY")
	f.count = f.overlay:CreateFontString(nil, "OVERLAY")
	Style:ApplyFont(f.timer, nil, 12)
	Style:ApplyFont(f.count, nil, 12)
	Mixin(f, IconMixin)
	f:LayoutContent()
	return f
end

--------------------------------------------------------------------------------
-- Bar: a status bar inside a border, with an optional icon and two texts.
--------------------------------------------------------------------------------
local BarMixin = {}

-- barBlock: { width, height, color, useGlobal, texture, bgColor }
-- iconSide: "LEFT", "RIGHT" or "NONE"
function BarMixin:ApplyLayout(barBlock, borderBlock, iconSide)
	local b = Style:Resolve("bar", barBlock)
	local w, h = b.width or 200, b.height or 20
	self:SetSize(w, h)
	local inset = self.border:Apply(borderBlock)
	Style:ApplyBar(self.bar, barBlock)

	local iconW = 0
	self.icon:ClearAllPoints()
	if iconSide == "LEFT" or iconSide == "RIGHT" then
		iconW = h - 2 * inset
		self.icon:SetSize(iconW, iconW)
		self.icon:SetPoint(iconSide == "LEFT" and "TOPLEFT" or "TOPRIGHT", self, iconSide == "LEFT" and "TOPLEFT" or "TOPRIGHT",
			iconSide == "LEFT" and inset or -inset, -inset)
		Style:IconTexCoord(self.icon, iconW, iconW)
		self.icon:Show()
	else
		self.icon:Hide()
	end

	self.bar:ClearAllPoints()
	local left = inset + ((iconSide == "LEFT") and iconW or 0)
	local right = inset + ((iconSide == "RIGHT") and iconW or 0)
	self.bar:SetPoint("TOPLEFT", self, "TOPLEFT", left, -inset)
	self.bar:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -right, inset)
	self.texts:SetFrameLevel(self.bar:GetFrameLevel() + 2)
end

function BarMixin:ApplyNameText(block)
	if type(block) == "table" and block.enabled == false then self.name:Hide() return end
	Style:ApplyFont(self.name, block)
	self.name:ClearAllPoints()
	self.name:SetPoint("LEFT", self.bar, "LEFT", 4, 0)
	self.name:SetPoint("RIGHT", self.time, "LEFT", -4, 0)
	self.name:SetJustifyH("LEFT")
	self.name:Show()
end

function BarMixin:ApplyTimeText(block)
	if type(block) == "table" and block.enabled == false then self.time:Hide() return end
	Style:ApplyFont(self.time, block)
	self.time:ClearAllPoints()
	self.time:SetPoint("RIGHT", self.bar, "RIGHT", -4, 0)
	self.time:Show()
end

function BarMixin:SetColor(r, g, b, a)
	self.bar:SetStatusBarColor(r, g, b, a or 1)
end

function Widgets:CreateBar(name, parent)
	local f = CreateFrame("Frame", name, parent or UIParent)
	f:SetSize(200, 20)
	f.bar = CreateFrame("StatusBar", nil, f)
	f.bar:SetMinMaxValues(0, 1)
	f.bar:SetValue(1)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.border = Style:Border(f)
	f.texts = CreateFrame("Frame", nil, f)
	f.texts:SetAllPoints(f)
	f.name = f.texts:CreateFontString(nil, "OVERLAY")
	f.time = f.texts:CreateFontString(nil, "OVERLAY")
	f.name:SetWordWrap(false)
	Style:ApplyFont(f.name, nil, 12)
	Style:ApplyFont(f.time, nil, 12)
	Mixin(f, BarMixin)
	return f
end

--------------------------------------------------------------------------------
-- Templates: default blocks for module settings. Using these keeps every
-- module's saved settings in the same shape the options panel expects.
--------------------------------------------------------------------------------
local T = {}
XUI.Templates = T

local function Merge(t, extra)
	if extra then
		for k, v in pairs(extra) do t[k] = v end
	end
	return t
end

function T.Position(x, y, strata)
	return { point = "CENTER", relPoint = "CENTER", x = x or 0, y = y or 0, strata = strata or "MEDIUM" }
end

-- A font block for one text element; `extra` adds fields such as color,
-- enabled, anchor, x, y.
function T.Font(size, extra)
	return Merge({ size = size or 14, useGlobal = true }, extra)
end

function T.Border(extra)
	return Merge({ useGlobal = true }, extra)
end

function T.Glow(enabled, extra)
	return Merge({ enabled = enabled and true or false, useGlobal = true }, extra)
end

function T.Icon(width, height, extra)
	return Merge({ width = width or 36, height = height or width or 36, useGlobal = true }, extra)
end

function T.Bar(width, height, extra)
	return Merge({ width = width or 200, height = height or 20, useGlobal = true }, extra)
end

function T.Background(extra)
	return Merge({ enabled = true, useGlobal = true }, extra)
end

function T.Alert(mode, extra)
	return Merge({
		mode = mode or "NONE",
		sound = "",
		channel = "Master",
		text = "",
		voice = "",
		volume = 100,
		rate = 0,
	}, extra)
end
