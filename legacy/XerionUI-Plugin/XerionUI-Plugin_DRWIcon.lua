local _, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('DRWIcon', hooksecurefunc, C_Timer)
local _G = _G

local CreateFrame = CreateFrame
local pcall = pcall
local hooksecurefunc = hooksecurefunc
local C_Timer = C_Timer
local ipairs, next, type = ipairs, next, type
local wipe = wipe

ns.hasDRWIcon = true

local secret = ns.IsSecret

local MEDIA = [[Interface\AddOns\XerionUI-Plugin\Media\]]

local SWAPS = {
	{
		key    = 'bone',
		label  = 'Bone Shield',
		ids    = { [195181] = true },
		iconOf = 195181,
		tex    = MEDIA .. 'BoneShieldFace.png',
	},
}

local function IconOf(sw)
	if sw.icon then return sw.icon end
	if not sw.iconOf then return nil end
	local CS = _G.C_Spell
	if CS and CS.GetSpellTexture then
		local ok, id = pcall(CS.GetSpellTexture, sw.iconOf)
		if ok and id and not secret(id) then
			sw.icon = id
			return id
		end
	end
	return nil
end

local VIEWERS = {
	'BuffIconCooldownViewer',
	'BuffBarCooldownViewer',
}

local function IsBlood() return ns.IsSpec('DEATHKNIGHT', 1) end

local DEFAULTS = {
	bone = false,
}

-- The Dancing Rune Weapon swap (and DRWFace.png) was removed at the user's
-- request; its saved switch, and the older `enable` it replaced, go with it.
local function Migrate(cfg)
	cfg.enable = nil
	cfg.drw = nil
end

local function GetCfg() return ns.ModuleCfg('drwIcon', DEFAULTS, Migrate) end
ns.DRWGetCfg = GetCfg

local function SwapOn(sw) return GetCfg()[sw.key] and IsBlood() and true or false end
local function AnyOn()
	if not IsBlood() then return false end
	local cfg = GetCfg()
	for i = 1, #SWAPS do
		if cfg[SWAPS[i].key] then return true end
	end
	return false
end

-- At file level with the set passed in, so a match does not build a new
-- closure on every call.
local function IdIn(ids, v) return v ~= nil and not secret(v) and ids[v] == true end

-- The second answer says whether the cooldown entry could be read at all:
-- only an answer built on a readable entry is worth remembering.
local function EntryMatches(cooldownID, ids)
	if secret(cooldownID) or not cooldownID then return false, false end
	local get = _G.C_CooldownViewer and _G.C_CooldownViewer.GetCooldownViewerCooldownInfo
	if not get then return false, false end
	local ok, info = pcall(get, cooldownID)
	if not ok or not info then return false, false end
	if IdIn(ids, info.spellID) or IdIn(ids, info.linkedSpellID)
		or IdIn(ids, info.overrideSpellID) or IdIn(ids, info.overrideTooltipSpellID) then
		return true, true
	end
	local linked = info.linkedSpellIDs
	if type(linked) == 'table' then
		for i = 1, #linked do
			if IdIn(ids, linked[i]) then return true, true end
		end
	end
	return false, true
end

local function IconTextureOf(f)
	if not f or not f.GetIconTexture then return nil end
	local ok, tex = pcall(f.GetIconTexture, f)
	if ok and tex and tex.SetTexture then return tex end
	return nil
end

local function ReadCooldownID(f)
	if not f or not f.GetCooldownID then return nil end
	local ok, id = pcall(f.GetCooldownID, f)
	if ok then return id end
	return nil
end

-- The cooldownID is read by the caller and handed in. The second answer is
-- true only when the verdict rests on the cooldown entry alone: a readable
-- entry that names the swap, or readable entries that name none and neither
-- fallback matched. A swap found only through the frame's spell ID or its
-- art is not remembered, because those two can change under the same
-- cooldownID.
local function MatchSwap(f, tex, cdID)
	if not f then return nil, false end

	local sID, fileID
	if f.GetSpellID then
		local ok, id = pcall(f.GetSpellID, f) if ok then sID = id end
	end
	if tex and tex.GetTextureFileID then
		local ok, id = pcall(tex.GetTextureFileID, tex) if ok then fileID = id end
	end

	local known = true
	for i = 1, #SWAPS do
		local sw = SWAPS[i]
		local hit, read = EntryMatches(cdID, sw.ids)
		if hit then return sw, true end
		if not read then known = false end
		if sID ~= nil and not secret(sID) and sw.ids[sID] then return sw, false end
		if fileID ~= nil and not secret(fileID) then
			local art = IconOf(sw)
			if art and fileID == art then return sw, false end
		end
	end
	return nil, known
end

-- WHICH SWAP, REMEMBERED PER FRAME
-- The texture hook runs on every refresh of every buff icon, which in a fight
-- is every aura update, and the full match costs five pcalls plus a
-- cooldown-info table (and its linked-spell table) per icon - an API that
-- answers in keys too, so it allocates there as well. The answer only changes
-- when the viewer hands the frame a different cooldown, so it is kept per
-- frame against the cooldownID it was worked out for (false for "no swap"),
-- the same trick as the `ident` cache in DRWSound. Weak keys: a frame the
-- viewer throws away takes its entry with it. A secret or missing cooldownID
-- is never remembered and takes the full match every time, art fallback
-- included. The whole cache goes at every loading screen, spec change and
-- talent change, and again on the two late passes after each, which is when
-- an entry's spell list can move under the same number.
local identID = setmetatable({}, { __mode = 'k' })
local identSw = setmetatable({}, { __mode = 'k' })
local function ForgetIdent()
	wipe(identID)
	wipe(identSw)
end

-- Returns the swap this frame belongs to, or nil, plus the icon texture when
-- the full match had to read it (nil on a remembered answer).
local function SwapFor(f)
	local cdID = ReadCooldownID(f)
	local plain = not secret(cdID) and type(cdID) == 'number'
	if plain and identID[f] == cdID then
		return identSw[f] or nil, nil
	end
	local tex = IconTextureOf(f)
	local sw, known = MatchSwap(f, tex, cdID)
	if plain and known then
		identID[f], identSw[f] = cdID, sw or false
	end
	return sw, tex
end

local hooked = setmetatable({}, { __mode = 'k' })
local painted = setmetatable({}, { __mode = 'k' })

local function Paint(f, sw, tex)
	tex = tex or IconTextureOf(f)
	if not tex then return end
	pcall(tex.SetTexture, tex, sw.tex)
	painted[f] = sw
end

local function Unpaint(f)
	painted[f] = nil
	if f and f.RefreshSpellTexture then pcall(f.RefreshSpellTexture, f) end
end

-- A hook cannot be removed, so it asks "Blood with a swap on?" before the
-- match. Blizzard has just written its own art, so a frame with no swap
-- needs nothing; the one that has a swap is painted again.
local function OnRefreshTexture(f)
	if not AnyOn() then
		painted[f] = nil
		return
	end
	local sw, tex = SwapFor(f)
	if not sw or not SwapOn(sw) then
		painted[f] = nil
		return
	end
	Paint(f, sw, tex)
end

local function Hook(f)
	if not f or hooked[f] then return end
	if not f.RefreshSpellTexture then return end
	hooked[f] = true
	pcall(hooksecurefunc, f, 'RefreshSpellTexture', OnRefreshTexture)
end

-- Off (or not Blood): no hooks are installed and only frames we painted
-- earlier are handed back to Blizzard; Scan runs again when a swap is
-- switched on, and hooks the icons then.
--
-- Scan has two jobs the per-frame hook cannot do: hook a frame the viewer
-- created after we last looked (its first art was written before any hook of
-- ours was on it), and put the picture back if a UI skin wrote the art
-- through some path of its own. It used to run every second, idle included.
-- Now it runs a frame after each whole-viewer refresh - which is when the
-- viewer takes new frames from its pool and when a skin re-dresses its icons
-- - plus a slow five-second net for anything that slips past that.
local function Scan()
	local on = AnyOn()
	if not on and next(painted) == nil then return end
	for v = 1, #VIEWERS do
		local viewer = _G[VIEWERS[v]]
		if viewer and viewer.GetChildren then
			for _, f in ipairs({ viewer:GetChildren() }) do
				if f and f.GetIconTexture then
					if on then
						Hook(f)
						local sw, tex = SwapFor(f)
						if sw and SwapOn(sw) then
							Paint(f, sw, tex)
						elseif painted[f] then
							Unpaint(f)
						end
					elseif painted[f] then
						Unpaint(f)
					end
				end
			end
		end
	end
end

-- The viewer hooks go in only while a swap is live (Blood, switched on), as
-- the per-frame ones do; a hook cannot come out again, so it asks first.
local hookedViewers = {}
local QueueScan = ns.Coalesce(Scan)
local function OnViewerRefresh()
	if AnyOn() then QueueScan() end
end

local function HookViewers()
	for i = 1, #VIEWERS do
		local v = _G[VIEWERS[i]]
		if v and v.RefreshData and not hookedViewers[v] then
			hookedViewers[v] = true
			pcall(hooksecurefunc, v, 'RefreshData', OnViewerRefresh)
		end
	end
end

local ticker
local function NetScan()
	HookViewers()
	Scan()
end

local function SyncTicker()
	local want = AnyOn()
	if want and not ticker then
		ticker = C_Timer.NewTicker(5, NetScan)
	elseif not want and ticker then
		ticker:Cancel()
		ticker = nil
	end
end

ns.DRWApply = function()
	if AnyOn() then HookViewers() end
	Scan()
	SyncTicker()
end

-- The Cooldown Manager builds its item frames on its own schedule, and on a
-- cold login that lands after us, hence the two late passes. Each pass also
-- forgets the remembered answers: the event itself can move a spell list,
-- and a late pass drops any answer worked out from an entry still filling.
local function Resync()
	ForgetIdent()
	if ns.DRWApply then ns.DRWApply() end
end

local evt = CreateFrame('Frame')
evt:RegisterEvent('PLAYER_ENTERING_WORLD')
evt:RegisterUnitEvent('PLAYER_SPECIALIZATION_CHANGED', 'player')
evt:RegisterEvent('PLAYER_TALENT_UPDATE')
evt:SetScript('OnEvent', function()
	Resync()
	if C_Timer and C_Timer.After then
		C_Timer.After(2, Resync)
		C_Timer.After(6, Resync)
	end
end)

_G.SLASH_XERIONDRWICON1 = '/xeriondrw'
SlashCmdList.XERIONDRWICON = function(msg)
	local function p(...) print('|cff0CD29DXerionUI buff icons|r', ...) end
	local dump = (msg or ''):lower():find('dump') ~= nil
	local cfg = GetCfg()
	p('Blood =', tostring(IsBlood()), '| buff viewers only',
		'| net scan =', ticker and 'every 5s' or 'stopped',
		'| viewer hooks =', next(hookedViewers) and 'in' or 'none')
	for i = 1, #SWAPS do
		local sw = SWAPS[i]
		local art = IconOf(sw)
		p(('  %-20s %s  art=%s  %s'):format(sw.label,
			cfg[sw.key] and '|cff00ff00on|r ' or '|cff777777off|r',
			art and tostring(art) or 'not cached yet', sw.tex))
	end

	local function show(v)
		if v == nil then return '-' end
		if secret(v) then return '|cffff6600secret|r' end
		return tostring(v)
	end

	local total, matched = 0, 0
	for v = 1, #VIEWERS do
		local viewer = _G[VIEWERS[v]]
		if not viewer then
			p(VIEWERS[v], '= |cffff6600not created|r')
		elseif not viewer.GetChildren then
			p(VIEWERS[v], '= no GetChildren')
		else
			local kids = { viewer:GetChildren() }
			local n = #kids
			local hit = 0
			for i, f in ipairs(kids) do
				if f and f.GetIconTexture then
					total = total + 1
					local tex = IconTextureOf(f)
					local sw = MatchSwap(f, tex, ReadCooldownID(f))
					if sw then hit = hit + 1 end

					if dump then
						local cdID, sID, fileID
						if f.GetCooldownID then
							local ok, id = pcall(f.GetCooldownID, f) if ok then cdID = id end
						end
						if f.GetSpellID then
							local ok, id = pcall(f.GetSpellID, f) if ok then sID = id end
						end
						if tex and tex.GetTextureFileID then
							local ok, id = pcall(tex.GetTextureFileID, tex) if ok then fileID = id end
						end
						local info
						local get = _G.C_CooldownViewer and _G.C_CooldownViewer.GetCooldownViewerCooldownInfo
						if get and cdID and not secret(cdID) then
							local ok, inf = pcall(get, cdID) if ok then info = inf end
						end
						local shownTxt = '?'
						local okS, sh = pcall(f.IsShown, f)
						if okS then shownTxt = sh and 'shown' or 'hidden' end
						p(('  [%d.%d] %s cd=%s spell=%s icon=%s%s'):format(
							v, i, shownTxt, show(cdID), show(sID), show(fileID),
							sw and ('  |cff00ff00<- ' .. sw.label .. '|r') or ''))
						if info then
							p(('        info: spellID=%s linked=%s override=%s tooltip=%s'):format(
								show(info.spellID), show(info.linkedSpellID),
								show(info.overrideSpellID), show(info.overrideTooltipSpellID)))
							local ls = info.linkedSpellIDs
							if type(ls) == 'table' and #ls > 0 then
								local parts = {}
								for k = 1, #ls do parts[#parts + 1] = show(ls[k]) end
								p('        linkedSpellIDs: ' .. table.concat(parts, ', '))
							end
						end
					end
				end
			end
			matched = matched + hit
			p(VIEWERS[v], '= ' .. n .. ' children,',
				hit > 0 and ('|cff00ff00' .. hit .. ' matched|r') or 'none matched')
		end
	end
	p('item frames seen:', total, '| matched:', matched)
	if not dump then
		p('|cffffd100Run|r |cffffd200/xeriondrw dump|r |cffffd100WHILE THE BUFF IS UP to print every id each|r')
		p('|cffffd100frame reports - that is what says why it did not match.|r')
	elseif matched == 0 then
		p('|cffffd100=> Nothing above matched. If the buff WAS up when you ran this, it is|r')
		p('|cffffd100   filed under some other id - send me the dump.|r')
	end
end
