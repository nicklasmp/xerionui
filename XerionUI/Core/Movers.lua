--------------------------------------------------------------------------------
-- XerionUI - Core/Movers.lua
-- Positions and unlock mode.
--
-- Every movable display stores its place in one block shape:
--     position = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0, strata = "MEDIUM" }
-- relative to UIParent. Modules register their frame once:
--     XUI.Movers:Register(frame, module, "position")      -- path inside module.db
-- and call XUI.Movers:Apply(frame) from OnRefresh.
--
-- Unlock mode (/xui unlock) previews every enabled module and lays a mover over
-- each registered frame: drag with the left button, click one and nudge it with
-- the arrow keys (Shift = 10px). The grid is on by default and can be switched off with the
-- Grid button (remembered).
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local Style = XUI.Style

local Movers = { list = {}, byFrame = {} }
XUI.Movers = Movers

local floor = math.floor
local GetPath = XUI.GetPath
-- the mover chrome keeps one fixed font, whatever face the user picked for the displays
local UI_FONT = [[Fonts\ARIALN.TTF]]

--------------------------------------------------------------------------------
-- Registration and placement
--------------------------------------------------------------------------------
-- opts.label overrides the module name on the mover; opts.key makes the mover
-- key unique when a module has several frames.
function Movers:Register(frame, module, path, opts)
	opts = opts or {}
	local entry = {
		frame = frame,
		module = module,
		path = path or "position",
		key = "XerionUI_" .. module.key .. (opts.key and ("_" .. opts.key) or ""),
		label = opts.label or module.name,
	}
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	self.list[#self.list + 1] = entry
	self.byFrame[frame] = entry
	XUI:Fire("MoverRegistered", entry)
	if XUI.unlockActive and Movers.overlayMode then Movers:ShowOverlay(entry) end
	return entry
end

function Movers:GetPosition(entry)
	return GetPath(entry.module.db, entry.path)
end

function Movers:GetDefaultPosition(entry)
	return GetPath(entry.module.defaults, entry.path)
end

-- The frame a position is attached to by name (position.attach), if there is
-- one, it exists and it is not the frame itself.
local function AttachTarget(p, frame)
	local name = p.attach
	if type(name) ~= "string" or name == "" then return nil end
	local target = _G[name]
	if type(target) ~= "table" or target == frame or not target.GetObjectType or not target.GetCenter then return nil end
	return target
end

function Movers:Apply(frame)
	local entry = self.byFrame[frame]
	if not entry then return end
	local p = self:GetPosition(entry)
	if type(p) ~= "table" then return end
	frame:ClearAllPoints()
	local target = AttachTarget(p, frame)
	-- an anchor that would loop back to this frame is refused by the client
	if target and pcall(frame.SetPoint, frame, p.point or "CENTER", target, p.relPoint or p.point or "CENTER", p.x or 0, p.y or 0) then
		entry.attached = true
	else
		entry.attached = false
		frame:ClearAllPoints()
		frame:SetPoint(p.point or "CENTER", UIParent, p.relPoint or p.point or "CENTER", p.x or 0, p.y or 0)
	end
	if p.strata then frame:SetFrameStrata(p.strata) end
end

-- Frames other addons build late (EllesmereUI, the Cooldown Manager) are
-- looked for again after loading screens.
local latePlace = CreateFrame("Frame")
latePlace:RegisterEvent("PLAYER_ENTERING_WORLD")
latePlace:SetScript("OnEvent", function()
	C_Timer.After(2, function()
		for _, entry in ipairs(Movers.list) do
			local p = Movers:GetPosition(entry)
			if type(p) == "table" and type(p.attach) == "string" and p.attach ~= "" and entry.module.db.enabled then
				Movers:Apply(entry.frame)
			end
		end
	end)
end)

function Movers:SetOffset(entry, x, y)
	local p = self:GetPosition(entry)
	if type(p) ~= "table" then return end
	local grid = XUI.DB.global.unlock
	if grid.snap and Movers.dragging and not IsShiftKeyDown() then
		local g = grid.gridSize / 4
		x, y = XUI.Round(x, g), XUI.Round(y, g)
	end
	-- attached to another frame, the anchor points are the user's
	if not entry.attached then p.point, p.relPoint = "CENTER", "CENTER" end
	p.x, p.y = floor(x + 0.5), floor(y + 0.5)
	self:Apply(entry.frame)
end

--------------------------------------------------------------------------------
-- Unlock mode
--------------------------------------------------------------------------------
local overlays = {}
local toolbar, grid
local HideGuides, DragUpdate

local function Accent()
	return XUI.UnpackColor(XUI.DB.global.accent)
end

local function Tint(ov)
	local r, g, b = Accent()
	ov.bg:SetColorTexture(r, g, b, (Movers.selected == ov or ov:IsMouseOver()) and 0.32 or 0.18)
end

local function UpdateLabel(ov)
	local p = Movers:GetPosition(ov.entry)
	if Movers.dragging == ov or Movers.selected == ov or ov:IsMouseOver() then
		ov.label:SetText(("%s\n|cffaaaaaa%d, %d|r"):format(ov.entry.label, p and p.x or 0, p and p.y or 0))
	else
		ov.label:SetText(ov.entry.label)
	end
end

--------------------------------------------------------------------------------
-- Dragging: our own, so the position can snap to the grid and to the edges and
-- centres of the other movers (and the middle of the screen) while it moves.
--------------------------------------------------------------------------------
local guides

local function Guides()
	if guides then return guides end
	guides = CreateFrame("Frame", nil, UIParent)
	guides:SetAllPoints(UIParent)
	guides:SetFrameStrata("FULLSCREEN")
	guides.v = guides:CreateTexture(nil, "OVERLAY")
	guides.h = guides:CreateTexture(nil, "OVERLAY")
	local r, g, b = Accent()
	guides.v:SetColorTexture(r, g, b, 0.9)
	guides.h:SetColorTexture(r, g, b, 0.9)
	guides.v:Hide()
	guides.h:Hide()
	return guides
end

HideGuides = function()
	if guides then guides.v:Hide() guides.h:Hide() end
end

local function ShowGuide(vertical, at)
	local gd = Guides()
	local t = vertical and gd.v or gd.h
	t:ClearAllPoints()
	local px = Style:Pixels(gd, 1)
	if vertical then
		t:SetPoint("TOPLEFT", gd, "TOPLEFT", at, 0)
		t:SetPoint("BOTTOMLEFT", gd, "BOTTOMLEFT", at, 0)
		t:SetWidth(px)
	else
		t:SetPoint("BOTTOMLEFT", gd, "BOTTOMLEFT", 0, at)
		t:SetPoint("BOTTOMRIGHT", gd, "BOTTOMRIGHT", 0, at)
		t:SetHeight(px)
	end
	t:Show()
end

-- left, right, bottom, top of a frame in UIParent units
local function ScreenRect(f)
	local l, b, w, h = f:GetRect()
	if not l then return nil end
	local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return l * k, (l + w) * k, b * k, (b + h) * k
end

local SNAP = 6
local function SnapToOthers(entry, k)
	local p = Movers:GetPosition(entry)
	local l, r, b, t = ScreenRect(entry.frame)
	if not (p and l) then HideGuides() return end
	local mineX, mineY = { l, (l + r) / 2, r }, { b, (b + t) / 2, t }
	-- targets: the middle of the screen, then every other shown mover
	local tx, ty = { UIParent:GetWidth() / 2 }, { UIParent:GetHeight() / 2 }
	for _, other in ipairs(Movers.list) do
		if other ~= entry and other.module.db.enabled and other.frame:IsShown() then
			local ol, orr, ob, ot = ScreenRect(other.frame)
			if ol then
				tx[#tx + 1], tx[#tx + 2], tx[#tx + 3] = ol, (ol + orr) / 2, orr
				ty[#ty + 1], ty[#ty + 2], ty[#ty + 3] = ob, (ob + ot) / 2, ot
			end
		end
	end
	local function Best(list, targets)
		local bestD, bestAt
		for _, m in ipairs(list) do
			for _, tg in ipairs(targets) do
				local d = tg - m
				if math.abs(d) <= SNAP and (not bestD or math.abs(d) < math.abs(bestD)) then bestD, bestAt = d, tg end
			end
		end
		return bestD, bestAt
	end
	local dx, atX = Best(mineX, tx)
	local dy, atY = Best(mineY, ty)
	if dx or dy then
		p.x = (p.x or 0) + (dx or 0) / k
		p.y = (p.y or 0) + (dy or 0) / k
		Movers:Apply(entry.frame)
	end
	if atX then ShowGuide(true, atX) elseif guides then guides.v:Hide() end
	if atY then ShowGuide(false, atY) elseif guides then guides.h:Hide() end
end

DragUpdate = function(ov)
	local d = ov.drag
	if not d then return end
	local cx, cy = GetCursorPosition()
	local us = UIParent:GetEffectiveScale()
	local k = ov.entry.frame:GetEffectiveScale() / us
	local dx, dy = cx / us - d.cx, cy / us - d.cy
	if math.abs(dx) + math.abs(dy) > 3 then d.moved = true end
	if not d.moved then return end
	Movers:SetOffset(ov.entry, d.x + dx / k, d.y + dy / k)
	if XUI.DB.global.unlock.snap and not IsShiftKeyDown() then
		SnapToOthers(ov.entry, k)
	else
		HideGuides()
	end
	UpdateLabel(ov)
end

-- The overlay the arrow keys move: the one last clicked, else the one under the mouse.
function Movers:Select(ov)
	local old = self.selected
	self.selected = ov
	if old and old ~= ov then Tint(old) UpdateLabel(old) end
	if ov then Tint(ov) UpdateLabel(ov) end
end

local function KeyTarget()
	if Movers.selected and Movers.selected:IsShown() then return Movers.selected end
	for _, ov in pairs(overlays) do
		if ov:IsShown() and ov:IsMouseOver() then return ov end
	end
end

local function CreateKeys(parent)
	local k = CreateFrame("Frame", nil, parent)
	k:EnableKeyboard(true)
	k:SetPropagateKeyboardInput(true)
	k:SetScript("OnKeyDown", function(self, key)
		local step = IsShiftKeyDown() and 10 or 1
		local dx, dy = 0, 0
		if key == "LEFT" then dx = -step
		elseif key == "RIGHT" then dx = step
		elseif key == "UP" then dy = step
		elseif key == "DOWN" then dy = -step
		else
			self:SetPropagateKeyboardInput(true)
			return
		end
		local ov = KeyTarget()
		if not ov then
			self:SetPropagateKeyboardInput(true)
			return
		end
		self:SetPropagateKeyboardInput(false)
		local p = Movers:GetPosition(ov.entry)
		if p then
			Movers:SetOffset(ov.entry, (p.x or 0) + dx, (p.y or 0) + dy)
			UpdateLabel(ov)
		end
	end)
	return k
end

local function CreateOverlay(entry)
	local ov = CreateFrame("Frame", nil, UIParent)
	ov.entry = entry
	ov:SetFrameStrata("DIALOG")
	ov:EnableMouse(true)
	ov:SetClampedToScreen(true)

	local r, g, b = Accent()
	ov.bg = ov:CreateTexture(nil, "BACKGROUND")
	ov.bg:SetAllPoints()
	ov.bg:SetColorTexture(r, g, b, 0.18)
	local border = Style:Border(ov)
	border:Apply({ useGlobal = false, style = "SOLID", size = 1, color = { r, g, b, 0.9 } })

	ov.label = ov:CreateFontString(nil, "OVERLAY")
	ov.label:SetFont(UI_FONT, 11, "OUTLINE")
	ov.label:SetPoint("CENTER")
	ov.label:SetTextColor(1, 1, 1)

	ov:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" then return end
		local p = Movers:GetPosition(self.entry)
		if type(p) ~= "table" then return end
		Movers:Select(self)
		local cx, cy = GetCursorPosition()
		local us = UIParent:GetEffectiveScale()
		self.drag = { cx = cx / us, cy = cy / us, x = p.x or 0, y = p.y or 0, moved = false }
		Movers.dragging = self
		self:SetScript("OnUpdate", DragUpdate)
	end)
	ov:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" and Movers.dragging == self then
			local moved = self.drag and self.drag.moved
			Movers.dragging = nil
			self.drag = nil
			self:SetScript("OnUpdate", nil)
			HideGuides()
			UpdateLabel(self)
			-- a second click without moving opens the module's settings
			local now = GetTime()
			if not moved and self.lastClick and now - self.lastClick < 0.35 then
				self.lastClick = nil
				XUI:SetUnlocked(false)
				XUI:OpenOptions(self.entry.module.key)
			elseif not moved then
				self.lastClick = now
			end
		end
	end)
	ov:SetScript("OnEnter", function(self)
		Tint(self)
		UpdateLabel(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(self.entry.label, 1, 1, 1)
		GameTooltip:AddLine("Drag to move (hold Shift to turn snapping off). Click it, then the arrow keys nudge (Shift: 10).", 0.7, 0.7, 0.7)
		GameTooltip:AddLine("Double-click to open its settings.", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	ov:SetScript("OnLeave", function(self)
		Tint(self)
		UpdateLabel(self)
		GameTooltip:Hide()
	end)
	return ov
end

function Movers:ShowOverlay(entry)
	if not entry.module.db.enabled then return end
	local ov = overlays[entry]
	if not ov then
		ov = CreateOverlay(entry)
		overlays[entry] = ov
	end
	ov:ClearAllPoints()
	ov:SetPoint("CENTER", entry.frame, "CENTER")
	local w, h = entry.frame:GetSize()
	ov:SetSize(math.max(w or 0, 24), math.max(h or 0, 16))
	UpdateLabel(ov)
	ov:Show()
end

local function CreateGrid()
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetAllPoints(UIParent)
	f:SetFrameStrata("BACKGROUND")
	f.lines = {}
	function f:Build()
		for _, l in ipairs(self.lines) do l:Hide() end
		local size = XUI.DB.global.unlock.gridSize
		local w, h = UIParent:GetSize()
		local n, cx, cy = 0, w / 2, h / 2
		local function Line(vertical, offset, center)
			n = n + 1
			local l = self.lines[n]
			if not l then
				l = self:CreateTexture(nil, "BACKGROUND")
				self.lines[n] = l
			end
			l:ClearAllPoints()
			if center then
				local r, g, b = Accent()
				l:SetColorTexture(r, g, b, 0.5)
			else
				l:SetColorTexture(1, 1, 1, 0.07)
			end
			local t = Style:Pixels(self, 1)
			if vertical then
				l:SetPoint("TOPLEFT", self, "TOPLEFT", offset, 0)
				l:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", offset, 0)
				l:SetWidth(t)
			else
				l:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -offset)
				l:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -offset)
				l:SetHeight(t)
			end
			l:Show()
		end
		for x = 0, cx, size do
			Line(true, cx + x, x == 0)
			if x > 0 then Line(true, cx - x) end
		end
		for y = 0, cy, size do
			Line(false, cy + y, y == 0)
			if y > 0 then Line(false, cy - y) end
		end
	end
	return f
end

local function CreateToolbar()
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(320, 36)
	f:SetPoint("TOP", UIParent, "TOP", 0, -40)
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	local bg = Style:Background(f)
	bg:SetTexture([[Interface\Buttons\WHITE8X8]])
	bg:SetVertexColor(0.08, 0.08, 0.08, 0.95)
	Style:Border(f):Apply({ useGlobal = false, style = "SOLID", size = 1, color = { 0.16, 0.16, 0.16, 1 } })

	local title = f:CreateFontString(nil, "OVERLAY")
	title:SetFont(UI_FONT, 13, "")
	title:SetPoint("LEFT", 12, 0)
	title:SetText(XUI.TITLE .. "  |cffaaaaaaunlocked|r")

	local function Button(text, onClick)
		local b = CreateFrame("Button", nil, f)
		b:SetSize(64, 22)
		local t = b:CreateTexture(nil, "BACKGROUND")
		t:SetAllPoints()
		t:SetColorTexture(0.14, 0.14, 0.14, 1)
		b.bg = t
		local fs = b:CreateFontString(nil, "OVERLAY")
		fs:SetFont(UI_FONT, 12, "")
		fs:SetPoint("CENTER")
		fs:SetText(text)
		b.text = fs
		b:SetScript("OnEnter", function() t:SetColorTexture(0.2, 0.2, 0.2, 1) end)
		b:SetScript("OnLeave", function() t:SetColorTexture(0.14, 0.14, 0.14, 1) end)
		b:SetScript("OnClick", onClick)
		return b
	end

	local done = Button("Done", function() XUI:SetUnlocked(false) end)
	done:SetPoint("RIGHT", -7, 0)
	local gridBtn = Button("Grid", function()
		local on = not grid:IsShown()
		XUI.DB.global.unlock.showGrid = on
		if on then grid:Build() grid:Show() else grid:Hide() end
	end)
	gridBtn:SetPoint("RIGHT", done, "LEFT", -6, 0)
	f.keys = CreateKeys(f)
	return f
end

-- Previews every enabled module and shows the movers.
function XUI:SetUnlocked(on)
	on = on and true or false
	if on and InCombatLockdown() then
		XUI.Print("Unlock mode is not available in combat.")
		return
	end
	if XUI.unlockActive == on and Movers.overlayMode == on then return end
	Movers.overlayMode = on
	self:SetUnlockPreview(on)
	if on then
		toolbar = toolbar or CreateToolbar()
		grid = grid or CreateGrid()
		toolbar:Show()
		if XUI.DB.global.unlock.showGrid ~= false then grid:Build() grid:Show() end
		for _, entry in ipairs(Movers.list) do Movers:ShowOverlay(entry) end
	else
		if toolbar then toolbar:Hide() end
		if grid then grid:Hide() end
		for _, ov in pairs(overlays) do ov:Hide() end
		Movers.selected = nil
	end
end

-- Turns the "everything previews" state on or off and refreshes the modules.
function XUI:SetUnlockPreview(on)
	if XUI.unlockActive == on then return end
	XUI.unlockActive = on
	for _, m in ipairs(XUI.modules) do
		if m.db.enabled then m:Refresh() end
	end
	-- overlays follow their frames' sizes once the previews have laid out
	if on and Movers.overlayMode then
		C_Timer.After(0, function()
			for _, entry in ipairs(Movers.list) do
				if overlays[entry] and overlays[entry]:IsShown() then Movers:ShowOverlay(entry) end
			end
		end)
	end
	XUI:Fire("UnlockModeChanged", on)
end

function XUI:ToggleUnlocked()
	self:SetUnlocked(not (self.unlockActive and Movers.overlayMode))
end

local combat = CreateFrame("Frame")
combat:RegisterEvent("PLAYER_REGEN_DISABLED")
combat:SetScript("OnEvent", function()
	if Movers.overlayMode then XUI:SetUnlocked(false) end
end)
