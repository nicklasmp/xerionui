local ns = _G.XerionUIPlugin and _G.XerionUIPlugin.__ns
if not ns then return end
ns.OptionsBuild = '2026-09-21.5'

local Msg = ns.Msg
local Trim = ns.Trim
local CdSpellName, CdSpellTexture = ns.CdSpellName, ns.CdSpellTexture

local format, ipairs, pairs, tostring, tonumber = format, ipairs, pairs, tostring, tonumber
local CreateFrame, tinsert = CreateFrame, tinsert

local CONFIG, scroll, content
local navContent
local navTree = {}
local navFilter = ''
local pageBuild = {}
local currentPage
local ShowPage
local RebuildNav
local Search = { words = {}, pages = {}, hits = {} }

local ACCENT    = { 1, 0.49, 0.04 }
local C_BG      = { 0.055, 0.055, 0.065 }
local C_PANEL   = { 0.115, 0.115, 0.135 }
local C_PANEL_H = { 0.175, 0.175, 0.200 }
local C_TRACK   = { 0.210, 0.210, 0.240 }
local C_INPUT   = { 0.080, 0.080, 0.095 }
local ARROW_TEX = [[Interface\ChatFrame\ChatFrameExpandArrow]]

local RoundN = ns.Round

local function TextH(fs, minimum)
	local h = fs:GetStringHeight()
	if not h or h < 1 then
		local _, size = fs:GetFont()
		h = (size or 12) * 1.2
	end
	if minimum and h < minimum then h = minimum end
	return h
end

local function TextW(fs)
	local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
	return w or 0
end

local measureFS
local function MeasureText(text, fontObject)
	if not measureFS then
		local holder = CreateFrame('Frame', nil, UIParent)
		holder:SetSize(1, 1)
		holder:SetPoint('TOPLEFT')
		holder:SetAlpha(0)
		measureFS = holder:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
		measureFS:SetPoint('TOPLEFT')
	end
	measureFS:SetFontObject(fontObject or 'GameFontHighlight')
	measureFS:SetText(text or '')
	return TextW(measureFS), TextH(measureFS)
end

local function After(fs, x0, minX, gap)
	local x = x0 + TextW(fs) + (gap or 6)
	return (minX and minX > x) and minX or x
end

local scrollPopup, OpenScrollPopup

local function SkinBox(f, c)
	f.__border = f:CreateTexture(nil, 'BACKGROUND', nil, 0)
	f.__border:SetColorTexture(0, 0, 0, 1)
	f.__border:SetPoint('TOPLEFT', -1, 1)
	f.__border:SetPoint('BOTTOMRIGHT', 1, -1)
	f.__bg = f:CreateTexture(nil, 'BACKGROUND', nil, 1)
	f.__bg:SetAllPoints()
	c = c or C_PANEL
	f.__bg:SetColorTexture(c[1], c[2], c[3], 1)
	return f
end

local function MakeFlatButton(parent, text, w, h)
	local b = CreateFrame('Button', nil, parent)
	b:SetSize(w or 170, h or 24)
	SkinBox(b, C_PANEL)
	b.__label = b:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
	b.__label:SetPoint('LEFT', 4, 0)
	b.__label:SetPoint('RIGHT', -4, 0)
	b.__label:SetJustifyH('CENTER')
	b.__label:SetWordWrap(false)
	b.__label:SetText(text or '')
	b.SetText = function(self, t) self.__label:SetText(t) end
	b.GetFontString = function(self) return self.__label end
	b:SetScript('OnEnter', function(self)
		self.__bg:SetColorTexture(C_PANEL_H[1], C_PANEL_H[2], C_PANEL_H[3], 1)
		self.__border:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.85)
	end)
	b:SetScript('OnLeave', function(self)
		self.__bg:SetColorTexture(C_PANEL[1], C_PANEL[2], C_PANEL[3], 1)
		self.__border:SetColorTexture(0, 0, 0, 1)
	end)
	return b
end

local function MakeEditBox(parent, w, h)
	local eb = CreateFrame('EditBox', nil, parent)
	eb:SetAutoFocus(false)
	eb:SetSize(w or 60, h or 20)
	eb:SetFontObject(_G.ChatFontNormal)
	eb:SetTextInsets(5, 5, 0, 0)
	SkinBox(eb, C_INPUT)
	eb:SetScript('OnEscapePressed', function(self) self:ClearFocus() end)
	eb:HookScript('OnEditFocusGained', function(self)
		self.__border:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
	end)
	eb:HookScript('OnEditFocusLost', function(self)
		self.__border:SetColorTexture(0, 0, 0, 1)
	end)
	return eb
end

local function SetButtonState(b, on, offLabel)
	b.__on = on and true or false
	local function paint(hovered)
		local bg = (b.__on or hovered) and C_PANEL_H or C_PANEL
		b.__bg:SetColorTexture(bg[1], bg[2], bg[3], 1)
		if b.__on then
			b.__border:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], hovered and 1 or 0.85)
			b.__label:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
		else
			if hovered then
				b.__border:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.85)
			else
				b.__border:SetColorTexture(0, 0, 0, 1)
			end
			local c = offLabel or { 1, 1, 1 }
			b.__label:SetTextColor(c[1], c[2], c[3])
		end
	end
	b:SetScript('OnEnter', function() paint(true) end)
	b:SetScript('OnLeave', function() paint(false) end)
	paint(false)
	return b
end

local function MakeToggle(parent)
	local t = CreateFrame('Button', nil, parent)
	t:SetSize(32, 16)
	SkinBox(t, C_TRACK)
	t.knob = t:CreateTexture(nil, 'ARTWORK')
	t.knob:SetSize(12, 12)
	t.__checked = false
	t.SetChecked = function(self, v)
		self.__checked = v and true or false
		self.knob:ClearAllPoints()
		if self.__checked then
			self.__bg:SetColorTexture(ACCENT[1] * 0.85, ACCENT[2] * 0.85, ACCENT[3] * 0.85, 1)
			self.knob:SetColorTexture(1, 1, 1, 1)
			self.knob:SetPoint('RIGHT', -2, 0)
		else
			self.__bg:SetColorTexture(C_TRACK[1], C_TRACK[2], C_TRACK[3], 1)
			self.knob:SetColorTexture(0.55, 0.55, 0.60, 1)
			self.knob:SetPoint('LEFT', 2, 0)
		end
	end
	t.GetChecked = function(self) return self.__checked end
	t:SetChecked(false)
	return t
end

local function MakeTickBox(parent, label, w)
	local b = CreateFrame('Button', nil, parent)
	b:SetHeight(18)

	local box = CreateFrame('Frame', nil, b)
	box:SetSize(14, 14)
	box:SetPoint('LEFT', 0, 0)
	SkinBox(box, C_INPUT)

	local tick = box:CreateTexture(nil, 'OVERLAY')
	tick:SetAllPoints()
	tick:SetTexture([[Interface\Buttons\UI-CheckBox-Check]])
	tick:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3])
	tick:Hide()

	local fs = b:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
	fs:SetPoint('LEFT', box, 'RIGHT', 5, 0)
	fs:SetText(label or '')

	if w then
		b:SetWidth(w)
		fs:SetPoint('RIGHT', b, 'RIGHT', 0, 0)
		fs:SetJustifyH('LEFT')
		fs:SetWordWrap(false)
	else
		b:SetWidth(14 + 5 + TextW(fs) + 2)
	end

	local function Paint(hovered)
		if b.__checked then
			tick:Show()
			box.__border:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], hovered and 1 or 0.85)
			fs:SetTextColor(1, 1, 1)
		else
			tick:Hide()
			box.__border:SetColorTexture(0, 0, 0, 1)
			if hovered then
				box.__border:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.6)
			end
			fs:SetTextColor(0.55, 0.55, 0.60)
		end
	end
	b.SetChecked = function(self, v) self.__checked = v and true or false Paint(false) end
	b.GetChecked = function(self) return self.__checked end
	b:SetScript('OnEnter', function() Paint(true) end)
	b:SetScript('OnLeave', function() Paint(false) end)
	b:SetChecked(false)
	return b
end

local function Track(w) content.widgets[#content.widgets + 1] = w return w end

local function ResetContent()
	if content.widgets then
		for _, w in ipairs(content.widgets) do
			w:Hide()
			w:SetParent(nil)
			if w.ClearAllPoints then w:ClearAllPoints() end
		end
	end
	content.widgets = {}
	content.cy = -14
	content.rows = {}
	content.header = nil
	content.tab = nil
	content.variants = nil
	content.noReg = nil
	if content.searchHL then content.searchHL:Hide() end
end

local function Plain(s)
	s = tostring(s or '')
	s = s:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', ''):gsub('|T.-|t', '')
	return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

function Search.Reg(kind, label, tip, widget, tab, what)
	local rows = content and content.rows
	if not rows or content.noReg then return end
	local text = Plain(label)
	if text == '' then return end
	local e = {
		kind = kind, text = text, low = text:lower(),
		tip = (type(tip) == 'string') and Plain(tip):lower() or nil,
		page = content.pageKey, widget = widget, y = content.cy, what = what,
	}
	if kind == 'dest' then
		e.tab = tab
	else
		e.tab = content.tab
		if kind ~= 'header' then e.header = content.header end
	end
	e.tabLow = e.tab and e.tab:lower() or nil
	e.headerLow = e.header and e.header:lower() or nil
	rows[#rows + 1] = e
	return e
end

function Search.Tip(tip)
	local rows = content and content.rows
	local last = rows and rows[#rows]
	if not last or type(tip) ~= 'string' then return end
	local t = Plain(tip):lower()
	if t == '' then return end
	last.tip = last.tip and (last.tip .. ' ' .. t) or t
end

function Search.Variants(names, cur, what)
	if not content or not content.rows then return end
	content.variants = names
	content.tab = cur
	for _, name in ipairs(names) do Search.Reg('dest', name, nil, nil, name, what) end
end

local subTab = {}
local function AddTabs(pageKey, names)
	local cur = subTab[pageKey]
	local valid = false
	for _, n in ipairs(names) do if n == cur then valid = true break end end
	if not valid then cur = names[1] end
	Search.Variants(names, cur, 'Tab')

	local x = 16
	for _, name in ipairs(names) do
		local on = (name == cur)
		local b = MakeFlatButton(content, name, math.max(80, MeasureText(name) + 24), 24)
		b:SetPoint('TOPLEFT', x, content.cy)
		if on then
			b.__bg:SetColorTexture(C_PANEL_H[1], C_PANEL_H[2], C_PANEL_H[3], 1)
			b.__border:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.85)
			b.__label:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
			b:SetScript('OnLeave', function(self)
				self.__bg:SetColorTexture(C_PANEL_H[1], C_PANEL_H[2], C_PANEL_H[3], 1)
				self.__border:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.85)
			end)
		else
			b:SetScript('OnClick', function()
				subTab[pageKey] = name
				ShowPage(pageKey)
			end)
		end
		Track(b)
		x = x + b:GetWidth() + 6
	end
	content.cy = content.cy - 34
	return cur
end

local pinnedTabs
local function HidePinnedTabs()
	if pinnedTabs then pinnedTabs:Hide() end
end

-- `icons` (optional) holds one texture per name, drawn left of the label, or
-- { spec = specID, tex = fallback } for a class page's spec button: the spec's
-- own icon from the client, the file if the client will not say. `cur`
-- (optional) names the lit tab when the page keeps more than the tab in
-- subTab[pageKey] - a click still writes the tab's name there, so such a page
-- must read it back. A class page with one spec passes that spec as `cur`: its
-- lone button is always lit, and subTab stays free for the page's categories.
local function AddPinnedTabs(pageKey, names, icons, cur)
	cur = cur or subTab[pageKey]
	local valid = false
	for _, n in ipairs(names) do if n == cur then valid = true break end end
	if not valid then cur = names[1] end
	Search.Variants(names, cur, 'Tab')

	if content.indexing then
		content.cy = content.cy - 34
		return cur
	end

	if not pinnedTabs then
		pinnedTabs = CreateFrame('Frame', nil, CONFIG)
		pinnedTabs:SetFrameLevel((CONFIG:GetFrameLevel() or 1) + 50)
		pinnedTabs.bg = pinnedTabs:CreateTexture(nil, 'BACKGROUND')
		pinnedTabs.bg:SetAllPoints()
		pinnedTabs.bg:SetColorTexture(C_BG[1], C_BG[2], C_BG[3], 1)
		pinnedTabs.line = pinnedTabs:CreateTexture(nil, 'ARTWORK')
		pinnedTabs.line:SetHeight(1)
		pinnedTabs.line:SetPoint('BOTTOMLEFT', 0, 0)
		pinnedTabs.line:SetPoint('BOTTOMRIGHT', 0, 0)
		pinnedTabs.line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.25)
		pinnedTabs.buttons = {}
	end

	pinnedTabs:ClearAllPoints()
	pinnedTabs:SetPoint('TOPLEFT', scroll, 'TOPLEFT', 0, 0)
	pinnedTabs:SetPoint('TOPRIGHT', scroll, 'TOPRIGHT', 0, 0)
	pinnedTabs:SetHeight(34)
	pinnedTabs:Show()

	for _, b in ipairs(pinnedTabs.buttons) do b:Hide() end

	local x = 16
	for i, name in ipairs(names) do
		local on = (name == cur)
		local b = pinnedTabs.buttons[i]
		if not b then
			b = MakeFlatButton(pinnedTabs, name, 80, 24)
			pinnedTabs.buttons[i] = b
		end
		b:SetText(name)
		-- The buttons are shared by every page with pinned tabs, so an icon left
		-- over from the Death Knight page is hidden and the label put back.
		local icon = icons and icons[i]
		if type(icon) == 'table' then
			local spec, get = icon.spec, _G.GetSpecializationInfoByID
			icon = icon.tex
			if spec and get then
				local ok, _, _, _, tex = pcall(get, spec)
				if ok and type(tex) == 'number' and not (ns.IsSecret and ns.IsSecret(tex)) then icon = tex end
			end
		end
		if icon and not b.__icon then
			b.__icon = b:CreateTexture(nil, 'ARTWORK')
			b.__icon:SetSize(16, 16)
			b.__icon:SetPoint('LEFT', 8, 0)
			b.__icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end
		if b.__icon then
			b.__icon:SetTexture(icon)
			b.__icon:SetShown(icon and true or false)
		end
		b.__label:ClearAllPoints()
		b.__label:SetPoint('LEFT', icon and 28 or 4, 0)
		b.__label:SetPoint('RIGHT', icon and -8 or -4, 0)
		b:SetWidth(math.max(80, MeasureText(name) + 24 + (icon and 24 or 0)))
		b:ClearAllPoints()
		b:SetPoint('TOPLEFT', x, -4)
		b:Show()
		SetButtonState(b, on)
		if on then
			b:SetScript('OnClick', nil)
		else
			b:SetScript('OnClick', function()
				subTab[pageKey] = name
				ShowPage(pageKey)
			end)
		end
		x = x + b:GetWidth() + 6
	end

	content.cy = content.cy - 34
	return cur
end

local function AddHeader(text)
	local fs = content:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
	fs:SetPoint('TOPLEFT', 16, content.cy)
	fs:SetText(text)
	fs:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
	content.header = Plain(text)
	Search.Reg('header', text, nil, fs)
	local ly = math.max(20, TextH(fs, 16) + 2)
	local line = content:CreateTexture(nil, 'ARTWORK')
	line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.25)
	line:SetHeight(1)
	line:SetPoint('TOPLEFT', 16, content.cy - ly)
	line:SetPoint('TOPRIGHT', -20, content.cy - ly)
	Track(line)
	content.cy = content.cy - (ly + 10)
	return Track(fs)
end

local function AddDesc(text)
	local fs = content:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
	fs:SetPoint('TOPLEFT', 16, content.cy)
	fs:SetWidth(470)
	fs:SetJustifyH('LEFT')
	fs:SetText(text)
	fs:SetTextColor(0.7, 0.7, 0.7)
	Search.Tip(text)
	content.cy = content.cy - TextH(fs, 12) - 10
	return Track(fs)
end

local function Tooltip(frame, text)
	if not text then return end
	frame:HookScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
		GameTooltip:AddLine(text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	frame:HookScript('OnLeave', function() GameTooltip:Hide() end)
end

local function AddLabel(text)
	local fs = content:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
	fs:SetPoint('TOPLEFT', 16, content.cy)
	fs:SetText(text)
	fs:SetTextColor(0.9, 0.9, 0.9)
	Search.Reg('row', text, nil, fs)
	return Track(fs)
end

local function LabelGap(fs)
	return math.max(18, TextH(fs) + 4)
end

local function AddCheck(label, getFn, setFn, tooltip)
	local row = CreateFrame('Button', nil, content)
	row:SetPoint('TOPLEFT', 16, content.cy)
	row:SetSize(440, 20)
	local tog = MakeToggle(row)
	tog:SetPoint('LEFT', 0, 0)
	tog:EnableMouse(false)
	local fs = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
	fs:SetPoint('LEFT', tog, 'RIGHT', 10, 0)
	fs:SetText(label)
	Search.Reg('row', label, tooltip, row)
	tog:SetChecked(getFn() and true or false)
	row:SetScript('OnClick', function()
		local v = not (getFn() and true or false)
		tog:SetChecked(v)
		setFn(v)
	end)
	row:SetScript('OnEnter', function() fs:SetTextColor(1, 1, 1) end)
	row:SetScript('OnLeave', function() fs:SetTextColor(0.9, 0.9, 0.9) end)
	fs:SetTextColor(0.9, 0.9, 0.9)
	Tooltip(row, tooltip)
	local th = TextH(fs)
	if th > 20 then row:SetHeight(th) end
	content.cy = content.cy - math.max(27, th + 9)
	return Track(row)
end

local function AddSlider(label, mn, mx, st, getFn, setFn, tooltip)
	local fs = AddLabel(label)
	Search.Tip(tooltip)
	local gap = LabelGap(fs)

	local s = CreateFrame('Slider', nil, content)
	s:SetOrientation('HORIZONTAL')
	s:SetSize(300, 16)
	s:SetPoint('TOPLEFT', 16, content.cy - gap)
	s:SetMinMaxValues(mn, mx)
	s:SetValueStep(st)
	s:SetObeyStepOnDrag(true)
	local trackBorder = s:CreateTexture(nil, 'BACKGROUND', nil, 0)
	trackBorder:SetPoint('LEFT', 0, 0)
	trackBorder:SetPoint('RIGHT', 0, 0)
	trackBorder:SetHeight(6)
	trackBorder:SetColorTexture(0, 0, 0, 1)
	local track = s:CreateTexture(nil, 'BACKGROUND', nil, 1)
	track:SetPoint('LEFT', 1, 0)
	track:SetPoint('RIGHT', -1, 0)
	track:SetHeight(4)
	track:SetColorTexture(C_TRACK[1], C_TRACK[2], C_TRACK[3], 1)
	local thumb = s:CreateTexture(nil, 'ARTWORK')
	thumb:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
	thumb:SetSize(10, 16)
	s:SetThumbTexture(thumb)

	local function fmt(v) return (st < 1) and format('%.2f', v) or tostring(math.floor(v + 0.5)) end
	local function snap(v)
		if v < mn then v = mn elseif v > mx then v = mx end
		if st < 1 then v = math.floor(v / st + 0.5) * st else v = math.floor(v + 0.5) end
		return v
	end

	local eb = MakeEditBox(content, 56, 18)
	eb:SetJustifyH('CENTER')
	eb:SetPoint('LEFT', s, 'RIGHT', 16, 0)

	local cur = getFn() or mn
	s:SetValue(cur)
	eb:SetText(fmt(cur))
	s:SetScript('OnValueChanged', function(_, val)
		val = snap(val)
		if not eb:HasFocus() then eb:SetText(fmt(val)) end
		setFn(val)
	end)
	s:EnableMouseWheel(true)
	s:SetScript('OnMouseWheel', function(self, delta)
		if IsShiftKeyDown() then
			self:SetValue(snap(self:GetValue() + delta * st))
		elseif scroll then
			local maxScroll = scroll:GetVerticalScrollRange()
			local new = scroll:GetVerticalScroll() - delta * 40
			if new < 0 then new = 0 elseif new > maxScroll then new = maxScroll end
			scroll:SetVerticalScroll(new)
		end
	end)
	eb:SetScript('OnEnterPressed', function(self)
		local n = tonumber(self:GetText())
		if n then s:SetValue(snap(n)) end
		self:ClearFocus()
	end)
	eb:SetScript('OnEscapePressed', function(self) self:SetText(fmt(s:GetValue())) self:ClearFocus() end)
	eb:HookScript('OnEditFocusLost', function(self) self:SetText(fmt(s:GetValue())) end)
	Tooltip(s, tooltip)

	Track(eb)
	content.cy = content.cy - (gap + 28)
	return Track(s)
end

local function AddEditBoxOption(label, getFn, setFn, width)
	local fs = AddLabel(label)
	content.cy = content.cy - LabelGap(fs)

	local eb = MakeEditBox(content, width or 240, 22)
	eb:SetPoint('TOPLEFT', 16, content.cy)
	eb:SetText(getFn() or '')
	local function commit(self)
		setFn(self:GetText() or '')
		self:ClearFocus()
	end
	eb:SetScript('OnEnterPressed', commit)
	eb:HookScript('OnEditFocusLost', function(self) setFn(self:GetText() or '') end)
	Track(eb)
	content.cy = content.cy - 30
	return eb
end

local function AddDropdown(label, options, getFn, setFn)
	local fs = AddLabel(label)
	content.cy = content.cy - LabelGap(fs)

	local btn = MakeFlatButton(content, '', 200, 22)
	btn:SetPoint('TOPLEFT', 16, content.cy)
	btn.__label:ClearAllPoints()
	btn.__label:SetPoint('LEFT', 8, 0)
	btn.__label:SetPoint('RIGHT', -20, 0)
	btn.__label:SetJustifyH('LEFT')
	local ar = btn:CreateTexture(nil, 'OVERLAY')
	ar:SetTexture(ARROW_TEX)
	ar:SetSize(12, 12)
	ar:SetPoint('RIGHT', -5, 0)
	ar:SetRotation(-math.pi / 2)

	local function currentText()
		local cur = getFn()
		for _, o in ipairs(options) do if o.value == cur then return o.text end end
		return tostring(cur)
	end
	btn:SetText(currentText())
	btn:SetScript('OnClick', function()
		OpenScrollPopup(btn, options, getFn, setFn, nil, function(t) btn:SetText(t) end)
	end)

	Track(btn)
	content.cy = content.cy - 30
	return btn
end

local function FitWidth(label, minimum)
	local w = MeasureText(label) + 28
	local floor = minimum or 170
	return w > floor and w or floor
end

local function AddButton(label, onClick, width)
	local b = MakeFlatButton(content, label, width or FitWidth(label), 24)
	b:SetPoint('TOPLEFT', 16, content.cy)
	b:SetScript('OnClick', onClick)
	Search.Reg('row', label, nil, b)
	content.cy = content.cy - 30
	return Track(b)
end

local function AddToggleButton(labelFn, onClick)
	local b = MakeFlatButton(content, labelFn(), 170, 24)
	b:SetPoint('TOPLEFT', 16, content.cy)
	b:SetScript('OnClick', function() onClick() b:SetText(labelFn()) end)
	content.cy = content.cy - 30
	return Track(b)
end

local function AddColor(label, getFn, setFn)
	local fs = content:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
	fs:SetPoint('TOPLEFT', 16, content.cy)
	fs:SetText(label)
	Track(fs)
	Search.Reg('row', label, nil, fs)
	local sw = CreateFrame('Button', nil, content)
	sw:SetSize(18, 18)
	sw:SetPoint('LEFT', fs, 'RIGHT', 12, 0)
	local bord = sw:CreateTexture(nil, 'BACKGROUND')
	bord:SetPoint('TOPLEFT', -1, 1)
	bord:SetPoint('BOTTOMRIGHT', 1, -1)
	bord:SetColorTexture(0, 0, 0, 1)
	sw.tex = sw:CreateTexture(nil, 'ARTWORK')
	sw.tex:SetAllPoints()
	local function refresh()
		local c = getFn() or { 1, 1, 1 }
		sw.tex:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, 1)
	end
	refresh()
	sw:SetScript('OnClick', function()
		local c = getFn() or { 1, 1, 1 }
		local r, g, b = c[1] or 1, c[2] or 1, c[3] or 1
		local function applyNow()
			local nr, ng, nb = ColorPickerFrame:GetColorRGB()
			setFn({ nr, ng, nb, 1 })
			refresh()
		end
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r, g = g, b = b, hasOpacity = false,
			swatchFunc = applyNow,
			cancelFunc = function() setFn({ r, g, b, 1 }) refresh() end,
		})
	end)
	Track(sw)
	content.cy = content.cy - math.max(26, TextH(fs) + 10)
	return sw
end

local function GetScrollPopup()
	if scrollPopup then return scrollPopup end
	local pop = CreateFrame('Frame', 'KiraScrollDropdownPopup', UIParent, 'BackdropTemplate')
	pop:SetSize(260, 340)
	pop:SetFrameStrata('FULLSCREEN_DIALOG')
	pop:SetFrameLevel(200)
	if pop.SetBackdrop then
		pop:SetBackdrop({ bgFile = 'Interface\\Buttons\\WHITE8X8', edgeFile = 'Interface\\Buttons\\WHITE8X8', edgeSize = 1 })
		pop:SetBackdropColor(C_BG[1], C_BG[2], C_BG[3], 0.98)
		pop:SetBackdropBorderColor(0, 0, 0, 1)
	end
	pop:Hide()

	local catcher = CreateFrame('Button', nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata('FULLSCREEN_DIALOG')
	catcher:SetFrameLevel(150)
	catcher:Hide()
	catcher:SetScript('OnClick', function() pop:Hide() end)
	pop:SetScript('OnShow', function() catcher:Show() end)
	pop:SetScript('OnHide', function()
		catcher:Hide()
		if pop.search then pop.search:ClearFocus() end
	end)

	local search = MakeEditBox(pop, 200, 20)
	search:SetPoint('TOPLEFT', 6, -6)
	search:SetPoint('TOPRIGHT', -6, -6)
	search:SetAutoFocus(false)
	local hint = search:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
	hint:SetPoint('LEFT', 6, 0)
	hint:SetText('Search...')
	search:HookScript('OnTextChanged', function(self)
		hint:SetShown((self:GetText() or '') == '')
	end)
	pop.search = search
	pop.searchHint = hint

	local sf = CreateFrame('ScrollFrame', 'KiraScrollDropdownScroll', pop, 'UIPanelScrollFrameTemplate')
	sf:SetPoint('TOPLEFT', 6, -6)
	sf:SetPoint('BOTTOMRIGHT', -26, 6)
	local child = CreateFrame('Frame', nil, sf)
	child:SetSize(210, 10)
	sf:SetScrollChild(child)
	pop.scroll = sf
	pop.child = child
	pop.rows = {}
	scrollPopup = pop
	return pop
end

function OpenScrollPopup(owner, options, getFn, setFn, onPick, setBtnText, preview)
	local pop = GetScrollPopup()
	if pop:IsShown() and pop.__owner == owner then pop:Hide() return end
	pop.__owner = owner
	-- The popup and its full-screen click catcher hang off UIParent, so a list
	-- whose button went away (the window closed with ESC or /xerion, or the page
	-- switched) stayed on screen, and the invisible catcher ate the next click
	-- and right-drag camera turns. Every owner gets this hook here, once per
	-- button.
	if not owner.__kiraPopHide then
		owner.__kiraPopHide = true
		owner:HookScript('OnHide', function(self)
			if scrollPopup and scrollPopup.__owner == self then scrollPopup:Hide() end
		end)
	end
	local child = pop.child
	local _, fontH = MeasureText('Ag', 'GameFontHighlightSmall')
	local rowH = math.max(18, math.ceil(fontH) + 4)

	local searchable = #options > 12
	local search = pop.search
	search:SetText('')
	search:SetShown(searchable)
	pop.searchHint:SetShown(searchable)

	local maxVisible = 340 - 12 - (searchable and 24 or 0)

	local widest = 0
	for _, o in ipairs(options) do
		local w = MeasureText(o.text, 'GameFontHighlightSmall')
		if w > widest then widest = w end
	end
	local barW = (#options * rowH + 4 > maxVisible) and 26 or 6
	local popW = 6 + 4 + math.ceil(widest) + (preview and 22 or 4) + barW + 2
	pop:SetWidth(math.max(260, math.min(480, popW)))

	local sf = pop.scroll
	local function Render(filter)
		local cur = getFn()
		local shown = options
		if filter and filter ~= '' then
			shown = {}
			local match = {}
			for _, o in ipairs(options) do
				local term = ns.PlainName(o.text .. ' ' .. tostring(o.value))
				if term:find(filter, 1, true) then match[#match + 1] = o end
			end
			shown = match
		end

		local top = searchable and 30 or 6
		local contentH = #shown * rowH + 4
		local needsBar = contentH > maxVisible
		local bar = sf.ScrollBar or (sf.GetName and sf:GetName() and _G[sf:GetName() .. 'ScrollBar'])
		if bar then bar:SetShown(needsBar) end
		sf:ClearAllPoints()
		sf:SetPoint('TOPLEFT', 6, -top)
		sf:SetPoint('BOTTOMRIGHT', needsBar and -26 or -6, 6)
		sf:SetVerticalScroll(0)
		child:SetWidth(pop:GetWidth() - 6 - (needsBar and 26 or 6))

		local y = -2
		for i, o in ipairs(shown) do
			local row = pop.rows[i]
			if not row then
				row = CreateFrame('Button', nil, child)
				row:SetHeight(rowH)
				row.text = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
				row.text:SetJustifyH('LEFT')
				row.text:SetWordWrap(false)
				row.hl = row:CreateTexture(nil, 'HIGHLIGHT')
				row.hl:SetAllPoints()
				row.hl:SetColorTexture(1, 1, 1, 0.12)
				row.sel = row:CreateTexture(nil, 'BACKGROUND')
				row.sel:SetAllPoints()
				row.sel:SetColorTexture(0.9, 0.55, 0.1, 0.25)
				row.spk = CreateFrame('Button', nil, row)
				row.spk:SetSize(15, 15)
				row.spk:SetPoint('RIGHT', -4, 0)
				row.spk:RegisterForClicks('AnyUp')
				row.spk.tex = row.spk:CreateTexture(nil, 'ARTWORK')
				row.spk.tex:SetAllPoints()
				row.spk.tex:SetTexture('Interface\\Common\\VoiceChat-Speaker')
				pop.rows[i] = row
			end
			row:SetFrameLevel(child:GetFrameLevel() + 1)
			row.spk:SetFrameLevel(row:GetFrameLevel() + 2)
			row:ClearAllPoints()
			row:SetPoint('TOPLEFT', 0, y)
			row:SetPoint('TOPRIGHT', 0, y)
			row.text:ClearAllPoints()
			row.text:SetPoint('LEFT', 4, 0)
			row.text:SetPoint('RIGHT', preview and -22 or -4, 0)
			row.text:SetText(o.text)
			local isSelected = o.value == cur or ns.PlainName(o.value) == ns.PlainName(cur)
			row.sel:SetShown(isSelected and true or false)
			if preview then
				row.spk:SetScript('OnClick', function() preview(o.value) end)
				row.spk:Show()
			else
				row.spk:Hide()
			end
			row:SetScript('OnClick', function()
				setFn(o.value)
				if setBtnText then setBtnText(o.text) end
				if onPick then onPick(o.value) end
				pop:Hide()
			end)
			row:Show()
			y = y - rowH
		end
		for i = #shown + 1, #pop.rows do pop.rows[i]:Hide() end
		child:SetHeight(math.max(10, #shown * rowH + 4))
		pop:SetHeight(math.min(340, #shown * rowH + 16 + (searchable and 24 or 0)))
		pop.__first = shown[1]
	end

	Render(nil)

	do
		local es, os = pop:GetEffectiveScale(), owner:GetEffectiveScale()
		local ob, ot, ol = owner:GetBottom(), owner:GetTop(), owner:GetLeft()
		local up, rightSide = false, false
		if ob and ot and ol and es and os and es > 0 and os > 0 then
			local k = os / es
			local root = UIParent:GetEffectiveScale() / es
			local screenH = UIParent:GetHeight() * root
			local screenW = UIParent:GetWidth() * root
			local need = pop:GetHeight() + 2
			up = (ob * k - need < 0) and (ot * k + need <= screenH)
			rightSide = (ol * k + pop:GetWidth() > screenW)
		end
		pop:ClearAllPoints()
		pop:SetPoint((up and 'BOTTOM' or 'TOP') .. (rightSide and 'RIGHT' or 'LEFT'),
			owner, (up and 'TOP' or 'BOTTOM') .. (rightSide and 'RIGHT' or 'LEFT'),
			0, up and 2 or -2)
	end

	if searchable then
		search:SetScript('OnTextChanged', function(self)
			pop.searchHint:SetShown((self:GetText() or '') == '')
			Render(ns.PlainName(self:GetText()))
		end)
		search:SetScript('OnEnterPressed', function(self)
			local o = pop.__first
			if o then
				setFn(o.value)
				if setBtnText then setBtnText(o.text) end
				if onPick then onPick(o.value) end
			end
			pop:Hide()
		end)
		search:SetScript('OnEscapePressed', function() pop:Hide() end)
	else
		search:SetScript('OnTextChanged', nil)
		search:SetScript('OnEnterPressed', nil)
		search:SetScript('OnEscapePressed', nil)
	end

	pop:Show()
	pop:Raise()
	if searchable then search:SetFocus() end
end

local function AddScrollDropdown(label, options, getFn, setFn, onPick, preview)
	local fs = AddLabel(label)
	content.cy = content.cy - LabelGap(fs)
	local btn = MakeFlatButton(content, '', 220, 22)
	btn:SetPoint('TOPLEFT', 16, content.cy)
	btn.__label:ClearAllPoints()
	btn.__label:SetPoint('LEFT', 8, 0)
	btn.__label:SetPoint('RIGHT', -20, 0)
	btn.__label:SetJustifyH('LEFT')
	local ar = btn:CreateTexture(nil, 'OVERLAY')
	ar:SetTexture(ARROW_TEX)
	ar:SetSize(12, 12)
	ar:SetPoint('RIGHT', -5, 0)
	ar:SetRotation(-math.pi / 2)
	local function currentText()
		local cur = getFn()
		for _, o in ipairs(options) do if o.value == cur then return o.text end end
		return tostring(cur)
	end
	btn:SetText(currentText())
	btn:SetScript('OnClick', function()
		OpenScrollPopup(btn, options, getFn, setFn, onPick, function(t)
			btn:SetText(t or currentText())
		end, preview)
	end)
	Track(btn)
	content.cy = content.cy - 30
	return btn
end

local function AddPosition(getX, setX, getY, setY)
	local fs = AddLabel('Position')
	local hint = content:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
	hint:SetPoint('LEFT', fs, 'RIGHT', 8, 0)
	hint:SetText('|cff777777arrows nudge 1 px - hold Shift for 10 px|r')
	Track(hint)
	content.cy = content.cy - math.max(20, TextH(fs) + 6)

	local xBox, yBox
	local function refresh()
		local x, y = tostring(RoundN(getX() or 0)), tostring(RoundN(getY() or 0))
		if not xBox:HasFocus() and xBox:GetText() ~= x then xBox:SetText(x) end
		if not yBox:HasFocus() and yBox:GetText() ~= y then yBox:SetText(y) end
	end

	local xl = content:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
	xl:SetPoint('TOPLEFT', 16, content.cy - 4)
	xl:SetText('X')
	xl:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
	Track(xl)
	xBox = MakeEditBox(content, 54, 20)
	xBox:SetJustifyH('CENTER')
	xBox:SetPoint('LEFT', xl, 'RIGHT', 8, 0)
	Track(xBox)

	local yl = content:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
	yl:SetPoint('LEFT', xBox, 'RIGHT', 14, 0)
	yl:SetText('Y')
	yl:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
	Track(yl)
	yBox = MakeEditBox(content, 54, 20)
	yBox:SetJustifyH('CENTER')
	yBox:SetPoint('LEFT', yl, 'RIGHT', 8, 0)
	Track(yBox)

	local function commit(box, setFn, getFn)
		local n = tonumber(box:GetText())
		if n and RoundN(n) ~= RoundN(getFn() or 0) then setFn(RoundN(n)) end
		refresh()
	end
	xBox:SetScript('OnEnterPressed', function(self) commit(self, setX, getX) self:ClearFocus() end)
	yBox:SetScript('OnEnterPressed', function(self) commit(self, setY, getY) self:ClearFocus() end)
	xBox:HookScript('OnEditFocusLost', function(self) commit(self, setX, getX) end)
	yBox:HookScript('OnEditFocusLost', function(self) commit(self, setY, getY) end)
	xBox:SetScript('OnEscapePressed', function(self) self:SetText(tostring(RoundN(getX() or 0))) self:ClearFocus() end)
	yBox:SetScript('OnEscapePressed', function(self) self:SetText(tostring(RoundN(getY() or 0))) self:ClearFocus() end)

	local acc = 0
	xBox:HookScript('OnUpdate', function(_, elapsed)
		acc = acc + elapsed
		if acc >= 0.25 then
			acc = 0
			refresh()
		end
	end)

	local last
	local function ArrowBtn(rotation, dx, dy, tip)
		local b = MakeFlatButton(content, '', 22, 20)
		if last then b:SetPoint('LEFT', last, 'RIGHT', 4, 0)
		else b:SetPoint('LEFT', yBox, 'RIGHT', 18, 0) end
		local ar = b:CreateTexture(nil, 'OVERLAY')
		ar:SetTexture(ARROW_TEX)
		ar:SetSize(11, 11)
		ar:SetPoint('CENTER')
		ar:SetRotation(rotation)
		b:SetScript('OnClick', function()
			local step = IsShiftKeyDown() and 10 or 1
			if dx ~= 0 then setX(RoundN((getX() or 0) + dx * step)) end
			if dy ~= 0 then setY(RoundN((getY() or 0) + dy * step)) end
			refresh()
		end)
		Tooltip(b, tip)
		last = b
		return Track(b)
	end
	ArrowBtn(math.pi,      -1, 0, 'Move left (Shift = 10 px)')
	ArrowBtn(0,             1, 0, 'Move right (Shift = 10 px)')
	ArrowBtn(math.pi / 2,   0, 1, 'Move up (Shift = 10 px)')
	ArrowBtn(-math.pi / 2,  0, -1, 'Move down (Shift = 10 px)')

	refresh()
	content.cy = content.cy - 30
end

-- Every preview switched from the window is remembered on CONFIG, so closing
-- the window can end it (PREVIEWS END WITH THE WINDOW, in Build).
local function AddPreviewToggle(isPreview, setPreview)
	return AddToggleButton(function() return isPreview() and 'Stop Preview' or 'Preview' end,
		function()
			setPreview(not isPreview())
			if CONFIG and CONFIG.__kiraPreviews then
				CONFIG.__kiraPreviews[setPreview] = function()
					if isPreview() then setPreview(false) end
				end
			end
		end)
end

local function AddSpellIdRow(getList, onAdded, tooltip)
	local box = MakeEditBox(content, 90, 22)
	box:SetPoint('TOPLEFT', 16, content.cy)
	local btn = MakeFlatButton(content, 'Add', 60, 22)
	btn:SetPoint('LEFT', box, 'RIGHT', 8, 0)
	local function add()
		local id = tonumber(box:GetText())
		if not id or id <= 0 then Msg('enter a spell ID first') return end
		id = math.floor(id)
		local list = getList()
		for _, v in ipairs(list) do
			if v == id then Msg('spell ' .. id .. ' is already on the list') return end
		end
		list[#list + 1] = id
		box:SetText('')
		onAdded()
	end
	btn:SetScript('OnClick', add)
	box:SetScript('OnEnterPressed', function(self) add() self:ClearFocus() end)
	Tooltip(box, tooltip)
	Track(box) Track(btn)
	return box
end

local STRATA_OPTIONS = {
	{ value = 'LOW',    text = 'Low' },
	{ value = 'MEDIUM', text = 'Medium (default)' },
	{ value = 'HIGH',   text = 'High - above CDM icons' },
	{ value = 'DIALOG', text = 'Dialog - above almost everything' },
}

local function PagePlayer()
	AddHeader('Player')
	AddHeader('Debuff type borders')
	AddCheck('Enable',
		function() return ns.EUIGetDebuffColorCfg().enable end,
		function(v) ns.EUIGetDebuffColorCfg().enable = v ns.EUIApplyDebuffColors() end)
	AddPreviewToggle(ns.EUITBIsPreview, ns.EUITBSetPreview)
	AddCheck('Thick border',
		function() return ns.EUIGetDebuffColorCfg().thick end,
		function(v) ns.EUIGetDebuffColorCfg().thick = v ns.EUIApplyDebuffColors() end,
		'Doubles the border line thickness. Off = the original thin border, flush with the icon.')
	AddCheck('Border ignores cooldown swipe',
		function() return ns.EUIGetDebuffColorCfg().aboveSwipe end,
		function(v) ns.EUIGetDebuffColorCfg().aboveSwipe = v ns.EUIApplyDebuffColors() end,
		'Keeps the border fully lit while the duration swipe darkens the icon. Off = the border dims with the icon.')

	AddHeader('Debuff timer')
	AddCheck('Show min:sec',
		function() return ns.EUIGetDebuffTimer() == true end,
		function(v) ns.EUISetDebuffTimer(v) end,
		'Debuffs on the Player Aura Bars debuff bar read 4:32 instead of 4m below the time set here. The same setting as Precise Below in that bar\'s Duration cog in /eui, whose Duration must be on.')
	AddSlider('Start min:sec at (minutes)', 2, 10, 1,
		function() return select(2, ns.EUIGetDebuffTimer()) end,
		function(v) ns.EUISetDebuffTimer(ns.EUIGetDebuffTimer() == true, v) end)
end

local function PageBuffReminders()
	AddHeader('Buff Reminders')
	AddCheck('Enable',
		function() return ns.ABRGetCfg().enable end,
		function(v) ns.ABRGetCfg().enable = v ns.ABRApply() end)
	AddCheck('Cross on each reminder',
		function() return ns.ABRGetCfg().each ~= false end,
		function(v) ns.ABRGetCfg().each = v ns.ABRApply() end)
	AddCheck('Cross that dismisses them all',
		function() return ns.ABRGetCfg().all ~= false end,
		function(v) ns.ABRGetCfg().all = v ns.ABRApply() end)
	AddDropdown('Corner', {
			{ value = 'TOPRIGHT',    text = 'Top right' },
			{ value = 'TOPLEFT',     text = 'Top left' },
			{ value = 'BOTTOMRIGHT', text = 'Bottom right' },
			{ value = 'BOTTOMLEFT',  text = 'Bottom left' },
		},
		function() return ns.ABRGetCfg().corner end,
		function(v) ns.ABRGetCfg().corner = v ns.ABRApply() end)
	AddSlider('Cross size (px)', 8, 24, 1,
		function() return ns.ABRGetCfg().size end,
		function(v) ns.ABRGetCfg().size = v ns.ABRApply() end)
end

local function PageFocus()
	AddHeader('Focus')
	local function fcfg() return ns.EUIGetFocusMarkCfg() end
	AddCheck('Raid marker on cast bar',
		function() return fcfg().enable end,
		function(v) fcfg().enable = v ns.EUIApplyFocusMark() end,
		'Shows the focus raid marker beside the focus cast bar while it is casting.')
	AddSlider('Marker size', 8, 40, 1,
		function() return fcfg().size end,
		function(v) fcfg().size = v ns.EUIApplyFocusMark() end)
	AddSlider('Gap from bar', -40, 40, 1,
		function() return fcfg().x end,
		function(v) fcfg().x = v ns.EUIApplyFocusMark() end)
	AddSlider('Vertical offset', -20, 20, 1,
		function() return fcfg().y end,
		function(v) fcfg().y = v ns.EUIApplyFocusMark() end)

	AddHeader('Out-of-range fade')
	local function frcfg() return ns.EUIGetFocusRangeCfg() end
	AddCheck('Fade focus frame when out of range',
		function() return frcfg().enable end,
		function(v) frcfg().enable = v ns.EUIApplyFocusRange() end,
		'Dims the focus frame while your focus is more than 40 yards away. Works in keys - the range check is applied through the engine, never read.')
	AddSlider('Out-of-range opacity (%)', 10, 90, 5,
		function() return math.floor(((frcfg().alpha or 0.5) * 100) + 0.5) end,
		function(v) frcfg().alpha = v / 100 ns.EUIApplyFocusRange() end)
end

local function PageInterrupt()
	AddHeader('Nameplate Interrupt')
	local function icfg() return ns.EUIIntGetCfg() end
	AddCheck('Enable',
		function() return icfg().enable end,
		function(v) icfg().enable = v ns.EUIIntApply() end)
	AddPreviewToggle(ns.EUIIntIsPreview, ns.EUIIntSetPreview)
	AddCheck('Hide icon when interrupt is ready',
		function() return icfg().hideWhenReady end,
		function(v) icfg().hideWhenReady = v ns.EUIIntApply() end)
	AddCheck('Show cooldown text',
		function() return icfg().cooldownText end,
		function(v) icfg().cooldownText = v ns.EUIIntApply() end)
	AddSlider('Icon size', 10, 60, 1,
		function() return icfg().size end,
		function(v) icfg().size = v ns.EUIIntApply() end)
	AddSlider('Text size', 6, 30, 1,
		function() return icfg().textSize end,
		function(v) icfg().textSize = v ns.EUIIntApply() end)
	AddSlider('Offset X', -150, 150, 1,
		function() return icfg().x end,
		function(v) icfg().x = v ns.EUIIntApply() end)
	AddSlider('Offset Y', -60, 60, 1,
		function() return icfg().y end,
		function(v) icfg().y = v ns.EUIIntApply() end)
end

-- Additions to the Targeted Spell Bars of EllesmereUI Mythic+ Tools.
local function PageEUISpellBars()
	AddHeader('Targeted Spell Bars')
	local function cfg() return ns.EMCGetCfg() end
	local function get(k) return function() return cfg()[k] end end
	local function set(k) return function(v) cfg()[k] = v ns.EMCApplyBars() end end
	AddPreviewToggle(ns.EMCIsPreview, ns.EMCSetPreview)

	AddHeader('Boss casts')
	AddCheck('Hide boss casts',
		get('hideBossCasts'),
		function(v) cfg().hideBossCasts = v ns.EMCApply() ShowPage('eui_tsb', true) end,
		'Off shows every cast, exactly as EllesmereUI does on its own. Switching takes effect at once for plates already on screen.')
	AddButton('Re-detect', function() ns.EMCRedetect() ShowPage('eui_tsb', true) end, 120)

	AddHeader('Cast spark')
	AddCheck('Show a spark on the cast progress',
		get('spark'), set('spark'),
		'A bright line on the leading edge of the fill, so how far a cast has come reads at a glance.')
	AddSlider('Spark width', 1, 10, 1, get('sparkWidth'), set('sparkWidth'))
	AddColor('Spark colour', get('sparkColor'), set('sparkColor'))
	AddSlider('Spark opacity', 0.1, 1, 0.05, get('sparkAlpha'), set('sparkAlpha'))

end

local function PageNP()
	AddHeader('Nameplates')
	local function dcfg() return ns.EUINPGetDispelGlowCfg() end
	AddHeader('Enemy dispel glow')
	AddCheck('Show glow without purge or soothe',
		function() return dcfg().always end,
		function(v)
			dcfg().always = v
			ns.EUINPApplyDispelGlowOverride()
		end,
		'Lets the EllesmereUI dispel glow show for Magic and Enrage effects even if your character has no purge or soothe spell. EllesmereUI\'s Dispel Glow option must still be enabled.')

	AddHeader('Shield amount')
	local function scfg() return ns.EUINPGetShieldCfg() end
	AddCheck('Show shield amount',
		function() return scfg().enable end,
		function(v) scfg().enable = v ns.EUINPApplyShield() end,
		'The text only appears while the mob actually has a shield.')
	AddPreviewToggle(ns.EUINPShieldIsPreview, ns.EUINPShieldSetPreview)
	AddCheck('Enemies only',
		function() return scfg().enemyOnly end,
		function(v) scfg().enemyOnly = v ns.EUINPApplyShield() end,
		'Off = also shows shields on friendly nameplates (Power Word: Shield and the like).')
	AddCheck('CN number style',
		function() return scfg().cn end,
		function(v) scfg().cn = v ns.EUINPApplyShield() end,
		'Chinese grouping: 300K shows as 30 wan, 1.2M as 120 wan, 150M as 1.5 yi (drawn with the Chinese signs).')
	AddSlider('Text size', 6, 24, 1,
		function() return scfg().size end,
		function(v) scfg().size = v ns.EUINPApplyShield() end)
	AddSlider('Offset X', -60, 60, 1,
		function() return scfg().offX end,
		function(v) scfg().offX = v ns.EUINPApplyShield() end)
	AddSlider('Offset Y', -30, 30, 1,
		function() return scfg().offY end,
		function(v) scfg().offY = v ns.EUINPApplyShield() end)
	AddColor('Text color',
		function() return scfg().color end,
		function(c) scfg().color = c ns.EUINPApplyShield() end)
end

local function PageEUIMeterStretch()
	if ns.hasEUIMeterIlvl then
		AddHeader('Item Level')
		AddCheck('Show item level on spec icon hover',
			function() return ns.EMIGetCfg().enable end,
			function(v) ns.EMIGetCfg().enable = v ns.EMIApply() end,
			'Rest the pointer on the spec icon of a damage meter row to see that player\'s current item level. Group members are inspected on hover, out of combat only; in combat the last known value is shown.')
	end

	AddHeader('Damage Meter Stretch')
	local function cfg() return ns.EMSGetCfg() end
	local function get(k) return function() return cfg()[k] end end
	local function set(k) return function(v) cfg()[k] = v ns.EMSApply() end end
	AddCheck('Enable', get('enable'), set('enable'),
		'Hold the handle on top of an EllesmereUI damage meter window and drag up to show more rows. Let go and the window goes back.')
	AddSlider('Rows while stretched', 5, 40, 1, get('maxRows'), set('maxRows'),
		'The most rows a window grows to. EllesmereUI draws at most 40.')
	AddCheck('Stop at the last row', get('fitToData'), set('fitToData'),
		'Do not grow past the rows that have a name in them.')
	AddCheck('Slide back on release', get('animate'), set('animate'))
	AddCheck('Work in combat', get('combat'), set('combat'))
	AddCheck('Stretch a locked window by its title bar', get('headerGrab'), set('headerGrab'),
		'With the EllesmereUI padlock closed the title bar no longer moves the window, so holding it stretches the window instead.')

	AddHeader('Handle')
	AddDropdown('Show handle', {
			{ value = 'HOVER',  text = 'While the title bar is hovered' },
			{ value = 'ALWAYS', text = 'Always' },
		},
		get('handleShow'), set('handleShow'))
	AddDropdown('Position', {
			{ value = 'ABOVE',  text = 'On top of the window' },
			{ value = 'INSIDE', text = 'Over the window\'s top edge' },
		},
		get('handlePos'), set('handlePos'))
	AddSlider('Thickness', 3, 16, 1, get('handleSize'), set('handleSize'))
	AddSlider('Opacity', 0.1, 1, 0.05, get('alpha'), set('alpha'))
	AddCheck('EllesmereUI accent colour', get('useAccent'), set('useAccent'))
	AddColor('Colour', get('color'), set('color'))
end

local function PageEUICursor()
	AddHeader('Cursor Circle')
	local function cfg() return ns.ECUGetCfg() end
	local function get(k) return function() return cfg()[k] end end
	local function set(k) return function(v) cfg()[k] = v ns.ECUApply() end end

	AddCheck('Follow the cursor every frame',
		get('everyFrame'), set('everyFrame'),
		'EllesmereUI stops moving the circle after a second of rest and takes up to 50 ms (150 ms after half a minute of rest, e.g. steering with the mouse held) to notice the mouse moving again, so the circle hangs back at the start of every movement. On, the circle is placed on the cursor every frame and never waits.')

	AddHeader('Screen edge')
	AddDropdown('At the screen edge', {
			{ value = 'clamp', text = 'Stay on screen (EllesmereUI default)' },
			{ value = 'free',  text = 'Follow the cursor onto the edge' },
			{ value = 'slide', text = 'Slide out of sight' },
			{ value = 'fade',  text = 'Fade out' },
		},
		get('edge'),
		function(v) cfg().edge = v ns.ECUApply() ShowPage('eui_cursor', true) end)
	local mode = cfg().edge
	if mode == 'slide' or mode == 'fade' then
		AddSlider('Edge zone (pixels)', 1, 30, 1, get('edgeZone'), set('edgeZone'),
			'How close to the window edge the cursor has to stop for the circle to leave. A fast flick out of the window is caught at any distance.')
	end
	if mode == 'fade' then
		AddSlider('Fade time', 0, 1, 0.05, get('fadeTime'), set('fadeTime'))
	end
end

local function PageExternals()
	AddHeader('Externals')
	local function ecfg() return ns.ExtGetCfg() end
	AddCheck('Enable',
		function() return ecfg().enable end,
		function(v) ecfg().enable = v ns.ExtApply() end)
	AddPreviewToggle(ns.ExtIsPreview, ns.ExtSetPreview)
	AddCheck('Lock position',
		function() return ecfg().lock end,
		function(v) ecfg().lock = v ns.ExtApply() end)
	AddSlider('Icon size', 16, 80, 1,
		function() return ecfg().iconSize end,
		function(v) ecfg().iconSize = v ns.ExtApply() end)
	AddColor('Icon border colour',
		function() return ecfg().borderColor end,
		function(c) ecfg().borderColor = c ns.ExtApply() end)
	AddSlider('Border size', 0, 8, 1,
		function() return ecfg().borderSize end,
		function(v) ecfg().borderSize = v ns.ExtApply() end,
		'Zero removes the border; larger values make the colour border thicker.')
	AddSlider('Text size', 6, 30, 1,
		function() return ecfg().textSize end,
		function(v) ecfg().textSize = v ns.ExtApply() end)
	AddSlider('Spacing', 0, 20, 1,
		function() return ecfg().spacing end,
		function(v) ecfg().spacing = v ns.ExtApply() end)
	AddDropdown('Grow direction', {
		{ value = 'RIGHT', text = 'Right' },
		{ value = 'LEFT', text = 'Left' },
		{ value = 'UP', text = 'Up' },
	},
		function() return ecfg().grow end,
		function(v) ecfg().grow = v ns.ExtApply() end)
	AddCheck('Play sound on new external',
		function() return ecfg().soundEnabled end,
		function(v) ecfg().soundEnabled = v ns.ExtRebuildSoundSet() end)
	AddScrollDropdown('Sound', ns.SoundOptions(ecfg().sound),
		function() return ecfg().sound end,
		function(v) ecfg().sound = v ns.ExtRebuildSoundSet() end,
		ns.PlaySoundByName,
		ns.PlaySoundByName)

	AddHeader('Sound spell list')

	AddSpellIdRow(ns.ExtSoundSpells, function()
		ns.ExtRebuildSoundSet()
		ShowPage('externals', true)
	end)
	content.cy = content.cy - 32

	local sList = ns.ExtSoundSpells()
	if #sList == 0 then AddDesc('No spells on the sound list.') end
	for idx, id in ipairs(sList) do
		local fs = content:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
		fs:SetPoint('TOPLEFT', 16, content.cy)
		fs:SetWidth(356)
		fs:SetJustifyH('LEFT')
		fs:SetWordWrap(false)
		fs:SetText(format('|T%s:18|t %s |cff888888(%d)|r', CdSpellTexture(id), CdSpellName(id), id))
		Track(fs)
		local rem = MakeFlatButton(content, 'Remove', 70, 20)
		rem:SetPoint('TOPLEFT', 380, content.cy + 3)
		rem:SetScript('OnClick', function()
			table.remove(ns.ExtSoundSpells(), idx)
			ns.ExtRebuildSoundSet()
			ShowPage('externals', true)
		end)
		Track(rem)
		content.cy = content.cy - 26
	end

	AddHeader('Glow')
	AddCheck('Enable glow',
		function() return ecfg().glow end,
		function(v) ecfg().glow = v ns.ExtApply() end)
	AddColor('Glow color',
		function() return ecfg().glowColor end,
		function(c) ecfg().glowColor = c ns.ExtApply() end)
	AddDropdown('Glow type', {
		{ value = 'pixel', text = 'Pixel Glow' },
		{ value = 'shape', text = 'Shape Glow' },
		{ value = 'autoshine', text = 'Auto Cast Shine' },
	},
		function() return ecfg().glowType end,
		function(v) ecfg().glowType = v ns.ExtApply() end)
	AddSlider('Glow thickness / strength', 1, 10, 1,
		function() return ecfg().glowThickness end,
		function(v) ecfg().glowThickness = v ns.ExtApply() end)
	AddPosition(
		function() return ecfg().x end,
		function(v) ecfg().x = v ns.ExtApply() end,
		function() return ecfg().y end,
		function(v) ecfg().y = v ns.ExtApply() end)
end

local function PageCombatText()
	AddHeader('Combat Text')
	local function cfg() return ns.CTGetCfg() end
	local function Redraw() if ns.CTIsPreview() then ns.CTApply() end end
	AddCheck('Enable',
		function() return cfg().enable end,
		function(v) cfg().enable = v ns.CTApply() end)
	AddPreviewToggle(ns.CTIsPreview, ns.CTSetPreview)
	AddCheck('Lock position',
		function() return cfg().lock end,
		function(v) cfg().lock = v ns.CTApply() end)
	local OUTLINE_OPTIONS = {
		{ value = 'NONE', text = 'None' },
		{ value = 'OUTLINE', text = 'Outline' },
		{ value = 'THICK', text = 'Thick Outline' },
		{ value = 'SLUG', text = 'Slug' },
	}
	AddDropdown('Font outline', OUTLINE_OPTIONS,
		function() return cfg().outline end,
		function(v) cfg().outline = v ns.CTApply() end)
	AddDropdown('Grow direction', { { value = 'DOWN', text = 'Down' }, { value = 'UP', text = 'Up' } },
		function() return cfg().grow end,
		function(v) cfg().grow = v ns.CTApply() end)
	AddSlider('Spacing', 0, 20, 1,
		function() return cfg().spacing end,
		function(v) cfg().spacing = v ns.CTApply() end)
	AddSlider('Message duration', 0.5, 5, 0.1,
		function() return cfg().duration end,
		function(v) cfg().duration = v end)
	AddPosition(
		function() return cfg().x end,
		function(v) cfg().x = v ns.CTApply() end,
		function() return cfg().y end,
		function(v) cfg().y = v ns.CTApply() end)

	AddHeader('Messages')
	AddCheck('Interrupt announce',
		function() return cfg().interruptEnable end,
		function(v) cfg().interruptEnable = v end,
		'Shows "Interrupted [Spell]" when you or your pet interrupt an enemy cast.')
	AddColor('Interrupt color',
		function() return cfg().interruptColor end,
		function(c) cfg().interruptColor = c Redraw() end)
	AddSlider('Interrupt text size', 10, 40, 1,
		function() return cfg().interruptSize end,
		function(v) cfg().interruptSize = v Redraw() end)
	AddCheck('Enter combat',
		function() return cfg().enterEnable end,
		function(v) cfg().enterEnable = v end)
	AddEditBoxOption('Enter combat text',
		function() return cfg().enterText end,
		function(v) cfg().enterText = v Redraw() end)
	AddColor('Enter combat color',
		function() return cfg().enterColor end,
		function(c) cfg().enterColor = c Redraw() end)
	AddSlider('Enter combat text size', 10, 40, 1,
		function() return cfg().enterSize end,
		function(v) cfg().enterSize = v Redraw() end)
	AddCheck('Leave combat',
		function() return cfg().leaveEnable end,
		function(v) cfg().leaveEnable = v end)
	AddEditBoxOption('Leave combat text',
		function() return cfg().leaveText end,
		function(v) cfg().leaveText = v Redraw() end)
	AddColor('Leave combat color',
		function() return cfg().leaveColor end,
		function(c) cfg().leaveColor = c Redraw() end)
	AddSlider('Leave combat text size', 10, 40, 1,
		function() return cfg().leaveSize end,
		function(v) cfg().leaveSize = v Redraw() end)
	AddCheck('Death alert (party/raid)',
		function() return cfg().deathEnable end,
		function(v) cfg().deathEnable = v ns.CTApply() end,
		'Announces "[Name] dead" with the class-coloured name when a party/raid member (or you) dies.')
	AddColor('Death color',
		function() return cfg().deathColor end,
		function(c) cfg().deathColor = c Redraw() end)
	AddSlider('Death text size', 10, 40, 1,
		function() return cfg().deathSize end,
		function(v) cfg().deathSize = v Redraw() end)
	AddCheck('Speak deaths (TTS)',
		function() return cfg().ttsEnable end,
		function(v) cfg().ttsEnable = v ns.CTApply() end,
		'Says "<Name> dead" out loud for party/raid deaths. Silent for your own death, for repeat deaths within 5 seconds, and for the rest of the fight after a tank dies (usually a wipe).')
	AddCheck('Shorten spoken names',
		function() return cfg().ttsShortName end,
		function(v) cfg().ttsShortName = v end,
		'Speaks only the first 5 letters of the name - "Ramboolisch dead" becomes "Rambo dead".')
	AddSlider('TTS volume', 0, 100, 5,
		function() return cfg().ttsVolume end,
		function(v) cfg().ttsVolume = v end)
	do
		local vopts = { { text = 'Use Blizzard TTS setting', value = '' } }
		local vc = _G.C_VoiceChat
		local voices = vc and vc.GetTtsVoices and vc.GetTtsVoices()
		if voices then
			for _, v in ipairs(voices) do
				if v.name then vopts[#vopts + 1] = { text = v.name, value = v.name } end
			end
		end
		AddDropdown('TTS voice', vopts,
			function() return cfg().ttsVoiceName or '' end,
			function(v) cfg().ttsVoiceName = v end)
	end
	AddButton('Preview TTS', function() ns.CTTTSPreview() end, 170)
	AddCheck('Focus death',
		function() return cfg().focusDeathEnable end,
		function(v) cfg().focusDeathEnable = v ns.CTApply() end,
		'Shows "FOCUS dead" on the feed the moment your focus dies, also when the kill clears your focus.')
	AddEditBoxOption('Focus death text',
		function() return cfg().focusDeathText end,
		function(v) cfg().focusDeathText = v Redraw() end)
	AddColor('Focus death color',
		function() return cfg().focusDeathColor end,
		function(c) cfg().focusDeathColor = c ns.CTApply() end)
	AddSlider('Focus death text size', 10, 40, 1,
		function() return cfg().focusDeathSize end,
		function(v) cfg().focusDeathSize = v ns.CTApply() end)
	AddCheck("Didn't kick",
		function() return cfg().missedKickEnable end,
		function(v) cfg().missedKickEnable = v end,
		"Shows when you press your interrupt and it stops nothing: the target was not casting, the cast could not be interrupted, or someone else kicked first. In keys it stays quiet whenever any cast is interrupted right around your kick.")
	AddEditBoxOption("Didn't kick text",
		function() return cfg().missedKickText end,
		function(v) cfg().missedKickText = v Redraw() end)
	AddColor("Didn't kick color",
		function() return cfg().missedKickColor end,
		function(c) cfg().missedKickColor = c Redraw() end)
	AddSlider("Didn't kick text size", 10, 40, 1,
		function() return cfg().missedKickSize end,
		function(v) cfg().missedKickSize = v Redraw() end)
	AddSlider("Didn't kick seconds", 0.5, 10, 0.5,
		function() return cfg().missedKickDuration end,
		function(v) cfg().missedKickDuration = v end)
	AddCheck("Didn't kick pulse",
		function() return cfg().missedKickPulse end,
		function(v) cfg().missedKickPulse = v Redraw() end)
	do
		local sounds = ns.SoundOptions(cfg().missedKickSound)
		local listed = false
		for _, o in ipairs(sounds) do
			if o.value == ns.CTMissedSound then listed = true break end
		end
		if not listed then table.insert(sounds, 2, { value = ns.CTMissedSound, text = ns.CTMissedSound }) end
		AddScrollDropdown("Didn't kick sound", sounds,
			function() return cfg().missedKickSound end,
			function(v) cfg().missedKickSound = v end,
			ns.CTPlayKickSound,
			ns.CTPlayKickSound)
	end

	AddHeader('No Target')
	AddCheck('No Target in combat',
		function() return cfg().noTargetEnable end,
		function(v) cfg().noTargetEnable = v ns.CTApply() end,
		'Shows while you are in combat with nothing targeted.')
	AddCheck('Count a dead target as no target',
		function() return cfg().noTargetDead end,
		function(v) cfg().noTargetDead = v ns.CTApply() end)
	AddEditBoxOption('No Target text',
		function() return cfg().noTargetText end,
		function(v) cfg().noTargetText = v ns.CTApply() end)
	AddColor('No Target color',
		function() return cfg().noTargetColor end,
		function(c) cfg().noTargetColor = c ns.CTApply() end)
	AddSlider('No Target text size', 10, 60, 1,
		function() return cfg().noTargetSize end,
		function(v) cfg().noTargetSize = v ns.CTApply() end)
	AddPosition(
		function() return cfg().noTargetX end,
		function(v) cfg().noTargetX = v ns.CTApply() end,
		function() return cfg().noTargetY end,
		function(v) cfg().noTargetY = v ns.CTApply() end)

	AddHeader('Ready announcements')
	AddCheck('Bloodlust ready',
		function() return cfg().bloodlustAnnounce end,
		function(v) cfg().bloodlustAnnounce = v end,
		'Shows a "Bloodlust Ready" message in this feed when Bloodlust/Heroism is available again (driven by the Bloodlust alert settings).')
	AddEditBoxOption('Bloodlust text',
		function() return cfg().bloodlustText end,
		function(v) cfg().bloodlustText = v Redraw() end)
	AddColor('Bloodlust color',
		function() return cfg().bloodlustColor end,
		function(c) cfg().bloodlustColor = c Redraw() end)
	AddSlider('Bloodlust text size', 10, 40, 1,
		function() return cfg().bloodlustSize end,
		function(v) cfg().bloodlustSize = v Redraw() end)
end

local function BuffWatchSpellList(cfg)
	local C = cfg()
	ns.BWNormalizeCategories(C)
	C.categories = C.categories or {}
	C.spellCat = C.spellCat or {}
	C.catCollapsed = C.catCollapsed or {}

	local cats, of = C.categories, C.spellCat
	local rank = {}
	for i, n in ipairs(cats) do rank[n] = i end
	local function BlockOf(id) return rank[of[id]] or 0 end

	local function Redraw()
		ns.BWApply()
		ShowPage('buffwatch', true)
	end

	AddSpellIdRow(function() return C.spells end, Redraw,
		'Spell ID from the buff tooltip or Wowhead. New spells land in Uncategorised.')

	local catBox = MakeEditBox(content, 120, 22)
	catBox:SetPoint('TOPLEFT', 196, content.cy)
	local addCat = MakeFlatButton(content, 'Add category', 110, 22)
	addCat:SetPoint('LEFT', catBox, 'RIGHT', 8, 0)
	local function doAddCat()
		local name = (catBox:GetText() or ''):match('^%s*(.-)%s*$')
		if name == '' then Msg('type a category name first') return end
		for _, n in ipairs(cats) do
			if n == name then Msg('there is already a category called "' .. name .. '"') return end
		end
		cats[#cats + 1] = name
		catBox:SetText('')
		Redraw()
	end
	addCat:SetScript('OnClick', doAddCat)
	catBox:SetScript('OnEnterPressed', function(self) doAddCat() self:ClearFocus() end)
	Tooltip(catBox, 'A heading to group buffs under, e.g. "Movement" or "Potions". Organisation only.')
	Track(catBox) Track(addCat)
	content.cy = content.cy - 32

	local list = C.spells or {}
	if #list == 0 and #cats == 0 then AddDesc('No spells watched yet.') end

	local blocks = { [0] = {} }
	for i = 1, #cats do blocks[i] = {} end
	for idx, id in ipairs(list) do
		local b = blocks[BlockOf(id)]
		b[#b + 1] = idx
	end

	local function MoveBtn(x, rot, enabled, onClick, tip)
		local b = CreateFrame('Button', nil, content)
		b:SetSize(18, 18)
		b:SetPoint('TOPLEFT', x, content.cy + 2)
		local t = b:CreateTexture(nil, 'ARTWORK')
		t:SetAllPoints()
		t:SetTexture(ARROW_TEX)
		t:SetRotation(rot)
		if enabled then
			t:SetVertexColor(0.85, 0.85, 0.85)
			b:SetScript('OnEnter', function() t:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3]) end)
			b:SetScript('OnLeave', function() t:SetVertexColor(0.85, 0.85, 0.85) end)
			b:SetScript('OnClick', onClick)
			Tooltip(b, tip)
		else
			t:SetVertexColor(0.3, 0.3, 0.3)
			b:EnableMouse(false)
		end
		Track(b)
	end

	local function MoveSpell(idx, dir)
		local id = list[idx]
		local myR = BlockOf(id)
		local nb = list[idx + dir]
		if nb and BlockOf(nb) == myR then
			list[idx], list[idx + dir] = list[idx + dir], list[idx]
		else
			local newR = myR + dir
			if newR < 0 or newR > #cats then return end
			of[id] = cats[newR]
			ns.BWNormalizeCategories(C)
		end
		Redraw()
	end

	local function SpellRow(idx, id, indent)
		local fs = content:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
		fs:SetPoint('TOPLEFT', 18 + indent, content.cy - 4)
		fs:SetWidth(196 - indent)
		fs:SetJustifyH('LEFT')
		fs:SetWordWrap(false)
		fs:SetText(format('|T%s:18|t %s', CdSpellTexture(id), CdSpellName(id)))
		Track(fs)

		local idFs = content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
		idFs:SetPoint('TOPLEFT', 440, content.cy - 4)
		idFs:SetWidth(56)
		idFs:SetJustifyH('LEFT')
		idFs:SetWordWrap(false)
		idFs:SetText(tostring(id))
		Track(idFs)

		C.texts = C.texts or {}
		local entry = C.texts[id]
		local tBox = MakeEditBox(content, 76, 20)
		tBox:SetPoint('TOPLEFT', 220, content.cy + 3)
		tBox:SetText((entry and entry.text) or '')
		tBox:SetScript('OnEnterPressed', function(self) self:ClearFocus() end)
		tBox:SetScript('OnEditFocusLost', function(self)
			local txt = self:GetText() or ''
			local tt = C.texts
			if txt == '' then
				tt[id] = nil
			else
				tt[id] = tt[id] or { size = 14, x = 0, y = 0, color = { 1, 1, 1, 1 } }
				tt[id].text = txt
			end
			ns.BWApply()
		end)
		Tooltip(tBox, 'Text drawn above this buff\'s icon - e.g. "vers" on a trinket proc. Leave empty for none.')
		Track(tBox)

		local myR = BlockOf(id)
		MoveBtn(302, math.pi / 2, idx > 1 or myR > 0,
			function() MoveSpell(idx, -1) end,
			'Move earlier. From the top of a category this moves it into the one above.')
		MoveBtn(320, -math.pi / 2, idx < #list or myR < #cats,
			function() MoveSpell(idx, 1) end,
			'Move later. From the bottom of a category this moves it into the one below.')

		local catBtn = MakeFlatButton(content, '', 18, 20)
		catBtn:SetPoint('TOPLEFT', 344, content.cy + 3)
		local ct = catBtn:CreateTexture(nil, 'OVERLAY')
		ct:SetTexture(ARROW_TEX)
		ct:SetSize(10, 10)
		ct:SetPoint('CENTER')
		ct:SetRotation(-math.pi / 2)
		catBtn:SetScript('OnClick', function()
			local opts = { { value = '', text = 'Uncategorised' } }
			for _, n in ipairs(cats) do opts[#opts + 1] = { value = n, text = n } end
			OpenScrollPopup(catBtn, opts,
				function() return of[id] or '' end,
				function(v)
					of[id] = (v ~= '' and v) or nil
					ns.BWNormalizeCategories(C)
				end,
				function() Redraw() end)
		end)
		Tooltip(catBtn, 'Category: ' .. (of[id] or 'Uncategorised'))
		Track(catBtn)

		local rem = MakeFlatButton(content, 'Remove', 66, 20)
		rem:SetPoint('TOPLEFT', 368, content.cy + 3)
		rem:SetScript('OnClick', function()
			table.remove(C.spells, idx)
			of[id] = nil
			if C.texts then C.texts[id] = nil end
			Redraw()
		end)
		Track(rem)

		content.cy = content.cy - 28
	end

	local function CategoryHeader(r, name, count)
		local collapsed = C.catCollapsed[name] and true or false

		local tw = CreateFrame('Button', nil, content)
		tw:SetSize(16, 16)
		tw:SetPoint('TOPLEFT', 16, content.cy + 1)
		local tt = tw:CreateTexture(nil, 'ARTWORK')
		tt:SetAllPoints()
		tt:SetTexture(ARROW_TEX)
		tt:SetRotation(collapsed and 0 or -math.pi / 2)
		tt:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3])
		tw:SetScript('OnClick', function()
			C.catCollapsed[name] = (not collapsed) or nil
			ShowPage('buffwatch', true)
		end)
		Tooltip(tw, collapsed and 'Expand' or 'Collapse')
		Track(tw)

		local nameBox = MakeEditBox(content, 190, 20)
		nameBox:SetPoint('TOPLEFT', 36, content.cy + 2)
		nameBox:SetText(name)
		nameBox:SetScript('OnEnterPressed', function(self) self:ClearFocus() end)
		nameBox:SetScript('OnEditFocusLost', function(self)
			local new = (self:GetText() or ''):match('^%s*(.-)%s*$')
			if new == name then return end
			if new == '' then self:SetText(name) Msg('a category needs a name') return end
			for i, n in ipairs(cats) do
				if n == new and i ~= r then
					self:SetText(name)
					Msg('there is already a category called "' .. new .. '"')
					return
				end
			end
			cats[r] = new
			for id, cn in pairs(of) do if cn == name then of[id] = new end end
			if C.catCollapsed[name] then C.catCollapsed[name] = nil C.catCollapsed[new] = true end
			Redraw()
		end)
		Tooltip(nameBox, 'Rename this category')
		Track(nameBox)

		local cnt = content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
		cnt:SetPoint('TOPLEFT', 234, content.cy - 2)
		cnt:SetWidth(60)
		cnt:SetJustifyH('LEFT')
		cnt:SetText(count == 1 and '1 buff' or (count .. ' buffs'))
		Track(cnt)

		local function MoveCat(dir)
			local o = r + dir
			if o < 1 or o > #cats then return end
			cats[r], cats[o] = cats[o], cats[r]
			ns.BWNormalizeCategories(C)
			Redraw()
		end
		MoveBtn(302, math.pi / 2, r > 1, function() MoveCat(-1) end,
			'Move this whole category earlier')
		MoveBtn(320, -math.pi / 2, r < #cats, function() MoveCat(1) end,
			'Move this whole category later')

		local del = MakeFlatButton(content, 'Delete', 64, 20)
		del:SetPoint('TOPLEFT', 344, content.cy + 3)
		del:SetScript('OnClick', function()
			table.remove(cats, r)
			C.catCollapsed[name] = nil
			for id, cn in pairs(of) do if cn == name then of[id] = nil end end
			ns.BWNormalizeCategories(C)
			Msg('category "' .. name .. '" removed; its buffs went back to Uncategorised')
			Redraw()
		end)
		Tooltip(del, 'Remove the category. Its buffs are kept and become Uncategorised.')
		Track(del)

		content.cy = content.cy - 26
	end

	local function PlainHeader(text)
		local fs = content:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
		fs:SetPoint('TOPLEFT', 20, content.cy)
		fs:SetText(text)
		fs:SetTextColor(0.55, 0.55, 0.55)
		Track(fs)
		content.cy = content.cy - 20
	end

	for r = 0, #cats do
		local name = cats[r]
		local rows = blocks[r]
		if r == 0 then
			if #cats > 0 then PlainHeader(#rows > 0 and 'Uncategorised' or 'Uncategorised (empty)') end
		else
			CategoryHeader(r, name, #rows)
		end
		if not (name and C.catCollapsed[name]) then
			local indent = (r > 0) and 12 or 0
			for _, idx in ipairs(rows) do SpellRow(idx, list[idx], indent) end
		end
	end
end

local function PageBuffWatch()
	AddHeader('Buff Watch')
	if ns.BWDisabled then
		return
	end
	local function cfg() return ns.BWGetCfg() end
	local tab = AddTabs('buffwatch', { 'Buffs', 'Settings' })

	if tab == 'Buffs' then
		BuffWatchSpellList(cfg)
		return
	end

	AddCheck('Enable',
		function() return cfg().enable end,
		function(v) cfg().enable = v ns.BWApply() end)
	AddPreviewToggle(ns.BWIsPreview, ns.BWSetPreview)
	AddCheck('Lock position',
		function() return cfg().lock end,
		function(v) cfg().lock = v ns.BWApply() end)
	AddSlider('Icon width', 16, 120, 1,
		function() return cfg().iconW end,
		function(v) cfg().iconW = v ns.BWApply() end,
		'New size applies to icons as they (re)appear; toggle Preview to see it immediately.')
	AddSlider('Icon height', 16, 120, 1,
		function() return cfg().iconH end,
		function(v) cfg().iconH = v ns.BWApply() end)
	AddSlider('Zoom (% trimmed per edge)', 0, 40, 1,
		function() return cfg().zoom end,
		function(v) cfg().zoom = v ns.BWApply() end,
		'0 shows the whole icon file including its border. 8 matches the rest of the addon. Higher zooms in further.')
	AddSlider('Text size', 6, 30, 1,
		function() return cfg().textSize end,
		function(v) cfg().textSize = v ns.BWApply() end,
		'Countdown text size. The stack count uses 3/4 of this unless given its own size under Stack count.')
	AddSlider('Spacing', 0, 20, 1,
		function() return cfg().spacing end,
		function(v) cfg().spacing = v ns.BWApply() end)
	AddSlider('Max icons', 1, 32, 1,
		function() return cfg().maxIcons end,
		function(v) cfg().maxIcons = v ns.BWApply() end)
	AddDropdown('Grow direction', {
		{ value = 'RIGHT', text = 'Right' },
		{ value = 'LEFT', text = 'Left' },
		{ value = 'DOWN', text = 'Down' },
		{ value = 'UP', text = 'Up' },
	}, function() return cfg().grow end,
		function(v) cfg().grow = v ns.BWApply() end)
	AddPosition(
		function() return cfg().x end,
		function(v) cfg().x = v ns.BWApply() end,
		function() return cfg().y end,
		function(v) cfg().y = v ns.BWApply() end)

	AddHeader('Attach to a frame')
	AddEditBoxOption('Attach to frame',
		function() return cfg().attachFrame or '' end,
		function(v) cfg().attachFrame = v ns.BWApply() end)
	AddDropdown('Attach point', {
		{ value = 'CENTER', text = 'Centre (overlay)' },
		{ value = 'TOP',    text = 'Above it' },
		{ value = 'BOTTOM', text = 'Below it' },
		{ value = 'LEFT',   text = 'Left of it' },
		{ value = 'RIGHT',  text = 'Right of it' },
	}, function() return cfg().attachPoint end,
		function(v) cfg().attachPoint = v ns.BWApply() end)
	AddSlider('Attach offset X', -200, 200, 1,
		function() return cfg().attachX end,
		function(v) cfg().attachX = v ns.BWApply() end)
	AddSlider('Attach offset Y', -200, 200, 1,
		function() return cfg().attachY end,
		function(v) cfg().attachY = v ns.BWApply() end)
	AddSlider('Stand-in offset X', -200, 200, 1,
		function() return cfg().standInX end,
		function(v) cfg().standInX = v ns.BWApply() end)
	AddSlider('Stand-in offset Y', -200, 200, 1,
		function() return cfg().standInY end,
		function(v) cfg().standInY = v ns.BWApply() end,
		'0/0 = exactly where the trinket row would have been. Only applies while attached to XerionUITrinkets with no trinket shown.')
	AddCheck('Fall back when that frame is hidden',
		function() return cfg().attachFallback end,
		function(v) cfg().attachFallback = v ns.BWApply() end,
		'With no trinket equipped or the icon hidden, the row returns to the free position above.')
	AddDropdown('Layer (strata)', STRATA_OPTIONS, function() return cfg().strata end,
		function(v) cfg().strata = v ns.BWApply() end)

	AddHeader('Stack count')
	AddCheck('Show stack count',
		function() return cfg().stackShow ~= false end,
		function(v) cfg().stackShow = v ns.BWApply() end,
		'Off hides the number on every watched buff.')
	AddSlider('Stack text size (0 = auto)', 0, 40, 1,
		function() return cfg().stackSize end,
		function(v) cfg().stackSize = v ns.BWApply() end,
		'0 keeps the old behaviour: 3/4 of the countdown text size, so it scales with it.')
	AddDropdown('Stack corner', {
		{ value = 'BOTTOMRIGHT', text = 'Bottom right' },
		{ value = 'BOTTOM',      text = 'Bottom' },
		{ value = 'BOTTOMLEFT',  text = 'Bottom left' },
		{ value = 'RIGHT',       text = 'Right' },
		{ value = 'CENTER',      text = 'Center' },
		{ value = 'LEFT',        text = 'Left' },
		{ value = 'TOPRIGHT',    text = 'Top right' },
		{ value = 'TOP',         text = 'Top' },
		{ value = 'TOPLEFT',     text = 'Top left' },
	}, function() return cfg().stackPoint end,
		function(v) cfg().stackPoint = v ns.BWApply() end)
	AddSlider('Stack X offset', -40, 40, 1,
		function() return cfg().stackX end,
		function(v) cfg().stackX = v ns.BWApply() end)
	AddSlider('Stack Y offset', -40, 40, 1,
		function() return cfg().stackY end,
		function(v) cfg().stackY = v ns.BWApply() end,
		'Nudges from the chosen corner, which already sits 1px inside the icon border.')
	AddColor('Stack color',
		function() return cfg().stackColor end,
		function(v) cfg().stackColor = v ns.BWApply() end)

	AddHeader('Custom text')
	AddSlider('Text size', 6, 40, 1,
		function() return cfg().labelSize end,
		function(v) cfg().labelSize = v ns.BWApply() end)
	AddSlider('Text X offset', -60, 60, 1,
		function() return cfg().labelX end,
		function(v) cfg().labelX = v ns.BWApply() end)
	AddSlider('Text Y offset', -60, 60, 1,
		function() return cfg().labelY end,
		function(v) cfg().labelY = v ns.BWApply() end,
		'0 sits just above the icon. Negative moves it down onto the icon.')

end

-- Bloodlust ready sound (the countdown icon has been removed).
local function PageReadyAlerts()
	AddHeader('Bloodlust ready')
	local function cfg() return ns.BLGetCfg() end
	local sounds = ns.SoundOptions(cfg().sound)
	local hasWoWSound = false
	for _, option in ipairs(sounds) do
		if option.value == 'WoW: Raid Warning' then hasWoWSound = true break end
	end
	if not hasWoWSound then table.insert(sounds, 2, { value = 'WoW: Raid Warning', text = 'WoW: Raid Warning' }) end
	AddCheck('Play sound when Bloodlust is ready',
		function() return cfg().soundEnabled end,
		function(v) cfg().soundEnabled = v end)
	AddScrollDropdown('Ready sound', sounds,
		function() return cfg().sound end,
		function(v) cfg().sound = v end,
		ns.BLPlayReadySound,
		ns.BLPlayReadySound)
	AddButton('Test sound', function() ns.BLPlayReadySound(cfg().sound) end, 120)
	AddCheck('Speak text when Bloodlust is ready',
		function() return cfg().ttsEnabled end,
		function(v) cfg().ttsEnabled = v end,
		'Uses the game text-to-speech voice in addition to the selected sound.')
	if cfg().ttsEnabled then
		AddEditBoxOption('Text to speak',
			function() return cfg().ttsText end,
			function(v) cfg().ttsText = v end)
		AddSlider('TTS volume', 0, 100, 5,
			function() return cfg().ttsVolume end,
			function(v) cfg().ttsVolume = v end)
		local vopts = { { text = 'Use Blizzard TTS setting', value = '' } }
		local vc = _G.C_VoiceChat
		local voices = vc and vc.GetTtsVoices and vc.GetTtsVoices()
		if voices then
			for _, voice in ipairs(voices) do
				if voice.name then vopts[#vopts + 1] = { text = voice.name, value = voice.name } end
			end
		end
		AddDropdown('TTS voice', vopts,
			function() return cfg().ttsVoiceName or '' end,
			function(v) cfg().ttsVoiceName = v end)
		AddButton('Test speech', function() ns.BLTestTTS() end, 120)
	end
end
local function PageRaidMarkers()
	AddHeader('Raid Markers')
	local function cfg() return ns.RMGetCfg() end
	AddCheck('Show panel',
		function() return cfg().enable end,
		function(v) cfg().enable = v ns.RMApply() end)
	AddCheck('Only show in a group/raid',
		function() return cfg().groupOnly end,
		function(v) cfg().groupOnly = v ns.RMApply() end,
		'Hide the bar while solo; show it in a party or raid. Changes made in combat apply when combat ends.')
	AddToggleButton(function() return ns.RMIsPreview() and 'Stop Preview' or 'Preview' end,
		function()
			ns.RMSetPreview(not ns.RMIsPreview())
			if CONFIG.__kiraPreviews then
				CONFIG.__kiraPreviews.raidmarkers = function()
					if ns.RMIsPreview() then ns.RMSetPreview(false) end
				end
			end
			ShowPage('raidmarkers', true)
		end)
	AddCheck('Lock position',
		function() return cfg().lock end,
		function(v) cfg().lock = v end,
		'Prevents moving the bar with right-drag.')
	AddSlider('Scale', 0.5, 2, 0.05,
		function() return cfg().scale end,
		function(v) cfg().scale = v ns.RMApply() end)
	AddSlider('Button spacing', 0, 20, 1,
		function() return cfg().spacing end,
		function(v) cfg().spacing = v ns.RMApply() end)
	AddDropdown('Orientation', {
		{ value = 'HORIZONTAL', text = 'Horizontal' },
		{ value = 'VERTICAL', text = 'Vertical' },
	}, function() return cfg().orientation end,
		function(v) cfg().orientation = v ns.RMApply() end)
	AddPosition(
		function() return cfg().x end,
		function(v) cfg().x = v ns.RMApply() end,
		function() return cfg().y end,
		function(v) cfg().y = v ns.RMApply() end)

	AddHeader('Buttons')
	AddCheck('Show clear button',
		function() return cfg().showClear end,
		function(v) cfg().showClear = v ns.RMApply() end,
		'Left: clear all target markers. Right: clear all world markers.')
	AddCheck('Show countdown button',
		function() return cfg().showCountdown end,
		function(v) cfg().showCountdown = v ns.RMApply() end,
		'Left: start a group countdown, or cancel one that is already running. Right: cancel. The clock tints orange while any countdown runs.')
	AddSlider('Countdown seconds', 1, 30, 1,
		function() return cfg().countdownSeconds end,
		function(v) cfg().countdownSeconds = v end)
	AddCheck('Show ready-check button',
		function() return cfg().showReadyCheck end,
		function(v) cfg().showReadyCheck = v ns.RMApply() end)

end

local function PageRecuperate()
	AddHeader('Recuperate')
	local function cfg() return ns.RecupGetCfg() end
	AddCheck('Enable',
		function() return cfg().enable end,
		function(v) cfg().enable = v ns.RecupApply() end)
	AddPreviewToggle(ns.RecupIsPreview, ns.RecupSetPreview)
	AddCheck('Lock position',
		function() return cfg().lock end,
		function(v) cfg().lock = v end)
	AddCheck('Show spell tooltip on hover',
		function() return cfg().showTooltip end,
		function(v) cfg().showTooltip = v end,
		'When off, hovering the icon shows nothing - just a clean clickable icon.')
	AddSlider('Show below health (%)', 10, 100, 1,
		function() return cfg().threshold end,
		function(v) cfg().threshold = v ns.RecupApply() end,
		'100 shows the icon whenever any health at all is missing. Lower it to ignore chip damage.')
	AddSlider('Fade-in range (%)', 0, 50, 1,
		function() return cfg().fadeRange end,
		function(v) cfg().fadeRange = v ns.RecupApply() end,
		'0 is a hard on/off at the threshold. Anything higher fades the icon in gradually, reaching full opacity that many percent of health below the threshold.')
	AddSlider('Icon size', 24, 96, 1,
		function() return cfg().size end,
		function(v) cfg().size = v ns.RecupApply() end)
	AddPosition(
		function() return cfg().x end,
		function(v) cfg().x = v ns.RecupApply() end,
		function() return cfg().y end,
		function(v) cfg().y = v ns.RecupApply() end)
end

-- One class page, one feature at a time: a Category dropdown under the class
-- header picks which feature's settings fill the rest of the page. Entries
-- whose module is not loaded (cond false) are dropped; with one entry left the
-- dropdown is skipped. The pick is remembered in subTab[pageKey], and every
-- category is indexed for search through Search.Variants. Returns the text of
-- the category it built.
--
-- An entry may carry `icon`, in the sidebar's NAV_ICONS shape (atlas / spell
-- with a fallback tex / tex, whole = no crop). It goes into the option's text
-- as an inline texture, so the popup rows and the closed dropdown both show it
-- with no change to the popup; the value stays the bare name, and the popup's
-- filter and the search index strip the markup (PlainName drops |T...|t).
local function CategoryPage(pageKey, entries)
	local function Markup(icon)
		if not icon then return '' end
		if icon.atlas then return '|A:' .. icon.atlas .. ':14:14|a ' end
		local tex = icon.tex
		if icon.spell and C_Spell and C_Spell.GetSpellTexture then
			local ok, id = pcall(C_Spell.GetSpellTexture, icon.spell)
			if ok and type(id) == 'number' and not (ns.IsSecret and ns.IsSecret(id)) then tex = id end
		end
		if not tex then return '' end
		if icon.whole then return '|T' .. tex .. ':14:14|t ' end
		return '|T' .. tex .. ':14:14:0:0:64:64:5:59:5:59|t '
	end

	local kept = {}
	for _, e in ipairs(entries) do
		if e and e.cond and e.build then kept[#kept + 1] = e end
	end
	if #kept == 0 then return end
	if #kept == 1 then kept[1].build() return kept[1].text end

	local cur = subTab[pageKey]
	local valid = false
	for _, e in ipairs(kept) do if e.text == cur then valid = true break end end
	if not valid then cur = kept[1].text end

	local opts, names = {}, {}
	for _, e in ipairs(kept) do
		opts[#opts + 1] = { value = e.text, text = Markup(e.icon) .. e.text }
		names[#names + 1] = e.text
	end
	Search.Variants(names, cur, 'Category')
	content.noReg = true
	AddDropdown('Category', opts,
		function() return cur end,
		function(v) subTab[pageKey] = v ShowPage(pageKey) end)
	content.noReg = nil

	for _, e in ipairs(kept) do
		if e.text == cur then e.build() return cur end
	end
end

-- Split into categories like the Death Knight page. The three builders stay
-- inside the do-block so they cost the main chunk no locals.
local PageBrewmaster
do
	local function cfg() return ns.BMGetCfg() end
	local function Get(key) return function() return cfg()[key] end end
	local function Set(key) return function(v) cfg()[key] = v ns.BMApply() end end

	local function PageOrbs()
		AddHeader('Expel Harm orbs')
		AddCheck('Enable', Get('orbEnable'), Set('orbEnable'))
		AddPreviewToggle(ns.BMOrbIsPreview, ns.BMOrbSetPreview)
		AddCheck('Lock position', Get('orbLock'), Set('orbLock'))
		AddSlider('Orb size', 6, 64, 1, Get('orbSize'), Set('orbSize'))
		AddSlider('Arc radius', 10, 80, 1, Get('orbRadius'), Set('orbRadius'),
			'Distance of the orbs from the arc centre - bigger = wider crown.')
		AddSlider('Arc spread (degrees)', 40, 180, 5, Get('orbSpread'), Set('orbSpread'),
			'How much of the circle the 5 orbs cover. They always stay evenly spaced across it.')
		AddColor('Orb color', Get('orbColor'), Set('orbColor'))
		AddPosition(Get('orbX'), Set('orbX'), Get('orbY'), Set('orbY'))
	end

	local function PageDodge()
		AddHeader('Dodge')
		AddCheck('Enable', Get('dodgeEnable'), Set('dodgeEnable'))
		AddPreviewToggle(ns.BMDodgeIsPreview, ns.BMDodgeSetPreview)
		AddCheck('Lock position', Get('dodgeLock'), Set('dodgeLock'))
		AddCheck('Only show in combat', Get('dodgeCombatOnly'), Set('dodgeCombatOnly'),
			'Unticked: the dodge text shows all the time (outside instances/combat too).')
		AddSlider('Text size', 8, 48, 1, Get('dodgeSize'), Set('dodgeSize'))
		AddColor('Text color', Get('dodgeColor'), Set('dodgeColor'))
		AddPosition(Get('dodgeX'), Set('dodgeX'), Get('dodgeY'), Set('dodgeY'))
	end

	local function PageElixir()
		AddHeader('Elixir of Determination')
		AddCheck('Enable', Get('elixEnable'), Set('elixEnable'),
			'A greyed icon with a swipe and seconds for the 15 s after the Elixir procs - it keeps counting after the shield is used up.')
		AddPreviewToggle(ns.BMElixirIsPreview, ns.BMElixirSetPreview)
		AddCheck('Lock position', Get('elixLock'), Set('elixLock'))
		AddCheck('Show icon while ready', Get('elixReady'), Set('elixReady'),
			'A full-colour icon while the Elixir can proc again. Unticked, the icon only shows during the 15 s.')
		AddSlider('Icon size', 20, 96, 1, Get('elixSize'), Set('elixSize'))
		AddCheck('Show cooldown swipe', Get('elixSwipe'), Set('elixSwipe'))
		AddCheck('Show countdown number', Get('elixText'), Set('elixText'))
		AddSlider('Countdown text size (0 = auto)', 0, 40, 1, Get('elixTextSize'), Set('elixTextSize'),
			'Auto follows the icon size.')
		AddPosition(Get('elixX'), Set('elixX'), Get('elixY'), Set('elixY'))
	end

	function PageBrewmaster()
		AddPinnedTabs('class_brew', { 'Brewmaster' },
			{ { spec = 268, tex = [[Interface\Icons\Spell_Monk_Brewmaster_Spec]] } }, 'Brewmaster')
		AddHeader('Monk')
		CategoryPage('class_brew', {
			{ cond = true, text = 'Expel Harm',              build = PageOrbs,
				icon = { spell = 322101 } },
			-- Mastery: Elusive Brawler, the Brewmaster's dodge.
			{ cond = true, text = 'Dodge',                   build = PageDodge,
				icon = { spell = 117906 } },
			{ cond = true, text = 'Elixir of Determination', build = PageElixir,
				icon = { spell = 455179 } },
		})
	end
end

local function PageCDMStacks()
	AddHeader('Cooldown Manager')
	local function cfg() return ns.CDSGetCfg() end
	AddCheck('Enable',
		function() return cfg().enable end,
		function(v) cfg().enable = v ns.CDSApply() end)

	AddHeader('Custom icon texts')

	local idBox = MakeEditBox(content, 80, 22)
	idBox:SetPoint('TOPLEFT', 16, content.cy)
	local txtBox = MakeEditBox(content, 130, 22)
	txtBox:SetPoint('LEFT', idBox, 'RIGHT', 8, 0)
	local addBtn = MakeFlatButton(content, 'Add', 60, 22)
	addBtn:SetPoint('LEFT', txtBox, 'RIGHT', 8, 0)
	local function doAddText()
		local id = tonumber(idBox:GetText())
		if not id or id <= 0 then Msg('enter a spell ID first') return end
		local list = cfg().customTexts
		list[#list + 1] = {
			spellID = math.floor(id),
			text = txtBox:GetText() or '',
			x = 0, y = 30, size = 14,
			color = { 1, 1, 1, 1 },
		}
		ns.CDSApply()
		idBox:SetText('')
		txtBox:SetText('')
		ShowPage('cdmstacks', true)
	end
	addBtn:SetScript('OnClick', doAddText)
	txtBox:SetScript('OnEnterPressed', function(self) doAddText() self:ClearFocus() end)
	Track(idBox) Track(txtBox) Track(addBtn)
	content.cy = content.cy - 32

	local list = cfg().customTexts or {}
	if #list == 0 then AddDesc('No custom texts yet.') end
	for idx, e in ipairs(list) do
		local fs = content:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
		fs:SetPoint('TOPLEFT', 16, content.cy)
		fs:SetWidth(356)
		fs:SetJustifyH('LEFT')
		fs:SetWordWrap(false)
		fs:SetText(format('|T%s:16|t %s |cff888888(%d)|r', ns.CdSpellTexture(e.spellID or 0), ns.CdSpellName(e.spellID or 0), e.spellID or 0))
		Track(fs)
		local rem = MakeFlatButton(content, 'Remove', 70, 20)
		rem:SetPoint('TOPLEFT', 380, content.cy + 3)
		rem:SetScript('OnClick', function()
			table.remove(cfg().customTexts, idx)
			ns.CDSApply()
			ShowPage('cdmstacks', true)
		end)
		Track(rem)
		content.cy = content.cy - 24

		local function lbl(x, t)
			local l = content:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
			l:SetPoint('TOPLEFT', x, content.cy - 5)
			l:SetText(t)
			l:SetTextColor(0.65, 0.65, 0.7)
			Track(l)
			return l
		end
		local function numBox(x, w, get, set)
			local b = MakeEditBox(content, w, 20)
			b:SetPoint('TOPLEFT', x, content.cy)
			b:SetJustifyH('CENTER')
			b:SetText(tostring(get()))
			local function commit(self)
				local n = tonumber(self:GetText())
				if n then set(n) ns.CDSApply() end
				self:SetText(tostring(get()))
			end
			b:SetScript('OnEnterPressed', function(self) commit(self) self:ClearFocus() end)
			b:HookScript('OnEditFocusLost', commit)
			Track(b)
		end

		local lT = lbl(20, 'Text')
		local xT = After(lT, 20, 48)
		local tb = MakeEditBox(content, 100, 20)
		tb:SetPoint('TOPLEFT', xT, content.cy)
		tb:SetText(e.text or '')
		local function commitT(self)
			e.text = self:GetText() or ''
			ns.CDSApply()
		end
		tb:SetScript('OnEnterPressed', function(self) commitT(self) self:ClearFocus() end)
		tb:HookScript('OnEditFocusLost', commitT)
		Track(tb)

		local xS = math.max(160, xT + 100 + 12)
		local lS = lbl(xS, 'Size')
		local xSb = After(lS, xS, 188)
		numBox(xSb, 36, function() return e.size or 14 end, function(v) e.size = math.floor(v) end)
		local xX = math.max(236, xSb + 36 + 12)
		local lX = lbl(xX, 'X')
		local xXb = After(lX, xX, 250)
		numBox(xXb, 44, function() return e.x or 0 end, function(v) e.x = math.floor(v) end)
		local xY = math.max(304, xXb + 44 + 10)
		local lY = lbl(xY, 'Y')
		local xYb = After(lY, xY, 318)
		numBox(xYb, 44, function() return e.y or 30 end, function(v) e.y = math.floor(v) end)

		local sw = CreateFrame('Button', nil, content)
		sw:SetSize(18, 18)
		sw:SetPoint('TOPLEFT', math.max(380, xYb + 44 + 18), content.cy - 1)
		local bord = sw:CreateTexture(nil, 'BACKGROUND')
		bord:SetPoint('TOPLEFT', -1, 1)
		bord:SetPoint('BOTTOMRIGHT', 1, -1)
		bord:SetColorTexture(0, 0, 0, 1)
		sw.tex = sw:CreateTexture(nil, 'ARTWORK')
		sw.tex:SetAllPoints()
		local function swRefresh()
			local c = e.color or { 1, 1, 1 }
			sw.tex:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, 1)
		end
		swRefresh()
		sw:SetScript('OnClick', function()
			local c = e.color or { 1, 1, 1 }
			local r, g, b = c[1] or 1, c[2] or 1, c[3] or 1
			local function applyNow()
				local nr, ng, nb = ColorPickerFrame:GetColorRGB()
				e.color = { nr, ng, nb, 1 }
				swRefresh()
				ns.CDSApply()
			end
			ColorPickerFrame:SetupColorPickerAndShow({
				r = r, g = g, b = b, hasOpacity = false,
				swatchFunc = applyNow,
				cancelFunc = function() e.color = { r, g, b, 1 } swRefresh() ns.CDSApply() end,
			})
		end)
		Tooltip(sw, 'Text colour')
		Track(sw)
		content.cy = content.cy - 30
	end

	AddHeader('Show "1" on buff stacks')

	local sBox = MakeEditBox(content, 80, 22)
	sBox:SetPoint('TOPLEFT', 16, content.cy)
	local sAdd = MakeFlatButton(content, 'Add', 60, 22)
	sAdd:SetPoint('LEFT', sBox, 'RIGHT', 8, 0)
	local function doAddStack()
		local id = tonumber(sBox:GetText())
		if not id or id <= 0 then Msg('enter a spell ID first') return end
		local list = cfg().stackOnes
		list[#list + 1] = { spellID = math.floor(id) }
		ns.CDSStackOnesApply()
		sBox:SetText('')
		ShowPage('cdmstacks', true)
	end
	sAdd:SetScript('OnClick', doAddStack)
	sBox:SetScript('OnEnterPressed', function(self) doAddStack() self:ClearFocus() end)
	Track(sBox) Track(sAdd)
	content.cy = content.cy - 32

	local slist = cfg().stackOnes or {}
	if #slist == 0 then AddDesc('No buffs added yet.') end
	for idx, e in ipairs(slist) do
		local fs2 = content:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
		fs2:SetPoint('TOPLEFT', 16, content.cy)
		fs2:SetWidth(356)
		fs2:SetJustifyH('LEFT')
		fs2:SetWordWrap(false)
		fs2:SetText(format('|T%s:16|t %s |cff888888(%d)|r',
			ns.CdSpellTexture(e.spellID or 0), ns.CdSpellName(e.spellID or 0), e.spellID or 0))
		Track(fs2)
		local rem2 = MakeFlatButton(content, 'Remove', 70, 20)
		rem2:SetPoint('TOPLEFT', 380, content.cy + 3)
		rem2:SetScript('OnClick', function()
			table.remove(cfg().stackOnes, idx)
			ns.CDSStackOnesApply()
			ShowPage('cdmstacks', true)
		end)
		Track(rem2)
		content.cy = content.cy - 24
	end

	AddCheck('Match the real stack text',
		function() return cfg().stackOneMatch end,
		function(v) cfg().stackOneMatch = v ns.CDSStackOnesApply() ShowPage('cdmstacks', true) end,
		'Draw the "1" with the same font, size, colour and corner as the Cooldown Manager\'s own stack count (or whatever your skin made of it), so going from 1 to 2 changes only the digit. Off: your own font, size, colour and position.')
	if cfg().stackOneMatch then
		AddSlider('"1" nudge X', -30, 30, 1,
			function() return cfg().stackOneNudgeX or 0 end,
			function(v) cfg().stackOneNudgeX = v ns.CDSStackOnesApply() end,
			'Shift from the spot where the real count sits.')
		AddSlider('"1" nudge Y', -30, 30, 1,
			function() return cfg().stackOneNudgeY or 0 end,
			function(v) cfg().stackOneNudgeY = v ns.CDSStackOnesApply() end)
	else
		AddSlider('"1" text size', 8, 40, 1,
			function() return cfg().stackOneSize or 14 end,
			function(v) cfg().stackOneSize = v ns.CDSStackOnesApply() end)
		AddSlider('"1" X offset', -60, 60, 1,
			function() return cfg().stackOneX or 0 end,
			function(v) cfg().stackOneX = v ns.CDSStackOnesApply() end,
			'Offset from the icon center.')
		AddSlider('"1" Y offset', -60, 60, 1,
			function() return cfg().stackOneY or 30 end,
			function(v) cfg().stackOneY = v ns.CDSStackOnesApply() end)
		AddColor('"1" colour',
			function() return cfg().stackOneColor end,
			function(c) cfg().stackOneColor = c ns.CDSStackOnesApply() end)
	end
end

local function PageTargetedSpells()
	AddHeader('Targeted Spells')
	local function cfg() return ns.TSGetCfg() end
	AddCheck('Enable',
		function() return cfg().enable end,
		function(v) cfg().enable = v ns.TSApply() end,
		'Off by default. While off the plugin does not touch TargetedSpells at all - its icons draw exactly the way that addon draws them.')
	AddCheck('Swipe: start colored, fill to black',
		function() return cfg().reverse end,
		function(v) cfg().reverse = v ns.TSApply() end,
		'Reverses the cast swipe: the icon starts fully coloured and darkens as the cast completes. The addon\'s own "Show Swipe" setting must be on.')
end

-- One spec button, the way the Druid page has Guardian: WoG Charges is
-- Protection only, and the aura reminder (every spec) sits beside it in the
-- Category dropdown. The two builders are locals of PagePaladin so they cost
-- the main chunk nothing.
local function PagePaladin()
	local function PageWoG()
		AddHeader('WoG Charges')
		if ns.SLDisabled then
			return
		end
		local function cfg() return ns.SLGetCfg() end
		AddCheck('Enable',
			function() return cfg().enable end,
			function(v) cfg().enable = v ns.SLApply() end)
		AddPreviewToggle(ns.SLIsPreview, ns.SLSetPreview)
		AddCheck('Lock position',
			function() return cfg().lock end,
			function(v) cfg().lock = v end)

		AddHeader('Bar')
		AddCheck('Show bar',
			function() return cfg().barEnable end,
			function(v) cfg().barEnable = v ns.SLApply() end,
			'8 boxed segments, left to right: each banked free WoG fills 3, charges continue after them.')
		AddCheck('Always show bar',
			function() return cfg().alwaysShow end,
			function(v) cfg().alwaysShow = v ns.SLApply() end,
			'Keep the empty boxed bar visible with no charges and no free procs, so the layout never shifts.')
		AddDropdown('Bar layer (strata)', STRATA_OPTIONS, function() return cfg().barStrata end,
			function(v) cfg().barStrata = v ns.SLApply() end)
		AddCheck('Show corner timer texts',
			function() return cfg().showTimers end,
			function(v) cfg().showTimers = v end,
			'Remaining time of the free proc (left) and the building charges (right), plain seconds.')
		AddSlider('Width', 100, 800, 1,
			function() return cfg().width end,
			function(v) cfg().width = v ns.SLApply() end)
		AddSlider('Height', 4, 40, 1,
			function() return cfg().height end,
			function(v) cfg().height = v ns.SLApply() end)
		AddSlider('Timer text size', 8, 24, 1,
			function() return cfg().textSize end,
			function(v) cfg().textSize = v ns.SLApply() end)
		AddSlider('Background opacity', 0, 1, 0.05,
			function() return cfg().bgAlpha end,
			function(v) cfg().bgAlpha = v ns.SLApply() end,
			'Opacity of empty cells: 1 = solid, 0.7 matches the EllesmereUI cast bar background, 0 = invisible.')
		AddColor('Background color',
			function() return cfg().bgColor end,
			function(c) cfg().bgColor = c ns.SLApply() end)
		AddColor('Free WoG color',
			function() return cfg().freeColor end,
			function(c) cfg().freeColor = c ns.SLApply() end)
		AddCheck('True stacks above the bar (engine)',
			function() return ns.SLGetCfg().engineDisplay end,
			function(v) ns.SLGetCfg().engineDisplay = v ns.SLApply() end,
			'Two engine-rendered displays above the bar: the real stack count and time left on the free WoG (left) and the charge buff (right). Correct even in M+, but display only - it cannot fill the bar. Experimental 12.1 API.')
		AddColor('Charges color',
			function() return cfg().chargeColor end,
			function(c) cfg().chargeColor = c ns.SLApply() end)
		AddPosition(
			function() return cfg().barX end,
			function(v) cfg().barX = v ns.SLApply() end,
			function() return cfg().barY end,
			function(v) cfg().barY = v ns.SLApply() end)
	end

	local function PageAura()
		local function cfg() return ns.PAUGetCfg() end
		local function get(k) return function() return cfg()[k] end end
		local function set(k) return function(v) cfg()[k] = v ns.PAUApply() end end
		AddHeader('Aura reminder')
		AddCheck('Enable', get('enable'), set('enable'),
			'Crusader Aura on (mounted or not): shows Devotion Aura as missing. On a mount without Crusader Aura: shows Crusader Aura, for the faster mount speed. Every spec.')
		AddCheck('Only in Mythic+', get('mplusOnly'), set('mplusOnly'),
			'Only inside a Mythic dungeon: while the key runs, and before it goes in. Unticked: everywhere.')
		AddPreviewToggle(ns.PAUIsPreview, ns.PAUSetPreview)
		AddCheck('Lock position', get('lock'), set('lock'),
			'Prevents moving the icon with right-drag while previewing.')

		AddHeader('Icon')
		AddSlider('Icon size', 16, 128, 1, get('iconSize'), set('iconSize'))
		AddPosition(get('x'), set('x'), get('y'), set('y'))

		AddHeader('Text')
		AddSlider('Text size', 8, 60, 1, get('textSize'), set('textSize'))
		AddColor('Text color', get('textColor'), set('textColor'))
		AddDropdown('Text position',
			{ { value = 'BOTTOM', text = 'Below the icon' }, { value = 'TOP', text = 'Above the icon' },
			  { value = 'LEFT', text = 'Left of the icon' }, { value = 'RIGHT', text = 'Right of the icon' },
			  { value = 'CENTER', text = 'On the icon' } },
			get('textPos'), set('textPos'))
		AddSlider('Text X offset', -100, 100, 1, get('textX'), set('textX'))
		AddSlider('Text Y offset', -100, 100, 1, get('textY'), set('textY'))
	end

	AddPinnedTabs('class_prot', { 'Protection' },
		{ { spec = 66, tex = [[Interface\Icons\Ability_Paladin_ShieldoftheTemplar]] } }, 'Protection')
	AddHeader('Paladin')
	CategoryPage('class_prot', {
		{ cond = ns.hasShiningLight, text = 'WoG Charges', build = PageWoG,
			icon = { spell = 85673 } },
		{ cond = ns.hasPaladinAura,  text = 'Aura',        build = PageAura,
			icon = { spell = 465, tex = [[Interface\Icons\Spell_Holy_DevotionAura]] } },
	})
end

local function PageMage()
	AddHeader('Mage')
	AddHeader('Alter Time Health')
	local function cfg() return ns.MageGetCfg() end
	AddCheck('Enable',
		function() return cfg().enable end,
		function(v) cfg().enable = v ns.MageApply() end)
	AddPreviewToggle(ns.MageIsPreview, ns.MageSetPreview)
	AddCheck('Lock position',
		function() return cfg().lock end,
		function(v) cfg().lock = v ns.MageApply() end,
		'Prevents moving the text with right-drag.')
	AddSlider('Text size', 8, 60, 1,
		function() return cfg().size end,
		function(v) cfg().size = v ns.MageApply() end)
	AddCheck('Anchor to Alter Time CDM buff icon',
		function() return cfg().anchorCDM end,
		function(v) cfg().anchorCDM = v ns.MageApply() end,
		'Rides the Alter Time icon in the Cooldown Manager (offsets below). Falls back to the free screen position if the icon is not found. Preview always uses the free position.')
	AddSlider('Icon offset X', -60, 60, 1,
		function() return cfg().anchorX end,
		function(v) cfg().anchorX = v ns.MageApply() end,
		'Offset from the buff icon center, used while anchored.')
	AddSlider('Icon offset Y', -60, 60, 1,
		function() return cfg().anchorY end,
		function(v) cfg().anchorY = v ns.MageApply() end)
	AddPosition(
		function() return cfg().x end,
		function(v) cfg().x = v ns.MageApply() end,
		function() return cfg().y end,
		function(v) cfg().y = v ns.MageApply() end)
end

local function PageEUIMissing()
	AddHeader('EllesmereUI')

	local function Line(ok, name, addon, what)
	end
	Line(ns.hasEUINP, 'Nameplates', 'EllesmereUINameplates',
		'Shield amount text on EllesmereUI nameplates.')
	Line(ns.hasEUIMythicCast, 'Targeted Spell Bars', 'EllesmereUIMythicTimer',
		'A boss cast filter, a cast spark and a movable raid marker on the Targeted Spell Bars.')
end

-- The Death Knight sub-pages from here down, and PagePutrefy inside the block,
-- are shown only by PageDeathKnight's tabs, so they all live in its do-block
-- and cost the main chunk no local (it peaks within a few of the 200). The
-- moved builders keep their column-0 indentation.
local PageDeathKnight
do
local function PageBloodDK()
	AddHeader('Death and Decay timer')
	local function cfg() return ns.CDSGetCfg() end
	AddCheck('Enable D&D timer',
		function() return cfg().dndEnable end,
		function(v) cfg().dndEnable = v ns.CDSApply() end)
	AddSlider('Timer text size', 8, 40, 1,
		function() return cfg().dndSize end,
		function(v) cfg().dndSize = v ns.CDSApply() end)
	AddSlider('Timer text X offset', -60, 60, 1,
		function() return cfg().dndX end,
		function(v) cfg().dndX = v ns.CDSApply() end,
		'Offset from the icon center.')
	AddSlider('Timer text Y offset', -60, 60, 1,
		function() return cfg().dndY end,
		function(v) cfg().dndY = v ns.CDSApply() end)

	AddHeader('Cleaving Strikes glow')
	AddCheck('Glow for 4 seconds after D&D ends',
		function() return cfg().dndGlow end,
		function(v) cfg().dndGlow = v ns.CDSApply() end,
		'Blood with Cleaving Strikes. Lights the D&D icon from 10 to 14 seconds after your cast, while the bonus lingers.')
	AddColor('Glow color',
		function() return cfg().dndGlowColor end,
		function(c) cfg().dndGlowColor = c ns.CDSApply() end)
	AddDropdown('Glow type', ns.GLOW_TYPES,
		function() return cfg().dndGlowType end,
		function(v) cfg().dndGlowType = v ns.CDSApply() end)
	AddSlider('Glow thickness / strength', 1, 10, 1,
		function() return cfg().dndGlowThickness end,
		function(v) cfg().dndGlowThickness = v ns.CDSApply() end)

	AddHeader('Death and Decay sound')
	AddCheck('Play sound after D&D',
		function() return cfg().dndSoundEnable end,
		function(v) cfg().dndSoundEnable = v ns.CDSApply() end,
		'Blood only. Rings 13 seconds after your own Death and Decay; a recast restarts the wait.')
	AddScrollDropdown('Sound', ns.SoundOptions(cfg().dndSound),
		function() return cfg().dndSound end,
		function(v) cfg().dndSound = v end,
		ns.PlaySoundByName,
		ns.PlaySoundByName)
end

local function PageControlUndead()
	AddHeader('Control Undead timer')
	local function cfg() return ns.CUGetCfg() end
	AddCheck('Enable',
		function() return cfg().enable end,
		function(v) cfg().enable = v ns.CUApply() end)
	AddPreviewToggle(ns.CUIsPreview, ns.CUSetPreview)
	AddCheck('Lock position',
		function() return cfg().lock end,
		function(v) cfg().lock = v end)

	AddHeader('Timing')
	AddCheck('Hide when the minion is lost',
		function() return cfg().hideOnPetLost end,
		function(v) cfg().hideOnPetLost = v ns.CUApply() end,
		'Clears the icon as soon as the charmed undead dies or breaks free.')
	AddSlider('Warning threshold (seconds)', 0, 120, 5,
		function() return cfg().warnAt end,
		function(v) cfg().warnAt = v ns.CUApply() end,
		'The countdown switches to the warning colour below this many seconds.')

	AddHeader('Icon')
	AddSlider('Icon size', 16, 128, 1,
		function() return cfg().iconSize end,
		function(v) cfg().iconSize = v ns.CUApply() end)
	AddSlider('Countdown text size (0 = auto)', 0, 40, 1,
		function() return cfg().textSize end,
		function(v) cfg().textSize = v ns.CUApply() end)
	AddCheck('Cooldown swipe',
		function() return cfg().showSwipe end,
		function(v) cfg().showSwipe = v ns.CUApply() end,
		'Darkened sweep across the icon as the control time runs out.')
	AddColor('Countdown colour',
		function() return cfg().textColor end,
		function(c) cfg().textColor = c ns.CUApply() end)
	AddColor('Warning colour',
		function() return cfg().warnColor end,
		function(c) cfg().warnColor = c ns.CUApply() end)
	AddDropdown('Layer (strata)', STRATA_OPTIONS, function() return cfg().strata end,
		function(v) cfg().strata = v ns.CUApply() end)
	AddPosition(
		function() return cfg().x end,
		function(v) cfg().x = v ns.CUApply() end,
		function() return cfg().y end,
		function(v) cfg().y = v ns.CUApply() end)
end

local function PageBoilingPoint()
	AddHeader('Boiling Point')
	local function cfg() return ns.BPGetCfg() end
	AddCheck('Enable',
		function() return cfg().enable end,
		function(v) cfg().enable = v ns.BPApply() end)
	AddPreviewToggle(ns.BPIsPreview, ns.BPSetPreview)
	AddCheck('Lock position',
		function() return cfg().lock end,
		function(v) cfg().lock = v end)

	AddHeader('Display')
	AddSlider('Bar length', 20, 400, 2,
		function() return cfg().barLength end,
		function(v) cfg().barLength = v ns.BPApply() end,
		'Along the direction it drains.')
	AddSlider('Bar thickness', 4, 60, 1,
		function() return cfg().barThickness end,
		function(v) cfg().barThickness = v ns.BPApply() end,
		'Across it.')
	AddColor('Bar colour',
		function() return cfg().barColor end,
		function(c) cfg().barColor = c ns.BPApply() end)
	AddColor('Background colour',
		function() return cfg().barBg end,
		function(c) cfg().barBg = c ns.BPApply() end)
	AddCheck('Show countdown number',
		function() return cfg().barText end,
		function(v) cfg().barText = v ns.BPApply() end,
		'Seconds remaining, drawn in the middle of the bar.')
	AddSlider('Countdown text size (0 = auto)', 0, 40, 1,
		function() return cfg().durSize end,
		function(v) cfg().durSize = v ns.BPApply() end,
		'Auto follows the bar\'s thickness.')
	AddColor('Countdown colour',
		function() return cfg().textColor end,
		function(c) cfg().textColor = c ns.BPApply() end)
	AddDropdown('Layer (strata)', STRATA_OPTIONS, function() return cfg().strata end,
		function(v) cfg().strata = v ns.BPApply() end)

	AddHeader('Proc bar')
	AddCheck('Show a bar while the proc is up',
		function() return cfg().procBar end,
		function(v) cfg().procBar = v ns.BPApply() ShowPage('class_dk', true) end)
	if cfg().procBar then
		AddColor('Proc bar colour',
			function() return cfg().procColor end,
			function(c) cfg().procColor = c ns.BPApply() end)
	end

	AddHeader('Proc glow')
	AddCheck('Glow while Blood Boil is glowing',
		function() return cfg().procGlow end,
		function(v) cfg().procGlow = v ns.BPApply() ShowPage('class_dk', true) end)
	if cfg().procGlow then
		AddColor('Glow colour',
			function() return cfg().procGlowColor end,
			function(c) cfg().procGlowColor = c ns.BPApply() end)
		AddSlider('Glow thickness', 1, 10, 1,
			function() return cfg().procGlowThickness end,
			function(v) cfg().procGlowThickness = v ns.BPApply() end,
			'Dashes march around the edge of the bar; this is how fat each dash is.')
	end

	AddHeader('Position')
	AddPosition(
		function() return cfg().x end,
		function(v) cfg().x = v ns.BPApply() end,
		function() return cfg().y end,
		function(v) cfg().y = v ns.BPApply() end)
end

local function PageBloodIsLife()
	AddHeader('The Blood is Life')
	local function cfg() return ns.BILGetCfg() end
	AddCheck('Enable',
		function() return cfg().enable end,
		function(v) cfg().enable = v ns.BILApply() end)
	AddPreviewToggle(ns.BILIsPreview, ns.BILSetPreview)
	AddCheck('Lock position',
		function() return cfg().lock end,
		function(v) cfg().lock = v end)

	AddHeader('Icon')
	AddSlider('Icon width', 16, 128, 1,
		function() return cfg().width end,
		function(v) cfg().width = v ns.BILApply() end)
	AddSlider('Icon height', 16, 128, 1,
		function() return cfg().height end,
		function(v) cfg().height = v ns.BILApply() end,
		'Width and height are separate. The art is square, so an uneven icon trims the long side.')
	AddCheck('Show cooldown swipe',
		function() return cfg().showSwipe end,
		function(v) cfg().showSwipe = v ns.BILApply() end,
		'The 10-second sweep around the icon. It runs |cffffd200reversed|r: the icon starts clear and fills as time runs out.\n\nDecoration only - hiding it changes nothing else.')
	AddColor('Border colour',
		function() return cfg().border end,
		function(c) cfg().border = c ns.BILApply() end)
	AddCheck('Show countdown number',
		function() return cfg().durText end,
		function(v) cfg().durText = v ns.BILApply() end,
		'Seconds remaining, drawn in the middle of the icon.')
	AddSlider('Countdown text size (0 = auto)', 0, 40, 1,
		function() return cfg().durSize end,
		function(v) cfg().durSize = v ns.BILApply() end,
		'Auto follows the icon\'s short side.')
	AddColor('Countdown colour',
		function() return cfg().textColor end,
		function(c) cfg().textColor = c ns.BILApply() end)

	AddHeader('Glow')
	AddColor('Glow colour',
		function() return cfg().glowColor end,
		function(c) cfg().glowColor = c ns.BILApply() end)
	AddSlider('Glow thickness (pixels)', 1, 4, 1,
		function() return cfg().glowThickness end,
		function(v) cfg().glowThickness = v ns.BILApply() end)

	AddDropdown('Layer (strata)', STRATA_OPTIONS, function() return cfg().strata end,
		function(v) cfg().strata = v ns.BILApply() end)

	AddHeader('Position')
	AddCheck('Anchor to an EllesmereUI buff group',
		function() return cfg().euiAnchor end,
		function(v) cfg().euiAnchor = v ns.BILApply() ShowPage('class_dk', true) end,
		'Rides an EllesmereUI Cooldown Manager buff/aura group instead of a free screen position - nothing to set up on the EllesmereUI side. It anchors to the group container, so it works even with no buff up.')
	if cfg().euiAnchor then
		AddDropdown('Group', ns.CDMGroupOptions and ns.CDMGroupOptions() or { { value = '', text = 'Auto' } },
			function() return cfg().euiBarKey or '' end,
			function(v) cfg().euiBarKey = v ns.BILApply() ShowPage('class_dk', true) end)
		AddDropdown('Placement', ns.CDMPlaceOptions and ns.CDMPlaceOptions(cfg()) or {
			{ value = 'CENTER', text = 'Centred on the group' },
			{ value = 'AFTER',  text = 'After the group (tail)' },
			{ value = 'BEFORE', text = 'Before the group' },
		}, function() return cfg().euiPlace or 'CENTER' end,
			function(v) cfg().euiPlace = v ns.BILApply() ShowPage('class_dk', true) end)
		AddSlider('Group offset X', -300, 300, 1,
			function() return cfg().euiOffsetX end,
			function(v) cfg().euiOffsetX = v ns.BILApply() end,
			'Nudge away from the group. Right-drag while Preview is on writes these two for you.')
		AddSlider('Group offset Y', -300, 300, 1,
			function() return cfg().euiOffsetY end,
			function(v) cfg().euiOffsetY = v ns.BILApply() end)
	else
		AddPosition(
			function() return cfg().x end,
			function(v) cfg().x = v ns.BILApply() end,
			function() return cfg().y end,
			function(v) cfg().y = v ns.BILApply() end)
	end

	if ns.hasBloodBeast then
		AddHeader('Bloodbeast damage')
		local function bb() return ns.BBGetCfg() end
		AddCheck('Enable damage text',
			function() return bb().enable end,
			function(v) bb().enable = v ns.BBApply() end)
		AddPreviewToggle(ns.BBIsPreview, ns.BBSetPreview)
		AddCheck('Lock text position',
			function() return bb().lock end,
			function(v) bb().lock = v end,
			'Right-drag the text to move it while its Preview is on and this is off.')
		AddSlider('Text size', 10, 48, 1,
			function() return bb().size end,
			function(v) bb().size = v ns.BBApply() end)
		AddColor('"Bloodbeast:" colour',
			function() return bb().labelColor end,
			function(c) bb().labelColor = c ns.BBApply() end)
		AddColor('Number colour',
			function() return bb().valueColor end,
			function(c) bb().valueColor = c ns.BBApply() end)
		AddDropdown('Text layer (strata)', STRATA_OPTIONS, function() return bb().strata end,
			function(v) bb().strata = v ns.BBApply() end)
		AddPosition(
			function() return bb().x end,
			function(v) bb().x = v ns.BBApply() end,
			function() return bb().y end,
			function(v) bb().y = v ns.BBApply() end)
	end
end

local function PageReapersMark()
	AddHeader('Reaper\'s Mark')
	if ns.RKMUnavailable then
		AddDesc('This needs the game\'s aura container widgets and they are not available on this client, so there is nothing to show here.')
		return
	end
	local function cfg() return ns.RKMGetCfg() end
	AddCheck('Enable',
		function() return cfg().enable end,
		function(v) cfg().enable = v ns.RKMApply() end)
	AddPreviewToggle(ns.RKMIsPreview, ns.RKMSetPreview)
	AddCheck('Lock position',
		function() return cfg().lock end,
		function(v) cfg().lock = v ns.RKMApply() end)

	AddHeader('Icon')
	AddSlider('Icon width', 16, 128, 1,
		function() return cfg().width end,
		function(v) cfg().width = v ns.RKMApply() end)
	AddSlider('Icon height', 16, 128, 1,
		function() return cfg().height end,
		function(v) cfg().height = v ns.RKMApply() end)
	AddSlider('Zoom (% trimmed per edge)', 0, 40, 1,
		function() return cfg().zoom end,
		function(v) cfg().zoom = v ns.RKMApply() end,
		'0 shows the whole icon file including its border. 8 matches the rest of the addon. Higher zooms in further.')
	AddCheck('Show cooldown swipe',
		function() return cfg().showSwipe end,
		function(v) cfg().showSwipe = v ns.RKMApply() end)
	AddColor('Border colour',
		function() return cfg().border end,
		function(c) cfg().border = c ns.RKMApply() end)

	AddHeader('Duration')
	AddCheck('Show duration',
		function() return cfg().durText end,
		function(v) cfg().durText = v ns.RKMApply() end)
	AddSlider('Duration text size (0 = auto)', 0, 40, 1,
		function() return cfg().durSize end,
		function(v) cfg().durSize = v ns.RKMApply() end)

	AddHeader('Stacks')
	AddSlider('Stacks text size', 6, 40, 1,
		function() return cfg().stackSize end,
		function(v) cfg().stackSize = v ns.RKMApply() end)
	AddSlider('Stacks X offset', -60, 60, 1,
		function() return cfg().stackX end,
		function(v) cfg().stackX = v ns.RKMApply() end,
		'From the icon\'s centre.')
	AddSlider('Stacks Y offset', -60, 60, 1,
		function() return cfg().stackY end,
		function(v) cfg().stackY = v ns.RKMApply() end)
	AddColor('Stacks colour',
		function() return cfg().stackColor end,
		function(c) cfg().stackColor = c ns.RKMApply() end)

	AddDropdown('Layer (strata)', STRATA_OPTIONS, function() return cfg().strata end,
		function(v) cfg().strata = v ns.RKMApply() end)

	AddHeader('Position')
	AddCheck('Anchor to an EllesmereUI buff group',
		function() return cfg().euiAnchor end,
		function(v) cfg().euiAnchor = v ns.RKMApply() ShowPage('class_dk', true) end,
		'Rides an EllesmereUI Cooldown Manager buff/aura group instead of a free screen position, like The Blood is Life.')
	if cfg().euiAnchor then
		AddDropdown('Group', ns.CDMGroupOptions and ns.CDMGroupOptions() or { { value = '', text = 'Auto' } },
			function() return cfg().euiBarKey or '' end,
			function(v) cfg().euiBarKey = v ns.RKMApply() ShowPage('class_dk', true) end)
		AddDropdown('Placement', ns.CDMPlaceOptions and ns.CDMPlaceOptions(cfg()) or {
			{ value = 'CENTER', text = 'Centred on the group' },
			{ value = 'AFTER',  text = 'After the group (tail)' },
			{ value = 'BEFORE', text = 'Before the group' },
		}, function() return cfg().euiPlace or 'CENTER' end,
			function(v) cfg().euiPlace = v ns.RKMApply() ShowPage('class_dk', true) end)
		AddSlider('Group offset X', -300, 300, 1,
			function() return cfg().euiOffsetX end,
			function(v) cfg().euiOffsetX = v ns.RKMApply() end,
			'Right-drag while Preview is on writes these two for you.')
		AddSlider('Group offset Y', -300, 300, 1,
			function() return cfg().euiOffsetY end,
			function(v) cfg().euiOffsetY = v ns.RKMApply() end)
	else
		AddPosition(
			function() return cfg().x end,
			function(v) cfg().x = v ns.RKMApply() end,
			function() return cfg().y end,
			function(v) cfg().y = v ns.RKMApply() end)
	end
end

local function PageBlightfall()
	AddHeader('Blightfall chain')
	local function cfg() return ns.BLFGetCfg() end
	AddCheck('Enable',
		function() return cfg().enable end,
		function(v) cfg().enable = v ns.BLFApply() end,
		'Unholy: Dark Transformation starts a countdown to Soul Reaper, Soul Reaper starts one to Blightfall.')
	AddPreviewToggle(ns.BLFIsPreview, ns.BLFSetPreview)
	AddCheck('Lock position',
		function() return cfg().lock end,
		function(v) cfg().lock = v end,
		'Unlocked, right-drag it while Preview is on.')

	AddHeader('Timing')
	AddSlider('Soul Reaper after Dark Transformation (sec)', 0.5, 15, 0.5,
		function() return cfg().delaySR end,
		function(v) cfg().delaySR = v end,
		'7 is the single-target timing. Tune it for AoE.')
	AddSlider('Blightfall after Soul Reaper (sec)', 0.5, 15, 0.5,
		function() return cfg().delayBF end,
		function(v) cfg().delayBF = v end,
		'Counted from the Soul Reaper press, not from Dark Transformation.')

	AddHeader('Display')
	AddSlider('Icon size', 16, 160, 1,
		function() return cfg().iconSize end,
		function(v) cfg().iconSize = v ns.BLFApply() end)
	AddDropdown('Countdown position', {
		{ value = 'BELOW',  text = 'Below the icon' },
		{ value = 'ABOVE',  text = 'Above the icon' },
		{ value = 'CENTER', text = 'On the icon' },
	}, function() return cfg().textPos end,
		function(v) cfg().textPos = v ns.BLFApply() end)
	AddSlider('Countdown X offset', -150, 150, 1,
		function() return cfg().textX end,
		function(v) cfg().textX = v ns.BLFApply() end)
	AddSlider('Countdown Y offset', -150, 150, 1,
		function() return cfg().textY end,
		function(v) cfg().textY = v ns.BLFApply() end)
	AddCheck('Grow as it nears NOW',
		function() return cfg().growPulse end,
		function(v) cfg().growPulse = v ns.BLFApply() ShowPage('class_dk', true) end)
	if cfg().growPulse then
		AddSlider('Start growing at (sec left)', 0.5, 5, 0.5,
			function() return cfg().growStart end,
			function(v) cfg().growStart = v end)
		AddSlider('Size at NOW', 1.2, 3, 0.1,
			function() return cfg().growMax end,
			function(v) cfg().growMax = v end)
	end
	AddDropdown('Countdown precision', {
		{ value = 0, text = 'Whole seconds (6)' },
		{ value = 1, text = '1 decimal (5.2)' },
	}, function() return cfg().decimals end,
		function(v) cfg().decimals = v ns.BLFApply() end)
	AddSlider('Countdown text size (0 = auto)', 0, 48, 1,
		function() return cfg().textSize end,
		function(v) cfg().textSize = v ns.BLFApply() end)
	AddDropdown('Layer (strata)', STRATA_OPTIONS, function() return cfg().strata end,
		function(v) cfg().strata = v ns.BLFApply() end)

	AddHeader('Sound')
	AddCheck('Voice countdown',
		function() return cfg().voice end,
		function(v) cfg().voice = v end,
		'"Soul Reaper in", 3, 2, 1, "Now" in your text-to-speech voice.')
	AddSlider('Voice volume', 0, 100, 5,
		function() return cfg().voiceVolume end,
		function(v) cfg().voiceVolume = v end)
	AddScrollDropdown('Sound at NOW', ns.SoundOptions(cfg().sound),
		function() return cfg().sound end,
		function(v) cfg().sound = v end,
		ns.PlaySoundByName,
		ns.PlaySoundByName)

	AddHeader('Position')
	AddPosition(
		function() return cfg().x end,
		function(v) cfg().x = v ns.BLFApply() end,
		function() return cfg().y end,
		function(v) cfg().y = v ns.BLFApply() end)
end

local function PageDRWIcon()
	AddHeader('Custom buff icons')
	local function cfg() return ns.DRWGetCfg() end

	AddCheck('Bone Shield',
		function() return cfg().bone end,
		function(v) cfg().bone = v ns.DRWApply() end,
		'Uses |cffffd200Media\\BoneShieldFace.png|r. Replace that file to change the picture, then reload.')
end
local function PageDRWSound()
	AddHeader('DRW sound')
	local function cfg() return ns.DRWSGetCfg() end
	AddCheck('Enable',
		function() return cfg().enable end,
		function(v) cfg().enable = v ns.DRWSApply() end)
	AddCheck('Ring on refresh',
		function() return cfg().onRefresh end,
		function(v) cfg().onRefresh = v end,
		'The weapon is still up and its duration was put back to full. This is the edge no "on buff gain" option can hear.')
	AddCheck('Ring on gain',
		function() return cfg().onGain end,
		function(v) cfg().onGain = v end,
		'The first application. EllesmereUI\'s per-icon |cffffd200Audio on Buff Gain|r already covers this for most people; tick it here only if you do not use that, or the gain plays twice.')
	AddScrollDropdown('Sound', ns.SoundOptions(cfg().sound),
		function() return cfg().sound end,
		function(v) cfg().sound = v end,
		ns.PlaySoundByName,
		ns.PlaySoundByName)
end
local function PageBoneShield()
	AddHeader('Bone Shield')
	local function cfg() return ns.BSGetCfg() end
	AddCheck('Enable',
		function() return cfg().enable end,
		function(v) cfg().enable = v ns.BSApply() end)
	AddPreviewToggle(ns.BSIsPreview, ns.BSSetPreview)

	AddHeader('Glow')
	AddCheck('Enable glow',
		function() return cfg().glow end,
		function(v) cfg().glow = v ns.BSApply() end)
	AddSlider('Glow at (seconds left)', 1, 29, 1,
		function() return cfg().glowThreshold end,
		function(v) cfg().glowThreshold = v ns.BSApply() end,
		'The glow starts when Bone Shield has this many seconds or fewer left, and stops the moment you refresh it.')
	AddColor('Glow color',
		function() return cfg().glowColor end,
		function(c) cfg().glowColor = c ns.BSApply() end)

	AddHeader('Low stacks')
	AddCheck('Glow on low stacks',
		function() return cfg().stackWarn end,
		function(v) cfg().stackWarn = v ns.BSApply() end)

	AddHeader('Sound')
	AddCheck('Play sound',
		function() return cfg().soundEnabled end,
		function(v) cfg().soundEnabled = v ns.BSApply() end)
	AddSlider('Sound at (seconds left)', 1, 29, 1,
		function() return cfg().soundThreshold end,
		function(v) cfg().soundThreshold = v ns.BSApply() end,
		'Rings once per Bone Shield window when it drops to this many seconds. Refreshing re-arms it.')
	AddCheck('Only in combat',
		function() return cfg().soundInCombatOnly end,
		function(v) cfg().soundInCombatOnly = v ns.BSApply() end,
		'On: silent out of combat. If Bone Shield is already inside the window when combat starts, it rings then.')
	AddScrollDropdown('Sound', ns.SoundOptions(cfg().sound),
		function() return cfg().sound end,
		function(v) cfg().sound = v end,
		ns.PlaySoundByName,
		ns.PlaySoundByName)

	AddButton('Forget learned refresh spells', function() ns.BSForgetLearned() end, 220)
end

	-- Unholy: one bar per Forbidden Sacrifice stack
	-- (XerionUI-Plugin_Putrefy.lua, named after its first version).
	local function PagePutrefy()
		local function cfg() return ns.PFGetCfg() end
		local function Get(key) return function() return cfg()[key] end end
		local function GetOn(key) return function() return cfg()[key] ~= false end end
		local function Set(key) return function(v) cfg()[key] = v ns.PFApply() end end

		AddHeader('Forbidden Sacrifice')
		AddCheck('Enable', Get('enable'), Set('enable'))
		AddPreviewToggle(ns.PFIsPreview, ns.PFSetPreview)
		AddCheck('Lock position', Get('lock'), Set('lock'),
			'Unlocked, right-drag the bars while Preview is on.')

		AddHeader('Bars')
		AddSlider('Length', 60, 600, 1, Get('width'), Set('width'))
		AddSlider('Height', 6, 60, 1, Get('height'), Set('height'))
		AddDropdown('Grow direction', {
			{ value = 'DOWN', text = 'Down' },
			{ value = 'UP',   text = 'Up' },
		}, Get('grow'), Set('grow'))
		AddSlider('Space between the bars', 0, 30, 1, Get('spacing'), Set('spacing'))
		AddColor('Bar colour', Get('color'), Set('color'))
		AddSlider('Background opacity', 0, 1, 0.05, Get('bgAlpha'), Set('bgAlpha'))

		AddHeader('Icon')
		AddCheck('Show the icon', GetOn('showIcon'), Set('showIcon'))
		-- An empty or unreadable entry goes back to the default icon, and the
		-- box is rewritten so it always shows the ID in use.
		local box
		box = AddEditBoxOption('Icon ID',
			function() return tostring(cfg().iconID or ns.PFDefaultIcon) end,
			function(text)
				local id = tonumber(text)
				cfg().iconID = (id and id > 0) and math.floor(id) or ns.PFDefaultIcon
				ns.PFApply()
				if box then box:SetText(tostring(cfg().iconID)) end
			end, 120)

		AddHeader('Timer')
		AddCheck('Show the timer', GetOn('showTimer'), Set('showTimer'))
		AddSlider('Text size', 6, 30, 1, Get('textSize'), Set('textSize'))

		AddPosition(Get('x'), Set('x'), Get('y'), Set('y'))
	end

	-- WHY THE PAGE HAS SPEC BUTTONS
	-- One Category dropdown held ten features of two specs, so the user asked
	-- for Blood | Unholy buttons on top (the pinned strip Kira Reminders uses),
	-- Blood first, and the dropdown under them listing only that spec's
	-- features. The Blood is Life is in both lists because it is a San'layn
	-- talent both specs take (DRW summons the beast for Blood, Dark
	-- Transformation for Unholy); Control Undead is in both because every Death
	-- Knight has it. Reaper's Mark is Deathbringer, which Unholy cannot pick.
	local SPECS = { 'Blood', 'Unholy' }

	-- Category icons, each the spell the feature is about; the fallback files
	-- are the ones the modules themselves draw when the spell is not readable.
	-- Buff icons has no spell of its own (it repaints icons), so it wears the
	-- XerionUI logo the user picked for it.
	local ICON = {
		dnd       = { spell = 43265 },                      -- Death and Decay
		bone      = { spell = 195181 },                     -- Bone Shield
		boil      = { spell = 50842 },                      -- Blood Boil
		bil       = { tex = 2032221 },                      -- BloodIsLife's BIL_ICON
		reaper    = { spell = 439843 },                     -- Reaper's Mark
		buffIcons = { tex = [[Interface\Icons\INV_Misc_QuestionMark]], whole = true },
		drw       = { spell = 49028 },                      -- Dancing Rune Weapon
		control   = { spell = 111673, tex = 237511 },       -- Control Undead
		blight    = { spell = 1271967, tex = 5976940 },     -- Blightfall
		putrefy   = { tex = 136157 },                       -- Forbidden Sacrifice (Putrefy.lua's DEFAULT_ICON)
	}

	local function Entries(spec)
		if spec == 'Unholy' then
			return {
				{ cond = ns.hasBloodIsLife,   text = 'The Blood is Life', build = PageBloodIsLife,  icon = ICON.bil },
				{ cond = ns.hasBlightfall,    text = 'Blightfall chain',  build = PageBlightfall,   icon = ICON.blight },
				{ cond = ns.hasPutrefy,       text = 'Forbidden Sacrifice', build = PagePutrefy,    icon = ICON.putrefy },
				{ cond = ns.hasControlUndead, text = 'Control Undead',    build = PageControlUndead, icon = ICON.control },
			}
		end
		return {
			{ cond = ns.hasCDMStacks,     text = 'Death and Decay',   build = PageBloodDK,       icon = ICON.dnd },
			{ cond = ns.hasBoneShield,    text = 'Bone Shield',       build = PageBoneShield,    icon = ICON.bone },
			{ cond = ns.hasBoilingPoint,  text = 'Boiling Point',     build = PageBoilingPoint,  icon = ICON.boil },
			{ cond = ns.hasBloodIsLife,   text = 'The Blood is Life', build = PageBloodIsLife,   icon = ICON.bil },
			{ cond = ns.hasReapersMark,   text = 'Reaper\'s Mark',    build = PageReapersMark,   icon = ICON.reaper },
			{ cond = ns.hasDRWIcon,       text = 'Buff icons',        build = PageDRWIcon,       icon = ICON.buffIcons },
			{ cond = ns.hasDRWSound,      text = 'DRW sound',         build = PageDRWSound,      icon = ICON.drw },
			{ cond = ns.hasControlUndead, text = 'Control Undead',    build = PageControlUndead, icon = ICON.control },
		}
	end

	local function Lists(list, text)
		for _, e in ipairs(list) do
			if e.cond and e.text == text then return true end
		end
		return false
	end

	local SPEC_ICONS = {
		{ spec = 250, tex = [[Interface\Icons\Spell_Deathknight_BloodPresence]] },
		{ spec = 252, tex = [[Interface\Icons\Spell_Deathknight_UnholyPresence]] },
	}

	-- The window's memory, not saved: the spec on show and each spec's last
	-- category, so Unholy -> Blood -> Unholy lands where it left off.
	local shownSpec, lastCat = 'Blood', {}

	-- Spec and category share subTab.class_dk, which is how everything else
	-- reaches this page: a spec button writes 'Blood' or 'Unholy' there, while
	-- search results and the modules' "open my settings" (ShowConfigSubTab with
	-- 'Forbidden Sacrifice', 'The Blood is Life', ...) write a category, and the category
	-- then decides the spec. One that sits in both lists stays on the spec
	-- already shown. The search indexer rebuilds the page with every value in
	-- turn; it must not move what the user sees, hence the indexing check.
	function PageDeathKnight()
		local v = subTab.class_dk
		local spec, cat = shownSpec, v
		if v == 'Blood' or v == 'Unholy' then
			spec, cat = v, lastCat[v]
		elseif v and not Lists(Entries(spec), v) then
			local other = (spec == 'Blood') and 'Unholy' or 'Blood'
			if Lists(Entries(other), v) then spec = other end
		end
		if not v then cat = lastCat[spec] end

		AddPinnedTabs('class_dk', SPECS, SPEC_ICONS, spec)
		AddHeader('Death Knight')
		subTab.class_dk = cat
		local shown = CategoryPage('class_dk', Entries(spec))

		-- The indexer walks content.variants, which CategoryPage just set to
		-- this spec's categories only; the spec names go in front so the other
		-- spec's list gets built and indexed too.
		local variants = { SPECS[1], SPECS[2] }
		for _, n in ipairs(content.variants or {}) do variants[#variants + 1] = n end
		content.variants = variants

		if not content.indexing then
			shownSpec = spec
			lastCat[spec] = shown
			subTab.class_dk = shown
		end
	end
end

-- Fiery Brand is Vengeance only, so the page gets the one spec button, the
-- way the Death Knight page has Blood | Unholy. Monk, Paladin and Shaman below
-- do the same for the one spec everything on their page is for.
local function PageFieryBrand()
	AddPinnedTabs('class_veng', { 'Vengeance' },
		{ { spec = 581, tex = [[Interface\Icons\Ability_DemonHunter_SpecTank]] } }, 'Vengeance')
	AddHeader('Demon Hunter')
	AddHeader('Fiery Brand Phases')
	if ns.FBDisabled then
		return
	end
	local function cfg() return ns.FBGetCfg() end
	AddCheck('Enable',
		function() return cfg().enable end,
		function(v) cfg().enable = v ns.FBApply() end)
	AddPreviewToggle(ns.FBIsPreview, ns.FBSetPreview)
	AddCheck('Lock position',
		function() return cfg().lock end,
		function(v) cfg().lock = v end)

	AddHeader('Icon')
	AddSlider('Icon width', 16, 128, 1,
		function() return cfg().iconW end,
		function(v) cfg().iconW = v ns.FBApply() end)
	AddSlider('Icon height', 16, 128, 1,
		function() return cfg().iconH end,
		function(v) cfg().iconH = v ns.FBApply() end)
	AddSlider('Countdown text size (0 = auto)', 0, 40, 1,
		function() return cfg().durSize end,
		function(v) cfg().durSize = v ns.FBApply() end,
		'Size of the countdown number inside the icon.')
	AddDropdown('Layer (strata)', STRATA_OPTIONS, function() return cfg().strata end,
		function(v) cfg().strata = v ns.FBApply() end)
	AddPosition(
		function() return cfg().x end,
		function(v) cfg().x = v ns.FBApply() end,
		function() return cfg().y end,
		function(v) cfg().y = v ns.FBApply() end)

	AddHeader('Phases')
	AddCheck('Desaturate in debuff phase',
		function() return cfg().desatDebuff end,
		function(v) cfg().desatDebuff = v ns.FBApply() end,
		'Grey out the icon once the buff on you has ended and only the target debuff remains.')
	AddColor('Buff phase border',
		function() return cfg().buffBorder end,
		function(c) cfg().buffBorder = c ns.FBApply() end)
	AddColor('Debuff phase border',
		function() return cfg().debuffBorder end,
		function(c) cfg().debuffBorder = c ns.FBApply() end)
	AddColor('Buff phase text',
		function() return cfg().buffText end,
		function(c) cfg().buffText = c ns.FBApply() end)
	AddColor('Debuff phase text',
		function() return cfg().debuffText end,
		function(c) cfg().debuffText = c ns.FBApply() end)
end

local function PageInterrupts()
	AddHeader('Party Interrupts')
	AddDesc('Party kick cooldowns. Keep the current cooldown bars or switch to kick icons anchored beside EllesmereUI party health bars.')
	local function cfg() return ns.IKGetCfg() end
	AddCheck('Enable',
		function() return cfg().enable end,
		function(v) cfg().enable = v ns.IKApply() end)
	AddCheck('Lock position',
		function() return cfg().lock end,
		function(v) cfg().lock = v ns.IKApply() end,
		'Prevents moving the bars with right-drag during preview.')
	AddPreviewToggle(ns.IKIsPreview, ns.IKSetPreview)

	AddHeader('Who')
	AddCheck('Include yourself',
		function() return cfg().showSelf end,
		function(v) cfg().showSelf = v ns.IKApply() end,
		'Your own bar comes first and follows your real cooldown, talents included.')
	AddCheck('Only while in a group',
		function() return cfg().groupOnly end,
		function(v) cfg().groupOnly = v ns.IKApply() end)
	AddCheck('Hide in raids',
		function() return cfg().hideInRaid end,
		function(v) cfg().hideInRaid = v ns.IKApply() end,
		'A five-man tool: raid groups only ever show your own subgroup anyway.')
	AddCheck('Show bars while ready',
		function() return cfg().showReady end,
		function(v) cfg().showReady = v ns.IKApply() end,
		'Off: a bar appears only while that kick is on cooldown and leaves when it is back.')

	AddHeader('Party kicks')
	AddCheck('Detect kicks from interrupted enemy casts',
		function() return cfg().observe end,
		function(v) cfg().observe = v end,
		'An interrupted enemy cast is charged to the party member who did it when the client names them. When it does not, it goes to the only member whose kick is ready, else to the ready member with the shortest kick, party order breaking ties. Your own kicks are never charged to anyone else.')
	AddCheck('Confirm with the built-in damage meter',
		function() return cfg().meterConfirm end,
		function(v) cfg().meterConfirm = v ns.IKApply() end,
		'A stun, a knock or a dying caster ends a cast exactly like a kick does. The damage meter\'s Interrupts counter only moves for a real interrupt, so a cast that ended is charged only when that counter moved within a second of it. Turn off if the bars stop reacting at all; /xerionkick shows whether the meter is reporting.')

	AddHeader('Display')
	AddDropdown('Variant', {
		{ value = 'bar', text = 'Cooldown bars (current)' },
		{ value = 'icon', text = 'Icons beside EllesmereUI party frames' },
	}, function() return cfg().displayMode end,
		function(v) cfg().displayMode = v ns.IKApply() ns.ShowConfigPage('interrupts') end)
	if cfg().displayMode == 'icon' then
		AddDropdown('Side of health bar', {
			{ value = 'LEFT', text = 'Left' },
			{ value = 'RIGHT', text = 'Right' },
		}, function() return cfg().partySide end,
			function(v) cfg().partySide = v ns.IKApply() end)
		AddSlider('Icon size', 12, 48, 1,
			function() return cfg().iconSize end,
			function(v) cfg().iconSize = v ns.IKApply() end)
		AddSlider('Gap from health bar', 0, 20, 1,
			function() return cfg().partyGap end,
			function(v) cfg().partyGap = v ns.IKApply() end)
	end

	AddHeader('Bars')
	AddDropdown('Grow', {
		{ value = 'DOWN', text = 'Down' },
		{ value = 'UP',   text = 'Up' },
	}, function() return cfg().growth end,
		function(v) cfg().growth = v ns.IKApply() end)
	AddSlider('Bar width', 80, 400, 1,
		function() return cfg().width end,
		function(v) cfg().width = v ns.IKApply() end)
	AddSlider('Bar height', 10, 50, 1,
		function() return cfg().height end,
		function(v) cfg().height = v ns.IKApply() end,
		'The icon is square and takes the bar height.')
	AddSlider('Spacing', 0, 20, 1,
		function() return cfg().spacing end,
		function(v) cfg().spacing = v ns.IKApply() end)
	AddSlider('Icon gap', 0, 10, 1,
		function() return cfg().iconGap end,
		function(v) cfg().iconGap = v ns.IKApply() end,
		'Empty space between the icon and the bar. The gap shows through to whatever is behind the row, not the bar background, so the icon reads as its own box.')
	AddSlider('Text size', 8, 30, 1,
		function() return cfg().textSize end,
		function(v) cfg().textSize = v ns.IKApply() end)
	AddSlider('Background opacity', 0, 1, 0.05,
		function() return cfg().bgAlpha end,
		function(v) cfg().bgAlpha = v ns.IKApply() end)
	AddCheck('Icon',
		function() return cfg().showIcon end,
		function(v) cfg().showIcon = v ns.IKApply() end)
	AddDropdown('Icon shows', {
		{ value = 'kick',   text = 'The kick' },
		{ value = 'kicked', text = 'The interrupted spell' },
	}, function() return cfg().iconSource end,
		function(v) cfg().iconSource = v ns.IKApply() end)
	AddCheck('Raid marker of the kicked mob',
		function() return cfg().showMark end,
		function(v) cfg().showMark = v ns.IKApply() end,
		'Left of the icon, while the bar counts down: the marker that was on the mob whose cast got kicked. Nothing shows for an unmarked mob.')
	AddCheck('Remaining time',
		function() return cfg().showTimer end,
		function(v) cfg().showTimer = v ns.IKApply() end)
	AddPosition(
		function() return cfg().x end,
		function(v) cfg().x = v ns.IKApply() end,
		function() return cfg().y end,
		function(v) cfg().y = v ns.IKApply() end)
end

local function PageHealerExternal()
	AddHeader('Healer External')
	AddDesc('Needs a macro on the healer\'s side: they paste the line from "The healer\'s macro" below under the /cast of their external. Each press whispers you and starts the timer. Without that macro the bars cannot know the external was used.')
	local function cfg() return ns.HXGetCfg() end
	AddCheck('Enable',
		function() return cfg().enable end,
		function(v) cfg().enable = v ns.HXApply() end)
	AddCheck('Lock position',
		function() return cfg().lock end,
		function(v) cfg().lock = v ns.HXApply() end,
		'Prevents moving the bars with right-drag during preview.')
	AddPreviewToggle(ns.HXIsPreview, ns.HXSetPreview)

	AddHeader('The press')
	AddSlider('Reaction delay', 0, 5, 0.5,
		function() return cfg().delay end,
		function(v) cfg().delay = v end,
		'Seconds between the external landing on you and your press. The bar starts this far into its cooldown.')
	AddCheck('Reset button on hover',
		function() return cfg().hoverReset ~= false end,
		function(v) cfg().hoverReset = v ns.HXApply() end,
		'Hover an icon whose timer is running and a red X appears in its corner; click it to cancel a timer you started by mistake. While a timer runs that icon catches the mouse; a ready icon never does.')
	local h = ns.HXHealer and ns.HXHealer()
	if h then
		local label = tostring(h.name)
		local cc = C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(h.class)
		if cc and cc.WrapTextInColorCode then label = cc:WrapTextInColorCode(label) end
		AddDesc(string.format('Healer right now: %s, %d external(s) on the bars%s. Their macro: %s.', label, h.count or 0,
			(h.class == 'PRIEST' and not h.spec) and ' (spec not inspected yet: Pain Suppression shown until it is)' or '',
			h.armed and 'seen' or 'not seen yet'))
	else
		AddDesc('No healer right now: the bars follow the party member with the Healer role assigned.')
	end
	AddButton('Refresh', function() ns.ShowConfigPage('healerexternal') end, 120)
	if h and not h.armed then
		AddButton('Trust their macro', function()
			ns.HXTrigger('arm')
			ns.ShowConfigPage('healerexternal')
		end, 160)
	end

	AddHeader('The healer\'s macro')
	AddCheck('Start the timer from the healer\'s whisper',
		function() return cfg().whisper ~= false end,
		function(v) cfg().whisper = v end)
	AddCheck('Ignore whispers while the timer runs',
		function() return cfg().whisperGuard ~= false end,
		function(v) cfg().whisperGuard = v end,
		'The macro whispers on every press, also when the healer mashes the key while the spell is still down. On: a whisper only starts an external that is ready or has under 10 seconds left. Turn it off for an external with two charges.')
	AddEditBoxOption('Word the macro line carries',
		function() return cfg().whisperWord end,
		function(v)
			v = tostring(v or ''):gsub('%s+', ''):lower()
			if v == '' then v = 'hx' end
			if v ~= cfg().whisperWord then
				cfg().whisperWord = v
				-- Redraws the macro lines below. The box also commits when it
				-- loses focus to a closing window or a page switch, and that must
				-- neither reopen the window nor pull you back to this page.
				C_Timer.After(0, function()
					if CONFIG and CONFIG:IsShown() and currentPage == 'healerexternal' then
						ns.ShowConfigPage('healerexternal')
					end
				end)
			end
		end, 120)
	AddEditBoxOption('Line for the healer\'s macro (click, Ctrl+A, Ctrl+C)',
		function() return ns.HXMacroLine and ns.HXMacroLine() or '' end,
		function() end, 320)

	AddHeader('For the whole party')
	AddCheck('Also start the timer from the healer\'s party chat line',
		function() return cfg().partyChat end,
		function(v) cfg().partyChat = v end)
	AddEditBoxOption('Party line for the healer\'s macro',
		function() return ns.HXMacroLine and ns.HXMacroLine('party') or '' end,
		function() end, 320)

	AddHeader('Who')
	AddCheck('Only while in a group',
		function() return cfg().groupOnly end,
		function(v) cfg().groupOnly = v ns.HXApply() end)
	AddCheck('Hide in raids',
		function() return cfg().hideInRaid end,
		function(v) cfg().hideInRaid = v ns.HXApply() end,
		'A five-man tool: a raid has several healers and no single external to wait for.')
	AddCheck('Show bars while ready',
		function() return cfg().showReady end,
		function(v) cfg().showReady = v ns.HXApply() end,
		'Off: a bar appears only while that external is on cooldown and leaves when it is back.')

	AddHeader('Cooldown per external')
	local function ClassLabel(class, text)
		local cname = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class
		local cc = C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class)
		if cc and cc.WrapTextInColorCode then cname = cc:WrapTextInColorCode(cname) end
		return cname .. '  ' .. text
	end
	for _, s in ipairs(ns.HXSpellList and ns.HXSpellList() or {}) do
		AddEditBoxOption(ClassLabel(s.class, s.name),
			function()
				local v = cfg().spellCd[s.spell]
				return tostring((type(v) == 'number' and v > 0) and v or s.default)
			end,
			function(v)
				local n = tonumber(v)
				cfg().spellCd[s.spell] = (n and n > 0 and n ~= s.default) and n or nil
				ns.HXApply()
			end, 70)
	end

	AddHeader('Display')
	AddDropdown('Style', {
		{ value = 'ICON', text = 'Icon' },
		{ value = 'BAR',  text = 'Bar' },
	}, function() return cfg().style end,
		function(v)
			cfg().style = v
			ns.HXApply()
			C_Timer.After(0, function() ns.ShowConfigPage('healerexternal') end)
		end)
	AddDropdown('Grow', {
		{ value = 'RIGHT', text = 'Right' },
		{ value = 'LEFT',  text = 'Left' },
		{ value = 'DOWN',  text = 'Down' },
		{ value = 'UP',    text = 'Up' },
	}, function() return cfg().growth end,
		function(v) cfg().growth = v ns.HXApply() end)
	if cfg().style == 'BAR' then
		AddSlider('Bar width', 80, 400, 1,
			function() return cfg().width end,
			function(v) cfg().width = v ns.HXApply() end)
		AddSlider('Bar height', 10, 50, 1,
			function() return cfg().height end,
			function(v) cfg().height = v ns.HXApply() end,
			'The spell icon is square and takes the bar height.')
		AddSlider('Background opacity', 0, 1, 0.05,
			function() return cfg().bgAlpha end,
			function(v) cfg().bgAlpha = v ns.HXApply() end)
		AddCheck('Spell icon',
			function() return cfg().showIcon end,
			function(v) cfg().showIcon = v ns.HXApply() end)
	else
		AddSlider('Icon size', 20, 100, 1,
			function() return cfg().iconSize end,
			function(v) cfg().iconSize = v ns.HXApply() end)
		AddCheck('Grey out while on cooldown',
			function() return cfg().desaturate ~= false end,
			function(v) cfg().desaturate = v ns.HXApply() end,
			'The swipe runs either way; this also drains the colour from the icon until the external is back.')
	end
	AddSlider('Spacing', 0, 20, 1,
		function() return cfg().spacing end,
		function(v) cfg().spacing = v ns.HXApply() end)
	AddSlider('Text size', 8, 30, 1,
		function() return cfg().textSize end,
		function(v) cfg().textSize = v ns.HXApply() end)
	AddCheck('Remaining time',
		function() return cfg().showTimer end,
		function(v) cfg().showTimer = v ns.HXApply() end)
	AddPosition(
		function() return cfg().x end,
		function(v) cfg().x = v ns.HXApply() end,
		function() return cfg().y end,
		function(v) cfg().y = v ns.HXApply() end)
end

-- One page, two pinned tabs (the bar, and the debuff row hung off it) - they
-- were two sidebar entries until the tree was regrouped, and 'cotank_debuffs'
-- is still accepted as a page key (see the alias on its Page() line). They live
-- in a block so the shared helpers cost the main chunk nothing - it is close to
-- Lua's 200-local limit.
local PageCoTank
do
	local POINTS9 = {
		{ value = 'TOPLEFT',     text = 'Top left' },
		{ value = 'TOP',         text = 'Top' },
		{ value = 'TOPRIGHT',    text = 'Top right' },
		{ value = 'LEFT',        text = 'Left' },
		{ value = 'CENTER',      text = 'Center' },
		{ value = 'RIGHT',       text = 'Right' },
		{ value = 'BOTTOMLEFT',  text = 'Bottom left' },
		{ value = 'BOTTOM',      text = 'Bottom' },
		{ value = 'BOTTOMRIGHT', text = 'Bottom right' },
	}

	local function cfg() return ns.CoTGetCfg() end
	local function Get(key) return function() return cfg()[key] end end
	-- `~= false` for the switches that default on: a profile saved before the
	-- key existed reads nil, and nil has to mean "on".
	local function GetOn(key) return function() return cfg()[key] ~= false end end
	local function Set(key) return function(v) cfg()[key] = v ns.CoTApply() end end

	-- A text block is the same five rows for the name, the health reading, the
	-- countdown and the stacks.
	local function TextRows(prefix, showKey, range)
		if showKey then AddCheck('Show', GetOn(showKey), Set(showKey)) end
		AddSlider('Text size', 6, 40, 1, Get(prefix .. 'Size'), Set(prefix .. 'Size'))
		AddDropdown('Anchor', POINTS9, Get(prefix .. 'Point'), Set(prefix .. 'Point'))
		AddSlider('X offset', -range, range, 1, Get(prefix .. 'X'), Set(prefix .. 'X'))
		AddSlider('Y offset', -range, range, 1, Get(prefix .. 'Y'), Set(prefix .. 'Y'))
	end

	local function FrameTab()
		AddHeader('Co-Tank Frame')
		AddCheck('Enable', Get('enable'), Set('enable'))
		AddPreviewToggle(ns.CoTIsPreview, ns.CoTSetPreview)
		AddCheck('Lock position', Get('lock'), Set('lock'))
		AddCheck('Only while you are tank-specced', GetOn('tankOnly'), Set('tankOnly'))
		AddEditBoxOption('Always show this player (blank = automatic)',
			function() return cfg().pinName or '' end,
			function(v) cfg().pinName = Trim(v) ns.CoTApply() end)

		AddHeader('Bar')
		AddSlider('Width', 60, 500, 1, Get('width'), Set('width'))
		AddSlider('Height', 8, 80, 1, Get('height'), Set('height'))
		AddSlider('Background opacity', 0, 1, 0.05, Get('bgAlpha'), Set('bgAlpha'),
			'What sits behind the empty part of the bar. The bar itself is always the co-tank\'s class colour.')
		AddPosition(Get('x'), Set('x'), Get('y'), Set('y'))

		AddHeader('Name')
		TextRows('name', nil, 200)

		AddHeader('Health percent')
		TextRows('health', 'healthShow', 200)
	end

	local function DebuffsTab()
		AddHeader('Boss Debuffs')
		if ns.CoTNoDebuffs then
			AddDesc('The debuff row needs the 12.1 aura container and is not available on this client. The health bar still works.')
			return
		end
		AddCheck('Show debuffs', GetOn('debuffEnable'), Set('debuffEnable'))
		AddPreviewToggle(ns.CoTIsPreview, ns.CoTSetPreview)
		AddCheck('Boss and role debuffs only', GetOn('debuffBossOnly'), Set('debuffBossOnly'),
			'The debuffs Blizzard\'s raid frames show big: the ones the game flags as a boss debuff or as a tank, healer or damage role debuff. If the row stays empty on a fight that has a tank debuff, turn this off: only the game knows which debuffs carry the flags.')
		AddCheck('Tooltip on mouseover', GetOn('debuffTooltip'), Set('debuffTooltip'),
			'The icons never take clicks, so they cannot get between you and the world.')

		AddHeader('Icons')
		AddSlider('Max icons', 1, 10, 1, Get('debuffMax'), Set('debuffMax'))
		AddSlider('Icon size', 12, 80, 1, Get('debuffSize'), Set('debuffSize'))
		AddSlider('Spacing', 0, 20, 1, Get('debuffSpacing'), Set('debuffSpacing'))
		AddDropdown('Grow direction', {
			{ value = 'RIGHT', text = 'Right' },
			{ value = 'LEFT', text = 'Left' },
			{ value = 'DOWN', text = 'Down' },
			{ value = 'UP', text = 'Up' },
		}, Get('debuffGrow'), Set('debuffGrow'))
		AddCheck('Debuff type border', GetOn('debuffBorder'), Set('debuffBorder'),
			'Coloured by the game from the debuff type: magic, curse, disease, poison, bleed, and red for a debuff with no type - which is most boss tank debuffs.')
		AddSlider('Border thickness', 1, 4, 1, Get('debuffBorderSize'), Set('debuffBorderSize'))

		AddHeader('Where the row sits')
		AddDropdown('Corner of the bar', POINTS9, Get('debuffAttach'), Set('debuffAttach'))
		AddSlider('X offset', -300, 300, 1, Get('debuffX'), Set('debuffX'))
		AddSlider('Y offset', -300, 300, 1, Get('debuffY'), Set('debuffY'),
			'The row follows the bar: move the bar and the debuffs come with it.')

		AddHeader('Countdown')
		TextRows('dur', 'durShow', 40)

		AddHeader('Stacks')
		TextRows('stack', 'stackShow', 40)
	end

	function PageCoTank()
		local tab = AddPinnedTabs('cotank', { 'Frame', 'Boss Debuffs' })
		if tab == 'Boss Debuffs' then DebuffsTab() else FrameTab() end
	end
end

-- DoT Coverage: one page, two pinned tabs - the display and the per-class
-- lists - the same shape as Co-Tank above, and in a block for the same reason:
-- one main-chunk local instead of seven. 'dotcov_spells' was the lists' own page
-- key and is still accepted (see the alias on the Page() line).
local PageDotCoverage
do
	local function cfg() return ns.DoTGetCfg() end
	local function Get(key) return function() return cfg()[key] end end
	local function GetOn(key) return function() return cfg()[key] ~= false end end
	local function Set(key) return function(v) cfg()[key] = v ns.DoTApply() end end

	-- Which class's list the second page is showing. It opens on your own and
	-- remembers the pick while the window lives, so adding three spells to an
	-- alt's list is not three trips back to the dropdown.
	local editClass

	local function ClassOptions()
		local out = {}
		for i = 1, (GetNumClasses and GetNumClasses()) or 0 do
			local name, token, classID = GetClassInfo(i)
			if name and token then
				local cc = C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(token)
				if cc and cc.WrapTextInColorCode then name = cc:WrapTextInColorCode(name) end
				out[#out + 1] = { value = token, text = name, classID = classID }
			end
		end
		table.sort(out, function(a, b) return a.value < b.value end)
		return out
	end

	local function ListFor(class)
		local all = cfg().classes
		if type(all[class]) ~= 'table' then all[class] = {} end
		return all[class]
	end

	local function Redraw()
		ns.DoTApply()
		ShowPage('dotcov', true)
	end

	local function MoveBtn(x, rot, enabled, onClick, tip)
		local b = CreateFrame('Button', nil, content)
		b:SetSize(18, 18)
		b:SetPoint('TOPLEFT', x, content.cy + 2)
		local t = b:CreateTexture(nil, 'ARTWORK')
		t:SetAllPoints()
		t:SetTexture(ARROW_TEX)
		t:SetRotation(rot)
		if enabled then
			t:SetVertexColor(0.85, 0.85, 0.85)
			b:SetScript('OnEnter', function() t:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3]) end)
			b:SetScript('OnLeave', function() t:SetVertexColor(0.85, 0.85, 0.85) end)
			b:SetScript('OnClick', onClick)
			Tooltip(b, tip)
		else
			t:SetVertexColor(0.3, 0.3, 0.3)
			b:EnableMouse(false)
		end
		Track(b)
	end

	-- `specs` is the edited class's specs in spec-index order, `offFor(create)`
	-- that class's table of switched-off specs by spell ID (nil until the first
	-- switch, so browsing a class writes nothing into the saved variables).
	local function SpellRow(list, idx, id, specs, offFor)
		-- The spec switches sit just before the ID column; the name gets
		-- whatever is left, which is the old full width when there are none.
		local specX = 272 - #specs * 20
		local fs = content:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
		fs:SetPoint('TOPLEFT', 18, content.cy - 4)
		fs:SetWidth(specX - 22)
		fs:SetJustifyH('LEFT')
		fs:SetWordWrap(false)
		fs:SetText(format('|T%s:18|t %s', CdSpellTexture(id), CdSpellName(id)))
		Track(fs)

		-- One switch per spec, lit where the debuff is counted. A debuff that is
		-- off for the spec being played is not built at all, and the icons after
		-- it close up into its place.
		local off = offFor(false)
		local set = off and off[id]
		for s, sp in ipairs(specs) do
			local isOff = set and set[s] == true
			local b = CreateFrame('Button', nil, content)
			b:SetSize(18, 18)
			b:SetPoint('TOPLEFT', specX + (s - 1) * 20, content.cy + 1)
			local t = b:CreateTexture(nil, 'ARTWORK')
			t:SetAllPoints()
			t:SetTexture(sp.icon or 134400)
			t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			t:SetDesaturated(isOff and true or false)
			t:SetAlpha(isOff and 0.3 or 1)
			local hl = b:CreateTexture(nil, 'HIGHLIGHT')
			hl:SetAllPoints()
			hl:SetColorTexture(1, 1, 1, 0.25)
			b:SetScript('OnClick', function()
				local byId = offFor(true)
				local specsOff = byId[id] or {}
				specsOff[s] = (not isOff) or nil
				byId[id] = next(specsOff) and specsOff or nil
				Redraw()
			end)
			Tooltip(b, isOff
				and format('%s: left out. Click to track it on this spec again.', sp.name)
				or format('%s: tracked. Click to leave it out on this spec - the icons after it move up into its place.', sp.name))
			Track(b)
		end

		local idFs = content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
		idFs:SetPoint('TOPLEFT', 276, content.cy - 4)
		idFs:SetWidth(60)
		idFs:SetJustifyH('LEFT')
		idFs:SetWordWrap(false)
		idFs:SetText(tostring(id))
		Track(idFs)

		MoveBtn(340, math.pi / 2, idx > 1, function()
			list[idx], list[idx - 1] = list[idx - 1], list[idx]
			Redraw()
		end, 'Move earlier. The icons are drawn in list order.')
		MoveBtn(358, -math.pi / 2, idx < #list, function()
			list[idx], list[idx + 1] = list[idx + 1], list[idx]
			Redraw()
		end, 'Move later. The icons are drawn in list order.')

		local rem = MakeFlatButton(content, 'Remove', 66, 20)
		rem:SetPoint('TOPLEFT', 384, content.cy + 3)
		rem:SetScript('OnClick', function()
			table.remove(list, idx)
			-- Added back later, it starts on every spec like any new entry.
			if off then off[id] = nil end
			Redraw()
		end)
		Track(rem)

		content.cy = content.cy - 28
	end

	local function DisplayTab()
		AddHeader('DoT Coverage')
		if ns.DoTUnavailable then
			AddDesc('This needs the game\'s aura container widgets and they are not available on this client, so there is nothing to show here.')
			return
		end
		AddCheck('Enable', Get('enable'), Set('enable'))
		AddPreviewToggle(ns.DoTIsPreview, ns.DoTSetPreview)
		AddCheck('Lock position', Get('lock'), Set('lock'),
			'Unlocked, right-drag the icons while Preview is on.')
		AddCheck('Show only in combat', GetOn('combatOnly'), Set('combatOnly'))

		AddHeader('Which enemies count')
		AddCheck('Only enemies that are in combat', GetOn('requireCombat'), Set('requireCombat'),
			'Off counts every attackable nameplate on screen, the pack you have not pulled included. Training dummies never report combat, so while you are fighting and nothing on screen does, this rule steps aside by itself and the dummies count.')
		AddCheck('Only enemies I am on the threat table of', Get('threatOnly'), Set('threatOnly'),
			'For the open world and for raids, where mobs in combat with somebody else would pad the total. Training dummies keep no threat table, so - like the rule above - this one steps aside by itself while you are fighting and nothing on screen passes it.')
		AddSlider('Most enemies counted', 1, 40, 1, Get('maxUnits'), Set('maxUnits'),
			'The total stops here however big the pull is; the enemies that were there first keep their place. Every counted enemy costs a small engine widget per debuff, built the first time a pull gets that big.')

		AddHeader('Icons')
		AddCheck('Hide a debuff while no enemy has it', GetOn('hideZero'), Set('hideZero'),
			'Icon and count both disappear at zero and come back with the first application. Its place in the row stays reserved, and it is still being watched for while hidden. A debuff your spec never applies is better switched off for that spec on the Tracked Debuffs tab: then it is not tracked at all and the icons after it move up.')
		AddCheck('Show the spell icon', GetOn('showIcon'), Set('showIcon'),
			'Off leaves the numbers on their own.')
		AddSlider('Icon size', 16, 80, 1, Get('iconSize'), Set('iconSize'))
		AddSlider('Icon opacity', 0.1, 1, 0.05, Get('iconAlpha'), Set('iconAlpha'),
			'A dimmer icon makes a count drawn on top of it easier to read.')
		AddSlider('Spacing', 0, 60, 1, Get('spacing'), Set('spacing'))
		AddDropdown('Grow direction', {
			{ value = 'RIGHT', text = 'Right' },
			{ value = 'LEFT', text = 'Left' },
			{ value = 'DOWN', text = 'Down' },
			{ value = 'UP', text = 'Up' },
		}, Get('grow'), Set('grow'))
		AddPosition(Get('x'), Set('x'), Get('y'), Set('y'))

		AddHeader('Count')
		AddDropdown('Shows', {
			{ value = 'FRACTION', text = 'Have it / enemies (3/5)' },
			{ value = 'COUNT',    text = 'Have it (3)' },
			{ value = 'MISSING',  text = 'Still missing it (2)' },
		}, Get('format'), Set('format'))
		AddSlider('Text size', 8, 32, 1, Get('textSize'), Set('textSize'))
		AddDropdown('Where', {
			{ value = 'CENTER', text = 'On the icon' },
			{ value = 'TOP',    text = 'Above the icon' },
			{ value = 'BOTTOM', text = 'Below the icon' },
			{ value = 'LEFT',   text = 'Left of the icon' },
			{ value = 'RIGHT',  text = 'Right of the icon' },
		}, Get('textPoint'), Set('textPoint'))
		AddSlider('X offset', -100, 100, 1, Get('textX'), Set('textX'))
		AddSlider('Y offset', -100, 100, 1, Get('textY'), Set('textY'))

		AddHeader('Colours')
		AddCheck('Colour the count by coverage', GetOn('colorize'),
			function(v) cfg().colorize = v ns.DoTApply() ShowPage('dotcov', true) end)
		if cfg().colorize ~= false then
			AddColor('Every enemy has it', Get('colorFull'), Set('colorFull'))
			AddColor('Some have it', Get('colorPartial'), Set('colorPartial'))
			AddColor('None has it', Get('colorNone'), Set('colorNone'))
		end
		AddColor(cfg().colorize ~= false and 'Nothing to count' or 'Text colour', Get('color'), Set('color'))
	end

	local function SpellsTab()
		AddHeader('Tracked Debuffs')
		local mine = ns.DoTPlayerClass()
		local classes = ClassOptions()
		editClass = editClass or mine or (classes[1] and classes[1].value)
		if not editClass then return end

		AddDropdown('Class', classes,
			function() return editClass end,
			function(v) editClass = v ShowPage('dotcov', true) end)

		local list = ListFor(editClass)
		AddSpellIdRow(function() return list end, Redraw,
			'The debuff\'s spell ID, from its tooltip on the enemy (with an ID addon) or from Wowhead.')
		content.cy = content.cy - 32

		if #list == 0 then
			AddDesc('Nothing tracked for this class yet.')
			return
		end

		local specs = {}
		local classID
		for _, c in ipairs(classes) do
			if c.value == editClass then classID = c.classID end
		end
		local CSI = _G.C_SpecializationInfo
		local numSpecs = (CSI and CSI.GetNumSpecializationsForClassID) or _G.GetNumSpecializationsForClassID
		local specInfo = _G.GetSpecializationInfoForClassID
		if classID and numSpecs and specInfo then
			local sex = UnitSex and UnitSex('player') or nil
			for s = 1, numSpecs(classID) or 0 do
				local _, specName, _, icon = specInfo(classID, s, sex)
				specs[s] = { name = specName or ('Spec ' .. s), icon = icon }
			end
		end
		local class = editClass
		local function offFor(create)
			local all = cfg().specOff
			if type(all) ~= 'table' then
				if not create then return nil end
				all = {}
				cfg().specOff = all
			end
			if type(all[class]) ~= 'table' then
				if not create then return nil end
				all[class] = {}
			end
			return all[class]
		end

		for idx, id in ipairs(list) do SpellRow(list, idx, id, specs, offFor) end
	end

	-- No tabs on a client without the aura container: the lists would have
	-- nothing to feed, so the page is just the "not available" note.
	function PageDotCoverage()
		if ns.DoTUnavailable then DisplayTab() return end
		local tab = AddPinnedTabs('dotcov', { 'Display', 'Tracked Debuffs' })
		if tab == 'Tracked Debuffs' then SpellsTab() else DisplayTab() end
	end
end

-- CC Tracker (XerionUI-Plugin_CCBars.lua): a bar per crowd control on the
-- enemies, coloured and named per spell, with a Display and a Tracked Spells
-- tab on the pinned row.
local PageCCTracker
do
	local function cfg() return ns.CCBGetCfg() end
	local function Get(key) return function() return cfg()[key] end end
	local function GetOn(key) return function() return cfg()[key] ~= false end end
	local function Set(key) return function(v) cfg()[key] = v ns.CCBApply() end end

	local function Redraw()
		ns.CCBApply()
		ShowPage('cctracker', true)
	end

	-- Every statusbar LibSharedMedia knows, after the addon's usual one.
	local function TextureOptions()
		local out = { { value = '', text = 'Default' } }
		local lib = ns.LSM()
		local hash = lib and lib.HashTable and lib:HashTable('statusbar')
		if hash then
			local names = {}
			for name in pairs(hash) do names[#names + 1] = name end
			table.sort(names, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
			for _, name in ipairs(names) do out[#out + 1] = { value = name, text = name } end
		end
		return out
	end

	local function DisplayTab()
		AddHeader('CC Tracker')
		if ns.CCBUnavailable then
			AddDesc('This needs the game\'s aura container widgets and they are not available on this client, so there is nothing to show here.')
			return
		end
		AddCheck('Enable', Get('enable'), Set('enable'))
		AddPreviewToggle(ns.CCBIsPreview, ns.CCBSetPreview)
		AddCheck('Lock position', Get('lock'), Set('lock'),
			'Unlocked, right-drag the bars while Preview is on.')

		AddHeader('Bars')
		AddDropdown('Show', {
			{ value = 'group', text = 'One bar per spell' },
			{ value = 'each', text = 'One bar per spell per enemy' },
		}, Get('mode'), function(v) cfg().mode = v Redraw() end)
		if cfg().mode ~= 'each' then
			AddCheck('Only spells of classes in my group', GetOn('classRows'), Set('classRows'),
				'Each spell has its own line, empty while nobody is controlled by it. On, a spell whose class is not in your group gets no line at all. Spells added by ID always keep theirs.')
		end
		AddSlider('Width', 80, 400, 1, Get('width'), Set('width'))
		AddSlider('Height', 10, 40, 1, Get('height'), Set('height'))
		AddSlider('Spacing', 0, 20, 1, Get('spacing'), Set('spacing'))
		AddDropdown('Grow direction', {
			{ value = 'DOWN', text = 'Down' },
			{ value = 'UP', text = 'Up' },
		}, Get('grow'), Set('grow'))
		AddDropdown('Icon', {
			{ value = 'RIGHT', text = 'Right of the bar' },
			{ value = 'LEFT', text = 'Left of the bar' },
			{ value = 'NONE', text = 'No icon' },
		}, Get('icon'), Set('icon'))
		AddScrollDropdown('Texture', TextureOptions(), Get('texture'), Set('texture'))
		AddSlider('Background opacity', 0, 1, 0.05, Get('bgAlpha'), Set('bgAlpha'))
		AddCheck('Border', GetOn('border'), function(v) cfg().border = v Redraw() end)
		if cfg().border ~= false then
			AddSlider('Border size', 1, 4, 1, Get('borderSize'), Set('borderSize'))
			AddColor('Border colour', Get('borderColor'), Set('borderColor'))
		end

		AddHeader('Text')
		AddCheck('Show the spell name', GetOn('showName'), Set('showName'))
		AddCheck('Show the seconds', GetOn('showTimer'), Set('showTimer'))
		AddDropdown('Seconds side', {
			{ value = 'LEFT', text = 'Left, name on the right' },
			{ value = 'RIGHT', text = 'Right, name on the left' },
		}, Get('timerSide'), Set('timerSide'))
		AddCheck('Tenths of a second', GetOn('tenths'), Set('tenths'),
			'On: "4.2". Off: whole seconds.')
		AddSlider('Name size', 8, 24, 1, Get('nameSize'), Set('nameSize'))
		AddSlider('Name Y offset', -30, 30, 1, Get('nameY'), Set('nameY'))
		AddSlider('Seconds size', 8, 24, 1, Get('timerSize'), Set('timerSize'))

		AddHeader('Sound')
		local sounds = ns.SoundOptions(cfg().sound)
		local listed = false
		for _, o in ipairs(sounds) do
			if o.value == ns.CCBSoundName then listed = true break end
		end
		if not listed then table.insert(sounds, 2, { value = ns.CCBSoundName, text = ns.CCBSoundName }) end
		AddScrollDropdown('Sound when a bar shows', sounds, Get('sound'), Set('sound'), nil, ns.CCBPlaySound)
		AddDropdown('Play it for', {
			{ value = 'ALL', text = 'Every enemy it lands on' },
			{ value = 'TARGET', text = 'My target only' },
		}, Get('soundFrom'), Set('soundFrom'))
		local channels = {
			{ value = 'SFX', text = 'Sound effects' }, { value = 'Master', text = 'Master' },
			{ value = 'Dialog', text = 'Dialog' }, { value = 'Ambience', text = 'Ambience' },
			{ value = 'Music', text = 'Music' },
		}
		-- Redraw, so the volume slider below changes to the new channel's.
		AddDropdown('Sound channel', channels, Get('soundChannel'), function(v) cfg().soundChannel = v Redraw() end)
		local channel = channels[1].text
		for _, o in ipairs(channels) do
			if o.value == cfg().soundChannel then channel = o.text break end
		end
		AddSlider(channel .. ' volume', 0, 100, 5, ns.CCBGetVolume, ns.CCBSetVolume,
			'The game\'s own volume for this channel, the same slider as in its Audio settings. Every sound on the channel follows it.')

		AddHeader('Enemies')
		AddSlider('Most enemies watched', 3, 20, 1, Get('maxUnits'), Set('maxUnits'),
			'Every enemy nameplate on screen takes a place, controlled or not - the game does not tell addons which ones are. "One bar per spell per enemy" costs ten engine buttons per tracked spell for each watched enemy.')
		AddPosition(Get('x'), Set('x'), Get('y'), Set('y'))
	end

	-- A colour swatch that opens the colour picker; nil for "no override" puts
	-- the spell back on its built-in colour.
	local function ColorSwatch(id, x, y)
		local sw = CreateFrame('Button', nil, content)
		sw:SetSize(18, 18)
		sw:SetPoint('TOPLEFT', x, y)
		local bord = sw:CreateTexture(nil, 'BACKGROUND')
		bord:SetPoint('TOPLEFT', -1, 1)
		bord:SetPoint('BOTTOMRIGHT', 1, -1)
		bord:SetColorTexture(0, 0, 0, 1)
		sw.tex = sw:CreateTexture(nil, 'ARTWORK')
		sw.tex:SetAllPoints()
		local function refresh()
			local r, g, b = ns.CCBColor(id)
			sw.tex:SetColorTexture(r, g, b, 1)
		end
		refresh()
		sw:SetScript('OnClick', function()
			local r, g, b = ns.CCBColor(id)
			local before = cfg().colors[id]
			local function set(v)
				cfg().colors[id] = v
				refresh()
				ns.CCBApply()
			end
			local function applyNow()
				local nr, ng, nb = ColorPickerFrame:GetColorRGB()
				set({ nr, ng, nb, 1 })
			end
			ColorPickerFrame:SetupColorPickerAndShow({
				r = r, g = g, b = b, hasOpacity = false,
				swatchFunc = applyNow,
				cancelFunc = function() set(before) end,
			})
		end)
		Tooltip(sw, 'Bar colour')
		return Track(sw)
	end

	-- Column x positions of a bar spell row, shared with the captions above it.
	local COL_ID, COL_COLOR, COL_LABEL, COL_REMOVE = 194, 252, 280, 392

	-- One spell: its icon and the game's name for it, the ID, the bar colour,
	-- the short name written on the bar, and Remove.
	local function SpellRow(list, idx, id)
		local y = content.cy
		local fs = content:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
		fs:SetPoint('TOPLEFT', 18, y - 4)
		fs:SetWidth(COL_ID - 24)
		fs:SetJustifyH('LEFT')
		fs:SetWordWrap(false)
		fs:SetText(format('|T%s:18|t %s', CdSpellTexture(id), CdSpellName(id)))
		Track(fs)

		local idFs = content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
		idFs:SetPoint('TOPLEFT', COL_ID, y - 4)
		idFs:SetWidth(COL_COLOR - COL_ID - 4)
		idFs:SetJustifyH('LEFT')
		idFs:SetWordWrap(false)
		idFs:SetText(tostring(id))
		Track(idFs)

		ColorSwatch(id, COL_COLOR, y - 1)

		local eb = MakeEditBox(content, COL_REMOVE - COL_LABEL - 8, 20)
		eb:SetPoint('TOPLEFT', COL_LABEL, y)
		eb:SetText(ns.CCBLabel(id))
		local function commit(self)
			local t = Trim(self:GetText() or '')
			cfg().labels[id] = (t ~= '') and t or nil
			self:SetText(ns.CCBLabel(id))
			ns.CCBApply()
		end
		eb:SetScript('OnEnterPressed', function(self) commit(self) self:ClearFocus() end)
		eb:HookScript('OnEditFocusLost', commit)
		Tooltip(eb, 'The name written on the bar. Clear it for the default.')
		Track(eb)

		local rem = MakeFlatButton(content, 'Remove', 66, 20)
		rem:SetPoint('TOPLEFT', COL_REMOVE, y)
		rem:SetScript('OnClick', function()
			table.remove(list, idx)
			Redraw()
		end)
		Track(rem)

		content.cy = y - 28
	end

	local function SpellsTab()
		AddHeader('Tracked Spells')
		local list = cfg().spells
		AddSpellIdRow(function() return cfg().spells end, Redraw,
			'The debuff\'s spell ID, from its tooltip on the enemy (with an ID addon) or from Wowhead.')
		content.cy = content.cy - 32
		AddButton('Restore the default list', function()
			cfg().spells = ns.CCBDefaultSpells()
			Redraw()
		end)

		if #list == 0 then
			AddDesc('Nothing tracked yet.')
			return
		end
		local captions = { { 18, 'Spell' }, { COL_ID, 'ID' }, { COL_COLOR, 'Colour' }, { COL_LABEL, 'Name on the bar' } }
		for _, c in ipairs(captions) do
			local cap = content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
			cap:SetPoint('TOPLEFT', c[1], content.cy)
			cap:SetText(c[2])
			Track(cap)
		end
		content.cy = content.cy - 18
		for idx, id in ipairs(list) do SpellRow(list, idx, id) end
	end

	-- No tabs on a client without the aura container: the list would have
	-- nothing to feed, so the page is just the "not available" note.
	function PageCCTracker()
		if ns.CCBUnavailable then DisplayTab() return end
		local tab = AddPinnedTabs('cctracker', { 'Display', 'Tracked Spells' })
		if tab == 'Tracked Spells' then SpellsTab() else DisplayTab() end
	end
end

-- A second, independently placed group for cast notifications. Unlike the
-- CC Tracker above, these rows report party spell casts for a short window.
local function PageCCCastNotices()
	local function cfg() return ns.CCCastGetCfg() end
	local function Get(key) return function() return cfg()[key] end end
	local function Set(key) return function(v) cfg()[key] = v ns.CCCastApply() end end
	AddHeader('CC Cast Notices')
	AddDesc('Short notifications when someone in your party or raid casts Capacitor Totem, Sigil of Silence or Shadowfury. This group has its own position, separate from the aura-based CC Tracker.')
	AddCheck('Enable', Get('enable'), Set('enable'))
	AddPreviewToggle(ns.CCCastIsPreview, ns.CCCastSetPreview)
	AddCheck('Lock position', Get('lock'), Set('lock'), 'Unlocked, right-drag the preview group.')
	AddSlider('Notification duration', 1, 15, 1, Get('duration'), Set('duration'))
	AddSlider('Width', 140, 500, 5, Get('width'), Set('width'))
	AddSlider('Row height', 16, 40, 1, Get('height'), Set('height'))
	AddSlider('Row spacing', 0, 20, 1, Get('spacing'), Set('spacing'))
	AddPosition(Get('x'), Set('x'), Get('y'), Set('y'))
end

-- Augment Rune. The icon the engine shows while the rune buff is missing, for
-- the active key where EllesmereUI's own reminder has to stay quiet.
local PageAugmentRune
do
	local function cfg() return ns.ARGetCfg() end
	local function Get(key) return function() return cfg()[key] end end
	local function GetOn(key) return function() return cfg()[key] ~= false end end
	local function Set(key) return function(v) cfg()[key] = v ns.ARApply() end end

	function PageAugmentRune()
		AddHeader('Augment Rune')
		if ns.ARUnavailable then
			AddDesc('This needs the game\'s aura container widgets and they are not available on this client, so there is nothing to show here.')
			return
		end
		AddCheck('Enable', Get('enable'), Set('enable'))
		AddPreviewToggle(ns.ARIsPreview, ns.ARSetPreview)
		AddCheck('Lock position', Get('lock'), Set('lock'),
			'Unlocked, right-drag the icon while Preview is on.')

		AddHeader('When')
		AddDropdown('Show', {
			{ value = 'KEY',      text = 'In an active keystone only' },
			{ value = 'INSTANCE', text = 'In dungeons and raids' },
			{ value = 'ALWAYS',   text = 'Everywhere' },
		}, Get('where'), Set('where'))
		AddCheck('Hide in combat', GetOn('hideInCombat'), Set('hideInCombat'),
			'The icon waits for the pull to end. Off, it stays up through the fight as well.')

		AddHeader('Icon')
		AddSlider('Size', 20, 100, 1, Get('size'), Set('size'))
		AddPosition(Get('x'), Set('x'), Get('y'), Set('y'))

		AddHeader('Dismiss cross')
		AddCheck('Show the cross',
			function() return cfg().cross ~= 'OFF' end,
			function(v) cfg().cross = v and 'ALWAYS' or 'OFF' ns.ARApply() end)
		AddSlider('Cross size', 8, 32, 1, Get('crossSize'), Set('crossSize'))
		AddDropdown('Corner', {
			{ value = 'TOPRIGHT',    text = 'Top right' },
			{ value = 'TOPLEFT',     text = 'Top left' },
			{ value = 'BOTTOMRIGHT', text = 'Bottom right' },
			{ value = 'BOTTOMLEFT',  text = 'Bottom left' },
		}, Get('crossCorner'), Set('crossCorner'))
	end
end

-- Shroud/Invis Bar: the rogue's Shroud of Concealment with a timer, for the rest of
-- the party, with the mage's Mass Invisibility on a second bar above it. The
-- bars are the whole feature; the party countdown and macro chat line the
-- page once had were removed at the user's request. The two bars share size,
-- text and position (they move as one stack) and differ in switch and colour.
local PageShroud
do
	local function cfg() return ns.SHGetCfg() end
	local function Get(key) return function() return cfg()[key] end end
	local function GetOn(key) return function() return cfg()[key] ~= false end end
	local function Set(key) return function(v) cfg()[key] = v ns.SHApply() end end
	local function TextureOptions()
		local out = { { value = '', text = 'Default' } }
		local lib = ns.LSM()
		local hash = lib and lib.HashTable and lib:HashTable('statusbar')
		if hash then
			local names = {}
			for name in pairs(hash) do names[#names + 1] = name end
			table.sort(names, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
			for _, name in ipairs(names) do out[#out + 1] = { value = name, text = name } end
		elseif #out == 1 then
			out[1].text = '|cff777777LibSharedMedia not loaded|r'
		end
		return out
	end

	-- For a switch that adds or removes controls under it.
	local function Redraw()
		ns.SHApply()
		ShowPage('shroud', true)
	end

	function PageShroud()
		AddHeader('Shroud/Invis Bar')
		if ns.SHUnavailable then
			AddDesc('This needs the game\'s aura container widgets and they are not available on this client, so there is nothing to show here.')
			return
		end
		AddCheck('Enable', Get('enable'), Set('enable'))
		AddPreviewToggle(ns.SHIsPreview, ns.SHSetPreview)
		AddCheck('Lock position', Get('lock'), Set('lock'),
			'Unlocked, right-drag the bars while Preview is on.')

		AddHeader('Mass Invisibility')
		AddCheck('Show the Mass Invisibility bar', GetOn('showMassInvis'), Set('showMassInvis'))
		AddColor('Mass Invisibility colour', Get('miColor'), Set('miColor'))

		AddHeader('Shroud')
		AddCheck('Show the Shroud bar', GetOn('showShroud'), Set('showShroud'))
		AddCheck('Show my own Shroud when I am the rogue', GetOn('selfBar'), Set('selfBar'),
			'Off, a rogue sees the bar only for another rogue in the group.')
		AddColor('Shroud colour', Get('color'), Set('color'))

		AddHeader('Both bars')
		AddSlider('Width', 100, 500, 1, Get('width'), Set('width'))
		AddSlider('Height', 10, 60, 1, Get('height'), Set('height'))
		AddSlider('Space between the bars', 0, 30, 1, Get('gap'), Set('gap'))
		AddScrollDropdown('Bar texture', TextureOptions(), Get('texture'), Set('texture'))
		AddCheck('Use custom background colour', Get('customBgColor'), function(v)
			cfg().customBgColor = v
			Redraw()
		end,
			'Applies to both bars. Turn this off to return to the darker version of each bar colour.')
		if cfg().customBgColor then AddColor('Background colour', Get('bgColor'), Set('bgColor')) end
		AddSlider('Background opacity', 0, 1, 0.05, Get('bgAlpha'), Set('bgAlpha'))
		AddCheck('Border', GetOn('border'), function(v) cfg().border = v Redraw() end)
		if cfg().border ~= false then
			AddSlider('Border size', 1, 4, 1, Get('borderSize'), Set('borderSize'))
			AddColor('Border colour', Get('borderColor'), Set('borderColor'))
		end
		AddCheck('Show the icon', GetOn('showIcon'), Set('showIcon'))
		AddCheck('Show the name ("Mass Invis", "Shroud")', GetOn('showName'), Set('showName'))
		AddCheck('Show the seconds', GetOn('showTimer'), Set('showTimer'))
		AddSlider('Text size', 8, 30, 1, Get('textSize'), Set('textSize'))
		AddPosition(Get('x'), Set('x'), Get('y'), Set('y'))
	end
end

-- Spell Queue Window. The numbers are kept per class and spec for the whole
-- account, so the page can set up any class from any character: the dropdown
-- picks the class (the played one until it is touched) and every spec of it
-- gets a switch - own value or not - and, once it has one, the slider. A spec
-- left off follows the 'Other specs' number. The spec rows stay out of the
-- search index: they change with the dropdown, and a search for 'Blood' that
-- only works while Death Knight happens to be picked is worse than none.
local PageSpellQueue
do

local sqClass

local function SqClassOptions()
	local out = {}
	for i = 1, (GetNumClasses and GetNumClasses()) or 0 do
		local name, token, classID = GetClassInfo(i)
		if name and token and classID then
			local cc = C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(token)
			local text = (cc and cc.WrapTextInColorCode) and cc:WrapTextInColorCode(name) or name
			out[#out + 1] = { value = token, text = text, name = name, classID = classID }
		end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

local function SqSpecs(class)
	local CSI = _G.C_SpecializationInfo
	local numSpecs = (CSI and CSI.GetNumSpecializationsForClassID) or _G.GetNumSpecializationsForClassID
	local specInfo = _G.GetSpecializationInfoForClassID
	local sex = UnitSex and UnitSex('player') or nil
	local out = {}
	for s = 1, (numSpecs and numSpecs(class.classID)) or 0 do
		local _, specName, _, icon
		if specInfo then _, specName, _, icon = specInfo(class.classID, s, sex) end
		out[#out + 1] = { key = format('%s-%d', class.value, s), name = specName or ('Spec ' .. s), icon = icon }
	end
	return out
end

function PageSpellQueue()
	local function cfg() return ns.SQGetCfg() end
	local function redraw() ShowPage('spellqueue', true) end

	local function statusText()
		local cur = ns.SQCurrent()
		local now = cur and format('%d ms', cur) or 'an unreadable value'
		if cfg().enable then
			return format('You are on %s - the game is using |cffffffff%s|r right now.', ns.CdSpecLabel(), now)
		end
		return format('Switched off - the game keeps what it has, |cffffffff%s|r.', now)
	end
	local status
	local function changed()
		ns.SQApply(true)
		if status then status:SetText(statusText()) end
	end

	AddHeader('Spell Queue Window')
	AddCheck('Enable',
		function() return cfg().enable end,
		function(v)
			if v then ns.SQSeedFallback() end
			cfg().enable = v
			ns.SQApply(true)
			redraw()
		end)
	AddCheck('Announce changes in chat',
		function() return cfg().announce end,
		function(v) cfg().announce = v end,
		'Prints the new value when a login or a spec change moves it. Changes made in this window are never announced.')
	status = AddDesc(statusText())
	AddSlider('Other specs (ms)', 0, 400, 1,
		function() return cfg().fallback end,
		function(v) cfg().fallback = v changed() end,
		'Used by every spec that has no value of its own below - on every class and every character.')

	AddHeader('Per spec')
	local curKey = ns.SQSpecKey()
	local curClass = curKey and curKey:match('^(.-)%-%d+$')
	local classes = SqClassOptions()
	local picked
	for _, c in ipairs(classes) do
		if c.value == (sqClass or curClass) then picked = c break end
	end
	picked = picked or classes[1]
	if not picked then return end

	AddDropdown('Class', classes,
		function() return picked.value end,
		function(v) sqClass = v redraw() end)

	content.noReg = true
	for _, sp in ipairs(SqSpecs(picked)) do
		local key = sp.key
		local label = sp.icon and format('|T%s:16|t %s', sp.icon, sp.name) or sp.name
		if key == curKey then label = label .. '  |cffff7d0a- current|r' end
		AddCheck(label,
			function() return cfg().specs[key] ~= nil end,
			function(v)
				cfg().specs[key] = v and (ns.SQWantedFor(key)) or nil
				ns.SQApply(true)
				redraw()
			end,
			'Give this spec its own spell queue window. Off: it uses the "Other specs" value.')
		if cfg().specs[key] ~= nil then
			AddSlider(sp.name .. ' (ms)', 0, 400, 1,
				function() return cfg().specs[key] end,
				function(v) cfg().specs[key] = v changed() end)
		end
	end
	content.noReg = nil
end

end

local function PageCrosshair()
	AddHeader('Crosshair')
	local function cfg() return ns.CHGetCfg() end
	AddCheck('Enable',
		function() return cfg().enable end,
		function(v) cfg().enable = v ns.CHApply() end)
	AddCheck('Show only in combat',
		function() return cfg().combatOnly end,
		function(v) cfg().combatOnly = v ns.CHApply() end,
		'Only display the crosshair while you are in combat.')
	AddCheck('X shape',
		function() return cfg().diagonal end,
		function(v) cfg().diagonal = v ns.CHApply() end,
		'Turns the crosshair 45 degrees so it looks like an X instead of a +.')
	AddColor('Colour',
		function() return cfg().color end,
		function(c) cfg().color = c ns.CHApply() end)
	AddSlider('Opacity', 0, 1, 0.05,
		function() return cfg().opacity end,
		function(v) cfg().opacity = v ns.CHApply() end)
	AddCheck('Border',
		function() return cfg().border end,
		function(v) cfg().border = v ns.CHApply() end,
		'Draws a dark outline around the crosshair so it stays visible on any background.')
	AddColor('Border colour',
		function() return cfg().borderColor end,
		function(c) cfg().borderColor = c ns.CHApply() end)
	AddSlider('Border size', 1, 5, 1,
		function() return cfg().borderSize end,
		function(v) cfg().borderSize = v ns.CHApply() end)
	AddSlider('Arm length', 0, 60, 1,
		function() return cfg().length end,
		function(v) cfg().length = v ns.CHApply() end)
	AddSlider('Arm thickness', 1, 12, 1,
		function() return cfg().thickness end,
		function(v) cfg().thickness = v ns.CHApply() end)
	AddSlider('Centre gap', 0, 40, 1,
		function() return cfg().gap end,
		function(v) cfg().gap = v ns.CHApply() end,
		'Distance from the centre to where each arm starts.')
	AddCheck('Centre dot',
		function() return cfg().dot end,
		function(v) cfg().dot = v ns.CHApply() end)
	AddSlider('Dot size', 1, 20, 1,
		function() return cfg().dotSize end,
		function(v) cfg().dotSize = v ns.CHApply() end)
	AddPosition(
		function() return cfg().x end,
		function(v) cfg().x = v ns.CHApply() end,
		function() return cfg().y end,
		function(v) cfg().y = v ns.CHApply() end)

	AddHeader('Out of range')
	local function rangeStatus()
		local name, range, source = ns.CHRangeInfo()
		local spec = ns.CdSpecLabel()
		if not name then
			return format('%s: no range spell found - set one below.', spec)
		end
		local how = (source == 'custom' and 'your spell') or (source == 'form' and 'your form')
			or (source == 'scan' and 'found in your spellbook') or 'automatic'
		return format('%s: |cffffffff%s|r (%s, %s)', spec, name, range, how)
	end
	local status
	AddCheck('Colour when the target is out of range',
		function() return cfg().rangeColor end,
		function(v) cfg().rangeColor = v ns.CHApply() end,
		'Turns the crosshair this colour while your attackable target is out of range of your main attack.')
	AddCheck('Only show when out of range',
		function() return cfg().oorOnly end,
		function(v) cfg().oorOnly = v ns.CHApply() end,
		'Hides the crosshair until your target is out of range, then shows it in the out of range colour.')
	AddPreviewToggle(ns.CHIsPreview, ns.CHSetPreview)
	AddColor('Out of range colour',
		function() return cfg().oorColor end,
		function(c) cfg().oorColor = c ns.CHApply() end)
	status = AddDesc(rangeStatus())
	do
		local specID = ns.CHSpecID()
		local last
		local function current()
			local id = specID and cfg().rangeSpells[specID]
			return id and tostring(id) or ''
		end
		last = current()
		AddEditBoxOption('Range spell for this spec (ID or name, empty = automatic)',
			current,
			function(v)
				v = (v or ''):match('^%s*(.-)%s*$')
				if v == last then return end
				last = v
				if v == '' then
					ns.CHSetRangeSpell(nil)
				else
					local id = ns.CdResolveSpellID(v)
					if not id then Msg('no spell found for "' .. v .. '"') return end
					ns.CHSetRangeSpell(id)
				end
				status:SetText(rangeStatus())
			end)
	end
end

local function PageAggroCheck()
	AddHeader('Aggro Check')
	local function cfg() return ns.AGCGetCfg() end
	AddCheck('Enable',
		function() return cfg().enable end,
		function(v) cfg().enable = v ns.AGCApply() end)
	AddPreviewToggle(ns.AGCIsPreview, ns.AGCSetPreview)
	AddCheck('Only in Mythic+ keys',
		function() return cfg().keyOnly end,
		function(v) cfg().keyOnly = v ns.AGCApply() end,
		'Untick to also warn in raids, normal dungeons and the open world.')

	AddHeader('Appearance')
	AddEditBoxOption('Text',
		function() return cfg().text end,
		function(v) v = ns.Trim(v) if v == '' then v = 'AGGRO' end cfg().text = v ns.AGCApply() end)
	AddColor('Colour',
		function() return cfg().color end,
		function(c) cfg().color = c ns.AGCApply() end)
	AddSlider('Text size', 12, 80, 1,
		function() return cfg().fontSize end,
		function(v) cfg().fontSize = v ns.AGCApply() end)
	AddCheck('Pulse',
		function() return cfg().pulse end,
		function(v) cfg().pulse = v ns.AGCApply() end,
		'Fades the text in and out while it is shown so it catches the eye.')
	AddCheck('Lock position',
		function() return cfg().lock end,
		function(v) cfg().lock = v ns.AGCApply() end,
		'Prevents moving the text with right-drag while previewing.')
	AddPosition(
		function() return cfg().x end,
		function(v) cfg().x = v ns.AGCApply() end,
		function() return cfg().y end,
		function(v) cfg().y = v ns.AGCApply() end)

	AddHeader('Sound')
	AddCheck('Play sound when you get aggro',
		function() return cfg().soundEnabled end,
		function(v) cfg().soundEnabled = v end)
	AddScrollDropdown('Sound', ns.SoundOptions(cfg().sound),
		function() return cfg().sound end,
		function(v) cfg().sound = v end,
		ns.PlaySoundByName,
		ns.PlaySoundByName)
end

local function PageSecondaryStats()
	AddHeader('Secondary Stats')
	local function cfg() return ns.SSGetCfg() end
	AddCheck('Enable',
		function() return cfg().enable end,
		function(v) cfg().enable = v ns.SSApply() end)
	AddCheck('Lock position',
		function() return cfg().lock end,
		function(v) cfg().lock = v ns.SSApply() end,
		'Prevents moving the list with right-drag (and makes it click-through).')
	AddSlider('Text size', 8, 40, 1,
		function() return cfg().fontSize end,
		function(v) cfg().fontSize = v ns.SSApply() end)
	AddDropdown('Durability shows', {
			{ value = 'lowest',  text = 'Lowest item' },
			{ value = 'average', text = 'Average of all items' },
		},
		function() return cfg().duraMode end,
		function(v) cfg().duraMode = v ns.SSApply() end)
	AddPosition(
		function() return cfg().x end,
		function(v) cfg().x = v ns.SSApply() end,
		function() return cfg().y end,
		function(v) cfg().y = v ns.SSApply() end)
end

local function PageReadyCheck()
	AddHeader('Ready Check Consumables')
	local function cfg() return ns.RCGetCfg() end
	AddCheck('Enable',
		function() return cfg().enable end,
		function(v) cfg().enable = v ns.RCApply() end)
	AddPreviewToggle(ns.RCIsPreview, ns.RCSetPreview)

	AddHeader('Slots')
	AddCheck('Food', function() return cfg().showFood end,
		function(v) cfg().showFood = v ns.RCApply() end)
	AddCheck('Flask', function() return cfg().showFlask end,
		function(v) cfg().showFlask = v ns.RCApply() end)
	AddCheck('Augment Rune', function() return cfg().showRune end,
		function(v) cfg().showRune = v ns.RCApply() end)
	AddCheck('Weapon oil - main hand', function() return cfg().showOilMH end,
		function(v) cfg().showOilMH = v ns.RCApply() end)
	AddCheck('Weapon oil - off hand', function() return cfg().showOilOH end,
		function(v) cfg().showOilOH = v ns.RCApply() end,
		'Only useful if you actually dual wield or carry an off-hand that takes an oil.')

	AddHeader('Appearance')
	AddSlider('Icon size', 16, 80, 1,
		function() return cfg().iconSize end,
		function(v) cfg().iconSize = v ns.RCApply() end)
	AddSlider('Spacing', 0, 24, 1,
		function() return cfg().spacing end,
		function(v) cfg().spacing = v ns.RCApply() end)
	AddSlider('Scale', 0.5, 2, 0.05,
		function() return cfg().scale end,
		function(v) cfg().scale = v ns.RCApply() end)
	AddCheck('Lock position',
		function() return cfg().lock end,
		function(v) cfg().lock = v ns.RCApply() end)
	AddPosition(function() return cfg().x end, function(v) cfg().x = v ns.RCApply() end,
		function() return cfg().y end, function(v) cfg().y = v ns.RCApply() end)

	AddHeader('Behaviour')
	AddCheck('Show each item you carry',
		function() return cfg().showVariants end,
		function(v) cfg().showVariants = v ns.RCApply() end,
		'When you carry more than one kind of the same consumable - two different flasks, say - a row of small icons appears under the slot, one per item. Clicking one uses that item.')
	AddCheck('Show tooltips on hover',
		function() return cfg().showTooltip end,
		function(v) cfg().showTooltip = v ns.RCApply() end,
		'Off = hovering the bar shows nothing. The icon, red X and count already say what a slot needs.')
	AddCheck('Hide if nothing is missing',
		function() return cfg().hideWhenAllGood end,
		function(v) cfg().hideWhenAllGood = v ns.RCApply() end,
		'Only shows the bar when you actually need to fix something.')
	AddSlider('Maximum time on screen (sec)', 0, 60, 1,
		function() return cfg().duration end,
		function(v) cfg().duration = v ns.RCApply() end,
		'The bar closes when everyone has answered. This is the ceiling for a check nobody finishes. 0 = no limit.')
end

local function PageInspect()
	AddHeader('Inspect Talents')
	local function cfg() return ns.INSGetCfg() end
	AddCheck('Enable',
		function() return cfg().enable end,
		function(v) cfg().enable = v ns.INSApply() end)
	AddCheck('Show untaken talents',
		function() return cfg().showInactive end,
		function(v) cfg().showInactive = v ns.INSApply() end,
		'On = the full tree with unspent nodes greyed out. Off = only the talents they took, in a smaller panel.')
	AddCheck('Show their secondary stats',
		function() return cfg().showStats ~= false end,
		function(v) cfg().showStats = v ns.INSApply() end,
		'Two rows of flat ratings in the empty space under the class tree: C crit, H haste, M mastery, V versatility. The numbers are added up from their gear tooltips, so an enchant that shows a name instead of a number (most weapon enchants) is not in there.')
	AddSlider('Stat text size', 8, 20, 1,
		function() return cfg().statFontSize end,
		function(v) cfg().statFontSize = v ns.INSApply() end)
	AddSlider('Stat block drop', 0, 40, 1,
		function() return cfg().statDrop end,
		function(v) cfg().statDrop = v ns.INSApply() end,
		'Pushes the stat lines further down the panel. The panel grows to keep them clear of the talents and inside its own border.')
	AddDropdown('Dock side',
		{ { value = 'RIGHT', text = 'Right of the sheet' }, { value = 'LEFT', text = 'Left of the sheet' } },
		function() return cfg().side end,
		function(v) cfg().side = v ns.INSApply() end)
	AddSlider('Talent icon size', 14, 44, 1,
		function() return cfg().nodeSize end,
		function(v) cfg().nodeSize = v ns.INSApply() end,
		'Pixel size of each talent icon. This controls how big the whole panel is.')
	AddSlider('Node spacing', 0, 24, 1,
		function() return cfg().spacing end,
		function(v) cfg().spacing = v ns.INSApply() end,
		'Extra pixels between talent icons. Spreads the tree out without changing the icon size.')
	AddSlider('Background opacity', 0, 1, 0.05,
		function() return cfg().bgAlpha end,
		function(v) cfg().bgAlpha = v ns.INSApply() end)
	AddSlider('Gap', 0, 60, 1,
		function() return cfg().gap end,
		function(v) cfg().gap = v ns.INSApply() end,
		'Pixels between the inspect sheet and the talent panel.')
	AddSlider('Vertical offset', -40, 40, 1,
		function() return cfg().yOffset end,
		function(v) cfg().yOffset = v ns.INSApply() end,
		'Nudges the panel up or down relative to the inspect sheet\'s top edge.')
end

local function PageMDITeleport()
	AddHeader('MDI Teleports')
	AddCheck('Enable', function() return ns.MDIGetCfg().enable end,
		function(v) ns.MDIGetCfg().enable = v end)
	AddSlider('Icon size', 12, 40, 1,
		function() return ns.MDIGetCfg().iconSize end,
		function(v) ns.MDIGetCfg().iconSize = v end)
	AddCheck('Rename greeting to "Dungeons:"', function() return ns.MDIGetCfg().renameGreeting end,
		function(v) ns.MDIGetCfg().renameGreeting = v end)

	if ns.hasKeyVendor then
		AddHeader('Keystone Vendor')
		local function kcfg() return ns.KVGetCfg() end
		AddCheck('Enable',
			function() return kcfg().enable end,
			function(v) kcfg().enable = v ns.KVApply() end)
		AddSlider('Highlight key level from', 2, 40, 1,
			function() return kcfg().minLevel end,
			function(v) kcfg().minLevel = v ns.KVApply() end,
			'"Set Keystone Level" entries from this level up are highlighted green.')
		AddSlider('Highlight key level to', 2, 40, 1,
			function() return kcfg().maxLevel end,
			function(v) kcfg().maxLevel = v ns.KVApply() end)
		AddSlider('Highlight text size', 8, 24, 1,
			function() return kcfg().textSize end,
			function(v) kcfg().textSize = v ns.KVApply() end,
			'Keystone / level / affix entries.')
		AddSlider('Dungeon name text size', 8, 24, 1,
			function() return kcfg().mapSize end,
			function(v) kcfg().mapSize = v ns.KVApply() end,
			'The red dungeon entries - smaller than the rest so long names stay inside the button.')

		local eb = MakeEditBox(content, 90, 22)
		eb:SetPoint('TOPLEFT', 16, content.cy)
		eb:SetJustifyH('CENTER')
		eb:SetText(tostring(kcfg().npcID or 0))
		local function commitNpc(self)
			local n = tonumber(self:GetText())
			if n and n >= 0 then
				kcfg().npcID = math.floor(n)
				ns.KVApply()
			end
			self:SetText(tostring(kcfg().npcID or 0))
		end
		eb:SetScript('OnEnterPressed', function(self) commitNpc(self) self:ClearFocus() end)
		eb:HookScript('OnEditFocusLost', commitNpc)
		Track(eb)
		content.cy = content.cy - 32
	end
end

local function TrItemLabel(id)
	local nm, tex
	local CI = _G.C_Item
	if CI then
		if CI.GetItemNameByID then
			local ok, v = pcall(CI.GetItemNameByID, id)
			if ok then nm = v end
		end
		if CI.GetItemIconByID then
			local ok, v = pcall(CI.GetItemIconByID, id)
			if ok then tex = v end
		end
	end
	if nm then return format('|T%s:18|t %s', tex or 134400, nm) end

	local ok, sn = pcall(CdSpellName, id)
	local okT, st = pcall(CdSpellTexture, id)
	return format('|T%s:18|t %s |cff888888(spell)|r',
		(okT and st) or tex or 134400, (ok and sn) or ('unknown ' .. id))
end

local function PageAppearance()
	AddHeader('Font')
	AddScrollDropdown('Font', ns.FontOptions(),
		function() return (_G.XerionUIChangesDB and _G.XerionUIChangesDB.font) or '' end,
		function(v)
			if _G.XerionUIChangesDB then _G.XerionUIChangesDB.font = v end
			ns.FontApply()
			ShowPage('appearance', true)
		end)
	local sample = content:CreateFontString(nil, 'OVERLAY')
	sample:SetPoint('TOPLEFT', 16, content.cy)
	sample:SetFont(ns.GetFont(), 18, 'OUTLINE')
	sample:SetText('12:34  99  Ready Check  Bloodlust  1234567890')
	sample:SetTextColor(1, 0.82, 0)
	Track(sample)
	content.cy = content.cy - 30
end

local function PageProfiles()
	AddHeader('Profiles')

	local opts = {}
	for _, n in ipairs(ns.GetProfileNames()) do opts[#opts + 1] = { value = n, text = n } end
	AddScrollDropdown('Profile', opts,
		function() return ns.GetCurrentProfile() end,
		function() end,
		function(v) ns.SwitchProfile(v) ShowPage('profiles', true) end)

	local eb = MakeEditBox(content, 180, 22)
	eb:SetPoint('TOPLEFT', 16, content.cy)
	local mk = MakeFlatButton(content, 'Create', 70, 22)
	mk:SetPoint('LEFT', eb, 'RIGHT', 10, 0)
	local function doNew()
		local nm = eb:GetText() and eb:GetText():trim()
		if nm and nm ~= '' then ns.NewProfile(nm) eb:SetText('') ShowPage('profiles', true) end
	end
	mk:SetScript('OnClick', doNew)
	eb:SetScript('OnEnterPressed', function(self) doNew() self:ClearFocus() end)
	Track(eb) Track(mk)
	content.cy = content.cy - 34

	AddButton('Export current profile', ShowExportPopup)
	AddButton('Import profile (paste code)', ShowImportPopup)

	local cur = ns.GetCurrentProfile()
	if cur ~= 'Default' then
		local dlabel = 'Delete profile "' .. cur .. '"'
		AddButton(dlabel, function()
			ns.SwitchProfile('Default')
			ns.DeleteProfile(cur)
			ShowPage('profiles', true)
		end, FitWidth(dlabel))
	end

	if not ns.hasDungeonAlerts then return end

	AddHeader('Kira Reminders profiles')

	local dopts = {}
	for _, n in ipairs(ns.GetDungeonProfileNames()) do dopts[#dopts + 1] = { value = n, text = n } end
	AddScrollDropdown('Reminders profile', dopts,
		function() return ns.GetDungeonProfile() end,
		function() end,
		function(v) ns.SwitchDungeonProfile(v) ShowPage('profiles', true) end)

	local deb = MakeEditBox(content, 180, 22)
	deb:SetPoint('TOPLEFT', 16, content.cy)
	local dmk = MakeFlatButton(content, 'Create', 70, 22)
	dmk:SetPoint('LEFT', deb, 'RIGHT', 10, 0)
	local function doNewDungeon()
		local nm = deb:GetText() and deb:GetText():trim()
		if nm and nm ~= '' then
			ns.NewDungeonProfile(nm)
			deb:SetText('')
			ShowPage('profiles', true)
		end
	end
	dmk:SetScript('OnClick', doNewDungeon)
	deb:SetScript('OnEnterPressed', function(self) doNewDungeon() self:ClearFocus() end)
	Track(deb) Track(dmk)
	content.cy = content.cy - 34

	AddButton('Export reminders', ShowDungeonExportPopup)
	local dimport = 'Import reminders (paste code)'
	AddButton(dimport, ShowDungeonImportPopup, FitWidth(dimport))

	local dcur = ns.GetDungeonProfile()
	if dcur ~= 'Default' then
		local ddelete = 'Delete reminders profile "' .. dcur .. '"'
		AddButton(ddelete, function()
			ns.SwitchDungeonProfile('Default')
			ns.DeleteDungeonProfile(dcur)
			ShowPage('profiles', true)
		end, FitWidth(ddelete))
	end
end

local PageDungeonAlerts
do
	local pendingCat = { add = 'tank' }
	local pendingCD, pendingCast = true, false
	local kindTab = 'countdown'
	local bossFilter = { all = '' }

	local function NumText(v, fallback)
		local n = tonumber(v) or fallback or 0
		if n == math.floor(n) then return tostring(math.floor(n)) end
		return format('%.1f', n)
	end

	local function CommitSeconds(box, tbl, key, fallback, minimum)
		local n = tonumber(box:GetText())
		if n then
			n = math.floor(n * 10 + 0.5) / 10
			local lo = minimum or 0.1
			if n < lo then n = lo elseif n > 60 then n = 60 end
			if n ~= tbl[key] then
				tbl[key] = n
				ns.DAApply()
			end
		end
		box:SetText(NumText(tbl[key], fallback))
	end

	local function PendingCat(which)
		local cats = ns.DACatList()
		for _, c in ipairs(cats) do
			if c.key == pendingCat[which] then return c.key end
		end
		pendingCat[which] = cats[1] and cats[1].key or 'tank'
		return pendingCat[which]
	end

	local function DungeonOptions()
		local out = {}
		local here = ns.DACurrentInstance and ns.DACurrentInstance()
		for _, d in ipairs(ns.DADungeons or {}) do
			local text = d.name
			if here and d.id == here then text = text .. '  |cff40a5e4(here)|r' end
			out[#out + 1] = { value = tostring(d.id), text = text }
		end
		return out
	end

	local function FindCat(key)
		for _, c in ipairs(ns.DACatList()) do
			if c.key == key then return c end
		end
		return nil
	end

	local function CatCode(key)
		local c = FindCat(key)
		local col = c and c.color
		if type(col) ~= 'table' then return 'ffffff' end
		return format('%02x%02x%02x', (col[1] or 1) * 255, (col[2] or 1) * 255, (col[3] or 1) * 255)
	end

	local function CatText(key)
		return format('|cff%s%s|r', CatCode(key), ns.DACatLabel(key))
	end

	local function CatOptions()
		local out = {}
		for _, c in ipairs(ns.DACatList()) do
			out[#out + 1] = { value = c.key, text = CatText(c.key) }
		end
		return out
	end

	local function LSMLib()
		return ns.LSM and ns.LSM()
	end

	local function SoundOptions()
		local out = { { value = '', text = '|cff777777No sound|r' } }
		local lib = LSMLib()
		if lib then
			for _, name in ipairs(lib:List('sound') or {}) do
				out[#out + 1] = { value = name, text = name }
			end
		end
		return out
	end

	local function SoundText(name)
		if type(name) ~= 'string' or name == '' then return '|cff777777No sound|r' end
		return name
	end

	local function PlaySoundNamed(name)
		local path = ns.DAFetchMedia and ns.DAFetchMedia('sound', name)
		if not path then return end
		local ok, willPlay = pcall(_G.PlaySoundFile, path, 'Master')
		if not ok or willPlay == false then
			pcall(_G.PlaySoundFile, path, 'SFX')
		end
	end

	local function ArrowTexOptions()
		local out = {}
		local lib = LSMLib()
		if lib then
			for _, name in ipairs(lib:List('background') or {}) do
				out[#out + 1] = { value = name, text = name }
			end
		end
		if #out == 0 then
			out[1] = { value = '', text = '|cff777777LibSharedMedia not loaded|r' }
		end
		return out
	end

	local DIRS = {
		{ value = '',      text = '|cff777777No arrow|r' },
		{ value = 'LEFT',  text = 'Left' },
		{ value = 'RIGHT', text = 'Right' },
		{ value = 'UP',    text = 'Up' },
		{ value = 'DOWN',  text = 'Down' },
	}

	local function DirText(v)
		for _, d in ipairs(DIRS) do
			if d.value == (v or '') then return d.text end
		end
		return '|cff777777No arrow|r'
	end

	local GROUNDS = {
		{ key = 'countdown', label = 'Countdown' },
		{ key = 'cast',      label = 'Casts' },
		{ key = 'announce',  label = 'Announce' },
	}

	-- The Announce tab's blocks above the announcements. One table, not a local each: this
	-- do-block holds the file's peak local count.
	local Rows = {}

	-- Boss HP calls on the Announce tab: a boss and a threshold; the line counts the last
	-- 5% down to it in steps (runtime in DungeonAlerts, ns.DAHP*). There is deliberately no
	-- way to add one here: the calls come only from Kira's profile string, so a list
	-- without them shows nothing at all. Imported rows can still be tuned or removed.
	function Rows.BossHP(instanceID, Redraw)
		local list = ns.DAHPList(instanceID)
		if #list == 0 then return end

		local title = content:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
		title:SetPoint('TOPLEFT', 18, content.cy)
		title:SetText('Boss HP')
		Track(title)
		content.cy = content.cy - 20

		local stepText = {}
		for i, s in ipairs(ns.DAHPSteps or {}) do stepText[i] = format('%g', s) end
		local atTip = 'The boss health the call counts down to. It starts 5% above it: '
			.. table.concat(stepText, ', ') .. '.'

		-- "at [90] %" starting at x; returns the x after it.
		local function AtBox(x, get, set)
			local pre = content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
			pre:SetPoint('TOPLEFT', x, content.cy - 4)
			pre:SetText('at')
			Track(pre)
			local bx = After(pre, x, x + 16)
			local box = MakeEditBox(content, 44, 20)
			box:SetPoint('TOPLEFT', bx, content.cy)
			box:SetJustifyH('CENTER')
			box:SetText(NumText(get(), 0))
			local function commit(self)
				local n = tonumber(self:GetText())
				if n then set(math.floor(n * 10 + 0.5) / 10) end
				self:SetText(NumText(get(), 0))
			end
			box:SetScript('OnEnterPressed', function(self) commit(self) self:ClearFocus() end)
			box:HookScript('OnEditFocusLost', commit)
			Tooltip(box, atTip)
			Track(box)
			local pct = content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
			pct:SetPoint('TOPLEFT', bx + 50, content.cy - 4)
			pct:SetText('%')
			Track(pct)
			return After(pct, bx + 50, bx + 62, 10)
		end

		local UNITS = {}
		for i = 1, 5 do UNITS[i] = { value = 'boss' .. i, text = 'boss' .. i } end

		for idx = 1, #list do
			local row = list[idx]

			local name = content:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
			name:SetPoint('TOPLEFT', 18, content.cy - 4)
			name:SetWidth(340)
			name:SetJustifyH('LEFT')
			name:SetWordWrap(false)
			name:SetText(row.boss or ('Encounter ' .. tostring(row.enc)))
			Track(name)

			local test = MakeFlatButton(content, 'Test', 52, 20)
			test:SetPoint('TOPLEFT', 376, content.cy - 3)
			test:SetScript('OnClick', function() ns.DAHPTest(instanceID, idx) end)
			Tooltip(test, 'Plays every step of this call on screen, half a second each.')
			Track(test)

			local rem = MakeFlatButton(content, 'Remove', 58, 20)
			rem:SetPoint('TOPLEFT', 440, content.cy - 3)
			rem:SetScript('OnClick', function()
				table.remove(list, idx)
				Redraw()
			end)
			Track(rem)
			content.cy = content.cy - 26

			local tBox = MakeEditBox(content, 140, 20)
			tBox:SetPoint('TOPLEFT', 28, content.cy)
			tBox:SetText(row.text or '')
			local function commitText(self)
				local txt = Trim(self:GetText())
				local now = (txt ~= '') and txt or nil
				if now ~= row.text then
					row.text = now
					ns.DAApply()
				end
			end
			tBox:SetScript('OnEnterPressed', function(self) commitText(self) self:ClearFocus() end)
			tBox:HookScript('OnEditFocusLost', commitText)
			Tooltip(tBox, 'Written before the percent, e.g. "Phase 1.5%". Leave it empty for the number alone.')
			Track(tBox)

			local unitX = AtBox(176,
				function() return row.at end,
				function(v)
					if v == row.at then return end
					row.at = v
					ns.DAHPList(instanceID)
					ns.DAApply()
				end)

			local unitBtn = MakeFlatButton(content, row.unit or 'boss1', 60, 20)
			unitBtn:SetPoint('TOPLEFT', unitX, content.cy)
			unitBtn:SetScript('OnClick', function()
				OpenScrollPopup(unitBtn, UNITS,
					function() return row.unit or 'boss1' end,
					function(v) row.unit = v end,
					function()
						unitBtn:SetText(row.unit or 'boss1')
						ns.DAApply()
					end)
			end)
			Tooltip(unitBtn, 'Which boss frame to read. boss1 unless the fight has more than one boss.')
			Track(unitBtn)

			content.cy = content.cy - 30
		end

		content.cy = content.cy - 6
	end

	-- Wrong target (runtime in DungeonAlerts, ns.DAWT*): the rules are built in, so the block
	-- only names the fight and offers the Test button.
	function Rows.WrongTarget(instanceID)
		local list = ns.DAWTRules(instanceID)
		if not list then return end

		local title = content:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
		title:SetPoint('TOPLEFT', 18, content.cy)
		title:SetText('Wrong Target')
		Track(title)
		content.cy = content.cy - 20

		for _, row in ipairs(list) do
			local name = content:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
			name:SetPoint('TOPLEFT', 18, content.cy - 4)
			name:SetWidth(340)
			name:SetJustifyH('LEFT')
			name:SetWordWrap(false)
			name:SetText(row.boss)
			Track(name)

			local test = MakeFlatButton(content, 'Test', 52, 20)
			test:SetPoint('TOPLEFT', 376, content.cy - 3)
			test:SetScript('OnClick', function() ns.DAWTTest() end)
			Track(test)
			content.cy = content.cy - 26
		end

		content.cy = content.cy - 6
	end

	local function SpellList(instanceID, bossMap)
		local list = ns.DASpells(instanceID)
		local announcing = (kindTab == 'announce')

		local function Redraw()
			ns.DAApply()
			ShowPage('dungeonalerts', true)
		end

		local idBox = MakeEditBox(content, 76, 22)
		idBox:SetPoint('TOPLEFT', 16, content.cy)
		idBox:SetNumeric(true)
		Tooltip(idBox, announcing and 'Spell ID. Enter adds a scripted announcement for it.'
			or 'Spell ID. Enter adds it with whatever is ticked.')
		Track(idBox)

		local W_CD, W_CAST = 86, 72
		local catX, addX, prevX = 268, 362, 414

		if announcing then
			catX, addX, prevX = 100, 200, 260
		else
			local newCD = MakeTickBox(content, 'Countdown', W_CD)
			newCD:SetPoint('TOPLEFT', 100, content.cy - 2)
			local newCast = MakeTickBox(content, 'Cast', W_CAST)
			newCast:SetPoint('TOPLEFT', 190, content.cy - 2)

			newCD:SetChecked(pendingCD)
			newCast:SetChecked(pendingCast)

			local function SetNew(which, v)
				if which == 'cd' then pendingCD = v else pendingCast = v end
				if not pendingCD and not pendingCast then
					if which == 'cd' then pendingCast = true else pendingCD = true end
				end
				newCD:SetChecked(pendingCD)
				newCast:SetChecked(pendingCast)
			end
			newCD:SetScript('OnClick', function() SetNew('cd', not pendingCD) end)
			newCast:SetScript('OnClick', function() SetNew('cast', not pendingCast) end)
			Tooltip(newCD, 'Countdown list: a bar that counts down to the mechanic and ends as it lands.')
			Tooltip(newCast, 'Casts list: a bar - or a circle - that starts when BigWigs announces the spell and runs for a length you set.\n\nTick both to add it to both lists.')
			Track(newCD)
			Track(newCast)
		end

		local catBtn = MakeFlatButton(content, CatText(PendingCat('add')), 90, 22)
		catBtn:SetPoint('TOPLEFT', catX, content.cy)
		catBtn:SetScript('OnClick', function()
			OpenScrollPopup(catBtn, CatOptions(),
				function() return PendingCat('add') end,
				function(v) pendingCat.add = v end,
				function() catBtn:SetText(CatText(PendingCat('add'))) end)
		end)
		Tooltip(catBtn, announcing and 'Colour the announcement is written in.'
			or 'Colour category the new bars start in.')
		Track(catBtn)

		local function FollowAdd()
			if kindTab == 'cast' and not pendingCast then kindTab = 'countdown'
			elseif kindTab == 'countdown' and not pendingCD then kindTab = 'cast' end
		end

		local function AddSpell()
			local id = tonumber(idBox:GetText())
			if not id or id <= 0 then return end

			if announcing then
				list[#list + 1] = {
					id = id, kind = 'announce', cat = PendingCat('add'),
					lead = ns.DADefaultAnnounceLead,
					hold = ns.DADefaultAnnounceHold,
					steps = { {} },
				}
				idBox:SetText('')
				Redraw()
				return
			end

			if pendingCD then
				local have = false
				for _, e in ipairs(list) do
					if e.kind == 'countdown' and tonumber(e.id) == id then have = true break end
				end
				if not have then
					list[#list + 1] = { id = id, kind = 'countdown', cat = PendingCat('add') }
				end
			end
			if pendingCast then
				list[#list + 1] = {
					id = id, kind = 'cast', cat = PendingCat('add'),
					duration = ns.DADefaultCastSeconds,
				}
			end

			idBox:SetText('')
			FollowAdd()
			Redraw()
		end

		idBox:SetScript('OnEnterPressed', function(self) AddSpell() self:ClearFocus() end)

		local addBtn = MakeFlatButton(content, 'Add', 48, 22)
		addBtn:SetPoint('TOPLEFT', addX, content.cy)
		addBtn:SetScript('OnClick', AddSpell)
		Track(addBtn)

		local isPrev = ns.DAIsListPreview(instanceID)
		local prevBtn = MakeFlatButton(content, isPrev and 'Stop' or 'Preview', 80, 22)
		prevBtn:SetPoint('TOPLEFT', prevX, content.cy)
		prevBtn:SetScript('OnClick', function()
			ns.DASetListPreview(instanceID, not ns.DAIsListPreview(instanceID))
			if CONFIG.__kiraPreviews then
				CONFIG.__kiraPreviews['dalist:' .. tostring(instanceID)] = function()
					if ns.DAIsListPreview(instanceID) then ns.DASetListPreview(instanceID, false) end
				end
			end
			ShowPage('dungeonalerts', true)
		end)
		Tooltip(prevBtn, 'Show everything listed below on screen, drawn the way it will appear in the dungeon.')
		Track(prevBtn)
		content.cy = content.cy - 34

		do
			local total, gap = 480, 6
			local w = (total - gap * (#GROUNDS - 1)) / #GROUNDS
			local x = 16
			for _, h in ipairs(GROUNDS) do
				local on = (kindTab == h.key)
				local b = MakeFlatButton(content, h.label, w, 24)
				b:SetPoint('TOPLEFT', x, content.cy)
				SetButtonState(b, on)
				if not on then
					b:SetScript('OnClick', function()
						kindTab = h.key
						ShowPage('dungeonalerts', true)
					end)
				end
				local tip = 'Bars that count down to the mechanic and end as it lands. One per spell.'
				if h.key == 'cast' then
					tip = 'Bars or circles that start when BigWigs announces the spell and run for a length you set. A spell can appear here more than once.'
				elseif h.key == 'announce' then
					tip = 'One big line in the middle of the screen, shown before the mechanic. Its steps are read in order, one per cast, wrapping at the end.'
				end
				Tooltip(b, tip)
				Track(b)
				x = x + w + gap
			end
			content.cy = content.cy - 32
		end

		if announcing and ns.DAHiddenSupported and ns.DAHiddenSupported(instanceID) then
			local h = ns.DAHiddenCfg(instanceID)

			local title = content:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
			title:SetPoint('TOPLEFT', 18, content.cy)
			title:SetText('Hidden channel |cff777777- outdoor trash|r')
			Track(title)
			content.cy = content.cy - 16

			local desc = content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
			desc:SetPoint('TOPLEFT', 18, content.cy)
			desc:SetWidth(470)
			desc:SetJustifyH('LEFT')
			desc:SetText('The outdoor channel with no bar and no readable name. Detected by shape - an elite at your level, outdoors, in combat, channelling at nobody - and answered with the alert sound. Saved with this dungeon.')
			Track(desc)
			content.cy = content.cy - TextH(desc, 12) - 8

			local tick = MakeTickBox(content, 'Play the alert sound', 150)
			tick:SetPoint('TOPLEFT', 18, content.cy + 2)
			tick:SetChecked(h.enable)
			tick:SetScript('OnClick', function(self)
				h.enable = not h.enable
				self:SetChecked(h.enable)
				ns.DAApply()
			end)
			Tooltip(tick, 'Off by default. On registers the channel event only while you are in this dungeon.')
			Track(tick)

			local gapLabel = content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
			gapLabel:SetPoint('TOPLEFT', 180, content.cy + 3)
			gapLabel:SetText('then quiet for')
			Track(gapLabel)

			local cdX = After(gapLabel, 180, 262)
			local cdBox = MakeEditBox(content, 40, 20)
			cdBox:SetPoint('TOPLEFT', cdX, content.cy)
			cdBox:SetJustifyH('CENTER')
			cdBox:SetText(NumText(h.cooldown, ns.DAHiddenDefaultCooldown))
			cdBox:SetScript('OnEnterPressed', function(self)
				CommitSeconds(self, h, 'cooldown', ns.DAHiddenDefaultCooldown, 1)
				self:ClearFocus()
			end)
			cdBox:HookScript('OnEditFocusLost', function(self)
				CommitSeconds(self, h, 'cooldown', ns.DAHiddenDefaultCooldown, 1)
			end)
			Tooltip(cdBox, 'How long the same mob stays silenced after it has been called. The same nameplate going again inside this window is treated as the same pull.')
			Track(cdBox)

			local cdSuffix = content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
			cdSuffix:SetPoint('TOPLEFT', cdX + 46, content.cy + 3)
			cdSuffix:SetText('sec')
			Track(cdSuffix)

			local test = MakeFlatButton(content, 'Test', 60, 20)
			test:SetPoint('TOPLEFT', After(cdSuffix, cdX + 46, 388, 8), content.cy)
			test:SetScript('OnClick', function() ns.DATestHidden() end)
			Tooltip(test, 'Play the alert sound now, to check the sound file is there.')
			Track(test)

			content.cy = content.cy - 28
		end

		if announcing and ns.DAHPList then Rows.BossHP(instanceID, Redraw) end
		if announcing and ns.DAWTRules then Rows.WrongTarget(instanceID) end

		local casting = (kindTab == 'cast')

		local mine = {}
		for idx = 1, #list do
			if list[idx].kind == kindTab then mine[#mine + 1] = idx end
		end

		local bosses = ns.DABossList(instanceID)
		local function Owner(id)
			return bossMap and bossMap[id] or nil
		end

		if bosses and #bosses > 0 and #mine > 0 then
			local used, anyTrash = {}, false
			for _, idx in ipairs(mine) do
				local o = Owner(tonumber(list[idx].id) or 0)
				if o then used[o] = true else anyTrash = true end
			end

			local tabs = { { key = '', label = 'All' } }
			for _, b in ipairs(bosses) do
				if used[b] then tabs[#tabs + 1] = { key = b, label = b } end
			end
			if anyTrash then tabs[#tabs + 1] = { key = '\1trash', label = 'Trash' } end

			local valid = false
			for _, t in ipairs(tabs) do
				if t.key == bossFilter.all then valid = true break end
			end
			if not valid then bossFilter.all = '' end

			if #tabs > 1 then
				local x, rowTop = 16, content.cy
				for _, t in ipairs(tabs) do
					local w = math.max(52, MeasureText(t.label) + 20)
					if x + w > 496 then
						x = 16
						rowTop = rowTop - 26
					end
					local on = (t.key == bossFilter.all)
					local b = MakeFlatButton(content, t.label, w, 22)
					b:SetPoint('TOPLEFT', x, rowTop)
					SetButtonState(b, on)
					if not on then
						b:SetScript('OnClick', function()
							bossFilter.all = t.key
							ShowPage('dungeonalerts', true)
						end)
					end
					Track(b)
					x = x + w + 6
				end
				content.cy = rowTop - 28
			end
		elseif #mine > 0 then
			local hint = content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
			hint:SetPoint('TOPLEFT', 18, content.cy)
			hint:SetText('|cff777777Load the boss list below to split these up by boss.|r')
			Track(hint)
			content.cy = content.cy - 20
		end

		local EMPTY = {
			countdown = 'No countdowns listed for this ',
			cast      = 'No casts listed for this ',
			announce  = 'No announcements listed for this ',
		}

		local function Empty(what)
			local fs = content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
			fs:SetPoint('TOPLEFT', 18, content.cy)
			fs:SetText((EMPTY[kindTab] or 'Nothing listed for this ') .. what .. ' yet.')
			Track(fs)
			content.cy = content.cy - 22
		end

		if #mine == 0 then Empty('dungeon') return end

		local shown = {}
		for _, idx in ipairs(mine) do
			local o = Owner(tonumber(list[idx].id) or 0)
			local f = bossFilter.all
			if f == '' or (f == '\1trash' and not o) or (o and o == f) then
				shown[#shown + 1] = idx
			end
		end

		if #shown == 0 then Empty('boss') return end

		local cols = { { 18, 'Spell' }, { 398, 'ID' } }
		for _, c in ipairs(cols) do
			local h = content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
			h:SetPoint('TOPLEFT', c[1], content.cy)
			h:SetText(c[2])
			Track(h)
		end
		content.cy = content.cy - 16

		local copies, nth = {}, {}
		for _, idx in ipairs(shown) do
			local id = tonumber(list[idx].id) or 0
			copies[id] = (copies[id] or 0) + 1
		end

		for _, idx in ipairs(shown) do
			local e = list[idx]
			local id = tonumber(e.id) or 0
			nth[id] = (nth[id] or 0) + 1

			local label = format('|T%s:18|t %s', ns.DASpellIcon(id), ns.DASpellName(id))
			if (copies[id] or 0) > 1 then
				label = label .. format(' |cff777777#%d|r', nth[id])
			end
			local fs = content:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
			fs:SetPoint('TOPLEFT', 18, content.cy - 4)
			fs:SetWidth(casting and 296 or 370)
			fs:SetJustifyH('LEFT')
			fs:SetWordWrap(false)
			fs:SetText(label)
			Track(fs)

			if casting then
				local ring = MakeTickBox(content, 'Circle', 66)
				ring:SetPoint('TOPLEFT', 326, content.cy - 3)
				ring:SetChecked(e.circle)
				ring:SetScript('OnClick', function()
					e.circle = (not e.circle) or nil
					ring:SetChecked(e.circle)
					ns.DAApply()
				end)
				Tooltip(ring, 'Draw this cast as a ring on the circle anchor instead of as a bar. Its size, colour and number are set on the Display tab, under Cast circles.')
				Track(ring)
			end

			local idFs = content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
			idFs:SetPoint('TOPLEFT', 398, content.cy - 4)
			idFs:SetWidth(40)
			idFs:SetJustifyH('LEFT')
			idFs:SetWordWrap(false)
			idFs:SetText(tostring(id))
			Track(idFs)

			local rem = MakeFlatButton(content, 'Remove', 58, 20)
			rem:SetPoint('TOPLEFT', 440, content.cy - 3)
			rem:SetScript('OnClick', function()
				table.remove(list, idx)
				Redraw()
			end)
			Tooltip(rem, (copies[id] or 0) > 1
				and 'Removes this row only. The other rows listed for this spell stay.'
				or 'Removes this row. The same spell on another list is a separate row and stays.')
			Track(rem)

			content.cy = content.cy - 22

			local function RowCat() return e.cat or 'tank' end
			local function CatButton(x, w)
				local b = MakeFlatButton(content, CatText(RowCat()), w, 20)
				b:SetPoint('TOPLEFT', x, content.cy)
				b:SetScript('OnClick', function()
					OpenScrollPopup(b, CatOptions(), RowCat,
						function(v) e.cat = v end,
						function()
							b:SetText(CatText(RowCat()))
							ns.DAApply()
						end)
				end)
				Track(b)
				return b
			end

			if announcing then
				local leadLabel = content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
				leadLabel:SetPoint('TOPLEFT', 28, content.cy + 3)
				leadLabel:SetText('starts')
				Track(leadLabel)

				local leadX = After(leadLabel, 28, 66)
				local leadBox = MakeEditBox(content, 40, 20)
				leadBox:SetPoint('TOPLEFT', leadX, content.cy)
				leadBox:SetJustifyH('CENTER')
				leadBox:SetText(NumText(e.lead, ns.DADefaultAnnounceLead))
				leadBox:SetScript('OnEnterPressed', function(self)
					CommitSeconds(self, e, 'lead', ns.DADefaultAnnounceLead, 0)
					self:ClearFocus()
				end)
				leadBox:HookScript('OnEditFocusLost', function(self)
					CommitSeconds(self, e, 'lead', ns.DADefaultAnnounceLead, 0)
				end)
				Tooltip(leadBox, 'How many seconds BEFORE the mechanic the line appears, measured back from where the BigWigs bar runs out.')
				Track(leadBox)

				local midX = leadX + 46
				local midLabel = content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
				midLabel:SetPoint('TOPLEFT', midX, content.cy + 3)
				midLabel:SetText('sec early, stays')
				Track(midLabel)

				local holdX = After(midLabel, midX, 210)
				local holdBox = MakeEditBox(content, 40, 20)
				holdBox:SetPoint('TOPLEFT', holdX, content.cy)
				holdBox:SetJustifyH('CENTER')
				holdBox:SetText(NumText(e.hold, ns.DADefaultAnnounceHold))
				holdBox:SetScript('OnEnterPressed', function(self)
					CommitSeconds(self, e, 'hold', ns.DADefaultAnnounceHold, 0.5)
					self:ClearFocus()
				end)
				holdBox:HookScript('OnEditFocusLost', function(self)
					CommitSeconds(self, e, 'hold', ns.DADefaultAnnounceHold, 0.5)
				end)
				Tooltip(holdBox, 'How many seconds the line stays up, counted from when it appeared. 3 early and 7 total = on screen from three seconds before the mechanic until four seconds after.')
				Track(holdBox)

				local secX = holdX + 46
				local secLabel = content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
				secLabel:SetPoint('TOPLEFT', secX, content.cy + 3)
				secLabel:SetText('sec')
				Track(secLabel)

				local catBX = After(secLabel, secX, 284)
				CatButton(catBX, 96)

				local test = MakeFlatButton(content, 'Test', 60, 20)
				test:SetPoint('TOPLEFT', math.max(388, catBX + 96 + 8), content.cy)
				test:SetScript('OnClick', function() ns.DATestAnnounce(instanceID, idx) end)
				Tooltip(test, 'Say the next step for real - text, arrow and sound. Press once per step to walk the whole rotation.')
				Track(test)

				content.cy = content.cy - 26

				local steps = e.steps or {}
				for si = 1, #steps do
					local st = steps[si]

					local n = content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
					n:SetPoint('TOPLEFT', 44, content.cy + 3)
					n:SetText(tostring(si) .. '.')
					Track(n)

					local sBox = MakeEditBox(content, 150, 20)
					sBox:SetPoint('TOPLEFT', 64, content.cy)
					sBox:SetText(st.text or '')
					local function commitStep(self)
						local txt = Trim(self:GetText())
						local now = (txt ~= '') and txt or nil
						if now ~= st.text then
							st.text = now
							ns.DAApply()
						end
					end
					sBox:SetScript('OnEnterPressed', function(self) commitStep(self) self:ClearFocus() end)
					sBox:HookScript('OnEditFocusLost', commitStep)
					Tooltip(sBox, 'What the line says on this pass. Leave it empty and it says the category name.')
					Track(sBox)

					local dirBtn = MakeFlatButton(content, DirText(st.dir), 66, 20)
					dirBtn:SetPoint('TOPLEFT', 222, content.cy)
					dirBtn:SetScript('OnClick', function()
						OpenScrollPopup(dirBtn, DIRS,
							function() return st.dir or '' end,
							function(v) st.dir = (v ~= '') and v or nil end,
							function()
								dirBtn:SetText(DirText(st.dir))
								ns.DAApply()
							end)
					end)
					Tooltip(dirBtn, 'Draws an arrow beside the words. Left and Right put it on that side; Up and Down put one on each side.')
					Track(dirBtn)

					local sndBtn = MakeFlatButton(content, SoundText(st.sound), 130, 20)
					sndBtn.__label:ClearAllPoints()
					sndBtn.__label:SetPoint('LEFT', 6, 0)
					sndBtn.__label:SetPoint('RIGHT', -6, 0)
					sndBtn.__label:SetJustifyH('LEFT')
					sndBtn.__label:SetWordWrap(false)
					sndBtn:SetPoint('TOPLEFT', 294, content.cy)
					sndBtn:SetScript('OnClick', function()
						OpenScrollPopup(sndBtn, SoundOptions(),
							function() return st.sound or '' end,
							function(v) st.sound = (v ~= '') and v or nil end,
							function()
								sndBtn:SetText(SoundText(st.sound))
								ns.DAApply()
							end,
							nil, PlaySoundNamed)
					end)
					Tooltip(sndBtn, 'Played when this step appears. The speaker beside each name plays it, so you can find one by ear.')
					Track(sndBtn)

					if #steps > 1 then
						local del = MakeFlatButton(content, 'X', 20, 20)
						del:SetPoint('TOPLEFT', 430, content.cy)
						del:SetScript('OnClick', function()
							table.remove(steps, si)
							Redraw()
						end)
						Tooltip(del, 'Removes this step from the rotation.')
						Track(del)
					end

					content.cy = content.cy - 24
				end

				local addStep = MakeFlatButton(content, 'Add step', 90, 20)
				addStep:SetPoint('TOPLEFT', 64, content.cy)
				addStep:SetScript('OnClick', function()
					steps[#steps + 1] = {}
					e.steps = steps
					Redraw()
				end)
				Tooltip(addStep, 'One more pass before the rotation starts over.')
				Track(addStep)

				content.cy = content.cy - 30

			else
				local tBox = MakeEditBox(content, casting and 170 or 210, 20)
				tBox:SetPoint('TOPLEFT', 28, content.cy)
				tBox:SetText(e.text or '')
				local function commitText(self)
					local txt = Trim(self:GetText())
					local now = (txt ~= '') and txt or nil
					if now ~= e.text then
						e.text = now
						ns.DAApply()
					end
				end
				tBox:SetScript('OnEnterPressed', function(self) commitText(self) self:ClearFocus() end)
				tBox:HookScript('OnEditFocusLost', commitText)
				Tooltip(tBox, 'What this bar says. Leave it empty and it says the category name. The colour always comes from the category.')
				Track(tBox)

				CatButton(casting and 206 or 250, casting and 92 or 100)

				if casting then
					local dBox = MakeEditBox(content, 44, 20)
					dBox:SetPoint('TOPLEFT', 330, content.cy)
					dBox:SetJustifyH('CENTER')
					dBox:SetText(NumText(e.duration, ns.DADefaultCastSeconds))

					local dLabel = content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
					dLabel:SetPoint('RIGHT', dBox, 'LEFT', -5, 0)
					dLabel:SetText('for')
					Track(dLabel)

					dBox:SetScript('OnEnterPressed', function(self)
						CommitSeconds(self, e, 'duration', ns.DADefaultCastSeconds, 0.1)
						self:ClearFocus()
					end)
					dBox:HookScript('OnEditFocusLost', function(self)
						CommitSeconds(self, e, 'duration', ns.DADefaultCastSeconds, 0.1)
					end)
					Tooltip(dBox, 'How many seconds the bar stays on screen. Decimals are fine - 2.5 works. The real cast length cannot be read by an addon, so it is typed.')
					Track(dBox)

					local dSuffix = content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
					dSuffix:SetPoint('LEFT', dBox, 'RIGHT', 5, 0)
					dSuffix:SetText('sec')
					Track(dSuffix)

					local delayed = (tonumber(e.delay) or 0) > 0
					local delayTick = MakeTickBox(content, 'Delay', 62)
					delayTick:SetPoint('TOPLEFT', 410, content.cy + 1)
					delayTick:SetChecked(delayed)
					delayTick:SetScript('OnClick', function()
						e.delay = (not delayed) and ns.DADefaultCastDelay or nil
						Redraw()
					end)
					Tooltip(delayTick, 'Wait before showing this bar: BigWigs announces the spell, the seconds you set pass, then the bar appears and runs for its own length. Two rows for one spell - one plain, one delayed - gives a two-part mechanic a bar for each.')
					Track(delayTick)

					if delayed then
						content.cy = content.cy - 24

						local wBox = MakeEditBox(content, 44, 20)
						wBox:SetPoint('TOPLEFT', 46, content.cy)
						wBox:SetJustifyH('CENTER')
						wBox:SetText(NumText(e.delay, ns.DADefaultCastDelay))

						local wLabel = content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
						wLabel:SetPoint('RIGHT', wBox, 'LEFT', -5, 0)
						wLabel:SetText('wait')
						Track(wLabel)

						wBox:SetScript('OnEnterPressed', function(self)
							CommitSeconds(self, e, 'delay', ns.DADefaultCastDelay, 0.1)
							self:ClearFocus()
						end)
						wBox:HookScript('OnEditFocusLost', function(self)
							CommitSeconds(self, e, 'delay', ns.DADefaultCastDelay, 0.1)
						end)
						Tooltip(wBox, 'Seconds between BigWigs announcing the spell and this bar appearing.')
						Track(wBox)

						local wSuffix = content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
						wSuffix:SetPoint('LEFT', wBox, 'RIGHT', 5, 0)
						wSuffix:SetText('sec after BigWigs announces it')
						wSuffix:SetTextColor(0.47, 0.47, 0.47)
						Track(wSuffix)
					end
				end

				content.cy = content.cy - 28
			end
		end
		content.cy = content.cy - 8
	end

	local UNIT_SCOPES = {
		{ value = 'NAMEPLATE', text = 'Nameplates' },
		{ value = 'PLAYER',    text = 'You' },
	}

	local function ScopeText(v)
		for _, u in ipairs(UNIT_SCOPES) do
			if u.value == (v or 'NAMEPLATE') then return u.text end
		end
		return 'Nameplates'
	end

	local trashPendingID
	local trashWhere = 'ALL'

	local function TrashScopeOptions()
		local out = { { value = 'ALL', text = 'Any key' } }
		local here = ns.DACurrentInstance and ns.DACurrentInstance()
		for _, d in ipairs(ns.DADungeons or {}) do
			local text = d.name
			if here and d.id == here then text = text .. '  |cff40a5e4(here)|r' end
			out[#out + 1] = { value = tostring(d.id), text = text }
		end
		return out
	end

	local function TrashTab(cfg)
		if not ns.DATrashSupported() then
			return
		end

		AddCheck('Enable trash sounds',
			function() return cfg().trashEnable end,
			function(v) cfg().trashEnable = v ns.DAApply() end)
		AddCheck('Only inside instances',
			function() return cfg().trashInstanceOnly end,
			function(v) cfg().trashInstanceOnly = v ns.DAApply() end,
			'Applies to the "Any key" rows only. Off means those rows play in the open world too.')
		AddDropdown('Sound channel',
			{ { value = 'Master', text = 'Master' }, { value = 'Dialog', text = 'Dialog' },
			  { value = 'SFX', text = 'Sound effects' }, { value = 'Ambience', text = 'Ambience' },
			  { value = 'Music', text = 'Music' } },
			function() return cfg().trashChannel end,
			function(v) cfg().trashChannel = v ns.DAApply() end)

		AddSlider('Nameplate seats per call-out', 1, 40, 1,
			function() return cfg().trashPlates end,
			function(v) cfg().trashPlates = v ns.DAApply() end,
			'How many nameplates a call-out listens on; 40 is all of them. The sound plays once per listening nameplate, so five mobs gaining the aura together is five copies at once. At 3 a wave is never louder than three copies.')

		AddDropdown('Key', TrashScopeOptions(),
			function() return trashWhere end,
			function(v) trashWhere = v ShowPage('dungeonalerts') end)

		local anyKey = (trashWhere == 'ALL')

		local list = anyKey and ns.DATrashAny() or ns.DATrashList(tonumber(trashWhere) or 0)

		if anyKey and #list > 0 then
			AddButton('Sort these into their keys', function()
				ns.DASortTrashByKey()
				ShowPage('dungeonalerts', true)
			end, 200)
		end

		local function Redraw()
			ns.DAApply()
			ShowPage('dungeonalerts', true)
		end

		local idBox = MakeEditBox(content, 76, 22)
		idBox:SetPoint('TOPLEFT', 16, content.cy)
		idBox:SetNumeric(true)
		Tooltip(idBox, 'Aura spell ID - the buff or debuff itself, not the spell that applies it.')
		Track(idBox)

		local scopeBtn = MakeFlatButton(content, ScopeText(trashPendingID), 110, 22)
		scopeBtn:SetPoint('TOPLEFT', 100, content.cy)
		scopeBtn:SetScript('OnClick', function()
			OpenScrollPopup(scopeBtn, UNIT_SCOPES,
				function() return trashPendingID or 'NAMEPLATE' end,
				function(v) trashPendingID = v end,
				function() scopeBtn:SetText(ScopeText(trashPendingID)) end)
		end)
		Tooltip(scopeBtn, 'Which units to watch. Nameplates covers everything with a nameplate - i.e. trash.')
		Track(scopeBtn)

		local function AddTrash()
			local id = tonumber(idBox:GetText())
			if not id or id <= 0 then return end
			for _, e in ipairs(list) do
				if tonumber(e.id) == id and (e.unit or 'NAMEPLATE') == (trashPendingID or 'NAMEPLATE') then
					idBox:SetText('')
					return
				end
			end
			list[#list + 1] = { id = id, unit = trashPendingID or 'NAMEPLATE' }
			idBox:SetText('')
			Redraw()
		end
		idBox:SetScript('OnEnterPressed', function(self) AddTrash() self:ClearFocus() end)

		local addBtn = MakeFlatButton(content, 'Add', 48, 22)
		addBtn:SetPoint('TOPLEFT', 218, content.cy)
		addBtn:SetScript('OnClick', AddTrash)
		Track(addBtn)
		content.cy = content.cy - 34

		if #list == 0 then
			local fs = content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
			fs:SetPoint('TOPLEFT', 18, content.cy)
			fs:SetText(anyKey and 'Nothing listed for every key yet.'
				or 'Nothing listed for this dungeon yet.')
			Track(fs)
			content.cy = content.cy - 22
			return
		end

		for idx = 1, #list do
			local e = list[idx]
			local id = tonumber(e.id) or 0

			local fs = content:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
			fs:SetPoint('TOPLEFT', 18, content.cy - 4)
			fs:SetWidth(370)
			fs:SetJustifyH('LEFT')
			fs:SetWordWrap(false)
			fs:SetText(format('|T%s:18|t %s', ns.DASpellIcon(id), ns.DASpellName(id)))
			Track(fs)

			local idFs = content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
			idFs:SetPoint('TOPLEFT', 398, content.cy - 4)
			idFs:SetWidth(40)
			idFs:SetJustifyH('LEFT')
			idFs:SetWordWrap(false)
			idFs:SetText(tostring(id))
			Track(idFs)

			local rem = MakeFlatButton(content, 'Remove', 58, 20)
			rem:SetPoint('TOPLEFT', 440, content.cy - 3)
			rem:SetScript('OnClick', function()
				table.remove(list, idx)
				Redraw()
			end)
			Track(rem)
			content.cy = content.cy - 22

			local function SoundSlot(x, key, label, tip)
				local fsL = content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
				fsL:SetPoint('TOPLEFT', x, content.cy + 3)
				fsL:SetText(label)
				Track(fsL)

				local b = MakeFlatButton(content, SoundText(e[key]), 150, 20)
				b.__label:ClearAllPoints()
				b.__label:SetPoint('LEFT', 6, 0)
				b.__label:SetPoint('RIGHT', -6, 0)
				b.__label:SetJustifyH('LEFT')
				b.__label:SetWordWrap(false)
				b:SetPoint('TOPLEFT', After(fsL, x, x + 42), content.cy)
				b:SetScript('OnClick', function()
					OpenScrollPopup(b, SoundOptions(),
						function() return e[key] or '' end,
						function(v) e[key] = (v ~= '') and v or nil end,
						function()
							b:SetText(SoundText(e[key]))
							ns.DAApply()
						end,
						nil, PlaySoundNamed)
				end)
				Tooltip(b, tip)
				Track(b)
			end

			SoundSlot(28, 'show', 'Show', 'Played when the aura appears on the unit. The speaker beside each name plays it, so you can find one by ear.')
			SoundSlot(262, 'hide', 'Hide', 'Played when the aura falls off.')
			content.cy = content.cy - 24

			SoundSlot(28, 'stack', 'Stack', 'Played when the aura gains an application. Silent on a debuff that never stacks.')

			local scope = MakeFlatButton(content, ScopeText(e.unit), 110, 20)
			scope:SetPoint('TOPLEFT', 304, content.cy)
			scope:SetScript('OnClick', function()
				OpenScrollPopup(scope, UNIT_SCOPES,
					function() return e.unit or 'NAMEPLATE' end,
					function(v) e.unit = v end,
					function()
						scope:SetText(ScopeText(e.unit))
						ns.DAApply()
					end)
			end)
			Tooltip(scope, 'Which units this call-out watches. Nameplates are re-registered as they come and go, which is why a huge list costs more than a short one.')
			Track(scope)

			content.cy = content.cy - 30
		end
		content.cy = content.cy - 8
	end

	local function DisplayTab(cfg)
		AddPreviewToggle(ns.DAIsCatPreview, ns.DASetCatPreview)

		AddHeader('Countdown bars')
		AddDropdown('Style',
			{ { value = 'BAR', text = 'Bar' }, { value = 'TEXT', text = 'Text only' } },
			function() return cfg().style end,
			function(v) cfg().style = v ns.DAApply() end)
		AddDropdown('Text alignment',
			{ { value = 'CENTER', text = 'Centre' }, { value = 'LEFT', text = 'Left' } },
			function() return cfg().textAlign end,
			function(v) cfg().textAlign = v ns.DAApply() end)
		local function BarGeometry(prefix)
			local function K(k) return prefix == '' and k or prefix .. k:sub(1, 1):upper() .. k:sub(2) end
			local function get(k) return function() return cfg()[K(k)] end end
			local function set(k) return function(v) cfg()[K(k)] = v ns.DAApply() end end
			AddSlider('Bar width', 80, 500, 2, get('width'), set('width'))
			AddSlider('Bar height', 8, 60, 1, get('height'), set('height'),
				'The icon is square and follows this, so it always matches the bar.')
			AddSlider('Spacing', 0, 20, 1, get('spacing'), set('spacing'),
				'Pixels between bars. 0 merges the two borders into a single hairline.')
			AddSlider('Text size', 8, 30, 1, get('fontSize'), set('fontSize'))
			AddDropdown('Growth', { { value = 'UP', text = 'Up' }, { value = 'DOWN', text = 'Down' } }, get('grow'), set('grow'))
			AddCheck('Show icon', get('icon'), set('icon'))
			AddPosition(get('x'), set('x'), get('y'), set('y'))
		end

		AddCheck('Lock position',
			function() return cfg().lock end,
			function(v) cfg().lock = v ns.DAApply() end)
		AddSlider('Countdown length (seconds)', 2, 15, 1,
			function() return cfg().lead end,
			function(v) cfg().lead = v ns.DAApply() end,
			'How long the bar is on screen before the mechanic lands. It starts full and empties right to left.')
		BarGeometry('')

		AddHeader('Casts')
		AddCheck('Enable casts',
			function() return cfg().castEnable end,
			function(v) cfg().castEnable = v ns.DAApply() end,
			'Turns off the second display - bars and circles both - without touching the list.')
		AddCheck('Lock position',
			function() return cfg().castLock end,
			function(v) cfg().castLock = v ns.DAApply() end)
		AddDropdown('Fill direction',
			{ { value = 'FILL', text = 'Fill up (like a castbar)' }, { value = 'DRAIN', text = 'Empty right to left' } },
			function() return cfg().castFill end,
			function(v) cfg().castFill = v ns.DAApply() end)
		BarGeometry('cast')

		AddHeader('Cast circles')
		AddCheck('Lock position',
			function() return cfg().castCircleLock end,
			function(v) cfg().castCircleLock = v ns.DAApply() end)
		AddSlider('Size', 24, 300, 2,
			function() return cfg().castCircleSize end,
			function(v) cfg().castCircleSize = v ns.DAApply() end,
			'Diameter of the ring in pixels. The band scales with it; how wide it is relative to the ring is the Band setting below.')
		AddDropdown('Band',
			{ { value = 'THIN', text = 'Thin' }, { value = 'MEDIUM', text = 'Medium' }, { value = 'THICK', text = 'Thick' } },
			function() return cfg().castCircleBand end,
			function(v) cfg().castCircleBand = v ns.DAApply() end)
		AddColor('Colour',
			function() return cfg().castCircleColor end,
			function(v) cfg().castCircleColor = v ns.DAApply() end)
		AddDropdown('Fill direction',
			{ { value = 'DRAIN', text = 'Empty clockwise' }, { value = 'FILL', text = 'Fill up clockwise' } },
			function() return cfg().castCircleFill end,
			function(v) cfg().castCircleFill = v ns.DAApply() end)
		AddCheck('Show seconds left',
			function() return cfg().castCircleText ~= false end,
			function(v) cfg().castCircleText = v ns.DAApply() ShowPage('dungeonalerts', true) end,
			'The number beside the ring: one decimal, in brackets, counting down.')
		if cfg().castCircleText ~= false then
			AddSlider('Text size', 8, 40, 1,
				function() return cfg().castCircleFontSize end,
				function(v) cfg().castCircleFontSize = v ns.DAApply() end)
			AddColor('Text colour',
				function() return cfg().castCircleTextColor end,
				function(v) cfg().castCircleTextColor = v ns.DAApply() end)
			AddDropdown('Text position',
				{ { value = 'TOP', text = 'Above the ring' }, { value = 'CENTER', text = 'Inside the ring' }, { value = 'BOTTOM', text = 'Below the ring' } },
				function() return cfg().castCircleTextPos end,
				function(v) cfg().castCircleTextPos = v ns.DAApply() end)
		end
		AddPosition(
			function() return cfg().castCircleX end,
			function(v) cfg().castCircleX = v ns.DAApply() end,
			function() return cfg().castCircleY end,
			function(v) cfg().castCircleY = v ns.DAApply() end)

		AddHeader('Repeats')
		AddSlider('Ignore repeats within (seconds)', 0, 30, 0.5,
			function() return cfg().retrigger end,
			function(v) cfg().retrigger = v ns.DAApply() end,
			'Boss modules often announce the same spell several times (timer bar, cast bar, start and land messages), each of which would raise the bar again. Set this below how often the mechanic can really repeat; 0 turns it off. |cffffd200/xeriondr log|r shows what is ignored.')

		AddHeader('Announcement')
		AddCheck('Enable announcements',
			function() return cfg().announceEnable end,
			function(v) cfg().announceEnable = v ns.DAApply() end)
		AddCheck('Lock position',
			function() return cfg().announceLock end,
			function(v) cfg().announceLock = v ns.DAApply() end)
		AddCheck('Show direction arrow',
			function() return cfg().announceArrow end,
			function(v) cfg().announceArrow = v ns.DAApply() end,
			'Left and Right draw one arrow on that side; Up and Down draw one on each side. Off leaves just the words.')
		if cfg().announceArrow then
			AddScrollDropdown('Arrow texture', ArrowTexOptions(),
				function() return cfg().announceArrowTex end,
				function(v) cfg().announceArrowTex = v ns.DAApply() end)
			AddDropdown('Texture points',
				{ { value = 'RIGHT', text = 'Right' }, { value = 'UP', text = 'Up' },
				  { value = 'LEFT', text = 'Left' }, { value = 'DOWN', text = 'Down' } },
				function() return cfg().announceArrowBase end,
				function(v) cfg().announceArrowBase = v ns.DAApply() end)
			AddSlider('Arrow size', 0.4, 2.5, 0.1,
				function() return cfg().announceArrowScale end,
				function(v) cfg().announceArrowScale = v ns.DAApply() end,
				'Relative to the text. Textures differ in how much of their square they fill, so a padded one needs to be bigger to look the same weight.')
		end
		AddSlider('Text size', 12, 72, 1,
			function() return cfg().announceFontSize end,
			function(v) cfg().announceFontSize = v ns.DAApply() end,
			'Bigger than the bars on purpose - this one is read at a glance mid-pull.')
		AddPosition(
			function() return cfg().announceX end,
			function(v) cfg().announceX = v ns.DAApply() end,
			function() return cfg().announceY end,
			function(v) cfg().announceY = v ns.DAApply() end)

		AddHeader('Boss HP')
		AddCheck('Enable boss HP countdown',
			function() return cfg().hpEnable end,
			function(v) cfg().hpEnable = v ns.DAApply() end)
		AddCheck('Lock position',
			function() return cfg().hpLock end,
			function(v) cfg().hpLock = v ns.DAApply() end)
		AddSlider('Text size', 12, 72, 1,
			function() return cfg().hpFontSize end,
			function(v) cfg().hpFontSize = v ns.DAApply() end)
		AddColor('Text colour',
			function() return cfg().hpColor end,
			function(v) cfg().hpColor = v ns.DAApply() end)
		AddCheck('Show bar',
			function() return cfg().hpBar end,
			function(v) cfg().hpBar = v ns.DAApply() ShowPage('dungeonalerts', true) end)
		if cfg().hpBar then
			AddSlider('Bar width', 80, 500, 2,
				function() return cfg().hpBarWidth end,
				function(v) cfg().hpBarWidth = v ns.DAApply() end)
			AddSlider('Bar height', 2, 30, 1,
				function() return cfg().hpBarHeight end,
				function(v) cfg().hpBarHeight = v ns.DAApply() end)
		end
		AddPosition(
			function() return cfg().hpX end,
			function(v) cfg().hpX = v ns.DAApply() end,
			function() return cfg().hpY end,
			function(v) cfg().hpY = v ns.DAApply() end)

		AddHeader('Wrong Target')
		AddCheck('Enable wrong target warning',
			function() return cfg().wtEnable end,
			function(v) cfg().wtEnable = v ns.DAApply() end)
		AddCheck('Mythic and Mythic+ only',
			function() return cfg().wtMythicOnly end,
			function(v) cfg().wtMythicOnly = v ns.DAApply() end)
		AddCheck('Lock position',
			function() return cfg().wtLock end,
			function(v) cfg().wtLock = v ns.DAApply() end)
		AddSlider('Text size', 12, 96, 1,
			function() return cfg().wtFontSize end,
			function(v) cfg().wtFontSize = v ns.DAApply() end)
		AddPosition(
			function() return cfg().wtX end,
			function(v) cfg().wtX = v ns.DAApply() end,
			function() return cfg().wtY end,
			function(v) cfg().wtY = v ns.DAApply() end)

		AddHeader('Bar background')
		AddColor('Background colour',
			function() return cfg().bgColor end,
			function(col) cfg().bgColor = col ns.DAApply() end)
		AddSlider('Background opacity', 0, 1, 0.05,
			function() return cfg().bgAlpha end,
			function(v) cfg().bgAlpha = v ns.DAApply() end)
	end

	local function CategoriesTab(cfg)

		local cats = ns.DACatList()
		for idx = 1, #cats do
			local cat = cats[idx]

			local nameBox = MakeEditBox(content, 132, 22)
			nameBox:SetPoint('TOPLEFT', 16, content.cy)
			nameBox:SetText(cat.label or '')
			local function commitName(self)
				local txt = Trim(self:GetText())
				if txt == '' then
					self:SetText(cat.label or '')
					return
				end
				if txt ~= cat.label then
					cat.label = txt
					ns.DAApply()
					ShowPage('dungeonalerts', true)
				end
			end
			nameBox:SetScript('OnEnterPressed', function(self) commitName(self) self:ClearFocus() end)
			nameBox:HookScript('OnEditFocusLost', commitName)
			Track(nameBox)

			local sw = CreateFrame('Button', nil, content)
			sw:SetSize(20, 20)
			sw:SetPoint('TOPLEFT', 156, content.cy - 1)
			local bord = sw:CreateTexture(nil, 'BACKGROUND')
			bord:SetPoint('TOPLEFT', -1, 1)
			bord:SetPoint('BOTTOMRIGHT', 1, -1)
			bord:SetColorTexture(0, 0, 0, 1)
			sw.tex = sw:CreateTexture(nil, 'ARTWORK')
			sw.tex:SetAllPoints()
			local function paint()
				local c = cat.color or { 1, 1, 1 }
				sw.tex:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, 1)
			end
			paint()
			sw:SetScript('OnClick', function()
				local c = cat.color or { 1, 1, 1 }
				local r, g, b = c[1] or 1, c[2] or 1, c[3] or 1
				local function applyNow()
					local nr, ng, nb = ColorPickerFrame:GetColorRGB()
					cat.color = { nr, ng, nb, 1 }
					paint()
					ns.DAApply()
				end
				local function cancel()
					cat.color = { r, g, b, 1 }
					paint()
					ns.DAApply()
				end
				ColorPickerFrame:SetupColorPickerAndShow({
					r = r, g = g, b = b, hasOpacity = false,
					swatchFunc = applyNow, cancelFunc = cancel,
				})
			end)
			Tooltip(sw, 'Colour for ' .. (cat.label or cat.key))
			Track(sw)

			cat.roles = cat.roles or { TANK = true, HEALER = true, DAMAGER = true }
			local rx = 186
			for _, rk in ipairs(ns.DARoleKeys) do
				local label = ns.DARoleLabel[rk] or rk
				local w = math.max(44, MeasureText(label) + 16)
				local on = cat.roles[rk] ~= false
				local rb = MakeFlatButton(content, label, w, 20)
				rb:SetPoint('TOPLEFT', rx, content.cy - 1)
				SetButtonState(rb, on, { 0.45, 0.45, 0.45 })
				rb:SetScript('OnClick', function()
					cat.roles[rk] = not (cat.roles[rk] ~= false)
					ns.DAApply()
					ShowPage('dungeonalerts', true)
				end)
				Tooltip(rb, on and ('Shown to ' .. label .. ' - click to hide it from them')
					or ('Hidden from ' .. label .. ' - click to show it'))
				Track(rb)
				rx = rx + w + 4
			end

			local function Move(dir)
				local target = idx + dir
				if target < 1 or target > #cats then return end
				cats[idx], cats[target] = cats[target], cats[idx]
				ns.DAApply()
				ShowPage('dungeonalerts', true)
			end
			local function MoveBtn(x, rot, enabled, onClick)
				local b = MakeFlatButton(content, '', 20, 20)
				b:SetPoint('TOPLEFT', x, content.cy - 1)
				local t = b:CreateTexture(nil, 'OVERLAY')
				t:SetTexture(ARROW_TEX)
				t:SetSize(10, 10)
				t:SetPoint('CENTER')
				t:SetRotation(rot)
				if enabled then
					b:SetScript('OnClick', onClick)
				else
					b:EnableMouse(false)
					t:SetVertexColor(0.4, 0.4, 0.4)
				end
				Track(b)
			end
			MoveBtn(370, math.pi / 2, idx > 1, function() Move(-1) end)
			MoveBtn(394, -math.pi / 2, idx < #cats, function() Move(1) end)

			if #cats > 1 then
				local rem = MakeFlatButton(content, 'Remove', 62, 20)
				rem:SetPoint('TOPLEFT', 422, content.cy - 1)
				rem:SetScript('OnClick', function()
					local fallback = cats[idx - 1] or cats[idx + 1]
					if not fallback then return end
					ns.DAReassignCat(cat.key, fallback.key)
					table.remove(cats, idx)
					ns.DAApply()
					ShowPage('dungeonalerts', true)
				end)
				Tooltip(rem, 'Spells using this move to "' .. ((cats[idx - 1] or cats[idx + 1] or {}).label or '?') .. '".')
				Track(rem)
			end

			content.cy = content.cy - 26
		end
		content.cy = content.cy - 6

		local newBox = MakeEditBox(content, 132, 22)
		newBox:SetPoint('TOPLEFT', 16, content.cy)
		Tooltip(newBox, 'Name for a new category. Enter adds it.')
		Track(newBox)
		local function AddCat()
			local txt = Trim(newBox:GetText())
			if txt == '' then return end
			local list = ns.DACatList()
			list[#list + 1] = {
				key = ns.DANewCatKey(txt), label = txt, color = { 1, 1, 1, 1 },
				roles = { TANK = true, HEALER = true, DAMAGER = true },
			}
			newBox:SetText('')
			ns.DAApply()
			ShowPage('dungeonalerts', true)
		end
		newBox:SetScript('OnEnterPressed', function(self) AddCat() self:ClearFocus() end)
		local addCat = MakeFlatButton(content, 'Add category', 100, 22)
		addCat:SetPoint('TOPLEFT', 156, content.cy)
		addCat:SetScript('OnClick', AddCat)
		Track(addCat)
		content.cy = content.cy - 34

		AddButton('Reset categories to default', function()
			cfg().cats = ns.DADefaultCats()
			ns.DAPruneCats()
			ns.DAApply()
			ShowPage('dungeonalerts', true)
		end, 210)
	end

	PageDungeonAlerts = function()
		local function cfg() return ns.DAGetCfg() end

		local tab = AddPinnedTabs('dungeonalerts', { 'Spells', 'Trash Sounds', 'Display', 'Categories' })

		AddHeader('Kira Reminders')

		AddCheck('Enable',
			function() return cfg().enable end,
			function(v) cfg().enable = v ns.DAApply() end)

		if tab == 'Trash Sounds' then
			TrashTab(cfg)
			return
		end
		if tab == 'Display' then
			DisplayTab(cfg)
			return
		end
		if tab == 'Categories' then
			CategoriesTab(cfg)
			return
		end

		AddDropdown('Dungeon', DungeonOptions(),
			function() return cfg().selected end,
			function(v) cfg().selected = v ShowPage('dungeonalerts') end)

		local instanceID = tonumber(cfg().selected) or 0

		local bossMap = ns.DAPeekDungeon(instanceID)

		SpellList(instanceID, bossMap)

		if not bossMap then
			AddButton('Load boss list from BigWigs', function()
				ns.DAResolveDungeon(instanceID, true)
				ShowPage('dungeonalerts', true)
			end, 210)
		end
	end
end

local function AttachScrollBar(sf, gap)
	local track = CreateFrame('Frame', nil, sf:GetParent())
	track:SetWidth(4)
	track:SetPoint('TOPLEFT', sf, 'TOPRIGHT', gap or 6, 0)
	track:SetPoint('BOTTOMLEFT', sf, 'BOTTOMRIGHT', gap or 6, 0)
	local bg = track:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints()
	bg:SetColorTexture(1, 1, 1, 0.06)

	local thumb = CreateFrame('Button', nil, track)
	thumb:SetWidth(4)
	thumb:RegisterForDrag('LeftButton')
	local ttex = thumb:CreateTexture(nil, 'ARTWORK')
	ttex:SetAllPoints()
	ttex:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.8)

	local MIN_THUMB = 24
	local function Update()
		local range = sf:GetVerticalScrollRange() or 0
		if range <= 0.5 then track:Hide() return end
		track:Show()
		local h = track:GetHeight()
		local child = sf:GetScrollChild()
		local total = (child and child:GetHeight()) or 0
		local visible = sf:GetHeight()
		local frac = (total > 0) and math.min(1, visible / total) or 1
		local th = math.max(MIN_THUMB, h * frac)
		if th > h then th = h end
		thumb:SetHeight(th)
		local pos = sf:GetVerticalScroll() / range
		if pos < 0 then pos = 0 elseif pos > 1 then pos = 1 end
		thumb:ClearAllPoints()
		thumb:SetPoint('TOP', track, 'TOP', 0, -pos * (h - th))
	end
	sf.UpdateScrollBar = Update

	thumb:SetScript('OnEnter', function() ttex:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1) end)
	thumb:SetScript('OnLeave', function()
		if not thumb.dragging then ttex:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.8) end
	end)
	thumb:SetScript('OnDragStart', function(self)
		self.dragging = true
		local _, cy = GetCursorPosition()
		self.grabY = cy / track:GetEffectiveScale()
		self.grabScroll = sf:GetVerticalScroll()
		self:SetScript('OnUpdate', function(s)
			local travel = track:GetHeight() - s:GetHeight()
			if travel <= 0 then return end
			local _, ny = GetCursorPosition()
			ny = ny / track:GetEffectiveScale()
			local range = sf:GetVerticalScrollRange()
			local new = s.grabScroll + (s.grabY - ny) / travel * range
			if new < 0 then new = 0 elseif new > range then new = range end
			sf:SetVerticalScroll(new)
		end)
	end)
	thumb:SetScript('OnDragStop', function(self)
		self.dragging = nil
		self:SetScript('OnUpdate', nil)
		ttex:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.8)
	end)

	sf:HookScript('OnVerticalScroll', Update)
	sf:HookScript('OnScrollRangeChanged', Update)
	sf:HookScript('OnSizeChanged', Update)
	return Update
end

local function FirstLeafKey()
	for _, sec in ipairs(navTree) do
		for _, it in ipairs(sec.items) do return it.key end
	end
end

-- WHY THIS EXISTS: the nav column had grown to nine sections and thirty-odd
-- pages, so the flat list was one long scroll. Sections now collapse, and they
-- start collapsed - the user asked for that explicitly. What is open lives in
-- this file-local table and nowhere else, so every /reload starts with every
-- section shut again (the user asked for that too: a short list of headers is
-- faster to scan than whatever was left open last session). It used to be
-- saved in XerionUIChangesDB.__navOpen; the line below drops that leftover. A
-- live search filter overrides the state entirely (below), otherwise typing
-- into the box would find pages it could not then show. The do-block keeps the
-- table off the main chunk's local count, which sits near Lua's 200 ceiling.
local NavSecOpen, NavSecSetOpen
do
	local navOpen = {}
	if _G.XerionUIChangesDB then _G.XerionUIChangesDB.__navOpen = nil end

	function NavSecOpen(title)
		if navFilter ~= '' then return true end
		return navOpen[title] and true or false
	end

	function NavSecSetOpen(title, open)
		navOpen[title] = open or nil
	end
end

-- Everything from here to the end of RebuildNav (forward-declared at the top
-- of the file) serves RebuildNav alone, so it sits in one do-block and costs
-- the main chunk no locals. Left unindented, like the search block below.
--
-- WHY THE SIDEBAR IS KEPT, NOT REMADE
-- RebuildNav runs on every page switch, every click on a section header and
-- every keystroke in the search box. It used to throw the whole column away
-- and make it again each time: sixteen to twenty frames, some seventy textures
-- and font strings and sixty-odd closures per page switch, up to sixty frames
-- per keystroke with every section forced open - and the client never frees a
-- frame, so all of it stayed in memory until /reload. Now each section header
-- and each page button is made the first time the sidebar lists it and kept in
-- the two tables below, keyed by section title and by page key. A rebuild only
-- decides what is listed, anchors those rows in order, shows them, hides the
-- rest and repaints what can change: the +/- sign, the selected row, the text
-- colour, the header lock while a search is typed. The click and hover handlers
-- are shared by every row and read the row they fire on from its own fields,
-- so a kept button never holds a stale closure. The tree is fixed once Build()
-- has run - a page whose module is missing is not in it at all (see Page) - so
-- no kept button ever has to be taken back.
do
local heads, buttons = {}, {}

local ROW_H, HEAD_H, HEAD_GAP, INDENT = 28, 18, 6, 10

local function HeadClick(self)
	-- A typed search forces every section open and takes the mouse off the
	-- headers (PaintHeader); this only makes sure.
	if navFilter ~= '' then return end
	NavSecSetOpen(self.secTitle, not NavSecOpen(self.secTitle))
	RebuildNav()
end
local function HeadEnter(self) self.hl:Show() end
local function HeadLeave(self) self.hl:Hide() end

local function NavHeader(title)
	local f = CreateFrame('Button', nil, navContent)
	f:SetSize(164, 18)
	f.secTitle = title
	local hl = f:CreateTexture(nil, 'BACKGROUND')
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.05)
	hl:Hide()
	f.hl = hl
	local fs = f:CreateFontString(nil, 'OVERLAY')
	fs:SetFont(STANDARD_TEXT_FONT, 10, 'OUTLINE')
	fs:SetPoint('BOTTOMLEFT', 8, 2)
	fs:SetText(title:upper())
	fs:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
	local sign = f:CreateFontString(nil, 'OVERLAY')
	sign:SetFont(STANDARD_TEXT_FONT, 12, 'OUTLINE')
	sign:SetPoint('BOTTOMRIGHT', -7, 1)
	f.sign = sign
	local rule = f:CreateTexture(nil, 'ARTWORK')
	rule:SetHeight(1)
	rule:SetPoint('BOTTOMLEFT', fs, 'BOTTOMRIGHT', 6, 3)
	rule:SetPoint('BOTTOMRIGHT', sign, 'BOTTOMLEFT', -4, 4)
	rule:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.18)
	f:SetScript('OnClick', HeadClick)
	f:SetScript('OnEnter', HeadEnter)
	f:SetScript('OnLeave', HeadLeave)
	heads[title] = f
	return f
end

local function PaintHeader(f, open, locked, hasCurrent)
	f.sign:SetText(open and '-' or '+')
	-- A closed section holding the page you are on keeps the accent; every other
	-- closed one dims, so the sidebar still says where you are with nothing expanded.
	if open or hasCurrent then
		f.sign:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
	else
		f.sign:SetTextColor(0.55, 0.55, 0.60)
	end
	-- Locked while a search is typed: the mouse passes through it, as it did
	-- when a locked header was made with no handlers at all.
	f:EnableMouse(not locked)
	if locked then f.hl:Hide() end
end

local function BtnClick(self) ShowPage(self.pageKey) end
local function BtnEnter(self)
	if currentPage ~= self.pageKey then self.hl:Show() end
	if self.icon then self.icon:SetAlpha(1) end
end
local function BtnLeave(self)
	self.hl:Hide()
	if self.icon and currentPage ~= self.pageKey then self.icon:SetAlpha(0.75) end
end

-- `it.icon` is the page's entry in NAV_ICONS (in the Build block below) or nil;
-- `iconCol` says the row's section has icons at all. Text in such a section
-- starts after the icon column on every row, iconless ones too, so the titles
-- still line up - the way a menu with only some icons does it. Sections with
-- no icons keep the old layout. The icon is looked up once, here, when the
-- button is made - not on every rebuild.
local function NavButton(it, iconCol)
	local b = CreateFrame('Button', nil, navContent)
	b:SetSize(164 - INDENT, 24)
	b.pageKey = it.key
	local icon = it.icon
	local hl = b:CreateTexture(nil, 'BACKGROUND', nil, 0)
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.05)
	hl:Hide()
	b.hl = hl
	local sel = b:CreateTexture(nil, 'BACKGROUND', nil, 1)
	sel:SetAllPoints()
	sel:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.12)
	sel:Hide()
	b.sel = sel
	local bar = b:CreateTexture(nil, 'ARTWORK')
	bar:SetWidth(3)
	bar:SetPoint('TOPLEFT')
	bar:SetPoint('BOTTOMLEFT')
	bar:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
	bar:Hide()
	b.bar = bar
	if icon then
		local t = b:CreateTexture(nil, 'ARTWORK')
		t:SetSize(16, 16)
		t:SetPoint('LEFT', 8, 0)
		-- A spell looked up by ID, so a patch that repaints it is picked up; the
		-- fixed texture beside it is the fallback for a spell the client lacks.
		local tex = icon.tex
		if icon.spell and C_Spell and C_Spell.GetSpellTexture then
			local ok, id = pcall(C_Spell.GetSpellTexture, icon.spell)
			if ok and type(id) == 'number' and not (ns.IsSecret and ns.IsSecret(id)) then tex = id end
		end
		if icon.atlas then
			t:SetAtlas(icon.atlas)
		else
			t:SetTexture(tex)
			-- Spell and item icons carry a bevelled border that reads as noise at
			-- 16 px; UI textures (ready check tick, raid marker) are drawn whole.
			if not icon.whole then t:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
		end
		b.icon = t
	end
	local fs = b:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
	fs:SetPoint('LEFT', iconCol and 29 or 10, 0)
	fs:SetPoint('RIGHT', -4, 0)
	fs:SetJustifyH('LEFT')
	fs:SetWordWrap(false)
	fs:SetText(it.title)
	b.fs = fs
	b:SetScript('OnClick', BtnClick)
	b:SetScript('OnEnter', BtnEnter)
	b:SetScript('OnLeave', BtnLeave)
	buttons[it.key] = b
	return b
end

local function PaintButton(b)
	local isCurrent = (b.pageKey == currentPage)
	b.sel:SetShown(isCurrent)
	b.bar:SetShown(isCurrent)
	if isCurrent then
		b.hl:Hide()
		b.fs:SetTextColor(1, 1, 1)
	else
		b.fs:SetTextColor(0.72, 0.72, 0.76)
	end
	-- Dimmed with the text, or a column of full-colour icons outshouts the
	-- page you are actually on. A kept row still under the mouse keeps the
	-- hover look BtnEnter gave it.
	if b.icon then b.icon:SetAlpha((isCurrent or b.hl:IsShown()) and 1 or 0.75) end
end

local function WordsIn(hay)
	for _, w in ipairs(Search.words) do
		if not hay:find(w, 1, true) then return false end
	end
	return true
end

local function NavMatches(title)
	if navFilter == '' then return true end
	return WordsIn(Plain(title):lower())
end

local function NavMatchesPage(it)
	if navFilter == '' or Search.hits[it.key] then return true end
	local info = Search.pages[it.key]
	return WordsIn(info and info.hay or Plain(it.title):lower())
end

-- One pass over the tree. Each kept widget gets one Show or one Hide, never a
-- Hide and then a Show, so a row that stays listed is never hidden in between.
-- The header goes in with its section's first match, so a section with none is
-- left out whole, header and all.
RebuildNav = function()
	if not navContent then return end
	local y, drawnAny = 0, false
	local searching = navFilter ~= ''
	for _, sec in ipairs(navTree) do
		local sectionHit = NavMatches(sec.title)
		local open = searching or NavSecOpen(sec.title)
		local head = heads[sec.title]
		local listed, hasCurrent = false, false
		for _, it in ipairs(sec.items) do
			if it.key == currentPage then hasCurrent = true end
			local show = false
			if sectionHit or NavMatchesPage(it) then
				if not listed then
					listed = true
					if drawnAny then y = y + HEAD_GAP end
					drawnAny = true
					head = head or NavHeader(sec.title)
					head:ClearAllPoints()
					head:SetPoint('TOPLEFT', 3, -4 - y)
					y = y + HEAD_H
				end
				show = open
			end
			local b = buttons[it.key]
			if show then
				b = b or NavButton(it, sec.icons)
				b:ClearAllPoints()
				b:SetPoint('TOPLEFT', 3 + INDENT, -4 - y)
				y = y + ROW_H
				PaintButton(b)
				b:Show()
			elseif b then
				b:Hide()
				b.hl:Hide()
			end
		end
		if listed then
			PaintHeader(head, open, searching, hasCurrent)
			head:Show()
		elseif head then
			head:Hide()
			head.hl:Hide()
		end
	end
	navContent:SetHeight(math.max(10, y + 10))
	local sf = navContent:GetParent()
	if sf and sf.UpdateScrollBar then sf.UpdateScrollBar() end
end
end -- the sidebar builders' do-block

do

Search.KEYWORDS = {
	appearance     = 'font scale window skin colour color',
	profiles       = 'profile import export share string copy backup',
	eui_np         = 'ellesmere eui nameplates plates',
	eui_missing    = 'ellesmere eui missing addons',
	externals      = 'external defensive cooldowns',
	
	
	
	readyalerts    = 'bloodlust heroism time warp lust sated exhaustion ready cooldown sound alert',
	
	cotank         = 'co tank cotank other tank offtank off-tank health bar raid taunt swap boss debuffs tank debuff stacks',
	
	
	
	
	interrupts     = 'party interrupts kick kicks cooldown bars group',
	
	
	
	class_dk       = 'bdk dk blood death knight bone shield death and decay dnd boiling point the blood is life bloodbeast blood beast damage buff icons drw dancing rune weapon control undead reaper reapers mark deathbringer stacks unholy soul reaper blightfall dark transformation chain putrefy forbidden sacrifice knowledge mastery lesser ghoul',
	class_veng     = 'vdh dh vengeance demon hunter fiery brand phases',
	class_druid    = 'druid bear guardian feral balance boomkin resto restoration cheat death well-honed well honed instincts frenzied regeneration sound bear form reminder not in bear shapeshift combat text warning',
	class_mage     = 'mage alter time health',
	class_brew     = 'brm brewmaster monk expel harm orbs dodge elixir determination',
	class_prot     = 'prot protection paladin shining light wog word of glory charges aura devotion crusader mount missing reminder',
	class_shaman   = 'shaman ele elemental blast crit critical strike haste mastery letters cdm cooldown manager buff icons',
	class_warrior  = 'warrior prot protection arms fury spell reflection reflect reflected damage text meter',
	
	
	
}

local S = {
	index = {},
	builds = {},
	seen = {},
	errors = {},
	frame = nil,
	done = false,
	running = false,
	-- The pass's queue and how far it got, kept between starts, plus its combat
	-- wait frame and the window OnShow hook flag (IndexStep, RunIndexPass).
	jobs = nil,
	queued = nil,
	at = 0,
	waiter = nil,
	onShow = false,
}

function Search.Fold(key)
	local rows = content and content.rows
	if not rows or not key then return end
	local id = key .. '\1' .. (content.tab or '')
	if S.builds[id] then return end
	S.builds[id] = true
	for _, r in ipairs(rows) do
		local sig = key .. '\1' .. r.kind .. '\1' .. r.low .. '\1' .. (r.tabLow or '') .. '\1' .. (r.headerLow or '')
		if not S.seen[sig] then
			S.seen[sig] = true
			S.index[#S.index + 1] = {
				kind = r.kind, text = r.text, low = r.low, tip = r.tip,
				header = r.header, headerLow = r.headerLow,
				tab = r.tab, tabLow = r.tabLow, what = r.what, page = key,
			}
		end
	end
end

local function IndexBuild(key, tab)
	if not S.frame then
		local host = CreateFrame('Frame', nil, UIParent)
		host:Hide()
		S.frame = CreateFrame('Frame', nil, host)
		S.frame:SetSize(500, 10)
		S.frame.widgets = {}
		S.frame.cy = -14
		S.frame.indexing = true
	end
	local saved, savedTab = content, subTab[key]
	if tab then subTab[key] = tab end
	content = S.frame
	ResetContent()
	content.pageKey = key
	local ok, err = pcall(pageBuild[key])
	if not ok then S.errors[key .. (tab and ('/' .. tab) or '')] = tostring(err) end
	local variants = content.variants
	Search.Fold(key)
	ResetContent()
	content = saved
	subTab[key] = savedTab
	return variants
end

-- WHY THE PASS STOPS WITH THE WINDOW
-- The index pass builds every page off-screen, one every 0.02 s, and it used to
-- run to the end whatever happened: on after the window was closed, parked on
-- PLAYER_REGEN_ENABLED in combat and back to work straight after the pull with
-- the window long shut, and at the end it rebuilt the sidebar of a closed
-- window. Now every step first asks whether the window is open, and a shut
-- window ends the pass there; the combat wait does not pick it up again unless
-- the window is open by then. The queue lives on S (S.jobs, S.queued, S.at), not
-- in the pass, so the next start - a keystroke, or the window opening again
-- with a search still typed (the OnShow hook below) - carries on from the next
-- job instead of queueing everything again. A page is built whole inside one
-- step, so a stop never leaves one half-built.
local function IndexQueue(key, tab)
	local id = key .. '\1' .. (tab or '')
	if S.queued[id] or S.builds[id] then return end
	S.queued[id] = true
	S.jobs[#S.jobs + 1] = { key = key, tab = tab }
end

local function IndexStep()
	if not (CONFIG and CONFIG:IsShown()) then
		S.running = false
		if S.waiter then S.waiter:UnregisterEvent('PLAYER_REGEN_ENABLED') end
		return
	end
	if InCombatLockdown() then
		if not S.waiter then
			S.waiter = CreateFrame('Frame')
			S.waiter:SetScript('OnEvent', function(self)
				self:UnregisterEvent('PLAYER_REGEN_ENABLED')
				if CONFIG and CONFIG:IsShown() then
					C_Timer.After(0.05, IndexStep)
				else
					S.running = false
				end
			end)
		end
		S.waiter:RegisterEvent('PLAYER_REGEN_ENABLED')
		return
	end
	S.at = S.at + 1
	local job = S.jobs[S.at]
	if not job then
		S.done, S.running = true, false
		S.jobs, S.queued = nil, nil
		Search.Refresh()
		return
	end
	-- A page opened by hand since it was queued has been folded in already.
	if pageBuild[job.key] and not S.builds[job.key .. '\1' .. (job.tab or '')] then
		local variants = IndexBuild(job.key, job.tab)
		if variants then
			for _, v in ipairs(variants) do IndexQueue(job.key, v) end
		end
	end
	C_Timer.After(0.02, IndexStep)
end

local function RunIndexPass()
	if S.done or S.running or not CONFIG then return end
	S.running = true
	if not S.jobs then
		S.jobs, S.queued, S.at = {}, {}, 0
		for _, sec in ipairs(navTree) do
			for _, it in ipairs(sec.items) do IndexQueue(it.key) end
		end
	end
	-- Reopening the window with a search still in the box carries on with an
	-- index a closed window stopped, so its results come out whole. Hooked the
	-- first time a pass starts, the only way one can be left unfinished.
	if not S.onShow then
		S.onShow = true
		CONFIG:HookScript('OnShow', function()
			if navFilter ~= '' then RunIndexPass() end
		end)
	end
	C_Timer.After(0, IndexStep)
end

local function Fuzzy(hay, needle)
	local hi, ni, hl, nl = 1, 1, #hay, #needle
	local first, last, run, score = nil, nil, 0, 0
	while hi <= hl and ni <= nl do
		if hay:byte(hi) == needle:byte(ni) then
			first = first or hi
			last = hi
			run = run + 1
			score = score + run
			ni = ni + 1
		else
			run = 0
		end
		hi = hi + 1
	end
	if ni <= nl then return nil end
	local span = last - first + 1
	if span > nl + 8 then return nil end
	return score * 100 / span
end

local function WordScore(e, w, hay)
	local best, own
	local s = e.low:find(w, 1, true)
	if s then
		best, own = 60, true
		if s == 1 then best = 80
		elseif e.low:sub(s - 1, s - 1) == ' ' then best = 70 end
	elseif #w >= 3 then
		local f = Fuzzy(e.low, w)
		if f then best, own = 10 + math.min(15, f / 20), true end
	end
	if e.headerLow and e.headerLow:find(w, 1, true) then
		own = true
		if not best or best < 30 then best = 30 end
	end
	if e.tabLow and e.tabLow:find(w, 1, true) then
		own = true
		if not best or best < 30 then best = 30 end
	end
	if e.tip and e.tip:find(w, 1, true) then
		own = true
		if not best or best < 15 then best = 15 end
	end
	if hay and hay:find(w, 1, true) then
		if not best or best < 5 then best = 5 end
	end
	return best, own
end

local KIND_RANK = { page = 0, dest = 1, header = 2, row = 3 }

local function SearchAll(q)
	local words = {}
	for w in q:gmatch('%S+') do words[#words + 1] = w end
	if #words == 0 then return {} end
	local out = {}
	local order = 0
	for _, sec in ipairs(navTree) do
		for _, it in ipairs(sec.items) do
			order = order + 1
			local info = Search.pages[it.key]
			if info then
				local total, all = 0, true
				for _, w in ipairs(words) do
					local s
					local p = info.low:find(w, 1, true)
					if p then s = (p == 1) and 80 or 60
					elseif info.keys:find(w, 1, true) then s = 40
					elseif info.hay:find(w, 1, true) then s = 20
					end
					if not s then all = false break end
					total = total + s
				end
				if all then
					if info.low == q then total = total + 50
					elseif info.low:find(q, 1, true) then total = total + 25 end
					out[#out + 1] = {
						e = { kind = 'page', page = it.key, text = info.title, low = info.low },
						score = total, order = order,
					}
				end
			end
		end
	end
	for i, e in ipairs(S.index) do
		local info = Search.pages[e.page]
		local total, all, own = 0, true, false
		for _, w in ipairs(words) do
			local s, o = WordScore(e, w, info and info.hay)
			if not s then all = false break end
			total = total + s
			if o then own = true end
		end
		if all and (own or e.kind == 'dest') then
			if e.low == q then total = total + 50
			elseif e.low:find(q, 1, true) then total = total + 25 end
			out[#out + 1] = { e = e, score = total, order = 1000 + i }
		end
	end
	table.sort(out, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		local ra, rb = KIND_RANK[a.e.kind] or 9, KIND_RANK[b.e.kind] or 9
		if ra ~= rb then return ra < rb end
		return a.order < b.order
	end)
	local res, seen = {}, {}
	for _, r in ipairs(out) do
		local e = r.e
		local sig = (e.page or '') .. '\1' .. e.kind .. '\1' .. e.low .. '\1' .. (e.headerLow or '')
		if not seen[sig] then
			seen[sig] = true
			res[#res + 1] = e
		end
	end
	return res
end

local popup, popupRows, popupFoot
local popupResults, popupSel = {}, 1
local POP_W, POP_MAX = 440, 10
local ACCENT_HEX = format('|cff%02x%02x%02x',
	math.floor(ACCENT[1] * 255 + 0.5), math.floor(ACCENT[2] * 255 + 0.5), math.floor(ACCENT[3] * 255 + 0.5))

local function RowLabel(e)
	if e.kind == 'page' then return ACCENT_HEX .. 'Page:|r ' .. e.text end
	if e.kind == 'dest' then return ACCENT_HEX .. (e.what or 'Tab') .. ':|r ' .. e.text end
	if e.kind == 'header' then return ACCENT_HEX .. 'Section:|r ' .. e.text end
	return e.text
end

local function Crumb(e)
	local info = Search.pages[e.page]
	local parts = {}
	if info then
		parts[#parts + 1] = info.section
		if e.kind ~= 'page' then parts[#parts + 1] = info.title end
	end
	if e.kind ~= 'dest' and e.tab then parts[#parts + 1] = e.tab end
	if e.kind == 'row' and e.header then parts[#parts + 1] = e.header end
	return table.concat(parts, '  >  ')
end

local function FlashRow(y, h)
	local hl = content.searchHL
	if not hl then
		hl = content:CreateTexture(nil, 'BACKGROUND')
		hl:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.22)
		local ag = hl:CreateAnimationGroup()
		local fade = ag:CreateAnimation('Alpha')
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0)
		fade:SetStartDelay(0.9)
		fade:SetDuration(1.1)
		ag:SetScript('OnFinished', function() hl:Hide() end)
		hl.ag = ag
		content.searchHL = hl
	end
	hl.ag:Stop()
	hl:ClearAllPoints()
	hl:SetPoint('TOPLEFT', content, 'TOPLEFT', 8, y + 4)
	hl:SetPoint('TOPRIGHT', content, 'TOPRIGHT', -8, y + 4)
	hl:SetHeight(h)
	hl:SetAlpha(1)
	hl:Show()
	hl.ag:Play()
end

local function JumpTo(e)
	if popup then popup:Hide() end
	if Search.box then Search.box:ClearFocus() end
	if e.tab then subTab[e.page] = e.tab end
	-- Open the section we are jumping into. The search filter forces every
	-- section open while it is typed, so without this the page would vanish from
	-- the sidebar the moment the user cleared the box.
	local pageInfo = Search.pages[e.page]
	if pageInfo then NavSecSetOpen(pageInfo.section, true) end
	ShowPage(e.page)
	if e.kind == 'page' or e.kind == 'dest' then return end
	local rows, hit, at = content.rows, nil, nil
	for i, r in ipairs(rows) do
		if r.kind == e.kind and r.low == e.low and r.headerLow == e.headerLow then
			hit, at = r, i
			break
		end
	end
	if not hit then
		for i, r in ipairs(rows) do
			if r.low == e.low then hit, at = r, i break end
		end
	end
	if not hit or not hit.y then return end
	local margin = 14 + ((pinnedTabs and pinnedTabs:IsShown()) and 34 or 0)
	local target = math.max(0, -hit.y - margin)
	local okH, viewH = pcall(scroll.GetHeight, scroll)
	local maxScroll = (okH and type(viewH) == 'number') and math.max(0, content:GetHeight() - viewH) or 0
	if target > maxScroll then target = maxScroll end
	scroll:SetVerticalScroll(target)
	if scroll.UpdateScrollBar then scroll.UpdateScrollBar() end
	local nxt = rows[at + 1]
	local h = (nxt and nxt.y) and (hit.y - nxt.y) or 30
	FlashRow(hit.y, math.max(22, math.min(64, h)))
end

local function PaintPopup()
	if not popupRows then return end
	for i, row in ipairs(popupRows) do
		local on = (i == popupSel) and popupResults[i] ~= nil
		row.bg:SetShown(on)
		row.bar:SetShown(on)
	end
end

local function EnsurePopup()
	if popup then return end
	local _, lh = MeasureText('Ag', 'GameFontHighlight')
	local _, sh = MeasureText('Ag', 'GameFontHighlightSmall')
	local _, fh = MeasureText('Ag', 'GameFontDisableSmall')
	local rowH = math.max(34, lh + sh + 10)

	popup = CreateFrame('Frame', nil, CONFIG, 'BackdropTemplate')
	popup:SetWidth(POP_W)
	popup:SetPoint('TOPLEFT', CONFIG, 'TOPLEFT', 174, -44)
	popup:SetFrameLevel((CONFIG:GetFrameLevel() or 1) + 60)
	popup:SetBackdrop({
		bgFile = 'Interface\\Buttons\\WHITE8X8',
		edgeFile = 'Interface\\Buttons\\WHITE8X8',
		edgeSize = 1,
	})
	popup:SetBackdropColor(C_PANEL[1], C_PANEL[2], C_PANEL[3], 0.98)
	popup:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.35)
	popup:EnableMouse(true)
	popup.rowH, popup.footH = rowH, fh
	popup:Hide()

	popupRows = {}
	for i = 1, POP_MAX do
		local row = CreateFrame('Button', nil, popup)
		row:SetHeight(rowH)
		row:SetPoint('TOPLEFT', 4, -4 - (i - 1) * rowH)
		row:SetPoint('TOPRIGHT', -4, -4 - (i - 1) * rowH)
		row.bg = row:CreateTexture(nil, 'BACKGROUND')
		row.bg:SetAllPoints()
		row.bg:SetColorTexture(1, 1, 1, 0.07)
		row.bg:Hide()
		row.bar = row:CreateTexture(nil, 'ARTWORK')
		row.bar:SetWidth(2)
		row.bar:SetPoint('TOPLEFT', 0, -3)
		row.bar:SetPoint('BOTTOMLEFT', 0, 3)
		row.bar:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
		row.bar:Hide()
		row.label = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
		row.label:SetPoint('TOPLEFT', 10, -4)
		row.label:SetPoint('TOPRIGHT', -8, -4)
		row.label:SetJustifyH('LEFT')
		row.label:SetWordWrap(false)
		row.sub = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
		row.sub:SetPoint('BOTTOMLEFT', 10, 4)
		row.sub:SetPoint('BOTTOMRIGHT', -8, 4)
		row.sub:SetJustifyH('LEFT')
		row.sub:SetWordWrap(false)
		row.sub:SetTextColor(0.55, 0.55, 0.60)
		row:SetScript('OnEnter', function() popupSel = i PaintPopup() end)
		row:SetScript('OnClick', function()
			local e = popupResults[i]
			if e then JumpTo(e) end
		end)
		popupRows[i] = row
	end
	popupFoot = popup:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
	popupFoot:SetPoint('BOTTOMLEFT', 14, 6)
	popupFoot:SetPoint('BOTTOMRIGHT', -8, 6)
	popupFoot:SetJustifyH('LEFT')
	popupFoot:SetWordWrap(false)

	local clickOff = CreateFrame('Frame')
	clickOff:SetScript('OnEvent', function()
		if not popup:IsMouseOver() and not (Search.box and Search.box:IsMouseOver()) then
			popup:Hide()
		end
	end)
	popup:SetScript('OnShow', function() clickOff:RegisterEvent('GLOBAL_MOUSE_DOWN') end)
	-- Hidden for real, as the link popup is: closed with the window it still
	-- counted as shown and came back on the next open with the old results.
	popup:SetScript('OnHide', function(self)
		clickOff:UnregisterEvent('GLOBAL_MOUSE_DOWN')
		self:Hide()
	end)
end

local function ShowResults(results)
	EnsurePopup()
	popupResults = results
	local n = math.min(#results, POP_MAX)
	if n == 0 and not S.running then
		popup:Hide()
		return
	end
	for i, row in ipairs(popupRows) do
		local e = results[i]
		if e then
			row.label:SetText(RowLabel(e))
			row.sub:SetText(Crumb(e))
			row:Show()
		else
			row:Hide()
		end
	end
	if popupSel > n then popupSel = 1 end
	PaintPopup()
	local total = #results
	local count = format('%d match%s', total, total == 1 and '' or 'es')
	local foot
	if S.running then
		foot = (total == 0) and 'Indexing pages...' or (count .. ' so far - indexing pages...')
	elseif total > POP_MAX then
		foot = format('%d of %d matches - keep typing to narrow it down', POP_MAX, total)
	else
		foot = count
	end
	if n > 0 then foot = foot .. '   |cff555555Enter opens - Tab moves down|r' end
	popupFoot:SetText(foot)
	popup:SetHeight(4 + n * popup.rowH + 4 + popup.footH + 8)
	popup:Show()
end

function Search.Run()
	wipe(Search.hits)
	if navFilter == '' then
		if popup then popup:Hide() end
		return
	end
	if not S.done then RunIndexPass() end
	local results = SearchAll(navFilter)
	for _, e in ipairs(results) do Search.hits[e.page] = true end
	ShowResults(results)
end

function Search.Refresh()
	Search.Run()
	RebuildNav()
end

function Search.Typed()
	popupSel = 1
	Search.Refresh()
end

function Search.Next()
	local n = math.min(#popupResults, POP_MAX)
	if n == 0 then return end
	popupSel = (popupSel % n) + 1
	PaintPopup()
end

function Search.Open()
	local e = popupResults[popupSel] or popupResults[1]
	if e then
		JumpTo(e)
	elseif Search.box then
		Search.box:ClearFocus()
	end
end

_G.SLASH_XERIONSEARCH1 = '/xerionsearch'
_G.SlashCmdList.XERIONSEARCH = function(msg)
	if not CONFIG then
		Msg('open the settings window once first (/xerion)')
		return
	end
	msg = Trim(msg or ''):lower()
	local builds = 0
	for _ in pairs(S.builds) do builds = builds + 1 end
	Msg(format('search index: %d entries from %d page builds, pass %s',
		#S.index, builds, S.done and 'done' or (S.running and 'running'
			or (S.jobs and format('stopped at %d of %d', S.at, #S.jobs) or 'not started'))))
	for id, err in pairs(S.errors) do Msg('  build failed: ' .. id .. ' - ' .. err) end
	if msg == '' then return end
	local results = SearchAll(msg)
	Msg(format('"%s": %d matches', msg, #results))
	for i = 1, math.min(15, #results) do
		local e = results[i]
		Msg(format('  %2d. %s  |cff777777[%s]|r', i, Plain(RowLabel(e)), Crumb(e)))
	end
end

end

ShowPage = function(key, keepScroll)
	if not CONFIG or not key then return end
	if not pageBuild[key] then return end
	local prev = 0
	if keepScroll and key == currentPage then
		local ok, v = pcall(scroll.GetVerticalScroll, scroll)
		if ok and type(v) == 'number' then prev = v end
	end
	currentPage = key
	ResetContent()
	content.pageKey = key
	HidePinnedTabs()
	pageBuild[key]()
	Search.Fold(key)
	local h = math.max(10, -content.cy + 20)
	content:SetHeight(h)
	if prev > 0 then
		local okH, viewH = pcall(scroll.GetHeight, scroll)
		local maxScroll = (okH and type(viewH) == 'number') and math.max(0, h - viewH) or 0
		if prev > maxScroll then prev = maxScroll end
	end
	scroll:SetVerticalScroll(prev)
	if scroll.UpdateScrollBar then scroll.UpdateScrollBar() end
	RebuildNav()
end

-- WHY THE SIDEBAR TREE IS NOT INSIDE Build()
--
-- Lua 5.1 lets one function capture 60 outer locals (upvalues), and every PageX
-- builder named in the tree is one of them. With the window's frame code and the
-- whole tree in a single function, the two Co-Tank pages made it 61 and the file
-- stopped compiling: "function at line N has more than 60 upvalues", which the
-- core reports as the settings window failing to load. It is the same kind of
-- ceiling as the 200 locals of the main chunk, and a syntax check does not see
-- this one either - count upvalues per function before deploying a new page.
--
-- So the tree is declared by two functions of its own, about half the sections
-- each, and Build() only calls them. Each stands near 23 of the 60. When one gets
-- close, split it again; do not move pages back into Build(). Section and Page
-- are shared by both, and the do-block keeps all four helpers out of the main
-- chunk's locals.
local Build
do

-- WHY SOME SIDEBAR ROWS HAVE ICONS
-- The user asked for icons to make pages quicker to find, "maybe not to all":
-- the class pages and the features that already have a face in the game (a
-- ready check tick, the Recuperate spell, the augment rune). Pages about the
-- window or about another addon's frames (Appearance, EllesmereUI, Combat,
-- Mythic+) stay text only - an icon picked for them would be decoration, not a
-- cue. One entry per page key; a page with no entry simply has none.
--
-- Each entry is one of:
--   atlas = 'name'           a Blizzard atlas, drawn whole
--   spell = id, tex = file   the spell's own icon, the file as fallback
--   tex = file               a texture path or fileID; cropped like a spell
--                            icon unless whole = true (UI art has no border)
-- Reusing what the modules themselves draw where they have it: the rune file
-- is AugmentRune's RUNE_ICON, Recuperate's fallback is its FALLBACK_ICON, and
-- the Shroud path is the one on its bar.
local NAV_ICONS = {
	class_dk     = { atlas = 'classicon-deathknight' },
	class_veng   = { atlas = 'classicon-demonhunter' },
	class_druid  = { atlas = 'classicon-druid' },
	class_mage   = { atlas = 'classicon-mage' },
	class_brew   = { atlas = 'classicon-monk' },
	class_prot   = { atlas = 'classicon-paladin' },
	class_shaman = { atlas = 'classicon-shaman' },
	class_warrior = { atlas = 'classicon-warrior' },

	readyalerts  = { spell = 2825, tex = 136012 },      -- Bloodlust
	buffwatch    = { spell = 21562, tex = [[Interface\Icons\Spell_Holy_WordFortitude]] },
	augmentrune  = { tex = 4549099 },
	readycheck   = { tex = [[Interface\RaidFrame\ReadyCheck-Ready]], whole = true },
	recup        = { spell = 1231411, tex = 132290 },   -- Recuperate

	externals      = { spell = 6940, tex = [[Interface\Icons\Spell_Holy_SealOfSacrifice]] },
	healerexternal = { spell = 33206, tex = [[Interface\Icons\Spell_Holy_PainSupression]] },
	interrupts     = { spell = 1766, tex = [[Interface\Icons\Ability_Kick]] },
	cotank         = { atlas = 'UI-LFG-RoleIcon-Tank' },
	shroud         = { spell = 114018, tex = [[Interface\Icons\Ability_Rogue_EnvelopingShadows]] },
	targetedspells = { spell = 257284, tex = [[Interface\Icons\Ability_Hunter_SniperShot]] }, -- Hunter's Mark
	raidmarkers    = { tex = [[Interface\TargetingFrame\UI-RaidTargetingIcon_8]], whole = true },
	inspect        = { atlas = 'communities-icon-searchmagnifyingglass' },
	stoneform      = { spell = 20594, tex = 132275 },

}

local function Section(title, items, n)
	local kept, icons = {}, false
	for i = 1, (n or #items) do
		local it = items[i]
		if it then
			kept[#kept + 1] = it
			if it.icon then icons = true end
		end
	end
	if #kept > 0 then navTree[#navTree + 1] = { title = title, items = kept, icons = icons } end
end

-- false, not nil, for a page whose module is not loaded: a nil inside the table
-- constructor leaves a hole, and #items over a table with holes may stop at any
-- of them, so Section would silently drop the pages after it.
--
-- `was` lists the keys this page answered to before it swallowed another page:
-- { oldKey = 'Tab to open' }. Build() turns it into Search.alias, which
-- ns.ShowConfigPage consults, so edit mode, the XerionUI installer and anything
-- else holding an old key still lands on the right tab.
local function Page(cond, key, title, build, was)
	if not cond then return false end
	return { key = key, title = title, build = build, was = was, icon = NAV_ICONS[key] }
end

-- Declared in this block rather than beside the other pages only for the
-- 200-locals ceiling: the main chunk peaks within a few of it, and a page
-- here costs it nothing.
-- These class-specific builders live near the sidebar tree to stay below Lua's
-- upvalue limit; the earlier removed Vendor Search page no longer occupies a
-- slot here.
local function PageShaman()
	local function cfg() return ns.SHMGetCfg() end
	local function apply() ns.SHMApply() end
	AddPinnedTabs('class_shaman', { 'Elemental' },
		{ { spec = 262, tex = [[Interface\Icons\Spell_Nature_Lightning]] } }, 'Elemental')
	AddHeader('Shaman')
	AddHeader('Elemental Blast letters')
	AddCheck('Enable',
		function() return cfg().enable end,
		function(v) cfg().enable = v apply() end)
	AddPreviewToggle(ns.SHMIsPreview, ns.SHMSetPreview)
	AddSlider('Text size', 8, 40, 1,
		function() return cfg().size end,
		function(v) cfg().size = v apply() end)
	AddSlider('Y offset', -40, 40, 1,
		function() return cfg().offsetY end,
		function(v) cfg().offsetY = v apply() end)
	AddColor('Crit (C) colour',
		function() return cfg().critColor end,
		function(c) cfg().critColor = c apply() end)
	AddColor('Haste (H) colour',
		function() return cfg().hasteColor end,
		function(c) cfg().hasteColor = c apply() end)
	AddColor('Mastery (M) colour',
		function() return cfg().masteryColor end,
		function(c) cfg().masteryColor = c apply() end)
end

-- Kept near the sidebar tree to stay below Lua's upvalue limit. One spec button, the way the
-- Monk page has Brewmaster: the Bear Form reminder is Guardian only, and Cheat
-- Death (every spec) sits beside it in the Category dropdown. When another
-- spec gets a feature, give it a button and list Cheat Death under both, the
-- way Control Undead is under Blood and Unholy. The two builders are locals of
-- PageDruid so they cost the main chunk nothing.
local function PageDruid()
	local function PageBearForm()
		local function cfg() return ns.BFRGetCfg() end
		local function get(k) return function() return cfg()[k] end end
		local function set(k) return function(v) cfg()[k] = v ns.BFRApply() end end
		AddHeader('Bear Form reminder')
		AddCheck('Enable', get('enable'), set('enable'),
			'Shows the text while you are in combat as Guardian and not in Bear Form.')
		AddPreviewToggle(ns.BFRIsPreview, ns.BFRSetPreview)
		AddCheck('Lock position', get('lock'), set('lock'),
			'Prevents moving the text with right-drag while previewing.')

		AddHeader('Text')
		AddEditBoxOption('Text', get('text'),
			function(v) v = ns.Trim(v) if v == '' then v = 'BEAR FORM' end cfg().text = v ns.BFRApply() end)
		AddSlider('Text size', 12, 80, 1, get('size'), set('size'))
		AddColor('Colour', get('color'), set('color'))
		AddPosition(get('x'), set('x'), get('y'), set('y'))
	end

	local function PageCheatDeath()
		local function cfg() return ns.WHIGetCfg() end
		local function get(k) return function() return cfg()[k] end end
		local function set(k) return function(v) cfg()[k] = v ns.WHIApply() end end
		AddHeader('Cheat Death - Well-Honed Instincts')
		AddCheck('Enable', get('enable'), set('enable'),
			'Plays a sound when Well-Honed Instincts saves you - the moment its debuff (382912) lands on you. Every spec.')
		AddScrollDropdown('Sound', ns.SoundOptions(cfg().sound),
			get('sound'), set('sound'), ns.PlaySoundByName, ns.PlaySoundByName)
		AddScrollDropdown('Sound when it falls off', ns.SoundOptions(cfg().endSound),
			get('endSound'), set('endSound'), ns.PlaySoundByName, ns.PlaySoundByName)
		AddDropdown('Sound channel',
			{ { value = 'Master', text = 'Master' }, { value = 'Dialog', text = 'Dialog' },
			  { value = 'SFX', text = 'Sound effects' }, { value = 'Ambience', text = 'Ambience' },
			  { value = 'Music', text = 'Music' } },
			get('channel'), set('channel'))
		AddButton('Test', function() ns.WHITest() end, 120)
	end

	AddPinnedTabs('class_druid', { 'Guardian' },
		{ { spec = 104, tex = [[Interface\Icons\Ability_Racial_BearForm]] } }, 'Guardian')
	AddHeader('Druid')
	CategoryPage('class_druid', {
		{ cond = ns.hasBearForm,  text = 'Bear Form',   build = PageBearForm,
			icon = { spell = 5487, tex = [[Interface\Icons\Ability_Racial_BearForm]] } },
		{ cond = ns.hasWellHoned, text = 'Cheat Death', build = PageCheatDeath,
			icon = { spell = 382912 } },
	})
end

-- Kept near the sidebar tree to stay below Lua's upvalue limit. Built like the Druid page
-- minus the spec tabs (Spell Reflection is every spec): the next warrior
-- feature is one more CategoryPage entry, and the dropdown appears by itself
-- once there are two.
local function PageWarrior()
	local function PageReflect()
		local function cfg() return ns.RFLGetCfg() end
		local function get(k) return function() return cfg()[k] end end
		local function set(k) return function(v) cfg()[k] = v ns.RFLApply() end end
		AddHeader('Reflect damage')
		AddCheck('Enable', get('enable'), set('enable'),
			'After you cast Spell Reflection, shows how much damage the spells you reflected did. The damage meter can only be read out of combat, so the number comes when the fight ends. It learns your own spells from fights without a reflect; until it has seen one, it counts only spells that also hit you.')
		AddPreviewToggle(ns.RFLIsPreview, ns.RFLSetPreview)
		AddCheck('Lock position', get('lock'),
			function(v) cfg().lock = v end,
			'Right-drag the text to move it while its Preview is on and this is off.')
		AddSlider('Text size', 10, 48, 1, get('size'), set('size'))
		AddColor('"Reflect:" colour', get('labelColor'), set('labelColor'))
		AddColor('Number colour', get('valueColor'), set('valueColor'))
		AddDropdown('Text layer (strata)', STRATA_OPTIONS, get('strata'), set('strata'))
		AddPosition(get('x'), set('x'), get('y'), set('y'))
	end

	AddHeader('Warrior')
	CategoryPage('class_warrior', {
		{ cond = ns.hasReflect, text = 'Spell Reflection', build = PageReflect,
			icon = { spell = 23920, tex = 132361 } },
	})
end

-- Kept near the sidebar tree to stay below Lua's upvalue limit.
local function PageEUIFocusKick()
	local function cfg() return ns.EFKGetCfg() end
	local function get(k) return function() return cfg()[k] end end
	local function set(k) return function(v) cfg()[k] = v ns.EFKApply() end end
	AddHeader('Kick alert')
	AddCheck('Enable', get('enable'), set('enable'),
		'Speaks when your kick is off cooldown AND your FocusKick unit is casting something you can interrupt: when the cast starts while your kick is ready, or when your kick comes back while the cast is still going. Silent for casts that cannot be interrupted, in keys too.')
	AddEditBoxOption('Text', get('text'), set('text'))
	AddSlider('Volume', 0, 100, 5, get('voiceVolume'), set('voiceVolume'))
	local vopts = { { text = 'Use Blizzard TTS setting', value = '' } }
	local vc = _G.C_VoiceChat
	local voices = vc and vc.GetTtsVoices and vc.GetTtsVoices()
	if voices then
		for _, v in ipairs(voices) do
			if v.name then vopts[#vopts + 1] = { text = v.name, value = v.name } end
		end
	end
	AddDropdown('Voice', vopts, get('voiceName'), set('voiceName'))
	AddButton('Test', function() ns.EFKTest() end, 120)
	if ns.EFKEUISoundOn() then
		AddDesc('EllesmereUI\'s own Focus Cast Sound is on too and plays on every cast. Set it to None in FocusKick\'s options to hear only this one.')
	end
end

local function PageFocusCastbar()
	AddHeader('Focus cast bar background')
	local function cfg() return ns.EUIGetFocusCastbarBgCfg() end
	local function apply() ns.EUIApplyFocusCastbar() end
	AddCheck('Use custom background colour',
		function() return cfg().enable end,
		function(v) cfg().enable = v apply() end,
		'Tints the empty background behind the cast fill. The cast progress colour is unchanged.')
	AddColor('Background colour',
		function() return cfg().color end,
		function(c) cfg().color = c apply() end)
	AddSlider('Background opacity', 0, 1, 0.05,
		function() return cfg().alpha end,
		function(v) cfg().alpha = v apply() end)
end

local function NavTreeTop()
	Section('General', {
		Page(true, 'appearance', 'Appearance', PageAppearance),
		Page(true, 'profiles',   'Profiles',   PageProfiles),

	})
	Section('Misc', {
		Page(ns.hasStoneform, 'stoneform', 'Stoneform', function()
			local function cfg() return ns.SFMGetCfg() end
			local function apply() ns.SFMApply() end
			AddHeader('Stoneform bleed alert')
			AddCheck('Enable', function() return cfg().enable end,
				function(v) cfg().enable = v apply() end,
				'Shows the Stoneform icon while you have a bleed and Stoneform is ready.')
			AddPreviewToggle(ns.SFMIsPreview, ns.SFMSetPreview)
			AddDesc('Right-drag the icon while Preview is active to move it.')
			AddCheck('Lock position', function() return cfg().lock end,
				function(v) cfg().lock = v apply() end)
			AddSlider('Icon size', 16, 120, 1,
				function() return cfg().iconSize end,
				function(v) cfg().iconSize = v apply() end)
			AddColor('Border colour', function() return cfg().borderColor end,
				function(c) cfg().borderColor = c apply() end)
			AddSlider('Border size', 0, 8, 1,
				function() return cfg().borderSize end,
				function(v) cfg().borderSize = v apply() end)
			AddHeader('Bleed alert')
			AddDropdown('Alert type', {
				{ value = 'tts', text = 'Text to Speak' },
				{ value = 'sound', text = 'Sound' },
			},
				function() return cfg().alertMode or 'tts' end,
				function(v) cfg().alertMode = v end)
			if cfg().alertMode == 'sound' then
				AddScrollDropdown('Sound', ns.SoundOptions(cfg().sound),
					function() return cfg().sound or 'None' end,
					function(v) cfg().sound = v end,
					ns.PlaySoundByName, ns.PlaySoundByName)
				AddButton('Test sound', function() ns.PlaySoundByName(cfg().sound) end, 120)
			else
				AddEditBoxOption('Text to speak',
					function() return cfg().ttsText end,
					function(v) cfg().ttsText = v end)
				AddSlider('TTS volume', 0, 100, 5,
					function() return cfg().ttsVolume or 100 end,
					function(v) cfg().ttsVolume = v end)
				local vopts = { { text = 'Use Blizzard TTS setting', value = '' } }
				local vc = _G.C_VoiceChat
				local voices = vc and vc.GetTtsVoices and vc.GetTtsVoices()
				if voices then
					for _, voice in ipairs(voices) do
						if voice.name then vopts[#vopts + 1] = { text = voice.name, value = voice.name } end
					end
				end
				AddDropdown('TTS voice', vopts,
					function() return cfg().ttsVoiceName or '' end,
					function(v) cfg().ttsVoiceName = v end)
				AddButton('Test speech', function() ns.SFMTestAlert() end, 120)
			end
			AddHeader('Glow')
			AddCheck('Enable glow', function() return cfg().glow end,
				function(v) cfg().glow = v apply() end)
			if cfg().glow then
				AddColor('Glow colour', function() return cfg().glowColor end,
					function(c) cfg().glowColor = c apply() end)
				AddDropdown('Glow type', {
					{ value = 'pixel', text = 'Pixel Glow' },
					{ value = 'shape', text = 'Shape Glow' },
					{ value = 'autoshine', text = 'Auto Cast Shine' },
				},
					function() return cfg().glowType end,
					function(v) cfg().glowType = v apply() end)
				AddSlider('Glow thickness / strength', 1, 10, 1,
					function() return cfg().glowThickness end,
					function(v) cfg().glowThickness = v apply() end)
			end
			AddPosition(function() return cfg().x end, function(v) cfg().x = v apply() end,
				function() return cfg().y end, function(v) cfg().y = v apply() end)
		end),
	})
	local euiNP = ns.hasEUINP
		Section('EllesmereUI Tweaks', {
		Page(euiNP,       'eui_np',     'Nameplates', PageNP),
		Page(ns.hasEUIFocusKick, 'eui_focuskick', 'FocusKick Sound', PageEUIFocusKick),
		Page(ns.hasEUI, 'eui_focuscastbar', 'Focus Cast Bar', PageFocusCastbar),
		Page(ns.hasEUIMythicCast, 'eui_tsb', 'Targeted Spell Bars', PageEUISpellBars),
		-- Built inline, not as a PageX local: this block already peaks at 196 of
		-- the 200 locals a Lua 5.1 function may hold.
		Page(ns.hasEUIPartyHealth, 'eui_party', 'Party Frames', function()
			local function cfg() return ns.EPHGetCfg() end
			local function get(k) return function() return cfg()[k] end end
			local function set(k) return function(v) cfg()[k] = v ns.EPHApply() end end
			AddHeader('Health + Shield %')
			AddCheck('Enable', get('enable'), set('enable'))
			AddDropdown('Position', {
					{ value = 'LEFT',   text = 'Left' },
					{ value = 'CENTER', text = 'Centre' },
					{ value = 'RIGHT',  text = 'Right' },
					{ value = 'TOP',    text = 'Top' },
					{ value = 'BOTTOM', text = 'Bottom' },
				},
				get('anchor'), set('anchor'))
			AddSlider('Offset X', -60, 60, 1, get('offX'), set('offX'))
			AddSlider('Offset Y', -30, 30, 1, get('offY'), set('offY'))
			AddSlider('Text size', 6, 30, 1, get('size'), set('size'))
			AddHeader('Colour')
			AddCheck('Colour by value', get('byValue'),
				function(v) cfg().byValue = v ns.EPHApply() ShowPage('eui_party', true) end)
			if cfg().byValue then
				AddColor('Below step 1', get('c1'), set('c1'))
				AddSlider('Step 1', 1, 200, 1, get('t1'), set('t1'))
				AddColor('Step 1 to step 2', get('c2'), set('c2'))
				AddSlider('Step 2', 1, 200, 1, get('t2'), set('t2'))
				AddColor('Step 2 to step 3', get('c3'), set('c3'))
				AddSlider('Step 3', 1, 200, 1, get('t3'), set('t3'))
				AddColor('Step 3 and above', get('c4'), set('c4'))
			else
				AddColor('Text color', get('color'), set('color'))
			end
			AddHeader('Debuff stack placement')
			AddDropdown('Position on each debuff icon', {
					{ value = 'BOTTOMRIGHT', text = 'Bottom right (default)' },
					{ value = 'TOPLEFT', text = 'Top left' },
					{ value = 'TOP', text = 'Top' },
					{ value = 'TOPRIGHT', text = 'Top right' },
				},
				get('debuffStackPlacement'),
				function(v)
					cfg().debuffStackPlacement = v
					ns.EPHApplyDebuffStackPlacement()
				end)
			AddPreviewToggle(ns.EPHStackPreviewIsOn, ns.EPHStackPreviewSet)
			local function setStackOffset(key)
				return function(v)
					cfg()[key] = v
					ns.EPHApplyDebuffStackPlacement()
				end
			end
			AddSlider('Offset X', -40, 40, 1, get('debuffStackOffsetX'), setStackOffset('debuffStackOffsetX'))
			AddSlider('Offset Y', -40, 40, 1, get('debuffStackOffsetY'), setStackOffset('debuffStackOffsetY'))
		end),
		Page(ns.hasEUICore and not (euiNP and ns.hasEUIMythicCast),
		                  'eui_missing', 'What is missing', PageEUIMissing),
	})
end

local function NavTreeBottom()
	-- Everything about the other players in the party or raid.
	Section('Group', {
		Page(ns.hasExternals,      'externals',      'Externals',        PageExternals),
		Page(ns.hasInterrupts,     'interrupts',     'Party Interrupts', PageInterrupts),
		Page(ns.hasCCBars,         'cctracker',      'CC Tracker',       PageCCTracker),
		Page(ns.hasCCCastNotices,  'cccasts',        'CC Cast Notices',  PageCCCastNotices),
		Page(ns.hasBloodlust,      'readyalerts',    'Lust',             PageReadyAlerts),
		Page(ns.hasAggroCheck,     'aggrocheck',     'Aggro Check',      PageAggroCheck),
		Page(ns.hasCoTank,         'cotank',         'Co-Tank',          PageCoTank,
			{ cotank_debuffs = 'Boss Debuffs' }),
		Page(ns.hasShroud,         'shroud',         'Shroud/Invis Bar', PageShroud),
	})
	Section('Class', {
		Page(ns.hasCDMStacks or ns.hasControlUndead or ns.hasBoilingPoint or ns.hasBoneShield or ns.hasBloodIsLife or ns.hasReapersMark or ns.hasBlightfall or ns.hasPutrefy or ns.hasDRWIcon or ns.hasDRWSound,
		                         'class_dk',    '|cffC41E3ADeath Knight|r', PageDeathKnight),
		Page(ns.hasFieryBrand,   'class_veng',  '|cffA330C9Demon Hunter|r', PageFieryBrand),
		Page(ns.hasWellHoned or ns.hasBearForm, 'class_druid', '|cffFF7C0ADruid|r', PageDruid),
		Page(ns.hasMage,         'class_mage',  '|cff3FC7EBMage|r',         PageMage),
		Page(ns.hasBrewmaster,   'class_brew',  '|cff00FF98Monk|r',         PageBrewmaster),
		Page(ns.hasShiningLight or ns.hasPaladinAura, 'class_prot', '|cffF48CBAPaladin|r', PagePaladin),
		Page(ns.hasElementalBlast, 'class_shaman', '|cff0070DDShaman|r',    PageShaman),
		Page(ns.hasReflect,      'class_warrior', '|cffC69B6DWarrior|r',    PageWarrior),
	})
end

-- WHY THE LINK ICONS WORK THIS WAY
-- Small icons, each with its name beside it, sit in the strip at the bottom of
-- the window and point at the author's Twitch, Patreon and website. An addon
-- cannot open a browser - the client has no API for it, on purpose - so the most
-- a click can do is hand the address over: a small box opens above the icons
-- with the URL focused and selected, Ctrl+C takes it, the hint line confirms the
-- copy and the box goes away. A click anywhere outside the box closes it too.
-- EllesmereUI's video guides make the same deal, which is where the OnKeyDown
-- check comes from (it is known to fire on a focused EditBox on 12.1).
--
-- The textures are white glyphs with the shape in the alpha channel only, so
-- SetVertexColor paints them: a dimmed brand colour at rest, the full one on
-- hover. A link whose url is empty is skipped, icon and all.
--
-- It lives here and not in Build() for the upvalue ceiling described above, and
-- inside the do-block so it costs the main chunk no locals. Nothing in it runs
-- at file load - the options addon can be first-loaded in combat.
local LINKS = {
	{
		name = 'Twitch', url = 'https://www.twitch.tv/xeriontank_tv',
		tex = [[Interface\AddOns\XerionUI-Plugin\Media\icon_twitch.tga]],
		color = { 0.57, 0.27, 1.00 },
	},
	{
		name = 'Patreon', url = 'https://www.patreon.com/Kiratank',
		tex = [[Interface\AddOns\XerionUI-Plugin\Media\icon_patreon.tga]],
		color = { 1.00, 0.26, 0.30 },
	},
	-- No brand mark of its own, so a globe in the window's accent orange.
	{
		name = 'Website', url = 'https://xeriontank.com',
		tex = [[Interface\AddOns\XerionUI-Plugin\Media\icon_web.tga]],
		color = ACCENT,
	},
}
local LINK_HINT = 'Ctrl+C to copy, then paste it into your browser'

local linkPopup
local linkButtons = {}
local function ShowLink(link, anchor)
	local f = linkPopup
	if not f then
		f = CreateFrame('Frame', nil, CONFIG, 'BackdropTemplate')
		f:SetFrameStrata('DIALOG')
		f:SetBackdrop({
			bgFile = 'Interface\\Buttons\\WHITE8X8',
			edgeFile = 'Interface\\Buttons\\WHITE8X8',
			edgeSize = 1,
		})
		f:SetBackdropColor(C_BG[1], C_BG[2], C_BG[3], 0.98)
		f:SetBackdropBorderColor(0, 0, 0, 1)
		f:EnableMouse(true)
		-- A click anywhere else closes it, the way the search results do: the
		-- event only watches, so the click still lands on whatever was under it.
		-- The link buttons are left out - their own OnClick toggles the box, and
		-- closing it here on mouse-down would make that same click reopen it.
		f:SetScript('OnEvent', function(self)
			if self:IsMouseOver() then return end
			for _, b in ipairs(linkButtons) do
				if b:IsMouseOver() then return end
			end
			self:Hide()
		end)
		f:SetScript('OnShow', function(self) self:RegisterEvent('GLOBAL_MOUSE_DOWN') end)
		-- A child hidden by its parent still counts as shown and would come back
		-- with the window; hiding it for real makes every open a fresh one.
		f:SetScript('OnHide', function(self)
			self:UnregisterEvent('GLOBAL_MOUSE_DOWN')
			self:Hide()
		end)

		f.title = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
		f.hint = f:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')

		local eb = MakeEditBox(f, 240, 22)
		-- Read-only: typing, paste and cut put the address back and re-select it.
		eb:SetScript('OnTextChanged', function(self, userInput)
			if userInput then
				self:SetText(f.link and f.link.url or '')
				self:HighlightText()
			end
		end)
		eb:SetScript('OnMouseUp', function(self) self:SetFocus() self:HighlightText() end)
		eb:SetScript('OnEscapePressed', function() f:Hide() end)
		eb:SetScript('OnEnterPressed', function() f:Hide() end)
		eb:SetScript('OnKeyDown', function(_, key)
			if key == 'C' and IsControlKeyDown() then
				f.hint:SetText('Copied - paste it into your browser')
				f.hint:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
				-- Not at once: the client does the copy after this handler, and a
				-- box that is already hidden has nothing selected to copy.
				local shown = f.shown
				C_Timer.After(1.2, function()
					if f.shown == shown then f:Hide() end
				end)
			end
		end)
		f.box = eb
		-- A frame is born shown, so the Show() below would be a no-op and OnShow
		-- would never register the click-off event on the first open. Start hidden.
		f:Hide()
		linkPopup = f
	end

	if f:IsShown() and f.link == link then f:Hide() return end
	f.link = link
	f.shown = (f.shown or 0) + 1

	f.title:SetText(link.name)
	f.title:SetTextColor(link.color[1], link.color[2], link.color[3])
	f.hint:SetText(LINK_HINT)
	f.hint:SetTextColor(0.6, 0.6, 0.65)
	f.box:SetText(link.url)

	-- Measured, not assumed: the fonts are not the same on every client.
	local pad = 10
	local boxW = math.max(240, MeasureText(link.url, 'ChatFontNormal') + 16, TextW(f.hint))
	local y = -pad
	f.title:ClearAllPoints()
	f.title:SetPoint('TOPLEFT', pad, y)
	y = y - TextH(f.title, 12) - 6
	f.box:ClearAllPoints()
	f.box:SetPoint('TOPLEFT', pad, y)
	f.box:SetWidth(boxW)
	y = y - 22 - 6
	f.hint:ClearAllPoints()
	f.hint:SetPoint('TOPLEFT', pad, y)
	y = y - TextH(f.hint, 10) - pad
	f:SetSize(boxW + pad * 2, -y)

	f:ClearAllPoints()
	f:SetPoint('BOTTOMLEFT', anchor, 'TOPLEFT', 0, 6)
	f:Show()
	f.box:SetFocus()
	f.box:SetCursorPosition(0)
	f.box:HighlightText()
end

-- The row sits in the strip under the page, level with the version number, and
-- not under the sidebar where it started: the sidebar is 170 wide, and three
-- labelled links only fit in that on a narrow font. Here a fourth fits as well.
local function LinkFooter()
	local prev
	for _, link in ipairs(LINKS) do
		if link.url and link.url ~= '' then
			local b = CreateFrame('Button', nil, CONFIG)
			if prev then
				b:SetPoint('LEFT', prev, 'RIGHT', 14, 0)
			else
				b:SetPoint('BOTTOMLEFT', CONFIG, 'BOTTOMLEFT', 182, 2)
			end
			local icon = b:CreateTexture(nil, 'ARTWORK')
			icon:SetSize(16, 16)
			icon:SetPoint('LEFT', 0, 0)
			icon:SetTexture(link.tex)
			local label = b:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
			label:SetPoint('LEFT', icon, 'RIGHT', 4, 0)
			label:SetText(link.name)
			-- The whole row is the hit box, so its width follows the text.
			b:SetSize(16 + 4 + TextW(label) + 2, 20)
			local c = link.color
			local function Paint(hovered)
				local k = hovered and 1 or 0.7
				icon:SetVertexColor(c[1] * k, c[2] * k, c[3] * k)
				if hovered then label:SetTextColor(1, 1, 1) else label:SetTextColor(0.72, 0.72, 0.76) end
			end
			Paint(false)
			b:SetScript('OnEnter', function() Paint(true) end)
			b:SetScript('OnLeave', function() Paint(false) end)
			b:SetScript('OnClick', function(self) ShowLink(link, self) end)
			Tooltip(b, link.name .. '|nClick for the link.')
			linkButtons[#linkButtons + 1] = b
			prev = b
		end
	end
end

-- The version in the bottom right corner, and left of it a green line once another
-- player's copy has said a newer version exists (XerionUI-Plugin_VersionCheck.lua hears
-- it over the addon channel; an addon cannot ask CurseForge itself). Refreshed on
-- every show, and at once when the news arrives while the window is open.
local function VersionFooter()
	local version = CONFIG:CreateFontString(nil, 'OVERLAY')
	version:SetFont(_G.STANDARD_TEXT_FONT, 9, 'OUTLINE')
	version:SetTextColor(0.80, 0.20, 0.20)
	version:SetPoint('BOTTOMRIGHT', CONFIG, 'BOTTOMRIGHT', -6, 5)
	local addonName = 'XerionUI-Plugin'
	local pluginVersion = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, 'Version'))
		or (GetAddOnMetadata and GetAddOnMetadata(addonName, 'Version'))
		or '?'
	version:SetText('v' .. pluginVersion)

	local update = CONFIG:CreateFontString(nil, 'OVERLAY')
	update:SetFont(_G.STANDARD_TEXT_FONT, 9, 'OUTLINE')
	update:SetTextColor(0.50, 1, 0.50)
	update:SetPoint('BOTTOMRIGHT', version, 'BOTTOMLEFT', -8, 0)

	local function Refresh()
		local latest = ns.PluginLatestHeard and ns.PluginLatestHeard()
		update:SetText(latest and ('Update available: v' .. latest) or '')
	end
	Refresh()
	CONFIG:HookScript('OnShow', Refresh)
	ns.OnPluginLatest = Refresh
end

function Build()
	CONFIG = CreateFrame('Frame', 'KiraPluginConfig', UIParent, 'BackdropTemplate')
	CONFIG:SetSize(720, 520)
	CONFIG:SetPoint('CENTER')
	CONFIG:SetFrameStrata('HIGH')
	CONFIG:SetBackdrop({
		bgFile = 'Interface\\Buttons\\WHITE8X8',
		edgeFile = 'Interface\\Buttons\\WHITE8X8',
		edgeSize = 1,
	})
	CONFIG:SetBackdropColor(C_BG[1], C_BG[2], C_BG[3], 0.97)
	CONFIG:SetBackdropBorderColor(0, 0, 0, 1)
	CONFIG:SetMovable(true)
	CONFIG:EnableMouse(true)
	CONFIG:RegisterForDrag('LeftButton')
	CONFIG:SetScript('OnDragStart', CONFIG.StartMoving)
	CONFIG:SetScript('OnDragStop', CONFIG.StopMovingOrSizing)
	CONFIG:SetClampedToScreen(true)
	tinsert(UISpecialFrames, 'KiraPluginConfig')

	-- PREVIEWS END WITH THE WINDOW
	-- A preview left on after the window closed kept running until /reload,
	-- and several modules stop their real tracking while their preview is up
	-- (Interrupts and Healer External return early from every event), so a
	-- forgotten preview meant a dead feature in the next key. Closing the
	-- window (X, ESC, /xerion) now ends every preview switched from it. Not while
	-- move mode is on: it runs the previews itself and ends them in
	-- EditModeFinish, and ESC can close this window while move mode still waits
	-- on its Save/Discard box.
	-- EditModeFinish calls this too: a window closed while move mode was on
	-- skipped it here, and move mode only ends the previews of the modules it
	-- moves, so the rest ended when move mode did or not at all.
	CONFIG.__kiraPreviews = {}
	function ns.EndWindowPreviews()
		if CONFIG:IsShown() then return end
		for key, stop in pairs(CONFIG.__kiraPreviews) do
			pcall(stop)
			CONFIG.__kiraPreviews[key] = nil
		end
	end
	CONFIG:HookScript('OnHide', function()
		if ns.EditModeActive and ns.EditModeActive() then return end
		ns.EndWindowPreviews()
	end)

	local titleBar = CONFIG:CreateTexture(nil, 'ARTWORK')
	titleBar:SetColorTexture(0.09, 0.09, 0.105, 1)
	titleBar:SetPoint('TOPLEFT', 1, -1)
	titleBar:SetPoint('TOPRIGHT', -1, -1)
	titleBar:SetHeight(34)

	local accentLine = CONFIG:CreateTexture(nil, 'ARTWORK')
	accentLine:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
	accentLine:SetPoint('TOPLEFT', 1, -35)
	accentLine:SetPoint('TOPRIGHT', -1, -35)
	accentLine:SetHeight(1)

	local title = CONFIG:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
	title:SetPoint('TOPLEFT', 14, -9)
	title:SetText('|cffff7d0aXerionUI|r - QoL')

	-- The close cross is drawn from two turned bars, sized to the button,
	-- instead of a letter X in the small body font.
	local close = MakeFlatButton(CONFIG, '', 26, 26)
	close:SetPoint('TOPRIGHT', -5, -4)
	close:SetScript('OnClick', function() CONFIG:Hide() end)
	do
		local bars = {}
		for i2, deg in ipairs({ 45, -45 }) do
			local bar = close:CreateTexture(nil, 'OVERLAY')
			bar:SetColorTexture(0.85, 0.85, 0.85, 1)
			bar:SetSize(16, 2)
			bar:SetPoint('CENTER')
			bar:SetRotation(math.rad(deg))
			bars[i2] = bar
		end
		local function PaintCross(r, g, b)
			for _, bar in ipairs(bars) do bar:SetColorTexture(r, g, b, 1) end
		end
		close:HookScript('OnEnter', function() PaintCross(ACCENT[1], ACCENT[2], ACCENT[3]) end)
		close:HookScript('OnLeave', function() PaintCross(0.85, 0.85, 0.85) end)
	end

	-- EDIT MODE BUTTON
	-- A named button beside the cross, not an icon: the four-arrow square it
	-- replaced said nothing until hovered. It rests orange while edit mode is
	-- on. Edit mode also ends away from this button (its own panel's Done or
	-- ESC, the Save/Discard box, entering combat), so the edit mode file calls
	-- ns.OnEditModeChanged on every start and finish to repaint it.
	if ns.hasEditMode then
		local labelW = MeasureText('Edit Mode')
		local edit = MakeFlatButton(CONFIG, 'Edit Mode', math.max(96, RoundN(labelW) + 28), 24)
		edit:SetPoint('RIGHT', close, 'LEFT', -10, 0)
		local function PaintRest(self)
			if ns.EditModeActive and ns.EditModeActive() then
				self.__bg:SetColorTexture(ACCENT[1] * 0.45, ACCENT[2] * 0.45, ACCENT[3] * 0.45, 1)
				self.__border:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.85)
			else
				self.__bg:SetColorTexture(C_PANEL[1], C_PANEL[2], C_PANEL[3], 1)
				self.__border:SetColorTexture(0, 0, 0, 1)
			end
		end
		edit:SetScript('OnLeave', PaintRest)
		edit:SetScript('OnClick', function(self)
			if ns.EditModeToggle then ns.EditModeToggle() end
			PaintRest(self)
		end)
		edit:HookScript('OnShow', PaintRest)
		ns.OnEditModeChanged = function() PaintRest(edit) end
		PaintRest(edit)
		Tooltip(edit, 'Edit Mode|nDrag every enabled XerionUI element at once. Left-click selects, arrow keys nudge, right-click opens that element\'s settings.')
	end

	local navBG = CONFIG:CreateTexture(nil, 'BACKGROUND')
	navBG:SetColorTexture(0, 0, 0, 0.45)
	navBG:SetPoint('TOPLEFT', 1, -36)
	navBG:SetPoint('BOTTOMLEFT', 1, 1)
	navBG:SetWidth(170)

	local navSep = CONFIG:CreateTexture(nil, 'ARTWORK')
	navSep:SetColorTexture(0, 0, 0, 1)
	navSep:SetWidth(1)
	navSep:SetPoint('TOPLEFT', 171, -36)
	navSep:SetPoint('BOTTOMLEFT', 171, 1)

	local navSearch = MakeEditBox(CONFIG, 150, 20)
	Search.box = navSearch
	navSearch:SetPoint('TOPLEFT', 11, -44)
	navSearch:SetTextInsets(5, 18, 0, 0)
	navSearch.placeholder = navSearch:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
	navSearch.placeholder:SetPoint('LEFT', 5, 0)
	navSearch.placeholder:SetText('Search...')

	local navClear = CreateFrame('Button', nil, navSearch)
	navClear:SetSize(16, 16)
	navClear:SetPoint('RIGHT', -2, 0)
	navClear.label = navClear:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
	navClear.label:SetPoint('CENTER', 0, 0)
	navClear.label:SetText('x')
	navClear.label:SetTextColor(0.6, 0.6, 0.65)
	navClear:SetScript('OnEnter', function(self)
		self.label:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
	end)
	navClear:SetScript('OnLeave', function(self)
		self.label:SetTextColor(0.6, 0.6, 0.65)
	end)
	navClear:SetScript('OnClick', function()
		navSearch:SetText('')
		navSearch:ClearFocus()
	end)
	navClear:Hide()

	navSearch:HookScript('OnTextChanged', function(self)
		local t = self:GetText() or ''
		self.placeholder:SetShown(t == '')
		navClear:SetShown(t ~= '')
		navFilter = Trim(t:lower())
		Search.words = {}
		for w in navFilter:gmatch('%S+') do Search.words[#Search.words + 1] = w end
		Search.Typed()
		if navContent then
			local sf = navContent:GetParent()
			if sf and sf.SetVerticalScroll then
				sf:SetVerticalScroll(0)
				if sf.UpdateScrollBar then sf.UpdateScrollBar() end
			end
		end
	end)
	navSearch:SetScript('OnEscapePressed', function(self)
		self:SetText('')
		self:ClearFocus()
	end)
	navSearch:SetScript('OnEnterPressed', Search.Open)
	navSearch:SetScript('OnTabPressed', Search.Next)
	navSearch:HookScript('OnEditFocusGained', function()
		if navFilter ~= '' then Search.Run() end
	end)

	local navScroll = CreateFrame('ScrollFrame', nil, CONFIG)
	navScroll:SetPoint('TOPLEFT', 1, -70)
	navScroll:SetPoint('BOTTOMLEFT', 1, 22)
	navScroll:SetWidth(169)
	navScroll:EnableMouseWheel(true)
	navScroll:SetScript('OnMouseWheel', function(self, delta)
		local maxScroll = self:GetVerticalScrollRange()
		local new = self:GetVerticalScroll() - delta * 40
		if new < 0 then new = 0 elseif new > maxScroll then new = maxScroll end
		self:SetVerticalScroll(new)
	end)
	navContent = CreateFrame('Frame', nil, navScroll)
	navContent:SetSize(169, 10)
	navScroll:SetScrollChild(navContent)
	AttachScrollBar(navScroll, 2)

	navTree = {}
	NavTreeTop()
	NavTreeBottom()

	pageBuild = {}
	Search.pages = {}
	Search.alias = {}
	for _, sec in ipairs(navTree) do
		for _, it in ipairs(sec.items) do
			pageBuild[it.key] = it.build
			for old, tab in pairs(it.was or {}) do
				Search.alias[old] = { key = it.key, tab = tab }
			end
			local title = Plain(it.title)
			local keys = Search.KEYWORDS[it.key] or ''
			Search.pages[it.key] = {
				title = title, section = sec.title, low = title:lower(), keys = keys,
				hay = (sec.title .. ' ' .. title .. ' ' .. keys):lower(),
			}
		end
	end

	VersionFooter()
	LinkFooter()

	scroll = CreateFrame('ScrollFrame', 'XerionUIQoLConfigScroll', CONFIG)
	scroll:SetPoint('TOPLEFT', 180, -42)
	scroll:SetPoint('BOTTOMRIGHT', -22, 24)
	scroll:EnableMouseWheel(true)
	scroll:SetScript('OnMouseWheel', function(self, delta)
		local range = self:GetVerticalScrollRange()
		local new = self:GetVerticalScroll() - delta * 40
		if new < 0 then new = 0 elseif new > range then new = range end
		self:SetVerticalScroll(new)
	end)
	content = CreateFrame('Frame', nil, scroll)
	content:SetSize(500, 10)
	content.widgets = {}
	content.cy = -14
	scroll:SetScrollChild(content)
	AttachScrollBar(scroll, 6)
end

end

ns.ShowConfigPage = function(key)
	if not CONFIG then Build() end
	CONFIG:Show()
	-- A key from before two pages became tabs of one ('potion', 'cotank_debuffs')
	-- opens the page that took it over, on the tab that holds its settings.
	local alias = key and Search.alias[key]
	if alias then
		key = alias.key
		subTab[key] = alias.tab
	end
	-- Someone asked for this page by name (a module's "open my settings" button),
	-- so unfold its section - landing on a page the sidebar does not list reads
	-- as a bug. Called with no key it is just "show the window", which must not
	-- expand anything, or sections would never stay closed across a session.
	local pageInfo = key and Search.pages[key]
	if pageInfo then NavSecSetOpen(pageInfo.section, true) end
	ShowPage(key or currentPage or FirstLeafKey())
end

ns.ShowConfigSubTab = function(key, tabName)
	if tabName then subTab[key] = tabName end
	ns.ShowConfigPage(key)
end

ns.ToggleConfig = function()
	if CONFIG and CONFIG:IsShown() then CONFIG:Hide() return false end
	ns.OpenConfig()
	return true
end

ns.OpenConfig = function()
	if not CONFIG then Build() end
	CONFIG:Show()
	ShowPage(currentPage or FirstLeafKey())
end
