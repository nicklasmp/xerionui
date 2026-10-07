--------------------------------------------------------------------------------
-- XerionUI - Core/Glow.lua
-- Script-free glows: everything moves through AnimationGroups, which the
-- client runs in C. That makes them
--   * cheap: no Lua OnUpdate per glowing frame (LibCustomGlow's pixel glow
--     runs one), and
--   * safe on the engine's aura buttons (AuraContainer): scripts on those
--     buttons' children never run and setting one there can take the whole
--     frame batch down, but animations play.
-- Style:ShowGlow uses these for the PIXEL and PULSE types.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI

local Glow = {}
XUI.Glow = Glow

local WHITE = [[Interface\Buttons\WHITE8X8]]
local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local function Level(frame, owner, offset)
	local ok, lvl = pcall(owner.GetFrameLevel, owner)
	if ok and type(lvl) == "number" then pcall(frame.SetFrameLevel, frame, lvl + offset) end
end

-- The owner's size. With o.fixed the caller's o.width/o.height rule: an engine
-- button's host reads 0 or 1 until the engine has laid it out, and only the
-- caller knows what the button is sized to. Otherwise a host that reads no size
-- falls back to o.width/o.height, and the third answer says the size is fixed.
local function Size(owner, o)
	if o and o.fixed and o.width and o.height and o.width > 0 and o.height > 0 then return o.width, o.height, true end
	local ok, w, h = pcall(owner.GetSize, owner)
	local unknown = not ok or XUI.IsSecret(w) or XUI.IsSecret(h) or not w or w <= 0 or not h or h <= 0
	if unknown and o and o.width and o.height and o.width > 0 and o.height > 0 then return o.width, o.height end
	if not ok or XUI.IsSecret(w) or XUI.IsSecret(h) then return nil end
	return w, h
end

--------------------------------------------------------------------------------
-- Ants: dashes running round the frame's edge.
-- Each edge is a strip with a mask; its dashes sit one spacing apart and all
-- slide one spacing forward on a looping translation, so the pattern looks
-- continuous. Edges are phased by their distance along the perimeter, so the
-- dashes turn the corners in step.
--------------------------------------------------------------------------------
-- anchor, vertical, length key, perimeter base key, direction
local EDGES = {
	{ "TOPLEFT", false, "w", 0, 1, 0 },
	{ "TOPRIGHT", true, "h", 1, 0, -1 },
	{ "BOTTOMRIGHT", false, "w", 2, -1, 0 },
	{ "BOTTOMLEFT", true, "h", 3, 0, 1 },
}

local function EdgeBase(i, w, h)
	if i == 1 then return 0 elseif i == 2 then return w elseif i == 3 then return w + h end
	return w + h + w
end

-- o: color {r,g,b,a}, lines, frequency (laps per second; negative reverses),
-- length (0 = half the spacing), thickness (UI units), offset (UI units).
function Glow.StartAnts(owner, o)
	local st = owner.__xuiAnts
	if not st then
		st = { edges = {} }
		st.frame = CreateFrame("Frame", nil, owner)
		owner.__xuiAnts = st
	end
	local f = st.frame
	Level(f, owner, 4)
	local off = o.offset or 0
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", owner, "TOPLEFT", -off, off)
	f:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", off, -off)

	local w, h, fixed = Size(owner, o)
	if not w or w <= 0 or h <= 0 then
		f:Hide()
		return
	end
	w, h = w + 2 * off, h + 2 * off
	if fixed then
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", owner, "TOPLEFT", -off, off)
		f:SetSize(w, h)
	end

	local lines = max(1, floor(o.lines or 8))
	local freq = o.frequency or 0.25
	if freq == 0 then freq = 0.25 end
	local reverse = freq < 0
	local period = 1 / abs(freq)
	local th = (o.thickness and o.thickness > 0) and o.thickness or 1
	local P = 2 * (w + h) / lines
	local dash = (o.length and o.length > 0) and min(o.length, P) or P * 0.5
	dash = max(1, dash)
	local step = max(0.001, period / lines)
	local r, g, b, a = XUI.UnpackColor(o.color)

	local sig = ("%.2f:%.2f:%d:%.3f:%.2f:%.2f:%s"):format(w, h, lines, period, th, dash, tostring(reverse))
	local rebuild = st.sig ~= sig
	st.sig = sig

	for i, d in ipairs(EDGES) do
		local anchor, vertical, sx, sy = d[1], d[2], d[5], d[6]
		local len = vertical and h or w
		local E = st.edges[i]
		if not E then
			E = { segs = {} }
			E.mask = f:CreateMaskTexture()
			E.mask:SetTexture(WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			st.edges[i] = E
		end
		if rebuild then
			E.mask:ClearAllPoints()
			E.mask:SetPoint(anchor, f, anchor, 0, 0)
			E.mask:SetSize(vertical and th or len, vertical and len or th)
			local phase = EdgeBase(i, w, h) % P
			local first = -phase - P
			local count = floor((len + 2 * P) / P) + 1
			local dir = reverse and -1 or 1
			for j = 1, count do
				local s = E.segs[j]
				if not s then
					s = f:CreateTexture(nil, "OVERLAY", nil, 7)
					s:SetTexture(WHITE)
					s:AddMaskTexture(E.mask)
					s.ag = s:CreateAnimationGroup()
					s.ag:SetLooping("REPEAT")
					s.tr = s.ag:CreateAnimation("Translation")
					s.tr:SetSmoothing("NONE")
					E.segs[j] = s
				end
				s.ag:Stop()
				local pos = first + (j - 1) * P
				s:SetSize(vertical and th or dash, vertical and dash or th)
				s:ClearAllPoints()
				s:SetPoint(anchor, f, anchor, sx * pos, sy * pos)
				s.tr:SetOffset(sx * P * dir, sy * P * dir)
				s.tr:SetDuration(step)
			end
			for j = count + 1, #E.segs do
				E.segs[j].ag:Stop()
				E.segs[j]:Hide()
			end
			E.count = count
		end
	end
	-- color every pass; start all dashes together so they stay in step
	for _, E in ipairs(st.edges) do
		for j = 1, E.count or 0 do
			local s = E.segs[j]
			s:SetVertexColor(r, g, b, a)
			s:Show()
			if rebuild or not s.ag:IsPlaying() then s.ag:Play() end
		end
	end
	f:Show()
end

function Glow.StopAnts(owner)
	local st = owner.__xuiAnts
	if not st then return end
	for _, E in ipairs(st.edges) do
		for _, s in ipairs(E.segs) do
			s.ag:Stop()
			s:Hide()
		end
	end
	st.frame:Hide()
end

--------------------------------------------------------------------------------
-- Pulse: a soft additive wash over the frame that breathes in and out.
--------------------------------------------------------------------------------
function Glow.StartPulse(owner, o)
	local st = owner.__xuiPulse
	if not st then
		st = {}
		st.frame = CreateFrame("Frame", nil, owner)
		st.frame:SetAllPoints(owner)
		st.tex = st.frame:CreateTexture(nil, "OVERLAY", nil, 5)
		st.tex:SetTexture(WHITE)
		st.tex:SetBlendMode("ADD")
		st.tex:SetAllPoints(st.frame)
		st.ag = st.tex:CreateAnimationGroup()
		st.ag:SetLooping("BOUNCE")
		st.anim = st.ag:CreateAnimation("Alpha")
		st.anim:SetSmoothing("IN_OUT")
		owner.__xuiPulse = st
	end
	Level(st.frame, owner, 4)
	local r, g, b = XUI.UnpackColor(o.color)
	local freq = abs(o.frequency or 0.25)
	if freq == 0 then freq = 0.25 end
	local hi = min(0.9, 0.25 + 0.1 * (o.thickness or 2))
	st.tex:SetVertexColor(r, g, b, 1)
	st.ag:Stop()
	st.anim:SetFromAlpha(hi * 0.3)
	st.anim:SetToAlpha(hi)
	st.anim:SetDuration(max(0.1, 0.125 / freq))
	st.tex:SetAlpha(hi * 0.3)
	st.frame:Show()
	st.ag:Play()
end

function Glow.StopPulse(owner)
	local st = owner.__xuiPulse
	if not st then return end
	st.ag:Stop()
	st.frame:Hide()
end

--------------------------------------------------------------------------------
-- Shine: the autocast look - sparks travelling round the edge - without a
-- script. Each spark is a texture on a chain of four translations (the four
-- sides), started at its own place on the perimeter, so a loop ends where it
-- began and the sparks stay evenly spaced. This is the Autocast shine on the
-- engine's aura buttons, where LibCustomGlow's OnUpdate version cannot run.
--------------------------------------------------------------------------------
local SPARK = [[Interface\Artifacts\Blizzard_Spark]]

-- One spark: its texture and the looping chain of five translations.
local function NewSpark(f)
	local sp = { tex = f:CreateTexture(nil, "OVERLAY", nil, 7) }
	sp.tex:SetTexture(SPARK)
	sp.tex:SetBlendMode("ADD")
	sp.ag = sp.tex:CreateAnimationGroup()
	sp.ag:SetLooping("REPEAT")
	sp.moves = {}
	for k = 1, 5 do
		local m = sp.ag:CreateAnimation("Translation")
		m:SetSmoothing("NONE")
		m:SetOrder(k)
		sp.moves[k] = m
	end
	sp.tex:Hide()
	return sp
end

-- Makes every region the shine will ever need, hidden. An engine button's
-- subtree is closed to addon code once the button has been created, so on a
-- host that sits in one this has to run in the creation window; StartShine then
-- only configures (and draws at most `count` sparks).
function Glow.PrewarmShine(owner, count)
	local st = owner.__xuiShine
	if not st then
		st = { sparks = {} }
		st.frame = CreateFrame("Frame", nil, owner)
		st.frame:Hide()
		owner.__xuiShine = st
	end
	for i = #st.sparks + 1, count or 4 do st.sparks[i] = NewSpark(st.frame) end
	st.locked = true
end

-- o: color, particles (sparks), frequency (laps per second), scale, offset
function Glow.StartShine(owner, o)
	local st = owner.__xuiShine
	if not st then
		st = { sparks = {} }
		st.frame = CreateFrame("Frame", nil, owner)
		owner.__xuiShine = st
	end
	local f = st.frame
	Level(f, owner, 4)
	local off = o.offset or 0
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", owner, "TOPLEFT", -off, off)
	f:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", off, -off)

	local w, h, fixed = Size(owner, o)
	if not w or w <= 0 or h <= 0 then
		f:Hide()
		return
	end
	w, h = w + 2 * off, h + 2 * off
	-- a fixed size is the frame's own: it no longer follows the host's
	if fixed then
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", owner, "TOPLEFT", -off, off)
		f:SetSize(w, h)
	end
	local n = max(1, floor(o.particles or 4))
	-- a prewarmed host cannot make another spark
	if st.locked then n = min(n, #st.sparks) end
	local freq = abs(o.frequency or 0.25)
	if freq == 0 then freq = 0.25 end
	local period = 1 / freq
	local size = max(6, 9 * (o.scale or 1))
	local r, g, b, a = XUI.UnpackColor(o.color)
	local sig = ("%.2f:%.2f:%d:%.3f:%.2f"):format(w, h, n, period, size)
	local rebuild = st.sig ~= sig
	st.sig = sig

	if rebuild then
		local P = 2 * (w + h)
		local speed = P / period
		-- the four sides, clockwise from the top left: length, direction
		local sides = { { w, 1, 0 }, { h, 0, -1 }, { w, -1, 0 }, { h, 0, 1 } }
		for i = 1, n do
			local sp = st.sparks[i]
			if not sp then
				sp = NewSpark(f)
				st.sparks[i] = sp
			end
			sp.ag:Stop()
			-- where along the perimeter this spark starts
			local d = (i - 1) * P / n
			local side, into = 1, d
			while side < 4 and into >= sides[side][1] do into = into - sides[side][1] side = side + 1 end
			local len, dx, dy = sides[side][1], sides[side][2], sides[side][3]
			local sx, sy
			if side == 1 then sx, sy = into, 0
			elseif side == 2 then sx, sy = w, -into
			elseif side == 3 then sx, sy = w - into, -h
			else sx, sy = 0, -(h - into) end
			sp.tex:SetSize(size, size)
			sp.tex:ClearAllPoints()
			sp.tex:SetPoint("CENTER", f, "TOPLEFT", sx, sy)
			-- the rest of this side, the three after it, then the part already walked
			local function Move(k, length, ddx, ddy)
				sp.moves[k]:SetOffset(ddx * length, ddy * length)
				sp.moves[k]:SetDuration(max(0.001, length / speed))
			end
			Move(1, len - into, dx, dy)
			for k = 1, 3 do
				local s2 = sides[(side + k - 1) % 4 + 1]
				Move(k + 1, s2[1], s2[2], s2[3])
			end
			Move(5, into, dx, dy)
		end
		for i = n + 1, #st.sparks do
			st.sparks[i].ag:Stop()
			st.sparks[i].tex:Hide()
		end
		st.count = n
	end
	for i = 1, st.count or 0 do
		local sp = st.sparks[i]
		sp.tex:SetVertexColor(r, g, b, a)
		sp.tex:Show()
		if rebuild or not sp.ag:IsPlaying() then sp.ag:Play() end
	end
	f:Show()
end

function Glow.StopShine(owner)
	local st = owner.__xuiShine
	if not st then return end
	for _, sp in ipairs(st.sparks) do
		sp.ag:Stop()
		sp.tex:Hide()
	end
	st.frame:Hide()
end
