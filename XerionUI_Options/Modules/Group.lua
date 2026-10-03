--------------------------------------------------------------------------------
-- XerionUI_Options - Modules/Group.lua
-- Options for the Group category.
--------------------------------------------------------------------------------
local XUI = _G.XerionUI
local O = XUI and XUI.Options
if not O then return end

local Card, Join = O.Card, O.Join

local function IS121() return XUI.IS_121 end

--------------------------------------------------------------------------------
O:RegisterModuleOptions("DeathAlert", function(ctx, m, G)
	local function roleRow(role, label)
		return {
			{ type = "toggle", label = label .. ": show", path = "roles." .. role .. ".show" },
			{ type = "toggle", label = label .. ": alert", path = "roles." .. role .. ".alert" },
		}
	end
	return {
		Card("Message", {
			{ type = "input", label = "Text after the name", path = "suffix" },
			{ type = "color", label = "Color", path = "suffixColor" },
			{ type = "slider", label = "Show for (seconds)", path = "hold", min = 0.5, max = 8, step = 0.5 },
			{ type = "slider", label = "Fade out (seconds)", path = "fade", min = 0, max = 3, step = 0.1 },
		}),
		Card("Text", G.Font("text")),
		Card("Alert", G.Alert("alert", { fallbackHint = "Leave empty to speak \"<name> died\"." })),
		Card("Names", {
			{ type = "description", width = "full", text = "Comma separated. With a whitelist only those names alert; otherwise the blacklist names are skipped. Names hidden in combat always alert." },
			{ type = "input", label = "Whitelist", path = "whitelist" },
			{ type = "input", label = "Blacklist", path = "blacklist" },
		}),
		Card("Raid roles", Join(
			{ { type = "description", width = "full", text = "In a raid, what each role's deaths do." } },
			roleRow("TANK", "Tanks"), roleRow("HEALER", "Healers"), roleRow("DAMAGER", "Damage")
		)),
		Card("Position", G.Position("position")),
	}
end)

--------------------------------------------------------------------------------
O:RegisterModuleOptions("Externals", function(ctx, m, G)
	return {
		Card("Layout", {
			{ type = "dropdown", label = "Grow", path = "grow", values = m.GROW },
			{ type = "slider", label = "Spacing", path = "spacing", min = 0, max = 20, step = 1 },
		}),
		Card("Icon", G.Icon("icon", { square = true })),
		Card("Border", G.Border("border")),
		Card("Glow", G.Glow("glow")),
		Card("Timer text", G.Font("timerText", { toggle = "Show timer", anchor = true })),
		Card("Alert", Join(
			{ {
				type = "description", width = "full",
				text = function()
					if IS121() then return "On this client the sound is played by the game itself for the spells below; text to speech is not available here." end
					return "Plays when a new external lands on you."
				end,
			} },
			G.Alert("alert", { test = function() m:TestAlert() end })
		)),
		Card("Sound for these spells", {
			{ type = "spellList", path = "soundSpells", width = "full" },
		}, { hidden = function() return not IS121() end }),
		Card("Position", G.Position("position")),
	}
end)

--------------------------------------------------------------------------------
O:RegisterModuleOptions("Interrupts", function(ctx, m, G)
	local function barMode() return m.db.displayMode == "icon" end
	local function iconMode() return m.db.displayMode ~= "icon" end
	return {
		Card("Show", {
			{ type = "dropdown", label = "Display", path = "displayMode", values = m.MODES },
			{ type = "dropdown", label = "Icon shows", path = "iconSource", values = m.ICON_SOURCES,
				tip = "The interrupted spell is shown for as long as the bar runs, so you can see which cast was handled." },
			{ type = "toggle", label = "Your own interrupt", path = "showSelf" },
			{ type = "toggle", label = "Ready interrupts too", path = "showReady" },
			{ type = "toggle", label = "Only in a group", path = "groupOnly" },
			{ type = "toggle", label = "Hide in raids", path = "hideInRaid" },
			{ type = "toggle", label = "Raid marker of the kicked mob", path = "showMark", hidden = barMode },
			{ type = "toggle", label = "Icon", path = "showIcon", hidden = barMode },
			{ type = "toggle", label = "Timer", path = "showTimer", hidden = barMode },
		}),
		Card("Bars", Join(G.Bar("bar"), {
			{ type = "dropdown", label = "Grow", path = "growth", values = m.GROWTH },
			{ type = "slider", label = "Spacing", path = "spacing", min = 0, max = 20, step = 1 },
			{ type = "slider", label = "Gap between icon and bar", path = "iconGap", min = 0, max = 10, step = 1 },
			{ type = "slider", label = "Background opacity", path = "bgAlpha", min = 0, max = 1, step = 0.05 },
		}), { hidden = barMode }),
		Card("Icons on party frames", Join(G.Icon("icon", { square = true }), {
			{ type = "dropdown", label = "Side", path = "partySide", values = m.SIDES },
			{ type = "slider", label = "Gap", path = "partyGap", min = 0, max = 20, step = 1 },
			{ type = "description", width = "full", text = "Placed beside each member's EllesmereUI party frame; without EllesmereUI they stack at the position below." },
		}), { hidden = iconMode }),
		Card("Border", G.Border("border")),
		Card("Name text", G.Font("nameText"), { hidden = barMode }),
		Card("Timer text", G.Font("timerText"), { hidden = barMode }),
		Card("Detection", {
			{ type = "toggle", label = "Watch interrupted casts", path = "observe",
				tip = "Starts a member's bar when an enemy's cast is interrupted, even when the client hides who did it." },
			{ type = "toggle", label = "Confirm with the damage meter", path = "meterConfirm",
				tip = "Pairs each interrupted cast with the damage meter's interrupt list to tell who kicked." },
			{ type = "slider", label = "Unknown interrupt cooldown", path = "partyCd", min = 5, max = 60, step = 1 },
			{ type = "button", text = "Print status", onClick = function() m:PrintStatus() end },
		}),
		Card("Position", G.Position("position")),
	}
end)

--------------------------------------------------------------------------------
O:RegisterModuleOptions("CoTank", function(ctx, m, G)
	local function noDebuffs() return not m.db.debuffs.enabled end
	return {
		Card("Who", {
			{ type = "toggle", label = "Only while you are tank-specced", path = "tankOnly", width = "full" },
			{ type = "input", label = "Always show this player", path = "pinName",
				tip = "Leave empty to find the other tank automatically." },
			{
				type = "button", text = function() return m.testMode and "Stop test" or "Test on your target" end,
				tip = "Puts the live bar and the real debuff row on your target (or you), no raid needed.",
				onClick = function() m:SetTest(not m.testMode) end,
				disabled = function() return not m.running end,
			},
		}),
		Card("Bar", Join(G.Bar("bar"), {
			{ type = "slider", label = "Background opacity", path = "bgAlpha", min = 0, max = 1, step = 0.05 },
		})),
		Card("Border", G.Border("border")),
		Card("Name text", G.Font("nameText", { toggle = "Show name", anchor = true })),
		Card("Health text", G.Font("healthText", { toggle = "Show health %", anchor = true })),
		Card("Debuffs", {
			{ type = "toggle", label = "Show debuffs", path = "debuffs.enabled" },
			{ type = "toggle", label = "Boss and role debuffs only", path = "debuffs.bossOnly", disabled = noDebuffs },
			{ type = "slider", label = "How many", path = "debuffs.max", min = 1, max = 10, step = 1, disabled = noDebuffs },
			{ type = "slider", label = "Spacing", path = "debuffs.spacing", min = 0, max = 20, step = 1, disabled = noDebuffs },
			{ type = "dropdown", label = "Grow", path = "debuffs.grow", values = m.GROW, disabled = noDebuffs },
			{ type = "dropdown", label = "Attach to bar", path = "debuffs.attach", values = XUI.Style.ANCHORS, disabled = noDebuffs },
			{ type = "slider", label = "Offset X", path = "debuffs.x", min = -100, max = 100, step = 1, disabled = noDebuffs },
			{ type = "slider", label = "Offset Y", path = "debuffs.y", min = -100, max = 100, step = 1, disabled = noDebuffs },
			{ type = "toggle", label = "Dispel-colour border", path = "debuffs.dispelBorder", disabled = noDebuffs },
			{ type = "slider", label = "Border thickness (pixels)", path = "debuffs.borderSize", min = 1, max = 6, step = 1, disabled = noDebuffs },
			{ type = "toggle", label = "Tooltip on hover", path = "debuffs.tooltip", disabled = noDebuffs },
		}),
		Card("Debuff icons", G.Icon("debuffIcon", { square = true }), { hidden = noDebuffs }),
		Card("Debuff timer", G.Font("durText", { toggle = "Show timer", anchor = true }), { hidden = noDebuffs }),
		Card("Debuff stacks", G.Font("stackText", { toggle = "Show stacks", anchor = true }), { hidden = noDebuffs }),
		Card("Position", G.Position("position")),
	}
end)

--------------------------------------------------------------------------------
O:RegisterModuleOptions("Shroud", function(ctx, m, G)
	return {
		Card("Bars", {
			{ type = "toggle", label = "Mass Invisibility", path = "showMassInvis" },
			{ type = "color", label = "Color", path = "miColor" },
			{ type = "toggle", label = "Shroud of Concealment", path = "showShroud" },
			{ type = "color", label = "Color", path = "color" },
			{ type = "toggle", label = "Your own Shroud when you are the rogue", path = "selfBar", width = "full" },
		}),
		Card("Bar", Join(G.Bar("bar"), {
			{ type = "toggle", label = "Icon", path = "showIcon" },
			{ type = "slider", label = "Gap between icon and bar", path = "iconGap", min = 0, max = 10, step = 1 },
			{ type = "slider", label = "Gap between bars", path = "gap", min = 0, max = 20, step = 1 },
			{ type = "slider", label = "Background opacity", path = "bgAlpha", min = 0, max = 1, step = 0.05 },
			{ type = "toggle", label = "Own background colour", path = "customBgColor" },
			{ type = "color", label = "Background colour", path = "bgColor", disabled = function() return not m.db.customBgColor end },
		})),
		Card("Border", G.Border("border")),
		Card("Name text", G.Font("nameText", { toggle = "Show name" })),
		Card("Timer text", G.Font("timerText", { toggle = "Show timer" })),
		Card("Position", G.Position("position")),
	}
end)

--------------------------------------------------------------------------------
O:RegisterModuleOptions("CCTracker", function(ctx, m, G)
	return {
		Card("Bars", {
			{ type = "dropdown", label = "Stacking", path = "mode", values = m.MODES },
			{ type = "toggle", label = "Only spells your group can cast", path = "classRows",
				hidden = function() return m.db.mode == "each" end },
			{ type = "dropdown", label = "Grow", path = "grow", values = m.GROW },
			{ type = "slider", label = "Spacing", path = "spacing", min = 0, max = 20, step = 1 },
			{ type = "dropdown", label = "Icon", path = "iconSide", values = m.ICON_SIDES },
			{ type = "slider", label = "Gap between icon and bar", path = "iconGap", min = 0, max = 10, step = 1 },
			{ type = "slider", label = "Enemies tracked at most", path = "maxUnits", min = 1, max = 40, step = 1 },
		}),
		Card("Bar", G.Bar("bar")),
		Card("Border", G.Border("border")),
		Card("Name text", G.Font("nameText", { toggle = "Show name" })),
		Card("Timer text", Join(G.Font("timerText", { toggle = "Show timer" }), {
			{ type = "dropdown", label = "Timer side", path = "timerSide", values = m.TIMER_SIDES },
			{ type = "toggle", label = "Tenths of a second", path = "tenths" },
		})),
		Card("Sound", {
			{ type = "description", width = "full", text = "Played by the game when a listed debuff lands - once per enemy, so the Effects channel is the default." },
			{ type = "dropdown", label = "Sound", path = "sound", media = "sound", filesOnly = true },
			{ type = "dropdown", label = "Channel", path = "soundChannel", values = XUI.Audio.CHANNELS },
			{ type = "dropdown", label = "For", path = "soundFrom", values = m.SOUND_FROM },
			{ type = "button", text = "Test", onClick = function() m:PlayTest() end },
		}),
		Card("Spells", {
			{ type = "description", width = "full", text = "The DEBUFF's spell ID, which is not always the cast's (Binding Shot's stun is 117526). Order is the bars' order." },
			{
				type = "spellList", path = "spells", colors = "colors", labels = "labels", reorder = true, width = "full",
				defaultColor = function(id) return m:SpellColor(id) end,
				defaultLabel = function(id) local b = m.BUILTIN[id] return b and b[1] or nil end,
			},
		}),
		Card("Position", G.Position("position")),
	}
end)

--------------------------------------------------------------------------------
O:RegisterModuleOptions("AggroCheck", function(ctx, m, G)
	return {
		Card("Warning", {
			{ type = "input", label = "Text", path = "text" },
			{ type = "color", label = "Color", path = "color" },
			{ type = "toggle", label = "Pulse", path = "pulse" },
			{ type = "toggle", label = "Only in Mythic+ keys", path = "keyOnly" },
		}),
		Card("Text", G.Font("font")),
		Card("Alert", G.Alert("alert")),
		Card("Position", G.Position("position")),
	}
end)

--------------------------------------------------------------------------------
O:RegisterModuleOptions("Bloodlust", function(ctx, m, G)
	return {
		Card("Alert when lust is ready again", G.Alert("alert", { test = function() m:TestAlert() end })),
	}
end)
