--------------------------------------------------------------------------------
-- XerionUI_Options - Theme.lua
-- Palette, fonts and the few drawing helpers every control uses. The panel is
-- dark, flat and quiet: one typeface, one accent, icons over words.
--------------------------------------------------------------------------------
local XUI = _G.XerionUI
if not XUI then return end

local O = {}
XUI.Options = O

O.MEDIA = [[Interface\AddOns\XerionUI\Media\]]
O.WHITE = [[Interface\Buttons\WHITE8X8]]

O.C = {
	window       = { 0.078, 0.078, 0.078, 0.98 },
	sidebar      = { 0.059, 0.059, 0.059, 1 },
	header       = { 0.067, 0.067, 0.067, 1 },
	line         = { 0.145, 0.145, 0.145, 1 },
	card         = { 0.106, 0.106, 0.106, 1 },
	cardBorder   = { 0.150, 0.150, 0.150, 1 },
	control      = { 0.150, 0.150, 0.150, 1 },
	controlHover = { 0.195, 0.195, 0.195, 1 },
	controlLine  = { 0.230, 0.230, 0.230, 1 },
	track        = { 0.230, 0.230, 0.230, 1 },
	selected     = { 0.130, 0.130, 0.130, 1 },
	text         = { 0.93, 0.93, 0.93, 1 },
	label        = { 0.80, 0.80, 0.80, 1 },
	muted        = { 0.55, 0.55, 0.55, 1 },
	faint        = { 0.36, 0.36, 0.36, 1 },
	danger       = { 0.90, 0.30, 0.30, 1 },
}

O.SIZE = {
	title = 20,
	heading = 12,
	text = 13,
	small = 11,
}

local unpackColor = XUI.UnpackColor

function O:Accent()
	return unpackColor(XUI.DB.global.accent)
end

function O:Color(name)
	return unpackColor(self.C[name])
end

function O:FontPath()
	return XUI.Media:Fetch("font", XUI.DB.global.panel.font)
end

-- Creates a FontString in the panel font. `color` is a palette name.
function O:Text(parent, size, color, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	fs:SetFont(self:FontPath(), size or self.SIZE.text, "")
	fs:SetTextColor(self:Color(color or "text"))
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(false)
	return fs
end

function O:Rect(parent, color, layer, sublevel)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel)
	t:SetTexture(self.WHITE)
	if type(color) == "string" then
		t:SetVertexColor(self:Color(color))
	elseif color then
		t:SetVertexColor(unpackColor(color))
	end
	return t
end

function O:Icon(parent, name, size, color, layer)
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	t:SetTexture(self.MEDIA .. name)
	t:SetSize(size, size)
	if type(color) == "string" then
		t:SetVertexColor(self:Color(color))
	elseif color then
		t:SetVertexColor(unpackColor(color))
	end
	return t
end

-- Background fill plus a 1px border, both palette names.
function O:Skin(frame, bg, border)
	local tex = frame.__skinBg
	if not tex then
		tex = self:Rect(frame, bg, "BACKGROUND", -8)
		tex:SetAllPoints()
		frame.__skinBg = tex
	else
		tex:SetVertexColor(self:Color(bg))
	end
	if border then
		local b = XUI.Style:Border(frame, 1)
		b:Apply({ useGlobal = false, style = "SOLID", size = 1, color = self.C[border] })
	end
	return tex
end

function O:SetSkinColor(frame, bg)
	if frame.__skinBg then frame.__skinBg:SetVertexColor(self:Color(bg)) end
end

function O:SetBorderColor(frame, r, g, b, a)
	if frame.__xuiBorder then frame.__xuiBorder:SetColor(r, g, b, a) end
end

function O:Tooltip(frame, title, text)
	frame:HookScript("OnEnter", function(self)
		if not title then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
		GameTooltip:AddLine(title, 1, 1, 1)
		if text then GameTooltip:AddLine(text, 0.75, 0.75, 0.75, true) end
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A square icon button (close, unlock, reset ...).
function O:IconButton(parent, icon, size, tip, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size or 26, size or 26)
	b.bg = self:Rect(b, "control")
	b.bg:SetAllPoints()
	b.bg:SetAlpha(0)
	b.icon = self:Icon(b, icon, math.floor((size or 26) * 0.6), "muted")
	b.icon:SetPoint("CENTER")
	b:SetScript("OnEnter", function(self)
		self.bg:SetAlpha(1)
		self.icon:SetVertexColor(O:Color("text"))
	end)
	b:SetScript("OnLeave", function(self)
		self.bg:SetAlpha(0)
		if self.active then self.icon:SetVertexColor(O:Accent()) else self.icon:SetVertexColor(O:Color("muted")) end
	end)
	function b:SetActive(on)
		self.active = on
		if on then self.icon:SetVertexColor(O:Accent()) else self.icon:SetVertexColor(O:Color("muted")) end
	end
	b:SetScript("OnClick", onClick)
	if tip then self:Tooltip(b, tip) end
	return b
end

-- A flat text button. `primary` fills it with the accent.
function O:Button(parent, text, width, onClick, primary)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width or 120, 24)
	self:Skin(b, "control", "controlLine")
	b.text = self:Text(b, self.SIZE.text, "text")
	b.text:SetPoint("CENTER")
	b.text:SetText(text)
	b.primary = primary
	local function Paint(self, hover)
		if self.disabled then
			O:SetSkinColor(self, "control")
			self.text:SetTextColor(O:Color("faint"))
			return
		end
		if self.primary then
			local r, g, bl = O:Accent()
			local k = hover and 1 or 0.85
			self.__skinBg:SetVertexColor(r * k, g * k, bl * k, 1)
			self.text:SetTextColor(1, 1, 1)
		else
			O:SetSkinColor(self, hover and "controlHover" or "control")
			self.text:SetTextColor(O:Color("text"))
		end
	end
	b.Paint = Paint
	b:SetScript("OnEnter", function(self) Paint(self, true) end)
	b:SetScript("OnLeave", function(self) Paint(self, false) end)
	b:SetScript("OnClick", function(self, ...)
		if not self.disabled and onClick then onClick(self, ...) end
	end)
	function b:SetDisabled(on)
		self.disabled = on and true or false
		Paint(self, false)
	end
	Paint(b, false)
	return b
end
