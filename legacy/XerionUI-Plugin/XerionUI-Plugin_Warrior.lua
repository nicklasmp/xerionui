local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('Warrior', hooksecurefunc, C_Timer)
local _G = _G

-- Warrior features, one section each. Only one so far: the damage your Spell
-- Reflections sent back, as one line of text - the warrior twin of the Death
-- Knight page's Bloodbeast damage, built the same way.
--
-- WHAT IT DOES
-- Cast Spell Reflection, and once the numbers can be read the text says how
-- much damage the spells you reflected did: "Reflect: 845K", the label in the
-- warrior colour. It stays up for 10 s. Every reflection until then adds up,
-- so a pull with three reflects shows one number. Size, colours, layer and
-- position are the player's; right-drag moves it while previewing.
--
-- WHERE THE NUMBER COMES FROM
-- Blizzard's damage meter, read the way Bloodbeast reads it: your Overall
-- damage done, spell by spell, compared with the reading before the reflect.
-- The meter is secret in combat (SecretWhenInCombat), so a reflect cast in a
-- fight is counted when the fight ends - after every pull in a key.
--
-- WHICH LINES ARE REFLECTS
-- A reflected spell is credited to the warrior under the ENEMY's spell ID, the
-- way combat logs have always shown it (assumed for the meter too - untested).
-- Nothing on the line says "reflected", so a line counts by what it is not:
-- one of your own spells. Your own are
--   * anything in your spellbook (C_SpellBook.IsSpellKnownOrInSpellBook), and
--   * anything that did damage in a stretch with NO Spell Reflection cast - an
--     enemy spell cannot land in your damage done then. Learned after every
--     fight and kept per character (XerionUIChangesCharDB.reflect); it catches
--     what the spellbook misses: auto attack, Deep Wounds, the damage IDs of
--     Whirlwind or Ravager, trinkets, enchants.
-- Until one reflect-free fight has been learned, a line counts only when the
-- same spell also hit YOU at some point (your damage taken) - an enemy spell
-- for certain. Spell Reflection's own ID always counts, in case the meter files
-- reflects under it instead. A cast whose spell ID reads secret spoils its
-- stretch for learning: it may have been a reflect.
--
-- COST
-- Nothing listens unless the box is ticked on a warrior. One meter read after
-- each fight (your spell list, a few dozen rows) and one timer per reflect.

local CreateFrame = CreateFrame
local UIParent = UIParent
local GetTime = GetTime
local UnitGUID = UnitGUID
local InCombatLockdown = InCombatLockdown
local ipairs, pairs, pcall, type = ipairs, pairs, pcall, type
local tonumber, tostring, print = tonumber, tostring, print
local format, gsub = string.format, string.gsub
local mmax, mmin = math.max, math.min
local tsort = table.sort

ns.hasReflect = true

local secret = ns.IsSecret
local Round = ns.Round

-- Spell Reflection, and the PvP talent Mass Spell Reflection.
local REFLECT       = { [23920] = true, [213915] = true }
local LABEL         = 'Reflect:'
local SHOW_FOR      = 10
-- The buff lasts 5 s, and a spell reflected at its last moment still has to
-- fly back.
local SETTLE        = 7
local RETRY_GAP     = 0.5
local RETRY_MAX     = 12
local PREVIEW_VALUE = 845000

local DEFAULTS = {
	enable = true,
	lock = true,
	x = 0,
	y = -130,
	size = 22,
	strata = 'MEDIUM',
	labelColor = { 0.78, 0.61, 0.43, 1 },
	valueColor = { 1, 1, 1, 1 },
}

local function GetCfg() return ns.ModuleCfg('reflectDamage', DEFAULTS) end
ns.RFLGetCfg = GetCfg

local function IsWarrior() return ns.IsClass('WARRIOR') end

local UNITS = { { 1e9, 'B' }, { 1e6, 'M' }, { 1e3, 'K' } }

local function FormatShort(n)
	n = tonumber(n) or 0
	for i = 1, #UNITS do
		local div, suffix = UNITS[i][1], UNITS[i][2]
		if n >= div - div / 2000 then
			return gsub(format('%.1f', n / div), '%.0$', '') .. suffix
		end
	end
	return format('%d', Round(n))
end

local function Hex(c, fallback)
	if type(c) ~= 'table' then c = fallback end
	local function ch(v) return mmax(0, mmin(255, Round((tonumber(v) or 1) * 255))) end
	return format('%02x%02x%02x', ch(c[1]), ch(c[2]), ch(c[3]))
end

local function SpellName(id)
	local CS = _G.C_Spell
	local ok, name = pcall(CS and CS.GetSpellName, id)
	if ok and type(name) == 'string' and not secret(name) then return name end
	return '?'
end

-- XerionUIChangesCharDB.reflect = { own = { [spellID] = true }, learned = fights }
-- Per character, outside the profiles: it describes this warrior's spells and
-- gear, not a layout, so it must not travel in an export.
local function Store()
	local c = ns.GetCharDB and ns.GetCharDB()
	if not c then return nil end
	local st = c.reflect
	if type(st) ~= 'table' then st = {} c.reflect = st end
	if type(st.own) ~= 'table' then st.own = {} end
	st.learned = tonumber(st.learned) or 0
	return st
end

-- Your Overall damage done (or taken) as { [spellID] = amount }. nil while the
-- meter is secret or missing; an empty table when it simply has nothing.
local function ReadSpells(kind)
	local DM, E = _G.C_DamageMeter, _G.Enum
	if not (DM and DM.GetCombatSessionSourceFromType and E and E.DamageMeterSessionType and E.DamageMeterType) then
		return nil
	end
	local guid = UnitGUID('player')
	if not guid or secret(guid) then return nil end
	local ok, src = pcall(DM.GetCombatSessionSourceFromType,
		E.DamageMeterSessionType.Overall, E.DamageMeterType[kind], guid, nil)
	if not ok then return nil end
	local out = {}
	if src == nil then return out end
	if type(src) ~= 'table' then return nil end
	local spells = src.combatSpells
	if type(spells) ~= 'table' then return out end
	for i = 1, #spells do
		local sp = spells[i]
		if type(sp) == 'table' then
			local id, amt = sp.spellID, sp.totalAmount
			if secret(id) or secret(amt) then return nil end
			if type(id) == 'number' and type(amt) == 'number' then out[id] = (out[id] or 0) + amt end
		end
	end
	return out
end

local function Known(id)
	local SB = _G.C_SpellBook
	local fn = (SB and SB.IsSpellKnownOrInSpellBook) or _G.IsPlayerSpell
	if not fn then return false end
	local ok, v = pcall(fn, id)
	return ok and not secret(v) and v == true
end

-- Why a line is or is not counted, for Count and the /xerionreflect dump.
local function Verdict(id, st, taken)
	if REFLECT[id] then return true, 'Spell Reflection' end
	if Known(id) then return false, 'spellbook' end
	if st and st.own[id] then return false, 'learned' end
	if st and st.learned > 0 then return true, 'not yours' end
	if taken and taken[id] then return true, 'also hit you' end
	return false, 'still learning'
end

local function Count(was, now)
	local st = Store()
	local taken
	local total, lines = 0, {}
	for id, amt in pairs(now) do
		local d = amt - (was[id] or 0)
		-- The meter started over without saying so: all of it is new.
		if d < 0 then d = amt end
		if d > 0 then
			if taken == nil then
				taken = not (st and st.learned > 0) and ReadSpells('DamageTaken') or false
			end
			if Verdict(id, st, taken) then
				total = total + d
				lines[#lines + 1] = { id = id, amount = d }
			end
		end
	end
	tsort(lines, function(a, b) return a.amount > b.amount end)
	return total, lines
end

local function Learn(was, now)
	local st = Store()
	if not st then return end
	local any = false
	for id, amt in pairs(now) do
		if amt ~= (was[id] or 0) and not REFLECT[id] then
			st.own[id] = true
			any = true
		end
	end
	if any then st.learned = st.learned + 1 end
end

local frame, text
local preview = false
local live = false
local hideTimer, settleTimer
-- base: the meter at the last plain read, nil until one worked. pending: a
-- Spell Reflection was cast since then. dirty: a cast with a secret spell ID
-- was, so this stretch may not be learned from.
local base
local pending, dirty, needRead = false, false, false
local casts, castAt, retries = 0, 0, 0
local shownValue
local last

local function EnsureFrame()
	if frame then return end
	frame = CreateFrame('Frame', 'XerionUIReflect', UIParent)
	frame:SetSize(120, 30)
	frame:SetFrameStrata('MEDIUM')
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(false)
	frame:RegisterForDrag('RightButton')
	ns.MakeDraggable(frame, GetCfg, 'x', 'y', function() if ns.RFLApply then ns.RFLApply() end end)

	text = frame:CreateFontString(nil, 'OVERLAY')
	text:SetFontObject('GameFontNormalLarge')
	text:SetPoint('CENTER')
	text:SetJustifyH('CENTER')
	frame:Hide()
end

local function ApplySettings()
	EnsureFrame()
	local cfg = GetCfg()
	frame:ClearAllPoints()
	frame:SetPoint('CENTER', UIParent, 'CENTER', cfg.x or 0, cfg.y or DEFAULTS.y)
	frame:SetFrameStrata(cfg.strata or 'MEDIUM')
	local size = tonumber(cfg.size) or DEFAULTS.size
	if size < 6 then size = 6 end
	local ok, valid = pcall(text.SetFont, text, ns.GothamNarrowBlackFont(), size, 'OUTLINE')
	if not ok or valid == false then
		pcall(text.SetFont, text, _G.STANDARD_TEXT_FONT, size, 'OUTLINE')
	end
	text:SetShadowOffset(0, 0)
	text:SetShadowColor(0, 0, 0, 0)
end

local function Paint(value)
	local cfg = GetCfg()
	text:SetText(format('|cff%s%s|r |cff%s%s|r',
		Hex(cfg.labelColor, DEFAULTS.labelColor), LABEL,
		Hex(cfg.valueColor, DEFAULTS.valueColor), FormatShort(value)))
	local w, h = text:GetStringWidth(), text:GetStringHeight()
	if secret(w) then w = 0 end
	if secret(h) then h = 0 end
	frame:SetSize(mmax(40, (w or 0) + 8), mmax(16, (h or 0) + 4))
end

local function Hide()
	if hideTimer then hideTimer:Cancel() hideTimer = nil end
	shownValue = nil
	if frame then frame:Hide() end
end

local function Show(value)
	EnsureFrame()
	ApplySettings()
	shownValue = value
	Paint(value)
	frame:Show()
	if hideTimer then hideTimer:Cancel() end
	hideTimer = C_Timer.NewTimer(SHOW_FOR, function()
		hideTimer = nil
		if preview then return end
		Hide()
	end)
end

local Settle

local function Schedule(delay)
	if settleTimer then settleTimer:Cancel() end
	settleTimer = C_Timer.NewTimer(delay, Settle)
end

-- One reading of the meter against the last. After a reflect it counts the new
-- lines that are not yours; after a clean stretch it learns them as yours.
Settle = function()
	settleTimer = nil
	if pending then
		local left = castAt + SETTLE - GetTime()
		if left > 0 then Schedule(left) return end
	end
	local now = ReadSpells('DamageDone')
	if not now then
		needRead = true
		if not InCombatLockdown() and retries < RETRY_MAX then
			retries = retries + 1
			Schedule(RETRY_GAP)
		end
		return
	end
	needRead, retries = false, 0
	local was, hadReflect, wasDirty = base, pending, dirty
	base, pending, dirty, casts = now, false, false, 0
	-- No reading before the reflect (a /reload mid-pull): the whole session
	-- would count as new, so this one is dropped.
	if not was then return end
	if hadReflect then
		local total, lines = Count(was, now)
		last = { total = total, lines = lines }
		if total > 0 and not preview then Show(total) end
	elseif not wasDirty then
		Learn(was, now)
	end
end

local function Nudge()
	retries = 0
	Schedule(RETRY_GAP)
end

local function OnCast()
	pending = true
	casts = casts + 1
	castAt = GetTime()
	retries = 0
	Schedule(SETTLE)
end

local evt = CreateFrame('Frame')
local EVENTS = { 'PLAYER_ENTERING_WORLD', 'PLAYER_REGEN_ENABLED', 'DAMAGE_METER_RESET', 'ADDON_RESTRICTION_STATE_CHANGED' }

-- Whatever happened while nobody listened is no stretch to learn from, so
-- both ways start without a reading.
local function SetLive(on)
	on = on and true or false
	if on == live then return end
	live = on
	base, pending, dirty, casts = nil, false, false, 0
	if on then
		for _, e in ipairs(EVENTS) do pcall(evt.RegisterEvent, evt, e) end
		evt:RegisterUnitEvent('UNIT_SPELLCAST_SUCCEEDED', 'player')
		Nudge()
	else
		evt:UnregisterAllEvents()
		if settleTimer then settleTimer:Cancel() settleTimer = nil end
	end
end

local function Apply()
	local cfg = GetCfg()
	local on = cfg.enable and IsWarrior()
	SetLive(on)
	if not (on or preview) then
		Hide()
		return
	end
	ApplySettings()
	if preview then
		Paint(PREVIEW_VALUE)
		frame:Show()
	elseif shownValue then
		Paint(shownValue)
	end
end
ns.RFLApply = Apply

-- No class gate, so the text can be placed on any character.
ns.RFLIsPreview = function() return preview end
ns.RFLSetPreview = function(state)
	preview = state and true or false
	EnsureFrame()
	frame:EnableMouse(preview)
	if preview then
		Hide()
		ApplySettings()
		Paint(PREVIEW_VALUE)
		frame:Show()
	else
		frame:Hide()
		Apply()
	end
end

evt:SetScript('OnEvent', function(_, event, arg1, arg2, arg3)
	if event == 'UNIT_SPELLCAST_SUCCEEDED' then
		if secret(arg3) then dirty = true return end
		if REFLECT[arg3] then OnCast() end
		return
	end

	if event == 'PLAYER_REGEN_ENABLED' then
		Nudge()
		return
	end

	if event == 'DAMAGE_METER_RESET' then
		base = {}
		return
	end

	if event == 'ADDON_RESTRICTION_STATE_CHANGED' then
		if not (pending or needRead) then return end
		local E = _G.Enum
		local T = E and E.AddOnRestrictionType
		local S = E and E.AddOnRestrictionState
		if secret(arg1) or secret(arg2) or not (T and S) then Nudge() return end
		if arg1 == T.Combat and arg2 == S.Inactive then Nudge() end
		return
	end

	-- PLAYER_ENTERING_WORLD: the meter may still be settling from the load.
	retries = 0
	Schedule(2)
end)

-- /xerionreflect          - state dump and the last count, line by line
-- /xerionreflect meter    - every line of your damage done and how it is judged
-- /xerionreflect test     - the text with a sample number, for 10 s
-- /xerionreflect forget   - drop the learned spells of this character
_G.SLASH_XERIONREFLECT1 = '/xerionreflect'
_G.SlashCmdList.XERIONREFLECT = function(msg)
	local function p(...) print('|cffC79C6EXerionUI Reflect|r', ...) end
	msg = (msg or ''):lower()
	if msg:find('test') then
		Show(PREVIEW_VALUE)
		p('sample shown for ' .. SHOW_FOR .. ' s')
		return
	end
	if msg:find('forget') then
		local c = ns.GetCharDB and ns.GetCharDB()
		if c then c.reflect = nil end
		p('learned spells dropped; the next fight without a reflect starts them over')
		return
	end
	local st = Store()
	if msg:find('meter') then
		local now = ReadSpells('DamageDone')
		if not now then p('meter unreadable (secret here, or no meter)') return end
		local taken = ReadSpells('DamageTaken')
		local rows = {}
		for id, amt in pairs(now) do rows[#rows + 1] = { id = id, amount = amt } end
		tsort(rows, function(a, b) return a.amount > b.amount end)
		for _, r in ipairs(rows) do
			local hit, why = Verdict(r.id, st, taken)
			p((hit and '|cff40e040REFLECT|r ' or '') .. SpellName(r.id), '(' .. r.id .. ')', FormatShort(r.amount), '-', why)
		end
		if #rows == 0 then p('no damage done in this meter session') end
		return
	end
	local cfg = GetCfg()
	local n = 0
	if st then for _ in pairs(st.own) do n = n + 1 end end
	p('enabled =', cfg.enable and '|cff00ff00yes|r' or '|cff777777no|r',
		'| warrior =', tostring(IsWarrior()), '| listening =', tostring(live))
	p('reflect pending =', tostring(pending), '(' .. casts .. ' casts)',
		'| reading before it =', base and 'yes' or 'none yet',
		'| waiting for the meter =', tostring(needRead))
	p('own spells learned =', n, 'from', st and st.learned or 0, 'fights')
	if last then
		p('last count:', FormatShort(last.total), 'from', #last.lines, 'lines')
		for _, l in ipairs(last.lines) do p('  ', SpellName(l.id), '(' .. l.id .. ')', FormatShort(l.amount)) end
	else
		p('nothing counted yet this session')
	end
	p('|cff999999/xerionreflect meter|r lists every line, |cff999999test|r shows a sample, |cff999999forget|r drops the learned spells.')
end
