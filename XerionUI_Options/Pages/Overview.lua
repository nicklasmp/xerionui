--------------------------------------------------------------------------------
-- XerionUI_Options - Pages/Overview.lua
-- Every module on one page: switch it on or off, see at a glance whether it is
-- running (and why not), preview it, and jump to its settings.
--------------------------------------------------------------------------------
local XUI = _G.XerionUI
local O = XUI and XUI.Options
if not O then return end

local ROW_H = 30

local function ClassSuffix(m)
	if not m.classes then return "" end
	local names = {}
	for _, token in ipairs(m.classes) do
		local c = O.classByToken and O.classByToken[token]
		names[#names + 1] = c and c.name or token
	end
	return "  |cff777777" .. table.concat(names, ", ") .. "|r"
end

-- short text, colour and the full sentence for the tooltip
local function Status(m)
	if (m.errorCount or 0) > 0 then
		return "Errors", { O:Color("danger") }, ("%d Lua error(s); open the module and use Diagnostics."):format(m.errorCount)
	end
	if m.db.enabled then
		local ok, why = m:CanRun()
		if not ok then return "Not running", { O:Color("danger") }, why or "unknown reason" end
		local issues = XUI.Health.Issues(m)
		if #issues > 0 then return "Check", { 1, 0.8, 0.2 }, issues[1] end
		if m.running then return "Running", { O:Accent() }, "Running." end
		return "Starting", { O:Color("muted") }, "Enabled, starting."
	end
	return "Off", { O:Color("faint") }, "Switched off."
end

local function Row(parent, m)
	local r = CreateFrame("Button", nil, parent)
	r:SetHeight(ROW_H)
	r.module = m
	r.hover = O:Rect(r, "selected", "BACKGROUND")
	r.hover:SetAllPoints()
	r.hover:Hide()
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(18, 18)
	r.icon:SetPoint("LEFT", 4, 0)
	r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	-- right to left: open, preview, switch, status
	r.open = O:IconButton(r, "chevron", 24, "Open its settings", function() O:Open(m.key) end)
	r.open:SetPoint("RIGHT", -2, 0)
	r.open.icon:SetRotation(math.rad(-90))
	r.eye = O:IconButton(r, "eye", 24, "Preview", function() m:SetPreview(not m.preview) O:RefreshOverview() end)
	r.eye:SetPoint("RIGHT", r.open, "LEFT", -2, 0)
	r.toggle = CreateFrame("Button", nil, r)
	r.toggle:SetSize(44, 24)
	r.toggle:SetPoint("RIGHT", r.eye, "LEFT", -10, 0)
	r.switch = O.Switch(r.toggle)
	r.switch:SetPoint("CENTER")
	r.toggle:SetScript("OnClick", function() m:SetEnabled(not m.db.enabled) O:RefreshOverview() end)
	r.status = O:Text(r, O.SIZE.small, "muted")
	r.status:SetPoint("RIGHT", r.toggle, "LEFT", -10, 0)
	r.status:SetWidth(96)
	r.status:SetJustifyH("RIGHT")
	r.name = O:Text(r, O.SIZE.text, "label")
	r.name:SetPoint("LEFT", r.icon, "RIGHT", 10, 0)
	r.name:SetPoint("RIGHT", r.status, "LEFT", -10, 0)
	r.name:SetJustifyH("LEFT")

	r:SetScript("OnClick", function() O:Open(m.key) end)
	r:SetScript("OnEnter", function(self)
		self.hover:Show()
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(m.name, 1, 1, 1)
		local _, _, full = Status(m)
		GameTooltip:AddLine(full, 0.75, 0.75, 0.75, true)
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", function(self) self.hover:Hide() GameTooltip:Hide() end)
	return r
end

local function RefreshRow(r)
	local m = r.module
	r.icon:SetTexture(XUI.ModuleIcon(m))
	r.icon:SetDesaturated(not m.db.enabled)
	r.name:SetText(m.name .. ClassSuffix(m))
	local text, color = Status(m)
	r.status:SetText(text)
	r.status:SetTextColor(color[1], color[2], color[3])
	r.switch:SetState(m.db.enabled)
	if m.preview then r.eye:SetActive(true) else r.eye:SetActive(false) end
end

-- the list of modules of one category, as one control
local function ModuleList(category)
	return function(parent)
		local f = CreateFrame("Frame", nil, parent)
		f.rows = {}
		local mods = XUI:SortedModules(category)
		for i, m in ipairs(mods) do
			local r = Row(f, m)
			r:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(i - 1) * ROW_H)
			r:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -(i - 1) * ROW_H)
			f.rows[i] = r
		end
		f.height = math.max(1, #mods * ROW_H)
		f:SetHeight(f.height)
		function f:Refresh() for _, r in ipairs(self.rows) do RefreshRow(r) end end
		return f
	end
end

function O:RefreshOverview()
	local page = self:GetPageIfBuilt("overview")
	if page then page:Refresh() end
end

O:RegisterSystemPage({
	key = "overview",
	title = "Modules",
	icon = "layers",
	desc = "Every module at a glance: switch on, status, preview and settings.",
	root = function() return {} end,
	build = function()
		local cards = {}
		for _, cat in ipairs(XUI.CATEGORIES) do
			if #XUI:SortedModules(cat.key) > 0 then
				cards[#cards + 1] = O.Card(cat.name, { { type = "custom", build = ModuleList(cat.key), width = "full" } })
			end
		end
		return cards
	end,
})
