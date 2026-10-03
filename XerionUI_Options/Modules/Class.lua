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

O:RegisterModuleOptions("Blightfall", function(ctx, m, G)
	return {
		Card("Timings", {
			{ type = "slider", label = "Dark Transformation to Soul Reaper (s)", path = "delaySR", min = 0, max = 30, step = 0.5 },
			{ type = "slider", label = "Soul Reaper to Blightfall (s)", path = "delayBF", min = 0, max = 30, step = 0.5 },
			{ type = "dropdown", label = "Decimals", path = "decimals", values = { { value = 1, text = "One" }, { value = 0, text = "None" } } },
		}),
		Card("Voice", {
			{ type = "toggle", label = "Count out loud", path = "voice", width = "full",
				tip = "Says the spell five seconds out, then 3, 2, 1 and Now, with the game's text-to-speech voice." },
			{ type = "button", text = "Test", onClick = function() m:TestVoice() end },
			{ type = "description", width = "full", text = "An extra alert can play when the countdown reaches Now." },
		}),
		Card("Alert at Now", G.Alert("alert")),
		Card("Grow", {
			{ type = "toggle", label = "Grow the icon as the countdown ends", path = "growPulse", width = "full" },
			{ type = "slider", label = "Start growing at (s)", path = "growStart", min = 1, max = 10, step = 0.5 },
			{ type = "slider", label = "Largest scale", path = "growMax", min = 1, max = 3, step = 0.1 },
		}),
		Card("Icon", G.Icon("icon", { square = true })),
		Card("Border", G.Border("border")),
		Card("Glow in the last seconds", G.Glow("glow")),
		Card("Countdown text", G.Font("timerText", { toggle = "Show countdown", anchor = true })),
		Card("Position", G.Position("position")),
	}
end)

O:RegisterModuleOptions("WellHoned", function(ctx, m, G)
	return {
		Card("Sounds", {
			{ type = "dropdown", label = "When the lockout lands", path = "sound", media = "sound", filesOnly = true },
			{ type = "button", text = "Test", onClick = function() m:Test("sound") end },
			{ type = "dropdown", label = "When it ends", path = "endSound", media = "sound", filesOnly = true },
			{ type = "button", text = "Test", onClick = function() m:Test("endSound") end },
			{ type = "dropdown", label = "Channel", path = "channel", values = XUI.Audio.CHANNELS },
			{ type = "description", width = "full", text = "Played by the game itself, so it works in keys and raid encounters. A new sound is registered when the fight or the encounter ends." },
		}),
	}
end)

O:RegisterModuleOptions("BearForm", function(ctx, m, G)
	return {
		Card("Text", Join({
			{ type = "input", label = "Text", path = "text" },
			{ type = "color", label = "Color", path = "color" },
		}, G.Font("font"))),
		Card("Position", G.Position("position")),
	}
end)

O:RegisterModuleOptions("SpellReflect", function(ctx, m, G)
	return {
		Card("Text", Join(G.Font("font"), {
			{ type = "color", label = "Label colour", path = "labelColor" },
			{ type = "color", label = "Value colour", path = "valueColor" },
		})),
		Card("Learned spells", {
			{ type = "description", width = "full", text = "Which damage lines are yours is learned after fights without a reflect, per character." },
			{ type = "button", text = "Forget learned spells", onClick = function() m:Forget() end },
		}),
		Card("Position", G.Position("position")),
	}
end)

O:RegisterModuleOptions("PaladinAura", function(ctx, m, G)
	return {
		Card("When", {
			{ type = "toggle", label = "Only in Mythic+", path = "mplusOnly", width = "full" },
		}),
		Card("Icon", G.Icon("icon", { square = true })),
		Card("Border", G.Border("border")),
		Card("Text", Join(G.Font("text", { color = true }), {
			{ type = "dropdown", label = "Placed", path = "textSide", values = m.SIDES },
			{ type = "slider", label = "Offset X", path = "textX", min = -60, max = 60, step = 1 },
			{ type = "slider", label = "Offset Y", path = "textY", min = -60, max = 60, step = 1 },
		})),
		Card("Position", G.Position("position")),
	}
end)

O:RegisterModuleOptions("ElementalBlast", function(ctx, m, G)
	return {
		Card("Letters", Join({
			{ type = "color", label = "Critical Strike (C)", path = "critColor" },
			{ type = "color", label = "Haste (H)", path = "hasteColor" },
			{ type = "color", label = "Mastery (M)", path = "masteryColor" },
			{ type = "slider", label = "Height above the icon", path = "offsetY", min = -20, max = 30, step = 1 },
		}, G.Font("font"))),
		Card("Preview position", G.Position("position")),
	}
end)

O:RegisterModuleOptions("AlterTime", function(ctx, m, G)
	return {
		Card("Text", G.Font("font", { color = true })),
		Card("Placement", {
			{ type = "toggle", label = "Hang it on the Cooldown Manager's Alter Time icon", path = "anchorCDM", width = "full" },
			{ type = "slider", label = "Offset X", path = "anchorX", min = -60, max = 60, step = 1 },
			{ type = "slider", label = "Offset Y", path = "anchorY", min = -60, max = 60, step = 1 },
		}),
		Card("Position (when not on the icon)", G.Position("position")),
	}
end)
