--------------------------------------------------------------------------------
-- XerionUI - Core/Style.lua
-- The shared look. Fonts, borders, glows, backgrounds, status bars and icon
-- crops are applied through these functions and nowhere else, so every module
-- offers the same options and draws them the same way.
--
-- STYLE BLOCKS
-- A module element stores a small block per style kind, e.g.
--     text   = { size = 18, color = {1,1,1,1}, useGlobal = true }   -- kind "font"
--     border = { useGlobal = true }                                  -- kind "border"
--     glow   = { enabled = true, useGlobal = true }                  -- kind "glow"
-- Resolve(kind, block) merges it over the global style (DB.style[kind]):
--   * useGlobal ~= false: only the element's LOCAL fields (size, colour,
--     enabled ...) come from the block, the rest is the global look.
--   * useGlobal == false: every field in the block wins; anything it lacks
--     still falls back to the global value.
-- So "change the font everywhere" is one setting, and a single module can
-- still opt out.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local Media = XUI.Media

local LCG = LibStub("LibCustomGlow-1.0")

local type, pairs, max, floor = type, pairs, math.max, math.floor
local UnpackColor = XUI.UnpackColor

local Style = {}
XUI.Style = Style

--------------------------------------------------------------------------------
-- Choice lists (shared with the options panel)
--------------------------------------------------------------------------------
-- SLUG is Midnight's sharper text rendering, the one EllesmereUI uses: the
-- slug variants are the default and what you want unless you need the old look.
Style.OUTLINES = {
	{ value = "SLUGOUTLINE", text = "Outline (slug, like EllesmereUI)" },
	{ value = "SLUGTHICKOUTLINE", text = "Thick outline (slug)" },
	{ value = "SLUG", text = "No outline (slug)" },
	{ value = "NONE", text = "None (classic)" },
	{ value = "OUTLINE", text = "Outline (classic)" },
	{ value = "THICKOUTLINE", text = "Thick outline (classic)" },
	{ value = "MONOCHROME", text = "Monochrome" },
}

local OUTLINE_FLAGS = {
	SLUGOUTLINE = "OUTLINE, SLUG",
	SLUGTHICKOUTLINE = "THICKOUTLINE, SLUG",
	SLUG = "SLUG",
	NONE = "",
	OUTLINE = "OUTLINE",
	THICKOUTLINE = "THICKOUTLINE",
	MONOCHROME = "MONOCHROME, OUTLINE",
}

-- Built-in border styles; LibSharedMedia border textures are offered after these.
Style.BORDER_STYLES = {
	{ value = "NONE", text = "None" },
	{ value = "SOLID", text = "Solid" },
	{ value = "DOUBLE", text = "Solid + outline" },
}

Style.GLOW_TYPES = {
	{ value = "PIXEL", text = "Pixel" },
	{ value = "PULSE", text = "Pulse" },
	{ value = "AUTOCAST", text = "Autocast shine" },
	{ value = "BUTTON", text = "Action button" },
	{ value = "PROC", text = "Proc" },
}

Style.STRATA = {
	{ value = "BACKGROUND", text = "Background" },
	{ value = "LOW", text = "Low" },
	{ value = "MEDIUM", text = "Medium" },
	{ value = "HIGH", text = "High" },
	{ value = "DIALOG", text = "Dialog" },
}

Style.JUSTIFY = {
	{ value = "LEFT", text = "Left" },
	{ value = "CENTER", text = "Center" },
	{ value = "RIGHT", text = "Right" },
}

Style.ANCHORS = {
	{ value = "TOPLEFT", text = "Top left" },
	{ value = "TOP", text = "Top" },
	{ value = "TOPRIGHT", text = "Top right" },
	{ value = "LEFT", text = "Left" },
	{ value = "CENTER", text = "Center" },
	{ value = "RIGHT", text = "Right" },
	{ value = "BOTTOMLEFT", text = "Bottom left" },
	{ value = "BOTTOM", text = "Bottom" },
	{ value = "BOTTOMRIGHT", text = "Bottom right" },
}

--------------------------------------------------------------------------------
-- Resolution
--------------------------------------------------------------------------------
-- Fields that always belong to the element, whatever useGlobal says.
local LOCAL_FIELDS = {
	font = { size = true, color = true, justify = true },
	border = { enabled = true },
	glow = { enabled = true },
	background = { enabled = true },
	bar = { color = true, bgColor = true, width = true, height = true },
	icon = { width = true, height = true, size = true },
}
Style.LOCAL_FIELDS = LOCAL_FIELDS

-- Resolved blocks are cached per block table until anything style-related
-- changes; the version bump below invalidates them all at once.
local resolved = setmetatable({}, { __mode = "k" })
local version = 0

function Style:Invalidate()
	version = version + 1
end

function Style:Resolve(kind, block)
	local global = XUI.DB.style[kind]
	if type(block) ~= "table" then return global end
	local hit = resolved[block]
	if hit and hit.__v == version then return hit end

	local out = {}
	for k, v in pairs(global) do out[k] = v end
	if block.useGlobal == false then
		for k, v in pairs(block) do out[k] = v end
	else
		for k in pairs(LOCAL_FIELDS[kind]) do
			if block[k] ~= nil then out[k] = block[k] end
		end
	end
	out.__v = version
	resolved[block] = out
	return out
end

XUI:On("StyleChanged", Style, function() Style:Invalidate() end)
XUI:On("ProfileChanged", Style, function() Style:Invalidate() end)
XUI:On("MediaChanged", Style, function() Style:Invalidate() end)

--------------------------------------------------------------------------------
-- Pixels
--------------------------------------------------------------------------------
-- UI units of `frame` that make up `n` physical screen pixels.
function Style:Pixels(frame, n)
	if not n or n <= 0 then return 0 end
	local scale = frame and frame:GetEffectiveScale() or 1
	if scale <= 0 then scale = 1 end
	return n * PixelUtil.GetPixelToUIUnitFactor() / scale
end

--------------------------------------------------------------------------------
-- Fonts
-- Drop shadows only render when they come from a FontObject (runtime
-- SetShadowOffset on a FontString does not draw one), so each distinct shadow
-- gets a small shared FontObject the string is primed with before SetFont.
--------------------------------------------------------------------------------
local shadowObjects = {}
local shadowCount = 0

local function ShadowObject(f)
	local key
	if f.shadow then
		local r, g, b, a = UnpackColor(f.shadowColor, 0, 0, 0, 1)
		key = ("%.2f:%.2f:%.2f:%.2f:%d:%d"):format(r, g, b, a, f.shadowX or 1, f.shadowY or -1)
	else
		key = "none"
	end
	local obj = shadowObjects[key]
	if obj then return obj, key end
	shadowCount = shadowCount + 1
	obj = CreateFont("XUI_ShadowFont" .. shadowCount)
	obj:SetFont([[Fonts\ARIALN.TTF]], 12, "")
	if f.shadow then
		obj:SetShadowColor(UnpackColor(f.shadowColor, 0, 0, 0, 1))
		obj:SetShadowOffset(f.shadowX or 1, f.shadowY or -1)
	else
		obj:SetShadowColor(0, 0, 0, 0)
		obj:SetShadowOffset(0, 0)
	end
	shadowObjects[key] = obj
	return obj, key
end

function Style:FontFlags(f)
	return OUTLINE_FLAGS[f.outline] or OUTLINE_FLAGS.SLUGOUTLINE
end

-- Applies a font block to a FontString. `size` overrides the block's size
-- (for text that scales with its icon).
function Style:ApplyFont(fs, block, size)
	local f = self:Resolve("font", block)
	local path = Media:Fetch("font", f.face)
	size = size or f.size or 12
	if size < 1 then size = 1 end
	local flags = self:FontFlags(f)
	local obj, shadowKey = ShadowObject(f)
	local sig = path .. "|" .. size .. "|" .. flags .. "|" .. shadowKey
	if fs.__xuiFont ~= sig then
		fs:SetFontObject(obj)
		if not fs:SetFont(path, size, flags) then
			fs:SetFont(Media:Fetch("font"), size, flags)
		end
		fs.__xuiFont = sig
	end
	if f.color then fs:SetTextColor(UnpackColor(f.color)) end
	if f.justify then fs:SetJustifyH(f.justify) end
	return f
end

--------------------------------------------------------------------------------
-- Borders
-- A border lives INSIDE its frame's rect: it never eats into the spacing
-- between neighbouring frames and is never clipped by what the frame sits
-- on. Content (an icon, a bar fill) is inset by Border:GetInset().
--------------------------------------------------------------------------------
local BorderMixin = {}

local function Edge(holder, layer)
	local t = holder:CreateTexture(nil, "OVERLAY", nil, layer)
	t:SetTexture([[Interface\Buttons\WHITE8X8]])
	return t
end

local function LayoutEdges(edges, frame, inset, thickness)
	local top, bottom, left, right = edges[1], edges[2], edges[3], edges[4]
	top:ClearAllPoints()
	top:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
	top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
	top:SetHeight(thickness)
	bottom:ClearAllPoints()
	bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset)
	bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
	bottom:SetHeight(thickness)
	left:ClearAllPoints()
	left:SetPoint("TOPLEFT", top, "BOTTOMLEFT")
	left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT")
	left:SetWidth(thickness)
	right:ClearAllPoints()
	right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT")
	right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT")
	right:SetWidth(thickness)
end

local function ShowEdges(edges, shown, r, g, b, a)
	for i = 1, 4 do
		local e = edges[i]
		if shown then
			e:SetVertexColor(r, g, b, a)
			e:Show()
		else
			e:Hide()
		end
	end
end

function BorderMixin:Apply(block)
	local b = Style:Resolve("border", block)
	local owner = self.owner
	self:SetFrameLevel(owner:GetFrameLevel() + (self.levelOffset or 3))
	local style = b.style or "SOLID"
	if b.enabled == false then style = "NONE" end
	local px = math.floor((b.size or 1) + 0.5)
	local r, g, bl, a = UnpackColor(b.color, 0, 0, 0, 1)

	if self.backdrop then self.backdrop:Hide() end

	if style == "NONE" or (px <= 0 and (style == "SOLID" or style == "DOUBLE")) then
		ShowEdges(self.edges, false)
		if self.outer then ShowEdges(self.outer, false) end
		self.inset = 0
	elseif style == "SOLID" then
		local t = Style:Pixels(owner, px)
		LayoutEdges(self.edges, self, 0, t)
		ShowEdges(self.edges, true, r, g, bl, a)
		if self.outer then ShowEdges(self.outer, false) end
		self.inset = t
	elseif style == "DOUBLE" then
		-- a 1px black outline, then the coloured line inside it
		local one = Style:Pixels(owner, 1)
		local t = Style:Pixels(owner, px)
		if not self.outer then
			self.outer = { Edge(self, 6), Edge(self, 6), Edge(self, 6), Edge(self, 6) }
		end
		LayoutEdges(self.outer, self, 0, one)
		ShowEdges(self.outer, true, 0, 0, 0, a)
		LayoutEdges(self.edges, self, one, t)
		ShowEdges(self.edges, true, r, g, bl, a)
		self.inset = one + t
	else
		-- a LibSharedMedia border texture, drawn as a backdrop edge
		ShowEdges(self.edges, false)
		if self.outer then ShowEdges(self.outer, false) end
		if not self.backdrop then
			self.backdrop = CreateFrame("Frame", nil, self, "BackdropTemplate")
		end
		local edge = max(1, Style:Pixels(owner, px))
		local out = edge * 0.25
		local bd = self.backdrop
		bd:ClearAllPoints()
		bd:SetPoint("TOPLEFT", self, "TOPLEFT", -out, out)
		bd:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", out, -out)
		bd:SetBackdrop({ edgeFile = Media:Fetch("border", style), edgeSize = edge })
		bd:SetBackdropBorderColor(r, g, bl, a)
		bd:Show()
		self.inset = 0
	end
	return self.inset
end

-- Content inset in the owner's UI units.
function BorderMixin:GetInset()
	return self.inset or 0
end

function BorderMixin:SetColor(r, g, b, a)
	for i = 1, 4 do self.edges[i]:SetVertexColor(r, g, b, a or 1) end
	if self.backdrop then self.backdrop:SetBackdropBorderColor(r, g, b, a or 1) end
end

-- Creates (once) and returns the border of `frame`.
function Style:Border(frame, levelOffset)
	if frame.__xuiBorder then return frame.__xuiBorder end
	local holder = CreateFrame("Frame", nil, frame)
	holder:SetAllPoints(frame)
	holder.owner = frame
	holder.levelOffset = levelOffset
	holder.edges = { Edge(holder, 7), Edge(holder, 7), Edge(holder, 7), Edge(holder, 7) }
	Mixin(holder, BorderMixin)
	holder.inset = 0
	frame.__xuiBorder = holder
	return holder
end

--------------------------------------------------------------------------------
-- Backgrounds
--------------------------------------------------------------------------------
function Style:Background(frame)
	if frame.__xuiBg then return frame.__xuiBg end
	local tex = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	tex:SetAllPoints(frame)
	frame.__xuiBg = tex
	return tex
end

function Style:ApplyBackground(tex, block)
	local b = self:Resolve("background", block)
	if b.enabled == false then
		tex:Hide()
		return b
	end
	tex:SetTexture(Media:Fetch("background", b.texture))
	tex:SetVertexColor(UnpackColor(b.color, 0, 0, 0, 0.5))
	tex:Show()
	return b
end

--------------------------------------------------------------------------------
-- Status bars
--------------------------------------------------------------------------------
function Style:ApplyBar(bar, block)
	local b = self:Resolve("bar", block)
	local path = Media:Fetch("statusbar", b.texture)
	bar:SetStatusBarTexture(path)
	if b.color then bar:SetStatusBarColor(UnpackColor(b.color)) end
	local bg = bar.__xuiBarBg
	if not bg then
		bg = bar:CreateTexture(nil, "BACKGROUND", nil, -7)
		bg:SetAllPoints(bar)
		bar.__xuiBarBg = bg
	end
	bg:SetTexture(path)
	bg:SetVertexColor(UnpackColor(b.bgColor, 0, 0, 0, 0.5))
	return b
end

--------------------------------------------------------------------------------
-- Icons
-- Crops `zoom` percent off each edge, then trims the long side so a
-- non-square icon frame shows undistorted art.
--------------------------------------------------------------------------------
function Style:IconTexCoord(tex, w, h, zoom)
	if zoom == nil then zoom = self:Resolve("icon").zoom or 8 end
	local z = XUI.Clamp(zoom / 100, 0, 0.45)
	local l, r, t, b = z, 1 - z, z, 1 - z
	if w and h and w > 0 and h > 0 then
		if w > h then
			local cut = (1 - h / w) * (b - t) / 2
			t, b = t + cut, b - cut
		elseif h > w then
			local cut = (1 - w / h) * (r - l) / 2
			l, r = l + cut, r - cut
		end
	end
	tex:SetTexCoord(l, r, t, b)
end

--------------------------------------------------------------------------------
-- Glows
-- PIXEL and PULSE are our own animation-group glows (Core/Glow.lua): no Lua
-- per frame, and safe on the engine's aura buttons. AUTOCAST, BUTTON and
-- PROC come from LibCustomGlow, which animates in OnUpdate scripts; on an
-- engine button (engineSafe) those fall back to PIXEL.
-- Starting the same glow again is a no-op, so callers may simply call
-- ShowGlow on every refresh.
--------------------------------------------------------------------------------
local GLOW_KEY = "XerionUI"
local SCRIPTED = { AUTOCAST = true, BUTTON = true, PROC = true }

local function GlowSignature(kind, g)
	local r, gg, b, a = UnpackColor(g.color)
	return ("%s|%.3f|%.3f|%.3f|%.3f|%s|%s|%s|%s|%s|%s|%s"):format(kind, r, gg, b, a,
		g.lines or 0, g.frequency or 0, g.length or 0, g.thickness or 0,
		g.particles or 0, g.scale or 0, g.offset or 0)
end

function Style:HideGlow(frame)
	local current = frame.__xuiGlow
	if not current then return end
	if current == "PIXEL" then
		XUI.Glow.StopAnts(frame)
	elseif current == "PULSE" then
		XUI.Glow.StopPulse(frame)
	elseif current == "AUTOCAST" then
		LCG.AutoCastGlow_Stop(frame, GLOW_KEY)
	elseif current == "BUTTON" then
		LCG.ButtonGlow_Stop(frame)
	elseif current == "PROC" then
		LCG.ProcGlow_Stop(frame, GLOW_KEY)
	end
	frame.__xuiGlow, frame.__xuiGlowSig = nil, nil
end

function Style:ShowGlow(frame, block, engineSafe)
	local g = self:Resolve("glow", block)
	local kind = g.type
	if g.enabled == false or not kind or kind == "NONE" then
		self:HideGlow(frame)
		return
	end
	if engineSafe and SCRIPTED[kind] then kind = "PIXEL" end
	local ok, w, h = pcall(frame.GetSize, frame)
	if not ok or XUI.IsSecret(w) then w, h = 0, 0 end
	local sig = GlowSignature(kind, g) .. "|" .. floor((w or 0) + 0.5) .. "x" .. floor((h or 0) + 0.5)
	if frame.__xuiGlowSig == sig then return end
	if frame.__xuiGlow and frame.__xuiGlow ~= kind then self:HideGlow(frame) end

	local color = { UnpackColor(g.color) }
	local offset = g.offset or 0
	if kind == "PIXEL" then
		XUI.Glow.StartAnts(frame, {
			color = color, lines = g.lines, frequency = g.frequency, offset = offset,
			length = g.length, thickness = self:Pixels(frame, max(1, g.thickness or 2)),
		})
	elseif kind == "PULSE" then
		XUI.Glow.StartPulse(frame, { color = color, frequency = g.frequency, thickness = g.thickness })
	elseif kind == "AUTOCAST" then
		LCG.AutoCastGlow_Start(frame, color, floor(g.particles or 4), g.frequency or 0.25,
			g.scale or 1, offset, offset, GLOW_KEY)
	elseif kind == "BUTTON" then
		LCG.ButtonGlow_Start(frame, color, g.frequency or 0.25)
	elseif kind == "PROC" then
		LCG.ProcGlow_Start(frame, { color = color, key = GLOW_KEY, xOffset = offset, yOffset = offset })
	end
	frame.__xuiGlow, frame.__xuiGlowSig = kind, sig
end

function Style:SetGlow(frame, block, shown, engineSafe)
	if shown then self:ShowGlow(frame, block, engineSafe) else self:HideGlow(frame) end
end
