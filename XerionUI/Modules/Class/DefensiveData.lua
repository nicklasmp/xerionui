--------------------------------------------------------------------------------
-- Defensive Indicator data: the defensive auras per class and the external
-- ones other players put on you.
--   auraId     the aura on you
--   spellId    the spell that gives it (what "known" is asked of), if different
--   category   MASSIVE | MAJOR (default) | MINOR; externals are EXTERNAL
--   defaultOff not tracked until switched on
-- Ported from ItruliaQoL (MIT, (c) Itrulia).
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI

local DEFENSIVE = {
	DEATHKNIGHT = {
		{ auraId = 48707 }, -- Anti-Magic Shell
		{ auraId = 444741, spellId = 48707 }, -- Anti-Magic Shell, the Horsemen's cast on you
		{ auraId = 48792, category = "MASSIVE" }, -- Icebound Fortitude
		{ auraId = 49039, category = "MINOR", defaultOff = true }, -- Lichborne
		{ auraId = 55233 }, -- Vampiric Blood
		{ auraId = 101568, spellId = 178819, category = "MINOR" }, -- Dark Succor
	},
	DEMONHUNTER = {
		{ auraId = 442715, spellId = 442714, category = "MINOR", defaultOff = true }, -- Blade Ward
		{ auraId = 212800 }, -- Blur
		{ auraId = 1266616, spellId = 1266329, category = "MINOR", defaultOff = true }, -- Demon Muzzle
		{ auraId = 394933, spellId = 388111, category = "MINOR", defaultOff = true }, -- Demon Muzzle
		{ auraId = 427912, spellId = 258920, category = "MINOR", defaultOff = true }, -- Immolation Aura
		{ auraId = 258920, category = "MINOR", defaultOff = true }, -- Immolation Aura
		{ auraId = 187827, category = "MASSIVE" }, -- Metamorphosis
		{ auraId = 207771 }, -- Fiery Brand
		{ auraId = 209426, spellId = 196718, defaultOff = true }, -- Darkness
	},
	DRUID = {
		{ auraId = 22812 }, -- Barkskin
		{ auraId = 22842, category = "MINOR" }, -- Frenzied Regeneration
		{ auraId = 192081, category = "MINOR", defaultOff = true }, -- Ironfur
		{ auraId = 61336, category = "MASSIVE" }, -- Survival Instincts
		{ auraId = 393903, spellId = 377842, category = "MINOR", defaultOff = true }, -- Ursine Vigor
		{ auraId = 1261872, spellId = 1261867, category = "MINOR" }, -- Heart of the Wild
	},
	EVOKER = {
		{ auraId = 404381, spellId = 404195, category = "MASSIVE" }, -- Defy Fate
		{ auraId = 363916 }, -- Obsidian Scales
		{ auraId = 374349 }, -- Renewing Blaze
	},
	HUNTER = {
		{ auraId = 186265, category = "MASSIVE" }, -- Aspect of the Turtle
		{ auraId = 472708, spellId = 472707, category = "MINOR", defaultOff = true }, -- Shell Cover
		{ auraId = 264735 }, -- Survival of the Fittest
	},
	MAGE = {
		{ auraId = 342246, spellId = 342245, category = "MINOR" }, -- Alter Time
		{ auraId = 235313, category = "MINOR", defaultOff = true }, -- Blazing Barrier
		{ auraId = 11426, category = "MINOR", defaultOff = true }, -- Ice Barrier
		{ auraId = 45438, category = "MASSIVE" }, -- Ice Block
		{ auraId = 414658, spellId = 45438, category = "MASSIVE" }, -- Ice Cold
		{ auraId = 235450, category = "MINOR", defaultOff = true }, -- Prismatic Barrier
		{ auraId = 449336, spellId = 449330 }, -- Merely a Setback
		{ auraId = 1309793, spellId = 1309497, category = "MINOR" }, -- Amplified Refraction
	},
	MONK = {
		{ auraId = 122783 }, -- Diffuse Magic
		{ auraId = 115203, category = "MASSIVE" }, -- Fortifying Brew
		{ auraId = 120954, spellId = 115203, category = "MASSIVE" }, -- Fortifying Brew
		{ auraId = 125174, spellId = 122470 }, -- Touch of Karma
		{ auraId = 132578 }, -- Invoke Niuzao, the Black Ox
		{ auraId = 322507, category = "MINOR" }, -- Celestial Brew
		{ auraId = 432180, spellId = 432181, category = "MINOR", defaultOff = true }, -- Dance of the Wind
		{ auraId = 1241059, category = "MINOR" }, -- Celestial Infusion
	},
	PALADIN = {
		{ auraId = 498, category = "MINOR" }, -- Divine Protection
		{ auraId = 403876, category = "MINOR" }, -- Divine Protection
		{ auraId = 642, category = "MASSIVE" }, -- Divine Shield
		{ auraId = 184662, category = "MINOR", defaultOff = true }, -- Shield of Vengeance
		{ auraId = 31850, category = "MASSIVE" }, -- Ardent Defender
		{ auraId = 86659 }, -- Guardian of Ancient Kings
	},
	PRIEST = {
		{ auraId = 114216, spellId = 108945, category = "MINOR", defaultOff = true }, -- Angelic Bulwark
		{ auraId = 114214, spellId = 108945, category = "MINOR", defaultOff = true }, -- Angelic Bulwark
		{ auraId = 19236, category = "MINOR" }, -- Desperate Prayer
		{ auraId = 47585, category = "MASSIVE" }, -- Dispersion
		{ auraId = 586, category = "MINOR" }, -- Fade
		{ auraId = 45242, spellId = 45243, category = "MINOR", defaultOff = true }, -- Focused Will
		{ auraId = 426401, spellId = 45243, category = "MINOR", defaultOff = true }, -- Focused Will
		{ auraId = 193065, spellId = 193063, category = "MINOR" }, -- Protective Light
		{ auraId = 27827, spellId = 20711, category = "MASSIVE" }, -- Spirit of Redemption
	},
	ROGUE = {
		{ auraId = 31224, category = "MASSIVE" }, -- Cloak of Shadows
		{ auraId = 5277 }, -- Evasion
		{ auraId = 1966, category = "MINOR" }, -- Feint
		{ auraId = 185311, category = "MINOR" }, -- Crimson Vial
	},
	SHAMAN = {
		{ auraId = 108271 }, -- Astral Shift
		{ auraId = 260881, spellId = 260878, category = "MINOR" }, -- Spirit Wolf
	},
	WARLOCK = {
		{ auraId = 108416 }, -- Dark Pact
		{ auraId = 104773 }, -- Unending Resolve
		{ auraId = 132413, spellId = 108503, category = "MINOR" }, -- Shadow Bulwark
		{ auraId = 387636, spellId = 385899, category = "MINOR" }, -- Soulburn: Healthstone
		{ auraId = 389614, spellId = 389609, category = "MINOR" }, -- Abyss Walker
	},
	WARRIOR = {
		{ auraId = 118038 }, -- Die by the Sword
		{ auraId = 184364 }, -- Enraged Regeneration
		{ auraId = 190456, category = "MINOR" }, -- Ignore Pain
		{ auraId = 1277297, spellId = 190456, category = "MINOR" }, -- Ignore Pain
		{ auraId = 147833, spellId = 3411, category = "MINOR" }, -- Intervene
		{ auraId = 23920, category = "MINOR" }, -- Spell Reflection
		{ auraId = 385391, spellId = 23920, category = "MINOR" }, -- Spell Reflection
		{ auraId = 871, category = "MASSIVE" }, -- Shield Wall
		{ auraId = 202147, spellId = 29838, category = "MINOR", defaultOff = true }, -- Second Wind
	},
}

local EXTERNAL = {
	-- Druid
	{ auraId = 102342 }, -- Ironbark
	-- Evoker
	{ auraId = 357170 }, -- Time Dilation
	-- Hunter
	{ auraId = 53480 }, -- Roar of Sacrifice
	-- Monk
	{ auraId = 116849 }, -- Life Cocoon
	-- Paladin
	{ auraId = 1022 }, -- Blessing of Protection
	{ auraId = 1309794 }, -- Blessing of Protection
	{ auraId = 6940 }, -- Blessing of Sacrifice
	{ auraId = 204018 }, -- Blessing of Spellwarding
	-- Priest
	{ auraId = 47788 }, -- Guardian Spirit
	{ auraId = 33206 }, -- Pain Suppression
}

XUI.DefensiveData = { defensive = DEFENSIVE, external = EXTERNAL }
