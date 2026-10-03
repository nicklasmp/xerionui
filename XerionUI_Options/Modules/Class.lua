--------------------------------------------------------------------------------
-- XerionUI_Options - Modules/Class.lua
-- Options for the Class category.
--------------------------------------------------------------------------------
local XUI = _G.XerionUI
local O = XUI and XUI.Options
if not O then return end

local Card, Join = O.Card, O.Join

O:RegisterModuleOptions("BoneShield", function(ctx, m, G)
	return {
		Card("When", {
			{ type = "slider", label = "Glow with seconds left", path = "glowThreshold", min = 1, max = 20, step = 1 },
			{ type = "toggle", label = "Warn under 5 stacks", path = "stackWarn",
				tip = "In keys the stack count is hidden: put Ossuary on a Cooldown Manager buff bar for this to work there." },
			{ type = "slider", label = "Sound with seconds left", path = "soundThreshold", min = 1, max = 20, step = 1 },
			{ type = "toggle", label = "Sound only in combat", path = "soundInCombatOnly" },
			{ type = "slider", label = "Bone Shield duration (fallback)", path = "duration", min = 10, max = 60, step = 1 },
			{ type = "toggle", label = "Custom Bone Shield icon art", path = "customArt" },
		}),
		Card("Glow", G.Glow("glow")),
		Card("Alert", G.Alert("alert")),
		Card("Diagnostics", {
			{ type = "button", text = "Print status", onClick = function() m:PrintStatus() end },
			{ type = "button", text = "Forget learned spells", onClick = function() m:ForgetLearned() end },
		}),
	}
end)

O:RegisterModuleOptions("DRWSound", function(ctx, m, G)
	return {
		Card("When", {
			{ type = "toggle", label = "When it is extended", path = "onRefresh" },
			{ type = "toggle", label = "When it starts", path = "onGain" },
			{ type = "description", width = "full", text = "Dancing Rune Weapon must be on a Cooldown Manager bar." },
		}),
		Card("Alert", G.Alert("alert", { test = function() m:TestAlert() end })),
	}
end)

O:RegisterModuleOptions("BoilingPoint", function(ctx, m, G)
	return {
		Card("Bar", Join(G.Bar("bar", { color = true }), {
			{ type = "toggle", label = "Also a bar while the proc is up", path = "procBar" },
			{ type = "color", label = "Proc bar colour", path = "procColor" },
		})),
		Card("Border", G.Border("border")),
		Card("Timer text", G.Font("timerText", { toggle = "Show timer" })),
		Card("Glow while Blood Boil is lit", G.Glow("procGlow")),
		Card("Position", G.Position("position")),
	}
end)

--------------------------------------------------------------------------------
-- Shared card sets
--------------------------------------------------------------------------------
-- The cards of a Kit.TimedIcon module; `extra` cards are put first.
local function TimedIconCards(G, extra, glow)
	local cards = {}
	for _, c in ipairs(extra or {}) do cards[#cards + 1] = c end
	cards[#cards + 1] = Card("Icon", Join(G.Icon("icon", { square = true }), {
		{ type = "toggle", label = "Cooldown swipe", path = "showSwipe" },
	}))
	cards[#cards + 1] = Card("Border", G.Border("border"))
	if glow then cards[#cards + 1] = Card("Glow", G.Glow("glow")) end
	cards[#cards + 1] = Card("Timer text", G.Font("timerText", { toggle = "Show timer", color = true }))
	cards[#cards + 1] = Card("Position", G.Position("position"))
	return cards
end

O:RegisterModuleOptions("BloodIsLife", function(ctx, m, G)
	return TimedIconCards(G, nil, true)
end)

O:RegisterModuleOptions("BloodBeast", function(ctx, m, G)
	return {
		Card("Text", Join(G.Font("font"), {
			{ type = "color", label = "Label colour", path = "labelColor" },
			{ type = "color", label = "Value colour", path = "valueColor" },
		})),
		Card("Position", G.Position("position")),
	}
end)

O:RegisterModuleOptions("ControlUndead", function(ctx, m, G)
	return TimedIconCards(G, {
		Card("When", {
			{ type = "toggle", label = "Hide when the minion is gone", path = "hideOnPetLost" },
			{ type = "slider", label = "Warn colour with seconds left", path = "warnAt", min = 0, max = 120, step = 5 },
			{ type = "color", label = "Warn colour", path = "warnColor" },
		}),
	})
end)
