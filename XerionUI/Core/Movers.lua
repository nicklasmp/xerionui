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
-- each registered frame: drag with the left button, nudge with the arrow keys
-- (Shift = 10px). The grid is on by default and can be switched off with the
-- Grid button (remembered).
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local Style = XUI.Style

local Movers = { list = {}, byFrame = {} }
XUI.Movers = Movers

local floor = math.floor
local GetPath = XUI.GetPath

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

function Movers:Apply(frame)
	local entry = self.byFrame[frame]
	if not entry then return end
	local p = self:GetPosition(entry)
	if type(p) ~= "table" then return end
	frame:ClearAllPoints()
	frame:SetPoint(p.point or "CENTER", UIParent, p.relPoint or p.point or "CENTER", p.x or 0, p.y or 0)
	if p.strata then frame:SetFrameStrata(p.strata) end
end

-- Stores the frame's current screen spot as a CENTER offset from UIParent's
-- centre, rounded to whole units.
function Movers:SaveFromFrame(entry)
	local frame = entry.frame
	local cx, cy = frame:GetCenter()
	local ux, uy = UIParent:GetCenter()
	if not (cx and ux) then return end
	local fs, us = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
	local x = (cx * fs - ux * us) / fs
	local y = (cy * fs - uy * us) / fs
	self:SetOffset(entry, x, y)
end

function Movers:SetOffset(entry, x, y)
	local p = self:GetPosition(entry)
	if type(p) ~= "table" then return end
	local grid = XUI.DB.global.unlock
	if grid.snap and Movers.dragging and not IsShiftKeyDown() then
		local g = grid.gridSize / 4
		x, y = XUI.Round(x, g), XUI.Round(y, g)
	end
	p.point, p.relPoint = "CENTER", "CENTER"
	p.x, p.y = floor(x + 0.5), floor(y + 0.5)
	self:Apply(entry.frame)
end

function Movers:Reset(entry)
	local p, d = self:GetPosition(entry), self:GetDefaultPosition(entry)
	if type(p) ~= "table" or type(d) ~= "table" then return end
	p.point, p.relPoint, p.x, p.y = d.point, d.relPoint, d.x, d.y
	self:Apply(entry.frame)
	entry.module:RefreshSoon()
end

--------------------------------------------------------------------------------
-- Unlock mode
--------------------------------------------------------------------------------
local overlays = {}
local toolbar, grid

local function Accent()
	return XUI.UnpackColor(XUI.DB.global.accent)
end

local function UpdateLabel(ov)
	local p = Movers:GetPosition(ov.entry)
	if Movers.dragging == ov or ov:IsMouseOver() then
		ov.label:SetText(("%s\n|cffaaaaaa%d, %d|r"):format(ov.entry.label, p and p.x or 0, p and p.y or 0))
	else
		ov.label:SetText(ov.entry.label)
	end
end

local function OverlayOnUpdate(ov)
	-- follows the frame while it is dragged and keeps the read-out live
	UpdateLabel(ov)
end

local function CreateOverlay(entry)
	local ov = CreateFrame("Frame", nil, UIParent)
	ov.entry = entry
	ov:SetFrameStrata("DIALOG")
	ov:EnableMouse(true)
	ov:EnableKeyboard(false)
	ov:SetClampedToScreen(true)

	local r, g, b = Accent()
	ov.bg = ov:CreateTexture(nil, "BACKGROUND")
	ov.bg:SetAllPoints()
	ov.bg:SetColorTexture(r, g, b, 0.18)
	local border = Style:Border(ov)
	border:Apply({ useGlobal = false, style = "SOLID", size = 1, color = { r, g, b, 0.9 } })

	ov.label = ov:CreateFontString(nil, "OVERLAY")
	ov.label:SetFont([[Fonts\ARIALN.TTF]], 11, "OUTLINE")
	ov.label:SetPoint("CENTER")
	ov.label:SetTextColor(1, 1, 1)

	ov:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then
			Movers.dragging = self
			self.entry.frame:StartMoving()
			self:SetScript("OnUpdate", OverlayOnUpdate)
		end
	end)
	ov:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" and Movers.dragging == self then
			self.entry.frame:StopMovingOrSizing()
			-- a moved named frame is otherwise saved in layout-local.txt by
			-- the client and put back there at login, fighting our position
			self.entry.frame:SetUserPlaced(false)
			Movers:SaveFromFrame(self.entry)
			Movers.dragging = nil
			self:SetScript("OnUpdate", nil)
			UpdateLabel(self)
		end
	end)
	ov:SetScript("OnEnter", function(self)
		self:EnableKeyboard(true)
		local r, g, b = Accent()
		self.bg:SetColorTexture(r, g, b, 0.32)
		UpdateLabel(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(self.entry.label, 1, 1, 1)
		GameTooltip:AddLine("Drag to move. Arrow keys nudge (Shift: 10).", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	ov:SetScript("OnLeave", function(self)
		self:EnableKeyboard(false)
		local r, g, b = Accent()
		self.bg:SetColorTexture(r, g, b, 0.18)
		UpdateLabel(self)
		GameTooltip:Hide()
	end)
	ov:SetScript("OnKeyDown", function(self, key)
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
		self:SetPropagateKeyboardInput(false)
		local p = Movers:GetPosition(self.entry)
		if p then
			Movers:SetOffset(self.entry, (p.x or 0) + dx, (p.y or 0) + dy)
			UpdateLabel(self)
		end
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
	title:SetFont([[Fonts\ARIALN.TTF]], 13, "")
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
		fs:SetFont([[Fonts\ARIALN.TTF]], 12, "")
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
