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
local autoStarted, docked, UpdateDockSoon = {}, false, nil
local expandedClass = {}
local searchText = ""

--------------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------------
local function ModuleContext(m)
	return O:NewContext(function() return m.db end, function(path)
		XUI:NotifySettingChanged(m, path)
	end, { module = m })
end

local function ClassKey(key) return type(key) == "string" and key:match("^class:(.+)$") end

local function GetPage(key)
	if pages[key] then return pages[key] end
	local m = XUI:GetModule(key)
	local spec
	if ClassKey(key) then
		spec = O:ClassPageSpec(ClassKey(key))
	elseif m then
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

	local function HeadButton(icon, text, width, tip, onClick)
		local b = CreateFrame("Button", nil, f)
		b:SetSize(width, 28)
		O:Skin(b, "control", "controlLine")
		b.icon = O:Icon(b, icon, 16, "muted")
		b.icon:SetPoint("LEFT", 10, 0)
		b.text = O:Text(b, O.SIZE.text, "label")
		b.text:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
		b.text:SetText(text)
		b:SetScript("OnClick", onClick)
		b:SetScript("OnEnter", function(self) O:SetSkinColor(self, "controlHover") end)
		b:SetScript("OnLeave", function(self) O:SetSkinColor(self, "control") end)
		if tip then O:Tooltip(b, text, tip) end
		return b
	end

	-- plays a short sample through the module's real code
	f.test = HeadButton("play", "Test", 76, "Runs a short sample through the real code, as if it had been triggered in the game.", function()
		local m = f.module
		if m and m.Test then
			-- a test goes through the real code, not the sample
			if m.preview then autoStarted[m] = nil m:SetPreview(false) end
			XUI.SafeCallFor(m, m.Test, m)
			O:RefreshPageHead()
		end
	end)
	f.test:SetPoint("RIGHT", f.preview, "LEFT", -8, 0)

	-- cycles the looks the preview can take
	f.state = HeadButton("layers", "", 150, "Switch which look the preview shows.", function()
		local m = f.module
		local list = m and m.PREVIEW_STATES
		if not list then return end
		local index = 0
		for i, s in ipairs(list) do if s.value == m.previewState then index = i end end
		m:SetPreviewState(list[index % #list + 1].value)
		O:RefreshPageHead()
	end)
	f.state:SetPoint("RIGHT", f.test, "LEFT", -8, 0)

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
	f.test:SetShown(showModule and m.Test ~= nil)
	local states = showModule and m.PREVIEW_STATES
	f.state:SetShown(states and true or false)
	if states then
		local label = states[1].text
		for _, st in ipairs(states) do if st.value == m.previewState then label = st.text end end
		f.state.text:SetText(label)
		f.state:ClearAllPoints()
		f.state:SetPoint("RIGHT", m.Test and f.test or f.preview, "LEFT", -8, 0)
	end
	f.status:SetText("")
	if m then
		f.icon:SetTexture(XUI.ModuleIcon(m))
		f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		f.icon:SetVertexColor(1, 1, 1)
		f.iconBorder:Apply({ useGlobal = false, style = "SOLID", size = 1, color = { 0, 0, 0, 1 } })
		f.title:SetText(m.name)
		f.desc:SetText(m.desc or "")
		f.enable.switch:SetState(m.db.enabled)
		f.enable.label:SetText(m.db.enabled and "Enabled" or "Disabled")
		local ok, why = m:CanRun()
		local note = m.untested and "  |cff888888Untested in game.|r" or ""
		if (m.errorCount or 0) > 0 then
			f.status:SetTextColor(O:Color("danger"))
			f.status:SetText(("%d Lua error(s), last: %s"):format(m.errorCount, (m.errors and m.errors[#m.errors] or ""):match("^[^\n]*"):sub(1, 140)))
		elseif m.db.enabled and not ok then
			f.status:SetTextColor(O:Color("danger"))
			f.status:SetText("Not running: " .. (why or "unknown reason"))
		elseif m.db.enabled and m.running then
			f.status:SetTextColor(O:Accent())
			f.status:SetText("Running." .. note)
		elseif m.db.enabled then
			f.status:SetTextColor(O:Color("muted"))
			f.status:SetText("Enabled, starting..." .. note)
		else
			f.status:SetTextColor(O:Color("muted"))
			f.status:SetText("Off - switch it on, or use Preview to see it." .. note)
		end
		local ar, ag, ab = O:Accent()
		if m.preview then
			f.preview.icon:SetVertexColor(ar, ag, ab)
			f.preview.text:SetTextColor(ar, ag, ab)
		else
			f.preview.icon:SetVertexColor(O:Color("muted"))
			f.preview.text:SetTextColor(O:Color("label"))
		end
	elseif ClassKey(currentKey) then
		local c = O.classByToken[ClassKey(currentKey)]
		f.icon:SetTexture(c and c.icon or 134400)
		f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		f.icon:SetVertexColor(1, 1, 1)
		f.iconBorder:Apply({ useGlobal = false, style = "SOLID", size = 1, color = { 0, 0, 0, 1 } })
		f.title:SetText(c and c.name or "")
		f.desc:SetText(c and c.token ~= "ANY" and "Pick a specialization to see its modules." or "Modules that work for every class.")
	else
		local s
		for _, sp in ipairs(O.systemPages) do if sp.key == currentKey then s = sp end end
		f.icon:SetTexture(O.MEDIA .. (s and s.icon or "sliders"))
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
	b.arrow = O:Icon(b, "chevron", 10, "muted", "OVERLAY")
	b.arrow:SetPoint("RIGHT", -14, 0)
	b.text = O:Text(b, O.SIZE.text, "label")
	b.text:SetPoint("LEFT", b.icon, "RIGHT", 10, 0)
	b.text:SetPoint("RIGHT", -26, 0)
	b.dot = O:Icon(b, "circle", 6, nil, "OVERLAY")
	b.dot:SetPoint("RIGHT", -14, 0)
	b:SetScript("OnEnter", function(self)
		if self.key ~= currentKey then self.text:SetTextColor(O:Color("text")) end
	end)
	b:SetScript("OnLeave", function(self) O:PaintItem(self) end)
	b:SetScript("OnClick", function(self)
		if self.classToken then
			-- a second click on the open class folds it
			if self.key == currentKey then expandedClass[self.classToken] = not expandedClass[self.classToken]
			else expandedClass[self.classToken] = true end
		end
		O:Open(self.key)
	end)
	itemPool[i] = b
	return b
end

local function SidebarHead(i)
	local h = headPool[i]
	if h then return h end
	h = CreateFrame("Button", nil, sidebar.child)
	h:SetHeight(30)
	h.text = O:Text(h, O.SIZE.small, "faint")
	h.text:SetPoint("BOTTOMLEFT", 16, 6)
	h.arrow = O:Icon(h, "chevron", 10, "muted", "OVERLAY")
	h.arrow:SetPoint("BOTTOMRIGHT", -14, 8)
	h:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
	h:SetScript("OnEnter", function(self) if self.onClick then self.text:SetTextColor(O:Color("text")) end end)
	h:SetScript("OnLeave", function(self) self.text:SetTextColor(O:Color("faint")) end)
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
			if ok and (m.errorCount or 0) == 0 then b.dot:SetVertexColor(ar, ag, ab) else b.dot:SetVertexColor(O:Color("danger")) end
		else
			b.dot:SetVertexColor(O:Color("faint"))
		end
	else
		b.dot:Hide()
		b.icon:SetDesaturated(false)
		b.icon:SetAlpha(1)
		if b.classToken then
			b.icon:SetVertexColor(1, 1, 1)
			b.arrow:SetVertexColor(O:Color(selected and "text" or "muted"))
		elseif selected then b.icon:SetVertexColor(ar, ag, ab) else b.icon:SetVertexColor(O:Color("muted")) end
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

	local function AddItem(key, title, icon, m, isMedia, indent, classToken)
		ni = ni + 1
		local b = SidebarItem(ni)
		b.key, b.module, b.classToken = key, m, classToken
		b.icon:ClearAllPoints()
		b.icon:SetPoint("LEFT", 16 + (indent or 0), 0)
		b.arrow:SetShown(classToken ~= nil)
		if classToken then
			b.arrow:SetRotation(expandedClass[classToken] and 0 or math.rad(90))
		end
		b.text:SetText(m and m.untested and (title .. "  |cff777777untested|r") or title)
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
	-- fold: nil for a plain heading, else { folded = bool, toggle = function }
	local function AddHead(text, fold)
		nh = nh + 1
		local h = SidebarHead(nh)
		h.text:SetText(text:upper())
		h.onClick = fold and fold.toggle or nil
		h.arrow:SetShown(fold ~= nil)
		if fold then h.arrow:SetRotation(fold.folded and math.rad(90) or 0) end
		h:EnableMouse(fold ~= nil)
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
		if cat.key == "class" then
			-- every class, whatever you play, each with its modules below it; the
			-- whole group folds from its heading (a search unfolds it)
			local folded = XUI.DB.global.panel.classFolded and searchText == ""
			AddHead(cat.name, { folded = folded, toggle = function()
				XUI.DB.global.panel.classFolded = not XUI.DB.global.panel.classFolded
				O:RefreshSidebar()
			end })
			local order = {}
			for _, c in ipairs(O.CLASSES) do order[#order + 1] = c end
			order[#order + 1] = O.ANY_CLASS
			for _, c in ipairs(folded and {} or order) do
				local mods, matching = O:ClassModules(c.token), {}
				for _, m in ipairs(mods) do
					if Matches(ModuleWords(m) .. " " .. c.name:lower()) then matching[#matching + 1] = m end
				end
				local classMatches = Matches(c.name:lower())
				-- a class nothing has been made for yet stays out of the list
				if #mods > 0 and (searchText == "" or classMatches or #matching > 0) then
					-- the class you play starts unfolded
					if expandedClass[c.token] == nil then expandedClass[c.token] = (c.token == XUI.playerClass) end
					AddItem("class:" .. c.token, c.name, c.icon, nil, false, 0, c.token)
					if searchText ~= "" or expandedClass[c.token] then
						for _, m in ipairs(searchText ~= "" and not classMatches and matching or mods) do
							AddItem(m.key, m.name, XUI.ModuleIcon(m), m, false, 14)
						end
					end
				end
			end
			list = {}
		else
		for _, m in ipairs(XUI:SortedModules(cat.key)) do
			if m:IsAvailable() and Matches(ModuleWords(m) .. " " .. cat.name:lower()) then
				list[#list + 1] = m
			end
		end
		end
		if #list > 0 then
			AddHead(cat.name)
			for _, m in ipairs(list) do AddItem(m.key, m.name, XUI.ModuleIcon(m), m) end
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

	local title = O:Text(header, 17, "text")
	title:SetPoint("LEFT", 20, 0)
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
		wipe(autoStarted)
		if docked then docked = false end
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
		if frame:IsShown() then O:RefreshPageHead() UpdateDockSoon() end
	end)
	XUI:On("ModuleError", owner, function()
		if frame:IsShown() then O:RefreshPageHead() O:RefreshSidebar() end
	end)
end

--------------------------------------------------------------------------------
-- Preview that follows the page, and a window that steps aside for it
--------------------------------------------------------------------------------
local function SyncAutoPreview(key)
	for m in pairs(autoStarted) do
		if m.key ~= key then
			autoStarted[m] = nil
			m:SetPreview(false)
		end
	end
	if XUI.DB.global.panel.autoPreview == false then return end
	local m = XUI:GetModule(key)
	if m and not m.preview and not autoStarted[m] then
		autoStarted[m] = true
		m:SetPreview(true)
	end
end

local function RectsOverlap(a, b)
	return a.l < b.r and a.r > b.l and a.b < b.t and a.t > b.b
end
local function ScreenRect(f)
	local l, b, w, h = f:GetRect()
	if not l then return nil end
	local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return { l = l * s, b = b * s, r = (l + w) * s, t = (b + h) * s }
end

function O:UpdateDock()
	if not (frame and frame:IsShown()) then return end
	local want = false
	local mine = ScreenRect(frame)
	if XUI.DB.global.panel.dock ~= false and mine then
		for _, entry in ipairs(XUI.Movers.list) do
			local m = entry.module
			if m.preview and entry.frame:IsShown() then
				local r = ScreenRect(entry.frame)
				if r and RectsOverlap(mine, r) then
					-- the side the preview is not on
					local cx = (r.l + r.r) / 2
					frame:ClearAllPoints()
					if cx > UIParent:GetWidth() / 2 then
						frame:SetPoint("LEFT", UIParent, "LEFT", 24, 0)
					else
						frame:SetPoint("RIGHT", UIParent, "RIGHT", -24, 0)
					end
					docked = true
					return
				end
				want = want or false
			end
		end
	end
	if docked then
		docked = false
		frame:ClearAllPoints()
		local p = XUI.DB.global.panel.point
		if type(p) == "table" and p[1] then
			frame:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
		else
			frame:SetPoint("CENTER")
		end
	end
end

UpdateDockSoon = XUI.Coalesce(function() C_Timer.After(0.05, function() O:UpdateDock() end) end)

function O:Open(key)
	if not frame then CreateWindow() end
	key = key or currentKey or (O.systemPages[1] and O.systemPages[1].key)
	if XUI:GetModule(key) == nil and not (ClassKey(key) and O.classByToken[ClassKey(key)]) then
		local found = false
		for _, s in ipairs(O.systemPages) do if s.key == key then found = true end end
		if not found then key = O.systemPages[1].key end
	end
	if currentKey and pages[currentKey] and currentKey ~= key then pages[currentKey]:Hide() end
	currentKey = key
	frame:Show()
	SyncAutoPreview(key)
	UpdateDockSoon()
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
