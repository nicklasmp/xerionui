-- WHY THIS FILE EXISTS
--
-- The CC Tracker. These bars answer what the group asks during a pull - how
-- long the pack is still stunned - the way a nameplate WeakAura did before
-- 12.0: a bar per crowd control, coloured and named per spell, draining with
-- the seconds left. Inside a key an enemy's debuffs are secret, so this file
-- cannot read the spell, the seconds or which mob; the engine draws all of it.
--
-- WHAT IT DOES
--
-- A stack of bars anywhere on screen: the spell's own colour and short name,
-- the seconds left ("4.2"), the spell's icon beside the bar, and a sound the
-- moment one lands. Anyone's cast counts. Two ways to stack them:
--
-- * One bar per spell (mode 'group', the default): one Leg Sweep on ten mobs
--   is ONE bar. Every spell has a line of its own and every enemy's copy of
--   it is drawn on that line, one over the other.
-- * One bar per spell per enemy (mode 'each'): ten bars, one per mob, closed
--   up with no gaps.
--
-- THE SPELL IS SETTLED BEFORE THE AURA EXISTS
--
-- The colour, the name and the line belong to the spell, and Lua never
-- learns which spell a bar is showing. So every enemy's aura container gets
-- one engine display PER LISTED SPELL, filtered to that spell's IDs: a button
-- built for it can only ever show that spell, so its initializer paints that
-- spell's colour, name and icon itself, and the engine binds only the fill
-- and the seconds (SetDurationBar, SetDurationText). Spell-ID filters are
-- honoured for harmful auras on units you cannot assist
-- (AuraContainerUtil.CanApplyIdentityCandidateFilters), which is exactly an
-- enemy's debuff.
--
-- ONE BAR PER SPELL: AURA SLOTS
--
-- In 'group' mode each spell is an aura SLOT (AddAuraSlot): one button, shown
-- while the enemy carries the spell, placed wherever we put it. Every enemy's
-- slot for a spell is pinned to that spell's line, so all of them overlap and
-- read as one bar; the containers are layered so a later enemy draws over an
-- earlier one. What the overlap costs: when two mobs carry the same spell
-- with different time left, the bar on top is one of them, not the longer
-- one, and the other's fill shows dimmed past its end. A slot is one frame,
-- so this mode is cheap.
--
-- A line cannot close up when its spell is down: that would take "does ANY
-- enemy carry it", and anchors only add, they cannot take a maximum. So the
-- lines are fixed, in list order, and a line whose spell is down is an empty
-- gap. To keep the gaps few, a spell whose class is not in your group gets no
-- line at all (classRows): nobody can cast it. Class tokens of group members
-- are readable in a key; a spell added by ID has no known class and always
-- keeps its line.
--
-- Nor does a spell without a line get a slot. The engine tests every slot of
-- a container against every aura its enemy gains or refreshes
-- (AuraContainerAuraSlotManagerMixin:AddAura / UpdateAura), so a slot nobody
-- can fill is work on every aura event of a pull, times every enemy. A class
-- that joins later gets its slots from the builder; a spell that loses its
-- line keeps the slot it has, hidden.
--
-- ONE BAR PER ENEMY: AURA GROUPS AND THE CLOSING CHAIN
--
-- In 'each' mode each spell is an aura GROUP allowed one frame, and an
-- anchor trick keeps the stack closed: a
-- container lays its groups out in one column (flow axis Vertical) and sizes
-- itself to it, one element of bar height + gap per shown bar plus one pixel
-- of padding at the far end - an enemy with nothing up is one pixel tall
-- (AnchorUtil.ApplyFlowLayout never reports less). The containers are
-- chained, each off the far edge of the one before pulled back that pixel, so
-- an idle enemy adds nothing. The price is frames: a group allocates its
-- batch of ten engine buttons up front (CustomAuraContainerConstants.
-- FrameCreationBatchSize) and takes a few milliseconds to build.
--
-- Every container is made with DisableUntrustedLayoutScriptsTemplate, the
-- aspect a frame needs to hang off a container that has a group
-- (CustomAuraContainerSharedMixin:AddAuraGroup). With it on all of them from
-- the start, any container may hang off any other whatever it holds, and the
-- builder still gives the chain its groups last to first as the engine's own
-- order would want.
--
-- THE BUILDER
--
-- Containers, groups and slots are built in the background, one step per
-- frame, up to the cap as soon as the bars are switched on - never as a burst
-- in the middle of a pull - and only for the mode in use. A plate only gets a
-- place once its container is finished.
--
-- A finished container can still lack a slot: a spell that got its line
-- after the container was built. Those are added the same way, except while
-- the client restricts addons (a fight, a key, an encounter, a match): a
-- finished container may be watching an enemy right then, and one refused
-- slot stops the builder until /reload. They wait for the restriction to
-- lift, and the chain itself keeps growing meanwhile as it always did.
--
-- WHY SETTINGS ONLY TOUCH OUR OWN PIECES
--
-- After its initializer returns, the engine locks a button against addon code
-- for as long as auras are secret (DenyTaintedAccessWhenAurasAreSecret) - in
-- combat and for the whole of a key. That covers a SetPoint that merely names
-- the button as the relative frame, not only a SetSize on it. So nothing is
-- ever resized or anchored against a button after its initializer: the bar,
-- the icon and the text hang off a frame of ours pinned over the button once,
-- at creation, with sizes of their own, and a slot button is pinned to the
-- holder in its initializer and left there. Settings reach those pieces and
-- the group layouts; whatever the client refuses anyway is tried again when
-- the fight ends, and when the key does (a key keeps auras secret out of
-- combat).
--
-- THE SOUND
--
-- Lua never learns that a bar appeared, so the sound is the engine's own:
-- C_UnitAuras.AddAuraSound, registered per spell ID on every enemy nameplate
-- token (or on your target), plays the file when the aura is added - the
-- same door Kira Reminders' trash sounds use. The registrations are refused
-- during a boss encounter and in combat inside a key (BigWigs' Sound plugin
-- reads the same two restrictions), so they are made outside those and kept.
-- It is per enemy: one Chaos Nova on eight mobs starts eight copies at once.
-- There is no way to fold them into one on 12.1.0: the registration has no
-- "once" option, UNIT_AURA is secret while auras are restricted, the filter
-- check (IsAuraFilteredOutByInstanceID) needs aura access, and a frame of ours
-- under an engine button can neither run OnShow (UntrustedScriptExecution
-- propagates to children) nor report IsShown (secret Shown aspect). The
-- 12.1.5 PTR adds a throttle argument to AddAuraSound (NSRT passes it when
-- the interface is 120105 or later); whether it spans registrations on
-- different units is unknown until it can be tried.
-- Until then the copies play on the Sound effects channel by default, not
-- Master: they still stack, but under the slider players keep lowest. With
-- sound effects switched off in the game's settings it is silent, which is
-- what the channel setting is for. Under it the settings page carries the
-- game's own volume for that channel (ns.CCBGetVolume / ns.CCBSetVolume), the
-- only volume a sound played this way has.
--
-- WHAT IT CANNOT DO
--
-- * Sort by time left, warn when a CC is about to break, or say which mob a
--   bar belongs to. Anything that needs the answer in Lua is out of reach.
-- * Watch an enemy without a nameplate, or more enemies than the cap. Every
--   enemy plate on screen takes a place, controlled or not: which ones are
--   controlled is the secret. Bosses are the one exception (see Verdict).
-- * Time a crowd control whose debuff carries no duration. The bar is the
--   aura's own duration and nothing else.

local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('CCBars', hooksecurefunc, C_Timer)
local _G = _G

local CreateFrame = CreateFrame
local UIParent = UIParent
local C_Timer = C_Timer
local UnitExists = UnitExists
local UnitCanAttack = UnitCanAttack
local UnitCanAssist = UnitCanAssist
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsBossMob = UnitIsBossMob
local UnitName = UnitName
local UnitClass = UnitClass
local IsInRaid = IsInRaid
local InCombatLockdown = InCombatLockdown
local ipairs, pairs, pcall, type, tostring, tonumber = ipairs, pairs, pcall, type, tostring, tonumber
local tremove, tconcat, wipe, format = table.remove, table.concat, wipe, string.format
local mfloor, mceil, mmin, mmax = math.floor, math.ceil, math.min, math.max

local secret = ns.IsSecret
local Ask = ns.Ask

local AnchorUtil = _G.AnchorUtil
local AXIS = AnchorUtil and AnchorUtil.FlowLayoutAxis
local DIR = AnchorUtil and AnchorUtil.FlowDirection

ns.hasCCBars = true
ns.CCBUnavailable = not (ns.IS_121 and AXIS and DIR and ns.HasTemplate('CustomAuraContainerTemplate'))

-- nameplate1..40 is every enemy token the client has.
local MAX_SLOTS = 40
-- The preview draws at most this many bars.
local MAX_SAMPLES = 12
local GROUP_KEY, SLOT_KEY = 'ccb', 'ccbs'
-- Per container, frame levels apart, so one enemy's pieces never interleave
-- with the next one's and a later enemy's bar draws over an earlier one's.
local LEVEL_STEP = 12

-- The sound that ships with the addon, under the name the settings show:
-- green like every other Kira sound the XerionUI installer registers.
local SOUND_NAME = '|cFF00FF00XerionUI - Stun|r'
local SOUND_PATH = 'Interface\\AddOns\\XerionUI-Plugin\\Media\\Sounds\\cc_bar.mp3'

local DEFAULTS = {
	enable = false,
	lock = false,
	x = 0,
	y = 60,
	-- 'group': one bar per spell, all enemies share it. 'each': one per enemy.
	mode = 'group',
	-- 'group' mode: no line for a spell whose class is not in the group.
	classRows = true,
	-- The whole bar, icon included.
	width = 220,
	height = 20,
	spacing = 2,
	grow = 'DOWN',
	icon = 'RIGHT',
	-- A LibSharedMedia statusbar name; empty is the addon's usual bar.
	texture = '',
	bgAlpha = 0.6,
	-- An outline round the bar and its icon, inside the bar's own size.
	border = true,
	borderSize = 1,
	borderColor = { 0, 0, 0, 1 },
	showName = true,
	showTimer = true,
	timerSide = 'LEFT',
	tenths = true,
	nameSize = 12,
	timerSize = 12,
	-- Moves the name up or down on the bar; positive is up.
	nameY = 0,
	-- Every enemy plate on screen takes a place, controlled or not.
	maxUnits = 15,
	sound = SOUND_NAME,
	-- 'ALL': every enemy nameplate. 'TARGET': your target only.
	soundFrom = 'ALL',
	-- The game volume slider the sound plays under. 'SFX' because one stun on
	-- a pack is a copy per enemy, and eight copies on Master are too loud.
	soundChannel = 'SFX',
	-- The DEBUFF's ID, which for some spells is not the ID of the button that
	-- casts it: Binding Shot's stun is 117526 (117405 is the tether), Deep
	-- Breath's stun is 372245, Capacitor Totem's is Static Charge 118905.
	spells = {
		372048, -- Oppressing Roar
		204490, -- Sigil of Silence
		119381, -- Leg Sweep
		117526, -- Binding Shot
		255941, -- Wake of Ashes
		372245, -- Deep Breath
		179057, -- Chaos Nova
		279303, -- Frostwyrm's Fury
		118905, -- Capacitor Totem: Static Charge
		204490, -- Sigil of Silence
		30283,  -- Shadowfury
	},
	-- The player's own colour and name per spell ID. A spell without one takes
	-- the built-in pair below, or grey and the game's spell name.
	colors = {},
	labels = {},
}

-- Short names, colours and the caster's class for the default list, the
-- colours read off the WeakAura these bars replace. IDs are from memory, not
-- from 12.x data: one that is wrong simply never matches anything.
local BUILTIN = {
	[372048] = { 'Roar',          0.09, 0.75, 0.83, 'EVOKER' },
	[204490] = { 'Silence',       0.09, 0.75, 0.83, 'DEMONHUNTER' },
	[119381] = { 'Leg Sweep',     0.00, 0.80, 0.52, 'MONK' },
	[117526] = { 'Binding Shot',  0.50, 0.33, 0.55, 'HUNTER' },
	[30283]  = { 'Shadowfury',    0.47, 0.31, 0.70, 'WARLOCK' },
	[255941] = { 'Wake of Ashes', 0.70, 0.56, 0.20, 'PALADIN' },
	[372245] = { 'Breath',        0.70, 0.49, 0.29, 'EVOKER' },
	[179057] = { 'Nova',          0.53, 0.15, 0.66, 'DEMONHUNTER' },
	[118905] = { 'Cap Totem',     0.22, 0.24, 0.83, 'SHAMAN' },
	[279303] = { 'Frostwyrm',     0.45, 0.72, 0.95, 'DEATHKNIGHT' },
}

-- Other IDs one list entry stands for. Empty for now; kept so an entry can
-- cover a spell whose debuff comes in several IDs without cluttering the list.
local VARIANTS = {}

local function Migrate(cfg)
	if cfg.mode ~= 'each' then cfg.mode = 'group' end
	if cfg.grow ~= 'UP' then cfg.grow = 'DOWN' end
	if cfg.icon ~= 'LEFT' and cfg.icon ~= 'NONE' then cfg.icon = 'RIGHT' end
	if cfg.timerSide ~= 'RIGHT' then cfg.timerSide = 'LEFT' end
	if cfg.soundFrom ~= 'TARGET' then cfg.soundFrom = 'ALL' end
	local ch = cfg.soundChannel
	if ch ~= 'Master' and ch ~= 'Dialog' and ch ~= 'Ambience' and ch ~= 'Music' then
		cfg.soundChannel = 'SFX'
	end
	-- The first build had one text size for both.
	if type(cfg.textSize) == 'number' then
		cfg.nameSize, cfg.timerSize, cfg.textSize = cfg.textSize, cfg.textSize, nil
	end
	-- The bundled sound's earlier names.
	local s = cfg.sound
	if s == 'XerionUI CC' or s == 'Kira - Stun' or s == '|cFF00FF00Kira - Stun|r' then cfg.sound = SOUND_NAME end
	-- The name used to move sideways; it moves up and down now.
	cfg.nameX = nil
	if type(cfg.colors) ~= 'table' then cfg.colors = {} end
	if type(cfg.labels) ~= 'table' then cfg.labels = {} end
	if type(cfg.spells) ~= 'table' then cfg.spells = ns.CopyValue(DEFAULTS.spells) end
	-- An imported profile is where a string or a duplicate comes from. Cleaned
	-- in place so the settings page and this file keep looking at one table.
	local list, seen = cfg.spells, {}
	for i = #list, 1, -1 do
		local id = tonumber(list[i])
		id = id and mfloor(id)
		if not id or id <= 0 or seen[id] then
			tremove(list, i)
		else
			seen[id] = true
			list[i] = id
		end
	end
	-- The standalone CC Cast Notices module cannot read secret cast spell IDs
	-- on Midnight. Keep these debuffs in the secret-safe AuraContainer tracker,
	-- which can identify them through candidate filters without exposing IDs to Lua.
	local restored = { 118905, 204490, 30283 }
	for _, id in ipairs(restored) do
		if not seen[id] then
			list[#list + 1] = id
			seen[id] = true
		end
	end
end

local function GetCfg() return ns.ModuleCfg('ccBars', DEFAULTS, Migrate) end
ns.CCBGetCfg = GetCfg

local function SpellColor(cfg, id)
	local c = cfg.colors[id]
	if type(c) == 'table' then return c[1] or 1, c[2] or 1, c[3] or 1 end
	local b = BUILTIN[id]
	if b then return b[2], b[3], b[4] end
	return 0.6, 0.6, 0.6
end

local function SpellLabel(cfg, id)
	local l = cfg.labels[id]
	if type(l) == 'string' and l ~= '' then return l end
	local b = BUILTIN[id]
	if b then return b[1] end
	return ns.CdSpellName(id)
end

local function IncludeSet(id)
	local set = { [id] = true }
	local extra = VARIANTS[id]
	if extra then
		for _, v in ipairs(extra) do set[v] = true end
	end
	return set
end

-- The sound file for a setting: the one that ships with the addon, or a
-- LibSharedMedia name, or nil for "None".
local function SoundFile(name)
	if name == SOUND_NAME then return SOUND_PATH end
	return ns.SoundPath(name)
end

-- Listed with LibSharedMedia too, when some addon brought it, so the addon's
-- sound pickers and other addons can offer it.
local function RegisterSound()
	local lib = ns.LSM()
	if lib and lib.Register then pcall(lib.Register, lib, 'sound', SOUND_NAME, SOUND_PATH) end
end
RegisterSound()

ns.CCBDefaultSpells = function() return ns.CopyValue(DEFAULTS.spells) end
ns.CCBColor = function(id) return SpellColor(GetCfg(), id) end
ns.CCBLabel = function(id) return SpellLabel(GetCfg(), id) end
ns.CCBSoundName = SOUND_NAME
ns.CCBPlaySound = function(name)
	local path = SoundFile(name)
	if path then _G.PlaySoundFile(path, GetCfg().soundChannel or 'SFX') end
end

-- The game's own volume setting behind each channel the sound can play on.
-- The settings page shows the one for the chosen channel as a slider, so the
-- sound can be made louder or quieter without opening the game's Audio
-- settings. It is the game's value, not ours: every sound on that channel
-- follows it, and no XerionUI profile carries it.
local VOLUME_CVAR = {
	SFX = 'Sound_SFXVolume', Master = 'Sound_MasterVolume', Dialog = 'Sound_DialogVolume',
	Ambience = 'Sound_AmbienceVolume', Music = 'Sound_MusicVolume',
}
local volumePreview

-- 0-100 like the game's slider, or nil when the client does not answer.
ns.CCBGetVolume = function()
	local get = (_G.C_CVar and _G.C_CVar.GetCVar) or _G.GetCVar
	if not get then return nil end
	local ok, v = pcall(get, VOLUME_CVAR[GetCfg().soundChannel] or VOLUME_CVAR.SFX)
	if not ok or secret(v) then return nil end
	v = tonumber(v)
	return v and mfloor(v * 100 + 0.5)
end

-- The chosen sound plays once the slider has been still for a moment, so the
-- new level can be heard without a copy for every step of a drag.
ns.CCBSetVolume = function(pct)
	local set = (_G.C_CVar and _G.C_CVar.SetCVar) or _G.SetCVar
	pct = tonumber(pct)
	if not (set and pct) then return end
	pcall(set, VOLUME_CVAR[GetCfg().soundChannel] or VOLUME_CVAR.SFX, tostring(mmax(0, mmin(100, pct)) / 100))
	if volumePreview then volumePreview:Cancel() end
	volumePreview = C_Timer.NewTimer(0.35, function()
		volumePreview = nil
		ns.CCBPlaySound(GetCfg().sound)
	end)
end

local function Width(cfg) return mmax(40, cfg.width or 220) end
local function Height(cfg) return mmax(6, cfg.height or 20) end
local function Gap(cfg) return mmax(0, cfg.spacing or 2) end
local function BorderSize(cfg)
	if cfg.border == false then return 0 end
	return mmax(1, mmin(4, mfloor(cfg.borderSize or 1)))
end
local function Up(cfg) return cfg.grow == 'UP' end
local function Each(cfg) return cfg.mode == 'each' end
-- The corner everything hangs by: the chain grows away from it, a container's
-- column starts at it, and the pieces of a bar are pinned to it.
local function Corner(cfg) return Up(cfg) and 'BOTTOMLEFT' or 'TOPLEFT' end
local function Cap(cfg) return mmax(1, mmin(MAX_SLOTS, mfloor(cfg.maxUnits or 15))) end
local function Wanted(cfg) return cfg.enable and not ns.CCBUnavailable and #cfg.spells > 0 end

local function Texture(cfg)
	local name = cfg.texture
	if type(name) == 'string' and name ~= '' then
		local lib = ns.LSM()
		if lib and lib.Fetch then
			local ok, path = pcall(lib.Fetch, lib, 'statusbar', name, true)
			if ok and path then return path end
		end
	end
	return ns.BarTexture()
end

-- "4.2": tenths, rounded up so a bar never reads 0.0 while it still runs.
-- Built once; nil on a client without the rule formatter, and then the
-- seconds are whole like every other timer in the addon.
local tenthsFmt
local function TenthsFormatter()
	if tenthsFmt == nil then
		tenthsFmt = false
		local CSU = _G.C_StringUtil
		if CSU and CSU.CreateNumericRuleFormatter then
			local ok, f = pcall(CSU.CreateNumericRuleFormatter)
			if ok and f and f.SetBreakpoints then
				local E = _G.Enum
				local up = (E and E.NumericRuleFormatRounding and E.NumericRuleFormatRounding.Up) or 1
				if pcall(f.SetBreakpoints, f, {
					{ threshold = 0, step = 0.1, rounding = up, format = '%.1f' },
				}) then
					tenthsFmt = f
				end
			end
		end
	end
	return tenthsFmt or nil
end

local function TimerOptions(cfg)
	if cfg.tenths ~= false then
		local f = TenthsFormatter()
		if f then return { textFormatter = f } end
	end
	return ns.DurationTextOptions()
end

-- The fill drains as the seconds go.
local BAR_OPTIONS = {}
do
	local E = _G.Enum
	if E and E.StatusBarInterpolation then BAR_OPTIONS.interpolation = E.StatusBarInterpolation.Immediate end
	if E and E.StatusBarTimerDirection then BAR_OPTIONS.direction = E.StatusBarTimerDirection.RemainingTime end
end

-- ---------------------------------------------------------------------------
-- Who is in the group, for the 'group' mode's lines
-- ---------------------------------------------------------------------------

local PARTY, RAID = { 'player' }, {}
for i = 1, 4 do PARTY[i + 1] = 'party' .. i end
for i = 1, 40 do RAID[i] = 'raid' .. i end

-- The class tokens in the group, or nil when any member's class could not be
-- read - and an unreadable answer means "allow": every spell keeps its line.
local function GroupClasses()
	local out = {}
	for _, u in ipairs(IsInRaid() and RAID or PARTY) do
		if Ask(UnitExists, u) == true then
			local ok, _, token = pcall(UnitClass, u)
			if not ok or secret(token) or type(token) ~= 'string' then return nil end
			out[token] = true
		end
	end
	return out
end

-- [spellID] = its line (1 = nearest the holder) in 'group' mode, for every
-- listed spell that gets one.
local rowOf = {}

local function ComputeRows(cfg)
	wipe(rowOf)
	local rowCount = 0
	local classes = cfg.classRows ~= false and GroupClasses() or nil
	for _, id in ipairs(cfg.spells) do
		local b = BUILTIN[id]
		if not (classes and b and b[5] and not classes[b[5]]) then
			rowCount = rowCount + 1
			rowOf[id] = rowCount
		end
	end
end

-- The lines as a string, in list order, and the one the bars were last laid
-- out for (Restyle): a roster change that leaves it alone needs no Apply.
local rowsSig
local function RowsSignature(cfg)
	ComputeRows(cfg)
	local parts = {}
	for i, id in ipairs(cfg.spells) do parts[i] = rowOf[id] or 0 end
	return table.concat(parts, ',')
end

-- ---------------------------------------------------------------------------
-- The bars
-- ---------------------------------------------------------------------------

-- The pieces of one bar on `parent`: the dark back, the outline, the fill, the
-- icon beside it, the name on the fill and a layer above it for the seconds.
-- The same pieces make the preview and the live bars on the engine's buttons.
local function MakeBar(parent)
	local p = {}
	-- Everything hangs off this frame of ours, pinned over the parent once,
	-- here. On an engine button a SetPoint that names the BUTTON as the
	-- relative frame is refused for as long as auras are secret - a whole key
	-- (EllesmereUI_AuraKit guards its text anchors for it); one that names our
	-- own frame is not, so the pieces can be moved later.
	p.root = CreateFrame('Frame', nil, parent)
	p.root:SetAllPoints(parent)
	p.bg = p.root:CreateTexture(nil, 'BACKGROUND')
	-- The outline is five strips - the four sides and the line between the fill
	-- and the icon - rather than one plate under everything, which would show
	-- through the see-through back and make it solid.
	p.edges = {}
	for i = 1, 5 do p.edges[i] = p.root:CreateTexture(nil, 'BORDER') end
	p.icon = p.root:CreateTexture(nil, 'ARTWORK')
	p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	p.bar = CreateFrame('StatusBar', nil, p.root)
	p.name = p.bar:CreateFontString(nil, 'OVERLAY')
	p.name:SetWordWrap(false)
	-- Its own layer, because the engine owns the seconds' alpha (a secret
	-- aspect) and "hide the seconds" has to dim something that is ours.
	p.timerHost = CreateFrame('Frame', nil, p.root)
	p.timerHost:SetFrameLevel(p.bar:GetFrameLevel() + 5)
	p.timer = p.timerHost:CreateFontString(nil, 'OVERLAY')
	p.timer:SetWordWrap(false)
	-- A font straight away: SetText on an unfonted fontstring is a hard error,
	-- and the engine writes the seconds on its own even if styling failed.
	p.timer:SetFont(_G.STANDARD_TEXT_FONT, 12, 'OUTLINE')
	p.name:SetFont(_G.STANDARD_TEXT_FONT, 12, 'OUTLINE')
	return p
end

-- Everything pinned to one point of the root with its own size, so the
-- parent's size never matters (see WHY SETTINGS ONLY TOUCH OUR OWN PIECES):
-- the bar's `corner` goes to the root's `rel` point, `dy` along. Anchors name
-- only our own frames and are set again only when they change - stamped after
-- the calls, so a refused one is tried again next time.
local function StyleBar(p, cfg, id, rel, dy)
	local corner = Corner(cfg)
	local w, h = Width(cfg), Height(cfg)
	local side = cfg.icon
	-- The outline takes `s` pixels inside the bar's own size - at both ends,
	-- along both edges and between the fill and the icon - so the stack keeps
	-- its spacing and its layout whatever the outline is.
	local s = BorderSize(cfg)
	local inH = mmax(1, h - 2 * s)
	local iconW = (side == 'NONE') and 0 or inH
	local barW = mmax(1, w - 2 * s - ((side == 'NONE') and 0 or (inH + s)))
	local barX = (side == 'LEFT') and (2 * s + iconW) or s
	local iconX = (side == 'LEFT') and s or (2 * s + barW)
	local divX = (side == 'LEFT') and (s + iconW) or (s + barW)
	-- Toward the far edge: down from a top corner, up from a bottom one.
	local dir = (corner == 'BOTTOMLEFT') and 1 or -1
	local inY = dy + dir * s
	local r, g, b = SpellColor(cfg, id)
	local font = ns.GothamNarrowBlackFont()
	local nameSize, timerSize = cfg.nameSize or 12, cfg.timerSize or 12
	local nameY = cfg.nameY or 0
	local tSide = (cfg.timerSide == 'RIGHT') and 'RIGHT' or 'LEFT'
	local nSide = (tSide == 'LEFT') and 'RIGHT' or 'LEFT'
	local inset = (tSide == 'LEFT') and 4 or -4
	-- The name keeps clear of the seconds: room for "00.0" on their side.
	local reserve = (cfg.showTimer ~= false) and mceil(timerSize * 2.4) + 6 or 0

	local key = corner .. '|' .. rel .. '|' .. dy .. '|' .. w .. '|' .. h .. '|' .. s .. '|'
		.. barX .. '|' .. iconX .. '|' .. tSide .. '|' .. reserve .. '|' .. nameY
	if p.anchored ~= key then
		local root = p.root
		p.bg:ClearAllPoints()
		p.bg:SetPoint(corner, root, rel, barX, inY)
		p.icon:ClearAllPoints()
		p.icon:SetPoint(corner, root, rel, iconX, inY)
		p.bar:ClearAllPoints()
		p.bar:SetPoint(corner, root, rel, barX, inY)
		p.timerHost:ClearAllPoints()
		p.timerHost:SetPoint(corner, root, rel, barX, inY)
		-- Near side, far side, left, right, the divider.
		local e = p.edges
		for i = 1, 5 do e[i]:ClearAllPoints() end
		e[1]:SetPoint(corner, root, rel, 0, dy)
		e[2]:SetPoint(corner, root, rel, 0, dy + dir * (h - s))
		e[3]:SetPoint(corner, root, rel, 0, inY)
		e[4]:SetPoint(corner, root, rel, w - s, inY)
		e[5]:SetPoint(corner, root, rel, divX, inY)
		p.timer:ClearAllPoints()
		p.timer:SetPoint(tSide, p.timerHost, tSide, inset, 0)
		p.name:ClearAllPoints()
		p.name:SetPoint(nSide, p.bar, nSide, -inset, nameY)
		p.name:SetPoint(tSide, p.bar, tSide,
			(tSide == 'LEFT') and (4 + reserve) or -(4 + reserve), nameY)
		p.anchored = key
	end

	p.bg:SetSize(barW, inH)
	p.bg:SetColorTexture(0, 0, 0, cfg.bgAlpha or 0.6)

	local bc = cfg.borderColor
	if type(bc) ~= 'table' then bc = DEFAULTS.borderColor end
	local edgeW = mmax(1, s)
	for i = 1, 5 do
		local t = p.edges[i]
		if i <= 2 then t:SetSize(w, edgeW) else t:SetSize(edgeW, inH) end
		t:SetColorTexture(bc[1] or 0, bc[2] or 0, bc[3] or 0, bc[4] or 1)
		t:SetShown(s > 0 and (i < 5 or side ~= 'NONE'))
	end

	p.icon:SetSize(iconW, iconW)
	p.icon:SetTexture(ns.CdSpellTexture(id))
	p.icon:SetShown(side ~= 'NONE')

	p.bar:SetSize(barW, inH)
	p.bar:SetStatusBarTexture(Texture(cfg))
	p.bar:SetStatusBarColor(r, g, b)

	p.timerHost:SetSize(barW, inH)
	p.timerHost:SetAlpha(cfg.showTimer ~= false and 1 or 0)

	p.timer:SetFont(font, timerSize, 'OUTLINE')
	p.name:SetFont(font, nameSize, 'OUTLINE')
	p.timer:SetJustifyH(tSide)
	p.name:SetJustifyH(nSide)
	p.name:SetText(SpellLabel(cfg, id))
	p.name:SetShown(cfg.showName ~= false)
end

-- Everything StyleBar reads that every bar shares, as one string: the
-- settings as StyleBar resolves them, and the font and bar texture paths
-- themselves, which a media addon loading late can change under the same
-- setting. Restyle adds each spell's colour, name and icon to it, and a bar
-- whose string, spell and place are the ones it was last styled with is left
-- alone. Anything StyleBar comes to read must be added here or in Restyle's
-- per-spell part, or a change to it will not reach bars already styled.
local function StyleShared(cfg)
	local bc = cfg.borderColor
	if type(bc) ~= 'table' then bc = DEFAULTS.borderColor end
	return tconcat({
		Corner(cfg), Width(cfg), Height(cfg), BorderSize(cfg), tostring(cfg.icon),
		tostring(cfg.bgAlpha), tostring(bc[1]), tostring(bc[2]), tostring(bc[3]), tostring(bc[4]),
		tostring(ns.GothamNarrowBlackFont()), tostring(Texture(cfg)),
		tostring(cfg.nameSize), tostring(cfg.timerSize), tostring(cfg.nameY), tostring(cfg.timerSide),
		tostring(cfg.showTimer ~= false), tostring(cfg.showName ~= false),
	}, '\031')
end

-- A slot button is pinned to the holder's top left corner (see InitSlot), so
-- its bar's line is an offset from there: line 1 is the holder itself.
local function SlotPlace(cfg, row)
	local step = (Height(cfg) + Gap(cfg)) * ((row or 1) - 1)
	if Up(cfg) then return 'TOPLEFT', step - Height(cfg) end
	return 'TOPLEFT', -step
end

-- ---------------------------------------------------------------------------
-- The frame, the preview and the engine's part
-- ---------------------------------------------------------------------------

local holder
local samples = {}
-- The finished containers in slot order: the unit in slot 3 is watched by
-- chain[3].
local chain = {}
-- [container] = { [spellID] = true } for every group / slot it was given.
local groupsOf, slotsOf = {}, {}
-- The container being built; it hangs nowhere until it is finished.
local building
-- Our part of every engine button: { frame, p, id, slot = true|nil }.
local buttons = {}
-- [spellID] = its place in the list, for the list as it is now.
local listIndex = {}
local listSig
local failed, textFailed, barFailed
local linkedAs, timerAs
local preview = false
local stylePending = false
-- The builder's last pass found finished containers lacking slots and left
-- them for the end of the restriction (see THE BUILDER).
local slotsWaiting = false
local QueueScan

local function ApplyPosition()
	if not holder then return end
	local cfg = GetCfg()
	holder:ClearAllPoints()
	holder:SetPoint('CENTER', UIParent, 'CENTER', cfg.x or 0, cfg.y or 60)
end

local function EnsureFrame()
	if holder then return end
	-- Named, because edit mode looks the frame up by this exact string. The
	-- holder is the first bar's place; the stack grows away from it.
	holder = CreateFrame('Frame', 'XerionUICCBars', UIParent)
	holder:SetFrameStrata('MEDIUM')
	holder:SetSize(220, 20)
	holder:SetClampedToScreen(true)
	holder:SetMovable(true)
	holder:EnableMouse(false)
	holder:RegisterForDrag('RightButton')
	holder:Hide()
	ns.MakeDraggable(holder, GetCfg, 'x', 'y', ApplyPosition)
	ApplyPosition()
end

-- The preview: one bar per listed spell (up to MAX_SAMPLES), drawn by Lua,
-- since the engine only draws while a real debuff is up.
local SAMPLE_LEFT = { 5.8, 4.3, 3.1, 2.6, 5.2, 1.9, 4.8, 3.6, 2.2, 1.4, 3.9, 2.9 }

local function StyleSamples(cfg)
	local list = cfg.spells
	local corner = Corner(cfg)
	local step = (Height(cfg) + Gap(cfg)) * (Up(cfg) and 1 or -1)
	for i = 1, MAX_SAMPLES do
		local s = samples[i]
		local id = list[i]
		if id then
			if not s then
				local f = CreateFrame('Frame', nil, holder)
				f:SetSize(1, 1)
				f:SetFrameLevel(holder:GetFrameLevel() + 20)
				f:Hide()
				s = { frame = f, p = MakeBar(f) }
				s.p.bar:SetMinMaxValues(0, 1)
				samples[i] = s
			end
			s.frame:ClearAllPoints()
			s.frame:SetPoint(corner, holder, corner, 0, (i - 1) * step)
			StyleBar(s.p, cfg, id, corner, 0)
			local left = SAMPLE_LEFT[i]
			s.p.bar:SetValue(left / 6)
			s.p.timer:SetText(cfg.tenths ~= false and format('%.1f', left) or tostring(mceil(left)))
			s.used = true
		elseif s then
			s.used = false
		end
	end
end

-- One element per bar, in the container's own column: the bar and the gap
-- after it. The layout's element size is what the engine lays out, not the
-- button's own (CustomAuraContainerFlowLayoutMixin:GetElementSize), and
-- layoutIndex keeps one mob's bars in list order.
local function Layout(cfg, index)
	return {
		elementWidth = Width(cfg), elementHeight = Height(cfg) + Gap(cfg),
		elementSpacing = 0, lineSpacing = 0, layoutIndex = index or 0,
	}
end

-- One column growing away from the corner the chain hangs by, with the one
-- pixel an empty container is at the far end (padding is left, right, top,
-- bottom).
local function Flow(c, cfg)
	local up = Up(cfg)
	c:SetFlowLayoutAxis(AXIS.Vertical)
	c:SetFlowLayoutAnchorPoint(Corner(cfg))
	c:SetFlowLayoutGrowthDirection(DIR.Right, up and DIR.Up or DIR.Down)
	c:SetFlowLayoutPadding(0, 0, up and 1 or 0, up and 0 or 1)
end

-- Whether a slot's bar is drawn: slots are 'group' mode's, and a spell off
-- the list or without a line keeps its slot hidden rather than removed.
local function SlotShown(cfg, id)
	return not Each(cfg) and listIndex[id] ~= nil and rowOf[id] ~= nil
end

-- The engine bindings and the rest of one button, shared by groups and slots.
-- Runs inside the engine's frame creation: an error here would take the
-- group or slot down with it, so everything optional is armoured.
local function Dress(b, id, rel, dy, isSlot)
	local cfg = GetCfg()
	-- Display only. A Button takes the mouse by default and would swallow
	-- clicks on the play field for as long as the debuff is up.
	pcall(b.SetMouseClickEnabled, b, false)
	pcall(b.SetMouseMotionEnabled, b, false)
	-- Nothing hangs off this size; the pieces carry their own.
	pcall(b.SetSize, b, 1, 1)
	local p = MakeBar(b)
	pcall(StyleBar, p, cfg, id, rel, dy)
	local okB, errB = pcall(b.SetDurationBar, b, p.bar, BAR_OPTIONS)
	if not okB then barFailed = tostring(errB) end
	local okT, errT = pcall(b.SetDurationText, b, p.timer, TimerOptions(cfg))
	if not okT then textFailed = tostring(errT) end
	local rec = { frame = b, p = p, id = id, slot = isSlot }
	buttons[#buttons + 1] = rec
	return rec
end

local function InitGroupButton(id, b)
	local corner = Corner(GetCfg())
	Dress(b, id, corner, 0, nil)
end

-- A slot button takes no part in the engine's layout, so it is placed here,
-- once, while it is still ours to place: on the holder's top left corner,
-- where every enemy's slot for a spell lands on the same line.
local function InitSlot(id, b)
	pcall(b.SetPoint, b, 'TOPLEFT', holder, 'TOPLEFT', 0, 0)
	local cfg = GetCfg()
	local rel, dy = SlotPlace(cfg, rowOf[id])
	local rec = Dress(b, id, rel, dy, true)
	rec.p.root:SetShown(SlotShown(cfg, id))
end

local function NewContainer(cfg)
	-- The layout-script aspect from birth, so any container may hang off any
	-- other, groups or not (see ONE BAR PER ENEMY).
	local ok, c = pcall(CreateFrame, 'AuraContainer', nil, holder,
		'CustomAuraContainerTemplate,' .. ns.TAIL_TEMPLATE)
	if not ok or not c then
		ok, c = pcall(CreateFrame, 'AuraContainer', nil, holder, 'CustomAuraContainerTemplate')
	end
	if not ok or not c then
		failed = 'the client refused the AuraContainer frame'
		return nil
	end
	c:SetSize(1, 1)
	c:SetFrameLevel(holder:GetFrameLevel() + 1 + LEVEL_STEP * (#chain + 1))
	local okF, errF = pcall(Flow, c, cfg)
	if not okF then
		failed = 'column layout refused: ' .. tostring(errF)
		c:Hide()
		return nil
	end
	pcall(c.SetEnabled, c, false)
	groupsOf[c], slotsOf[c] = {}, {}
	return c
end

local function AddGroup(c, id, index, cfg)
	local ok, err = pcall(c.AddAuraGroup, c, GROUP_KEY .. id, 'HARMFUL', {
		maxFrameCount = 1,
		candidateFilters = { includeSpellIDs = IncludeSet(id) },
		initializeFrame = function(b) InitGroupButton(id, b) end,
		layout = Layout(cfg, index),
	})
	if not ok then
		failed = tostring(err)
		return
	end
	groupsOf[c][id] = true
end

local function AddSlot(c, id)
	local ok, err = pcall(c.AddAuraSlot, c, SLOT_KEY .. id, 'HARMFUL', {
		candidateFilters = { includeSpellIDs = IncludeSet(id) },
		initializeFrame = function(b) InitSlot(id, b) end,
	})
	if not ok then
		failed = tostring(err)
		return
	end
	slotsOf[c][id] = true
end

-- The first listed spell this container has nothing for yet, in the mode in
-- use: a group in 'each' mode, a slot in 'group' mode - and there only for a
-- spell with a line (see ONE BAR PER SPELL).
local function NextMissing(c, cfg)
	local each = Each(cfg)
	local have = each and groupsOf[c] or slotsOf[c]
	for index, id in ipairs(cfg.spells) do
		if not have[id] and (each or rowOf[id]) then return id, index end
	end
end

-- One step of building on `c`: one group (they are heavy), or every missing
-- slot at once (a slot is a single frame).
local function BuildOn(c, cfg)
	local id, index = NextMissing(c, cfg)
	if not id then return false end
	if Each(cfg) then
		AddGroup(c, id, index, cfg)
	else
		while id and not failed do
			AddSlot(c, id)
			id = NextMissing(c, cfg)
		end
	end
	return true
end

-- Where a container hangs: the first one on the holder, every other one off
-- the far edge of the one before it, pulled back the one pixel an empty
-- container is long. In 'group' mode every container is one pixel, so the
-- chain folds onto the holder and only the slots, pinned to it, matter.
local function Link(c, prev, cfg)
	c:ClearAllPoints()
	if Up(cfg) then
		if prev then
			c:SetPoint('BOTTOMLEFT', prev, 'TOPLEFT', 0, -1)
		else
			c:SetPoint('BOTTOMLEFT', holder, 'BOTTOMLEFT', 0, 0)
		end
	elseif prev then
		c:SetPoint('TOPLEFT', prev, 'BOTTOMLEFT', 0, 1)
	else
		c:SetPoint('TOPLEFT', holder, 'TOPLEFT', 0, 0)
	end
end

-- Whether the client restricts addons right now: a fight, a key, a boss
-- encounter or a PvP match. Asked of the client rather than tried, like the
-- sounds, so a refusal never happens. Each of these ends with
-- PLAYER_REGEN_ENABLED or ADDON_RESTRICTION_STATE_CHANGED, the two events that
-- wake the builder again.
local HOLD_TYPES = { 'Combat', 'Encounter', 'ChallengeMode', 'PvPMatch' }
local function Restricted()
	if InCombatLockdown() then return true end
	local R = _G.C_RestrictedActions
	local T = _G.Enum and _G.Enum.AddOnRestrictionType
	if not (R and R.IsAddOnRestrictionActive and T) then return false end
	for _, name in ipairs(HOLD_TYPES) do
		local t = T[name]
		if t ~= nil then
			local ok, v = pcall(R.IsAddOnRestrictionActive, t)
			if ok and v == true then return true end
		end
	end
	return false
end

-- The background builder: one step per frame while there is work. Spells
-- added to the list, or a switch of mode, come first, for the containers
-- already in use - last to first, so a container never gets its first group
-- before the one hanging off it has one; then the chain grows to the cap.
-- In 'group' mode a finished container's missing slots wait while Restricted
-- (see THE BUILDER); the container being built is not in use yet and is
-- finished as before.
local builder = CreateFrame('Frame')
builder:Hide()
builder:SetScript('OnUpdate', function(self)
	local cfg = GetCfg()
	if failed or not Wanted(cfg) or not holder then
		self:Hide()
		return
	end
	local each, hold = Each(cfg), nil
	slotsWaiting = false
	for i = #chain, 1, -1 do
		local c = chain[i]
		if each then
			if BuildOn(c, cfg) then return end
		elseif NextMissing(c, cfg) then
			-- Asked once a pass, and only when there is a slot to add.
			if hold == nil then hold = Restricted() end
			if not hold then
				BuildOn(c, cfg)
				return
			end
			slotsWaiting = true
		end
	end
	if #chain >= Cap(cfg) then
		self:Hide()
		return
	end
	if not building then
		building = NewContainer(cfg)
		return
	end
	if BuildOn(building, cfg) then return end
	local c = building
	building = nil
	local ok, err = pcall(Link, c, chain[#chain], cfg)
	if not ok then
		failed = tostring(err)
		c:Hide()
		return
	end
	chain[#chain + 1] = c
	QueueScan()
end)

-- A new list or a new mode: each group takes its one frame back only while
-- its spell is listed and the mode is 'each'. Slots are shown and hidden by
-- Restyle. Missing groups and slots are the builder's job.
local function DeclareList(cfg)
	wipe(listIndex)
	for index, id in ipairs(cfg.spells) do listIndex[id] = index end
	local sig = cfg.mode .. ':' .. tconcat(cfg.spells, ',')
	if sig == listSig then return end
	listSig = sig
	local each = Each(cfg)
	for c, have in pairs(groupsOf) do
		for id in pairs(have) do
			pcall(c.SetAuraGroupMaxFrameCount, c, GROUP_KEY .. id, (each and listIndex[id]) and 1 or 0)
		end
	end
end

-- Settings changes. Our pieces on the engine's buttons, the groups' layouts
-- and the containers' columns; should the client refuse any of it, the change
-- waits for the fight or the key to end.
local function Restyle(cfg)
	stylePending = false
	rowsSig = RowsSignature(cfg)
	local corner = Corner(cfg)
	-- Apply runs after every loading screen, on roster changes and on every
	-- slider step, and most of those change nothing a bar is made of: a bar
	-- is styled again only when its key (StyleShared plus its spell's own
	-- colour, name and icon, built once per spell here) or its place differs
	-- from the ones it was last styled with. The stamp is written only when
	-- StyleBar went through, so a bar the client refused is tried again.
	local shared, keys = StyleShared(cfg), {}
	for _, rec in ipairs(buttons) do
		local id = rec.id
		local rel, dy = corner, 0
		if rec.slot then rel, dy = SlotPlace(cfg, rowOf[id]) end
		local key = keys[id]
		if not key then
			local r, g, b = SpellColor(cfg, id)
			key = tconcat({ shared, id, tostring(r), tostring(g), tostring(b),
				tostring(SpellLabel(cfg, id)), tostring(ns.CdSpellTexture(id)) }, '\031')
			keys[id] = key
		end
		if rec.styled ~= key or rec.styledRel ~= rel or rec.styledDy ~= dy then
			if pcall(StyleBar, rec.p, cfg, id, rel, dy) then
				rec.styled, rec.styledRel, rec.styledDy = key, rel, dy
			else
				rec.styled = nil
				stylePending = true
			end
		end
		if rec.slot and not pcall(rec.p.root.SetShown, rec.p.root, SlotShown(cfg, id)) then
			stylePending = true
		end
	end
	-- The seconds' format is the engine's binding: set again only when it
	-- changed, and that is a call on the button itself.
	local tAs = cfg.tenths ~= false
	if timerAs ~= tAs then
		local ok = true
		for _, rec in ipairs(buttons) do
			if not pcall(rec.frame.SetDurationText, rec.frame, rec.p.timer, TimerOptions(cfg)) then ok = false end
		end
		if ok then timerAs = tAs else stylePending = true end
	end
	for c, have in pairs(groupsOf) do
		for id in pairs(have) do
			if not pcall(c.SetAuraGroupLayout, c, GROUP_KEY .. id, Layout(cfg, listIndex[id])) then
				stylePending = true
			end
		end
	end
	-- Columns turned and the chain re-hung only when the direction changed: a
	-- container whose points were cleared and then refused stays loose until
	-- the retry.
	if linkedAs ~= cfg.grow then
		local ok = true
		for c in pairs(groupsOf) do
			if not pcall(Flow, c, cfg) then ok = false end
		end
		for i, c in ipairs(chain) do
			if not pcall(Link, c, chain[i - 1], cfg) then ok = false end
		end
		if ok then linkedAs = cfg.grow else stylePending = true end
	end
end

-- ---------------------------------------------------------------------------
-- The sound
-- ---------------------------------------------------------------------------

local soundReg = {}
local soundPending = false
local soundRefused

local function SoundAPI()
	local api = _G.C_UnitAuras
	if not (api and api.AddAuraSound and api.RemoveAuraSound) then return nil end
	if not (_G.Enum and _G.Enum.UnitAuraSoundTrigger) then return nil end
	return api
end

-- The registration is refused during a boss encounter, and in combat inside a
-- key; asked of the client rather than tried, so a refusal never happens.
local function SoundBlocked()
	local R = _G.C_RestrictedActions
	local T = _G.Enum and _G.Enum.AddOnRestrictionType
	if not (R and R.IsAddOnRestrictionActive and T) then return InCombatLockdown() end
	local function on(t)
		local ok, v = pcall(R.IsAddOnRestrictionActive, t)
		return ok and v == true
	end
	return on(T.Encounter) or (on(T.Combat) and on(T.ChallengeMode))
end

local SOUND_TOKENS = { TARGET = { 'target' }, ALL = {} }
for i = 1, MAX_SLOTS do SOUND_TOKENS.ALL[i] = 'nameplate' .. i end

-- What should be registered: token and spell ID for every listed spell and
-- its variants, all with the same file on the same channel. In 'group' mode
-- only for a spell with a line: a class nobody in the group plays cannot put
-- its debuff on anything, and each spell is forty registrations the engine
-- checks. The lines come from Restyle, which Apply runs before the queued
-- sync lands, so a class joining brings its sounds with its bars; one leaving
-- takes them away (removing is never restricted).
local function SoundWanted(cfg)
	local out = {}
	if not Wanted(cfg) then return out end
	local path = SoundFile(cfg.sound)
	if not path then return out end
	local channel = cfg.soundChannel or 'SFX'
	local each = Each(cfg)
	for _, id in ipairs(cfg.spells) do
		if each or rowOf[id] then
			for sid in pairs(IncludeSet(id)) do
				for _, token in ipairs(SOUND_TOKENS[cfg.soundFrom] or SOUND_TOKENS.ALL) do
					out[token .. ':' .. sid] = { token = token, id = sid, path = path, channel = channel }
				end
			end
		end
	end
	return out
end

local function SyncSounds()
	local api = SoundAPI()
	if not api then return end
	local want = SoundWanted(GetCfg())
	for key, live in pairs(soundReg) do
		local w = want[key]
		if not w or w.path ~= live.path or w.channel ~= live.channel then
			pcall(api.RemoveAuraSound, live.id)
			soundReg[key] = nil
		end
	end
	soundPending = false
	if SoundBlocked() then
		for key in pairs(want) do
			if not soundReg[key] then soundPending = true break end
		end
		return
	end
	local added = _G.Enum.UnitAuraSoundTrigger.Added
	for key, w in pairs(want) do
		if not soundReg[key] then
			local ok, sid = pcall(api.AddAuraSound, added, {
				unitToken = w.token, spellID = w.id,
				soundFileName = w.path, outputChannel = w.channel,
			})
			if ok and sid then
				soundReg[key] = { id = sid, path = w.path, channel = w.channel }
			else
				soundRefused = ok and 'no ID returned' or tostring(sid)
				soundPending = true
				return
			end
		end
	end
end

-- The restriction state reads false while its own change event is being
-- handed out, so every sync runs on the next frame.
local QueueSounds = ns.Coalesce(SyncSounds)

-- ---------------------------------------------------------------------------
-- Which enemies get a place
-- ---------------------------------------------------------------------------

local PLATES, IS_PLATE = {}, {}
for i = 1, MAX_SLOTS do
	PLATES[i] = 'nameplate' .. i
	IS_PLATE[PLATES[i]] = true
end

local unitOf, slotOf = {}, {}
local tracking = false

-- Why a plate gets no place, or nil when it does. An unreadable answer lets
-- the unit through (the addon's rule), except for "can I assist it": on a unit
-- you can assist the spell filter is skipped by the engine and EVERY debuff
-- would get a bar, so only a plain "no" lets that one through.
--
-- A boss gets no place either: bosses are immune to crowd control and carry
-- the busiest aura lists in the fight, so a container on one only costs.
-- UnitIsBossMob is the boss flag the target frame's gold dragon reads, set on
-- dungeon bosses too (their classification is only 'elite'), and it belongs
-- to the mob, so it is right from the moment the plate appears with no need
-- to wait for boss1-5. The docs give its answer no secret condition; should
-- it come back unreadable anyway, the plate keeps its place as before.
local function Verdict(unit)
	if Ask(UnitExists, unit) ~= true then return 'no such unit' end
	if Ask(UnitCanAttack, 'player', unit) == false then return 'not attackable' end
	if Ask(UnitCanAssist, 'player', unit) ~= false then return 'friendly, or the client would not say' end
	if Ask(UnitIsDeadOrGhost, unit) == true then return 'dead' end
	if Ask(UnitIsBossMob, unit) == true then return 'boss (immune to crowd control)' end
	return nil
end

local function Release(slot)
	local unit = unitOf[slot]
	if not unit then return end
	unitOf[slot] = nil
	slotOf[unit] = nil
	local c = chain[slot]
	if c then pcall(c.SetEnabled, c, false) end
end

local function Take(slot, unit)
	local c = chain[slot]
	if not c then return end
	unitOf[slot] = unit
	slotOf[unit] = slot
	-- Unit before enable: enabling registers the unit's aura events, and the
	-- switch from off to on is also what makes the container read the unit
	-- afresh - a nameplate token is a slot, and SetUnit with the string it
	-- already holds is a no-op.
	pcall(c.SetUnit, c, unit)
	pcall(c.SetEnabled, c, true)
end

local function ReleaseAll()
	for slot = 1, MAX_SLOTS do Release(slot) end
end

-- Only finished containers take a unit; the builder asks again for every one
-- it finishes.
local function Rescan()
	if not tracking then return end
	local cap = mmin(Cap(GetCfg()), #chain)
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

-- A pull is a burst of plate events; one scan on the next frame answers all
-- of them.
QueueScan = ns.Coalesce(Rescan)

-- UNIT_FLAGS names one plate, and every stun, combat flip or death on it fires
-- one: only that plate can have won or lost a place, so only it is asked
-- again (next frame, like the scan) instead of all forty. A plate that lets go
-- frees a slot another plate may be waiting for, and that still takes the
-- full scan; so do plates coming and going, the builder and the settings.
local flagged = {}
local function RecheckFlagged()
	if not tracking then wipe(flagged) return end
	local cap = mmin(Cap(GetCfg()), #chain)
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
end
local QueueFlagged = ns.Coalesce(RecheckFlagged)

local watch = CreateFrame('Frame')
watch:SetScript('OnEvent', function(_, event, unit)
	if event == 'NAME_PLATE_UNIT_REMOVED' then
		-- Let go at once, not on the next frame: the token can be handed to a
		-- different mob within this one, and the scan would then find "the same
		-- unit" still placed and leave its container reading the old one.
		local slot = unit and slotOf[unit]
		if slot then Release(slot) end
	elseif event == 'UNIT_FLAGS' then
		if not IS_PLATE[unit] then return end
		flagged[unit] = true
		QueueFlagged()
		return
	end
	QueueScan()
end)

local function StartTracking()
	if tracking then return end
	tracking = true
	watch:RegisterEvent('NAME_PLATE_UNIT_ADDED')
	watch:RegisterEvent('NAME_PLATE_UNIT_REMOVED')
	watch:RegisterEvent('UNIT_FLAGS')
end

local function StopTracking()
	if not tracking then return end
	tracking = false
	watch:UnregisterAllEvents()
	ReleaseAll()
end

-- ---------------------------------------------------------------------------
-- Apply, and the options-side entry points
-- ---------------------------------------------------------------------------

local evt = CreateFrame('Frame')

local function UpdateVisibility()
	if not holder then return end
	local cfg = GetCfg()
	local live = Wanted(cfg) and not preview
	for _, s in ipairs(samples) do s.frame:SetShown(preview and s.used or false) end
	holder:SetSize(Width(cfg), Height(cfg))
	-- Shown while live even though it draws nothing itself: a container only
	-- works while it is visible (ShouldRegisterForDynamicEvents).
	holder:SetShown(preview or live)
	holder:EnableMouse(preview and not cfg.lock or false)
	if live then
		StartTracking()
		Rescan()
	else
		StopTracking()
	end
end

local EVENTS = { 'PLAYER_REGEN_ENABLED', 'GROUP_ROSTER_UPDATE', 'ADDON_RESTRICTION_STATE_CHANGED' }

local function Apply()
	local cfg = GetCfg()
	local wanted = Wanted(cfg)
	for _, e in ipairs(EVENTS) do
		if wanted then pcall(evt.RegisterEvent, evt, e) else pcall(evt.UnregisterEvent, evt, e) end
	end
	RegisterSound()
	QueueSounds()
	if not (wanted or preview) then
		StopTracking()
		builder:Hide()
		if holder then holder:Hide() end
		return
	end

	EnsureFrame()
	ApplyPosition()
	StyleSamples(cfg)
	if wanted then
		DeclareList(cfg)
		Restyle(cfg)
		builder:Show()
	end
	UpdateVisibility()
end

-- A dragged slider asks many times a frame; one Apply answers all of them.
ns.CCBApply = ns.Coalesce(Apply)

ns.CCBIsPreview = function() return preview end
ns.CCBSetPreview = function(state)
	preview = state and true or false
	Apply()
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

-- Who is in the group decides which spells have a line. The lines are our own
-- anchors, so this works in a fight too. Most roster events (someone going
-- offline, a role swap, the ones the client repeats) leave the lines as they
-- were, and those skip the whole Apply. The signature walks up to 40 units, and
-- a raid forming fires the event many times a frame: one look on the next
-- frame answers all of them.
local RosterChanged = ns.Coalesce(function()
	local cfg = GetCfg()
	if not Each(cfg) and holder and RowsSignature(cfg) ~= rowsSig then ns.CCBApply() end
end)

evt:RegisterEvent('PLAYER_ENTERING_WORLD')
-- A key whose last fight ended before the timer stopped lifts its restriction
-- with no PLAYER_REGEN_ENABLED after it, so a refused restyle also retries on
-- the restriction's own change event - on the next frame, because the state
-- still reads the old value while that event is handed out (LustPots).
local QueueRestyle = ns.Coalesce(function()
	if stylePending and not preview and holder then Restyle(GetCfg()) end
end)

-- Slots the builder left for the end of the restriction (see THE BUILDER),
-- asked for on the next frame for the same reason. Still restricted then
-- means the builder leaves them again and waits for the next change.
local QueueBuild = ns.Coalesce(function()
	if slotsWaiting then builder:Show() end
end)

evt:SetScript('OnEvent', function(_, event)
	if event == 'PLAYER_ENTERING_WORLD' then
		-- A loading screen hands out every nameplate token afresh, and leaving
		-- a key is when the engine's buttons are ours to touch again; Apply
		-- rescans, restyles and retries the sounds.
		C_Timer.After(0.5, ns.CCBApply)
	elseif event == 'GROUP_ROSTER_UPDATE' then
		RosterChanged()
	elseif event == 'ADDON_RESTRICTION_STATE_CHANGED' then
		if stylePending then QueueRestyle() end
		if soundPending then QueueSounds() end
		if slotsWaiting then QueueBuild() end
	else
		-- PLAYER_REGEN_ENABLED: out of a fight outside a key, the buttons take
		-- changes again, and the sounds and held slots may be added.
		if stylePending and not preview and holder then Restyle(GetCfg()) end
		if soundPending then QueueSounds() end
		if slotsWaiting then QueueBuild() end
	end
end)

-- ---------------------------------------------------------------------------
-- Diagnostics
--
-- Whether a mob is controlled is the one thing that cannot be printed - that
-- is the secret. Everything around it can: the list, the lines, how far the
-- builder got, which plates got a place and why the others did not, and the
-- sounds. A bar that never shows with all of this looking right is a wrong
-- spell ID: it has to be the debuff's, not the cast's.
-- ---------------------------------------------------------------------------

_G.SLASH_XERIONCCBARS1 = '/xerionccbars'
_G.SlashCmdList.XERIONCCBARS = function()
	local function p(...) print('|cffff7d0aXerionUI-CCBars|r', ...) end
	local cfg = GetCfg()
	p('enable =', cfg.enable and 'on' or 'off', '| preview =', preview and 'ON' or 'off',
		'| mode =', Each(cfg) and 'one bar per enemy' or 'one bar per spell',
		'| aura containers =', ns.CCBUnavailable and '|cffff5555unavailable|r' or 'ok',
		'| tracking =', tracking and 'yes' or 'no')
	ComputeRows(cfg)
	local names = {}
	for _, id in ipairs(cfg.spells) do
		local line = (not Each(cfg)) and (rowOf[id] and (' line ' .. rowOf[id]) or ' |cff888888no line|r') or ''
		names[#names + 1] = SpellLabel(cfg, id) .. ' ' .. id .. line
	end
	p('list (' .. #cfg.spells .. '):', #names > 0 and tconcat(names, ', ') or '|cff888888empty|r')
	local groups, slots = 0, 0
	for _, have in pairs(groupsOf) do
		for _ in pairs(have) do groups = groups + 1 end
	end
	for _, have in pairs(slotsOf) do
		for _ in pairs(have) do slots = slots + 1 end
	end
	-- 'group' mode gives each finished container a slot per spell WITH a line,
	-- not per listed spell: `lined` should reach lines x containers. Fewer is
	-- the builder still at work or waiting for the restriction to lift; the
	-- rest of `slots` is spells that lost their line since (hidden) and the
	-- container being built.
	local lines, lined = 0, 0
	for _ in pairs(rowOf) do lines = lines + 1 end
	for _, c in ipairs(chain) do
		for id in pairs(slotsOf[c]) do
			if rowOf[id] then lined = lined + 1 end
		end
	end
	p('containers =', #chain, 'of cap', Cap(cfg), '| building =', building and 'yes' or 'no',
		'| builder =', builder:IsShown() and 'running' or 'idle', '| groups =', groups,
		'| slots =', slots, Each(cfg) and '' or ('(lined ' .. lined .. ' of ' .. lines * #chain
			.. ': ' .. lines .. ' lines x ' .. #chain .. ' containers)'), '| engine buttons =', #buttons,
		stylePending and '|cffff5555(restyle waits for the fight or the key to end)|r' or '',
		slotsWaiting and '|cffff8800(new lines\' slots wait for the fight or the key to end)|r' or '')

	local placed = {}
	for slot = 1, MAX_SLOTS do
		local unit = unitOf[slot]
		if unit then
			local ok, name = pcall(UnitName, unit)
			local label = (ok and type(name) == 'string' and not secret(name)) and (unit .. ' (' .. name .. ')') or unit
			placed[#placed + 1] = slot .. '=' .. label
		end
	end
	p('placed:', #placed > 0 and tconcat(placed, ', ') or '|cff888888none|r')

	local plates = 0
	for _, unit in ipairs(PLATES) do
		if Ask(UnitExists, unit) == true then
			plates = plates + 1
			if not slotOf[unit] then
				local why = Verdict(unit)
				if not why then
					why = (#chain < Cap(cfg) and #placed >= #chain) and 'its container is still being built'
						or (#placed >= Cap(cfg) and 'the cap is full') or 'waiting for the next scan'
				end
				p('  no place:', unit, '|cffff5555' .. why .. '|r')
			end
		end
	end
	p('nameplates up =', plates)

	local regs = 0
	for _ in pairs(soundReg) do regs = regs + 1 end
	p('sound =', tostring(cfg.sound), '| file =', tostring(SoundFile(cfg.sound) or 'none'),
		'| channel =', tostring(cfg.soundChannel), '| for =', cfg.soundFrom == 'TARGET' and 'target' or 'every nameplate',
		'| registered =', regs, soundPending and '|cffff8800(waiting: encounter or combat in a key)|r' or '',
		SoundAPI() and '' or '|cffff5555(no C_UnitAuras.AddAuraSound on this client)|r')
	if soundRefused then p('sound registration refused: ' .. soundRefused) end
	if failed then p('|cffff5555stopped: ' .. failed .. '|r') end
	if barFailed then p('|cffff5555bar binding refused: ' .. barFailed .. '|r') end
	if textFailed then p('seconds refused: ' .. textFailed .. ' (the bar still drains)') end
	p('the bars are |cff66dd66up to the engine|r - drawn while a listed debuff is up; whether one is up right now is the one thing this cannot print')
end
