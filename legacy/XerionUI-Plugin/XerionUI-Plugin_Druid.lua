local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('Druid', hooksecurefunc, C_Timer)
local _G = _G

-- Two druid features, one section each: the Well-Honed Instincts sound (every
-- spec) right below, and the Guardian's Bear Form reminder at the bottom.
--
-- WHAT IT DOES
-- Well-Honed Instincts is the druid's cheat death: when you drop low it casts
-- Frenzied Regeneration on you by itself, and it leaves a debuff on you
-- (382912) for as long as it cannot do that again. This plays a sound the
-- moment that debuff lands and, if one is picked, another when it falls off.
-- Every spec - the debuff only ever lands on a druid who has the talent, so
-- nothing here needs to know which spec or build you are on.
--
-- HOW
-- The same road Kira Reminders' trash sounds take for "You": the game's own
-- C_UnitAuras.AddAuraSound on 'player', one registration per sound. The engine
-- plays the file when the aura comes or goes, so Lua never reads the aura and
-- it works inside a key and a raid encounter, where the aura is secret. It is
-- its own module rather than a row in Kira Reminders so it works with that
-- module off and ignores its "only inside instances" switch.
--
-- WHEN IT CAN REGISTER
-- The client refuses a NEW registration during a boss encounter and in combat
-- inside a key (LustPots found it), so it is made at login and on a settings
-- change, and kept: a live one keeps playing through both. One that had to
-- wait (a /reload mid-pull) is made when the fight or the encounter ends -
-- the two events for that are listened to only while something waits.

local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local PlaySoundFile = PlaySoundFile
local ipairs, pairs, pcall, tostring, print = ipairs, pairs, pcall, tostring, print

ns.hasWellHoned = true

local SPELL = 382912

local DEFAULTS = {
	enable   = true,
	sound    = '|cFF00FF00Kira - Cheat Death|r',
	endSound = 'None',
	channel  = 'Master',
}

local function GetCfg() return ns.ModuleCfg('wellHoned', DEFAULTS) end
ns.WHIGetCfg = GetCfg

local function IsDruid() return ns.IsClass('DRUID') end

-- One per sound setting, in the order the engine's trigger enum names them.
local TRIGGERS = {
	{ key = 'sound',    enum = 'Added' },
	{ key = 'endSound', enum = 'Removed' },
}

-- [setting key] = { id = registration, path, channel }
local reg = {}
local pending = false
local refused

local function SoundAPI()
	local api = _G.C_UnitAuras
	if not (api and api.AddAuraSound and api.RemoveAuraSound) then return nil end
	if not (_G.Enum and _G.Enum.UnitAuraSoundTrigger) then return nil end
	return api
end

-- Asked of the client rather than tried, so a refusal never happens.
local function Blocked()
	local R = _G.C_RestrictedActions
	local T = _G.Enum and _G.Enum.AddOnRestrictionType
	if not (R and R.IsAddOnRestrictionActive and T) then return InCombatLockdown() end
	local function on(t)
		local ok, v = pcall(R.IsAddOnRestrictionActive, t)
		return ok and v == true
	end
	return on(T.Encounter) or (on(T.Combat) and on(T.ChallengeMode))
end

local function Wanted(cfg)
	local out = {}
	if not (cfg.enable and IsDruid()) then return out end
	local channel = cfg.channel or 'Master'
	local enums = _G.Enum.UnitAuraSoundTrigger
	for _, t in ipairs(TRIGGERS) do
		local path = ns.SoundPath(cfg[t.key])
		local trigger = enums[t.enum]
		if path and trigger then
			out[t.key] = { trigger = trigger, path = path, channel = channel }
		end
	end
	return out
end

local evt = CreateFrame('Frame')
local WAIT_EVENTS = { 'PLAYER_REGEN_ENABLED', 'ADDON_RESTRICTION_STATE_CHANGED' }

local function Sync()
	local api = SoundAPI()
	if not api then return end
	local want = Wanted(GetCfg())
	for k, live in pairs(reg) do
		local w = want[k]
		if not w or w.path ~= live.path or w.channel ~= live.channel then
			pcall(api.RemoveAuraSound, live.id)
			reg[k] = nil
		end
	end
	pending = false
	local blocked = Blocked()
	for k, w in pairs(want) do
		if not reg[k] then
			if blocked then
				pending = true
			else
				local ok, id = pcall(api.AddAuraSound, w.trigger, {
					unitToken = 'player', spellID = SPELL,
					soundFileName = w.path, outputChannel = w.channel,
				})
				if ok and id then
					reg[k] = { id = id, path = w.path, channel = w.channel }
				else
					refused = ok and 'no ID returned' or tostring(id)
					pending = true
				end
			end
		end
	end
	for _, e in ipairs(WAIT_EVENTS) do
		if pending then pcall(evt.RegisterEvent, evt, e) else pcall(evt.UnregisterEvent, evt, e) end
	end
end

-- The restriction state still reads the old answer while its own change event
-- is being handed out, so every sync runs on the next frame; a dragged setting
-- asking many times a frame gets one pass too.
ns.WHIApply = ns.Coalesce(Sync)

evt:SetScript('OnEvent', function()
	if pending then ns.WHIApply() end
end)

-- The Test button: the chosen sound, on the chosen channel, whatever the class.
ns.WHITest = function(key)
	local cfg = GetCfg()
	local path = ns.SoundPath(cfg[key or 'sound'])
	if path then pcall(PlaySoundFile, path, cfg.channel or 'Master') end
end

_G.SLASH_XERIONWHI1 = '/xerionwhi'
_G.SLASH_XERIONWHI2 = '/xerioncheat'
_G.SlashCmdList.XERIONWHI = function(msg)
	local function p(...) print('|cffFF7C0AXerionUI Cheat Death|r', ...) end
	local cfg = GetCfg()
	if (msg or ''):lower():find('test') then
		ns.WHITest()
		p('test:', tostring(cfg.sound))
		return
	end
	p('enabled =', cfg.enable and '|cff00ff00yes|r' or '|cff777777no|r',
		'| druid =', tostring(IsDruid()),
		'| channel =', tostring(cfg.channel),
		SoundAPI() and '' or '|cffff5555(no C_UnitAuras.AddAuraSound on this client)|r')
	for _, t in ipairs(TRIGGERS) do
		local live = reg[t.key]
		p(t.enum .. ':', tostring(cfg[t.key]),
			live and '|cff40e040registered|r'
				or (ns.SoundPath(cfg[t.key]) and '|cffff8800not registered|r' or '|cff777777off|r'))
	end
	if pending then p('|cffff8800waiting|r - a boss encounter or a fight in a key; it registers when that ends') end
	if refused then p('last refusal: ' .. refused) end
	p('|cff999999/xerionwhi test|r plays the sound.')
end

-- BEAR FORM REMINDER (Guardian)
-- A Guardian who leaves Bear Form mid-fight - a Travel Form hop between packs,
-- a caster-form heal, a stray Cat Form - has dropped the armour and the rage
-- that make them the tank. This puts one line of text on the screen for as
-- long as the player is in combat, Guardian and not a bear. Text, colour, size
-- and position are the player's; right-drag moves it while previewing.
--
-- WHERE THE ANSWERS COME FROM
-- The form is GetShapeshiftFormID(), 5 for Bear Form (DRUID_BEAR_FORM in
-- Blizzard's Constants.lua; Incarnation: Guardian of Ursoc stays on it). It
-- has no secret annotation, and EllesmereUI's resource bars and nameplates
-- compare it in combat, keys included. Should it ever come back secret, the
-- text stays hidden: like Aggro Check, a warning that fails open would shout
-- at a player who is a bear. Guardian is spec index 3 (spec ID 104), read
-- through ns.IsSpec, where an unreadable spec means allow. Combat is
-- PLAYER_REGEN_DISABLED / ENABLED, read once more whenever listening starts.
--
-- COST
-- Nothing listens unless the box is ticked on a druid. UPDATE_SHAPESHIFT_FORM
-- can come in bursts, so every event only asks for one refresh on the next
-- frame. The text never takes the mouse outside preview: it sits in the middle
-- of the screen during a fight and must stay click-through.

ns.hasBearForm = true

local UIParent = UIParent
local UnitAffectingCombat = UnitAffectingCombat
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local GetShapeshiftFormID = GetShapeshiftFormID
local mmax = math.max
local secret = ns.IsSecret

local BEAR_FORM = 5
local GUARDIAN = 3

local BF_DEFAULTS = {
	enable = true,
	text   = 'BEAR FORM',
	color  = { 1, 0.49, 0.04, 1 },
	size   = 32,
	lock   = false,
	x      = 0,
	y      = 140,
}

local function BFGetCfg() return ns.ModuleCfg('bearForm', BF_DEFAULTS) end
ns.BFRGetCfg = BFGetCfg

local bfFrame, bfText
local bfPreview = false
local inCombat = false

local function ReadCombat()
	local ok, v = pcall(UnitAffectingCombat, 'player')
	inCombat = ok and not secret(v) and v and true or false
end

-- true only when the client says, in the clear, that the player is not a bear.
local function NotBear()
	if not GetShapeshiftFormID then return false end
	local ok, form = pcall(GetShapeshiftFormID)
	if not ok or secret(form) then return false end
	return form ~= BEAR_FORM
end

local function Dead()
	local ok, v = pcall(UnitIsDeadOrGhost, 'player')
	return ok and not secret(v) and v and true or false
end

-- Preview wins over every gate, so the text can be placed on any character.
local function ShouldShow()
	if bfPreview then return true end
	if not (inCombat and BFGetCfg().enable) then return false end
	if not ns.IsSpec('DRUID', GUARDIAN) then return false end
	if Dead() then return false end
	return NotBear()
end

local function EnsureBearFrame()
	if bfFrame then return end
	bfFrame = CreateFrame('Frame', 'XerionUIBearForm', UIParent)
	bfFrame:SetFrameStrata('HIGH')
	bfFrame:SetSize(120, 40)
	bfFrame:SetClampedToScreen(true)
	bfFrame:SetMovable(true)
	bfFrame:EnableMouse(false)
	bfFrame:RegisterForDrag('RightButton')
	ns.MakeDraggable(bfFrame, BFGetCfg, 'x', 'y')
	bfText = bfFrame:CreateFontString(nil, 'OVERLAY')
	bfText:SetPoint('CENTER')
	bfText:SetJustifyH('CENTER')
	bfFrame:Hide()
end

local function BearRefresh()
	if bfFrame then bfFrame:SetShown(ShouldShow()) end
end
local BearRefreshSoon = ns.Coalesce(BearRefresh)

local BF_EVENTS = {
	'PLAYER_ENTERING_WORLD', 'PLAYER_REGEN_DISABLED', 'PLAYER_REGEN_ENABLED',
	'UPDATE_SHAPESHIFT_FORM', 'PLAYER_DEAD', 'PLAYER_ALIVE', 'PLAYER_UNGHOST',
}
local bfEvt = CreateFrame('Frame')
local bfLive = false

local function SetBearLive(on)
	on = on and true or false
	if on == bfLive then return end
	bfLive = on
	if on then
		-- Combat went unwatched while off.
		ReadCombat()
		for _, e in ipairs(BF_EVENTS) do bfEvt:RegisterEvent(e) end
		bfEvt:RegisterUnitEvent('PLAYER_SPECIALIZATION_CHANGED', 'player')
	else
		for _, e in ipairs(BF_EVENTS) do bfEvt:UnregisterEvent(e) end
		bfEvt:UnregisterEvent('PLAYER_SPECIALIZATION_CHANGED')
	end
end

-- Nothing is built while the module is off (or the player is not a druid) and
-- not previewing; a frame built earlier is only hidden.
local function BearApply()
	local cfg = BFGetCfg()
	local on = cfg.enable and ns.IsClass('DRUID')
	SetBearLive(on)
	if not (on or bfPreview) then
		BearRefresh()
		return
	end
	EnsureBearFrame()
	local c = cfg.color or BF_DEFAULTS.color
	bfText:SetFont(ns.GothamNarrowBlackFont(), cfg.size or BF_DEFAULTS.size, 'OUTLINE')
	bfText:SetText(cfg.text or BF_DEFAULTS.text)
	bfText:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
	local w, h = bfText:GetStringWidth(), bfText:GetStringHeight()
	if secret(w) then w = 0 end
	if secret(h) then h = 0 end
	bfFrame:SetSize(mmax(60, (w or 0) + 16), mmax(24, (h or 0) + 8))
	bfFrame:ClearAllPoints()
	bfFrame:SetPoint('CENTER', UIParent, 'CENTER', cfg.x or 0, cfg.y or 0)
	bfFrame:EnableMouse(bfPreview and not cfg.lock or false)
	BearRefresh()
end
ns.BFRApply = ns.Coalesce(BearApply)

ns.BFRIsPreview = function() return bfPreview end
ns.BFRSetPreview = function(v)
	bfPreview = v and true or false
	BearApply()
end

bfEvt:SetScript('OnEvent', function(_, event)
	if event == 'PLAYER_REGEN_DISABLED' then
		inCombat = true
	elseif event == 'PLAYER_REGEN_ENABLED' then
		inCombat = false
	elseif event == 'PLAYER_ENTERING_WORLD' then
		ReadCombat()
	end
	BearRefreshSoon()
end)

-- /xerionbear          - state dump
-- /xerionbear test     - toggle the preview so the text can be placed
_G.SLASH_XERIONBEAR1 = '/xerionbear'
_G.SlashCmdList.XERIONBEAR = function(msg)
	local function p(...) print('|cffFF7C0AXerionUI Bear Form|r', ...) end
	msg = (msg or ''):lower()
	if msg:find('test') or msg:find('preview') then
		ns.BFRSetPreview(not bfPreview)
		p('preview', bfPreview and 'on' or 'off')
		return
	end
	local cfg = BFGetCfg()
	local okF, form = pcall(GetShapeshiftFormID)
	local formText = not okF and 'error' or (secret(form) and 'secret' or tostring(form))
	local spec, unreadable = ns.PlayerSpec()
	p('enabled =', cfg.enable and '|cff00ff00yes|r' or '|cff777777no|r',
		'| druid =', tostring(ns.IsClass('DRUID')),
		'| spec =', unreadable and 'secret' or tostring(spec), '(3 = Guardian)')
	p('in combat =', tostring(inCombat), '| form =', formText, '(5 = Bear)',
		'| shown =', tostring(bfFrame and bfFrame:IsShown() or false))
	p('listening =', tostring(bfLive), '| preview =', tostring(bfPreview))
	p('|cff999999/xerionbear test|r toggles the preview.')
end
