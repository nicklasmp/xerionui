--------------------------------------------------------------------------------
-- XerionUI_Options - Panel.lua
-- The window: header, sidebar (search, pages, modules by category) and the
-- page area with its header (icon, title, description, and for modules the
-- enable switch, preview and reset).
--------------------------------------------------------------------------------
local XUI = _G.XerionUI
local O = XUI and XUI.Options
if not O then return end

local W, H = 980, 680
local SIDEBAR_W = 228
local HEADER_H = 50
local PAGEHEAD_H = 78
local ITEM_H = 28

O.systemPages = {}      -- ordered list of { key, title, desc, icon, build }
O.moduleBuilders = {}   -- [module key] = function(ctx, module, G) -> cards

-- Registers the options of a module. build(ctx, module, G) returns cards.
function O:RegisterModuleOptions(key, build)
	self.moduleBuilders[key] = build
end

-- Registers a page shown at the top of the sidebar.
-- spec: { key, title, desc, icon, build = function(ctx, G) -> cards, root, onChange }
function O:RegisterSystemPage(spec)
	self.systemPages[#self.systemPages + 1] = spec
end

local frame, sidebar, content, pageHead
local entries = {}       -- sidebar entries in display order
local pages = {}         -- [key] = Page
local currentKey
local searchText = ""

--------------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------------
local function ModuleContext(m)
	return O:NewContext(function() return m.db end, function(path)
		XUI:NotifySettingChanged(m, path)
	end, { module = m })
end

local function GetPage(key)
	if pages[key] then return pages[key] end
	local m = XUI:GetModule(key)
	local spec
	if m then
		local build = O.moduleBuilders[key]
		spec = {
			ctx = ModuleContext(m),
			build = function(ctx)
				if build then return build(ctx, m, O.Groups) end
				return { O.Card(nil, { { type = "description", text = "This module has no settings yet.", width = "full" } }) }
			end,
		}
	else
		for _, s in ipairs(O.systemPages) do
			if s.key == key then
				spec = {
					ctx = O:NewContext(s.root, s.onChange, { system = s }),
					build = function(ctx) return s.build(ctx, O.Groups) end,
				}
				break
			end
		end
	end
	if not spec then return nil end
	pages[key] = O:CreatePage(content, spec)
	return pages[key]
end

--------------------------------------------------------------------------------
-- Page header
--------------------------------------------------------------------------------
local function CreatePageHead(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(PAGEHEAD_H)

	f.iconFrame = CreateFrame("Frame", nil, f)
	f.iconFrame:SetSize(36, 36)
	f.iconFrame:SetPoint("LEFT", 20, 2)
	f.icon = f.iconFrame:CreateTexture(nil, "ARTWORK")
	f.icon:SetPoint("TOPLEFT", 1, -1)
	f.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	f.iconBorder = XUI.Style:Border(f.iconFrame, 1)

	f.title = O:Text(f, O.SIZE.title, "text")
	f.title:SetPoint("TOPLEFT", f.iconFrame, "TOPRIGHT", 14, 0)
	f.desc = O:Text(f, O.SIZE.text, "muted")
	f.desc:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -5)
	f.status = O:Text(f, O.SIZE.small, "danger")
	f.status:SetPoint("TOPLEFT", f.desc, "BOTTOMLEFT", 0, -4)

	-- module controls, right to left
	f.enable = CreateFrame("Button", nil, f)
	f.enable:SetSize(64, 28)
	f.enable:SetPoint("RIGHT", -20, 0)
	f.enable.switch = O.Switch(f.enable)
	f.enable.switch:SetPoint("RIGHT")
	f.enable.label = O:Text(f.enable, O.SIZE.small, "muted")
	f.enable.label:SetPoint("RIGHT", f.enable.switch, "LEFT", -8, 0)
	f.enable:SetScript("OnClick", function()
		local m = f.module
		if m then
			m:SetEnabled(not m.db.enabled)
			O:RefreshPageHead()
			O:RefreshSidebar()
			if pages[m.key] then pages[m.key]:Refresh() end
		end
	end)

	f.reset = O:IconButton(f, "reset", 28, "Reset to defaults", function()
		local m = f.module
		if not m then return end
		StaticPopup_Show("XERIONUI_RESET_MODULE", m.name, nil, m)
	end)
	f.reset:SetPoint("RIGHT", f.enable, "LEFT", -12, 0)

	f.preview = CreateFrame("Button", nil, f)
	f.preview:SetSize(96, 28)
	f.preview:SetPoint("RIGHT", f.reset, "LEFT", -8, 0)
	O:Skin(f.preview, "control", "controlLine")
	f.preview.icon = O:Icon(f.preview, "eye", 16, "muted")
	f.preview.icon:SetPoint("LEFT", 10, 0)
	f.preview.text = O:Text(f.preview, O.SIZE.text, "label")
	f.preview.text:SetPoint("LEFT", f.preview.icon, "RIGHT", 8, 0)
	f.preview.text:SetText("Preview")
	f.preview:SetScript("OnClick", function()
		local m = f.module
		if m then
			m:SetPreview(not m.preview)
			O:RefreshPageHead()
		end
	end)
	f.preview:SetScript("OnEnter", function(self) O:SetSkinColor(self, "controlHover") end)
	f.preview:SetScript("OnLeave", function(self) O:SetSkinColor(self, "control") end)
	O:Tooltip(f.preview, "Preview", "Shows the module with sample content so you can see your changes. Ends when the window closes.")

	f.line = O:Rect(f, "line", "ARTWORK")
	f.line:SetHeight(1)
	f.line:SetPoint("BOTTOMLEFT")
	f.line:SetPoint("BOTTOMRIGHT")
	return f
end

function O:RefreshPageHead()
	local f = pageHead
	if not f then return end
	local m = XUI:GetModule(currentKey or "")
	f.module = m
	local showModule = m ~= nil
	f.enable:SetShown(showModule)
	f.reset:SetShown(showModule)
	f.preview:SetShown(showModule)
	f.status:SetText("")
	if m then
		f.icon:SetTexture(m.icon or 134400)
		f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		f.icon:SetVertexColor(1, 1, 1)
		f.iconBorder:Apply({ useGlobal = false, style = "SOLID", size = 1, color = { 0, 0, 0, 1 } })
		f.title:SetText(m.name)
		f.desc:SetText(m.desc or "")
		f.enable.switch:SetState(m.db.enabled)
		f.enable.label:SetText(m.db.enabled and "Enabled" or "Disabled")
		local ok, why = m:CanRun()
		if m.db.enabled and not ok then f.status:SetText(why or "") end
		local ar, ag, ab = O:Accent()
		if m.preview then
			f.preview.icon:SetVertexColor(ar, ag, ab)
			f.preview.text:SetTextColor(ar, ag, ab)
		else
			f.preview.icon:SetVertexColor(O:Color("muted"))
			f.preview.text:SetTextColor(O:Color("label"))
		end
	else
		local s
		for _, sp in ipairs(O.systemPages) do if sp.key == currentKey then s = sp end end
		f.icon:SetTexture(O.MEDIA .. (s and s.icon or "logo"))
		f.icon:SetTexCoord(0, 1, 0, 1)
		f.icon:SetVertexColor(O:Accent())
		f.iconBorder:Apply({ useGlobal = false, style = "NONE" })
		f.title:SetText(s and s.title or "")
		f.desc:SetText(s and s.desc or "")
	end
end

StaticPopupDialogs.XERIONUI_RESET_MODULE = {
	text = "Reset all settings of %s to their defaults?",
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, m)
		m:Reset()
		if pages[m.key] then pages[m.key]:Refresh() end
		O:RefreshPageHead()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

--------------------------------------------------------------------------------
-- Sidebar
--------------------------------------------------------------------------------
local itemPool, headPool = {}, {}

local function SidebarItem(i)
	local b = itemPool[i]
	if b then return b end
	b = CreateFrame("Button", nil, sidebar.child)
	b:SetHeight(ITEM_H)
	b.sel = O:Rect(b, "selected", "BACKGROUND")
	b.sel:SetAllPoints()
	b.bar = O:Rect(b, nil, "ARTWORK")
	b.bar:SetWidth(2)
	b.bar:SetPoint("TOPLEFT")
	b.bar:SetPoint("BOTTOMLEFT")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(16, 16)
	b.icon:SetPoint("LEFT", 16, 0)
	b.text = O:Text(b, O.SIZE.text, "label")
	b.text:SetPoint("LEFT", b.icon, "RIGHT", 10, 0)
	b.text:SetPoint("RIGHT", -26, 0)
	b.dot = O:Icon(b, "circle", 6, nil, "OVERLAY")
	b.dot:SetPoint("RIGHT", -14, 0)
	b:SetScript("OnEnter", function(self)
		if self.key ~= currentKey then self.text:SetTextColor(O:Color("text")) end
	end)
	b:SetScript("OnLeave", function(self) O:PaintItem(self) end)
	b:SetScript("OnClick", function(self) O:Open(self.key) end)
	itemPool[i] = b
	return b
end

local function SidebarHead(i)
	local h = headPool[i]
	if h then return h end
	h = CreateFrame("Frame", nil, sidebar.child)
	h:SetHeight(30)
	h.text = O:Text(h, O.SIZE.small, "faint")
	h.text:SetPoint("BOTTOMLEFT", 16, 6)
	headPool[i] = h
	return h
end

function O:PaintItem(b)
	local selected = b.key == currentKey
	b.sel:SetShown(selected)
	b.bar:SetShown(selected)
	local ar, ag, ab = O:Accent()
	b.bar:SetVertexColor(ar, ag, ab)
	b.text:SetTextColor(O:Color(selected and "text" or "label"))
	local m = b.module
	if m then
		b.icon:SetDesaturated(not m.db.enabled)
		b.icon:SetAlpha(m.db.enabled and 1 or 0.55)
		b.dot:Show()
		if m.db.enabled then
			local ok = m:CanRun()
			if ok then b.dot:SetVertexColor(ar, ag, ab) else b.dot:SetVertexColor(O:Color("danger")) end
		else
			b.dot:SetVertexColor(O:Color("faint"))
		end
	else
		b.dot:Hide()
		b.icon:SetDesaturated(false)
		b.icon:SetAlpha(1)
		if selected then b.icon:SetVertexColor(ar, ag, ab) else b.icon:SetVertexColor(O:Color("muted")) end
	end
end

-- Lower-case words the search matches a module against: its name, category,
-- description and the labels of its options.
local searchIndex = {}
local function ModuleWords(m)
	if searchIndex[m.key] then return searchIndex[m.key] end
	local words = { m.name:lower(), (m.desc or ""):lower() }
	local build = O.moduleBuilders[m.key]
	if build then
		local ok, cards = pcall(build, ModuleContext(m), m, O.Groups)
		if ok and type(cards) == "table" then
			for _, card in ipairs(cards) do
				if card.title then words[#words + 1] = card.title:lower() end
				for _, d in ipairs(card.items or {}) do
					local label = d.label or d.text
					if type(label) == "string" then words[#words + 1] = label:lower() end
				end
			end
		end
	end
	local joined = table.concat(words, " ")
	searchIndex[m.key] = joined
	return joined
end

local function Matches(hay)
	if searchText == "" then return true end
	for word in searchText:gmatch("%S+") do
		if not hay:find(word, 1, true) then return false end
	end
	return true
end

function O:RefreshSidebar()
	if not sidebar then return end
	local child = sidebar.child
	local y, ni, nh = 6, 0, 0
	wipe(entries)

	local function AddItem(key, title, icon, m, isMedia)
		ni = ni + 1
		local b = SidebarItem(ni)
		b.key, b.module = key, m
		b.text:SetText(title)
		if isMedia then
			b.icon:SetTexture(O.MEDIA .. icon)
			b.icon:SetTexCoord(0, 1, 0, 1)
		else
			b.icon:SetTexture(icon or 134400)
			b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			b.icon:SetVertexColor(1, 1, 1)
		end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
		b:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y)
		b:Show()
		O:PaintItem(b)
		entries[#entries + 1] = key
		y = y + ITEM_H
	end
	local function AddHead(text)
		nh = nh + 1
		local h = SidebarHead(nh)
		h.text:SetText(text:upper())
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
		h:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y)
		h:Show()
		y = y + 30
	end

	for _, s in ipairs(O.systemPages) do
		if Matches((s.title .. " " .. (s.desc or "")):lower()) then
			AddItem(s.key, s.title, s.icon, nil, true)
		end
	end
	for _, cat in ipairs(XUI.CATEGORIES) do
		local list = {}
		for _, m in ipairs(XUI:SortedModules(cat.key)) do
			if m:IsAvailable() and Matches(ModuleWords(m) .. " " .. cat.name:lower()) then
				list[#list + 1] = m
			end
		end
		if #list > 0 then
			AddHead(cat.name)
			for _, m in ipairs(list) do AddItem(m.key, m.name, m.icon, m) end
		end
	end
	for i = ni + 1, #itemPool do itemPool[i]:Hide() end
	for i = nh + 1, #headPool do headPool[i]:Hide() end
	child:SetHeight(y + 8)
	sidebar:UpdateBar()
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local function SavePosition()
	local point, _, relPoint, x, y = frame:GetPoint(1)
	XUI.DB.global.panel.point = { point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5) }
end

local function CreateWindow()
	frame = CreateFrame("Frame", "XUI_OptionsFrame", UIParent)
	frame:SetSize(W, H)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	-- scale first: borders are sized in physical pixels of the final scale
	frame:SetScale(XUI.DB.global.panel.scale or 1)
	O:Skin(frame, "window", "line")
	tinsert(UISpecialFrames, "XUI_OptionsFrame")

	local p = XUI.DB.global.panel.point
	if type(p) == "table" and p[1] then
		frame:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
	else
		frame:SetPoint("CENTER")
	end

	-- header
	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(HEADER_H)
	header.bg = O:Rect(header, "header", "BACKGROUND")
	header.bg:SetAllPoints()
	header.line = O:Rect(header, "line", "ARTWORK")
	header.line:SetHeight(1)
	header.line:SetPoint("BOTTOMLEFT")
	header.line:SetPoint("BOTTOMRIGHT")
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function() frame:StartMoving() end)
	header:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		SavePosition()
	end)

	local logo = header:CreateTexture(nil, "ARTWORK")
	logo:SetTexture(O.MEDIA .. "logo")
	logo:SetSize(26, 26)
	logo:SetPoint("LEFT", 16, 0)
	local title = O:Text(header, 17, "text")
	title:SetPoint("LEFT", logo, "RIGHT", 10, 0)
	title:SetText(XUI.TITLE)
	local version = O:Text(header, O.SIZE.small, "faint")
	version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 1)
	version:SetText(XUI.version)

	local close = O:IconButton(header, "close", 30, nil, function() frame:Hide() end)
	close:SetPoint("RIGHT", -10, 0)
	local unlock = O:IconButton(header, "move", 30, "Unlock frames", function()
		frame:Hide()
		XUI:SetUnlocked(true)
	end)
	unlock:SetPoint("RIGHT", close, "LEFT", -4, 0)

	-- sidebar
	local side = CreateFrame("Frame", nil, frame)
	side:SetPoint("TOPLEFT", 0, -HEADER_H)
	side:SetPoint("BOTTOMLEFT")
	side:SetWidth(SIDEBAR_W)
	side.bg = O:Rect(side, "sidebar", "BACKGROUND")
	side.bg:SetAllPoints()
	side.line = O:Rect(side, "line", "ARTWORK")
	side.line:SetWidth(1)
	side.line:SetPoint("TOPRIGHT")
	side.line:SetPoint("BOTTOMRIGHT")

	local search = CreateFrame("EditBox", nil, side)
	search:SetHeight(28)
	search:SetPoint("TOPLEFT", 12, -12)
	search:SetPoint("TOPRIGHT", -12, -12)
	search:SetAutoFocus(false)
	search:SetFont(O:FontPath(), O.SIZE.text, "")
	search:SetTextColor(O:Color("text"))
	search:SetTextInsets(28, 8, 0, 0)
	O:Skin(search, "control", "controlLine")
	local sIcon = O:Icon(search, "search", 13, "muted")
	sIcon:SetPoint("LEFT", 9, 0)
	local hint = O:Text(search, O.SIZE.text, "faint")
	hint:SetPoint("LEFT", 28, 0)
	hint:SetText("Search")
	search:SetScript("OnTextChanged", function(self)
		searchText = (self:GetText() or ""):lower()
		hint:SetShown(searchText == "")
		O:RefreshSidebar()
	end)
	search:SetScript("OnEscapePressed", function(self)
		if self:GetText() ~= "" then self:SetText("") else self:ClearFocus() end
	end)
	search:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		if entries[1] then O:Open(entries[1]) end
	end)

	local list = CreateFrame("Frame", nil, side)
	list:SetPoint("TOPLEFT", 0, -50)
	list:SetPoint("BOTTOMRIGHT", -1, 8)
	sidebar = O:CreateScroll(list)
	sidebar:SetAllPoints(list)

	-- content
	content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", SIDEBAR_W, -(HEADER_H + PAGEHEAD_H))
	content:SetPoint("BOTTOMRIGHT", 0, 1)
	pageHead = CreatePageHead(frame)
	pageHead:SetPoint("TOPLEFT", SIDEBAR_W, -HEADER_H)
	pageHead:SetPoint("TOPRIGHT", 0, -HEADER_H)

	frame:SetScript("OnHide", function()
		O.CloseDropdown()
		for _, m in ipairs(XUI.modules) do m:SetPreview(false) end
	end)

	local owner = {}
	XUI:On("ProfileChanged", owner, function()
		if not frame:IsShown() then return end
		for _, page in pairs(pages) do page:Refresh() end
		O:RefreshSidebar()
		O:RefreshPageHead()
	end)
	XUI:On("ModuleStateChanged", owner, function()
		if frame:IsShown() then O:RefreshSidebar() O:RefreshPageHead() end
	end)
	XUI:On("PreviewChanged", owner, function()
		if frame:IsShown() then O:RefreshPageHead() end
	end)
end

function O:Open(key)
	if not frame then CreateWindow() end
	key = key or currentKey or (O.systemPages[1] and O.systemPages[1].key)
	if XUI:GetModule(key) == nil then
		local found = false
		for _, s in ipairs(O.systemPages) do if s.key == key then found = true end end
		if not found then key = O.systemPages[1].key end
	end
	if currentKey and pages[currentKey] and currentKey ~= key then pages[currentKey]:Hide() end
	currentKey = key
	frame:Show()
	O:RefreshSidebar()
	O:RefreshPageHead()
	local page = GetPage(key)
	if page then page:Show() end
end

function O:Close()
	if frame then frame:Hide() end
end

function O:IsShown()
	return frame and frame:IsShown() or false
end

-- Rebuilds every page (after the panel font or accent changed).
function O:RebuildAll()
	for _, page in pairs(pages) do page:Rebuild() end
	O:RefreshSidebar()
	O:RefreshPageHead()
end
