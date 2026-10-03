-- Layout + render support for the mock: resolves anchors into rects (so
-- GetWidth/GetHeight answer like the client does for anchored frames) and
-- turns the visible widget tree into draw operations that run.js writes out
-- as an HTML "screenshot". Approximate by design: no scale, no rotation,
-- text measured from character counts.

local Object = MOCK.Object
local UIW, UIH = UIParent._w, UIParent._h

-- every layout change invalidates the rect cache
local pass = 0
local function Dirty() pass = pass + 1 end

local origSetPoint = Object.SetPoint
function Object:SetPoint(...) Dirty() origSetPoint(self, ...) end
local origClear = Object.ClearAllPoints
function Object:ClearAllPoints() Dirty() origClear(self) end
function Object:SetAllPoints(rel)
	Dirty()
	rel = rel or self._parent or UIParent
	if rel == true then rel = self._parent end
	self._points = { { "TOPLEFT", rel, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0 } }
end
local origSize, origW, origH = Object.SetSize, Object.SetWidth, Object.SetHeight
function Object:SetSize(w, h) Dirty() self._sizeSet = true origSize(self, w, h) end
function Object:SetWidth(w) Dirty() self._sizeSet = true origW(self, w) end
function Object:SetHeight(h) Dirty() self._sizeSet = true origH(self, h) end
local origShow, origHide = Object.Show, Object.Hide
function Object:Show() Dirty() origShow(self) end
function Object:Hide() Dirty() origHide(self) end
local origText = Object.SetText
function Object:SetText(t) Dirty() origText(self, t) end
function Object:SetScrollChild(c) self._scrollChild = c c._scrollParent = self Dirty() end
function Object:SetVerticalScroll(v) self._scroll = v Dirty() end
function Object:GetVerticalScroll() return self._scroll or 0 end

-- colours and text state
function Object:SetColorTexture(r, g, b, a) self._texture = "SOLID" self._color = { r, g, b, a or 1 } end
function Object:SetVertexColor(r, g, b, a) self._vcolor = { r, g, b, a or 1 } end
function Object:SetTextColor(r, g, b, a) self._tcolor = { r, g, b, a or 1 } end
function Object:SetJustifyH(j) self._justify = j end
function Object:SetDrawLayer(layer, sub) self._layer, self._sub = layer, sub end
function Object:SetTexCoord(...) self._coords = { ... } end

local function FontSize(o)
	return (o._font and o._font[2]) or 12
end

function Object:GetStringWidth()
	local t = tostring(self._text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return #t * FontSize(self) * 0.5
end
Object.GetUnboundedStringWidth = Object.GetStringWidth
function Object:GetStringHeight()
	local t = tostring(self._text or "")
	local lines = 1
	for _ in t:gmatch("\n") do lines = lines + 1 end
	return lines * FontSize(self) * 1.2
end

--------------------------------------------------------------------------------
-- Anchor resolution
--------------------------------------------------------------------------------
local function ParsePoint(o, a)
	local point = a[1]
	local i, rel, relPoint, x, y = 2, nil, nil, 0, 0
	local v = a[i]
	if type(v) == "string" and _G[v] and type(_G[v]) == "table" then v = _G[v] end
	if type(v) == "table" then
		rel = v
		i = i + 1
		if type(a[i]) == "string" then relPoint = a[i] i = i + 1 end
	elseif v == nil and a[3] ~= nil then
		i = i + 1
	end
	if type(a[i]) == "number" then x, y = a[i], a[i + 1] or 0 end
	return point, rel or o._parent or UIParent, relPoint or point, x, y
end

local function PX(rect, p)
	if p:find("LEFT") then return rect[1] elseif p:find("RIGHT") then return rect[3] end
	return (rect[1] + rect[3]) / 2
end
local function PY(rect, p)
	if p:find("TOP") then return rect[4] elseif p:find("BOTTOM") then return rect[2] end
	return (rect[2] + rect[4]) / 2
end

local cache, cachePass, visiting = {}, -1, {}

local function Rect(o)
	if o == UIParent then return { 0, 0, UIW, UIH } end
	if cachePass ~= pass then cache, cachePass = {}, pass end
	local hit = cache[o]
	if hit ~= nil then return hit or nil end
	if visiting[o] then return nil end
	visiting[o] = true
	local L, R, CX, T, B, CY
	local sp = o._scrollParent
	if sp then
		local pr = Rect(sp)
		if pr then L, T = pr[1], pr[4] + (sp._scroll or 0) end
	end
	for _, a in ipairs(o._points) do
		local point, rel, relPoint, x, y = ParsePoint(o, a)
		local rr = Rect(rel)
		if rr then
			local ax, ay = PX(rr, relPoint) + x, PY(rr, relPoint) + y
			if point:find("LEFT") then L = ax elseif point:find("RIGHT") then R = ax else CX = ax end
			if point:find("TOP") then T = ay elseif point:find("BOTTOM") then B = ay else CY = ay end
		end
	end
	visiting[o] = nil
	local w, h = o._w or 0, o._h or 0
	if o._kind == "FontString" then
		if not (L and R) and (not o._sizeSet or w == 0) then w = o:GetStringWidth() end
		if not (T and B) and (not o._sizeSet or h == 0) then h = o:GetStringHeight() end
	end
	if not (L or R or CX) or not (T or B or CY) then
		cache[o] = false
		return nil
	end
	if L and R then
	elseif L then R = L + w
	elseif R then L = R - w
	else L, R = CX - w / 2, CX + w / 2 end
	if T and B then
	elseif T then B = T - h
	elseif B then T = B + h
	else B, T = CY - h / 2, CY + h / 2 end
	local r = { L, B, R, T }
	cache[o] = r
	return r
end
MOCK.Rect = Rect

function Object:GetWidth()
	local r = (#self._points > 0 or self._scrollParent) and Rect(self)
	if r and (#self._points > 1 or self._kind == "FontString") then return r[3] - r[1] end
	return self._w
end
function Object:GetHeight()
	local r = (#self._points > 0 or self._scrollParent) and Rect(self)
	if r and (#self._points > 1 or self._kind == "FontString") then return r[4] - r[2] end
	return self._h
end
function Object:GetSize() return self:GetWidth(), self:GetHeight() end
function Object:GetCenter()
	local r = Rect(self)
	if not r then return nil end
	return (r[1] + r[3]) / 2, (r[2] + r[4]) / 2
end
function Object:GetLeft() local r = Rect(self) return r and r[1] end
function Object:GetRight() local r = Rect(self) return r and r[3] end
function Object:GetTop() local r = Rect(self) return r and r[4] end
function Object:GetBottom() local r = Rect(self) return r and r[2] end
function Object:GetVerticalScrollRange()
	local c = self._scrollChild
	if not c then return 0 end
	return math.max(0, (c._h or 0) - self:GetHeight())
end

--------------------------------------------------------------------------------
-- Snapshot
--------------------------------------------------------------------------------
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local LAYER = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }

local function Visible(o)
	while o do
		if not o._shown then return false end
		o = o._parent
	end
	return true
end

local function Alpha(o)
	local a = 1
	while o do a = a * (o._alpha or 1) o = o._parent end
	return a
end

local function Clip(o, r)
	local p = o._parent
	while p do
		if p._kind == "ScrollFrame" then
			local pr = Rect(p)
			if pr then
				r = { math.max(r[1], pr[1]), math.max(r[2], pr[2]), math.min(r[3], pr[3]), math.min(r[4], pr[4]) }
				if r[1] >= r[3] or r[2] >= r[4] then return nil end
			end
		end
		p = p._parent
	end
	return r
end

local function Esc(s)
	return (tostring(s):gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"))
end

local function Color(c)
	if not c then return "null" end
	return ("[%.3f,%.3f,%.3f,%.3f]"):format(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
end

-- Returns a JSON array of draw ops for every visible texture, font string and
-- backdrop, in draw order.
function MOCK.Snapshot()
	local ops = {}
	for idx, o in ipairs(MOCK.frames) do
		local kind = o._kind
		local isRegion = kind == "Texture" or kind == "FontString"
		local isBackdrop = o._backdrop and o._backdrop.edgeFile
		if (isRegion or isBackdrop) and Visible(o) then
			local r = Rect(o)
			r = r and Clip(o, r)
			if r and r[3] - r[1] > 0.1 and r[4] - r[2] > 0.1 then
				local frame = isRegion and o._parent or o
				local strata = STRATA[frame:GetFrameStrata()] or 3
				local level = frame._level or 0
				local layer = LAYER[o._layer or "ARTWORK"] or 3
				local key = ((strata * 10000 + level) * 10 + layer) * 100 + ((o._sub or 0) + 8)
				local alpha = Alpha(o)
				local op
				if kind == "FontString" then
					if o._text and o._text ~= "" then
						op = ('{"t":"text","r":[%.1f,%.1f,%.1f,%.1f],"text":"%s","size":%s,"color":%s,"justify":"%s","font":"%s","a":%.3f'):format(
							r[1], r[2], r[3], r[4], Esc(o._text), FontSize(o), Color(o._tcolor), o._justify or "CENTER",
							Esc(o._font and o._font[1] or ""), alpha)
					end
				elseif isBackdrop then
					op = ('{"t":"outline","r":[%.1f,%.1f,%.1f,%.1f],"color":[0.5,0.5,0.5,1],"a":%.3f'):format(r[1], r[2], r[3], r[4], alpha)
				else
					local tex = o._texture
					local color = o._color or o._vcolor
					if o._color and o._vcolor then
						color = { o._color[1] * o._vcolor[1], o._color[2] * o._vcolor[2], o._color[3] * o._vcolor[3], o._color[4] * o._vcolor[4] }
					end
					if tex ~= nil then
						op = ('{"t":"tex","r":[%.1f,%.1f,%.1f,%.1f],"tex":"%s","color":%s,"desat":%s,"a":%.3f'):format(
							r[1], r[2], r[3], r[4], Esc(tex), Color(color), o._desat and "true" or "false", alpha)
					end
				end
				if op then ops[#ops + 1] = { key = key, idx = idx, json = op .. "}" } end
			end
		end
	end
	table.sort(ops, function(a, b) if a.key ~= b.key then return a.key < b.key end return a.idx < b.idx end)
	local out = {}
	for i, op in ipairs(ops) do out[i] = op.json end
	return "[" .. table.concat(out, ",") .. "]"
end

function Object:SetDesaturated(v) self._desat = v end

function MOCK.Shot(name)
	MOCK.Advance(0.05)
	local crop = MOCK.crop and _G[MOCK.crop] and _G[MOCK.crop]:IsShown() and Rect(_G[MOCK.crop])
	if crop then
		emitsnapshot(name, MOCK.Snapshot(), UIW, UIH, crop[1] - 8, crop[2] - 8, crop[3] + 8, crop[4] + 8)
	else
		emitsnapshot(name, MOCK.Snapshot(), UIW, UIH)
	end
end

-- Things the client does on its own: size-change scripts and slider thumbs.
function Object:SetThumbTexture(t) self._thumb = t t._parent = self end
local origShot = MOCK.Shot
function MOCK.Shot(name)
	for _ = 1, 3 do
		for _, o in ipairs(MOCK.frames) do
			local s = o._scripts and o._scripts.OnSizeChanged
			if s and Visible(o) then
				local w, h = o:GetWidth(), o:GetHeight()
				if o._lastW ~= w or o._lastH ~= h then
					o._lastW, o._lastH = w, h
					s(o, w, h)
				end
			end
		end
		MOCK.Advance(0.05)
	end
	for _, o in ipairs(MOCK.frames) do
		local t = o._thumb
		if t then
			local lo, hi = o:GetMinMaxValues()
			local v = o:GetValue()
			local k = (hi > lo) and (v - lo) / (hi - lo) or 0
			t._points = {}
			t._points[1] = { "CENTER", o, "LEFT", k * o:GetWidth(), 0 }
			Dirty()
		end
	end
	origShot(name)
end
