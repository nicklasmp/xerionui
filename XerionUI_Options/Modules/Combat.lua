--------------------------------------------------------------------------------
-- XerionUI_Options - Modules/Combat.lua
-- Options for the Combat category.
--------------------------------------------------------------------------------
local XUI = _G.XerionUI
local O = XUI and XUI.Options
if not O then return end

local Card = O.Card

O:RegisterModuleOptions("Stoneform", function(ctx, m, G)
	return {
		Card("Icon", G.Icon("icon", { square = true })),
		Card("Border", G.Border("border")),
		Card("Glow", G.Glow("glow")),
		Card("Alert", G.Alert("alert", {
			label = "Alert when a bleed appears",
			fallbackText = "Bleed detected",
		})),
		Card("Position", G.Position("position")),
	}
end)

O:RegisterModuleOptions("MeleeIndicator", function(ctx, m, G)
	return {
		Card("Marker", {
			{ type = "input", label = "Text", path = "text" },
			{ type = "color", label = "Color", path = "color" },
			{ type = "slider", label = "Check every (seconds)", path = "interval", min = 0.1, max = 1, step = 0.05 },
		}),
		Card("Text", G.Font("font")),
		Card("Position", G.Position("position")),
	}
end)
