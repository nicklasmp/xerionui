--------------------------------------------------------------------------------
-- XerionUI_Options - Modules/General.lua
-- Options for the General category.
--------------------------------------------------------------------------------
local XUI = _G.XerionUI
local O = XUI and XUI.Options
if not O then return end

local Card, Join = O.Card, O.Join

O:RegisterModuleOptions("CombatAlert", function(ctx, m, G)
	return {
		Card("Messages", {
			{ type = "input", label = "Entering combat", path = "enterText" },
			{ type = "color", label = "Color", path = "enterColor" },
			{ type = "input", label = "Leaving combat", path = "leaveText" },
			{ type = "color", label = "Color", path = "leaveColor" },
			{ type = "slider", label = "Show for (seconds)", path = "hold", min = 0.5, max = 5, step = 0.1 },
			{ type = "slider", label = "Fade out (seconds)", path = "fade", min = 0, max = 3, step = 0.1 },
		}),
		Card("Text", G.Font("text")),
		Card("Alert on entering combat", G.Alert("enterAlert", {
			test = function() XUI.Audio:Play(m.db.enterAlert, m.db.enterText, true) end,
		})),
		Card("Alert on leaving combat", G.Alert("leaveAlert", {
			test = function() XUI.Audio:Play(m.db.leaveAlert, m.db.leaveText, true) end,
		})),
		Card("Position", G.Position("position")),
	}
end)

O:RegisterModuleOptions("CombatTimer", function(ctx, m, G)
	return {
		Card("Timer", {
			{ type = "dropdown", label = "Format", path = "format", values = m.FORMATS },
			{
				type = "slider", label = "Keep after combat (seconds)", path = "linger", min = 0, max = 30, step = 1,
				tip = "How long the final time stays on screen after combat ends. 0 hides it at once.",
			},
		}),
		Card("Text", G.Font("text", { color = true })),
		Card("Position", G.Position("position")),
	}
end)
