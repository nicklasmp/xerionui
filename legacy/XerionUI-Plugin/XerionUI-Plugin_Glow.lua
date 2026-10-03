local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('Glow', hooksecurefunc, C_Timer)

local CreateFrame = CreateFrame
local ipairs = ipairs
local mfloor, mmin = math.floor, math.min

local function PinToOwnerLevel(frame, owner)
	local ok, lvl = pcall(owner.GetFrameLevel, owner)
	if ok and type(lvl) == 'number' then pcall(frame.SetFrameLevel, frame, lvl) end
end

local ANTS_LINES = 8
local ANTS_FREQ  = 0.25
local ANTS_LENGTH = 0

local ANTS_SOLID = [[Interface\Buttons\WHITE8X8]]

local function AntsEdgeDefs(w, h, reverse)
	local e = {
		{ vert = false, len = w, base = 0,         anchor = 'TOPLEFT',     sx =  1, sy =  0 },
		{ vert = true,  len = h, base = w,         anchor = 'TOPRIGHT',    sx =  0, sy = -1 },
		{ vert = false, len = w, base = w + h,     anchor = 'BOTTOMRIGHT', sx = -1, sy =  0 },
		{ vert = true,  len = h, base = w + h + w, anchor = 'BOTTOMLEFT',  sx =  0, sy =  1 },
	}
	if reverse then
		for _, d in ipairs(e) do d.sx, d.sy = -d.sx, -d.sy end
	end
	return e
end

function ns.AntsStart(owner, w, h, opts)
	opts = opts or {}
	if not (w and h) or w <= 0 or h <= 0 then return end
	local st = owner.__kiraAnts
	if not st then
		st = { edges = {} }
		owner.__kiraAnts = st
		st.frame = CreateFrame('Frame', nil, owner)
	end
	PinToOwnerLevel(st.frame, owner)
	st.frame:ClearAllPoints()
	st.frame:SetPoint('CENTER', owner, 'CENTER', 0, 0)
	st.frame:SetSize(w, h)
	st.frame:Show()

	local color = opts.color or { 1, 1, 1, 1 }
	local lines = math.max(1, mfloor(opts.lines or 8))
	local freq = opts.freq or 0.25
	if freq == 0 then freq = 0.25 end
	local reverse = freq < 0
	local period = 1 / math.abs(freq)
	-- Any positive width, not at least 1: a caller asking for one screen
	-- pixel (Blood is Life) passes under a unit above a pixel-perfect scale.
	local th = opts.thickness
	if type(th) ~= 'number' or th <= 0 then th = 2 end
	local perim = 2 * (w + h)
	local P = perim / lines
	local dashLen = (opts.length and opts.length > 0) and opts.length or (P * 0.5)
	dashLen = math.max(1, mmin(dashLen, P))
	local step = math.max(0.001, period / lines)

	local sig = w .. ':' .. h .. ':' .. lines .. ':' .. period .. ':' .. th
		.. ':' .. dashLen .. ':' .. (reverse and 1 or 0)
	local rebuild = st.sig ~= sig
	st.sig = sig

	local defs = AntsEdgeDefs(w, h, reverse)
	for i = 1, 4 do
		local d = defs[i]
		local E = st.edges[i]
		if not E then
			E = { segs = {} }
			st.edges[i] = E
			E.mask = st.frame:CreateMaskTexture()
			E.mask:SetTexture(ANTS_SOLID, 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE')
		end

		if rebuild then
			E.mask:ClearAllPoints()
			E.mask:SetPoint(d.anchor, st.frame, d.anchor, 0, 0)
			E.mask:SetSize(d.vert and th or d.len, d.vert and d.len or th)

			local phase = d.base % P
			local first = -phase - P
			local count = mfloor((d.len + 2 * P) / P) + 1

			for j = 1, count do
				local s = E.segs[j]
				if not s then
					s = st.frame:CreateTexture(nil, 'OVERLAY', nil, 7)
					s:SetTexture(ANTS_SOLID)
					s:AddMaskTexture(E.mask)
					s.ag = s:CreateAnimationGroup()
					s.ag:SetLooping('REPEAT')
					s.tr = s.ag:CreateAnimation('Translation')
					s.tr:SetSmoothing('NONE')
					E.segs[j] = s
				end
				s.ag:Stop()
				local o = first + (j - 1) * P
				s:SetSize(d.vert and th or dashLen, d.vert and dashLen or th)
				s:ClearAllPoints()
				if d.vert then
					s:SetPoint(d.anchor, st.frame, d.anchor, 0, d.sy >= 0 and o or -o)
				else
					s:SetPoint(d.anchor, st.frame, d.anchor, d.sx >= 0 and o or -o, 0)
				end
				s.tr:SetOffset(d.sx * P, d.sy * P)
				s.tr:SetDuration(step)
				s:Show()
			end
			for j = count + 1, #E.segs do
				E.segs[j].ag:Stop()
				E.segs[j]:Hide()
			end
			E.count = count
		end

		for j = 1, (E.count or 0) do
			local s = E.segs[j]
			if s then
				s:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
				s:Show()
				if not s.ag:IsPlaying() then s.ag:Play() end
			end
		end
	end
end

function ns.AntsStop(owner)
	local st = owner.__kiraAnts
	if not st then return end
	for i = 1, 4 do
		local E = st.edges and st.edges[i]
		if E then
			for _, s in ipairs(E.segs) do
				s.ag:Stop()
				s:Hide()
			end
		end
	end
	st.frame:Hide()
end

local SHAPE_SOLID = [[Interface\Buttons\WHITE8X8]]

function ns.ShapeGlowStart(owner, w, h, opts)
	opts = opts or {}
	local st = owner.__kiraShape
	if not st then
		st = {}
		owner.__kiraShape = st
		st.frame = CreateFrame('Frame', nil, owner)
		st.glow = st.frame:CreateTexture(nil, 'OVERLAY', nil, 5)
		st.glow:SetTexture(SHAPE_SOLID)
		st.glow:SetBlendMode('ADD')
		st.ag = st.glow:CreateAnimationGroup()
		st.ag:SetLooping('BOUNCE')
		st.anim = st.ag:CreateAnimation('Alpha')
		st.anim:SetDuration(0.32)
		st.anim:SetSmoothing('IN_OUT')
	end
	PinToOwnerLevel(st.frame, owner)

	local c = opts.color or { 1, 1, 1, 1 }
	local hi = mmin(0.9, 0.25 + 0.125 * (opts.thickness or 2))
	local lo = hi * 0.5

	st.frame:ClearAllPoints()
	st.frame:SetAllPoints(owner)
	st.frame:Show()

	st.glow:ClearAllPoints()
	st.glow:SetAllPoints(st.frame)
	st.glow:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, 1)
	st.glow:SetAlpha(lo)
	st.glow:Show()

	st.ag:Stop()
	st.anim:SetFromAlpha(lo)
	st.anim:SetToAlpha(hi)
	st.ag:Play()
end

function ns.ShapeGlowStop(owner)
	local st = owner.__kiraShape
	if not st then return end
	st.ag:Stop()
	st.glow:Hide()
	st.frame:Hide()
end

ns.GLOW_TYPES = {
	{ value = 'pixel', text = 'Pixel Glow' },
	{ value = 'shape', text = 'Shape Glow' },
}

function ns.GlowStop(owner)
	if not owner then return end
	ns.AntsStop(owner)
	ns.ShapeGlowStop(owner)
	owner.__glow = false
end

function ns.GlowStart(owner, w, h, cfg)
	if not owner then return end
	if not (cfg and cfg.glow) then ns.GlowStop(owner) return end
	ns.GlowStop(owner)
	if (cfg.glowType or 'pixel') == 'shape' then
		pcall(ns.ShapeGlowStart, owner, w, h, {
			color = cfg.glowColor,
			thickness = cfg.glowThickness,
		})
	else
		pcall(ns.AntsStart, owner, w, h, {
			color = cfg.glowColor,
			thickness = cfg.glowThickness,
			lines = ANTS_LINES,
			freq = ANTS_FREQ,
			length = ANTS_LENGTH,
		})
	end
	owner.__glow = true
end

function ns.GlowMigrate(cfg, defaultColor)
	if type(cfg.glowColor) ~= 'table' and defaultColor then
		cfg.glowColor = ns.CopyValue(defaultColor)
	end
	local t = cfg.glowType
	if t ~= nil and t ~= 'pixel' and t ~= 'shape' then cfg.glowType = 'pixel' end
	cfg.glowLines, cfg.glowFreq, cfg.glowLength = nil, nil, nil
end
