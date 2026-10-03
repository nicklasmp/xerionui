--------------------------------------------------------------------------------
-- XerionUI_Options - Groups.lua
-- The shared option groups. Every module that shows text, an icon, a bar, a
-- border or a glow builds those options from here, so the same setting has
-- the same name, range and place everywhere - and the global style page is
-- built from the very same groups.
--
--   G.Font(path, opts)        a text element (font block)
--   G.Border(path, opts)      border style block
--   G.Glow(path, opts)        glow style block
--   G.Icon(path, opts)        icon size + crop
--   G.Bar(path, opts)         status bar size + texture + colours
--   G.Background(path, opts)  background texture + colour
--   G.Alert(path, opts)       sound / text to speech
--   G.Position(path, opts)    placement on screen
--
-- Each returns a list of control descriptors; wrap it in O.Card(...) or join
-- it with other controls. opts.global = true builds the variant used on the
-- global style page (no "use global" switch, no per-element fields).
--------------------------------------------------------------------------------
local XUI = _G.XerionUI
local O = XUI and XUI.Options
if not O then return end

local GetPath = XUI.GetPath
local Style = XUI.Style

local G = {}
O.Groups = G

--------------------------------------------------------------------------------
-- Field binding for style blocks
--------------------------------------------------------------------------------
local function Block(ctx, path)
	local b = GetPath(ctx:Root(), path)
	if type(b) ~= "table" then
		b = {}
		XUI.SetPath(ctx:Root(), path, b)
	end
	return b
end

local function UsesGlobal(ctx, path)
	return Block(ctx, path).useGlobal ~= false
end

-- A style field: shows the element's own value when it overrides the global
-- style, otherwise the global value (greyed out).
local function StyleField(kind, path, field, opts, desc)
	desc.path = path .. "." .. field
	if opts.global then return desc end
	desc.get = function(ctx)
		local b = Block(ctx, path)
		if b.useGlobal == false and b[field] ~= nil then return b[field] end
		return XUI.DB.style[kind][field]
	end
	local userDisabled = desc.disabled
	desc.disabled = function(ctx)
		if UsesGlobal(ctx, path) then return true end
		if userDisabled then return userDisabled(ctx) end
		return false
	end
	return desc
end

-- The "use global style" switch. Turning it off copies the current global
-- values into the block, so the element starts from what it looked like.
local function UseGlobalToggle(kind, path, label)
	return {
		type = "toggle",
		label = label or "Use global style",
		tip = "Follow the look set on the Global Style page. Turn off to style this element on its own.",
		path = path .. ".useGlobal",
		get = function(ctx) return UsesGlobal(ctx, path) end,
		set = function(ctx, on)
			local b = Block(ctx, path)
			b.useGlobal = on
			if not on then
				for k, v in pairs(XUI.DB.style[kind]) do
					if b[k] == nil and not Style.LOCAL_FIELDS[kind][k] then b[k] = XUI.CopyTable(v) end
				end
			end
		end,
		width = "full",
	}
end

local function Hidden(fn) return fn end

--------------------------------------------------------------------------------
-- Font
-- opts: color (bool), toggle ("label" to add a show switch on path.enabled),
--       anchor (bool: anchor + x/y for texts on icons), sizeMin/sizeMax,
--       noSize (bool)
--------------------------------------------------------------------------------
function G.Font(path, opts)
	opts = opts or {}
	local items = {}
	local function off(ctx)
		return opts.toggle and Block(ctx, path).enabled == false
	end
	if opts.toggle then
		items[#items + 1] = {
			type = "toggle", label = opts.toggle, path = path .. ".enabled",
			get = function(ctx) return Block(ctx, path).enabled ~= false end,
			width = "full",
		}
	end
	if not opts.global and not opts.noSize then
		items[#items + 1] = {
			type = "slider", label = "Size", path = path .. ".size",
			min = opts.sizeMin or 6, max = opts.sizeMax or 64, step = 1,
			disabled = off,
		}
	end
	if opts.color then
		items[#items + 1] = { type = "color", label = "Color", path = path .. ".color", disabled = off }
	end
	if not opts.global then
		local t = UseGlobalToggle("font", path, "Use global font")
		t.disabled = off
		items[#items + 1] = t
	end
	items[#items + 1] = StyleField("font", path, "face", opts, {
		type = "dropdown", label = "Font", media = "font",
	})
	items[#items + 1] = StyleField("font", path, "outline", opts, {
		type = "dropdown", label = "Outline", values = Style.OUTLINES,
		tip = "The slug variants use Midnight's sharper text rendering, the same as EllesmereUI. The classic ones are the old look.",
	})
	items[#items + 1] = StyleField("font", path, "shadow", opts, {
		type = "toggle", label = "Drop shadow",
	})
	if opts.global then
		items[#items + 1] = StyleField("font", path, "shadowColor", opts, {
			type = "color", label = "Shadow color",
			hidden = function(ctx) return not Block(ctx, path).shadow end,
		})
	end
	if opts.anchor then
		items[#items + 1] = { type = "dropdown", label = "Anchor", path = path .. ".anchor", values = Style.ANCHORS, disabled = off }
		items[#items + 1] = { type = "spacer", height = 1 }
		items[#items + 1] = { type = "slider", label = "Offset X", path = path .. ".x", min = -50, max = 50, step = 1, disabled = off }
		items[#items + 1] = { type = "slider", label = "Offset Y", path = path .. ".y", min = -50, max = 50, step = 1, disabled = off }
	end
	-- when the element itself is switched off, nothing else applies
	for i = (opts.toggle and 2 or 1), #items do
		local d = items[i]
		local was = d.disabled
		if was ~= off then
			d.disabled = function(ctx)
				if off(ctx) then return true end
				return was and was(ctx) or false
			end
		end
	end
	return items
end

--------------------------------------------------------------------------------
-- Border
--------------------------------------------------------------------------------
function G.Border(path, opts)
	opts = opts or {}
	local items = {}
	if not opts.global then items[#items + 1] = UseGlobalToggle("border", path) end
	local function isNone(ctx)
		local b = opts.global and Block(ctx, path) or Style:Resolve("border", Block(ctx, path))
		return b.style == "NONE"
	end
	items[#items + 1] = StyleField("border", path, "style", opts, {
		type = "dropdown", label = "Style", media = "border",
	})
	items[#items + 1] = StyleField("border", path, "size", opts, {
		type = "slider", label = "Thickness (pixels)", min = 0, max = 16, step = 1,
		disabled = isNone,
	})
	items[#items + 1] = StyleField("border", path, "color", opts, {
		type = "color", label = "Color",
		disabled = isNone,
	})
	return items
end

--------------------------------------------------------------------------------
-- Glow
-- opts.toggle: label of the show switch on path.enabled (default "Glow")
--------------------------------------------------------------------------------
function G.Glow(path, opts)
	opts = opts or {}
	local items = {}
	local function off(ctx)
		return not opts.global and Block(ctx, path).enabled == false
	end
	local function glowType(ctx)
		local b = opts.global and Block(ctx, path) or Style:Resolve("glow", Block(ctx, path))
		return b.type
	end
	local function notType(...)
		local wanted = { ... }
		return function(ctx)
			local t = glowType(ctx)
			for _, w in ipairs(wanted) do if t == w then return false end end
			return true
		end
	end
	if not opts.global then
		items[#items + 1] = {
			type = "toggle", label = opts.toggle or "Glow", path = path .. ".enabled",
			get = function(ctx) return Block(ctx, path).enabled ~= false end,
		}
		local t = UseGlobalToggle("glow", path)
		t.width = nil
		t.disabled = off
		items[#items + 1] = t
	end
	items[#items + 1] = StyleField("glow", path, "type", opts, {
		type = "dropdown", label = "Type", values = Style.GLOW_TYPES,
	})
	items[#items + 1] = StyleField("glow", path, "color", opts, {
		type = "color", label = "Color",
	})
	items[#items + 1] = StyleField("glow", path, "lines", opts, {
		type = "slider", label = "Lines", min = 1, max = 24, step = 1,
		hidden = notType("PIXEL"),
	})
	items[#items + 1] = StyleField("glow", path, "thickness", opts, {
		type = "slider", label = "Thickness (pixels)", min = 1, max = 8, step = 1,
		hidden = notType("PIXEL"),
	})
	items[#items + 1] = StyleField("glow", path, "length", opts, {
		type = "slider", label = "Line length (0 = auto)", min = 0, max = 30, step = 1,
		hidden = notType("PIXEL"),
	})
	items[#items + 1] = StyleField("glow", path, "particles", opts, {
		type = "slider", label = "Particles", min = 1, max = 16, step = 1,
		hidden = notType("AUTOCAST"),
	})
	items[#items + 1] = StyleField("glow", path, "scale", opts, {
		type = "slider", label = "Particle scale", min = 0.5, max = 3, step = 0.05,
		hidden = notType("AUTOCAST"),
	})
	items[#items + 1] = StyleField("glow", path, "frequency", opts, {
		type = "slider", label = "Speed", min = -2, max = 2, step = 0.05,
		tip = "Negative values run the animation the other way.",
		hidden = notType("PIXEL", "PULSE", "AUTOCAST", "BUTTON"),
	})
	items[#items + 1] = StyleField("glow", path, "offset", opts, {
		type = "slider", label = "Offset", min = -10, max = 20, step = 1,
		hidden = notType("PIXEL", "AUTOCAST", "PROC"),
	})
	for i = (opts.global and 1 or 2), #items do
		local d = items[i]
		local was = d.disabled
		d.disabled = function(ctx)
			if off(ctx) then return true end
			return was and was(ctx) or false
		end
	end
	return items
end

--------------------------------------------------------------------------------
-- Icon: size + crop
-- opts.square: one Size slider instead of width/height
--------------------------------------------------------------------------------
function G.Icon(path, opts)
	opts = opts or {}
	local items = {}
	if not opts.global then
		if opts.square then
			items[#items + 1] = {
				type = "slider", label = "Size", path = path .. ".width", min = 12, max = 128, step = 1,
				set = function(ctx, v)
					local b = Block(ctx, path)
					b.width, b.height = v, v
				end,
			}
		else
			items[#items + 1] = { type = "slider", label = "Width", path = path .. ".width", min = 12, max = 128, step = 1 }
			items[#items + 1] = { type = "slider", label = "Height", path = path .. ".height", min = 12, max = 128, step = 1 }
		end
		items[#items + 1] = UseGlobalToggle("icon", path, "Use global icon crop")
	end
	items[#items + 1] = StyleField("icon", path, "zoom", opts, {
		type = "slider", label = "Crop (%)", min = 0, max = 30, step = 1,
		tip = "How much of each edge of the icon art is trimmed off.",
	})
	return items
end

--------------------------------------------------------------------------------
-- Bar
-- opts.color: show a fill colour (bars whose colour is not semantic)
--------------------------------------------------------------------------------
function G.Bar(path, opts)
	opts = opts or {}
	local items = {}
	if not opts.global then
		items[#items + 1] = { type = "slider", label = "Width", path = path .. ".width", min = 40, max = 600, step = 1 }
		items[#items + 1] = { type = "slider", label = "Height", path = path .. ".height", min = 4, max = 60, step = 1 }
		if opts.color then
			items[#items + 1] = { type = "color", label = "Bar color", path = path .. ".color" }
			items[#items + 1] = { type = "spacer" }
		end
		items[#items + 1] = UseGlobalToggle("bar", path, "Use global bar texture")
	end
	items[#items + 1] = StyleField("bar", path, "texture", opts, {
		type = "dropdown", label = "Texture", media = "statusbar",
	})
	if opts.global then
		items[#items + 1] = StyleField("bar", path, "bgColor", opts, {
			type = "color", label = "Background color",
		})
	else
		-- an element's own field (like the fill colour): it works without
		-- leaving the global style, and shows the global one until set
		items[#items + 1] = {
			type = "color", label = "Background color", path = path .. ".bgColor",
			get = function(ctx)
				return Block(ctx, path).bgColor or XUI.DB.style.bar.bgColor
			end,
		}
	end
	return items
end

--------------------------------------------------------------------------------
-- Background
--------------------------------------------------------------------------------
function G.Background(path, opts)
	opts = opts or {}
	local items = {}
	local function off(ctx)
		return not opts.global and Block(ctx, path).enabled == false
	end
	if not opts.global then
		items[#items + 1] = {
			type = "toggle", label = opts.toggle or "Background", path = path .. ".enabled",
			get = function(ctx) return Block(ctx, path).enabled ~= false end,
		}
		local t = UseGlobalToggle("background", path)
		t.width = nil
		t.disabled = off
		items[#items + 1] = t
	end
	local tex = StyleField("background", path, "texture", opts, { type = "dropdown", label = "Texture", media = "background" })
	local col = StyleField("background", path, "color", opts, { type = "color", label = "Color" })
	for _, d in ipairs({ tex, col }) do
		local was = d.disabled
		d.disabled = function(ctx)
			if off(ctx) then return true end
			return was and was(ctx) or false
		end
		items[#items + 1] = d
	end
	return items
end

--------------------------------------------------------------------------------
-- Alert: sound or text to speech
-- opts.test = function(ctx) plays the alert (a Test button is added)
-- opts.fallback = label shown as the TTS placeholder hint
--------------------------------------------------------------------------------
function G.Alert(path, opts)
	opts = opts or {}
	local function mode(ctx) return Block(ctx, path).mode end
	local function notMode(m) return function(ctx) return mode(ctx) ~= m end end
	local items = {
		{ type = "dropdown", label = opts.label or "Alert", path = path .. ".mode", values = XUI.Audio.MODES },
		{
			type = "button", text = "Test", path = path,
			hidden = function(ctx) return mode(ctx) == "NONE" end,
			onClick = function(ctx)
				if opts.test then opts.test(ctx) else XUI.Audio:Play(Block(ctx, path), opts.fallbackText, true) end
			end,
		},
		{ type = "dropdown", label = "Sound", path = path .. ".sound", media = "sound", hidden = notMode("SOUND") },
		{ type = "dropdown", label = "Channel", path = path .. ".channel", values = XUI.Audio.CHANNELS, hidden = notMode("SOUND") },
		{
			type = "input", label = "Spoken text", path = path .. ".text", hidden = notMode("TTS"),
			tip = opts.fallbackHint or "Leave empty to speak the text shown on screen.",
		},
		{ type = "dropdown", label = "Voice", path = path .. ".voice", values = function() return XUI.Audio:Voices() end, hidden = notMode("TTS") },
		{ type = "slider", label = "Volume", path = path .. ".volume", min = 0, max = 100, step = 5, hidden = notMode("TTS") },
		{ type = "slider", label = "Speed", path = path .. ".rate", min = -10, max = 10, step = 1, hidden = notMode("TTS") },
	}
	return items
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------
-- frames worth attaching to; a missing one is simply skipped by the client
G.ATTACH_TARGETS = {
	{ value = "", text = "The screen" },
	{ value = "PlayerFrame", text = "Player frame (Blizzard)" },
	{ value = "TargetFrame", text = "Target frame (Blizzard)" },
	{ value = "Minimap", text = "Minimap" },
	{ value = "EssentialCooldownViewer", text = "Cooldown Manager: Essential" },
	{ value = "UtilityCooldownViewer", text = "Cooldown Manager: Utility" },
	{ value = "BuffIconCooldownViewer", text = "Cooldown Manager: Buff icons" },
	{ value = "BuffBarCooldownViewer", text = "Cooldown Manager: Buff bars" },
}

function G.Position(path, opts)
	opts = opts or {}
	local function range()
		local w, h = UIParent:GetSize()
		return math.floor(w / 2), math.floor(h / 2)
	end
	local rx, ry = range()
	local items = {
		{ type = "slider", label = "X", path = path .. ".x", min = -rx, max = rx, step = 1 },
		{ type = "slider", label = "Y", path = path .. ".y", min = -ry, max = ry, step = 1 },
		{ type = "dropdown", label = "Layer", path = path .. ".strata", values = Style.STRATA },
		{
			type = "dropdown", label = "Attach to", values = G.ATTACH_TARGETS,
			tip = "Hang this on another frame instead of the screen: X and Y then count from the point you pick. If the frame does not exist (yet), the screen is used.",
			get = function(ctx)
				local a = GetPath(ctx:Root(), path .. ".attach")
				return (type(a) == "string") and a or ""
			end,
			set = function(ctx, v) XUI.SetPath(ctx:Root(), path .. ".attach", v) end,
		},
		{
			type = "input", label = "Or a frame name", path = path .. ".attach",
			tip = "The global name of any frame, e.g. PlayerFrame. /fstack in the game shows names.",
		},
		{
			type = "dropdown", label = "Point on that frame", path = path .. ".relPoint", values = Style.ANCHORS,
			hidden = function(ctx) local a = GetPath(ctx:Root(), path .. ".attach") return type(a) ~= "string" or a == "" end,
		},
		{
			type = "dropdown", label = "Point on this", path = path .. ".point", values = Style.ANCHORS,
			hidden = function(ctx) local a = GetPath(ctx:Root(), path .. ".attach") return type(a) ~= "string" or a == "" end,
		},
		{ type = "spacer" },
		{ type = "button", text = "Unlock frames", onClick = function() XUI:SetUnlocked(true) end },
		{
			type = "button", text = "Reset position",
			onClick = function(ctx)
				local m = ctx.module
				local p, d = GetPath(ctx:Root(), path), m and GetPath(m.defaults, path)
				if p and d then
					p.point, p.relPoint, p.x, p.y, p.attach = d.point, d.relPoint, d.x, d.y, d.attach
					ctx:Changed(path)
				end
			end,
		},
	}
	return items
end
