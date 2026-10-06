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
--   3. The cast SUCCEEDED and something was removed -> the alert shows. A cast
--      that dispelled nothing (no valid aura, resisted) stays silent.
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
local pending          -- { snaps = { [unit] = { [auraInstanceID] = rec } }, spell, ok, hit }

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
local function Snapshot(unit)
	local AU = AuraUtil
	if not (AU and AU.ForEachAura) then return nil end
	local snap, any = {}, false
	local function Visit(a)
		if not a then return end
		local id = a.auraInstanceID
		if id ~= nil and not IsSecret(id) then
			snap[id] = { name = a.name, icon = a.icon }
			any = true
		end
	end
	pcall(AU.ForEachAura, unit, "HELPFUL", nil, Visit, true)
	pcall(AU.ForEachAura, unit, "HARMFUL", nil, Visit, true)
	return any and snap or nil
end

local FIXED = { "target", "focus", "mouseover", "softenemy", "softfriend", "player" }

-- Units the spell can have been aimed at, from the name UNIT_SPELLCAST_SENT gives.
local function Candidates(targetName)
	local out, seen = {}, {}
	local function add(u)
		if #out < MAX_UNITS and not seen[u] and UnitExists(u) then
			seen[u] = true
			out[#out + 1] = u
		end
	end
	local name = XUI.Readable(targetName)
	if type(name) ~= "string" or name == "" then
		for i = 1, #FIXED do add(FIXED[i]) end
		return out
	end
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
	return out
end

--------------------------------------------------------------------------------
-- Message
--------------------------------------------------------------------------------
local function Message(db, name)
	if type(name) ~= "string" or IsSecret(name) then return db.textUnknown end
	if not db.text:find("%%s") then return db.text end
	local colored = CreateColor(XUI.UnpackColor(db.nameColor)):WrapTextInColorCode(name)
	return (db.text:gsub("%%s", function() return colored end))
end

function M:Show(name, icon, hold)
	local d, db = Display(), self.db
	d.anim:Stop()
	d:ApplyStyle(db.font)
	d:SetText(Message(db, name))
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
	if not rec then return end
	M:Show(rec.name, rec.icon)
	local name = XUI.Readable(rec.name)
	XUI.Audio:Play(M.db.alert, type(name) == "string" and (name .. " dispelled") or M.db.textUnknown)
end

local function OnAura(_, _, unit, info)
	local mine = pending
	if not mine or not unit then return end
	local snap = mine.snaps[unit]
	if not snap or type(info) ~= "table" or XUI.IsSecretTable(info) then return end
	local removed = info.removedAuraInstanceIDs
	if type(removed) ~= "table" or XUI.IsSecretTable(removed) or mine.hit then return end
	for i = 1, #removed do
		local id = removed[i]
		local rec = not IsSecret(id) and snap[id]
		if rec then
			local friendly = XUI.Ask(UnitIsFriend, "player", unit)
			if (friendly and M.db.friendly) or (not friendly and M.db.enemy) then
				mine.hit = rec
				return
			end
		end
	end
end

local function OnSent(_, _, _, target, _, spellID)
	if IsSecret(spellID) or not DISPELS[spellID] then return end
	local snaps, any = {}, false
	local units = Candidates(target)
	for i = 1, #units do
		local s = Snapshot(units[i])
		if s then
			snaps[units[i]] = s
			any = true
		end
	end
	if not any then return end
	local mine = { snaps = snaps, spell = spellID }
	pending = mine
	M:RegisterEvent("UNIT_AURA", OnAura)
	M:After(WINDOW, function() Finish(mine) end)
end

local function OnSucceeded(_, _, _, _, spellID)
	if pending and not IsSecret(spellID) and pending.spell == spellID then pending.ok = true end
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
	}
end
