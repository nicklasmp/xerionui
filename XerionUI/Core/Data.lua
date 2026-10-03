--------------------------------------------------------------------------------
-- XerionUI - Core/Data.lua
-- Game data shared by several modules.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI

local Data = {}
XUI.Data = Data

--------------------------------------------------------------------------------
-- Interrupts
--------------------------------------------------------------------------------
-- [spellID] = cooldown (seconds), class, and for a healer-length kick its
-- healer cooldown; `icon` points a pet's spell at the icon players know.
Data.KICKS = {
	[47528]   = { cd = 12, class = "DEATHKNIGHT", name = "Mind Freeze" },
	[183752]  = { cd = 15, class = "DEMONHUNTER", name = "Disrupt" },
	[106839]  = { cd = 15, class = "DRUID", name = "Skull Bash" },
	[78675]   = { cd = 60, class = "DRUID", name = "Solar Beam" },
	[351338]  = { cd = 40, class = "EVOKER", name = "Quell" },
	[147362]  = { cd = 24, class = "HUNTER", name = "Counter Shot" },
	[187707]  = { cd = 15, class = "HUNTER", name = "Muzzle" },
	[2139]    = { cd = 21, class = "MAGE", name = "Counterspell" },
	[116705]  = { cd = 15, class = "MONK", name = "Spear Hand Strike" },
	[96231]   = { cd = 15, class = "PALADIN", name = "Rebuke" },
	[15487]   = { cd = 45, class = "PRIEST", name = "Silence" },
	[1766]    = { cd = 15, class = "ROGUE", name = "Kick" },
	[57994]   = { cd = 12, healerCd = 30, class = "SHAMAN", name = "Wind Shear" },
	[6552]    = { cd = 13.5, class = "WARRIOR", name = "Pummel" },
	[386071]  = { cd = 90, class = "WARRIOR", name = "Disrupting Shout" },
	[19647]   = { cd = 24, class = "WARLOCK", name = "Spell Lock" },
	[89766]   = { cd = 30, class = "WARLOCK", name = "Axe Toss" },
	[119910]  = { cd = 24, class = "WARLOCK", icon = 19647 },
	[132409]  = { cd = 24, class = "WARLOCK", icon = 19647 },
	[1276467] = { cd = 24, class = "WARLOCK", icon = 19647 },
	[119914]  = { cd = 30, class = "WARLOCK", icon = 89766 },
}

-- A party member's kick by class, before their spec is known.
Data.CLASS_KICK = {
	DEATHKNIGHT = 47528, DEMONHUNTER = 183752, DRUID = 106839, EVOKER = 351338,
	HUNTER = 147362, MAGE = 2139, MONK = 116705, PALADIN = 96231, PRIEST = 15487,
	ROGUE = 1766, SHAMAN = 57994, WARRIOR = 6552, WARLOCK = 19647,
}

-- Specs whose kick differs from their class's (false = no kick).
Data.SPEC_KICK = {
	[102] = 78675,  -- Balance: Solar Beam
	[255] = 187707, -- Survival: Muzzle
	[105] = false, [1468] = false, [65] = false, [256] = false, [257] = false, [270] = false,
}

-- Healer specs of classes whose healers have no interrupt.
Data.HEALER_NO_KICK = { DRUID = true, EVOKER = true, PALADIN = true, PRIEST = true, MONK = true }

Data.HEALER_SPEC = { [65] = true, [105] = true, [256] = true, [257] = true, [264] = true, [270] = true, [1468] = true }

-- What the player may know, in order of preference.
Data.PLAYER_KICKS = {
	DEATHKNIGHT = { 47528 }, DEMONHUNTER = { 183752 }, DRUID = { 78675, 106839 },
	EVOKER = { 351338 }, HUNTER = { 187707, 147362 }, MAGE = { 2139 }, MONK = { 116705 },
	PALADIN = { 96231 }, PRIEST = { 15487 }, ROGUE = { 1766 }, SHAMAN = { 57994 },
	WARRIOR = { 6552 },
}

-- Warlock kicks belong to the pet: the spell to show and the one to poll.
Data.WARLOCK_PET_KICKS = { { pet = 89766, poll = 119914 }, { pet = 19647, poll = 119910 } }

local function SpellKnown(id, bank)
	local SB = C_SpellBook
	if SB and SB.IsSpellKnownOrInSpellBook then
		return XUI.Ask(SB.IsSpellKnownOrInSpellBook, id, bank) == true
	end
	return XUI.IsSpellKnown(id)
end

-- The player's interrupt: the spell to show and the spell whose cooldown to
-- read (different for warlock pets), or nil.
function Data.PlayerKick()
	local class = XUI.playerClass
	if class == "WARLOCK" then
		local petBank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
		for _, k in ipairs(Data.WARLOCK_PET_KICKS) do
			if petBank and SpellKnown(k.pet, petBank) then return k.pet, k.poll end
		end
		if SpellKnown(132409) then return 19647, 132409 end
		return nil
	end
	for _, id in ipairs(Data.PLAYER_KICKS[class] or {}) do
		if SpellKnown(id) then return id, id end
	end
	return nil
end
