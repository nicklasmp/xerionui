--------------------------------------------------------------------------------
-- CC Tracker
-- Bars for the crowd control on enemies - how long the pack stays stunned -
-- coloured and named per spell, with a sound when one lands. Inside a key an
-- enemy's debuffs are secret, so Lua never learns the spell, the seconds or
-- the mob: the engine draws all of it.
--
-- THE SPELL IS SETTLED BEFORE THE AURA EXISTS
-- Every enemy's AuraContainer gets one display PER LISTED SPELL, filtered to
-- that spell's ID; a button built for it can only ever show that spell, so
-- its initializer paints the spell's colour, name and icon, and the engine
-- binds only the fill and the seconds. (Spell-ID filters are honoured for
-- harmful auras on units you cannot assist.)
--
-- TWO WAYS TO STACK
--   * One bar per spell (mode "group"): each spell is an aura SLOT pinned to
--     its line; every enemy's slot for it overlaps on that line. A spell whose
--     class is not in your group gets no line (nobody can cast it).
--   * One bar per spell per enemy (mode "each"): each spell is an aura GROUP
--     with one frame; containers are chained so idle enemies take no room.
--
-- THE BUILDER
-- Containers, groups and slots are built in the background, one step per
-- frame, never as a burst mid-pull. Slots for spells that gain a line while
-- the client restricts addons wait for the restriction to lift.
--
-- ENGINE BUTTONS ARE LOCKED
-- After its initializer a button refuses addon code while auras are secret -
-- even a SetPoint that names it. So every piece hangs off a frame of ours
-- pinned over the button once; settings restyle those pieces, and whatever
-- the client refuses is retried when the fight or the key ends.
--
-- THE SOUND
-- Lua never learns that a bar appeared, so the sound is the engine's own:
-- C_UnitAuras.AddAuraSound per spell ID on every nameplate (or the target),
-- registered outside encounters and keyed combat. It is per enemy, so one
-- stun on eight mobs plays eight copies - hence the Effects channel default.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates
local Style = XUI.Style

local MAX_SLOTS = 40
local MAX_SAMPLES = 12
local GROUP_KEY, SLOT_KEY = "ccb", "ccbs"
local LEVEL_STEP = 12

-- Short names, colours and the caster's class for the default list.
local BUILTIN = {
	[372048] = { "Roar", 0.09, 0.75, 0.83, "EVOKER" },
	[204490] = { "Silence", 0.09, 0.75, 0.83, "DEMONHUNTER" },
	[119381] = { "Leg Sweep", 0.00, 0.80, 0.52, "MONK" },
	[117526] = { "Binding Shot", 0.50, 0.33, 0.55, "HUNTER" },
	[30283]  = { "Shadowfury", 0.47, 0.31, 0.70, "WARLOCK" },
	[255941] = { "Wake of Ashes", 0.70, 0.56, 0.20, "PALADIN" },
	[372245] = { "Breath", 0.70, 0.49, 0.29, "EVOKER" },
	[179057] = { "Nova", 0.53, 0.15, 0.66, "DEMONHUNTER" },
	[118905] = { "Cap Totem", 0.22, 0.24, 0.83, "SHAMAN" },
	[279303] = { "Frostwyrm", 0.45, 0.72, 0.95, "DEATHKNIGHT" },
}

local M = XUI:NewModule("CCTracker", {
	name = "CC Tracker",
	desc = "Bars for crowd control on enemies, coloured per spell.",
	category = "group",
	icon = [[Interface\Icons\Spell_Frost_Stun]],
	order = 60,
	defaults = {
		mode = "group",
		classRows = true,
		grow = "DOWN",
		iconSide = "RIGHT",
		iconGap = 2,
		spacing = 2,
		bar = T.Bar(220, 20),
		border = T.Border(),
		nameText = T.Font(12, { enabled = true, y = 0 }),
		timerText = T.Font(12, { enabled = true }),
		timerSide = "LEFT",
		tenths = true,
		maxUnits = 15,
		sound = "Xerion: Stun",
		soundFrom = "ALL",
		soundChannel = "SFX",
		-- the DEBUFF's ID, which is not always the cast's
		spells = { 372048, 204490, 119381, 117526, 255941, 372245, 179057, 279303, 118905, 30283 },
		colors = {},
		labels = {},
		position = T.Position(0, 60),
	},
})

M.BUILTIN = BUILTIN
M.MODES = { { value = "group", text = "One bar per spell" }, { value = "each", text = "One bar per enemy" } }
M.GROW = { { value = "DOWN", text = "Down" }, { value = "UP", text = "Up" } }
M.ICON_SIDES = { { value = "RIGHT", text = "Right" }, { value = "LEFT", text = "Left" }, { value = "NONE", text = "None" } }
M.TIMER_SIDES = { { value = "LEFT", text = "Left" }, { value = "RIGHT", text = "Right" } }
M.SOUND_FROM = { { value = "ALL", text = "Every enemy nameplate" }, { value = "TARGET", text = "Your target only" } }

local IsSecret, Ask = XUI.IsSecret, XUI.Ask
local AXIS = AnchorUtil and AnchorUtil.FlowLayoutAxis
local DIR = AnchorUtil and AnchorUtil.FlowDirection

function M:CanLoad()
	if not (XUI.HasAuraContainers() and AXIS and DIR) then return false, "Needs the 12.1 aura containers." end
	return true
end

function M:OnInitialize()
	-- an imported profile is where strings and duplicates come from
	local list, seen = self.db.spells, {}
	for i = #list, 1, -1 do
		local id = tonumber(list[i])
		id = id and math.floor(id)
		if not id or id <= 0 or seen[id] then
			table.remove(list, i)
		else
			seen[id] = true
			list[i] = id
		end
	end
end

function M:SpellColor(id)
	local c = self.db.colors[id]
	if type(c) == "table" then return c[1] or 1, c[2] or 1, c[3] or 1 end
	local b = BUILTIN[id]
	if b then return b[2], b[3], b[4] end
	return 0.6, 0.6, 0.6
end

function M:SpellLabel(id)
	local l = self.db.labels[id]
	if type(l) == "string" and l ~= "" then return l end
	local b = BUILTIN[id]
	if b then return b[1] end
	return XUI.GetSpellName(id)
end

local function BarSize(db)
	local b = Style:Resolve("bar", db.bar)
	return math.max(40, b.width or 220), math.max(6, b.height or 20)
end
local function Up(db) return db.grow == "UP" end
local function Each(db) return db.mode == "each" end
local function Corner(db) return Up(db) and "BOTTOMLEFT" or "TOPLEFT" end
local function Cap(db) return math.max(1, math.min(MAX_SLOTS, math.floor(db.maxUnits))) end
local function Wanted() return M.running and #M.db.spells > 0 end

local function TimerOptions(db)
	return db.tenths and XUI.TenthsTextOptions() or XUI.DurationTextOptions()
end

--------------------------------------------------------------------------------
-- Lines ("group" mode)
--------------------------------------------------------------------------------
local PARTY, RAID = { "player" }, {}
for i = 1, 4 do PARTY[i + 1] = "party" .. i end
for i = 1, 40 do RAID[i] = "raid" .. i end

-- nil when any member's class is unreadable: then every spell keeps its line
local function GroupClasses()
	local out = {}
	for _, u in ipairs(IsInRaid() and RAID or PARTY) do
		if Ask(UnitExists, u) == true then
			local ok, _, token = pcall(UnitClass, u)
			if not ok or IsSecret(token) or type(token) ~= "string" then return nil end
			out[token] = true
		end
	end
	return out
end

local rowOf = {}
local function ComputeRows(db)
	wipe(rowOf)
	local n = 0
	local classes = db.classRows and GroupClasses() or nil
	for _, id in ipairs(db.spells) do
		local b = BUILTIN[id]
		if not (classes and b and b[5] and not classes[b[5]]) then
			n = n + 1
			rowOf[id] = n
		end
	end
end

local rowsSig
local function RowsSignature(db)
	ComputeRows(db)
	local parts = {}
	for i, id in ipairs(db.spells) do parts[i] = rowOf[id] or 0 end
	return table.concat(parts, ",")
end

--------------------------------------------------------------------------------
-- A bar's pieces, all hanging off p.root (a frame of ours)
--------------------------------------------------------------------------------
local function MakeBar(parent)
	local p = {}
	p.root = CreateFrame("Frame", nil, parent)
	p.root:SetAllPoints(parent)
	p.iconBox = CreateFrame("Frame", nil, p.root)
	p.icon = p.iconBox:CreateTexture(nil, "ARTWORK")
	p.iconBorder = Style:Border(p.iconBox)
	p.barBox = CreateFrame("Frame", nil, p.root)
	p.bar = CreateFrame("StatusBar", nil, p.barBox)
	p.barBorder = Style:Border(p.barBox)
	p.name = p.bar:CreateFontString(nil, "OVERLAY")
	p.name:SetWordWrap(false)
	-- its own layer: the engine owns the seconds' alpha, "hide" dims ours
	p.timerHost = CreateFrame("Frame", nil, p.root)
	p.timerHost:SetFrameLevel(p.bar:GetFrameLevel() + 5)
	p.timer = p.timerHost:CreateFontString(nil, "OVERLAY")
	p.timer:SetWordWrap(false)
	-- fonts at once: the engine writes the seconds even if styling failed
	Style:ApplyFont(p.timer, nil, 12)
	Style:ApplyFont(p.name, nil, 12)
	return p
end

local function Inset(region, parent, inset)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -inset)
	region:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, inset)
end

-- Each box is pinned to one point of the root with its own size, so the
-- engine button's size never matters: the box's `corner` to the root's `rel`
-- point, `dy` along.
local function StyleBar(p, id, rel, dy)
	local db = M.db
	local corner = Corner(db)
	local w, h = BarSize(db)
	local side = db.iconSide
	local iconW = side == "NONE" and 0 or h
	local gap = side == "NONE" and 0 or db.iconGap
	local barW = math.max(1, w - iconW - gap)
	local barX = side == "LEFT" and (iconW + gap) or 0
	local iconX = side == "LEFT" and 0 or (barW + gap)
	local key = corner .. "|" .. rel .. "|" .. dy .. "|" .. w .. "|" .. h .. "|" .. side .. "|" .. gap
	if p.anchored ~= key then
		p.iconBox:ClearAllPoints()
		p.iconBox:SetPoint(corner, p.root, rel, iconX, dy)
		p.barBox:ClearAllPoints()
		p.barBox:SetPoint(corner, p.root, rel, barX, dy)
		p.timerHost:ClearAllPoints()
		p.timerHost:SetAllPoints(p.barBox)
		p.anchored = key
	end
	p.iconBox:SetSize(math.max(1, iconW), h)
	p.iconBox:SetShown(side ~= "NONE")
	Inset(p.icon, p.iconBox, p.iconBorder:Apply(db.border))
	p.icon:SetTexture(XUI.GetSpellIcon(id))
	Style:IconTexCoord(p.icon, iconW, h)
	p.barBox:SetSize(barW, h)
	Inset(p.bar, p.barBox, p.barBorder:Apply(db.border))
	Style:ApplyBar(p.bar, db.bar)
	p.bar:SetStatusBarColor(M:SpellColor(id))

	local tSide = db.timerSide == "RIGHT" and "RIGHT" or "LEFT"
	local nSide = tSide == "LEFT" and "RIGHT" or "LEFT"
	local inset = tSide == "LEFT" and 4 or -4
	local timerSize = Style:Resolve("font", db.timerText).size or 12
	-- the name keeps clear of the seconds
	local reserve = db.timerText.enabled ~= false and math.ceil(timerSize * 2.4) + 6 or 0
	local nameY = db.nameText.y or 0
	Style:ApplyFont(p.timer, db.timerText)
	p.timer:ClearAllPoints()
	p.timer:SetPoint(tSide, p.timerHost, tSide, inset, 0)
	p.timer:SetJustifyH(tSide)
	p.timerHost:SetAlpha(db.timerText.enabled ~= false and 1 or 0)
	Style:ApplyFont(p.name, db.nameText)
	p.name:ClearAllPoints()
	p.name:SetPoint(nSide, p.bar, nSide, -inset, nameY)
	p.name:SetPoint(tSide, p.bar, tSide, tSide == "LEFT" and (4 + reserve) or -(4 + reserve), nameY)
	p.name:SetJustifyH(nSide)
	p.name:SetText(M:SpellLabel(id))
	p.name:SetShown(db.nameText.enabled ~= false)
end

-- A slot button is pinned to the holder's top left, so its line is an
-- offset from there.
local function SlotPlace(db, row)
	local _, h = BarSize(db)
	local step = (h + db.spacing) * ((row or 1) - 1)
	if Up(db) then return "TOPLEFT", step - h end
	return "TOPLEFT", -step
end

--------------------------------------------------------------------------------
-- Frames, preview and the engine's part
--------------------------------------------------------------------------------
local holder
local samples = {}
local chain = {}
local groupsOf, slotsOf = {}, {}
local building
local buttons = {}
local listIndex = {}
local listSig
local failed
local linkedAs, timerAs
local stylePending, slotsWaiting = false, false
local QueueScan

local function Holder()
	if holder then return holder end
	holder = CreateFrame("Frame", "XUI_CCTracker", UIParent)
	holder:SetSize(220, 20)
	holder:Hide()
	XUI.Movers:Register(holder, M, "position")
	return holder
end

local SAMPLE_LEFT = { 5.8, 4.3, 3.1, 2.6, 5.2, 1.9, 4.8, 3.6, 2.2, 1.4, 3.9, 2.9 }

local function StyleSamples(db)
	local corner = Corner(db)
	local _, h = BarSize(db)
	local step = (h + db.spacing) * (Up(db) and 1 or -1)
	for i = 1, MAX_SAMPLES do
		local s = samples[i]
		local id = db.spells[i]
		if id then
			if not s then
				local f = CreateFrame("Frame", nil, holder)
				f:SetSize(1, 1)
				f:SetFrameLevel(holder:GetFrameLevel() + 20)
				f:Hide()
				s = { frame = f, p = MakeBar(f) }
				s.p.bar:SetMinMaxValues(0, 1)
				samples[i] = s
			end
			s.frame:ClearAllPoints()
			s.frame:SetPoint(corner, holder, corner, 0, (i - 1) * step)
			StyleBar(s.p, id, corner, 0)
			local left = SAMPLE_LEFT[i]
			s.p.bar:SetValue(left / 6)
			s.p.timer:SetText(db.tenths and ("%.1f"):format(left) or tostring(math.ceil(left)))
			s.used = true
		elseif s then
			s.used = false
		end
	end
end

local function Layout(db, index)
	local w, h = BarSize(db)
	return { elementWidth = w, elementHeight = h + db.spacing, elementSpacing = 0, lineSpacing = 0, layoutIndex = index or 0 }
end

-- one column away from the chain's corner, with the one pixel an empty
-- container is at the far end
local function Flow(c, db)
	local up = Up(db)
	c:SetFlowLayoutAxis(AXIS.Vertical)
	c:SetFlowLayoutAnchorPoint(Corner(db))
	c:SetFlowLayoutGrowthDirection(DIR.Right, up and DIR.Up or DIR.Down)
	c:SetFlowLayoutPadding(0, 0, up and 1 or 0, up and 0 or 1)
end

local function SlotShown(db, id)
	return not Each(db) and listIndex[id] ~= nil and rowOf[id] ~= nil
end

-- shared by groups and slots; runs inside the engine's frame creation, so
-- everything optional is armoured
local function Dress(b, id, rel, dy, isSlot)
	local db = M.db
	pcall(b.SetMouseClickEnabled, b, false)
	pcall(b.SetMouseMotionEnabled, b, false)
	pcall(b.SetSize, b, 1, 1)
	local p = MakeBar(b)
	pcall(StyleBar, p, id, rel, dy)
	pcall(b.SetDurationBar, b, p.bar, XUI.DurationBarOptions())
	pcall(b.SetDurationText, b, p.timer, TimerOptions(db))
	local rec = { frame = b, p = p, id = id, slot = isSlot }
	buttons[#buttons + 1] = rec
	return rec
end

local function InitGroupButton(id, b)
	Dress(b, id, Corner(M.db), 0, nil)
end

-- a slot takes no part in the engine's layout: placed here, once, while it
-- is still ours to place
local function InitSlot(id, b)
	pcall(b.SetPoint, b, "TOPLEFT", holder, "TOPLEFT", 0, 0)
	local db = M.db
	local rel, dy = SlotPlace(db, rowOf[id])
	local rec = Dress(b, id, rel, dy, true)
	rec.p.root:SetShown(SlotShown(db, id))
end

local function NewContainer(db)
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, holder, "CustomAuraContainerTemplate," .. XUI.TAIL_TEMPLATE)
	if not ok or not c then ok, c = pcall(CreateFrame, "AuraContainer", nil, holder, "CustomAuraContainerTemplate") end
	if not ok or not c then
		failed = "the client refused the AuraContainer frame"
		return nil
	end
	c:SetSize(1, 1)
	c:SetFrameLevel(holder:GetFrameLevel() + 1 + LEVEL_STEP * (#chain + 1))
	local okF, errF = pcall(Flow, c, db)
	if not okF then
		failed = "column layout refused: " .. tostring(errF)
		c:Hide()
		return nil
	end
	pcall(c.SetEnabled, c, false)
	groupsOf[c], slotsOf[c] = {}, {}
	return c
end

local function AddGroup(c, id, index, db)
	local ok, err = pcall(c.AddAuraGroup, c, GROUP_KEY .. id, "HARMFUL", {
		maxFrameCount = 1,
		candidateFilters = { includeSpellIDs = { [id] = true } },
		initializeFrame = function(b) InitGroupButton(id, b) end,
		layout = Layout(db, index),
	})
	if not ok then failed = tostring(err) return end
	groupsOf[c][id] = true
end

local function AddSlot(c, id)
	local ok, err = pcall(c.AddAuraSlot, c, SLOT_KEY .. id, "HARMFUL", {
		candidateFilters = { includeSpellIDs = { [id] = true } },
		initializeFrame = function(b) InitSlot(id, b) end,
	})
	if not ok then failed = tostring(err) return end
	slotsOf[c][id] = true
end

local function NextMissing(c, db)
	local each = Each(db)
	local have = each and groupsOf[c] or slotsOf[c]
	for index, id in ipairs(db.spells) do
		if not have[id] and (each or rowOf[id]) then return id, index end
	end
end

-- one group (heavy), or every missing slot (a slot is one frame)
local function BuildOn(c, db)
	local id, index = NextMissing(c, db)
	if not id then return false end
	if Each(db) then
		AddGroup(c, id, index, db)
	else
		while id and not failed do
			AddSlot(c, id)
			id = NextMissing(c, db)
		end
	end
	return true
end

local function Link(c, prev, db)
	c:ClearAllPoints()
	if Up(db) then
		if prev then c:SetPoint("BOTTOMLEFT", prev, "TOPLEFT", 0, -1) else c:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0) end
	elseif prev then
		c:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 1)
	else
		c:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
	end
end

-- one step per frame while there is work
local builder = CreateFrame("Frame")
builder:Hide()
builder:SetScript("OnUpdate", function(self)
	local db = M.db
	if failed or not Wanted() or not holder then
		self:Hide()
		return
	end
	local each, hold = Each(db), nil
	slotsWaiting = false
	for i = #chain, 1, -1 do
		local c = chain[i]
		if each then
			if BuildOn(c, db) then return end
		elseif NextMissing(c, db) then
			if hold == nil then hold = XUI.Restricted() end
			if not hold then
				BuildOn(c, db)
				return
			end
			slotsWaiting = true
		end
	end
	if #chain >= Cap(db) then
		self:Hide()
		return
	end
	if not building then
		building = NewContainer(db)
		return
	end
	if BuildOn(building, db) then return end
	local c = building
	building = nil
	local ok, err = pcall(Link, c, chain[#chain], db)
	if not ok then
		failed = tostring(err)
		c:Hide()
		return
	end
	chain[#chain + 1] = c
	QueueScan()
end)

local function DeclareList(db)
	wipe(listIndex)
	for index, id in ipairs(db.spells) do listIndex[id] = index end
	local sig = db.mode .. ":" .. table.concat(db.spells, ",")
	if sig == listSig then return end
	listSig = sig
	local each = Each(db)
	for c, have in pairs(groupsOf) do
		for id in pairs(have) do
			pcall(c.SetAuraGroupMaxFrameCount, c, GROUP_KEY .. id, (each and listIndex[id]) and 1 or 0)
		end
	end
end

local function Restyle(db)
	stylePending = false
	rowsSig = RowsSignature(db)
	local corner = Corner(db)
	for _, rec in ipairs(buttons) do
		local rel, dy = corner, 0
		if rec.slot then rel, dy = SlotPlace(db, rowOf[rec.id]) end
		if not pcall(StyleBar, rec.p, rec.id, rel, dy) then stylePending = true end
		if rec.slot and not pcall(rec.p.root.SetShown, rec.p.root, SlotShown(db, rec.id)) then stylePending = true end
	end
	if timerAs ~= db.tenths then
		local ok = true
		for _, rec in ipairs(buttons) do
			if not pcall(rec.frame.SetDurationText, rec.frame, rec.p.timer, TimerOptions(db)) then ok = false end
		end
		if ok then timerAs = db.tenths else stylePending = true end
	end
	for c, have in pairs(groupsOf) do
		for id in pairs(have) do
			if not pcall(c.SetAuraGroupLayout, c, GROUP_KEY .. id, Layout(db, listIndex[id])) then stylePending = true end
		end
	end
	if linkedAs ~= db.grow then
		local ok = true
		for c in pairs(groupsOf) do
			if not pcall(Flow, c, db) then ok = false end
		end
		for i, c in ipairs(chain) do
			if not pcall(Link, c, chain[i - 1], db) then ok = false end
		end
		if ok then linkedAs = db.grow else stylePending = true end
	end
end

--------------------------------------------------------------------------------
-- The sound
--------------------------------------------------------------------------------
local soundReg, soundPending = {}, false
local SOUND_TOKENS = { TARGET = { "target" }, ALL = {} }
for i = 1, MAX_SLOTS do SOUND_TOKENS.ALL[i] = "nameplate" .. i end

local function SoundAPI()
	local api = C_UnitAuras
	if not (api and api.AddAuraSound and api.RemoveAuraSound) then return nil end
	if not (Enum and Enum.UnitAuraSoundTrigger) then return nil end
	return api
end

local function SoundWanted(db)
	local out = {}
	if not Wanted() then return out end
	local path = XUI.Audio:SoundFile(db.sound)
	if not path then return out end
	local each = Each(db)
	for _, id in ipairs(db.spells) do
		if each or rowOf[id] then
			for _, token in ipairs(SOUND_TOKENS[db.soundFrom] or SOUND_TOKENS.ALL) do
				out[token .. ":" .. id] = { token = token, id = id, path = path, channel = db.soundChannel }
			end
		end
	end
	return out
end

local function SyncSounds()
	local api = SoundAPI()
	if not api then return end
	local want = SoundWanted(M.db)
	for key, live in pairs(soundReg) do
		local w = want[key]
		if not w or w.path ~= live.path or w.channel ~= live.channel then
			pcall(api.RemoveAuraSound, live.id)
			soundReg[key] = nil
		end
	end
	soundPending = false
	if XUI.AuraSoundsBlocked() then
		for key in pairs(want) do
			if not soundReg[key] then soundPending = true break end
		end
		return
	end
	local added = Enum.UnitAuraSoundTrigger.Added
	for key, w in pairs(want) do
		if not soundReg[key] then
			local ok, sid = pcall(api.AddAuraSound, added, {
				unitToken = w.token, spellID = w.id, soundFileName = w.path, outputChannel = w.channel,
			})
			if ok and sid then
				soundReg[key] = { id = sid, path = w.path, channel = w.channel }
			else
				soundPending = true
				return
			end
		end
	end
end
-- the restriction reads stale while its own event is handed out
local QueueSounds = XUI.Coalesce(SyncSounds)

function M:PlayTest()
	XUI.Audio:PlaySound(self.db.sound, self.db.soundChannel)
end

--------------------------------------------------------------------------------
-- Which enemies get a place
--------------------------------------------------------------------------------
local PLATES, IS_PLATE = {}, {}
for i = 1, MAX_SLOTS do
	PLATES[i] = "nameplate" .. i
	IS_PLATE[PLATES[i]] = true
end
local unitOf, slotOf = {}, {}
local tracking = false

-- Why a plate gets no place, or nil when it does. On a unit you can assist
-- the engine skips spell filters and every debuff would get a bar, so only a
-- plain "no" lets that one through. Bosses are immune to crowd control.
local function Verdict(unit)
	if Ask(UnitExists, unit) ~= true then return "no such unit" end
	if Ask(UnitCanAttack, "player", unit) == false then return "not attackable" end
	if Ask(UnitCanAssist, "player", unit) ~= false then return "friendly" end
	if Ask(UnitIsDeadOrGhost, unit) == true then return "dead" end
	if Ask(UnitIsBossMob, unit) == true then return "boss" end
	return nil
end

local function Release(slot)
	local unit = unitOf[slot]
	if not unit then return end
	unitOf[slot], slotOf[unit] = nil, nil
	local c = chain[slot]
	if c then pcall(c.SetEnabled, c, false) end
end

local function Take(slot, unit)
	local c = chain[slot]
	if not c then return end
	unitOf[slot], slotOf[unit] = unit, slot
	-- unit before enable; the off-to-on switch makes it read afresh
	pcall(c.SetUnit, c, unit)
	pcall(c.SetEnabled, c, true)
end

local function Rescan()
	if not tracking then return end
	local cap = math.min(Cap(M.db), #chain)
	for slot = 1, MAX_SLOTS do
		local unit = unitOf[slot]
		if unit and (slot > cap or Verdict(unit) ~= nil) then Release(slot) end
	end
	local free = 1
	for _, unit in ipairs(PLATES) do
		if not slotOf[unit] and Verdict(unit) == nil then
			while free <= cap and unitOf[free] do free = free + 1 end
			if free > cap then break end
			Take(free, unit)
		end
	end
end
QueueScan = XUI.Coalesce(Rescan)

-- UNIT_FLAGS names one plate: only that plate is asked again
local flagged = {}
local QueueFlagged = XUI.Coalesce(function()
	if not tracking then wipe(flagged) return end
	local cap = math.min(Cap(M.db), #chain)
	for unit in pairs(flagged) do
		flagged[unit] = nil
		local slot = slotOf[unit]
		if slot then
			if Verdict(unit) ~= nil then
				Release(slot)
				QueueScan()
			end
		elseif Verdict(unit) == nil then
			for free = 1, cap do
				if not unitOf[free] then Take(free, unit) break end
			end
		end
	end
end)

local function StartTracking()
	if tracking then return end
	tracking = true
	M:RegisterEvent("NAME_PLATE_UNIT_ADDED", QueueScan)
	M:RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, _, unit)
		-- let go at once: the token may go to another mob within this frame
		local slot = unit and slotOf[unit]
		if slot then Release(slot) end
		QueueScan()
	end)
	M:RegisterEvent("UNIT_FLAGS", function(_, _, unit)
		if not IS_PLATE[unit] then return end
		flagged[unit] = true
		QueueFlagged()
	end)
end

local function StopTracking()
	if not tracking then return end
	tracking = false
	M:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
	M:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
	M:UnregisterEvent("UNIT_FLAGS")
	for slot = 1, MAX_SLOTS do Release(slot) end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------
local function UpdateVisibility()
	local db = M.db
	local preview = M:IsPreview()
	local live = Wanted() and not preview
	for _, s in ipairs(samples) do s.frame:SetShown(preview and s.used or false) end
	holder:SetSize(BarSize(db))
	-- shown while live although it draws nothing: a container only works
	-- while visible
	holder:SetShown(preview or live)
	if live then
		StartTracking()
		Rescan()
	else
		StopTracking()
	end
end

function M:OnEnable()
	Holder()
	local RosterChanged = XUI.Coalesce(function()
		if M.running and not Each(M.db) and RowsSignature(M.db) ~= rowsSig then M:RefreshSoon() end
	end)
	self:RegisterEvent("GROUP_ROSTER_UPDATE", RosterChanged)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(self) self:After(0.5, function() self:Refresh() end) end)
	local function released()
		if stylePending and not M:IsPreview() then Restyle(M.db) end
		if soundPending then QueueSounds() end
		if slotsWaiting then builder:Show() end
	end
	self:RegisterEvent("PLAYER_REGEN_ENABLED", released)
	self:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", function(self) self:After(0, released) end)
end

function M:OnDisable()
	tracking = false
	for slot = 1, MAX_SLOTS do Release(slot) end
	builder:Hide()
	QueueSounds()
end

function M:OnRefresh()
	if not (holder or self:IsPreview()) then return end
	local h, db = Holder(), self.db
	XUI.Movers:Apply(h)
	StyleSamples(db)
	if Wanted() then
		DeclareList(db)
		Restyle(db)
		builder:Show()
	end
	QueueSounds()
	UpdateVisibility()
end
