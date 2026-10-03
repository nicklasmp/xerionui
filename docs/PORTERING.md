# Porteringsplan

Hvert legacy-feature flyttes ind i den nye kerne som ét modul: én fil i `XerionUI/Modules/<Kategori>/`, options i `XerionUI_Options/Modules/<Kategori>.lua`, kun fælles style-grupper til border/glow/font/bar/ikon/lyd/position. Ved porteringen ryddes død kode, debug-slash-kommandoer og hardcodede fonts væk, og alle events gøres unit-filtrerede og idle-frie.

**Kilde**: K = KiraUI-afledt (All Rights Reserved, kun personligt brug), I = ItruliaQoL (MIT), X = skrevet til Xerion.
**Status**: ✅ porteret · ⏳ planlagt · ❓ beslut om den skal med · ✖ udgår

## Fase 1 — kerne (færdig)

| Feature | Kilde | Status | Note |
|---|---|---|---|
| Combat Alert | I | ✅ | + valgfri lyd/TTS ved start og slut |
| Combat Timer | I | ✅ | Tikker kun i kamp (legacy kørte `OnUpdate` hver frame) |
| Stoneform Bleed Alert | X | ✅ | Unit-filtreret aura-event, cooldown-event kun mens man bløder |

## Fase 1b — gruppe, kamp og EllesmereUI (færdig, oktober 2026)

Melee Indicator, Death Alert, Externals, Party Interrupts, Co-Tank, Shroud/Mass Invis, CC Tracker, Aggro Check, Bloodlust Ready og de fem EllesmereUI-tweaks er porteret (se tabellerne). CC Cast Notices udgik.

## Næste runde — klasser

Fase 4 (klasser og specs) er næste runde.

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

## Fase 4 — klasser og specs

| Feature | Kilde | Klasse | Status |
|---|---|---|---|
| Bone Shield (glow, lyd, stack-advarsel) | K | Death Knight (Blood) | ⏳ |
| Dancing Rune Weapon ikon + lyd | K | Death Knight (Blood) | ⏳ |
| Boiling Point | K | Death Knight | ⏳ |
| The Blood is Life / Blood Beast | K | Death Knight (San'layn) | ⏳ |
| Reaper's Mark | K | Death Knight (Deathbringer) | ⏳ |
| Blightfall-kæde, Putrefy / Forbidden Sacrifice | K | Death Knight (Unholy) | ⏳ |
| Control Undead | K | Death Knight | ⏳ |
| Fiery Brand | K | Demon Hunter (Vengeance) | ⏳ |
| Brewmaster (orbs, dodge, elixir) | K | Monk | ⏳ |
| Shining Light, Paladin Aura | K | Paladin | ⏳ |
| Mage-features | K | Mage | ⏳ |
| Elemental Blast-buffs | K | Shaman | ⏳ |
| Well-Honed Instincts, Bear Form-reminder | K | Druid | ⏳ |
| Spell Reflect-skade | K | Warrior | ⏳ |
| Defensive Indicator | I | alle | ⏳ |
| Self Dispel Alert | I | alle | ⏳ |
| Movement Alert | I | alle | ⏳ |
| Runeforge Alert | I | Death Knight | ⏳ |

Klassemoduler får `classes = { ... }` og vises kun på den klasse. Kun de specs/talenter, du faktisk spiller, bør porteres — sig til, hvilke du bruger.

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
