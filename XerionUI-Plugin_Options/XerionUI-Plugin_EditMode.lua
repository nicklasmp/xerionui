local _G = _G
local ns = _G.XerionUIPlugin and _G.XerionUIPlugin.__ns
if not ns then return end

local CreateFrame = CreateFrame
local UIParent = UIParent
local pairs, ipairs, type, pcall = pairs, ipairs, type, pcall
local mfloor = math.floor

ns.hasEditMode = true

local ORANGE = { 1, 0.49, 0.04 }

local PURPLE = { 0.68, 0.36, 1.00 }

local STEEL = { 0.42, 0.66, 0.90 }

local MOVABLES = {
	{ label = 'CC Tracker',       frame = 'XerionUICCBars',          db = 'ccBars',         page = 'cctracker',   apply = 'CCBApply',   preview = 'CCBSetPreview' },
	{ label = 'CC Cast Notices',  frame = 'XerionUI_CCCastNotices',  db = 'ccCastNotices',  page = 'cccasts',     apply = 'CCCastApply', preview = 'CCCastSetPreview' },
	{ label = 'No Target',        frame = 'XerionUINoTarget',        db = 'combatText',     page = 'combattext',  apply = 'CTApply',    preview = 'CTSetPreview', xKey = 'noTargetX', yKey = 'noTargetY' },
	{ label = 'Co-Tank',          frame = 'XerionUICoTank',          db = 'cotank',         page = 'cotank',      apply = 'CoTApply',   preview = 'CoTSetPreview' },
	{ label = 'Control Undead',   frame = 'XerionUIControlUndead',   db = 'controlUndead',  page = 'class_dk',    apply = 'CUApply',    preview = 'CUSetPreview' },
	{ label = 'Blightfall chain', frame = 'XerionUIBlightfall',      db = 'blightfall',     page = 'class_dk',    apply = 'BLFApply',   preview = 'BLFSetPreview' },
	{ label = 'Forbidden Sacrifice', frame = 'XerionUIPutrefy',         db = 'putrefy',        page = 'class_dk',    apply = 'PFApply',    preview = 'PFSetPreview' },
	{ label = 'Boiling Point',    frame = 'XerionUIBoilingPoint',    db = 'boilingPoint',   page = 'class_dk',    apply = 'BPApply',    preview = 'BPSetPreview' },
	{ label = 'The Blood is Life', frame = 'XerionUIBloodIsLife',    db = 'bloodIsLife',    page = 'class_dk',    apply = 'BILApply',   preview = 'BILSetPreview', unless = 'euiAnchor' },
	{ label = 'Bloodbeast damage', frame = 'XerionUIBloodBeast',     db = 'bloodBeast',     page = 'class_dk',    apply = 'BBApply',    preview = 'BBSetPreview' },
	{ label = 'Reaper\'s Mark',   frame = 'XerionUIReapersMark',     db = 'reapersMark',    page = 'class_dk',    apply = 'RKMApply',   preview = 'RKMSetPreview', unless = 'euiAnchor' },
	{ label = 'Aggro Check',      frame = 'XerionUIAggroCheck',      db = 'aggroCheck',     page = 'aggrocheck',  apply = 'AGCApply',   preview = 'AGCSetPreview' },
	{ label = 'Reminders - countdowns', frame = 'XerionUIDungeonAlerts', db = 'dungeonAlerts', page = 'dungeonalerts', apply = 'DAApply', preview = 'DASetPreview', color = PURPLE },
	{ label = 'Reminders - casts',      frame = 'XerionUIDungeonCasts',   db = 'dungeonAlerts', page = 'dungeonalerts', apply = 'DAApply', preview = 'DASetPreview', color = PURPLE, xKey = 'castX', yKey = 'castY' },
	{ label = 'Reminders - cast circles', frame = 'XerionUIDungeonCircles', db = 'dungeonAlerts', page = 'dungeonalerts', apply = 'DAApply', preview = 'DASetPreview', color = PURPLE, xKey = 'castCircleX', yKey = 'castCircleY' },
	{ label = 'Reminders - announcement', frame = 'XerionUIDungeonAnnounce', db = 'dungeonAlerts', page = 'dungeonalerts', apply = 'DAApply', preview = 'DASetPreview', color = PURPLE, xKey = 'announceX', yKey = 'announceY' },
	{ label = 'Reminders - boss HP',      frame = 'XerionUIDungeonBossHP',      db = 'dungeonAlerts', page = 'dungeonalerts', apply = 'DAApply', preview = 'DASetPreview', color = PURPLE, xKey = 'hpX', yKey = 'hpY' },
	{ label = 'Reminders - wrong target', frame = 'XerionUIDungeonWrongTarget', db = 'dungeonAlerts', page = 'dungeonalerts', apply = 'DAApply', preview = 'DASetPreview', color = PURPLE, xKey = 'wtX', yKey = 'wtY' },
	{ label = 'Externals',        frame = 'XerionUIExternals',       db = 'externals',      page = 'externals',   apply = 'ExtApply',   preview = 'ExtSetPreview' },
	{ label = 'Fiery Brand',      frame = 'XerionUIFieryBrand',      db = 'fieryBrand',     page = 'class_veng',  apply = 'FBApply',    preview = 'FBSetPreview' },
	{ label = 'Interrupts',       frame = 'XerionUIInterrupts',      db = 'interrupts',     page = 'interrupts',  apply = 'IKApply',    preview = 'IKSetPreview' },
	{ label = 'Shroud/Invis Bar', frame = 'XerionUIShroud',          db = 'shroud',         page = 'shroud',      apply = 'SHApply',    preview = 'SHSetPreview' },
	{ label = 'WoG bar',          frame = 'XerionUIShiningLight',    db = 'shiningLight',   page = 'class_prot',  apply = 'SLApply',    preview = 'SLSetPreview', xKey = 'barX', yKey = 'barY' },
	{ label = 'Paladin Aura',     frame = 'XerionUIPaladinAura',     db = 'paladinAura',    page = 'class_prot',  apply = 'PAUApply',   preview = 'PAUSetPreview' },
	{ label = 'Stoneform',        frame = 'XerionUIStoneform',       db = 'stoneform',      page = 'stoneform',   apply = 'SFMApply',   preview = 'SFMSetPreview' },
	{ label = 'Alter Time',       frame = 'XerionUIAlterTimeHP',     db = 'mageAlterTime',  page = 'class_mage',  apply = 'MageApply',  preview = 'MageSetPreview' },
	{ label = 'Bear Form',        frame = 'XerionUIBearForm',        db = 'bearForm',       page = 'class_druid', apply = 'BFRApply',   preview = 'BFRSetPreview' },
	{ label = 'Reflect damage',   frame = 'XerionUIReflect',         db = 'reflectDamage',  page = 'class_warrior', apply = 'RFLApply', preview = 'RFLSetPreview' },

	{ label = 'EUI debuff borders', frame = 'XerionUITBPreview',      db = 'euiDebuffColors', page = 'eui_player', apply = 'EUIApplyDebuffColors', preview = 'EUITBSetPreview', static = true, color = STEEL },

}

local function Cfg(m)
	local db = _G.XerionUIChangesDB
	return db and db[m.db]
end

-- unless: a key that, while set, moves the frame off x/y - The Blood is Life
-- and Reaper's Mark riding an EllesmereUI group keep an offset from the group
-- instead, so edit mode leaves them alone (a drag would write x/y they ignore).
local function IsOn(m)
	local c = Cfg(m)
	return c and c.enable and not (m.unless and c[m.unless]) and true or false
end

local function PosTable(m)
	local c = Cfg(m)
	if not c then return nil end
	if m.nested then
		c.pos = c.pos or {}
		return c.pos
	end
	return c
end

local function XKey(m) return m.xKey or 'x' end
local function YKey(m) return m.yKey or 'y' end

local function Key(m) return m.db .. '|' .. XKey(m) end

local function GetXY(m)
	local t = PosTable(m)
	if not t then return 0, 0 end
	return t[XKey(m)] or 0, t[YKey(m)] or 0
end

local function SetXY(m, x, y)
	local t = PosTable(m)
	if not t then return end
	t[XKey(m)], t[YKey(m)] = x, y
end

local function Frm(m)
	local f = _G[m.frame]
	if type(f) == 'table' and f.GetObjectType then return f end
	return nil
end

local placedBySelf = {}

local function EnsurePlaced(m, f)
	if m.static then return end
	if not f or f:GetCenter() then return end
	local x, y = GetXY(m)
	local ok = pcall(function()
		f:ClearAllPoints()
		f:SetPoint('CENTER', UIParent, 'CENTER', x, y)
	end)
	if ok then placedBySelf[Key(m)] = true end
	return ok
end

local function RePlaceIfOurs(m, f)
	if not f or not placedBySelf[Key(m)] then return end
	local x, y = GetXY(m)
	pcall(function()
		f:ClearAllPoints()
		f:SetPoint('CENTER', UIParent, 'CENTER', x, y)
	end)
end

local active, dirty = false, false
local snapshot = {}
local overlays = {}
local panel
local selected
local ApplyOne, Rebuild, Stop, Select, Nudge, RefreshReadout

local function TakeSnapshot()
	snapshot = {}
	for _, m in ipairs(MOVABLES) do
		if Cfg(m) and not m.static then
			local x, y = GetXY(m)
			snapshot[Key(m)] = { x = x, y = y }
		end
	end
	dirty = false
end

local function RestoreSnapshot()
	for _, m in ipairs(MOVABLES) do
		local c, snap = Cfg(m), snapshot[Key(m)]
		if c and snap then
			SetXY(m, snap.x, snap.y)
			ApplyOne(m)
		end
	end
	dirty = false
end

function ApplyOne(m)
	local f = m.apply and ns[m.apply]
	if type(f) == 'function' then pcall(f) end
end

local UNSEL = { fill = 0.10, edge = 0.55 }
local SEL   = { fill = 0.28, edge = 1.00 }

local function Paint(o)
	local isSel = (selected == o)
	local look = isSel and SEL or UNSEL
	local C = (o.spec and o.spec.color) or ORANGE
	o.bg:SetColorTexture(C[1], C[2], C[3], look.fill)
	for _, t in ipairs(o.edges) do
		t:SetColorTexture(C[1], C[2], C[3], look.edge)
		t:SetHeight(t.horiz and (isSel and 2 or 1) or t:GetHeight())
		if not t.horiz then t:SetWidth(isSel and 2 or 1) end
	end
	o.label:SetTextColor(C[1], C[2], C[3])
	o.tools:SetShown(isSel and not o.spec.static)
end

function Nudge(o, dx, dy)
	if o.spec.static or not Cfg(o.spec) then return end
	local x, y = GetXY(o.spec)
	SetXY(o.spec, x + dx, y + dy)
	dirty = true
	ApplyOne(o.spec)
	RePlaceIfOurs(o.spec, Frm(o.spec))
	RefreshReadout(o)
	Rebuild()
end

function RefreshReadout(o)
	if o.spec.static or not Cfg(o.spec) then return end
	local x, y = GetXY(o.spec)
	o.readout:SetFormattedText('X %d   Y %d', x, y)
end

function Select(o)
	local prev = selected
	selected = o
	if prev and prev ~= o then Paint(prev) end
	if o then Paint(o) RefreshReadout(o) end
end

local function MakeOverlay(m)
	local o = CreateFrame('Frame', nil, UIParent)
	o:SetFrameStrata('FULLSCREEN_DIALOG')
	o:EnableMouse(true)
	o:RegisterForDrag('LeftButton')
	o.spec = m

	local bg = o:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints()
	o.bg = bg

	local edges = {}
	for i = 1, 4 do
		local t = o:CreateTexture(nil, 'OVERLAY')
		edges[i] = t
	end
	edges[1].horiz, edges[2].horiz = true, true
	edges[1]:SetPoint('TOPLEFT') edges[1]:SetPoint('TOPRIGHT') edges[1]:SetHeight(1)
	edges[2]:SetPoint('BOTTOMLEFT') edges[2]:SetPoint('BOTTOMRIGHT') edges[2]:SetHeight(1)
	edges[3]:SetPoint('TOPLEFT') edges[3]:SetPoint('BOTTOMLEFT') edges[3]:SetWidth(1)
	edges[4]:SetPoint('TOPRIGHT') edges[4]:SetPoint('BOTTOMRIGHT') edges[4]:SetWidth(1)
	o.edges = edges

	local label = o:CreateFontString(nil, 'OVERLAY')
	label:SetFont(ns.GetFont(), 11, 'OUTLINE')
	label:SetPoint('BOTTOM', o, 'TOP', 0, 2)
	label:SetText(m.label)
	o.label = label

	local tools = CreateFrame('Frame', nil, o)
	tools:SetFrameStrata('FULLSCREEN_DIALOG')
	tools:SetFrameLevel(o:GetFrameLevel() + 10)
	tools:SetSize(96, 46)
	tools:SetPoint('TOP', o, 'BOTTOM', 0, -6)
	tools:Hide()
	o.tools = tools

	local tbg = tools:CreateTexture(nil, 'BACKGROUND')
	tbg:SetAllPoints()
	tbg:SetColorTexture(0.055, 0.055, 0.065, 0.95)

	local readout = tools:CreateFontString(nil, 'OVERLAY')
	readout:SetFont(ns.GetFont(), 11, 'OUTLINE')
	readout:SetPoint('BOTTOM', tools, 'BOTTOM', 0, 4)
	readout:SetTextColor(1, 1, 1)
	o.readout = readout

	local function Arrow(rot, ox, oy, dx, dy)
		local b = CreateFrame('Button', nil, tools)
		b:SetSize(18, 16)
		b:SetPoint('TOP', tools, 'TOP', ox, oy)
		local t = b:CreateTexture(nil, 'ARTWORK')
		t:SetAllPoints()
		t:SetTexture([[Interface\ChatFrame\ChatFrameExpandArrow]])
		t:SetRotation(rot)
		b:SetScript('OnClick', function()
			local step = _G.IsShiftKeyDown and _G.IsShiftKeyDown() and 10 or 1
			Nudge(o, dx * step, dy * step)
		end)
		b:SetScript('OnEnter', function() t:SetVertexColor(1, 0.82, 0) end)
		b:SetScript('OnLeave', function() t:SetVertexColor(1, 1, 1) end)
		return b
	end
	Arrow(math.pi / 2,  0, -2,  0,  1)
	Arrow(-math.pi / 2, 0, -20, 0, -1)
	Arrow(math.pi,     -20, -11, -1, 0)
	Arrow(0,            20, -11,  1, 0)

	o:SetScript('OnEnter', function(self)
		if selected ~= self then
			local C = m.color or ORANGE
			self.bg:SetColorTexture(C[1], C[2], C[3], 0.20)
		end
		_G.GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
		_G.GameTooltip:AddLine(m.label, 1, 1, 1)
		if m.static then
			_G.GameTooltip:AddLine('Shown here so you can see it - EllesmereUI places this one.',
				0.8, 0.8, 0.8)
			_G.GameTooltip:AddLine('/eui  >  Unit Frames  >  Buffs and Debuffs', 1, 0.82, 0)
		else
			_G.GameTooltip:AddLine('Left-click to select, drag to move', 0.8, 0.8, 0.8)
			_G.GameTooltip:AddLine('Arrow keys nudge 1px (Shift = 10)', 0.8, 0.8, 0.8)
		end
		_G.GameTooltip:AddLine('Right-click for settings', 0.8, 0.8, 0.8)
		_G.GameTooltip:Show()
	end)
	o:SetScript('OnLeave', function(self)
		Paint(self)
		_G.GameTooltip:Hide()
	end)

	o:SetScript('OnMouseDown', function(self, button)
		if button == 'LeftButton' then Select(self) end
	end)

	o:SetScript('OnDragStart', function(self)
		if self.spec.static then return end
		local f = Frm(self.spec)
		if not f then return end
		Select(self)
		self.moving = f
		f:SetMovable(true)
		f:StartMoving()
	end)
	o:SetScript('OnDragStop', function(self)
		local f = self.moving
		self.moving = nil
		if not f then return end
		f:StopMovingOrSizing()
		local cx, cy = f:GetCenter()
		local ux, uy = UIParent:GetCenter()
		if Cfg(self.spec) and cx and ux then
			SetXY(self.spec, mfloor(cx - ux + 0.5), mfloor(cy - uy + 0.5))
			dirty = true
		end
		ApplyOne(self.spec)
		RePlaceIfOurs(self.spec, f)
		RefreshReadout(self)
		Rebuild()
	end)

	o:SetScript('OnMouseUp', function(self, button)
		if button ~= 'RightButton' then return end
		Select(self)
		if ns.ShowConfigPage and self.spec.page then
			pcall(ns.ShowConfigPage, self.spec.page)
		elseif ns.OpenConfig then
			ns.OpenConfig()
		end
	end)

	Paint(o)
	return o
end

-- The overlay covers everything the frame shows, not just the frame: several
-- modules pin their FIRST row or icon to the saved spot and hang the rest
-- outside it (DRAG ANYTHING THE PREVIEW SHOWS in the core), and an overlay the
-- size of the frame left a five-row preview with one grabbable row. It is
-- anchored to the frame, so it rides along while the frame is dragged. Frames
-- the core cannot measure keep the old frame-sized box.
local function FitOverlay(o, f)
	local l, b, r, t
	if ns.ContentBounds then l, b, r, t = ns.ContentBounds(f) end
	local ok, fl, fb = pcall(f.GetScaledRect, f)
	local s = o:GetEffectiveScale()
	local secret = ns.IsSecret
	o:ClearAllPoints()
	if l and ok and not secret(fl) and not secret(fb) and fl and fb and s and s > 0 then
		o:SetSize(math.max((r - l) / s, 24), math.max((t - b) / s, 24))
		o:SetPoint('CENTER', f, 'BOTTOMLEFT', ((l + r) / 2 - fl) / s, ((b + t) / 2 - fb) / s)
		return
	end
	local w, h = f:GetWidth(), f:GetHeight()
	o:SetSize(math.max(w or 0, 24), math.max(h or 0, 24))
	o:SetPoint('CENTER', f, 'CENTER', 0, 0)
end

function Rebuild()
	if not active then return end
	for _, m in ipairs(MOVABLES) do
		local f = IsOn(m) and Frm(m) or nil
		local o = overlays[Key(m)]
		if f then EnsurePlaced(m, f) end
		if f and f:IsShown() and f:GetCenter() then
			if not o then o = MakeOverlay(m) overlays[Key(m)] = o end
			FitOverlay(o, f)
			o:Show()
		elseif o then
			o:Hide()
		end
	end
end

local GRID_STEP = 40
local grid

local function GridShown()
	local db = _G.XerionUIChangesDB
	if not db then return true end
	return db.editGrid ~= false
end

local function LayoutGrid()
	if not grid then
		grid = CreateFrame('Frame', 'XerionUIEditModeGrid', UIParent)
		grid:SetAllPoints(UIParent)
		grid:SetFrameStrata('BACKGROUND')
		grid.lines = {}
		grid:Hide()
	end
	for _, t in ipairs(grid.lines) do t:Hide() end
	local n = 0
	local function Line(vertical, offset, centre)
		n = n + 1
		local t = grid.lines[n]
		if not t then
			t = grid:CreateTexture(nil, 'BACKGROUND')
			grid.lines[n] = t
		end
		t:SetColorTexture(1, 1, 1, centre and 0.65 or 0.50)
		t:ClearAllPoints()
		if vertical then
			t:SetWidth(1)
			t:SetPoint('TOP', grid, 'TOP', offset, 0)
			t:SetPoint('BOTTOM', grid, 'BOTTOM', offset, 0)
		else
			t:SetHeight(1)
			t:SetPoint('LEFT', grid, 'LEFT', 0, offset)
			t:SetPoint('RIGHT', grid, 'RIGHT', 0, offset)
		end
		t:Show()
	end
	local halfW = mfloor((UIParent:GetWidth() or 1920) / 2)
	local halfH = mfloor((UIParent:GetHeight() or 1080) / 2)
	Line(true, 0, true)
	Line(false, 0, true)
	for x = GRID_STEP, halfW, GRID_STEP do Line(true, x) Line(true, -x) end
	for y = GRID_STEP, halfH, GRID_STEP do Line(false, y) Line(false, -y) end
	return grid
end

local function RefreshGrid()
	local g = LayoutGrid()
	g:SetShown(active and GridShown())
end

local SPARK = [[Interface\Cooldown\star4]]

local flight, sparks, impact

local function BuildFlight()
	if flight then return end

	flight = CreateFrame('Frame', nil, UIParent)
	flight:SetFrameStrata('FULLSCREEN_DIALOG')
	flight:SetFrameLevel(600)
	flight:EnableMouse(false)
	flight:SetSize(110, 110)
	flight:Hide()
	local tex = flight:CreateTexture(nil, 'ARTWORK')
	tex:SetAllPoints()

	local ag = flight:CreateAnimationGroup()
	flight.ag = ag

	local pop = ag:CreateAnimation('Scale')
	pop:SetScaleFrom(0.05, 0.05) pop:SetScaleTo(1, 1)
	pop:SetDuration(0.3) pop:SetOrder(1) pop:SetSmoothing('OUT')
	local popA = ag:CreateAnimation('Alpha')
	popA:SetFromAlpha(0) popA:SetToAlpha(1)
	popA:SetDuration(0.3) popA:SetOrder(1)
	local popSpin = ag:CreateAnimation('Rotation')
	popSpin:SetDegrees(-180) popSpin:SetDuration(0.3) popSpin:SetOrder(1)
	popSpin:SetOrigin('CENTER', 0, 0) popSpin:SetSmoothing('OUT')

	local path = ag:CreateAnimation('Path')
	path:SetDuration(1.5) path:SetOrder(2)
	if path.SetCurve then pcall(path.SetCurve, path, 'SMOOTH') end
	flight.path = path
	flight.cp1 = path:CreateControlPoint()
	flight.cp1:SetOrder(1)
	flight.cp2 = path:CreateControlPoint()
	flight.cp2:SetOrder(2)

	local spin = ag:CreateAnimation('Rotation')
	spin:SetDegrees(540) spin:SetDuration(1.5) spin:SetOrder(2)
	spin:SetOrigin('CENTER', 0, 0) spin:SetSmoothing('IN_OUT')
	local shrink = ag:CreateAnimation('Scale')
	shrink:SetScaleFrom(1, 1) shrink:SetScaleTo(0.18, 0.18)
	shrink:SetDuration(1.5) shrink:SetOrder(2) shrink:SetSmoothing('IN')
	local dim = ag:CreateAnimation('Alpha')
	dim:SetFromAlpha(1) dim:SetToAlpha(0)
	dim:SetDuration(1.5) dim:SetOrder(2) dim:SetSmoothing('IN')

	ag:SetScript('OnFinished', function() flight:Hide() end)
	ag:SetScript('OnStop', function() flight:Hide() end)

	sparks = {}
	for i = 1, 6 do
		local sp = CreateFrame('Frame', nil, UIParent)
		sp:SetFrameStrata('FULLSCREEN_DIALOG')
		sp:SetFrameLevel(590)
		sp:EnableMouse(false)
		sp:SetSize(46 - i * 4, 46 - i * 4)
		sp:Hide()
		local st = sp:CreateTexture(nil, 'ARTWORK')
		st:SetAllPoints()
		st:SetTexture(SPARK)
		st:SetBlendMode('ADD')
		st:SetVertexColor(ORANGE[1], ORANGE[2], ORANGE[3])
		local sag = sp:CreateAnimationGroup()
		local sPath = sag:CreateAnimation('Path')
		sPath:SetDuration(1.5) sPath:SetOrder(1)
		sPath:SetStartDelay(0.3 + i * 0.07)
		sp.cp1 = sPath:CreateControlPoint() sp.cp1:SetOrder(1)
		sp.cp2 = sPath:CreateControlPoint() sp.cp2:SetOrder(2)
		local sFade = sag:CreateAnimation('Alpha')
		sFade:SetFromAlpha(0.9) sFade:SetToAlpha(0)
		sFade:SetDuration(1.5) sFade:SetOrder(1)
		sFade:SetStartDelay(0.3 + i * 0.07)
		sag:SetScript('OnFinished', function() sp:Hide() end)
		sag:SetScript('OnStop', function() sp:Hide() end)
		sp.ag = sag
		sparks[i] = sp
	end

	impact = CreateFrame('Frame', nil, UIParent)
	impact:SetFrameStrata('FULLSCREEN_DIALOG')
	impact:SetFrameLevel(580)
	impact:EnableMouse(false)
	impact:SetSize(260, 120)
	impact:Hide()
	local it = impact:CreateTexture(nil, 'ARTWORK')
	it:SetAllPoints()
	it:SetTexture(SPARK)
	it:SetBlendMode('ADD')
	it:SetVertexColor(ORANGE[1], ORANGE[2], ORANGE[3])
	local iag = impact:CreateAnimationGroup()
	local ig = iag:CreateAnimation('Scale')
	ig:SetScaleFrom(0.3, 0.3) ig:SetScaleTo(1.6, 1.6)
	ig:SetDuration(0.45) ig:SetSmoothing('OUT')
	local ia = iag:CreateAnimation('Alpha')
	ia:SetFromAlpha(0.85) ia:SetToAlpha(0)
	ia:SetDuration(0.45) ia:SetSmoothing('OUT')
	iag:SetScript('OnFinished', function() impact:Hide() end)
	impact.ag = iag
end

local function StopFlight()
	if flight then flight.ag:Stop() flight:Hide() end
	if sparks then for _, sp in ipairs(sparks) do sp.ag:Stop() sp:Hide() end end
	if impact then impact.ag:Stop() impact:Hide() end
end

local function FlyLogo(target)
	if not target then return end
	local ok = pcall(BuildFlight)
	if not ok or not flight then return end
	StopFlight()

	local scale = UIParent:GetEffectiveScale()
	if not scale or scale == 0 then scale = 1 end
	local mx, my = _G.GetCursorPosition()
	mx, my = mx / scale, my / scale

	local px, py = target:GetCenter()
	if not px then return end

	local dx, dy = px - mx, py - my
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 1 then len = 1 end
	local bow = math.min(180, len * 0.35)
	local nx, ny = -dy / len, dx / len
	if ny < 0 then nx, ny = -nx, -ny end

	local function Aim(f)
		f:ClearAllPoints()
		f:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', mx, my)
		f.cp1:SetOffset(dx * 0.5 + nx * bow, dy * 0.5 + ny * bow)
		f.cp2:SetOffset(dx, dy)
	end

	Aim(flight)
	flight:Show()
	flight.ag:Play()

	for _, sp in ipairs(sparks) do
		Aim(sp)
		sp:Show()
		sp.ag:Play()
	end

	_G.C_Timer.After(1.75, function()
		if not active then return end
		impact:ClearAllPoints()
		impact:SetPoint('CENTER', target, 'CENTER', 0, 0)
		impact:Show()
		impact.ag:Play()
	end)
end

-- SetPropagateKeyboardInput is combat-restricted for addon code (HasRestrictions
-- in SimpleFrameAPIDocumentation): calling it in lockdown raises
-- ADDON_ACTION_BLOCKED even on a plain, unprotected frame. This addon is
-- LoadOnDemand, so its file-load Boot() runs whenever the player first types
-- /xui - which can be mid-fight. The panel is therefore built WITHOUT
-- touching propagation; Start() sets it (it already refuses in combat) and the
-- key handler goes through this guard. Skipping the call in combat is safe:
-- PLAYER_REGEN_DISABLED hides the panel, and a hidden frame eats no keys.
local function Propagate(f, on)
	if _G.InCombatLockdown and _G.InCombatLockdown() then return end
	f:SetPropagateKeyboardInput(on)
end

local function MakePanel()
	if panel then return panel end
	panel = CreateFrame('Frame', 'XerionUIEditModePanel', UIParent)
	panel:SetSize(252, 108)
	panel:SetPoint('TOP', UIParent, 'TOP', 0, -140)
	panel:SetFrameStrata('FULLSCREEN_DIALOG')
	panel:SetFrameLevel(200)
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag('LeftButton')
	panel:SetScript('OnDragStart', panel.StartMoving)
	panel:SetScript('OnDragStop', panel.StopMovingOrSizing)

	local bg = panel:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints()
	bg:SetColorTexture(0.055, 0.055, 0.065, 0.96)
	for _, p in ipairs({ { 'TOPLEFT', 'TOPRIGHT', 'h' }, { 'BOTTOMLEFT', 'BOTTOMRIGHT', 'h' },
		{ 'TOPLEFT', 'BOTTOMLEFT', 'v' }, { 'TOPRIGHT', 'BOTTOMRIGHT', 'v' } }) do
		local t = panel:CreateTexture(nil, 'OVERLAY')
		t:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.8)
		t:SetPoint(p[1]) t:SetPoint(p[2])
		if p[3] == 'h' then t:SetHeight(1) else t:SetWidth(1) end
	end

	local title = panel:CreateFontString(nil, 'OVERLAY')
	title:SetFont(ns.GetFont(), 13, 'OUTLINE')
	title:SetPoint('TOP', 0, -8)
	title:SetText('XerionUI Edit Mode')
	title:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])

	local hint = panel:CreateFontString(nil, 'OVERLAY')
	hint:SetFont(ns.GetFont(), 10, '')
	hint:SetPoint('TOP', title, 'BOTTOM', 0, -4)
	hint:SetWidth(232)
	hint:SetText('Left-click selects  |  drag or arrow keys to move (Shift = 10px)  |  right-click for settings  |  Esc exits')
	hint:SetTextColor(0.75, 0.75, 0.78)
	panel.hint = hint

	panel:EnableKeyboard(true)
	panel:SetScript('OnKeyDown', function(self, key)
		local dx, dy = 0, 0
		if key == 'UP' then dy = 1
		elseif key == 'DOWN' then dy = -1
		elseif key == 'LEFT' then dx = -1
		elseif key == 'RIGHT' then dx = 1
		else
			Propagate(self, true)
			return
		end
		if not selected or selected.spec.static then
			Propagate(self, true)
			return
		end
		Propagate(self, false)
		local step = (_G.IsShiftKeyDown and _G.IsShiftKeyDown()) and 10 or 1
		Nudge(selected, dx * step, dy * step)
	end)

	local function Btn(text, x, w, onClick)
		local b = CreateFrame('Button', nil, panel)
		b:SetSize(w, 22)
		b:SetPoint('BOTTOMLEFT', x, 10)
		local t = b:CreateTexture(nil, 'BACKGROUND')
		t:SetAllPoints()
		t:SetColorTexture(0.115, 0.115, 0.135, 1)
		local fs = b:CreateFontString(nil, 'OVERLAY')
		fs:SetFont(ns.GetFont(), 11, '')
		fs:SetPoint('CENTER')
		fs:SetText(text)
		fs:SetTextColor(0.9, 0.9, 0.9)
		b.fs = fs
		b:SetScript('OnEnter', function() t:SetColorTexture(0.175, 0.175, 0.2, 1) end)
		b:SetScript('OnLeave', function() t:SetColorTexture(0.115, 0.115, 0.135, 1) end)
		b:SetScript('OnClick', onClick)
		return b
	end

	Btn('Lock', 10, 55, function() Stop(true) end)
	Btn('Reset', 69, 55, function()
		RestoreSnapshot()
		Rebuild()
		if selected then RefreshReadout(selected) end
	end)
	local gridBtn
	gridBtn = Btn('Grid', 128, 55, function()
		local db = _G.XerionUIChangesDB
		if db then db.editGrid = not GridShown() end
		RefreshGrid()
		gridBtn.fs:SetText(GridShown() and 'Grid on' or 'Grid')
		gridBtn.fs:SetTextColor(GridShown() and ORANGE[1] or 0.9,
			GridShown() and ORANGE[2] or 0.9, GridShown() and ORANGE[3] or 0.9)
	end)
	gridBtn.fs:SetText(GridShown() and 'Grid on' or 'Grid')

	Btn('Settings', 187, 55, function()
		if ns.ToggleConfig then ns.ToggleConfig()
		elseif ns.OpenConfig then ns.OpenConfig() end
	end)
	return panel
end

local confirm
local function MakeConfirm()
	if confirm then return confirm end
	confirm = CreateFrame('Frame', 'XerionUIEditModeConfirm', UIParent)
	confirm:SetSize(340, 120)
	confirm:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
	confirm:SetFrameStrata('FULLSCREEN_DIALOG')
	confirm:SetFrameLevel(400)
	confirm:EnableMouse(true)
	confirm:Hide()

	local bg = confirm:CreateTexture(nil, 'BACKGROUND')
	bg:SetAllPoints()
	bg:SetColorTexture(0.055, 0.055, 0.065, 0.98)
	for _, p2 in ipairs({ { 'TOPLEFT', 'TOPRIGHT', 'h' }, { 'BOTTOMLEFT', 'BOTTOMRIGHT', 'h' },
		{ 'TOPLEFT', 'BOTTOMLEFT', 'v' }, { 'TOPRIGHT', 'BOTTOMRIGHT', 'v' } }) do
		local t = confirm:CreateTexture(nil, 'OVERLAY')
		t:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 0.9)
		t:SetPoint(p2[1]) t:SetPoint(p2[2])
		if p2[3] == 'h' then t:SetHeight(1) else t:SetWidth(1) end
	end

	local msg = confirm:CreateFontString(nil, 'OVERLAY')
	msg:SetFont(ns.GetFont(), 13, '')
	msg:SetPoint('TOP', 0, -22)
	msg:SetWidth(300)
	msg:SetText('Keep the positions you just changed?')
	msg:SetTextColor(1, 1, 1)

	local function Btn(text, x, onClick)
		local b = CreateFrame('Button', nil, confirm)
		b:SetSize(120, 24)
		b:SetPoint('BOTTOMLEFT', x, 16)
		local t = b:CreateTexture(nil, 'BACKGROUND')
		t:SetAllPoints()
		t:SetColorTexture(0.115, 0.115, 0.135, 1)
		local fs = b:CreateFontString(nil, 'OVERLAY')
		fs:SetFont(ns.GetFont(), 12, '')
		fs:SetPoint('CENTER')
		fs:SetText(text)
		fs:SetTextColor(0.9, 0.9, 0.9)
		b:SetScript('OnEnter', function() t:SetColorTexture(0.175, 0.175, 0.2, 1) end)
		b:SetScript('OnLeave', function() t:SetColorTexture(0.115, 0.115, 0.135, 1) end)
		b:SetScript('OnClick', onClick)
		return b
	end
	Btn(_G.SAVE or 'Save', 26, function()
		confirm:Hide()
		ns.EditModeFinish(true)
	end)
	Btn('Discard', 194, function()
		confirm:Hide()
		ns.EditModeFinish(false)
	end)
	return confirm
end

local ticker

local function SetPreviews(on)
	for _, m in ipairs(MOVABLES) do
		if m.preview and IsOn(m) then
			local f = ns[m.preview]
			if type(f) == 'function' then pcall(f, on) end
		end
	end
end

local function Start()
	if active then return end
	if _G.InCombatLockdown and _G.InCombatLockdown() then
		if ns.Msg then ns.Msg('Edit mode is not available in combat.') end
		return
	end
	active = true
	-- repaints the settings window's Edit Mode button (orange while on)
	if ns.OnEditModeChanged then pcall(ns.OnEditModeChanged) end
	TakeSnapshot()
	SetPreviews(true)
	local p = MakePanel()
	Propagate(p, true)
	p:Show()
	RefreshGrid()
	Rebuild()
	ticker = _G.C_Timer.NewTicker(0.25, Rebuild)
	if ns.Msg then ns.Msg('Edit mode ON - drag to move, right-click for settings, Esc to exit.') end

	local missing
	for _, m in ipairs(MOVABLES) do
		if IsOn(m) and not Frm(m) then
			missing = (missing and (missing .. ', ') or '') .. m.label
		end
	end
	if missing and ns.Msg then
		ns.Msg('|cff888888not shown - dormant on this character (wrong class/spec): ' .. missing .. '|r')
	end
end

function ns.EditModeFinish(keep)
	if not keep then RestoreSnapshot() end
	if confirm then confirm:Hide() end
	dirty = false
	active = false
	if ns.OnEditModeChanged then pcall(ns.OnEditModeChanged) end
	Select(nil)
	if ticker then ticker:Cancel() ticker = nil end
	for _, o in pairs(overlays) do o:Hide() end
	if panel then panel:Hide() end
	if grid then grid:Hide() end
	StopFlight()
	SetPreviews(false)
	for _, m in ipairs(MOVABLES) do ApplyOne(m) end
	-- the settings window may have closed while this ran; its own previews
	-- end now (it skips them while move mode is on)
	if ns.EndWindowPreviews then ns.EndWindowPreviews() end
end

function Stop(ask)
	if not active then return end
	if ask ~= false and dirty then
		MakeConfirm():Show()
		return
	end
	ns.EditModeFinish(true)
end

ns.EditModeActive = function() return active end
ns.EditModeToggle = function()
	if active then Stop(true) else Start() end
end

local escHooked
local function HookEsc()
	if escHooked or not panel then return end
	escHooked = true
	-- Never assign the UISpecialFrames global itself: that write taints it for the
	-- secure ESC chain. Appending our own entry is the supported way in.
	local already = false
	for _, n in ipairs(_G.UISpecialFrames) do
		if n == 'XerionUIEditModePanel' then already = true break end
	end
	if not already then
		_G.UISpecialFrames[#_G.UISpecialFrames + 1] = 'XerionUIEditModePanel'
	end
	panel:SetScript('OnHide', function()
		if active then Stop(true) end
	end)
end

local function Boot()
	MakePanel()
	panel:Hide()
	HookEsc()
end
if IsLoggedIn() then
	Boot()
else
	local boot = CreateFrame('Frame')
	boot:RegisterEvent('PLAYER_LOGIN')
	boot:SetScript('OnEvent', function(self)
		self:UnregisterEvent('PLAYER_LOGIN')
		Boot()
	end)
end

local cw = CreateFrame('Frame')
cw:RegisterEvent('PLAYER_REGEN_DISABLED')
cw:SetScript('OnEvent', function()
	if active then ns.EditModeFinish(true) end
end)
