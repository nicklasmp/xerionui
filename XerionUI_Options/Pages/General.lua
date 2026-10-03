--------------------------------------------------------------------------------
-- XerionUI_Options - Pages/General.lua
-- Account-wide settings: the panel itself, unlock mode, and credits.
--------------------------------------------------------------------------------
local XUI = _G.XerionUI
local O = XUI and XUI.Options
if not O then return end

O:RegisterSystemPage({
	key = "general",
	title = "General",
	icon = "sliders",
	desc = "Settings for the addon itself. They apply to every profile.",
	root = function() return XUI.DB.global end,
	onChange = function(path)
		if path == "panel.scale" then
			local f = _G.XUI_OptionsFrame
			if f then f:SetScale(XUI.DB.global.panel.scale) end
		elseif path == "accent" then
			O:RefreshSidebar()
			O:RefreshPageHead()
		end
	end,
	build = function(ctx, G)
		return {
			O.Card("Window", {
				{ type = "color", label = "Accent color", path = "accent", hasAlpha = false },
				{ type = "spacer" },
				{ type = "slider", label = "Scale", path = "panel.scale", min = 0.7, max = 1.5, step = 0.05 },
				{
					type = "dropdown", label = "Font", path = "panel.font", media = "font",
					tip = "Applies the next time you log in or /reload.",
				},
			}),
			O.Card("Unlock mode", {
				{ type = "toggle", label = "Snap to grid while dragging", path = "unlock.snap" },
				{ type = "slider", label = "Grid size", path = "unlock.gridSize", min = 8, max = 128, step = 4 },
				{ type = "button", text = "Unlock frames", onClick = function() XUI:SetUnlocked(true) end },
			}),
			O.Card("Chat", {
				{ type = "toggle", label = "Show a message when the addon loads", path = "loginMessage", width = "full" },
			}),
			O.Card("About", {
				{
					type = "description", width = "full", size = O.SIZE.text, color = "label",
					text = function()
						return ("%s %s\nA personal quality-of-life and tweak suite for World of Warcraft: Midnight.\n\n"
							.. "Type |cffffffff/xui|r to open this window and |cffffffff/xui unlock|r to move frames.\n\n"
							.. "Some features are ported from ItruliaQoL by Itrulia (MIT licence)."):format(XUI.TITLE, XUI.version)
					end,
				},
			}),
		}
	end,
})
