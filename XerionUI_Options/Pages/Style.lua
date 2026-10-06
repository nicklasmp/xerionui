--------------------------------------------------------------------------------
-- XerionUI_Options - Pages/Style.lua
-- The global look: one place to set the font, borders, glows, bars,
-- backgrounds and icon crop every module follows, with a live sample.
--------------------------------------------------------------------------------
local XUI = _G.XerionUI
local O = XUI and XUI.Options
if not O then return end

local Widgets = XUI.Widgets

-- A text, an icon and a bar drawn with the current global style.
local function BuildSample(parent)
	local f = CreateFrame("Frame", nil, parent)
	f.height = 96
	f:SetHeight(f.height)

	f.icon = Widgets:CreateIcon(nil, f)
	f.icon:SetIcon(XUI.GetSpellIcon(20594, 132275))
	f.icon:SetPoint("LEFT", 20, 0)

	f.bar = Widgets:CreateBar(nil, f)
	f.bar:SetPoint("LEFT", f.icon, "RIGHT", 40, 10)
	f.bar.bar:SetValue(0.62)
	f.bar.icon:SetTexture(XUI.GetSpellIcon(2825, 136012))

	f.text = Widgets:CreateText(nil, f)
	f.text:SetPoint("TOPLEFT", f.bar, "BOTTOMLEFT", 0, -12)

	function f:Refresh()
		self.icon:ApplyLayout({ width = 48, height = 48 }, nil)
		self.icon:ApplyCountText({ size = 13, anchor = "BOTTOMRIGHT", x = -2, y = 2 })
		self.icon.count:SetText("3")
		self.icon:ApplyTimerText({ size = 16 })
		self.icon.timer:SetText("8")
		self.icon:SetGlow(nil, true)

		self.bar:ApplyLayout({ width = 240, height = 22 }, nil, "LEFT")
		self.bar:SetColor(XUI.UnpackColor(XUI.DB.global.accent))
		self.bar:ApplyNameText({ size = 12 })
		self.bar:ApplyTimeText({ size = 12 })
		self.bar.name:SetText("Bloodlust")
		self.bar.time:SetText("24.6")

		self.text:ApplyStyle({ size = 20 })
		self.text:SetText("Sample alert text")
		self.text:SetTextColor(1, 1, 1, 1)
	end
	f:SetScript("OnHide", function(self) XUI.Style:HideGlow(self.icon) end)
	f:SetScript("OnShow", function(self) self:Refresh() end)
	return f
end

-- text typed into the themes card; not a setting
local scratch = { name = "", pick = "" }

local function ThemeValues()
	local out = {}
	for _, name in ipairs(XUI.DB:ListThemes()) do out[#out + 1] = { value = name, text = name } end
	return out
end

StaticPopupDialogs.XERIONUI_THEME_CONFIRM = {
	text = "%s",
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, fn) fn() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

O:RegisterSystemPage({
	key = "style",
	title = "Global Style",
	icon = "drop",
	desc = "The look every module follows unless you style it on its own.",
	root = function() return XUI.DB.style end,
	onChange = function()
		XUI.Style:Invalidate()
		XUI:Fire("StyleChanged")
	end,
	build = function(ctx, G)
		return {
			O.Card("Sample", { { type = "custom", build = BuildSample, width = "full" } }),
			O.Card("Themes", {
				{ type = "description", width = "full", text = "Save the whole global style under a name and bring it back in any profile." },
				{ type = "dropdown", label = "Saved themes", values = ThemeValues,
					get = function() return scratch.pick end, set = function(_, v) scratch.pick = v end },
				{
					type = "button", text = "Apply",
					disabled = function() return scratch.pick == "" or not XUI.DB.global.themes[scratch.pick] end,
					onClick = function()
						if XUI.DB:ApplyTheme(scratch.pick) then
							XUI.Style:Invalidate()
							XUI:Fire("StyleChanged")
							if ctx.page then ctx.page:Refresh() end
						end
					end,
				},
				{
					type = "button", text = "Delete",
					disabled = function() return scratch.pick == "" or not XUI.DB.global.themes[scratch.pick] end,
					onClick = function()
						local name = scratch.pick
						StaticPopup_Show("XERIONUI_THEME_CONFIRM", ("Delete the theme '%s'?"):format(name), nil, function()
							XUI.DB:DeleteTheme(name)
							scratch.pick = ""
							if ctx.page then ctx.page:Refresh() end
						end)
					end,
				},
				{ type = "input", label = "Save the current style as", get = function() return scratch.name end, set = function(_, v) scratch.name = v end },
				{
					type = "button", text = "Save theme", primary = true,
					disabled = function() return scratch.name == "" end,
					onClick = function()
						if XUI.DB:SaveTheme(scratch.name) then
							scratch.pick, scratch.name = scratch.name, ""
							if ctx.page then ctx.page:Refresh() end
						end
					end,
				},
			}),
			O.Card("Font", G.Font("font", { global = true })),
			O.Card("Border", G.Border("border", { global = true })),
			O.Card("Glow", G.Glow("glow", { global = true })),
			O.Card("Bars", G.Bar("bar", { global = true })),
			O.Card("Backgrounds", G.Background("background", { global = true })),
			O.Card("Icons", G.Icon("icon", { global = true })),
		}
	end,
})
