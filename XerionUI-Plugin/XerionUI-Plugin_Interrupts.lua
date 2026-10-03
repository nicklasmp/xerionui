local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('Interrupts', hooksecurefunc, C_Timer)
local _G = _G

local CreateFrame = CreateFrame
local UIParent = UIParent
local GetTime = GetTime
local C_Timer = C_Timer
local C_Spell = C_Spell
local C_SpellBook = C_SpellBook
local C_ClassColor = C_ClassColor
local C_SpecializationInfo = C_SpecializationInfo
local UnitExists, UnitName, UnitGUID = UnitExists, UnitName, UnitGUID
local UnitClassBase = UnitClassBase
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local IsInGroup, IsInRaid = IsInGroup, IsInRaid
local CanInspect, NotifyInspect = CanInspect, NotifyInspect
local GetRaidTargetIndex = GetRaidTargetIndex
local ipairs, pairs, pcall, type, tostring = ipairs, pairs, pcall, type, tostring
local mfloor, mabs = math.floor, math.abs
local sformat = string.format
local wipe = wipe
local secret = ns.IsSecret

ns.hasInterrupts = true

local DEFAULTS = {
	enable = false,
	lock = false,
	showSelf = true,
	groupOnly = true,
	hideInRaid = true,
	showReady = true,
	showIcon = true,
	iconSource = 'kick',
	showTimer = true,
	showMark = true,
	growth = 'DOWN',
	width = 180,
	height = 20,
	spacing = 2,
	textSize = 12,
	bgAlpha = 0.6,
	x = -420,
	y = 0,
	observe = true,
	meterConfirm = true,
	partyCd = 15,
	displayMode = 'bar',
	partySide = 'RIGHT',
	iconSize = 24,
	iconGap = 2,
	partyGap = 3,
}

local function Migrate(cfg)
	if cfg.growth ~= 'DOWN' and cfg.growth ~= 'UP' then cfg.growth = 'DOWN' end
	if cfg.iconSource ~= 'kick' and cfg.iconSource ~= 'kicked' then cfg.iconSource = 'kick' end
	if cfg.displayMode ~= 'bar' and cfg.displayMode ~= 'icon' then cfg.displayMode = 'bar' end
	if cfg.partySide ~= 'LEFT' and cfg.partySide ~= 'RIGHT' then cfg.partySide = 'RIGHT' end
	cfg.kickCd, cfg.memberCd, cfg.kickOrder, cfg.texture = nil, nil, nil, nil
end

local function GetCfg() return ns.ModuleCfg('interrupts', DEFAULTS, Migrate) end
ns.IKGetCfg = GetCfg

local KICKS = {
	[47528]  = { cd = 12, class = 'DEATHKNIGHT', name = 'Mind Freeze' },
	[183752] = { cd = 15, class = 'DEMONHUNTER', name = 'Disrupt' },
	[106839] = { cd = 15, class = 'DRUID',       name = 'Skull Bash' },
	[78675]  = { cd = 60, class = 'DRUID',       name = 'Solar Beam' },
	[351338] = { cd = 40, class = 'EVOKER',      name = 'Quell' },
	[147362] = { cd = 24, class = 'HUNTER',      name = 'Counter Shot' },
	[187707] = { cd = 15, class = 'HUNTER',      name = 'Muzzle' },
	[2139]   = { cd = 21, class = 'MAGE',        name = 'Counterspell' },
	[116705] = { cd = 15, class = 'MONK',        name = 'Spear Hand Strike' },
	[96231]  = { cd = 15, class = 'PALADIN',     name = 'Rebuke' },
	[15487]  = { cd = 45, class = 'PRIEST',      name = 'Silence' },
	[1766]   = { cd = 15, class = 'ROGUE',       name = 'Kick' },
	[57994]  = { cd = 12, healerCd = 30, class = 'SHAMAN', name = 'Wind Shear' },
	[6552]   = { cd = 13.5, class = 'WARRIOR',   name = 'Pummel' },
	[386071] = { cd = 90, class = 'WARRIOR',     name = 'Disrupting Shout' },
	[19647]  = { cd = 24, class = 'WARLOCK',     name = 'Spell Lock' },
	[89766]  = { cd = 30, class = 'WARLOCK',     name = 'Axe Toss' },
	[119910] = { cd = 24, class = 'WARLOCK', icon = 19647 },
	[132409] = { cd = 24, class = 'WARLOCK', icon = 19647 },
	[1276467] = { cd = 24, class = 'WARLOCK', icon = 19647 },
	[119914] = { cd = 30, class = 'WARLOCK', icon = 89766 },
}

local CLASS_KICK = {
	DEATHKNIGHT = 47528, DEMONHUNTER = 183752, DRUID = 106839, EVOKER = 351338,
	HUNTER = 147362, MAGE = 2139, MONK = 116705, PALADIN = 96231, PRIEST = 15487,
	ROGUE = 1766, SHAMAN = 57994, WARRIOR = 6552, WARLOCK = 19647,
}

local SPEC_KICK = {
	[102] = 78675,
	[255] = 187707,
	[105] = false,
	[1468] = false,
	[65] = false,
	[256] = false,
	[257] = false,
	[270] = false,
}

local HEALER_NO_KICK = { DRUID = true, EVOKER = true, PALADIN = true, PRIEST = true, MONK = true }

-- HEALER KICK LENGTH. A Restoration Shaman's Wind Shear is 30 seconds while
-- Elemental and Enhancement keep 12, under the same spell ID, so the ID alone
-- cannot pick the length: a kick with a healerCd uses it for a member who
-- heals. The spec decides once it is known (an inspect for party members, the
-- spec list for us) - a Resto Shaman queued as DPS still has the 30 - and the
-- assigned role stands in until then.
local HEALER_SPEC = { [65] = true, [105] = true, [256] = true, [257] = true, [264] = true, [270] = true, [1468] = true }

local function Heals(spec, role)
	if spec then return HEALER_SPEC[spec] or false end
	return role == 'HEALER'
end

local function KickCd(spell, heals)
	local kick = spell and KICKS[spell]
	if not kick then return nil end
	return heals and kick.healerCd or kick.cd
end

-- ns.PlayerSpec answers with the spec INDEX; HEALER_SPEC is keyed by spec ID.
local function SelfSpecId()
	local idx = ns.PlayerSpec()
	local get = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo or _G.GetSpecializationInfo
	if not idx or not get then return nil end
	local ok, id = pcall(get, idx)
	if ok and not secret(id) and type(id) == 'number' and id > 0 then return id end
	return nil
end

local PLAYER_KICKS = {
	DEATHKNIGHT = { 47528 }, DEMONHUNTER = { 183752 }, DRUID = { 78675, 106839 },
	EVOKER = { 351338 }, HUNTER = { 187707, 147362 }, MAGE = { 2139 }, MONK = { 116705 },
	PALADIN = { 96231 }, PRIEST = { 15487 }, ROGUE = { 1766 }, SHAMAN = { 57994 },
	WARRIOR = { 6552 },
}
local WARLOCK_PET_KICKS = { { pet = 89766, poll = 119914 }, { pet = 19647, poll = 119910 } }

local function SpellKnown(id, bank)
	if not (C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook) then
		return _G.IsSpellKnown and _G.IsSpellKnown(id) or false
	end
	local ok, known = pcall(C_SpellBook.IsSpellKnownOrInSpellBook, id, bank)
	return ok and known and not secret(known) and true or false
end

local function PlayerKick()
	local class = UnitClassBase('player')
	if not class or secret(class) then return nil end
	if class == 'WARLOCK' then
		local petBank = _G.Enum and _G.Enum.SpellBookSpellBank and _G.Enum.SpellBookSpellBank.Pet
		for _, k in ipairs(WARLOCK_PET_KICKS) do
			if petBank and SpellKnown(k.pet, petBank) then return k.pet, k.poll end
		end
		if SpellKnown(132409) then return 19647, 132409 end
		return nil
	end
	for _, id in ipairs(PLAYER_KICKS[class] or {}) do
		if SpellKnown(id) then return id, id end
	end
	return nil
end

local UNITS = { 'player', 'party1', 'party2', 'party3', 'party4' }
local CAST_OWNER = {
	player = 'player', pet = 'player',
	party1 = 'party1', partypet1 = 'party1',
	party2 = 'party2', partypet2 = 'party2',
	party3 = 'party3', partypet3 = 'party3',
	party4 = 'party4', partypet4 = 'party4',
}

local probe = {}
local function Probe(unit)
	local p = probe[unit]
	if not p then p = { plain = 0, secret = 0 } probe[unit] = p end
	return p
end
local obs = { total = 0, readable = 0, secret = 0, mine = 0, guessed = 0, unmatched = 0, meter = 0, confirmed = 0, named = 0, unconfirmed = 0 }

local PARTY_UNITS = { 'party1', 'party2', 'party3', 'party4' }

-- row.cd is KickCd's answer for that member (see HEALER KICK LENGTH).
local function MemberCd(row)
	local spell = row.spell
	if spell and KICKS[spell] then return row.cd or KICKS[spell].cd end
	return GetCfg().partyCd or 15
end

local frame
local rows = {}
local pool = {}
local shown = {}
local previewActive = false
local specByGUID = {}
local members = {}

local BUNDLED_BAR = 'Interface\\AddOns\\XerionUI-Plugin\\Media\\KiraBar'
local barTexPath
-- A MISS IS REMEMBERED TOO. Without an installer-registered 'XerionUI - Main'
-- every StyleRow (so every Rebuild, so every roster event) walked the whole
-- statusbar list with two gsubs and a lower per entry, to find the same
-- nothing again. The miss is only trusted while LibSharedMedia can tell us it
-- went stale: its 'LibSharedMedia_Registered' callback drops the memo when a
-- statusbar is added, so a texture registered after the first scan is still
-- found by the next StyleRow, exactly as before. No lib, or a lib without
-- callbacks, keeps the old rescan - with no lib there is nothing to walk.
local barTexMiss, barTexWatched = false, false

local function BarTex()
	if barTexPath then return barTexPath end
	if barTexMiss then return BUNDLED_BAR end
	local lib = ns.LSM and ns.LSM()
	local hash = lib and lib.HashTable and lib:HashTable('statusbar')
	if hash then
		for name, path in pairs(hash) do
			local plain = tostring(name):gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', ''):lower()
			if plain == 'kiraui - main' and type(path) == 'string' and path ~= '' then
				barTexPath = path
				return path
			end
		end
	end
	if lib and not barTexWatched and type(lib.RegisterCallback) == 'function' then
		-- CallbackHandler takes the owner as its first argument (a string is
		-- allowed), so this is a dot call; a colon would pass the lib itself.
		barTexWatched = pcall(lib.RegisterCallback, 'XerionUIPluginInterruptsBarTex', 'LibSharedMedia_Registered', function(_, mediatype)
			if mediatype == 'statusbar' then barTexMiss = false end
		end) and true or false
	end
	if barTexWatched then barTexMiss = true end
	return BUNDLED_BAR
end

local function ClassRGB(class)
	local c = class and C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class)
	if not c and class and _G.RAID_CLASS_COLORS then c = _G.RAID_CLASS_COLORS[class] end
	if c then return c.r or 0.7, c.g or 0.7, c.b or 0.7 end
	return 0.7, 0.7, 0.7
end

local function ApplyPosition()
	if not frame then return end
	local cfg = GetCfg()
	frame:ClearAllPoints()
	frame:SetPoint('CENTER', UIParent, 'CENTER', cfg.x or 0, cfg.y or 0)
end

local function EnsureFrame()
	if frame then return end
	frame = CreateFrame('Frame', 'XerionUIInterrupts', UIParent)
	frame:SetFrameStrata('MEDIUM')
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(false)
	frame:RegisterForDrag('RightButton')
	ns.MakeDraggable(frame, GetCfg, 'x', 'y', function() ApplyPosition() end)
	frame:Hide()
end

-- Borders are four 1px edges drawn INSIDE the rect they outline, on a frame
-- that sits above the status bar. The obvious cheap trick - one black texture
-- behind the bar, anchored a pixel outside it - is wrong here for three
-- reasons: it steals from cfg.spacing (a gap of 3 reads as 1 once the rows
-- above and below each push a pixel into it), neighbouring rows then overlap
-- their outlines so an edge can vanish depending on stacking order, and a
-- border parented to row.bar would blink out whenever the kick comes off
-- cooldown, because that state hides the bar frame and shows row.ready in its
-- place. Drawn inside and on top, the outline is state-independent and every
-- row stays exactly cfg.height tall.
local function NewBorder(parent)
	local t = {}
	for i = 1, 4 do
		t[i] = parent:CreateTexture(nil, 'ARTWORK', nil, 7)
		t[i]:SetColorTexture(0, 0, 0, 1)
	end
	return t
end

local function SetBorder(t, anchor, shown)
	if not shown then
		for i = 1, 4 do t[i]:Hide() end
		return
	end
	t[1]:ClearAllPoints()
	t[1]:SetPoint('TOPLEFT', anchor, 'TOPLEFT')
	t[1]:SetPoint('TOPRIGHT', anchor, 'TOPRIGHT')
	t[1]:SetHeight(1)
	t[2]:ClearAllPoints()
	t[2]:SetPoint('BOTTOMLEFT', anchor, 'BOTTOMLEFT')
	t[2]:SetPoint('BOTTOMRIGHT', anchor, 'BOTTOMRIGHT')
	t[2]:SetHeight(1)
	t[3]:ClearAllPoints()
	t[3]:SetPoint('TOPLEFT', t[1], 'BOTTOMLEFT')
	t[3]:SetPoint('BOTTOMLEFT', t[2], 'TOPLEFT')
	t[3]:SetWidth(1)
	t[4]:ClearAllPoints()
	t[4]:SetPoint('TOPRIGHT', t[1], 'BOTTOMRIGHT')
	t[4]:SetPoint('BOTTOMRIGHT', t[2], 'TOPRIGHT')
	t[4]:SetWidth(1)
	for i = 1, 4 do t[i]:Show() end
end

local function NewRow()
	local row = CreateFrame('Frame', nil, frame)
	row.bg = row:CreateTexture(nil, 'BACKGROUND')
	-- Deliberately not SetAllPoints: StyleRow anchors it to where the bar starts
	-- so the icon gap stays a hole. See the comment there.
	row.icon = row:CreateTexture(nil, 'ARTWORK')
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.mark = row:CreateTexture(nil, 'ARTWORK')
	row.mark:SetTexture('Interface\\TargetingFrame\\UI-RaidTargetingIcons')
	row.mark:Hide()
	row.ready = row:CreateTexture(nil, 'ARTWORK')
	row.bar = CreateFrame('StatusBar', nil, row)
	row.bar:SetMinMaxValues(0, 1)
	row.bar:SetValue(1)
	row.text = CreateFrame('Frame', nil, row)
	row.text:SetAllPoints()
	row.text:SetFrameLevel(row.bar:GetFrameLevel() + 1)
	row.barBorder = NewBorder(row.text)
	row.iconBorder = NewBorder(row.text)
	row.name = row.text:CreateFontString(nil, 'OVERLAY')
	row.name:SetWordWrap(false)
	row.timer = row.text:CreateFontString(nil, 'OVERLAY')
	-- Rebuild clears the timer before styling a row, and the icon-only style
	-- deliberately leaves its text hidden. Give both strings a font up front so
	-- SetText is safe in either presentation mode.
	local font = ns.GetFont()
	row.name:SetFont(font, 12, 'OUTLINE')
	row.timer:SetFont(font, 12, 'OUTLINE')
	row.swipe = CreateFrame('Cooldown', nil, row, 'CooldownFrameTemplate')
	row.swipe:SetAllPoints(row)
	row.swipe:SetDrawEdge(false)
	row.swipe:SetDrawBling(false)
	row.swipe:Hide()
	return row
end

local function AcquireRow()
	local row = table.remove(pool)
	if not row then row = NewRow() end
	row.cdStart, row.cdDur, row.previewRestart = nil, nil, nil
	row.kickedTex, row.markIdx, row.previewKicked = nil, nil, nil
	return row
end

local function ReleaseRow(row)
	row:Hide()
	row.cdStart, row.cdDur, row.previewRestart, row.guid = nil, nil, nil, nil
	row.kickedTex, row.markIdx, row.previewKicked = nil, nil, nil
	-- The raid marker has to be cleared here, not just hidden with the row.
	-- Rows are pooled, and StyleRow re-shows the mark straight off row.hasMark
	-- without being told whose row it is now - so a marker left set by the
	-- preview reappeared on whichever real party member recycled that row.
	row.hasMark = nil
	row.mark:Hide()
	pool[#pool + 1] = row
end

-- WHAT THE ICON BOX SHOWS. By default the kick itself. With iconSource set to
-- 'kicked', a bar that was started by an interrupt shows the enemy spell that
-- interrupt stopped instead, for as long as the bar runs - so a glance at the
-- stack says "the Frostbolt on skull is handled, the heal is not" rather than
-- repeating what the name and class colour already say.
--
-- In a key the interrupted cast's spell ID arrives secret, so nothing here can
-- know WHICH spell it was. It does not need to: C_Spell.GetSpellTexture and
-- Texture:SetTexture both take secret arguments from addon code, so the
-- texture travels from the event to the row untouched and the client draws
-- it. row.kickedTex is only ever stored, handed to SetTexture, or tested with
-- type() - never compared, formatted or used as a key.
--
-- Everything without an interrupt behind it falls back to the kick icon: a
-- ready row, your own kick that hit nothing, a bar started from a readable
-- cast before its interrupt was seen, or a texture the client did not give.
local KICK_ICON = 'Interface\\Icons\\Ability_Kick'

local function PaintIcon(row, cfg)
	if cfg.iconSource == 'kicked' and type(row.kickedTex) ~= 'nil'
		and pcall(row.icon.SetTexture, row.icon, row.kickedTex) then
		return
	end
	local tex = row.spell and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(row.spell)
	row.icon:SetTexture(tex or KICK_ICON)
end

local function StyleRow(row, cfg)
	if cfg.displayMode == 'icon' then
		local size = cfg.iconSize or 24
		row:SetSize(size, size)
		row.bg:Hide()
		row.mark:Hide()
		row.bar:Hide()
		row.ready:Hide()
		row.icon:ClearAllPoints()
		row.icon:SetPoint('TOPLEFT')
		row.icon:SetPoint('BOTTOMRIGHT')
		row.icon:Show()
		row.text:Show()
		row.name:Hide()
		row.timer:Hide()
		SetBorder(row.iconBorder, row.icon, true)
		row.swipe:ClearAllPoints()
		row.swipe:SetAllPoints(row.icon)
		if row.cdStart and row.cdDur then
			row.swipe:SetCooldown(row.cdStart, row.cdDur)
			row.swipe:Show()
		else
			row.swipe:Hide()
		end
		PaintIcon(row, cfg)
		return
	end
	row.text:Show()
	row.name:Show()
	row.timer:Show()
	row.swipe:Hide()
	row.bg:Show()
	local h, w = cfg.height or 20, cfg.width or 180
	row:SetSize(w, h)
	local r, g, b = ClassRGB(row.class)
	row.bg:SetColorTexture(r * 0.15, g * 0.15, b * 0.15, cfg.bgAlpha or 0.6)
	row.mark:ClearAllPoints()
	row.mark:SetPoint('RIGHT', row, 'LEFT', -3, 0)
	row.mark:SetSize(h, h)
	row.mark:SetShown((cfg.showMark and row.hasMark) and true or false)
	local left = 0
	row.icon:ClearAllPoints()
	row.icon:SetPoint('LEFT')
	row.icon:SetSize(h, h)
	row.icon:SetShown(cfg.showIcon and true or false)
	-- The gap between the icon box and the bar has to be a HOLE, not a sliver of
	-- row background. The first attempt at this left the background running all
	-- the way under it, and bg is the class colour at 0.15 - near black, the same
	-- near black as the two inset border edges sitting either side of the gap.
	-- Three dark pixels in a row read as one seam, so the icon looked embedded in
	-- the bar instead of standing beside it. Starting the background where the
	-- bar starts lets the gap show whatever is behind the row, which is the only
	-- thing that reads as separation at this size. Default 2 rather than 1
	-- because at UI scales below 1 a single logical pixel can round away to
	-- nothing; cfg.iconGap is there for anyone who wants it back to 1, or wider.
	local gap = cfg.iconGap or 2
	if cfg.showIcon then left = h + gap end
	row.bg:ClearAllPoints()
	row.bg:SetPoint('TOPLEFT', row, 'TOPLEFT', left, 0)
	row.bg:SetPoint('BOTTOMRIGHT', row, 'BOTTOMRIGHT')
	row.bar:ClearAllPoints()
	row.bar:SetPoint('TOPLEFT', left, 0)
	row.bar:SetPoint('BOTTOMRIGHT')
	local tex = BarTex()
	row.bar:SetStatusBarTexture(tex)
	row.bar:SetStatusBarColor(r, g, b)
	row.ready:ClearAllPoints()
	row.ready:SetPoint('TOPLEFT', row.bar)
	row.ready:SetPoint('BOTTOMRIGHT', row.bar)
	row.ready:SetTexture(tex)
	row.ready:SetVertexColor(r, g, b)
	SetBorder(row.barBorder, row.bar, true)
	SetBorder(row.iconBorder, row.icon, cfg.showIcon)
	local font, size = ns.GetFont(), cfg.textSize or 12
	row.timer:SetFont(font, size, 'OUTLINE')
	row.timer:ClearAllPoints()
	row.timer:SetPoint('RIGHT', row.bar, 'RIGHT', -4, 0)
	row.timer:SetJustifyH('RIGHT')
	row.timer:SetShown(cfg.showTimer and true or false)
	row.name:SetFont(font, size, 'OUTLINE')
	row.name:ClearAllPoints()
	row.name:SetPoint('LEFT', row.bar, 'LEFT', 4, 0)
	row.name:SetPoint('RIGHT', row.timer, 'LEFT', -4, 0)
	row.name:SetJustifyH('LEFT')
	row.name:SetText(row.label or '')
	PaintIcon(row, cfg)
end

local function Layout(list)
	if not frame then return end
	local cfg = GetCfg()
	local h, w, gap = cfg.height or 20, cfg.width or 180, cfg.spacing or 2
	local iconMode = cfg.displayMode == 'icon'
	local iconSize = cfg.iconSize or 24
	local stackGap = iconMode and (cfg.partyGap or 3) or gap
	frame:SetSize(iconMode and iconSize or w, iconMode and iconSize or h)
	local prev
	for _, row in ipairs(list) do
		row:ClearAllPoints()
		local health = iconMode and row.unit and ns.EPHGetHealthBar and ns.EPHGetHealthBar(row.unit)
		if health then
			-- The rows live under our UIParent container rather than inside the
			-- secure party frames. Match their strata and raise their frame level
			-- so the icons remain visible beside EllesmereUI's health bars.
			local strata = health:GetFrameStrata()
			if strata then row:SetFrameStrata(strata) end
			row:SetFrameLevel(health:GetFrameLevel() + 5)
			if cfg.partySide == 'LEFT' then
				row:SetPoint('RIGHT', health, 'LEFT', -stackGap, 0)
			else
				row:SetPoint('LEFT', health, 'RIGHT', stackGap, 0)
			end
		else
			row:SetFrameStrata('MEDIUM')
			row:SetFrameLevel(frame:GetFrameLevel() + 1)
		end
		if not health and not prev then
			row:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, 0)
		elseif not health and cfg.growth == 'UP' then
			row:SetPoint('BOTTOMLEFT', prev, 'TOPLEFT', 0, stackGap)
		elseif not health then
			row:SetPoint('TOPLEFT', prev, 'BOTTOMLEFT', 0, -stackGap)
		end
		prev = row
	end
end

local function ShouldShow()
	if previewActive then return true end
	local cfg = GetCfg()
	if not cfg.enable then return false end
	if #shown == 0 then return false end
	if cfg.groupOnly and not IsInGroup() then return false end
	if cfg.hideInRaid and IsInRaid() then return false end
	return true
end

local Tick

local function StartTicker()
	if frame and not frame:GetScript('OnUpdate') then
		frame.__acc = 0
		frame:SetScript('OnUpdate', Tick)
	end
end

local function FormatRem(rem)
	if rem >= 10 then return sformat('%d', mfloor(rem + 0.5)) end
	return sformat('%.1f', rem)
end

local function StackBefore(a, b)
	local ra, rb = a.cdStart ~= nil, b.cdStart ~= nil
	if ra ~= rb then return rb end
	if ra then
		local la, lb = a.cdStart + a.cdDur, b.cdStart + b.cdDur
		if la ~= lb then return la < lb end
	else
		local ca = KICKS[a.spell] and (a.cd or KICKS[a.spell].cd) or 99
		local cb = KICKS[b.spell] and (b.cd or KICKS[b.spell].cd) or 99
		if ca ~= cb then return ca < cb end
	end
	return (a.order or 0) < (b.order or 0)
end

local function ShowRows()
	table.sort(shown, StackBefore)
	local visible = {}
	for _, row in ipairs(shown) do
		if row:IsShown() then visible[#visible + 1] = row end
	end
	Layout(visible)
	if frame then frame:SetShown(ShouldShow()) end
end

local function SetMark(row, idx)
	row.hasMark = false
	row.markIdx = idx
	if type(idx) ~= 'nil' and _G.SetRaidTargetIconTexture then
		row.hasMark = pcall(_G.SetRaidTargetIconTexture, row.mark, idx) and true or false
	end
	row.mark:SetShown((row.hasMark and GetCfg().showMark) and true or false)
end

-- nil puts the kick icon back; see WHAT THE ICON BOX SHOWS.
local function SetKicked(row, tex)
	row.kickedTex = tex
	PaintIcon(row, GetCfg())
end

local function SetReady(row)
	row.cdStart, row.cdDur = nil, nil
	row.timer:SetText('')
	row.__lastText = nil -- see Tick
	row.bar:Hide()
	row.ready:Show()
	row.swipe:Hide()
	SetMark(row, nil)
	SetKicked(row, nil)
	if not GetCfg().showReady and not previewActive then row:Hide() end
	ShowRows()
end

local function StartCooldown(row, start, dur)
	if not dur or dur <= 0 then return end
	row.cdStart, row.cdDur = start, dur
	if GetCfg().displayMode == 'icon' then
		row.swipe:SetCooldown(start, dur)
		row.swipe:Show()
	end
	row.bar:SetMinMaxValues(0, dur)
	row.bar:SetValue(dur - (GetTime() - start))
	row.ready:Hide()
	row.bar:Show()
	row:Show()
	ShowRows()
	StartTicker()
end

local learnedSwept = false
local function LearnedStore()
	local db = _G.XerionUIChangesCharDB
	if type(db) ~= 'table' then return nil end
	if type(db.ikLearned) ~= 'table' then db.ikLearned = {} end
	local store = db.ikLearned
	if not learnedSwept then
		-- Once a session: drop lengths learned before the cap existed, which
		-- LearnLength now refuses to write.
		learnedSwept = true
		for spell, v in pairs(store) do
			local cap = KICKS[spell] and KICKS[spell].cd
			if type(v) == 'number' and cap and v > cap + 0.25 then store[spell] = nil end
		end
	end
	return store
end

-- A measured length may only SHORTEN what the table says. A kick that
-- interrupted nothing runs its full base cooldown (Mind Freeze is 15 without
-- the 3-second Coldthirst refund a successful interrupt gives it), and one
-- such kick must not teach the bar 15 when every real kick is 12 - that is
-- exactly what happened on 2026-09-06. The stretch in Tick covers the long
-- case on screen; nothing needs to remember it.
-- Our own kick on its healer length (Wind Shear as Resto). That length is
-- never learned: the store keeps the SHORTEST length per spell, so the 12 the
-- other two specs of the same character teach it would win over the 30.
local function OwnHealerCd(spell)
	local m = members.player
	return m and m.heals and KICKS[spell] and KICKS[spell].healerCd or nil
end

local function LearnLength(spell, secs)
	local store = LearnedStore()
	if not store or not spell or type(secs) ~= 'number' or secs < 3 then return end
	if OwnHealerCd(spell) then return end
	local cap = KICKS[spell] and KICKS[spell].cd
	if cap and secs > cap + 0.25 then return end
	local cur = store[spell]
	if type(cur) ~= 'number' or secs < cur then store[spell] = mfloor(secs * 2 + 0.5) / 2 end
end

local function OwnCd(spell)
	local healerCd = OwnHealerCd(spell)
	if healerCd then return healerCd, 'healer table' end
	local store = LearnedStore()
	local v = store and spell and store[spell]
	if type(v) == 'number' and v > 0 then return v, 'measured' end
	local cap = spell and KICKS[spell] and KICKS[spell].cd
	if cap then return cap, 'table' end
	return GetCfg().partyCd or 15, 'fallback'
end

local function RefreshSelf(castSpell)
	local row = rows.player
	if not row or previewActive then return end
	local poll = row.poll or row.spell
	local now = GetTime()
	local info = poll and C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(poll)
	if not info then
		if castSpell and KICKS[castSpell] and not row.cdStart then
			StartCooldown(row, now, OwnCd(castSpell))
		end
		return
	end
	local running = (info.isActive and not info.isOnGCD) and true or false
	if not running then
		if row.cdStart then SetReady(row) end
		return
	end
	local st, du = info.startTime, info.duration
	if not secret(st) and not secret(du) and type(st) == 'number' and type(du) == 'number' and du > 2 then
		LearnLength(poll, du)
		if not row.cdStart or row.cdDur ~= du or (row.cdStart - st) > 0.5 or (st - row.cdStart) > 0.5 then
			StartCooldown(row, st, du)
		end
		row.fromCast = nil
		return
	end
	if row.cdStart then return end
	StartCooldown(row, now, OwnCd(poll))
	row.fromCast = castSpell ~= nil
end

-- Every call is a fresh table from the client, so Tick rations them: the
-- stamp below is what SELF POLL THROTTLE there reads.
local function SelfStillDown(row, now)
	row.__pollAt = now
	local poll = row.poll or row.spell
	local info = poll and C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(poll)
	if not info then return true end
	return (info.isActive and not info.isOnGCD) and true or false
end

local function SelfEndedEarly(row, now)
	if SelfStillDown(row, now) then return false end
	local elapsed = now - row.cdStart
	if row.fromCast then LearnLength(row.poll or row.spell, elapsed) end
	row.fromCast = nil
	return true
end

local function SelfStretch(row)
	row.cdDur = row.cdDur + 0.5
	row.bar:SetMinMaxValues(0, row.cdDur)
end

-- SELF POLL THROTTLE. The own row used to ask C_Spell.GetSpellCooldown on
-- every 0.05 s tick for "did it come back early" (a Coldthirst refund, a
-- learned length that is still too long). That answer is now asked at most
-- every 0.15 s - five times a second at 60 fps, where ticks land 0.067 s
-- apart. It cannot simply move to SPELL_UPDATE_COOLDOWN: nothing documents
-- that event firing when a cooldown runs out on its own, and out of combat
-- there is no other cast to set it off. The bar may now turn ready up to
-- ~0.2 s later on an early end, and LearnLength sees an elapsed time up to
-- that much longer - still inside the +-0.25 s its half-second rounding
-- forgives, so the lengths it stores do not change. The rem <= 0 check stays
-- unthrottled: it runs once per half-second stretch at most.
--
-- The timer text is cached per row for the same reason: above 10 s it changes
-- once a second and below it ten times, while the tick runs twenty. At 10 s
-- and above the cache holds the whole second FormatRem prints (a number), so
-- nothing is formatted until that number moves; below 10 it holds the string
-- itself, because a tenths key worked out in Lua cannot be proven to round the
-- way '%.1f' does at every half-tenth. A number never equals a string, so
-- crossing 10 either way always writes. Both only ever come from our own
-- GetTime arithmetic, never a client value, so the compare is safe in a key.
-- Every other writer of row.timer clears it (SetReady, Rebuild). SetValue
-- still runs every tick so the bar drains smoothly.
Tick = function(self, elapsed)
	self.__acc = (self.__acc or 0) + elapsed
	if self.__acc < 0.05 then return end
	self.__acc = 0
	local now, busy = GetTime(), false
	local showTimer = GetCfg().showTimer
	for _, row in ipairs(shown) do
		if row.cdStart then
			local rem = row.cdStart + row.cdDur - now
			if rem <= 0 and row.unit == 'player' and not previewActive and SelfStillDown(row, now) then
				SelfStretch(row)
				busy = true
			elseif rem <= 0 then
				if previewActive then row.previewRestart = now + 2 busy = true end
				SetReady(row)
			elseif row.unit == 'player' and not previewActive and now - (row.__pollAt or 0) >= 0.15 and SelfEndedEarly(row, now) then
				SetReady(row)
			else
				row.bar:SetValue(rem)
				if showTimer then
					if rem >= 10 then
						local secs = mfloor(rem + 0.5)
						if secs ~= row.__lastText then
							row.__lastText = secs
							row.timer:SetText(FormatRem(rem))
						end
					else
						local txt = FormatRem(rem)
						if txt ~= row.__lastText then
							row.__lastText = txt
							row.timer:SetText(txt)
						end
					end
				end
				busy = true
			end
		elseif previewActive and row.previewRestart then
			if now >= row.previewRestart then
				row.previewRestart = nil
				StartCooldown(row, now, row.cd or 15)
				SetMark(row, 8)
				SetKicked(row, row.previewKicked)
			end
			busy = true
		end
	end
	if not busy then self:SetScript('OnUpdate', nil) end
end

local function Read(fn, unit)
	if not fn then return nil end
	local ok, v = pcall(fn, unit)
	if not ok or secret(v) then return nil end
	return v
end

local function MemberSpell(m)
	if m.spec and SPEC_KICK[m.spec] ~= nil then return SPEC_KICK[m.spec] or nil end
	if m.role == 'HEALER' and HEALER_NO_KICK[m.class] then return nil end
	return CLASS_KICK[m.class]
end

-- Every member without a known spec is worth one inspect, not just the
-- classes whose KICK depends on it (Druid, Hunter, and the healer-capable
-- classes with no role assigned): the meter names its sources by class and
-- spec icon, so two Death Knights in one group can only be told apart once
-- their specs are known.
local function WantsSpec(m)
	return not m.spec
end

local inspectQueue = {}
local inspectTicker
local lastInspectAt = 0
local QueueInspect

local function UnitForGUID(guid)
	for unit, m in pairs(members) do
		if m.guid == guid then return unit end
	end
end

local ScheduleRebuild

local function ReadSpec(unit)
	local get = C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization or _G.GetInspectSpecialization
	local spec = Read(get, unit)
	if type(spec) == 'number' and spec > 0 then return spec end
	return nil
end

-- OFF MEANS NO INSPECTS. Switching the module off used to leave the queue and
-- its ticker running, so party members kept being inspected every 2 s until
-- /reload. Both go when it is off, and so do the retry counts: turning it back
-- on runs Rebuild, which queues everyone without a spec afresh, exactly as a
-- first enable does. The queue is emptied too, not just the ticker stopped:
-- QueueInspect skips a unit already queued before it starts a ticker.
local function StopInspects()
	wipe(inspectQueue)
	if inspectTicker then inspectTicker:Cancel() inspectTicker = nil end
	for _, m in pairs(members) do m.tries = nil end
end

local function InspectStep()
	if not GetCfg().enable then StopInspects() return end
	if #inspectQueue == 0 then
		if inspectTicker then inspectTicker:Cancel() inspectTicker = nil end
		return
	end
	local sheet = _G.InspectFrame
	if sheet and sheet:IsShown() then return end
	if GetTime() - lastInspectAt < 2 then return end
	local unit = table.remove(inspectQueue, 1)
	local m = members[unit]
	if not m or not WantsSpec(m) then return end
	if m.guid and specByGUID[m.guid] then
		m.spec = specByGUID[m.guid]
		ScheduleRebuild()
		return
	end
	m.tries = (m.tries or 0) + 1
	if m.tries > 12 then
		C_Timer.After(30, function()
			local cur = members[unit]
			if cur and cur.guid == m.guid and WantsSpec(cur) then
				cur.tries = 0
				QueueInspect(unit)
			end
		end)
		return
	end
	if Read(CanInspect, unit) and NotifyInspect then
		lastInspectAt = GetTime()
		pcall(NotifyInspect, unit)
	end
	inspectQueue[#inspectQueue + 1] = unit
end

QueueInspect = function(unit)
	for _, u in ipairs(inspectQueue) do if u == unit then return end end
	inspectQueue[#inspectQueue + 1] = unit
	if not inspectTicker and C_Timer and C_Timer.NewTicker then
		inspectTicker = C_Timer.NewTicker(1, InspectStep)
	end
end

local function OnInspectReady(guid)
	if secret(guid) then return end
	local unit = UnitForGUID(guid)
	if not unit then return end
	local m = members[unit]
	local spec = ReadSpec(unit)
	if spec then
		specByGUID[guid] = spec
		if m.spec ~= spec then
			m.spec = spec
			ScheduleRebuild()
		end
	end
end

local function Rebuild()
	if previewActive or not frame then return end
	local cfg = GetCfg()
	local old = members
	members = {}
	wipe(shown)
	local keep = {}
	for idx, unit in ipairs(UNITS) do
		local isSelf = unit == 'player'
		if (not isSelf or cfg.showSelf) and UnitExists(unit) then
			local class = Read(UnitClassBase, unit)
			if class then
				local guid = Read(UnitGUID, unit)
				local m = {
					guid = guid,
					name = Read(UnitName, unit),
					class = class,
					role = Read(UnitGroupRolesAssigned, unit),
					spec = guid and specByGUID[guid] or nil,
					tries = old[unit] and old[unit].guid == guid and old[unit].tries or nil,
				}
				m.heals = Heals(isSelf and SelfSpecId() or m.spec, m.role)
				members[unit] = m
				local spell, poll
				if isSelf then
					spell, poll = PlayerKick()
				else
					spell = MemberSpell(m)
					if WantsSpec(m) then QueueInspect(unit) end
				end
				m.spell = spell
				if spell then
					local row = rows[unit]
					if row and row.guid ~= guid then
						ReleaseRow(row)
						row = nil
					end
					if not row then
						row = AcquireRow()
						rows[unit] = row
					end
					keep[unit] = true
					row.unit, row.guid, row.class, row.order = unit, guid, class, idx
					row.label = m.name or unit
					row.spell, row.poll = spell, poll
					row.cd = KickCd(spell, m.heals) or 15
					StyleRow(row, cfg)
					local busy = row.cdStart ~= nil
					if busy then
						row.ready:Hide()
						row.bar:Show()
					else
						row.bar:Hide()
						row.ready:Show()
						row.timer:SetText('')
						row.__lastText = nil -- see Tick
					end
					row:SetShown((cfg.showReady or busy) and true or false)
					shown[#shown + 1] = row
				end
			end
		end
	end
	for unit, row in pairs(rows) do
		if not keep[unit] then
			ReleaseRow(row)
			rows[unit] = nil
		end
	end
	ShowRows()
	RefreshSelf()
end

local rebuildPending = false
ScheduleRebuild = function()
	if rebuildPending then return end
	rebuildPending = true
	C_Timer.After(0.2, function()
		rebuildPending = false
		Rebuild()
	end)
end

-- kicked: a stand-in enemy cast per row, shown when iconSource is 'kicked'.
local PREVIEW = {
	{ label = 'Kiratank',   class = 'DEATHKNIGHT', spell = 47528,  kicked = 'Interface\\Icons\\Spell_Shadow_ShadowBolt' },
	{ label = 'Brewnado',   class = 'MONK',        spell = 116705, kicked = 'Interface\\Icons\\Spell_Frost_FrostBolt02' },
	{ label = 'Pyroclast',  class = 'MAGE',        spell = 2139,   kicked = 'Interface\\Icons\\Spell_Holy_FlashHeal' },
	{ label = 'Stormcall',  class = 'SHAMAN',      spell = 57994,  kicked = 'Interface\\Icons\\Spell_Fire_FlameBolt' },
	{ label = 'Nightblade', class = 'ROGUE',       spell = 1766,   kicked = 'Interface\\Icons\\Spell_Nature_Lightning' },
}

local function BuildPreview()
	local cfg = GetCfg()
	for unit, row in pairs(rows) do ReleaseRow(row) rows[unit] = nil end
	wipe(shown)
	local now = GetTime()
	for i, p in ipairs(PREVIEW) do
		local row = AcquireRow()
		rows['preview' .. i] = row
		row.unit, row.guid, row.class, row.order = nil, nil, p.class, i
		row.label, row.spell, row.poll = p.label, p.spell, nil
		row.cd = KICKS[p.spell].cd
		row.previewKicked = p.kicked
		StyleRow(row, cfg)
		row:Show()
		shown[#shown + 1] = row
		if i == 1 then
			row.bar:Hide()
			row.ready:Show()
			row.previewRestart = now + 3
		else
			StartCooldown(row, now - (i - 1) * 2.5, row.cd)
			SetMark(row, 10 - i)
			SetKicked(row, p.kicked)
		end
	end
	ShowRows()
	StartTicker()
end

local function SetPreview(on)
	on = on and true or false
	if on == previewActive then return end
	previewActive = on
	EnsureFrame()
	if on then
		BuildPreview()
	else
		for unit, row in pairs(rows) do ReleaseRow(row) rows[unit] = nil end
		wipe(shown)
		Rebuild()
	end
	frame:EnableMouse(previewActive and not GetCfg().lock or false)
	frame:SetShown(ShouldShow())
end
ns.IKIsPreview = function() return previewActive end
ns.IKSetPreview = SetPreview

local function Apply()
	EnsureFrame()
	local cfg = GetCfg()
	ApplyPosition()
	frame:EnableMouse(previewActive and not cfg.lock or false)
	if not cfg.enable then
		if previewActive then SetPreview(false) end
		for unit, row in pairs(rows) do ReleaseRow(row) rows[unit] = nil end
		wipe(shown)
		StopInspects()
		frame:Hide()
		return
	end
	if previewActive then
		for _, row in ipairs(shown) do StyleRow(row, cfg) end
		ShowRows()
	else
		Rebuild()
	end
end

local lastSelfKickAt = -10
local selfClaimKick = -20    -- the own kick cast an interrupt has already been charged to
local lastObservedAt = -10
local lastObservedUnit
local lastGuessRow, lastGuessAt = nil, -10

local function MarkSelf(mark, tex)
	local row = rows.player
	if row then
		C_Timer.After(0, function()
			if row.cdStart then
				SetMark(row, mark)
				SetKicked(row, tex)
			end
		end)
	end
end

local function OnCast(unit, spellID)
	local owner = CAST_OWNER[unit]
	if not owner then return end
	local p = Probe(unit)
	if secret(spellID) then
		p.secret = p.secret + 1
		p.lastAt = GetTime()
		return
	end
	p.plain = p.plain + 1
	p.last, p.lastAt = spellID, GetTime()
	local kick = KICKS[spellID]
	if not kick then return end
	-- a guess handed back takes its marker and interrupted-spell icon along
	local handed, handMark, handTex
	if owner == 'player' then
		lastSelfKickAt = GetTime()
		if lastGuessRow and GetTime() - lastGuessAt < 0.4 then
			handed, handMark, handTex = true, lastGuessRow.markIdx, lastGuessRow.kickedTex
			SetReady(lastGuessRow)
			obs.guessed = obs.guessed - 1
			obs.mine = obs.mine + 1
			lastGuessRow = nil
			selfClaimKick = lastSelfKickAt
		end
	end
	if not GetCfg().enable or previewActive then return end
	local row = rows[owner]
	if not row or row.class ~= kick.class then return end
	if owner == 'player' then
		C_Timer.After(0, function() RefreshSelf(spellID) end)
		-- queued after RefreshSelf, so the own bar is running when MarkSelf looks
		if handed then MarkSelf(handMark, handTex) end
		return
	end
	local iconSpell = kick.icon or spellID
	if row.spell ~= iconSpell then
		row.spell = iconSpell
		row.cd = KickCd(spellID, members[owner] and members[owner].heals)
		if members[owner] then members[owner].spell = iconSpell end
		StyleRow(row, GetCfg())
	end
	lastObservedAt, lastObservedUnit = GetTime(), owner
	StartCooldown(row, GetTime(), MemberCd(row))
end

local function OwnerOfGUID(guid)
	local owner = UnitForGUID(guid)
	if owner then return owner end
	for _, unit in ipairs(PARTY_UNITS) do
		if members[unit] and Read(UnitGUID, 'partypet' .. unit:sub(-1)) == guid then return unit end
	end
	if Read(UnitGUID, 'pet') == guid then return 'player' end
	return nil
end

-- WHO KICKED, when the game will not say
-- In a key the interruptedBy GUID and every party cast ID are secret, so the
-- only witness left is the built-in damage meter. Its Interrupts session hands
-- back a list of sources whose numbers are secret in combat, but three things
-- about that list are not: the ORDER (the client sorts it by amount before
-- handing it over, Blizzard_DamageMeter just walks it with ipairs), and per
-- entry the classFilename, specIconID and isLocalPlayer fields, which the API
-- docs mark NeverSecret. Only the kicker's amount changes on a kick, so:
--   * an entry that was not in the list a moment ago is the kicker (their first
--     kick this session),
--   * an entry that climbed to a higher index is the kicker (they overtook
--     someone),
--   * a list with a single entry names the kicker outright,
--   * otherwise the kicker is still SOMEONE IN THE LIST (you cannot kick and
--     stay off it), which shrinks the guess to members who already kicked
--     this session instead of "shortest ready cooldown, party order".
-- Current and Overall sessions are two independently sorted views of the same
-- kick, so both are diffed; whichever moves first answers. The snapshot is
-- taken from the list itself on every read, so a session rolling over just
-- looks like entries vanishing, which the single-entry rule covers.
local SESSIONS = { 'Current', 'Overall' }
local meterSnap = {}
local lastMeterLists = {}
local specIconCache = {}

local function SpecIcon(specID)
	if not specID then return nil end
	local cached = specIconCache[specID]
	if cached ~= nil then return cached or nil end
	local get = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfoByID or _G.GetSpecializationInfoByID
	local ok, _, _, _, icon = pcall(get, specID)
	if not ok or secret(icon) or type(icon) ~= 'number' then icon = false end
	specIconCache[specID] = icon
	return icon or nil
end

local function ShortName(n)
	return (tostring(n):gsub('%-.*$', ''))
end

local function ReadMeterList(sessionType)
	local DM, E = _G.C_DamageMeter, _G.Enum
	if not (DM and DM.GetCombatSessionFromType and E and E.DamageMeterType and E.DamageMeterType.Interrupts) then return nil end
	local ok, session = pcall(DM.GetCombatSessionFromType, sessionType, E.DamageMeterType.Interrupts)
	if not ok or type(session) ~= 'table' or type(session.combatSources) ~= 'table' then return nil end
	local list, seen = {}, {}
	for _, src in ipairs(session.combatSources) do
		if type(src) == 'table' then
			local class = src.classFilename
			if secret(class) or type(class) ~= 'string' or class == '' then class = nil end
			if class then
				local me = src.isLocalPlayer
				if secret(me) then me = nil else me = me and true or false end
				local icon = src.specIconID
				if secret(icon) or type(icon) ~= 'number' then icon = nil end
				local name = src.name
				if secret(name) or type(name) ~= 'string' or name == '' then name = nil end
				local key = name and ShortName(name) or (class .. ':' .. tostring(icon) .. (me and ':me' or ''))
				seen[key] = (seen[key] or 0) + 1
				if seen[key] > 1 then key = key .. '#' .. seen[key] end
				list[#list + 1] = { key = key, class = class, icon = icon, me = me, name = name }
			end
		end
	end
	return list
end

-- Members that could be this meter entry. One hit is an answer; more is a
-- narrowed guess (two same-class same-spec strangers with hidden names).
local function MatchMember(e, out)
	local n = 0
	for _, unit in ipairs(UNITS) do
		local m = members[unit]
		local isMe = unit == 'player'
		local okUnit = e.me ~= nil and e.me and isMe
		if not okUnit and m and m.class == e.class then
			okUnit = e.me == nil or (e.me == isMe)
			if okUnit and e.name and m.name and ShortName(e.name) ~= ShortName(m.name) then okUnit = false end
			if okUnit and e.icon and m.spec then
				local icon = SpecIcon(m.spec)
				if icon and icon ~= e.icon then okUnit = false end
			end
		end
		if okUnit and not out[unit] then
			out[unit] = true
			n = n + 1
		end
	end
	return n
end

local function DiffMeter(sessionType)
	local list = ReadMeterList(sessionType)
	if not list then return nil end
	local old = meterSnap[sessionType]
	meterSnap[sessionType] = list
	if #list == 1 then return list[1], list end
	if not old then return nil, list end
	local oldIdx = {}
	for i, e in ipairs(old) do oldIdx[e.key] = i end
	local newcomer, climber, nNew, nClimb = nil, nil, 0, 0
	for i, e in ipairs(list) do
		local o = oldIdx[e.key]
		if not o then
			newcomer, nNew = e, nNew + 1
		elseif i < o then
			climber, nClimb = e, nClimb + 1
		end
	end
	if nNew == 1 then return newcomer, list end
	if nNew == 0 and nClimb == 1 then return climber, list end
	return nil, list
end

local function MeterKicker()
	local E = _G.Enum
	local ST = E and E.DamageMeterSessionType
	if not ST then return nil, nil end
	local cands = {}
	local narrowed = false
	for _, name in ipairs(SESSIONS) do
		local st = ST[name]
		if st then
			local e, list = DiffMeter(st)
			lastMeterLists[name] = list
			if e then
				local mine = {}
				if MatchMember(e, mine) == 1 then
					return next(mine), mine, name
				end
				if next(mine) and not narrowed then
					cands, narrowed = mine, true
				end
			elseif list and not narrowed then
				for _, entry in ipairs(list) do MatchMember(entry, cands) end
			end
		end
	end
	if not next(cands) then cands = nil end
	return nil, cands, nil
end

local function GuessKicker(cands, allowBusy)
	local best
	for _, unit in ipairs(PARTY_UNITS) do
		local row = rows[unit]
		if row and (allowBusy or not row.cdStart) and (not cands or cands[unit]) and (not best or StackBefore(row, best)) then best = row end
	end
	return best
end

-- The cast-ended events and meter hits still waiting to be paired; see
-- "TWO QUEUES" below.
local pendings, meterHits = {}, {}

-- Is another queued event closer to your own kick cast than this one? Then
-- this one is not yours, whatever the window says.
local function CloserToOwnKick(at)
	local d = mabs(at - lastSelfKickAt)
	for _, q in ipairs(pendings) do
		if mabs(q.at - lastSelfKickAt) < d then return true end
	end
	return false
end

local function Charge(at, owner, mark, cands, tex)
	if owner then
		if owner == 'player' then RefreshSelf() MarkSelf(mark, tex) return end
		lastObservedAt, lastObservedUnit = at, owner
		local row = rows[owner]
		if row then
			StartCooldown(row, at, MemberCd(row))
			SetMark(row, mark)
			SetKicked(row, tex)
		end
		return
	end
	lastObservedAt = at
	-- one own kick claims exactly one interrupt: a second one inside the
	-- window was somebody else's (two Death Knights kicking two mobs a
	-- moment apart is what this looked like on 2026-09-06), and so is one
	-- with another queued event sitting closer to the kick cast than it
	if lastSelfKickAt ~= selfClaimKick and mabs(at - lastSelfKickAt) < 0.8 and not CloserToOwnKick(at) then
		selfClaimKick = lastSelfKickAt
		obs.mine = obs.mine + 1
		lastObservedUnit = 'player'
		MarkSelf(mark, tex)
		return
	end
	-- The meter's candidate set beats our own ready/busy bookkeeping: if every
	-- candidate shows busy, one of our earlier charges was wrong, so re-charge
	-- the candidate closest to ready rather than an outsider.
	local row = GuessKicker(cands)
	if not row and cands then row = GuessKicker(cands, true) or GuessKicker(nil) end
	if not row then
		obs.unmatched = obs.unmatched + 1
		lastObservedUnit = nil
		return
	end
	obs.guessed = obs.guessed + 1
	lastObservedUnit = row.unit
	lastGuessRow, lastGuessAt = row, at
	StartCooldown(row, at, MemberCd(row))
	SetMark(row, mark)
	SetKicked(row, tex)
end

-- TWO QUEUES, PAIRED OLDEST-FIRST.
--
-- A single "pending" slot lost kicks: two people kicking two mobs a moment
-- apart produced two cast-ended events and two meter hits, and the second
-- event was thrown away as a duplicate of the first. Duplicates are real -
-- one interrupt is reported once per unit token pointing at that mob
-- (target, focus, nameplateN, bossN) - but those copies arrive in the SAME
-- frame, so "same frame" is the duplicate test, not "same half second".
-- Everything else goes into a queue, meter hits into another, and each hit
-- confirms the oldest event within a second of it. An event no hit ever
-- claims was a stun, a knock or a death and expires; a hit no event claims
-- (an interrupt on a mob we had no token for) expires the same way.
local lastEventAt = -10
local lastMeterOwner, lastMeterVia

local function Expire(list, now, onDrop)
	while list[1] and now - list[1].at > 1.5 do
		local e = table.remove(list, 1)
		if onDrop then onDrop(e) end
	end
end

local function DropUnconfirmed() obs.unconfirmed = obs.unconfirmed + 1 end

local function Pair(now)
	Expire(pendings, now, DropUnconfirmed)
	Expire(meterHits, now)
	while pendings[1] and meterHits[1] do
		local p, h = pendings[1], meterHits[1]
		local gap = p.at - h.at
		if gap > 1 then
			table.remove(meterHits, 1) -- a hit no event will claim
		elseif gap < -1 then
			table.remove(pendings, 1)  -- an event no hit will claim
			DropUnconfirmed()
		else
			table.remove(pendings, 1)
			table.remove(meterHits, 1)
			obs.confirmed = obs.confirmed + 1
			local owner = p.owner
			if not owner and h.owner then
				owner = h.owner
				obs.named = obs.named + 1
			end
			Charge(p.at, owner, p.mark, h.cands, p.icon)
		end
	end
end

local function OnEnemyInterrupted(unit, spellID, interruptedBy)
	if type(unit) ~= 'string' or secret(unit) then return end
	if CAST_OWNER[unit] then return end
	-- The event fires for every token a unit is seen through, so a friend's
	-- cancelled cast (a party member who moved mid-cast) also arrives as
	-- target, focus, raidN or a friendly nameplate, and was charged as a kick.
	-- Only a unit we can attack can have been kicked. An unreadable answer
	-- lets the event through, the same as before this check.
	if ns.Ask(_G.UnitCanAttack, 'player', unit) == false then return end
	obs.total = obs.total + 1
	local cfg = GetCfg()
	if not cfg.enable or not cfg.observe or previewActive then return end
	local now = GetTime()
	local owner
	if not secret(interruptedBy) and interruptedBy ~= nil then
		obs.readable = obs.readable + 1
		owner = OwnerOfGUID(interruptedBy)
		if not owner then return end
	else
		obs.secret = obs.secret + 1
	end
	-- the same interrupt, seen through another unit token: same frame
	if now - lastEventAt < 0.02 then return end
	-- the same member cannot kick twice inside half a second
	if owner and now - lastObservedAt < 0.5 and lastObservedUnit == owner then return end
	lastEventAt = now
	local mark
	if cfg.showMark and GetRaidTargetIndex then
		local ok, idx = pcall(GetRaidTargetIndex, unit)
		if ok then mark = idx end
	end
	-- Taken in both icon modes, so switching modes mid-pull also repaints the
	-- bars already running. Secret in a key; see WHAT THE ICON BOX SHOWS.
	local icon
	if cfg.showIcon and C_Spell and C_Spell.GetSpellTexture then
		local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
		if ok then icon = tex end
	end
	if cfg.meterConfirm then
		pendings[#pendings + 1] = { at = now, owner = owner, mark = mark, icon = icon }
		Pair(now)
	else
		Charge(now, owner, mark, nil, icon)
	end
end

local lastMeterAt = -10

-- The meter event fires for every meter type that changed - 258 a second in a
-- +20 on 2026-09-28 - and only the Interrupts one is wanted, so the enum is
-- read once and every other type is one comparison away from returning.
local METER_INTERRUPTS = _G.Enum and _G.Enum.DamageMeterType and _G.Enum.DamageMeterType.Interrupts

local function OnMeterUpdate(dmType)
	if not METER_INTERRUPTS or secret(dmType) or dmType ~= METER_INTERRUPTS then return end
	local now = GetTime()
	-- the overall and the current session each report the same change
	if now - lastMeterAt < 0.05 then return end
	lastMeterAt = now
	obs.meter = obs.meter + 1
	local owner, cands, via = MeterKicker()
	lastMeterOwner, lastMeterVia = owner, via
	meterHits[#meterHits + 1] = { at = now, owner = owner, cands = cands }
	Pair(now)
end

-- One frame per group token. SyncEvents registers them only while the module
-- is on: with it off, OnCast fed nothing but the /xerionkick probe counters.
local castFrames = {}
for unit in pairs(CAST_OWNER) do
	local f = CreateFrame('Frame')
	f.unit = unit
	f:SetScript('OnEvent', function(_, _, _, _, spellID) OnCast(unit, spellID) end)
	castFrames[#castFrames + 1] = f
end

local evt = CreateFrame('Frame')
evt:RegisterEvent('PLAYER_ENTERING_WORLD')
evt:RegisterEvent('GROUP_ROSTER_UPDATE')
evt:RegisterEvent('PLAYER_SPECIALIZATION_CHANGED')
evt:RegisterEvent('INSPECT_READY')
evt:RegisterEvent('SPELLS_CHANGED')
evt:RegisterUnitEvent('UNIT_NAME_UPDATE', 'party1', 'party2', 'party3', 'party4')
evt:RegisterUnitEvent('UNIT_PET', 'player')
evt:RegisterEvent('DAMAGE_METER_RESET')

-- The interrupt events fire for every unit token, the meter event on every
-- meter change and the cooldown event on every cast, and all of them do
-- nothing while the module is off (the default), so they are only listened to
-- while it is on. The meter event feeds nothing but the meter confirmation
-- (meterHits only pair with pendings, which exist only with it on), so it also
-- waits for that switch; the settings window re-applies when it flips. The
-- meter snapshot is dropped when listening starts, so the first diff is not
-- made against a list from before the gap.
local LIVE_EVENTS = { 'SPELL_UPDATE_COOLDOWN', 'UNIT_SPELLCAST_INTERRUPTED',
	'UNIT_SPELLCAST_CHANNEL_STOP' }
local METER_EVENT = 'DAMAGE_METER_COMBAT_SESSION_UPDATED'
local listening, listeningMeter
local function SyncEvents()
	local cfg = GetCfg()
	local on = cfg.enable and true or false
	local meter = on and cfg.meterConfirm and true or false
	if meter ~= listeningMeter then
		listeningMeter = meter
		if meter then
			wipe(meterSnap)
			evt:RegisterEvent(METER_EVENT)
		else
			evt:UnregisterEvent(METER_EVENT)
		end
	end
	if on == listening then return end
	listening = on
	for _, e in ipairs(LIVE_EVENTS) do
		if on then evt:RegisterEvent(e) else evt:UnregisterEvent(e) end
	end
	for _, f in ipairs(castFrames) do
		if on then f:RegisterUnitEvent('UNIT_SPELLCAST_SUCCEEDED', f.unit)
		else f:UnregisterEvent('UNIT_SPELLCAST_SUCCEEDED') end
	end
end
ns.IKApply = function()
	Apply()
	SyncEvents()
end

-- SPELL_UPDATE_COOLDOWN fires several times per cast and RefreshSelf reads a
-- fresh cooldown table each time, so a burst shares one read on the next
-- frame (the cast path already defers its own RefreshSelf by a frame).
local QueueSelf = ns.Coalesce(function() RefreshSelf() end)

evt:SetScript('OnEvent', function(_, event, arg1, arg2, arg3, arg4)
	if event == 'DAMAGE_METER_COMBAT_SESSION_UPDATED' then
		OnMeterUpdate(arg1)
	elseif event == 'DAMAGE_METER_RESET' then
		wipe(meterSnap)
	elseif event == 'UNIT_SPELLCAST_INTERRUPTED' then
		OnEnemyInterrupted(arg1, arg3, arg4)
	elseif event == 'UNIT_SPELLCAST_CHANNEL_STOP' then
		if secret(arg4) or arg4 ~= nil then OnEnemyInterrupted(arg1, arg3, arg4) end
	elseif event == 'PLAYER_ENTERING_WORLD' then
		Apply()
		SyncEvents()
	elseif event == 'INSPECT_READY' then
		OnInspectReady(arg1)
	elseif event == 'SPELL_UPDATE_COOLDOWN' then
		if GetCfg().enable then QueueSelf() end
	elseif event == 'PLAYER_SPECIALIZATION_CHANGED' then
		if type(arg1) == 'string' and not secret(arg1) and arg1 ~= 'player' then
			local m = members[arg1]
			if m and m.guid then specByGUID[m.guid] = nil end
		end
		if GetCfg().enable then ScheduleRebuild() end
	else
		if GetCfg().enable then ScheduleRebuild() end
	end
end)

_G.SLASH_XERIONKICK1 = '/xerionkick'
_G.SlashCmdList.XERIONKICK = function()
	local cfg = GetCfg()
	local restr = _G.C_Secrets and _G.C_Secrets.HasSecretRestrictions and _G.C_Secrets.HasSecretRestrictions()
	ns.Msg(sformat('Interrupts: %s, %s, preview %s, secret restrictions %s',
		cfg.enable and 'enabled' or 'disabled',
		IsInGroup() and (IsInRaid() and 'in a raid' or 'in a party') or 'solo',
		previewActive and 'on' or 'off',
		tostring(restr)))
	local now = GetTime()
	for _, unit in ipairs(UNITS) do
		local m = members[unit]
		if m then
			local row = rows[unit]
			local state = 'ready'
			if row and row.cdStart then state = sformat('%.1fs left', row.cdStart + row.cdDur - now) end
			local cdText
			if unit == 'player' then
				local poll = row and (row.poll or row.spell)
				local secs, from = OwnCd(poll)
				local info = poll and C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(poll)
				local live
				if not info then live = 'no cooldown info'
				elseif secret(info.startTime) or secret(info.duration) then live = 'numbers hidden now'
				else live = sformat('numbers readable now (duration %s)', tostring(info.duration)) end
				cdText = sformat('own: real read when allowed, else %gs (%s); %s', secs, from, live)
			elseif row then cdText = sformat('%gs', MemberCd(row))
			else cdText = '-' end
			ns.Msg(sformat('  %s: %s %s role=%s spec=%s kick=%s uses %s, %s%s',
				unit, tostring(m.name), tostring(m.class), tostring(m.role), tostring(m.spec),
				tostring(m.spell), cdText,
				m.spell and state or 'no interrupt',
				WantsSpec(m) and ' (spec pending)' or ''))
		end
	end
	ns.Msg(sformat('  casts ended early %d (%d named the kicker, %d secret, %d never confirmed), meter interrupts %d, confirmed %d: %d named by the meter, %d guessed, %d yours, %d unmatched%s',
		obs.total, obs.readable, obs.secret, obs.unconfirmed, obs.meter, obs.confirmed, obs.named, obs.guessed, obs.mine, obs.unmatched,
		cfg.meterConfirm and '' or ' (meter confirmation off)'))
	ns.Msg(sformat('  waiting: %d cast-ended events, %d meter hits', #pendings, #meterHits))
	do
		local store = LearnedStore()
		local poll = rows.player and (rows.player.poll or rows.player.spell)
		if store and poll then
			ns.Msg(sformat('  own kick %d: measured %s, table %s', poll, tostring(store[poll]), tostring(OwnHealerCd(poll) or (KICKS[poll] and KICKS[poll].cd))))
		end
	end
	ns.Msg(sformat('  last meter hit: %s', lastMeterOwner and sformat('%s via the %s list', lastMeterOwner, tostring(lastMeterVia)) or 'kicker not readable from the lists'))
	for _, name in ipairs(SESSIONS) do
		local list = lastMeterLists[name]
		if list then
			local parts = {}
			for i, e in ipairs(list) do
				local units = {}
				MatchMember(e, units)
				local names = {}
				for unit in pairs(units) do names[#names + 1] = unit end
				table.sort(names)
				parts[#parts + 1] = sformat('%d. %s%s -> %s', i, e.key, e.name and '' or ' (name hidden)', #names > 0 and table.concat(names, '/') or '?')
			end
			ns.Msg(sformat('  %s interrupt list: %s', name, #parts > 0 and table.concat(parts, '; ') or 'empty'))
		else
			ns.Msg(sformat('  %s interrupt list: not read yet', name))
		end
	end
	local any = false
	for unit, p in pairs(probe) do
		any = true
		ns.Msg(sformat('  casts from %s: %d readable, %d secret%s', unit, p.plain, p.secret,
			p.last and sformat(', last readable spell %d', p.last) or ''))
	end
	if not any then ns.Msg('  no cast events received yet') end
end
