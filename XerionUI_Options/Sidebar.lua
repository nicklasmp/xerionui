--------------------------------------------------------------------------------
-- XerionUI_Options - Sidebar.lua
-- (split out of Panel.lua; the window state lives in O.S)
--------------------------------------------------------------------------------
local XUI = _G.XerionUI
local O = XUI and XUI.Options
if not O then return end

local S = O.S
local ITEM_H = O.LAYOUT.ITEM_H

--------------------------------------------------------------------------------
-- Sidebar
--------------------------------------------------------------------------------
local itemPool, headPool = {}, {}

local function SidebarItem(i)
	local b = itemPool[i]
	if b then return b end
	b = CreateFrame("Button", nil, S.sidebar.child)
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
		if self.key ~= S.currentKey then self.text:SetTextColor(O:Color("text")) end
	end)
	b:SetScript("OnLeave", function(self) O:PaintItem(self) end)
	b:SetScript("OnClick", function(self)
		if self.classToken then
			-- a second click on the open class folds it
			if self.key == S.currentKey then S.expandedClass[self.classToken] = not S.expandedClass[self.classToken]
			else S.expandedClass[self.classToken] = true end
		end
		O:Open(self.key)
	end)
	itemPool[i] = b
	return b
end

local function SidebarHead(i)
	local h = headPool[i]
	if h then return h end
	h = CreateFrame("Button", nil, S.sidebar.child)
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
	local selected = b.key == S.currentKey
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
			if not ok or (m.errorCount or 0) > 0 then
				b.dot:SetVertexColor(O:Color("danger"))
			elseif #XUI.Health.Issues(m) > 0 then
				b.dot:SetVertexColor(1, 0.8, 0.2)
			else
				b.dot:SetVertexColor(ar, ag, ab)
			end
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
		local ok, cards = pcall(build, O.ModuleContext(m), m, O.Groups)
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
	if S.searchText == "" then return true end
	for word in S.searchText:gmatch("%S+") do
		if not hay:find(word, 1, true) then return false end
	end
	return true
end

-- The index runs every module's options builder, so it is only built once
-- somebody searches, not when the window opens.
local function ModuleMatches(m, extra)
	if S.searchText == "" then return true end
	return Matches(ModuleWords(m) .. " " .. extra)
end

function O:RefreshSidebar()
	if not S.sidebar then return end
	local child = S.sidebar.child
	local y, ni, nh = 6, 0, 0
	wipe(S.entries)

	local function AddItem(key, title, icon, m, isMedia, indent, classToken)
		ni = ni + 1
		local b = SidebarItem(ni)
		b.key, b.module, b.classToken = key, m, classToken
		b.icon:ClearAllPoints()
		b.icon:SetPoint("LEFT", 16 + (indent or 0), 0)
		b.arrow:SetShown(classToken ~= nil)
		if classToken then
			b.arrow:SetRotation(S.expandedClass[classToken] and 0 or math.rad(90))
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
		S.entries[#S.entries + 1] = key
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
			local folded = XUI.DB.global.panel.classFolded and S.searchText == ""
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
					if ModuleMatches(m, c.name:lower()) then matching[#matching + 1] = m end
				end
				local classMatches = Matches(c.name:lower())
				-- a class nothing has been made for yet stays out of the list
				if #mods > 0 and (S.searchText == "" or classMatches or #matching > 0) then
					-- the class you play starts unfolded
					if S.expandedClass[c.token] == nil then S.expandedClass[c.token] = (c.token == XUI.playerClass) end
					AddItem("class:" .. c.token, c.name, c.icon, nil, false, 0, c.token)
					if S.searchText ~= "" or S.expandedClass[c.token] then
						for _, m in ipairs(S.searchText ~= "" and not classMatches and matching or mods) do
							AddItem(m.key, m.name, XUI.ModuleIcon(m), m, false, 14)
						end
					end
				end
			end
			list = {}
		else
		for _, m in ipairs(XUI:SortedModules(cat.key)) do
			if m:IsAvailable() and ModuleMatches(m, cat.name:lower()) then
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
	S.sidebar:UpdateBar()
end
