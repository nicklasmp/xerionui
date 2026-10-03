local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('DRWSound', hooksecurefunc, C_Timer)
local _G = _G

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local GetTime = GetTime
local hooksecurefunc = hooksecurefunc
local pcall = pcall
local ipairs = ipairs
local type = type
local print = print
local tostring = tostring

ns.hasDRWSound = true

local secret = ns.IsSecret
local CooldownMatches = ns.CooldownMatches

local DRW_ABILITY = 49028
local DRW_BUFF    = 81256

local VIEWERS = {
	'EssentialCooldownViewer',
	'UtilityCooldownViewer',
	'BuffIconCooldownViewer',
	'BuffBarCooldownViewer',
}

local RING_GAP = 0.3

local SETTLE = 3

local DEFAULT_SOUND = '|cFF00FF00Kira - External|r'

local DEFAULTS = {
	enable    = false,
	onRefresh = true,
	onGain    = false,
	sound     = DEFAULT_SOUND,
}

local function GetCfg() return ns.ModuleCfg('drwSound', DEFAULTS) end
ns.DRWSGetCfg = GetCfg

local function IsBlood() return ns.IsSpec('DEATHKNIGHT', 1) end
local function Active() return GetCfg().enable and IsBlood() and true or false end

local ident = setmetatable({}, { __mode = 'k' })

local function IsDRW(f)
	if not f or not f.GetCooldownID then return false end
	local ok, id = pcall(f.GetCooldownID, f)
	if not ok or secret(id) or id == nil then return false end
	local c = ident[f]
	if c and c.id == id then return c.drw end
	local drw = CooldownMatches(id, DRW_BUFF) or CooldownMatches(id, DRW_ABILITY)
	ident[f] = { id = id, drw = drw }
	return drw
end

local function ReadExpiration(f)
	if not f or not f.GetAuraDataCached then return nil, 'none' end
	local ok, data = pcall(f.GetAuraDataCached, f)
	if not ok or secret(data) or type(data) ~= 'table' then return nil, 'none' end
	local exp = data.expirationTime
	if secret(exp) then return nil, 'secret' end
	if type(exp) ~= 'number' then return nil, 'none' end
	return exp, 'readable'
end

local lastRing = 0
local quietUntil = 0
local lastRingWhy, lastRingAt

local function Ring(why)
	local now = GetTime()
	if now < quietUntil then return end
	if now - lastRing < RING_GAP then return end
	lastRing = now
	lastRingWhy, lastRingAt = why, now
	ns.PlaySoundByName(GetCfg().sound)
end

local lastExp   = setmetatable({}, { __mode = 'k' })
local removedAt = setmetatable({}, { __mode = 'k' })

local function OnUpdated(f)
	if not IsDRW(f) or not Active() then return end
	local exp = ReadExpiration(f)
	local last = lastExp[f]
	lastExp[f] = exp
	if not GetCfg().onRefresh then return end
	if exp and last and exp <= last + 0.05 then return end
	Ring('refresh')
end

local function OnGain(f)
	if not IsDRW(f) or not Active() then return end
	lastExp[f] = (ReadExpiration(f))
	local cfg = GetCfg()
	local replaced = removedAt[f] == GetTime()
	if (replaced and cfg.onRefresh) or cfg.onGain then
		Ring(replaced and 'refresh (instance replaced)' or 'gain')
	end
end

local function OnRemoved(f)
	lastExp[f] = nil
	removedAt[f] = GetTime()
end

local hooked = setmetatable({}, { __mode = 'k' })

local function Hook(f)
	if not f or hooked[f] then return end
	if type(f.OnUnitAuraUpdatedEvent) ~= 'function' then return end
	hooked[f] = true
	pcall(hooksecurefunc, f, 'OnUnitAuraUpdatedEvent', OnUpdated)
	if type(f.TriggerAuraAppliedAlert) == 'function' then
		pcall(hooksecurefunc, f, 'TriggerAuraAppliedAlert', OnGain)
	end
	if type(f.TriggerAuraRemovedAlert) == 'function' then
		pcall(hooksecurefunc, f, 'TriggerAuraRemovedAlert', OnRemoved)
	end
end

local function Scan()
	for v = 1, #VIEWERS do
		local viewer = _G[VIEWERS[v]]
		if viewer and viewer.GetChildren then
			for _, f in ipairs({ viewer:GetChildren() }) do
				Hook(f)
			end
		end
	end
end

local hookedViewers = {}
local QueueScan = ns.Coalesce(function() if Active() then Scan() end end)

local function HookViewers()
	for i = 1, #VIEWERS do
		local v = _G[VIEWERS[i]]
		if v and v.RefreshData and not hookedViewers[v] then
			hookedViewers[v] = true
			pcall(hooksecurefunc, v, 'RefreshData', QueueScan)
		end
	end
end

local ticker
local function SyncTicker()
	local want = Active()
	if want and not ticker then
		ticker = C_Timer.NewTicker(5, function()
			HookViewers()
			Scan()
		end)
	elseif not want and ticker then
		ticker:Cancel()
		ticker = nil
	end
end

ns.DRWSApply = function()
	if Active() then
		HookViewers()
		Scan()
	end
	SyncTicker()
end

local evt = CreateFrame('Frame')
evt:RegisterEvent('PLAYER_ENTERING_WORLD')
evt:RegisterUnitEvent('PLAYER_SPECIALIZATION_CHANGED', 'player')
evt:SetScript('OnEvent', function(_, event)
	if event == 'PLAYER_ENTERING_WORLD' then
		quietUntil = GetTime() + SETTLE
	end
	if ns.DRWSApply then ns.DRWSApply() end
	if C_Timer and C_Timer.After then
		C_Timer.After(2, function() if ns.DRWSApply then ns.DRWSApply() end end)
		C_Timer.After(6, function() if ns.DRWSApply then ns.DRWSApply() end end)
	end
end)

SLASH_XERIONDRWSOUND1 = '/xeriondrwsound'
SLASH_XERIONDRWSOUND2 = '/xeriondrws'
SlashCmdList.XERIONDRWSOUND = function(msg)
	local function p(...) print('|cff0CD29DXerionUI DRW sound|r', ...) end
	msg = (msg or ''):lower()
	local cfg = GetCfg()
	if msg:find('test') then
		ns.PlaySoundByName(cfg.sound)
		p('test ring:', tostring(cfg.sound))
		return
	end
	p('enabled =', cfg.enable and '|cff00ff00yes|r' or '|cff777777no|r',
		'| Blood =', tostring(IsBlood()),
		'| on refresh =', cfg.onRefresh and 'on' or 'off',
		'| on gain =', cfg.onGain and 'on' or 'off')
	p('sound =', tostring(cfg.sound))

	local drwFrames = 0
	for v = 1, #VIEWERS do
		local viewer = _G[VIEWERS[v]]
		if not viewer then
			p(VIEWERS[v], '= |cffff6600not created|r')
		elseif not viewer.GetChildren then
			p(VIEWERS[v], '= no GetChildren')
		else
			local kids = { viewer:GetChildren() }
			local n, hk, hit = #kids, 0, 0
			for i = 1, n do
				local f = kids[i]
				if hooked[f] then hk = hk + 1 end
				if IsDRW(f) then
					hit = hit + 1
					drwFrames = drwFrames + 1
					local okS, shown = pcall(f.IsShown, f)
					local exp, state = ReadExpiration(f)
					local txt
					if state == 'readable' then
						txt = ('expires in %.1fs (readable: only a later time rings)'):format(exp - GetTime())
					elseif state == 'secret' then
						txt = '|cffff6600expiration SECRET|r (every update rings)'
					else
						txt = 'no aura data (buff not up)'
					end
					p(('  weapon frame: %s, %s, %s'):format(
						okS and (shown and 'shown' or 'hidden') or '?',
						hooked[f] and 'hooked' or '|cffff6600NOT hooked|r',
						txt))
				end
			end
			p(VIEWERS[v], '=', n, 'children,', hk, 'hooked,',
				hit > 0 and ('|cff00ff00' .. hit .. ' Dancing Rune Weapon|r') or 'no Dancing Rune Weapon')
		end
	end
	if drwFrames == 0 then
		p('|cffff6600No Dancing Rune Weapon frame in any viewer.|r The weapon has to be on a Cooldown Manager bar (buff or cooldown; Edit Mode > Cooldown Manager) for the sound to have anything to listen to.')
	end
	if lastRingAt then
		p(('last ring: %s, %.1fs ago'):format(lastRingWhy, GetTime() - lastRingAt))
	else
		p('no ring yet this session')
	end
	p('|cff999999/xeriondrws test|r plays the chosen sound.')
end
