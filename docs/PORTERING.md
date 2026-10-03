# Porteringsplan

Hvert legacy-feature flyttes ind i den nye kerne som ét modul: én fil i `XerionUI/Modules/<Kategori>/`, options i `XerionUI_Options/Modules/<Kategori>.lua`, kun fælles style-grupper til border/glow/font/bar/ikon/lyd/position. Ved porteringen ryddes død kode, debug-slash-kommandoer og hardcodede fonts væk, og alle events gøres unit-filtrerede og idle-frie.

**Kilde**: K = KiraUI-afledt (All Rights Reserved, kun personligt brug), I = ItruliaQoL (MIT), X = skrevet til Xerion.
**Status**: ✅ porteret · ⏳ planlagt · ❓ beslut om den skal med · ✖ udgår

## Fase 1 — kerne (færdig)

| Feature | Kilde | Status | Note |
|---|---|---|---|
| Combat Alert | I | ✖ | Porteret, men fjernet igen efter ønske |
| Combat Timer | I | ✖ | Porteret, men fjernet igen efter ønske |
| Stoneform Bleed Alert | X | ✅ | Unit-filtreret aura-event, cooldown-event kun mens man bløder |

## Fase 1b — gruppe, kamp og EllesmereUI (færdig, oktober 2026)

Melee Indicator, Death Alert, Externals, Party Interrupts, Co-Tank, Shroud/Mass Invis, CC Tracker, Aggro Check, Bloodlust Ready og de fem EllesmereUI-tweaks er porteret (se tabellerne). CC Cast Notices udgik.

## Fase 2 — generelle QoL-indikatorer (simple, mest tekst)

| Feature | Kilde | Status | Note |
|---|---|---|---|
| No Target Indicator | I | ⏳ | Tekst i kamp uden target |
| Stealth Indicator | I | ⏳ | |
| Stance Alert | I | ⏳ | Druid-form / warrior-stance |
| Repair Indicator | I | ⏳ | |
| Pet Missing / Pet Passive | I | ⏳ | Kan samles i ét "Pet"-modul |
| Melee Indicator | I | ✅ | |
| Character Indicator | I | ⏳ | |
| Potion Alert | I | ⏳ | |
| Death Alert | I | ✅ | |
| Prevent Release | I | ⏳ | |
| Cursor Circle | I | ❓ | EllesmereUI har selv cursor-features |
| Misc (AH-filtre m.m.) | I | ⏳ | AH-filteret skriver Blizzards globale `AUCTION_HOUSE_DEFAULT_FILTERS` — tjek for taint |
| Flying Bar | I | ❓ | Legacy havde en global-lækage (`OnEvent`) |

## Fase 3 — gruppe og Mythic+

| Feature | Kilde | Status | Note |
|---|---|---|---|
| Externals | K | ✅ | Ikon-række: oplagt test af `CreateIcon` + glow |
| Party Interrupts | K | ✅ | Stor (1.600 linjer); bar- og ikon-layout |
| Co-Tank | K | ✅ | Bar + debuff-ikoner |
| Shroud / Mass Invis bar | K | ✅ | Bar-modul: første rigtige bruger af `CreateBar` |
| CC Tracker (bars) | K | ✅ | Midnight AuraContainer-baseret |
| CC Cast Notices | K | ✖ | Virker ikke i Midnight (cast-ID'er er redigerede) — jf. legacy README |
| Aggro Check | K | ✅ | |
| Bloodlust ready (lyd/TTS) | K | ✅ | Kan bruge `G.Alert` direkte |
| Focus Interrupt Indicator | I | ⏳ | Overlapper med EUI FocusKick Sound — vælg én |
| Focus Target Marker | I | ⏳ | |
| Healer Mana Indicator | I | ⏳ | |
| Summon Helper | I | ⏳ | |
| Keystone Lister | I | ⏳ | |
| LFG Improvements | I | ⏳ | |
| Raid Frame Manager | I | ❓ | Erstatter Blizzards manager — stor |
| Dungeon Teleports | I | ❓ | Du har allerede TeleportMenu installeret |
| Key Vendor | K | ⏳ | |
| Macro Factory | I | ❓ | |

## Fase 4 — klasser og specs (færdig, oktober 2026)

Alle porteret og markeret `untested` i optionspanelet, indtil de er set i spillet. De delte byggeklodser (timer-ikon, damage-meter-tekst) ligger i `Modules/Class/Kit.lua`.

| Feature | Kilde | Klasse | Modul | Status |
|---|---|---|---|---|
| Bone Shield (glow, lyd, stack-advarsel, eget ikon) | K | Death Knight (Blood) | BoneShield | ✅ |
| Dancing Rune Weapon lyd | K | Death Knight (Blood) | DRWSound | ✅ |
| DRW-ikonbytte (Bone Shield-art i Cooldown Manager) | K | Death Knight (Blood) | BoneShield (`customArt`) | ✅ |
| Boiling Point | K | Death Knight (Blood) | BoilingPoint | ✅ |
| The Blood is Life | K | Death Knight (San'layn) | BloodIsLife | ✅ |
| Blood Beast-skade | K | Death Knight (San'layn) | BloodBeast | ✅ |
| Reaper's Mark | K | Death Knight (Deathbringer) | ReapersMark | ✅ |
| Blightfall-kæde | K | Death Knight (Unholy) | Blightfall | ✅ |
| Putrefy / Forbidden Sacrifice | K | Death Knight (Unholy) | ForbiddenSacrifice | ✅ |
| Control Undead | K | Death Knight | ControlUndead | ✅ |
| Runeforge Alert | I | Death Knight | RuneforgeAlert | ✅ |
| Fiery Brand | K | Demon Hunter (Vengeance) | FieryBrand | ✅ |
| Brewmaster (orbs, dodge, elixir) | K | Monk | ExpelHarmOrbs, BrewDodge, ElixirProc | ✅ |
| Shining Light | K | Paladin (Protection) | ShiningLight | ✅ |
| Paladin Aura | K | Paladin | PaladinAura | ✅ |
| Alter Time-helbred | K | Mage | AlterTime | ✅ |
| Elemental Blast-bogstaver | K | Shaman | ElementalBlast | ✅ |
| Well-Honed Instincts-lyd | K | Druid | WellHoned | ✅ |
| Bear Form-påmindelse | K | Druid (Guardian) | BearForm | ✅ |
| Spell Reflect-skade | K | Warrior | SpellReflect | ✅ |
| Defensive Indicator, Self Dispel Alert, Movement Alert | I | alle | – | ✖ porteret, men fjernet igen efter ønske (oktober 2026) |

Afvigelser fra legacy: de egne træk-/lås-/CDM-anker-indstillinger er erstattet af movers (`/xui unlock`); farver, fonte, rammer, glow og lyd går gennem de fælles blokke.

## Fase 5 — EllesmereUI Tweaks

Alle får `requires = "EllesmereUI…"`, så de kun kører med det relevante EllesmereUI-modul.

| Feature | Kilde | Status | Note |
|---|---|---|---|
| Nameplates (dispel-glow uden purge, shield amount) | K | ✅ | Hooker EllesmereUI-internals — skrøbeligt ved EUI-opdateringer |
| FocusKick Sound | K | ✅ | Ringede aldrig i legacy (slettede hjælpefunktioner) - rettet |
| Focus Cast Bar (M+ Tools) | K | ✅ | Finder EUI's bar via gemt position — skrøbeligt |
| Targeted Spell Bars | K | ✅ | |
| Party Frames (health-tekst, debuff-stack placering) | K | ✅ | Health-teksten lyttede på alle units - nu unit-filtreret |
| Damage Meter item level | K | ⏳ | |
| Cooldown Manager anchor / `/cdm` | K/I | ❓ | |

## Udgår

| Feature | Grund |
|---|---|
| VersionCheck | Tjekker KiraUI Installer-versionen og broadcaster i gruppen |
| KiraFPS-probes | Udviklerværktøj til Kiras profiler |
| Dungeon-profiler | Modulet (Dungeon Reminders) er fjernet |
| 40+ debug-slash-kommandoer | Erstattes af `/xui` og preview i panelet |
| Quazii-lydpakke og -font, Kira-medier | Ubrugte eller licens-uklare |

## Fremgangsmåde pr. modul

1. Læs legacy-filen og noter, hvad den reelt gør i Midnight (secret values, events).
2. Skriv modulet efter skabelonen i `docs/ARCHITECTURE.md` med `XUI.Templates`-blokke.
3. Byg options udelukkende af `G.*`-grupper plus modulets egne adfærds-indstillinger.
4. Tilføj modulet til `XerionUI.toc` og options-filen til `XerionUI_Options.toc`.
5. `npm test` og `npm run shots` i `tools/` — derefter test i spillet med BugSack.
6. Commit pr. modul.
