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
