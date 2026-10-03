--------------------------------------------------------------------------------
-- XerionUI_Options - Controls.lua
-- The option controls. Each is built from a descriptor:
--     { type = "toggle", label = "Show timer", path = "timer.enabled", tip = "..." }
-- and bound to a context (Page.lua) that knows which table `path` points
-- into. Every control has:
--     control:Refresh()          re-read its value and enabled state
--     control.height             its fixed height in the layout grid
-- Width comes from the layout.
--------------------------------------------------------------------------------
local XUI = _G.XerionUI
local O = XUI and XUI.Options
if not O then return end

local GetPath, SetPath = XUI.GetPath, XUI.SetPath
local floor, max, min = math.floor, math.max, math.min

O.Controls = {}
local Controls = O.Controls

local LABEL_H = 16
local FIELD_H = 24

--------------------------------------------------------------------------------
-- Binding
--------------------------------------------------------------------------------
function O:GetValue(desc, ctx)
	if desc.get then return desc.get(ctx) end
	if desc.path then return GetPath(ctx:Root(), desc.path) end
end

function O:SetValue(desc, ctx, value)
	if desc.set then
		desc.set(ctx, value)
	elseif desc.path then
		SetPath(ctx:Root(), desc.path, value)
	end
	ctx:Changed(desc.path, value, desc)
end

local function IsDisabled(desc, ctx)
	if desc.disabled == nil then return false end
	if type(desc.disabled) == "function" then return desc.disabled(ctx) and true or false end
	return desc.disabled and true or false
end
O.IsDisabled = IsDisabled

local function Resolve(v, ctx)
	if type(v) == "function" then return v(ctx) end
	return v
end
O.ResolveValue = Resolve

local function Base(parent, desc, ctx, height)
	local f = CreateFrame("Frame", nil, parent)
	f.desc, f.ctx, f.height = desc, ctx, height
	f:SetHeight(height)
	return f
end

local function Label(f, text)
	local fs = O:Text(f, O.SIZE.small, "label")
	fs:SetText(Resolve(text, f.ctx) or "")
	return fs
end

local function AddTooltip(f, desc)
	if desc.tip then O:Tooltip(f, Resolve(desc.label, f.ctx), desc.tip) end
end

--------------------------------------------------------------------------------
-- Toggle: [switch] Label
--------------------------------------------------------------------------------
local function Switch(parent)
	local s = CreateFrame("Frame", nil, parent)
	s:SetSize(30, 16)
	local l = O:Icon(s, "circle", 16, nil, "BACKGROUND")
	l:SetPoint("LEFT")
	local r = O:Icon(s, "circle", 16, nil, "BACKGROUND")
	r:SetPoint("RIGHT")
	local mid = O:Rect(s, nil, "BACKGROUND")
	mid:SetPoint("TOPLEFT", 8, 0)
	mid:SetPoint("BOTTOMRIGHT", -8, 0)
	s.parts = { l, r, mid }
	s.knob = O:Icon(s, "circle", 12, nil, "ARTWORK")
	function s:SetState(on, disabled)
		local cr, cg, cb = O:Color("track")
		if on then cr, cg, cb = O:Accent() end
		local a = disabled and 0.45 or 1
		for _, p in ipairs(self.parts) do p:SetVertexColor(cr, cg, cb, a) end
		self.knob:ClearAllPoints()
		if on then
			self.knob:SetPoint("RIGHT", -2, 0)
			self.knob:SetVertexColor(1, 1, 1, a)
		else
			self.knob:SetPoint("LEFT", 2, 0)
			self.knob:SetVertexColor(0.72, 0.72, 0.72, a)
		end
	end
	return s
end
O.Switch = Switch

function Controls.toggle(parent, desc, ctx)
	local f = Base(parent, desc, ctx, 24)
	local btn = CreateFrame("Button", nil, f)
	btn:SetPoint("TOPLEFT")
	btn:SetPoint("BOTTOMRIGHT")
	f.switch = Switch(btn)
	f.switch:SetPoint("LEFT", 0, 0)
	f.label = O:Text(btn, O.SIZE.text, "label")
	f.label:SetPoint("LEFT", f.switch, "RIGHT", 8, 0)
	f.label:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
	f.label:SetText(Resolve(desc.label, ctx) or "")
	btn:SetScript("OnClick", function()
		if f.disabled then return end
		O:SetValue(desc, ctx, not f.value)
	end)
	btn:SetScript("OnEnter", function() if not f.disabled then f.label:SetTextColor(O:Color("text")) end end)
	btn:SetScript("OnLeave", function() f:Refresh() end)
	AddTooltip(btn, desc)
	function f:Refresh()
		self.value = O:GetValue(desc, ctx) and true or false
		self.disabled = IsDisabled(desc, ctx)
		self.switch:SetState(self.value, self.disabled)
		self.label:SetTextColor(O:Color(self.disabled and "faint" or "label"))
	end
	return f
end

--------------------------------------------------------------------------------
-- Slider: Label ............ [value]
--         ======O------------
--------------------------------------------------------------------------------
local function FormatNumber(v, step)
	if step and step < 1 then
		local decimals = step < 0.1 and 2 or 1
		return ("%." .. decimals .. "f"):format(v)
	end
	return tostring(floor(v + 0.5))
end

local function Snap(v, desc)
	local step = desc.step or 1
	v = floor((v - desc.min) / step + 0.5) * step + desc.min
	v = max(desc.min, min(desc.max, v))
	if step >= 1 then v = floor(v + 0.5) end
	return v
end

function Controls.slider(parent, desc, ctx)
	local f = Base(parent, desc, ctx, LABEL_H + 22)
	f.label = Label(f, desc.label)
	f.label:SetPoint("TOPLEFT")

	local box = CreateFrame("EditBox", nil, f)
	box:SetSize(46, 16)
	box:SetPoint("TOPRIGHT", 0, 1)
	box:SetAutoFocus(false)
	box:SetFont(O:FontPath(), O.SIZE.small, "")
	box:SetTextColor(O:Color("text"))
	box:SetJustifyH("RIGHT")
	box:SetTextInsets(0, 2, 0, 0)
	f.box = box
	f.label:SetPoint("RIGHT", box, "LEFT", -6, 0)

	local s = CreateFrame("Slider", nil, f)
	s:SetOrientation("HORIZONTAL")
	s:SetPoint("BOTTOMLEFT", 0, 0)
	s:SetPoint("BOTTOMRIGHT", 0, 0)
	s:SetHeight(16)
	s:SetHitRectInsets(0, 0, -4, -4)
	s:SetMinMaxValues(desc.min, desc.max)
	s:SetValueStep(desc.step or 1)
	s:SetObeyStepOnDrag(true)
	local thumb = s:CreateTexture(nil, "OVERLAY")
	thumb:SetTexture(O.MEDIA .. "circle")
	thumb:SetSize(12, 12)
	s:SetThumbTexture(thumb)
	f.thumb = thumb
	local track = O:Rect(s, "track", "BACKGROUND")
	track:SetHeight(4)
	track:SetPoint("LEFT", 0, 0)
	track:SetPoint("RIGHT", 0, 0)
	local fill = O:Rect(s, nil, "ARTWORK")
	fill:SetHeight(4)
	fill:SetPoint("LEFT", track, "LEFT")
	fill:SetPoint("RIGHT", thumb, "CENTER")
	f.fill, f.slider = fill, s

	s:SetScript("OnValueChanged", function(_, v, userInput)
		if not userInput or f.updating then return end
		v = Snap(v, desc)
		box:SetText(FormatNumber(v, desc.step))
		if v ~= f.value then
			f.value = v
			O:SetValue(desc, ctx, v)
		end
	end)
	s:SetScript("OnMouseUp", function() f:Refresh() end)
	-- the page scrolls on the wheel; a slider must not steal it
	s:EnableMouseWheel(false)

	local function Commit()
		local text = (box:GetText() or ""):gsub(",", ".")
		local v = tonumber(text)
		if v and not f.disabled then
			-- typed values may go past the slider's soft range when desc.softMax/softMin allow it
			local lo, hi = desc.softMin or desc.min, desc.softMax or desc.max
			local step = desc.step or 1
			v = floor((v - lo) / step + 0.5) * step + lo
			v = max(lo, min(hi, v))
			if step >= 1 then v = floor(v + 0.5) end
			f.value = v
			O:SetValue(desc, ctx, v)
		end
		box:ClearFocus()
		f:Refresh()
	end
	box:SetScript("OnEnterPressed", Commit)
	box:SetScript("OnEscapePressed", function() box:ClearFocus() f:Refresh() end)
	box:SetScript("OnEditFocusLost", function() f:Refresh() end)
	AddTooltip(s, desc)

	function f:Refresh()
		local v = tonumber(O:GetValue(desc, ctx)) or desc.min
		self.value = v
		self.disabled = IsDisabled(desc, ctx)
		self.updating = true
		s:SetValue(max(desc.min, min(desc.max, v)))
		self.updating = false
		if not box:HasFocus() then box:SetText(FormatNumber(v, desc.step)) end
		s:EnableMouse(not self.disabled)
		box:EnableMouse(not self.disabled)
		local a = self.disabled and 0.4 or 1
		local r, g, b = O:Accent()
		fill:SetVertexColor(r, g, b, a)
		thumb:SetVertexColor(1, 1, 1, a)
		self.label:SetTextColor(O:Color(self.disabled and "faint" or "label"))
		box:SetTextColor(O:Color(self.disabled and "faint" or "text"))
	end
	return f
end

--------------------------------------------------------------------------------
-- Dropdown: Label
--           [ value               v ]
-- values: list of { value = x, text = "..." } or a function(ctx) returning one.
-- desc.media = "font" | "statusbar" | "sound" | "border" | "background" lists
-- LibSharedMedia names and previews them in the list.
--------------------------------------------------------------------------------
local function Field(f)
	local b = CreateFrame("Button", nil, f)
	b:SetHeight(FIELD_H)
	O:Skin(b, "control", "controlLine")
	b.text = O:Text(b, O.SIZE.text, "text")
	b.text:SetPoint("LEFT", 8, 0)
	b.text:SetPoint("RIGHT", -24, 0)
	b.arrow = O:Icon(b, "chevron", 12, "muted")
	b.arrow:SetPoint("RIGHT", -7, 0)
	b:SetScript("OnEnter", function(self)
		if f.disabled then return end
		O:SetSkinColor(self, "controlHover")
	end)
	b:SetScript("OnLeave", function(self) O:SetSkinColor(self, "control") end)
	return b
end

function O:DropdownValues(desc, ctx)
	if desc.media then
		local list = {}
		if desc.media == "border" then
			for _, v in ipairs(XUI.Style.BORDER_STYLES) do list[#list + 1] = v end
		end
		if desc.media == "sound" then
			list[#list + 1] = { value = "", text = "None" }
			if not desc.filesOnly then
				for _, s in ipairs(XUI.Audio.GAME_SOUNDS) do list[#list + 1] = { value = s.name, text = s.name } end
			end
		end
		for _, name in ipairs(XUI.Media:List(desc.media)) do
			if not (desc.media == "border" and (name == "None" or name == "Xerion Pixel")) then
				list[#list + 1] = { value = name, text = name }
			end
		end
		return list
	end
	return Resolve(desc.values, ctx) or {}
end

-- The label of `value`; a media name that is not registered (an uninstalled
-- SharedMedia pack) says so instead of silently showing the fallback.
local function TextFor(values, value, isMedia)
	for _, v in ipairs(values) do
		if v.value == value then return v.text end
	end
	if value == nil or value == "" then return "None" end
	if isMedia then return tostring(value) .. "  |cff888888(not installed)|r" end
	return tostring(value)
end

function Controls.dropdown(parent, desc, ctx)
	local f = Base(parent, desc, ctx, LABEL_H + FIELD_H + 2)
	f.label = Label(f, desc.label)
	f.label:SetPoint("TOPLEFT")
	f.label:SetPoint("TOPRIGHT")
	f.field = Field(f)
	f.field:SetPoint("BOTTOMLEFT")
	f.field:SetPoint("BOTTOMRIGHT")
	f.field:SetScript("OnClick", function(self)
		if f.disabled then return end
		O:OpenDropdown(self, desc, ctx, f.value, function(v)
			O:SetValue(desc, ctx, v)
		end)
	end)
	AddTooltip(f.field, desc)
	function f:Refresh()
		self.value = O:GetValue(desc, ctx)
		self.disabled = IsDisabled(desc, ctx)
		local text = TextFor(O:DropdownValues(desc, ctx), self.value, desc.media ~= nil)
		self.field.text:SetText(text)
		if desc.media == "font" and self.value then
			self.field.text:SetFont(XUI.Media:Fetch("font", self.value), O.SIZE.text, "")
		end
		self.field.text:SetTextColor(O:Color(self.disabled and "faint" or "text"))
		self.field.arrow:SetAlpha(self.disabled and 0.4 or 1)
		self.label:SetTextColor(O:Color(self.disabled and "faint" or "label"))
	end
	return f
end

--------------------------------------------------------------------------------
-- Color: [swatch] Label
--------------------------------------------------------------------------------
local function OpenColorPicker(color, hasAlpha, onChange)
	local r, g, b, a = XUI.UnpackColor(color)
	local function Read()
		local nr, ng, nb = ColorPickerFrame:GetColorRGB()
		local na = hasAlpha and ColorPickerFrame:GetColorAlpha() or 1
		return { nr, ng, nb, na }
	end
	ColorPickerFrame:SetupColorPickerAndShow({
		r = r, g = g, b = b,
		opacity = a,
		hasOpacity = hasAlpha,
		swatchFunc = function() onChange(Read()) end,
		opacityFunc = function() onChange(Read()) end,
		cancelFunc = function() onChange({ r, g, b, a }) end,
	})
end

function Controls.color(parent, desc, ctx)
	local f = Base(parent, desc, ctx, 24)
	local btn = CreateFrame("Button", nil, f)
	btn:SetAllPoints()
	local sw = CreateFrame("Frame", nil, btn)
	sw:SetSize(30, 16)
	sw:SetPoint("LEFT")
	O:Skin(sw, "control", "controlLine")
	f.swatch = O:Rect(sw, nil, "ARTWORK")
	f.swatch:SetPoint("TOPLEFT", 2, -2)
	f.swatch:SetPoint("BOTTOMRIGHT", -2, 2)
	f.label = O:Text(btn, O.SIZE.text, "label")
	f.label:SetPoint("LEFT", sw, "RIGHT", 8, 0)
	f.label:SetPoint("RIGHT")
	f.label:SetText(Resolve(desc.label, ctx) or "")
	btn:SetScript("OnClick", function()
		if f.disabled then return end
		OpenColorPicker(O:GetValue(desc, ctx), desc.hasAlpha ~= false, function(c)
			O:SetValue(desc, ctx, c)
			f:Refresh()
		end)
	end)
	btn:SetScript("OnEnter", function() if not f.disabled then f.label:SetTextColor(O:Color("text")) end end)
	btn:SetScript("OnLeave", function() f:Refresh() end)
	AddTooltip(btn, desc)
	function f:Refresh()
		self.disabled = IsDisabled(desc, ctx)
		local r, g, b, a = XUI.UnpackColor(O:GetValue(desc, ctx))
		self.swatch:SetVertexColor(r, g, b, self.disabled and 0.35 or a)
		self.label:SetTextColor(O:Color(self.disabled and "faint" or "label"))
	end
	return f
end

--------------------------------------------------------------------------------
-- Input: Label / [ text ]   (desc.multiline = height for a text area)
--------------------------------------------------------------------------------
function Controls.input(parent, desc, ctx)
	local multiline = desc.multiline
	local f = Base(parent, desc, ctx, LABEL_H + (multiline or FIELD_H) + 2)
	f.label = Label(f, desc.label)
	f.label:SetPoint("TOPLEFT")

	local holder = CreateFrame("Frame", nil, f)
	holder:SetPoint("TOPLEFT", 0, -LABEL_H - 2)
	holder:SetPoint("BOTTOMRIGHT")
	O:Skin(holder, "control", "controlLine")

	local box
	if multiline then
		local sf = CreateFrame("ScrollFrame", nil, holder, "ScrollFrameTemplate")
		sf:SetPoint("TOPLEFT", 6, -6)
		sf:SetPoint("BOTTOMRIGHT", -24, 6)
		box = CreateFrame("EditBox", nil, sf)
		box:SetMultiLine(true)
		box:SetWidth(200)
		sf:SetScrollChild(box)
		sf:SetScript("OnSizeChanged", function(_, w) box:SetWidth(w) end)
		holder:EnableMouse(true)
		holder:SetScript("OnMouseDown", function() box:SetFocus() end)
	else
		box = CreateFrame("EditBox", nil, holder)
		box:SetPoint("TOPLEFT", 8, 0)
		box:SetPoint("BOTTOMRIGHT", -8, 0)
	end
	box:SetAutoFocus(false)
	box:SetFont(O:FontPath(), O.SIZE.text, "")
	box:SetTextColor(O:Color("text"))
	f.box = box

	local function Commit()
		if f.disabled or desc.readOnly then return end
		local text = box:GetText() or ""
		if text ~= (f.value or "") then
			f.value = text
			O:SetValue(desc, ctx, text)
		end
	end
	if not multiline then
		box:SetScript("OnEnterPressed", function() Commit() box:ClearFocus() end)
	end
	box:SetScript("OnEscapePressed", function() box:ClearFocus() end)
	box:SetScript("OnEditFocusLost", function()
		if not desc.commitOnEnterOnly then Commit() end
		f:Refresh()
	end)
	box:SetScript("OnEditFocusGained", function()
		local r, g, b = O:Accent()
		O:SetBorderColor(holder, r, g, b, 1)
		if desc.selectAll then box:HighlightText() end
	end)
	box:HookScript("OnEditFocusLost", function() O:SetBorderColor(holder, O:Color("controlLine")) end)
	AddTooltip(holder, desc)

	function f:Refresh()
		self.disabled = IsDisabled(desc, ctx)
		self.value = O:GetValue(desc, ctx)
		if not box:HasFocus() then box:SetText(self.value or "") end
		box:EnableMouse(not self.disabled)
		box:SetTextColor(O:Color(self.disabled and "faint" or "text"))
		self.label:SetTextColor(O:Color(self.disabled and "faint" or "label"))
	end
	return f
end

--------------------------------------------------------------------------------
-- Button
--------------------------------------------------------------------------------
function Controls.button(parent, desc, ctx)
	local f = Base(parent, desc, ctx, FIELD_H)
	f.button = O:Button(f, Resolve(desc.text or desc.label, ctx), 100, function()
		if desc.onClick then desc.onClick(ctx, f) end
		if f.page then f.page:Refresh() end
	end, desc.primary)
	f.button:SetPoint("TOPLEFT")
	f.button:SetPoint("BOTTOMRIGHT")
	AddTooltip(f.button, desc)
	function f:Refresh()
		self.disabled = IsDisabled(desc, ctx)
		self.button.text:SetText(Resolve(desc.text or desc.label, ctx) or "")
		self.button:SetDisabled(self.disabled)
	end
	return f
end

--------------------------------------------------------------------------------
-- Description: wrapped muted text spanning its cell
--------------------------------------------------------------------------------
function Controls.description(parent, desc, ctx)
	local f = Base(parent, desc, ctx, 16)
	f.text = O:Text(f, desc.size or O.SIZE.small, desc.color or "muted")
	f.text:SetPoint("TOPLEFT")
	f.text:SetPoint("TOPRIGHT")
	f.text:SetWordWrap(true)
	f.text:SetJustifyV("TOP")
	f.text:SetSpacing(2)
	function f:Refresh()
		self.text:SetText(Resolve(desc.text, ctx) or "")
	end
	-- height follows the wrapped text once the layout gave it a width
	function f:Measure()
		self.height = max(14, (self.text:GetStringHeight() or 14) + 2)
		self:SetHeight(self.height)
		return self.height
	end
	return f
end

--------------------------------------------------------------------------------
-- Tabs: a row of labels, one active (desc.values = { { value, text } })
--------------------------------------------------------------------------------
function Controls.tabs(parent, desc, ctx)
	local f = Base(parent, desc, ctx, 30)
	f.buttons = {}
	f.line = O:Rect(f, "line", "BACKGROUND")
	f.line:SetHeight(1)
	f.line:SetPoint("BOTTOMLEFT")
	f.line:SetPoint("BOTTOMRIGHT")
	local function Button(i)
		local b = f.buttons[i]
		if b then return b end
		b = CreateFrame("Button", nil, f)
		b:SetHeight(30)
		b.text = O:Text(b, O.SIZE.text, "label")
		b.text:SetPoint("CENTER", 0, 1)
		b.under = O:Rect(b, nil, "ARTWORK")
		b.under:SetHeight(2)
		b.under:SetPoint("BOTTOMLEFT")
		b.under:SetPoint("BOTTOMRIGHT")
		b:SetScript("OnClick", function(self) O:SetValue(desc, ctx, self.value) end)
		f.buttons[i] = b
		return b
	end
	function f:Refresh()
		local values = O:DropdownValues(desc, ctx)
		local current = O:GetValue(desc, ctx)
		local x = 0
		for i, v in ipairs(values) do
			local b = Button(i)
			b.value = v.value
			b.text:SetText(v.text)
			local w = (b.text:GetStringWidth() or 40) + 28
			b:SetWidth(w)
			b:ClearAllPoints()
			b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 0)
			x = x + w
			local active = v.value == current
			b.under:SetShown(active)
			if active then b.under:SetVertexColor(O:Accent()) end
			b.text:SetTextColor(O:Color(active and "text" or "muted"))
			b:Show()
		end
		for i = #values + 1, #f.buttons do f.buttons[i]:Hide() end
	end
	return f
end

--------------------------------------------------------------------------------
-- Subheading inside a card
--------------------------------------------------------------------------------
function Controls.heading(parent, desc, ctx)
	local f = Base(parent, desc, ctx, 22)
	f.text = O:Text(f, O.SIZE.small, "muted")
	f.text:SetPoint("BOTTOMLEFT", 0, 4)
	f.text:SetText((Resolve(desc.label, ctx) or ""):upper())
	f.line = O:Rect(f, "line", "ARTWORK")
	f.line:SetHeight(1)
	f.line:SetPoint("BOTTOMLEFT")
	f.line:SetPoint("BOTTOMRIGHT")
	function f:Refresh() end
	return f
end

--------------------------------------------------------------------------------
-- Spacer: an empty cell, to end a row early.
--------------------------------------------------------------------------------
function Controls.spacer(parent, desc, ctx)
	local f = Base(parent, desc, ctx, desc.height or 1)
	function f:Refresh() end
	return f
end

--------------------------------------------------------------------------------
-- Custom: desc.build(parent, ctx) returns a frame with .height and Refresh.
--------------------------------------------------------------------------------
function Controls.custom(parent, desc, ctx)
	local f = desc.build(parent, ctx, desc)
	f.desc, f.ctx = desc, ctx
	f.height = f.height or f:GetHeight()
	f.Refresh = f.Refresh or function() end
	return f
end

--------------------------------------------------------------------------------
-- Spell list: one row per spell ID (icon, name, ID), optional colour and
-- label per spell, optional reordering, and a box to add an ID.
--   path        the list of IDs
--   colors      path of an [id] = {r,g,b} table (optional)
--   labels      path of an [id] = "text" table (optional)
--   reorder     show up/down buttons
--   defaultColor(id), defaultLabel(id)  shown when the user set none
--------------------------------------------------------------------------------
local ROW_H, ADD_H = 26, 28

function Controls.spellList(parent, desc, ctx)
	local f = Base(parent, desc, ctx, ADD_H)
	f.rows = {}

	local function List() return GetPath(ctx:Root(), desc.path) or {} end
	local function Changed() ctx:Changed(desc.path) end

	local function Row(i)
		local r = f.rows[i]
		if r then return r end
		r = CreateFrame("Frame", nil, f)
		r:SetHeight(ROW_H - 2)
		r.bg = O:Rect(r, "control", "BACKGROUND")
		r.bg:SetAllPoints()
		r.bg:SetAlpha(i % 2 == 0 and 0.35 or 0.6)
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(18, 18)
		r.icon:SetPoint("LEFT", 4, 0)
		r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		r.name = O:Text(r, O.SIZE.text, "text")
		r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
		r.id = O:Text(r, O.SIZE.small, "muted")
		r.remove = O:IconButton(r, "close", 22, "Remove", function()
			table.remove(List(), r.index)
			Changed()
		end)
		r.remove:SetPoint("RIGHT", -2, 0)
		local right = r.remove
		if desc.reorder then
			r.down = O:IconButton(r, "chevron", 22, "Move down", function()
				local l = List()
				if r.index < #l then l[r.index], l[r.index + 1] = l[r.index + 1], l[r.index] Changed() end
			end)
			r.down:SetPoint("RIGHT", right, "LEFT", -2, 0)
			r.up = O:IconButton(r, "chevron", 22, "Move up", function()
				local l = List()
				if r.index > 1 then l[r.index], l[r.index - 1] = l[r.index - 1], l[r.index] Changed() end
			end)
			r.up.icon:SetTexCoord(0, 1, 1, 0)
			r.up:SetPoint("RIGHT", r.down, "LEFT", -2, 0)
			right = r.up
		end
		if desc.labels then
			r.label = CreateFrame("EditBox", nil, r)
			r.label:SetSize(110, 20)
			r.label:SetPoint("RIGHT", right, "LEFT", -8, 0)
			r.label:SetAutoFocus(false)
			r.label:SetFont(O:FontPath(), O.SIZE.small, "")
			r.label:SetTextColor(O:Color("text"))
			r.label:SetTextInsets(6, 6, 0, 0)
			O:Skin(r.label, "control", "controlLine")
			local function commit()
				local labels = GetPath(ctx:Root(), desc.labels)
				local t = (r.label:GetText() or ""):match("^%s*(.-)%s*$")
				labels[r.spell] = t ~= "" and t or nil
				r.label:ClearFocus()
				Changed()
			end
			r.label:SetScript("OnEnterPressed", commit)
			r.label:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
			r.label:SetScript("OnEditFocusLost", function(self)
				if not self.committing then self.committing = true commit() self.committing = false end
			end)
			right = r.label
		end
		if desc.colors then
			r.swatch = CreateFrame("Button", nil, r)
			r.swatch:SetSize(26, 16)
			r.swatch:SetPoint("RIGHT", right, "LEFT", -8, 0)
			O:Skin(r.swatch, "control", "controlLine")
			r.swatch.tex = O:Rect(r.swatch, nil, "ARTWORK")
			r.swatch.tex:SetPoint("TOPLEFT", 2, -2)
			r.swatch.tex:SetPoint("BOTTOMRIGHT", -2, 2)
			r.swatch:SetScript("OnClick", function()
				local colors = GetPath(ctx:Root(), desc.colors)
				local cur = colors[r.spell] or { desc.defaultColor(r.spell) }
				local cr, cg, cb = XUI.UnpackColor(cur)
				ColorPickerFrame:SetupColorPickerAndShow({
					r = cr, g = cg, b = cb, hasOpacity = false,
					swatchFunc = function()
						local nr, ng, nb = ColorPickerFrame:GetColorRGB()
						colors[r.spell] = { nr, ng, nb }
						Changed()
					end,
					cancelFunc = function() colors[r.spell] = cur Changed() end,
				})
			end)
			right = r.swatch
		end
		r.id:SetPoint("RIGHT", right, "LEFT", -8, 0)
		r.name:SetPoint("RIGHT", r.id, "LEFT", -6, 0)
		f.rows[i] = r
		return r
	end

	-- the add box
	f.add = CreateFrame("EditBox", nil, f)
	f.add:SetSize(120, 24)
	f.add:SetAutoFocus(false)
	f.add:SetNumeric(true)
	f.add:SetFont(O:FontPath(), O.SIZE.text, "")
	f.add:SetTextColor(O:Color("text"))
	f.add:SetTextInsets(8, 8, 0, 0)
	O:Skin(f.add, "control", "controlLine")
	f.hint = O:Text(f.add, O.SIZE.text, "faint")
	f.hint:SetPoint("LEFT", 8, 0)
	f.hint:SetText("Spell ID")
	f.add:SetScript("OnTextChanged", function(self) f.hint:SetShown((self:GetText() or "") == "") end)
	local function Add()
		local id = tonumber(f.add:GetText() or "")
		f.add:SetText("")
		f.add:ClearFocus()
		if not id or id <= 0 then return end
		local l = List()
		for _, v in ipairs(l) do if v == id then return end end
		l[#l + 1] = id
		Changed()
	end
	f.add:SetScript("OnEnterPressed", Add)
	f.add:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	f.addBtn = O:Button(f, "Add", 70, Add)
	f.addBtn:SetPoint("LEFT", f.add, "RIGHT", 6, 0)

	function f:Measure()
		local n = #List()
		self.height = n * ROW_H + ADD_H + (n > 0 and 6 or 0)
		self:SetHeight(self.height)
		return self.height
	end

	function f:Refresh()
		local list = List()
		local colors = desc.colors and GetPath(ctx:Root(), desc.colors)
		local labels = desc.labels and GetPath(ctx:Root(), desc.labels)
		for i, id in ipairs(list) do
			local r = Row(i)
			r.index, r.spell = i, id
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
			r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
			r.icon:SetTexture(XUI.GetSpellIcon(id))
			r.name:SetText(XUI.GetSpellName(id))
			r.id:SetText(tostring(id))
			if r.swatch then
				local c = colors[id]
				if type(c) == "table" then r.swatch.tex:SetVertexColor(XUI.UnpackColor(c)) else r.swatch.tex:SetVertexColor(desc.defaultColor(id)) end
			end
			if r.label and not r.label:HasFocus() then
				r.label:SetText(labels[id] or "")
				if not labels[id] and desc.defaultLabel then r.label:SetText(desc.defaultLabel(id) or "") end
			end
			r:Show()
		end
		for i = #list + 1, #self.rows do self.rows[i]:Hide() end
		self.add:ClearAllPoints()
		self.add:SetPoint("TOPLEFT", 0, -(#list * ROW_H + (#list > 0 and 6 or 0)))
		self:Measure()
	end
	return f
end
