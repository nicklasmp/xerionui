--------------------------------------------------------------------------------
-- XerionUI_Options - Page.lua
-- A page is a scrolling column of cards; a card is a titled grid of controls.
-- Pages are described with plain tables and built the first time they are
-- shown:
--     { O.Card("Text", { control, control, ... }, { columns = 2 }), ... }
-- A control spans one column, or the whole row with width = "full" (or
-- span = n). hidden(ctx) / disabled(ctx) are re-evaluated after every change,
-- so dependent options appear and grey out as you click.
--------------------------------------------------------------------------------
local XUI = _G.XerionUI
local O = XUI and XUI.Options
if not O then return end

local max = math.max

local PAGE_PAD = 16
local CARD_PAD = 14
local CARD_GAP = 12
local COL_GAP = 18
local ROW_GAP = 12
local TITLE_H = 26

--------------------------------------------------------------------------------
-- Context: where a page's controls read and write.
--   root()                      the table paths are relative to
--   onChange(path, value, desc) after a write
--------------------------------------------------------------------------------
local Ctx = {}
Ctx.__index = Ctx

function O:NewContext(root, onChange, extra)
	local ctx = setmetatable(extra or {}, Ctx)
	ctx.root, ctx.onChange = root, onChange
	return ctx
end

function Ctx:Root()
	return self.root()
end

function Ctx:Changed(path, value, desc)
	if self.onChange then XUI.SafeCall(self.onChange, path, value, desc) end
	if self.page then self.page:RefreshSoon() end
end

--------------------------------------------------------------------------------
-- Descriptor helpers
--------------------------------------------------------------------------------
function O.Card(title, items, opts)
	local card = opts or {}
	card.title, card.items = title, items
	return card
end

-- Concatenates item lists: O.Join(G.Font("text"), { more }, ...)
function O.Join(...)
	local out = {}
	for i = 1, select("#", ...) do
		local list = select(i, ...)
		if list then
			for _, item in ipairs(list) do out[#out + 1] = item end
		end
	end
	return out
end

--------------------------------------------------------------------------------
-- Scroll area with a thin scrollbar
--------------------------------------------------------------------------------
function O:CreateScroll(parent)
	local sf = CreateFrame("ScrollFrame", nil, parent)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(1, 1)
	sf:SetScrollChild(child)
	sf:EnableMouseWheel(true)

	local bar = CreateFrame("Frame", nil, sf)
	bar:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -3, -4)
	bar:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -3, 4)
	bar:SetWidth(4)
	local thumb = CreateFrame("Frame", nil, bar)
	thumb:SetWidth(4)
	thumb.tex = O:Rect(thumb, "controlLine", "OVERLAY")
	thumb.tex:SetAllPoints()
	thumb:EnableMouse(true)
	sf.bar, sf.thumb, sf.child = bar, thumb, child

	function sf:UpdateBar()
		local range = self:GetVerticalScrollRange()
		if range <= 0 then
			bar:Hide()
			return
		end
		bar:Show()
		local h = bar:GetHeight()
		local view = self:GetHeight()
		local th = max(24, h * view / (view + range))
		thumb:SetHeight(th)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOP", bar, "TOP", 0, -(h - th) * self:GetVerticalScroll() / range)
	end

	sf:SetScript("OnMouseWheel", function(self, delta)
		local range = self:GetVerticalScrollRange()
		local v = math.max(0, math.min(range, self:GetVerticalScroll() - delta * 48))
		self:SetVerticalScroll(v)
		self:UpdateBar()
	end)
	sf:SetScript("OnScrollRangeChanged", function(self) self:UpdateBar() end)
	sf:SetScript("OnSizeChanged", function(self, w) child:SetWidth(w) self:UpdateBar() end)

	thumb:SetScript("OnMouseDown", function(self)
		local _, cy = GetCursorPosition()
		self.startY, self.startScroll = cy / self:GetEffectiveScale(), sf:GetVerticalScroll()
		self:SetScript("OnUpdate", function()
			local _, y = GetCursorPosition()
			y = y / self:GetEffectiveScale()
			local range = sf:GetVerticalScrollRange()
			local free = bar:GetHeight() - self:GetHeight()
			if free <= 0 then return end
			local v = self.startScroll + (self.startY - y) * range / free
			sf:SetVerticalScroll(math.max(0, math.min(range, v)))
			sf:UpdateBar()
		end)
	end)
	thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
	return sf, child
end

--------------------------------------------------------------------------------
-- Page
--------------------------------------------------------------------------------
local Page = {}
Page.__index = Page

-- spec: { build = function(ctx) return cards end, ctx = context }
function O:CreatePage(parent, spec)
	local page = setmetatable({ spec = spec, ctx = spec.ctx, cards = {} }, Page)
	page.ctx.page = page
	page.scroll, page.child = self:CreateScroll(parent)
	page.scroll:SetAllPoints(parent)
	page.scroll:Hide()
	page.RefreshSoon = XUI.Coalesce(function() page:Refresh() end)
	return page
end

--------------------------------------------------------------------------------
-- A small reset mark on controls whose value differs from the module's default:
-- it shows what has been changed, and one click puts that one value back.
--------------------------------------------------------------------------------
local RESETTABLE = { toggle = true, slider = true, color = true, dropdown = true, input = true }

function O:AttachReset(control, desc, ctx)
	local m = ctx.module
	if not (m and desc.path and RESETTABLE[desc.type]) or desc.noReset then return end
	local b = O:IconButton(control, "reset", 16, "Changed from the default - click to reset this value", function()
		local default = XUI.GetPath(m.defaults, desc.path)
		if default == nil then return end
		XUI.SetPath(ctx:Root(), desc.path, XUI.CopyTable(default))
		ctx:Changed(desc.path, default, desc)
		control:Refresh()
	end)
	b:SetPoint("TOPRIGHT", control, "TOPRIGHT", 0, 2)
	b:SetFrameLevel(control:GetFrameLevel() + 5)
	b.icon:SetVertexColor(O:Accent())
	b:Hide()
	control.resetMark = b
	local refresh = control.Refresh
	function control:Refresh(...)
		refresh(self, ...)
		local default = XUI.GetPath(m.defaults, desc.path)
		local current = XUI.GetPath(ctx:Root(), desc.path)
		local changed = default ~= nil and current ~= nil and not XUI.DeepEqual(default, current)
		b:SetShown(changed)
		if changed then b.icon:SetVertexColor(O:Accent()) end
	end
end

local function BuildCard(page, spec)
	local card = { spec = spec, items = {} }
	local f = CreateFrame("Frame", nil, page.child)
	O:Skin(f, "card", "cardBorder")
	card.frame = f
	if spec.title then
		f.title = O:Text(f, O.SIZE.heading, "muted")
		f.title:SetPoint("TOPLEFT", CARD_PAD, -CARD_PAD + 2)
		f.title:SetText(spec.title:upper())
	end
	-- an eye on the card's corner puts the preview in the look this card edits
	if spec.previewState and page.ctx.module then
		local m = page.ctx.module
		local b = O:IconButton(f, "eye", 22, "Show this in the preview", function()
			if spec.previewState == true then m:SetPreview(true) else m:SetPreviewState(spec.previewState) end
		end)
		b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -CARD_PAD + 4, -CARD_PAD + 6)
		card.previewButton = b
	end
	for _, desc in ipairs(spec.items or {}) do
		local make = O.Controls[desc.type]
		assert(make, "XerionUI options: unknown control type " .. tostring(desc.type))
		local control = make(f, desc, page.ctx)
		control.page = page
		O:AttachReset(control, desc, page.ctx)
		card.items[#card.items + 1] = control
	end
	return card
end

function Page:Build()
	if self.built then return end
	self.built = true
	local specs = self.spec.build(self.ctx) or {}
	for _, spec in ipairs(specs) do
		self.cards[#self.cards + 1] = BuildCard(self, spec)
	end
end

local function Hidden(desc, ctx)
	local h = desc.hidden
	if type(h) == "function" then return h(ctx) and true or false end
	return h and true or false
end

function Page:Layout()
	local width = self.scroll:GetWidth()
	if not width or width <= 1 then return end
	local cardW = width - PAGE_PAD * 2 - 8
	local y = PAGE_PAD
	for _, card in ipairs(self.cards) do
		local spec, f = card.spec, card.frame
		if Hidden(spec, self.ctx) then
			f:Hide()
		else
			local cols = spec.columns or 2
			local inner = cardW - CARD_PAD * 2
			local cellW = (inner - COL_GAP * (cols - 1)) / cols
			local top = spec.title and (CARD_PAD + TITLE_H - 8) or CARD_PAD
			local rowY, rowH, col = top, 0, 0
			local row = {}
			-- Controls in a row share its bottom edge, so a button lines up
			-- with the field of the labelled dropdown beside it.
			local function Flush()
				for _, it in ipairs(row) do
					local y = it.alignTop and rowY or (rowY + rowH - it.h)
					it.control:ClearAllPoints()
					it.control:SetPoint("TOPLEFT", f, "TOPLEFT", it.x, -y)
				end
				wipe(row)
				rowY = rowY + rowH + ROW_GAP
				rowH, col = 0, 0
			end
			for _, control in ipairs(card.items) do
				local desc = control.desc
				if Hidden(desc, self.ctx) then
					control:Hide()
				else
					local span = desc.width == "full" and cols or math.min(cols, desc.span or 1)
					if col > 0 and (col + span > cols or desc.newRow) then Flush() end
					control:SetWidth(cellW * span + COL_GAP * (span - 1))
					if control.Measure then control:Measure() end
					control:Show()
					local h = control.height or control:GetHeight()
					row[#row + 1] = {
						control = control, h = h, alignTop = desc.alignTop or desc.type == "description",
						x = CARD_PAD + col * (cellW + COL_GAP),
					}
					rowH = max(rowH, h)
					col = col + span
					if col >= cols then Flush() end
				end
			end
			if col > 0 then
				Flush()
			end
			col = 0
			local h = rowY + rowH + CARD_PAD - (col == 0 and ROW_GAP or 0)
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", self.child, "TOPLEFT", PAGE_PAD, -y)
			f:SetSize(cardW, max(h, top + CARD_PAD))
			f:Show()
			y = y + f:GetHeight() + CARD_GAP
		end
	end
	self.child:SetHeight(y + PAGE_PAD)
	self.scroll:UpdateBar()
end

function Page:Refresh()
	if not self.built then return end
	for _, card in ipairs(self.cards) do
		for _, control in ipairs(card.items) do
			XUI.SafeCall(control.Refresh, control)
		end
	end
	self:Layout()
end

function Page:Show()
	self:Build()
	self.scroll:Show()
	self:Refresh()
	-- the scroll frame may only have its size on the next frame
	C_Timer.After(0, function() if self.scroll:IsShown() then self:Layout() end end)
end

function Page:Hide()
	self.scroll:Hide()
end

-- Rebuilds the page from its spec (after a profile switch, say).
function Page:Rebuild()
	for _, card in ipairs(self.cards) do card.frame:Hide() card.frame:SetParent(nil) end
	wipe(self.cards)
	self.built = false
	if self.scroll:IsShown() then self:Show() end
end
