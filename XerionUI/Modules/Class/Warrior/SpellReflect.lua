--------------------------------------------------------------------------------
-- Spell Reflect damage (Warrior)
-- "Reflect: 845K" for the damage the spells you reflected did, from Blizzard's
-- damage meter (Overall damage done, compared with the reading before the
-- reflect). The meter is secret in combat, so a reflect in a fight is counted
-- when the fight ends. Every reflect until then adds up.
--
-- WHICH LINES ARE REFLECTS
-- A reflected spell is credited to you under the ENEMY's spell ID. Nothing on
-- the line says "reflected", so a line counts by what it is not: one of your
-- own spells. Yours are anything in your spellbook and anything that did
-- damage in a fight with NO reflect cast in it, learned after every such
-- fight and kept per character (XerionUICharDB.reflect). Until one clean
-- fight has been learned, a line counts only when the same spell also hit YOU
-- (your damage taken) - an enemy spell for certain.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates
local Kit = XUI.ClassKit

local REFLECT = { [23920] = true, [213915] = true } -- Spell Reflection, Mass Spell Reflection

local M = XUI:NewModule("SpellReflect", {
	name = "Spell Reflect Damage",
	desc = "The damage your reflected spells did, from the damage meter.",
	category = "class",
	icon = [[Interface\Icons\Ability_Warrior_ShieldReflection]],
	order = 30,
	classes = { "WARRIOR" },
	untested = true,
	defaults = {
		font = T.Font(22),
		labelColor = { 0.78, 0.61, 0.43, 1 },
		valueColor = { 1, 1, 1, 1 },
		position = T.Position(0, -130),
	},
})

local IsSecret = XUI.IsSecret

local function Store()
	local c = _G.XerionUICharDB
	if not c then return nil end
	local st = c.reflect
	if type(st) ~= "table" then st = {} c.reflect = st end
	if type(st.own) ~= "table" then st.own = {} end
	st.learned = tonumber(st.learned) or 0
	return st
end

local function Known(id)
	local SB = C_SpellBook
	local fn = (SB and SB.IsSpellKnownOrInSpellBook) or _G.IsPlayerSpell
	return fn and XUI.Probe(fn, id) == true or false
end

local taken, takenAt -- damage taken, read once per count while nothing is learned
local function IsReflected(id)
	if REFLECT[id] then return true end
	if Known(id) then return false end
	local st = Store()
	if st and st.own[id] then return false end
	if st and st.learned > 0 then return true end
	if not taken or GetTime() - takenAt > 1 then
		taken, takenAt = Kit.ReadSpells("DamageTaken") or {}, GetTime()
	end
	return taken[id] ~= nil
end

-- a fight without a reflect: everything that did damage in it is yours
local reflected = false

local Learn
Kit.Meter(M, {
	frame = "XUI_SpellReflect",
	label = "Reflect:",
	settle = 7, -- the buff lasts 5 s and the spell still has to fly back
	showFor = 10,
	preview = 845000,
	count = IsReflected,
	isTrigger = function(id) return REFLECT[id] == true end,
	-- a cast with a secret ID may have been a reflect
	onSpell = function(_, id) if IsSecret(id) or REFLECT[id] then reflected = true end end,
	onFightEnd = function(self) self:After(2, function() if reflected then reflected = false else Learn() end end) end,
})

Learn = function()
	local spells = Kit.ReadSpells()
	local st = Store()
	if not (spells and st) then return end
	local any = false
	for id in pairs(spells) do
		if not REFLECT[id] then st.own[id] = true any = true end
	end
	if any then st.learned = st.learned + 1 end
end

function M:OnEnable() self:StartMeterEvents() end

function M:Forget()
	local st = Store()
	if st then st.own, st.learned = {}, 0 end
	self:Print("forgot the learned spells of this character.")
end
