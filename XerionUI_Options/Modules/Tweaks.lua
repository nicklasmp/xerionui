--------------------------------------------------------------------------------
-- XerionUI_Options - Modules/Tweaks.lua
-- Options for the EllesmereUI Tweaks category.
--------------------------------------------------------------------------------
local XUI = _G.XerionUI
local O = XUI and XUI.Options
if not O then return end

local Card, Join = O.Card, O.Join

O:RegisterModuleOptions("EUINameplates", function(ctx, m, G)
	local function off() return not m.db.shield.enabled end
	return {
		Card("Dispel glow", {
			{ type = "toggle", label = "Show the glow without purge or soothe", path = "dispelAlways", width = "full",
				tip = "EllesmereUI's own Dispel Glow setting still switches the glow on and off." },
			{ type = "toggle", label = "Auto-Cast shine instead of EllesmereUI's style", path = "dispelShine", width = "full",
				tip = "EllesmereUI cannot draw Auto-Cast on its aura icons (it swaps in Modern WoW Glow). This draws an Auto-Cast shine there instead, in the look set below (up to 8 particles). EllesmereUI's Dispel Glow setting still decides when a buff glows. The shine is prepared when the icons are made, so reload the UI (/reload) after changing the module's state." },
		}),
		Card("Auto-Cast shine", G.Glow("dispelGlow"), { hidden = function() return not m.db.dispelShine end }),
		Card("Shield amount", Join({
			{ type = "toggle", label = "Show the shield amount", path = "shield.enabled" },
			{ type = "toggle", label = "Enemies only", path = "shield.enemyOnly", disabled = off },
			{ type = "spacer" },
			{ type = "slider", label = "Offset X", path = "shield.offX", min = -40, max = 40, step = 1, disabled = off },
			{ type = "slider", label = "Offset Y", path = "shield.offY", min = -40, max = 40, step = 1, disabled = off },
		}, G.Font("shieldText", { color = true }))),
	}
end)

O:RegisterModuleOptions("EUIFocusKick", function(ctx, m, G)
	return {
		Card("Speech", {
			{ type = "description", width = "full", text = "Speech only: whether a cast can be interrupted is hidden in keys, and only speech can follow it without Lua knowing. A sound file would play on every cast." },
			{ type = "input", label = "Words", path = "text" },
			{ type = "dropdown", label = "Voice", path = "voice", values = function() return XUI.Audio:Voices() end },
			{ type = "slider", label = "Volume", path = "volume", min = 0, max = 100, step = 5 },
			{ type = "slider", label = "Speed", path = "rate", min = -10, max = 10, step = 1 },
			{ type = "button", text = "Test", onClick = function() m:Test() end },
		}),
	}
end)

O:RegisterModuleOptions("EUIFlyingBar", function(ctx, m, G)
	return {
		Card("Whirling Surge icon", {
			{ type = "toggle", label = "Hide the icon", path = "hideIcon",
				tip = "Removes the Whirling Surge icon beside the bars; the bars close up. Switching this module off puts EllesmereUI's own icon setting back." },
		}),
	}
end)

O:RegisterModuleOptions("EUIActionBarFont", function(ctx, m, G)
	return {
		Card("Font", G.Font("font", { noSize = true })),
	}
end)

O:RegisterModuleOptions("EUICDMStackFont", function(ctx, m, G)
	return {
		Card("Font", {
			{ type = "dropdown", label = "Stack font", path = "face", media = "font",
				tip = "Used for stack and charge counts only. Size, outline and color stay as set in EllesmereUI." },
		}),
	}
end)

O:RegisterModuleOptions("ZoneText", function(ctx, m, G)
	return {
		Card("Font", Join({
			{ type = "slider", label = "Size", path = "scale", min = 50, max = 200, step = 5,
				tip = "Percent of Blizzard's own size. The color of the text stays as the game sets it for the zone." },
		}, G.Font("font", { noSize = true }))),
		Card("Preview", {
			{ type = "button", text = "Show sample", onClick = function() m:Test() end },
		}),
	}
end)

O:RegisterModuleOptions("EUIFocusCastbar", function(ctx, m, G)
	return {
		Card("Background", {
			{ type = "color", label = "Background color", path = "color",
				tip = "Tints the empty background behind the cast fill. The cast color itself is unchanged." },
		}),
	}
end)

O:RegisterModuleOptions("EUITargetedSpellBars", function(ctx, m, G)
	local function off() return not m.db.spark end
	return {
		Card("Boss casts", {
			{ type = "toggle", label = "Hide boss casts", path = "hideBossCasts",
				tip = "Takes effect at once for plates already on screen." },
			{ type = "button", text = "Re-detect", onClick = function() m:Redetect() end },
		}),
		Card("Cast spark", {
			{ type = "toggle", label = "Show a spark on the cast progress", path = "spark", width = "full" },
			{ type = "slider", label = "Width", path = "sparkWidth", min = 1, max = 10, step = 1, disabled = off },
			{ type = "color", label = "Color", path = "sparkColor", disabled = off },
			{ type = "button", text = "EllesmereUI preview", onClick = function() m:TogglePreview() end },
		}),
	}
end)

O:RegisterModuleOptions("EUIPartyFrames", function(ctx, m, G)
	local function off() return not m.db.health.enabled end
	local function byValue() return not m.db.health.byValue end
	local function single() return m.db.health.byValue end
	return {
		Card("Health + shield %", {
			{ type = "toggle", label = "Show health + shield %", path = "health.enabled", width = "full" },
			{ type = "dropdown", label = "Position", path = "health.anchor", values = m.ANCHORS, disabled = off },
			{ type = "toggle", label = "Use EllesmereUI's name font", path = "health.matchName", disabled = off },
			{ type = "slider", label = "Offset X", path = "health.x", min = -60, max = 60, step = 1, disabled = off },
			{ type = "slider", label = "Offset Y", path = "health.y", min = -30, max = 30, step = 1, disabled = off },
		}),
		Card("Text", G.Font("healthText"), { hidden = function() return off() or m.db.health.matchName end }),
		Card("Color", {
			{ type = "toggle", label = "Color by value", path = "health.byValue", width = "full", disabled = off },
			{ type = "color", label = "Text color", path = "health.color", hidden = single, disabled = off },
			{ type = "color", label = "Below step 1", path = "health.c1", hidden = byValue, disabled = off },
			{ type = "slider", label = "Step 1", path = "health.t1", min = 1, max = 200, step = 1, hidden = byValue, disabled = off },
			{ type = "color", label = "Step 1 to 2", path = "health.c2", hidden = byValue, disabled = off },
			{ type = "slider", label = "Step 2", path = "health.t2", min = 1, max = 200, step = 1, hidden = byValue, disabled = off },
			{ type = "color", label = "Step 2 to 3", path = "health.c3", hidden = byValue, disabled = off },
			{ type = "slider", label = "Step 3", path = "health.t3", min = 1, max = 200, step = 1, hidden = byValue, disabled = off },
			{ type = "color", label = "Step 3 and above", path = "health.c4", hidden = byValue, disabled = off },
		}),
		Card("Debuff stack count", {
			{ type = "dropdown", label = "Position on each debuff icon", path = "stack.placement", values = m.STACK_PLACES },
			{ type = "spacer" },
			{ type = "slider", label = "Offset X", path = "stack.x", min = -40, max = 40, step = 1 },
			{ type = "slider", label = "Offset Y", path = "stack.y", min = -40, max = 40, step = 1 },
			{ type = "description", width = "full", text = "Preview shows a sample debuff on your first party frame." },
		}),
	}
end)
