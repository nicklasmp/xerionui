--------------------------------------------------------------------------------
-- XerionUI_Options - Panel.lua
-- The window: header, sidebar (search, pages, modules by category) and the
-- page area with its header (icon, title, description, and for modules the
-- enable switch and preview).
--------------------------------------------------------------------------------
local XUI = _G.XerionUI
local O = XUI and XUI.Options
if not O then return end

local W, H = 980, 680
local SIDEBAR_W = 228
local HEADER_H = 50
local PAGEHEAD_H = 78
local ITEM_H = 28
O.LAYOUT = { SIDEBAR_W = SIDEBAR_W, HEADER_H = HEADER_H, PAGEHEAD_H = PAGEHEAD_H, ITEM_H = ITEM_H }

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

-- State the window, the sidebar, the page head and the preview helpers share.
local S = {
	entries = {},        -- sidebar entries in display order
	pages = {},          -- [key] = Page
	autoStarted = {},    -- modules whose preview the open page started
	expandedClass = {},  -- [class token] = unfolded in the sidebar
	docked = false,
	searchText = "",
}
O.S = S

--------------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------------
function O.ModuleContext(m)
	return O:NewContext(function() return m.db end, function(path)
		XUI:NotifySettingChanged(m, path)
	end, { module = m })
end

function O:GetPageIfBuilt(key) return S.pages[key] end

function O.ClassKey(key) return type(key) == "string" and key:match("^class:(.+)$") end

local function GetPage(key)
	if S.pages[key] then return S.pages[key] end
	local m = XUI:GetModule(key)
	local spec
	if O.ClassKey(key) then
		spec = O:ClassPageSpec(O.ClassKey(key))
	elseif m then
		local build = O.moduleBuilders[key]
		spec = {
			ctx = O.ModuleContext(m),
			build = function(ctx)
				local cards = {
					-- a module that is off says so, and can be switched on right here
					O.Card(nil, {
						{ type = "description", width = "full", color = "label",
							text = "This module is switched off. The preview shows it, but it does nothing in the game until you enable it." },
						{ type = "button", text = "Enable", primary = true,
							onClick = function() m:SetEnabled(true) O:RefreshPageHead() O:RefreshSidebar() if ctx.page then ctx.page:Refresh() end end },
					}, { hidden = function() return m.db.enabled end }),
					-- what the self-check found outside this addon
					O.Card("Needs attention", {
						{ type = "description", width = "full", color = "danger", text = function()
							local lines = {}
							for _, issue in ipairs(XUI.Health.Issues(m)) do lines[#lines + 1] = "- " .. issue end
							return table.concat(lines, "\n")
						end },
					}, { hidden = function() return #XUI.Health.Issues(m) == 0 end }),
				}
				local own
				if build then
					own = build(ctx, m, O.Groups)
				else
					own = { O.Card(nil, { { type = "description", text = "This module has no settings yet.", width = "full" } }) }
				end
				for _, c in ipairs(own) do cards[#cards + 1] = c end
				return cards
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
	S.pages[key] = O:CreatePage(S.content, spec)
	return S.pages[key]
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local function SavePosition()
	local point, _, relPoint, x, y = S.frame:GetPoint(1)
	XUI.DB.global.panel.point = { point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5) }
end

local function CreateWindow()
	S.frame = CreateFrame("Frame", "XUI_OptionsFrame", UIParent)
	S.frame:SetSize(W, H)
	S.frame:SetFrameStrata("HIGH")
	S.frame:SetToplevel(true)
	S.frame:SetClampedToScreen(true)
	S.frame:SetMovable(true)
	S.frame:EnableMouse(true)
	-- scale first: borders are sized in physical pixels of the final scale
	S.frame:SetScale(XUI.DB.global.panel.scale or 1)
	O:Skin(S.frame, "window", "line")
	tinsert(UISpecialFrames, "XUI_OptionsFrame")

	local p = XUI.DB.global.panel.point
	if type(p) == "table" and p[1] then
		S.frame:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
	else
		S.frame:SetPoint("CENTER")
	end

	-- header
	local header = CreateFrame("Frame", nil, S.frame)
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
	header:SetScript("OnDragStart", function() S.frame:StartMoving() end)
	header:SetScript("OnDragStop", function()
		S.frame:StopMovingOrSizing()
		SavePosition()
	end)

	local title = O:Text(header, 17, "text")
	title:SetPoint("LEFT", 20, 0)
	title:SetText(XUI.TITLE)
	local version = O:Text(header, O.SIZE.small, "faint")
	version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 1)
	version:SetText(XUI.version)

	local close = O:IconButton(header, "close", 30, nil, function() S.frame:Hide() end)
	close:SetPoint("RIGHT", -10, 0)
	local unlock = O:IconButton(header, "move", 30, "Unlock frames", function()
		S.frame:Hide()
		XUI:SetUnlocked(true)
	end)
	unlock:SetPoint("RIGHT", close, "LEFT", -4, 0)

	-- sidebar
	local side = CreateFrame("Frame", nil, S.frame)
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
		S.searchText = (self:GetText() or ""):lower()
		hint:SetShown(S.searchText == "")
		O:RefreshSidebar()
	end)
	search:SetScript("OnEscapePressed", function(self)
		if self:GetText() ~= "" then self:SetText("") else self:ClearFocus() end
	end)
	search:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		if S.entries[1] then O:Open(S.entries[1]) end
	end)

	local list = CreateFrame("Frame", nil, side)
	list:SetPoint("TOPLEFT", 0, -50)
	list:SetPoint("BOTTOMRIGHT", -1, 8)
	S.sidebar = O:CreateScroll(list)
	S.sidebar:SetAllPoints(list)

	-- content
	S.content = CreateFrame("Frame", nil, S.frame)
	S.content:SetPoint("TOPLEFT", SIDEBAR_W, -(HEADER_H + PAGEHEAD_H))
	S.content:SetPoint("BOTTOMRIGHT", 0, 1)
	S.pageHead = O.CreatePageHead(S.frame)
	S.pageHead:SetPoint("TOPLEFT", SIDEBAR_W, -HEADER_H)
	S.pageHead:SetPoint("TOPRIGHT", 0, -HEADER_H)

	S.frame:SetScript("OnHide", function()
		O.CloseDropdown()
		for _, m in ipairs(XUI.modules) do m:SetPreview(false) end
		wipe(S.autoStarted)
		if S.docked then S.docked = false end
	end)

	local owner = {}
	XUI:On("ProfileChanged", owner, function()
		if not S.frame:IsShown() then return end
		for _, page in pairs(S.pages) do page:Refresh() end
		O:RefreshSidebar()
		O:RefreshPageHead()
	end)
	XUI:On("ModuleStateChanged", owner, function()
		if S.frame:IsShown() then O:RefreshSidebar() O:RefreshPageHead() O:RefreshOverview() end
	end)
	XUI:On("PreviewChanged", owner, function()
		if S.frame:IsShown() then O:RefreshPageHead() S.UpdateDockSoon() O:RefreshOverview() end
	end)
	XUI:On("ModuleError", owner, function()
		if S.frame:IsShown() then O:RefreshPageHead() O:RefreshSidebar() O:RefreshOverview() end
	end)
end

function O:Open(key)
	if not S.frame then CreateWindow() end
	key = key or S.currentKey or (O.systemPages[1] and O.systemPages[1].key)
	if XUI:GetModule(key) == nil and not (O.ClassKey(key) and O.classByToken[O.ClassKey(key)]) then
		local found = false
		for _, s in ipairs(O.systemPages) do if s.key == key then found = true end end
		if not found then key = O.systemPages[1].key end
	end
	if S.currentKey and S.pages[S.currentKey] and S.currentKey ~= key then S.pages[S.currentKey]:Hide() end
	S.currentKey = key
	S.frame:Show()
	O.SyncAutoPreview(key)
	S.UpdateDockSoon()
	O:RefreshSidebar()
	O:RefreshPageHead()
	local page = GetPage(key)
	if page then page:Show() end
end

function O:Close()
	if S.frame then S.frame:Hide() end
end

function O:IsShown()
	return S.frame and S.frame:IsShown() or false
end

-- Rebuilds every page (after the panel font or accent changed).
function O:RebuildAll()
	for _, page in pairs(S.pages) do page:Rebuild() end
	O:RefreshSidebar()
	O:RefreshPageHead()
end
