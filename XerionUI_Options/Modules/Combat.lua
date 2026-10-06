--------------------------------------------------------------------------------
-- XerionUI_Options - Modules/Combat.lua
-- Options for the Combat category.
--------------------------------------------------------------------------------
local XUI = _G.XerionUI
local O = XUI and XUI.Options
if not O then return end

local Card, Join = O.Card, O.Join

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

O:RegisterModuleOptions("DispelAlert", function(ctx, m, G)
	return {
		Card("Triggers", {
			{ type = "description", width = "full", text = "Shows when one of your own dispels, purges, soothes or steals removes an aura (magic, curse, poison, disease, bleed, enrage). A cast that removes nothing stays silent." },
			{ type = "toggle", label = "Friendly targets (dispel)", path = "friendly" },
			{ type = "toggle", label = "Enemy targets (purge, soothe, steal)", path = "enemy" },
		}),
		Card("Message", {
			{ type = "input", label = "Text", path = "text", width = "full",
				tip = "%s is replaced by the name of the aura that was removed." },
			{ type = "input", label = "Text when the name is hidden", path = "textUnknown", width = "full",
				tip = "Used where the game hides aura names (some combat situations in instances)." },
			{ type = "color", label = "Ability name color", path = "nameColor" },
			{ type = "slider", label = "Show for (seconds)", path = "hold", min = 0.5, max = 8, step = 0.5 },
			{ type = "slider", label = "Fade out (seconds)", path = "fade", min = 0, max = 3, step = 0.1 },
		}),
		Card("Icon", {
			{ type = "toggle", label = "Show the ability icon", path = "showIcon" },
			{ type = "slider", label = "Icon size", path = "iconSize", min = 12, max = 80, step = 1,
				disabled = function() return not m.db.showIcon end },
		}),
		Card("Text", G.Font("font", { color = true })),
		Card("Alert", G.Alert("alert", { fallbackHint = "Leave empty to speak \"<ability> dispelled\"." })),
		Card("Position", G.Position("position")),
	}
end)

O:RegisterModuleOptions("MeleeIndicator", function(ctx, m, G)
	return {
		Card("Marker", {
			{ type = "input", label = "Text", path = "text" },
			{ type = "color", label = "Color", path = "color" },
			{ type = "slider", label = "Check every (seconds)", path = "interval", min = 0.1, max = 1, step = 0.05 },
			{ type = "toggle", label = "Pulse", path = "pulse", tip = "Fades the marker in and out so it is harder to miss." },
			{ type = "slider", label = "Pulse speed (seconds per fade)", path = "pulseSpeed", min = 0.15, max = 1.5, step = 0.05,
				disabled = function() return not m.db.pulse end },
		}),
		Card("Text", G.Font("font")),
		Card("Alert", Join(G.Alert("alert", { fallbackText = "Out of range" }), {
			{ type = "slider", label = "Repeat every (seconds, 0 = once)", path = "repeatEvery", min = 0, max = 10, step = 1,
				disabled = function() return m.db.alert.mode == "NONE" end },
			{ type = "description", width = "full", text = "Plays when you step out of melee range of your target. Where the game hides the range answer (inside a key or a boss fight) the marker still works, but only the game can tell, so no sound plays there." },
		})),
		Card("Position", G.Position("position")),
	}
end)
