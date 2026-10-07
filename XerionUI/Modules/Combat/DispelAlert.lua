--------------------------------------------------------------------------------
-- Dispel Alert
-- "<Ability> successfully dispelled" (with the ability's icon) when one of your
-- own dispels, purges, soothes or steals actually removes an aura - from a
-- friendly or an enemy unit: magic, curse, poison, disease, bleed and enrage.
--
-- Midnight gives addons no combat log, so a dispel is recognised in three steps:
--   1. UNIT_SPELLCAST_SENT for one of our dispel spells: the auras of the likely
--      target(s) are remembered (name + icon, before they vanish).
--   2. UNIT_AURA during the next moment: a removedAuraInstanceIDs entry that
--      matches a remembered aura means it was taken off.
--   3. The cast SUCCEEDED and something was removed -> the alert shows.
-- On this client the aura lists cannot be read at all, and the ids in a
-- UNIT_AURA payload are secret. What does come through is whether anything was
-- removed: removedAuraInstanceIDs is nil when nothing went and a (secret) table
-- when something did. So a removal on the unit while the dispel is in flight is
-- the proof; what was removed is only known when the lists can be read. The cast
-- alone proves nothing - a dispel with nothing to remove still succeeds.
-- /xui trace DispelAlert prints each step.
-- Nothing is registered or scanned while idle; the window only exists for about
-- a second after one of the listed spells. When the aura's name is secret the
-- alert falls back to a plain "Successfully dispelled" (the icon still shows).
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates

local M = XUI:NewModule("DispelAlert", {
	name = "Dispel Alert",
	desc = "Shows what you successfully dispelled, purged or stole.",
	category = "combat",
	icon = [[Interface\Icons\Spell_Holy_DispelMagic]],
	order = 40,
	untested = true,
	defaults = {
		friendly = true,
		enemy = true,
		text = "%s successfully dispelled",
		textUnknown = "Successfully dispelled",
		nameColor = { 1, 0.82, 0, 1 },
		showIcon = true,
		iconSize = 28,
		hold = 2,
		fade = 1,
		font = T.Font(24, { color = { 1, 1, 1, 1 } }),
		alert = T.Alert(),
		position = T.Position(0, 220),
	},
})

local IsSecret = XUI.IsSecret

-- Spells that can remove an aura from someone else (spell ids; an id that does
-- not exist is simply never cast). Pet and totem abilities are not tracked.
local DISPELS = {}
for _, id in ipairs({
	-- Priest: Purify, Dispel Magic, Mass Dispel, Purify Disease
	527, 528, 32375, 213634,
	-- Paladin: Cleanse, Cleanse Toxins
	4987, 213644,
	-- Druid: Nature's Cure, Remove Corruption, Soothe
	88423, 2782, 2908,
	-- Shaman: Purify Spirit, Cleanse Spirit, Purge
	77130, 51886, 370,
	-- Monk: Detox (both), Revival, Restoral
	115450, 218164, 115310, 388615,
	-- Evoker: Naturalize, Expunge, Cauterizing Flame
	360823, 365585, 374251,
	-- Mage: Remove Curse, Spellsteal
	475, 30449,
	-- Hunter: Tranquilizing Shot
	19801,
	-- Demon Hunter: Consume Magic
	278326,
	-- Rogue: Shiv (enrage)
	5938,
}) do
	DISPELS[id] = true
end

local WINDOW = 1       -- seconds the aura events are watched after a cast
local MAX_UNITS = 12

local display
local seen = { sent = 0, auraEvents = 0, matched = 0, removals = 0, shown = 0, byList = 0, assumed = 0, secretPayload = 0, auras = 0, secretNames = 0, route = "no cast yet" }
local last = "nothing yet"
local pending          -- { snaps = { [unit] = { ids = { [auraInstanceID] = rec }, blind } }, spell, ok, hit }

local function Display()
	if display then return display end
	display = XUI.Widgets:CreateText("XUI_DispelAlert")
	display:Hide()
	display.icon = display:CreateTexture(nil, "OVERLAY")
	display.icon:SetPoint("RIGHT", display.text, "LEFT", -6, 0)
	local anim = display:CreateAnimationGroup()
	display.fadeOut = anim:CreateAnimation("Alpha")
	display.fadeOut:SetFromAlpha(1)
	display.fadeOut:SetToAlpha(0)
	anim:SetScript("OnFinished", function() display:Hide() end)
	display.anim = anim
	XUI.Movers:Register(display, M, "position")
	return display
end

--------------------------------------------------------------------------------
-- Snapshots
--------------------------------------------------------------------------------
-- Calls visit(aura) for every aura of `unit` the client will show. Two routes
-- are tried in turn, since which of them answers differs between builds and
-- between restricted and open content. Answers the route that produced
-- auras (nil when none did) and whether a route ran at all.
local function Collect(unit, visit)
	local count, ran = 0, false
	local function Each(a)
		if a ~= nil and not IsSecret(a) and type(a) == "table" then
			count = count + 1
			visit(a)
		end
	end
	local api = C_UnitAuras
	if api and api.GetUnitAuras then
		for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
			local ok, list = pcall(api.GetUnitAuras, unit, filter)
			if ok then
				ran = true
				if type(list) == "table" and not IsSecret(list) and not XUI.IsSecretTable(list) then
					for i = 1, #list do Each(list[i]) end
				end
			end
		end
		if count > 0 then return "GetUnitAuras", true end
	end
	local AU = AuraUtil
	if AU and AU.ForEachAura then
		local a = pcall(AU.ForEachAura, unit, "HELPFUL", nil, Each, true)
		local b = pcall(AU.ForEachAura, unit, "HARMFUL", nil, Each, true)
		ran = ran or (a and b)
		if count > 0 then return "ForEachAura", true end
	end
	return nil, ran
end

-- The auras of `unit` by instance id, so a removal can be told from the rest.
-- The second answer is false when the list could not be read at all (secret
-- aura data): the unit is then watched "blind" and any removal counts. Names
-- and icons may be secret; they are kept all the same, because a secret
-- string or texture can still be shown.
local function Snapshot(unit)
	local snap, any = {}, false
	local route = Collect(unit, function(a)
		local id = a.auraInstanceID
		if id ~= nil and not IsSecret(id) then
			snap[id] = { name = a.name, icon = a.icon }
			any = true
			seen.auras = seen.auras + 1
			if IsSecret(a.name) then seen.secretNames = seen.secretNames + 1 end
		end
	end)
	if not any then
		-- no readable aura data: the ids alone still say that something went
		local api = C_UnitAuras
		if api and api.GetUnitAuraInstanceIDs then
			for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
				local ok, ids = pcall(api.GetUnitAuraInstanceIDs, unit, filter)
				if ok and type(ids) == "table" and not IsSecret(ids) and not XUI.IsSecretTable(ids) then
					for i = 1, #ids do
						local id = ids[i]
						if not IsSecret(id) then
							snap[id] = snap[id] or {}
							any = true
						end
					end
				end
			end
			if any then route = "GetUnitAuraInstanceIDs (ids only)" end
		end
	end
	seen.route = route or "none could be read"
	return snap, any
end

local FIXED = { "target", "focus", "mouseover", "softenemy", "softfriend", "player" }

-- A mouseover or soft target is gone by the time the aura event arrives, and
-- the event names the unit by another token (party2, raid7, nameplate3). So
-- such a unit is remembered under a token that stays: a group token, else a
-- nameplate.
local function Stable(u)
	if u ~= "mouseover" and u ~= "softenemy" and u ~= "softfriend" then return u end
	local function Same(token) return XUI.Ask(UnitIsUnit, u, token) == true end
	if IsInRaid() then
		for i = 1, 40 do
			local t = "raid" .. i
			if UnitExists(t) and Same(t) then return t end
		end
	elseif IsInGroup() then
		for i = 1, 4 do
			local t = "party" .. i
			if UnitExists(t) and Same(t) then return t end
		end
	end
	for i = 1, 40 do
		local t = "nameplate" .. i
		if UnitExists(t) and Same(t) then return t end
	end
	return u
end

-- Units the spell can have been aimed at, from the name UNIT_SPELLCAST_SENT gives.
local function Candidates(targetName)
	local out, seen = {}, {}
	local function add(u)
		if #out < MAX_UNITS and UnitExists(u) then
			u = Stable(u)
			if not seen[u] then
				seen[u] = true
				out[#out + 1] = u
			end
		end
	end
	local name = XUI.Readable(targetName)
	if type(name) ~= "string" or name == "" then
		-- the name is secret: every unit it may be, but you only when nobody else
		-- is there - an aura running out on you would otherwise pass for the dispel
		for i = 1, #FIXED do
			if FIXED[i] ~= "player" then add(FIXED[i]) end
		end
		if #out == 0 then add("player") end
		return out
	end
	-- the cast names a unit of another realm "Name-Realm", a unit token does not
	name = name:gsub("%-.*$", "")
	for i = 1, #FIXED do
		local u = FIXED[i]
		if UnitExists(u) and XUI.Probe(UnitName, u) == name then add(u) end
	end
	if #out == 0 then
		for i = 1, 4 do
			local u = "party" .. i
			if UnitExists(u) and XUI.Probe(UnitName, u) == name then add(u) end
		end
		if #out == 0 and IsInRaid() then
			for i = 1, 40 do
				local u = "raid" .. i
				if UnitExists(u) and XUI.Probe(UnitName, u) == name then add(u) break end
			end
		end
	end
	-- the name did not find anyone (a macro, a pet, a changed target): every
	-- unit it could have been is watched
	if #out == 0 then
		for i = 1, #FIXED do add(FIXED[i]) end
	end
	return out
end

--------------------------------------------------------------------------------
-- Message
--------------------------------------------------------------------------------
-- The text for a dispelled aura. A readable name is coloured and put in; a
-- secret one cannot be handled in Lua, so it goes into the format of
-- SetFormattedText, which the client fills in (that path answers a function).
local function Message(db, name)
	local colour = XUI.ColorHex(db.nameColor)
	if IsSecret(name) then
		if not db.text:find("%%s") then return db.text end
		local template = db.text:gsub("%%s", function() return "|cff" .. colour .. "%s|r" end)
		return function(fs) fs:SetFormattedText(template, name) end
	end
	if type(name) ~= "string" or name == "" then return db.textUnknown end
	if not db.text:find("%%s") then return db.text end
	return (db.text:gsub("%%s", function() return "|cff" .. colour .. name .. "|r" end))
end

function M:Show(name, icon, hold)
	local d, db = Display(), self.db
	d.anim:Stop()
	d:ApplyStyle(db.font)
	local text = Message(db, name)
	if type(text) == "function" then
		-- a secret name: the client fills it in, and the width cannot be measured
		d.text:SetText("")
		if not pcall(text, d.text) then
			d.text:SetText(db.textUnknown)
		end
		if not pcall(d.Fit, d) then d:SetSize(360, 30) end
	else
		d:SetText(text)
	end
	if db.showIcon and icon then
		d.icon:SetSize(db.iconSize, db.iconSize)
		d.icon:SetTexture(icon)
		d.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		d.icon:Show()
	else
		d.icon:Hide()
	end
	d:SetAlpha(1)
	d:Show()
	if not hold then
		d.fadeOut:SetStartDelay(db.hold)
		d.fadeOut:SetDuration(math.max(0.05, db.fade))
		d.anim:Play()
	end
end

--------------------------------------------------------------------------------
-- Detection
--------------------------------------------------------------------------------

local function Finish(mine)
	if pending ~= mine then return end
	pending = nil
	M:UnregisterEvent("UNIT_AURA")
	local rec = mine.ok and mine.hit
	M:Trace("window over: cast succeeded %s, aura gone %s", mine.ok == true, mine.hit ~= nil)
	if not rec then
		last = mine.hit and "an aura went but the cast did not succeed" or (mine.ok and "cast succeeded, no aura removal seen" or "cast never succeeded")
		return
	end
	seen.shown = seen.shown + 1
	last = "shown"
	-- what was removed is not always known; the dispel spell's own icon would
	-- say the wrong thing, so without an icon of the aura there is none
	M:Show(rec.name, rec.icon)
	local name = XUI.Readable(rec.name)
	XUI.Audio:Play(M.db.alert, type(name) == "string" and (name .. " dispelled") or M.db.textUnknown)
end

-- the alert shows the moment both halves are in (cast succeeded, aura gone)
local function TryFinish(mine)
	if mine == pending and mine.ok and mine.hit then Finish(mine) end
end

local function OnAura(_, _, unit, info)
	local mine = pending
	if not mine or not unit or mine.hit then return end
	seen.auraEvents = seen.auraEvents + 1
	M:Trace("UNIT_AURA on %s, payload secret: %s", unit, IsSecret(info))
	local entry = mine.snaps[unit]
	if not entry then
		-- the same unit under another token
		for token, e in pairs(mine.snaps) do
			if XUI.Ask(UnitIsUnit, unit, token) == true then
				entry = e
				break
			end
		end
	end
	if not entry then return end
	seen.matched = seen.matched + 1
	if IsSecret(info) or type(info) ~= "table" or XUI.IsSecretTable(info) then
		seen.secretPayload = seen.secretPayload + 1
		return
	end
	local removed = info.removedAuraInstanceIDs
	if M.trace then
		local added = info.addedAuras
		local a1 = type(added) == "table" and not IsSecret(added) and not XUI.IsSecretTable(added) and added[1] or nil
		local function N(t) return IsSecret(t) and "<secret>" or (type(t) == "table" and (XUI.IsSecretTable(t) and "<secret table>" or #t) or tostring(t)) end
		M:Trace("  removed: %s, added: %s, updated: %s, full: %s", N(removed), N(added), N(info.updatedAuraInstanceIDs), info.isFullUpdate)
		if type(a1) == "table" then M:Trace("  first added aura: id %s, name %s, icon %s", a1.auraInstanceID, a1.name, a1.icon) end
	end
	-- nothing was removed in this update
	if removed == nil then return end
	if IsSecret(removed) or type(removed) ~= "table" or XUI.IsSecretTable(removed) then
		-- the ids are unreadable, but something went off this unit
		seen.removals = seen.removals + 1
		local friendly = XUI.Ask(UnitIsFriend, "player", unit)
		local db = M.db
		local wanted
		if friendly == nil then wanted = db.friendly or db.enemy else wanted = (friendly and db.friendly) or (not friendly and db.enemy) end
		M:Trace("  something was removed from %s (ids unreadable); wanted: %s", unit, wanted)
		if wanted then
			mine.hit = {}
			TryFinish(mine)
		end
		return
	end
	for i = 1, #removed do
		local id = removed[i]
		if not IsSecret(id) then
			-- a blind unit (no readable list) takes any removal
			local rec = entry.ids[id] or (entry.blind and {})
			if rec then
				seen.removals = seen.removals + 1
				local friendly = XUI.Ask(UnitIsFriend, "player", unit)
				local db = M.db
				local wanted
				if friendly == nil then wanted = db.friendly or db.enemy else wanted = (friendly and db.friendly) or (not friendly and db.enemy) end
				if wanted then
					mine.hit = rec
					TryFinish(mine)
					return
				end
			end
		end
	end
end

local function OnSent(_, _, _, target, _, spellID)
	if IsSecret(spellID) or not DISPELS[spellID] then return end
	seen.sent = seen.sent + 1
	local snaps = {}
	local units = Candidates(target)
	M:Trace("dispel cast sent (spell %s) at %s: watching %d unit(s)", spellID, target, #units)
	for i = 1, #units do
		local ids, readable = Snapshot(units[i])
		snaps[units[i]] = { ids = ids, blind = not readable }
		local n = 0
		for _ in pairs(ids) do n = n + 1 end
		M:Trace("  %s: %d aura(s) read, readable: %s, through: %s", units[i], n, readable, seen.route)
	end
	if #units == 0 then
		last = "cast seen, but no unit to watch"
		return
	end
	local mine = { snaps = snaps, spell = spellID }
	pending = mine
	last = "watching " .. #units .. " unit(s)"
	M:RegisterEvent("UNIT_AURA", OnAura)
	M:After(WINDOW, function() Finish(mine) end)
end

-- Any of our dispels succeeding counts: a talent can swap the spell the cast
-- is reported under, so it need not be the id that was sent.
-- What the unit has now, by instance id; nil when the list cannot be read.
local function CurrentIds(unit)
	local ids, any = {}, false
	local _, ran = Collect(unit, function(a)
		local id = a.auraInstanceID
		if id ~= nil and not IsSecret(id) then
			ids[id] = true
			any = true
		end
	end)
	if not any then return ran and ids or nil end
	return ids
end

-- The remembered list against the one now: an aura that is gone was taken off.
local function CompareLists(mine)
	if pending ~= mine or mine.hit then return end
	for unit, entry in pairs(mine.snaps) do
		if not entry.blind then
			local now = CurrentIds(unit)
			if now then
				M:Trace("  list compare on %s: was read, now read", unit)
				for id, rec in pairs(entry.ids) do
					if not now[id] then
						seen.byList = seen.byList + 1
						mine.hit = rec
						TryFinish(mine)
						return
					end
				end
			end
		end
	end
end

local function OnSucceeded(_, _, _, _, spellID)
	local mine = pending
	if mine and not IsSecret(spellID) and DISPELS[spellID] then
		mine.ok = true
		mine.castSpell = spellID
		TryFinish(mine)
		M:Trace("cast succeeded (spell %s), aura seen going yet: %s", spellID, mine.hit ~= nil)
		if not mine.hit then M:After(0.15, function() CompareLists(mine) end) end
	end
end

function M:OnEnable()
	Display()
	self:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player", OnSent)
	self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", OnSucceeded)
end

function M:OnDisable()
	pending = nil
end

function M:OnRefresh()
	if not (display or self:IsPreview()) then return end
	local d = Display()
	XUI.Movers:Apply(d)
	if self:IsPreview() then
		self:Show("Power Word: Shield", 135940, true)
	elseif d.anim:IsPlaying() and self:IsRunning() then
		d:ApplyStyle(self.db.font)
	else
		d.anim:Stop()
		d:Hide()
	end
end

-- Shows a sample for a couple of seconds.
function M:Test()
	self:Show("Power Word: Shield", 135940)
end

function M:DebugInfo()
	local n = 0
	for _ in pairs(DISPELS) do n = n + 1 end
	return {
		"tracked dispel spells: " .. n,
		"watching a cast right now: " .. tostring(pending ~= nil),
		("your dispels seen: %d, aura events on a watched unit: %d (of %d seen), auras removed: %d, alerts shown: %d"):format(seen.sent, seen.matched, seen.auraEvents, seen.removals, seen.shown),
		("auras read at the last casts: %d (%d with a secret name), read through: %s"):format(seen.auras, seen.secretNames, tostring(seen.route)),
		("payload secret: %d times, found by list comparison: %d"):format(seen.secretPayload, seen.byList),
		"to see each step as it happens: /xui trace DispelAlert, dispel once, read the chat",
		"last cast: " .. last,
	}
end
