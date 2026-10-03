--------------------------------------------------------------------------------
-- XerionUI_Options - Dropdown.lua
-- The one dropdown list, shared by every dropdown control. Long lists get a
-- filter box; LibSharedMedia lists preview their entries (fonts drawn in
-- themselves, bar textures behind their names, a play button per sound).
--------------------------------------------------------------------------------
local XUI = _G.XerionUI
local O = XUI and XUI.Options
if not O then return end

local ROW_H = 22
local MAX_ROWS = 12
local SEARCH_FROM = 14

local popup, blocker
local rows = {}

local function Close()
	if popup then popup:Hide() end
	if blocker then blocker:Hide() end
end
O.CloseDropdown = Close

local function CreatePopup()
	blocker = CreateFrame("Button", nil, UIParent)
	blocker:SetAllPoints(UIParent)
	blocker:SetFrameStrata("FULLSCREEN_DIALOG")
	blocker:RegisterForClicks("AnyDown")
	blocker:SetScript("OnClick", Close)
	blocker:Hide()

	popup = CreateFrame("Frame", "XerionUIOptionsDropdown", UIParent)
	popup:SetFrameStrata("FULLSCREEN_DIALOG")
	popup:SetFrameLevel(blocker:GetFrameLevel() + 10)
	popup:SetClampedToScreen(true)
	popup:EnableMouse(true)
	O:Skin(popup, "card", "controlLine")
	popup:Hide()
	popup:SetScript("OnHide", function() if blocker then blocker:Hide() end end)
	tinsert(UISpecialFrames, "XerionUIOptionsDropdown")

	local search = CreateFrame("EditBox", nil, popup)
	search:SetHeight(22)
	search:SetPoint("TOPLEFT", 6, -6)
	search:SetPoint("TOPRIGHT", -6, -6)
	search:SetAutoFocus(false)
	search:SetFont(O:FontPath(), O.SIZE.text, "")
	search:SetTextColor(O:Color("text"))
	search:SetTextInsets(22, 6, 0, 0)
	O:Skin(search, "control", "controlLine")
	local icon = O:Icon(search, "search", 12, "muted")
	icon:SetPoint("LEFT", 6, 0)
	search:SetScript("OnEscapePressed", Close)
	search:SetScript("OnTextChanged", function(self, user)
		if user then popup.offset = 0 popup:Render() end
	end)
	popup.search = search

	popup:EnableMouseWheel(true)
	popup:SetScript("OnMouseWheel", function(self, delta)
		local maxOffset = math.max(0, #self.filtered - MAX_ROWS)
		self.offset = math.max(0, math.min(maxOffset, self.offset - delta * 3))
		self:Render()
	end)

	popup.scrollThumb = O:Rect(popup, "controlLine", "OVERLAY")
	popup.scrollThumb:SetWidth(3)
end

local function Row(i)
	local r = rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, popup)
	r:SetHeight(ROW_H)
	r.hl = O:Rect(r, "controlHover", "BACKGROUND")
	r.hl:SetAllPoints()
	r.hl:Hide()
	r.preview = r:CreateTexture(nil, "BACKGROUND", nil, 1)
	r.preview:SetPoint("TOPLEFT", 1, -1)
	r.preview:SetPoint("BOTTOMRIGHT", -1, 1)
	r.preview:Hide()
	r.text = O:Text(r, O.SIZE.text, "text")
	r.text:SetPoint("LEFT", 8, 0)
	r.text:SetPoint("RIGHT", -28, 0)
	r.check = O:Icon(r, "check", 12)
	r.check:SetPoint("RIGHT", -8, 0)
	r.play = CreateFrame("Button", nil, r)
	r.play:SetSize(18, 18)
	r.play:SetPoint("RIGHT", -24, 0)
	r.play.icon = O:Icon(r.play, "play", 10, "muted")
	r.play.icon:SetPoint("CENTER")
	r.play:SetScript("OnEnter", function(self) self.icon:SetVertexColor(O:Accent()) end)
	r.play:SetScript("OnLeave", function(self) self.icon:SetVertexColor(O:Color("muted")) end)
	r.play:SetScript("OnClick", function(self) XUI.Audio:PlaySound(self:GetParent().value, "Master") end)
	r:SetScript("OnEnter", function(self) self.hl:Show() end)
	r:SetScript("OnLeave", function(self) self.hl:Hide() end)
	r:SetScript("OnClick", function(self)
		local pick = popup.onPick
		Close()
		if pick then pick(self.value) end
	end)
	rows[i] = r
	return r
end

local function Filter()
	local q = (popup.search:IsShown() and popup.search:GetText() or ""):lower()
	local out = {}
	for _, v in ipairs(popup.values) do
		if q == "" or tostring(v.text):lower():find(q, 1, true) then out[#out + 1] = v end
	end
	popup.filtered = out
end

local function Render(self)
	Filter()
	self.offset = math.max(0, math.min(self.offset, #self.filtered - MAX_ROWS))
	local list, media = self.filtered, self.media
	local top = self.search:IsShown() and 34 or 4
	local visible = math.min(MAX_ROWS, #list)
	self:SetHeight(top + math.max(1, visible) * ROW_H + 4)
	local ar, ag, ab = O:Accent()
	for i = 1, MAX_ROWS do
		local r = Row(i)
		local item = list[i + self.offset]
		if item and i <= visible then
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", 4, -(top + (i - 1) * ROW_H))
			r:SetPoint("TOPRIGHT", -8, -(top + (i - 1) * ROW_H))
			r.value = item.value
			r.text:SetText(item.text)
			if media == "font" then
				r.text:SetFont(XUI.Media:Fetch("font", item.value), O.SIZE.text, "")
			else
				r.text:SetFont(O:FontPath(), O.SIZE.text, "")
			end
			if media == "statusbar" then
				r.preview:SetTexture(XUI.Media:Fetch("statusbar", item.value))
				r.preview:SetVertexColor(0.35, 0.35, 0.35, 1)
				r.preview:Show()
			else
				r.preview:Hide()
			end
			r.play:SetShown(media == "sound" and item.value ~= "")
			local selected = item.value == self.current
			r.check:SetShown(selected)
			r.check:SetVertexColor(ar, ag, ab)
			if selected then r.text:SetTextColor(ar, ag, ab) else r.text:SetTextColor(O:Color("text")) end
			r:Show()
		else
			r:Hide()
		end
	end
	-- scroll position indicator
	local thumb = self.scrollThumb
	if #list > MAX_ROWS then
		local trackH = visible * ROW_H
		local h = math.max(12, trackH * MAX_ROWS / #list)
		local y = (trackH - h) * self.offset / (#list - MAX_ROWS)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPRIGHT", -2, -(top + y))
		thumb:SetHeight(h)
		thumb:Show()
	else
		thumb:Hide()
	end
end

function O:OpenDropdown(anchor, desc, ctx, current, onPick)
	if not popup then CreatePopup() popup.Render = Render end
	if popup:IsShown() and popup.anchor == anchor then
		Close()
		return
	end
	popup.anchor = anchor
	popup.values = self:DropdownValues(desc, ctx)
	popup.media = desc.media
	popup.current = current
	popup.onPick = onPick
	popup.offset = 0
	popup.search:SetText("")
	popup.search:SetShown(#popup.values >= SEARCH_FROM)
	popup:SetWidth(math.max(anchor:GetWidth(), 180))
	popup:SetScale(anchor:GetEffectiveScale() / UIParent:GetEffectiveScale())
	popup:ClearAllPoints()
	popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	-- start scrolled to the current value
	for i, v in ipairs(popup.values) do
		if v.value == current then
			popup.offset = math.max(0, math.min(i - 3, #popup.values - MAX_ROWS))
			break
		end
	end
	popup:Render()
	blocker:Show()
	popup:Show()
	if popup.search:IsShown() then popup.search:SetFocus() end
end
