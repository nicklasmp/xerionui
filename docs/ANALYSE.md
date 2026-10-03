# Analyse af XerionUI Plugin v1.20 (ChatGPT-versionen)

*Gennemgået 3. oktober 2026. Den gamle kode ligger uændret i `legacy/` som reference.*

## Konklusion: ny kerne, features porteres

Jeg anbefaler (og har bygget) en **ny, ren kerne**, hvor features flyttes over modul for modul. Det er ikke "start helt forfra": feature-logikken (især Midnight-håndteringen af secret values) er det værdifulde i den gamle kode og genbruges. Det, der skiftes ud, er fundamentet.

Begrundelse i én sætning: v1.20 er ikke ét addon, men **tre addons syet sammen uden at blive ensrettet**. Hvert lag har sit eget options-UI, sin egen database, sine egne profiler og sine egne style-felter. Dit ønske om ensartede border/glow/font/texture-muligheder på tværs kan ikke opnås uden at erstatte alle tre lag. Så er det billigere at bygge laget én gang, rigtigt.

## Hvad v1.20 består af

| Lag | Kilde | Omfang | Licens |
|---|---|---|---|
| Kira-moduler (`XerionUI-Plugin_*.lua`) | KiraUI-Plugin, omdøbt | ~21.000 linjer, 38 filer | **All Rights Reserved** |
| Kira options-vindue | KiraUI-Plugin_Options | 8.264 linjer i én fil + 861 linjers edit mode | All Rights Reserved |
| Itrulia-moduler (`src/`) | ItruliaQoL | ~24.000 linjer, 29 moduler inkl. to sæt options pr. modul og 2.610 linjers EllesmereUI-integration | MIT |
| Biblioteker | Ace3 m.fl. | 20 biblioteker, 1,1 MB (heraf Ace3 ≈15.300 linjer) | diverse |

### Dobbelt (og tredobbelt) infrastruktur

- **3 options-UI'er**: Kiras eget vindue (`/xqol`), AceConfigDialog (`/xui`), og Itrulias indlejring i EllesmereUI's panel. Hvert Itrulia-modul har sine options skrevet **to gange** (`options.ace.lua` + `options.eui.lua`).
- **2 databaser**: `XerionUIChangesDB` (Kira) og `XerionUIFeaturesDB` (AceDB).
- **2 profilsystemer + 2 import/export-formater**: Kiras snapshot-profiler (`!XerionUI:1!`) og AceDB-profiler med LibDualSpec (AceSerializer).
- **4 mover-systemer**: Kiras egen drag + edit mode, LibEditMode, ElvUI-movers og EllesmereUI unlock mode.
- **3 glow-motorer**: Kiras egen "ants"-glow, LibCustomGlow og lånte kald ind i EllesmereUI's glow-motor.
- **2 slash-familier**: `/xqol /xerion /kc /xerionplugin` og `/xui` (med en dispatch-hack imellem), plus **40+ debug-slash-kommandoer** (`/xerionboil`, `/xerionmaps`, `/xerionzone` …).

### Inkonsistente style-indstillinger

Samme koncept hedder noget forskelligt i næsten hvert modul:

- Border: `border = {r,g,b,a}` (Blood is Life), `borderColor` + `borderSize` (Externals, Stoneform), `border = true` + `borderSize` + `borderColor` (CC Bars, Shroud), `debuffBorder` + `debuffBorderSize` (Co-Tank).
- Tekststørrelse: `textSize`, `durSize`, `fontSize`, `size`, `nameSize`, `stackSize`.
- Glow: `glow` + `glowType` + `glowColor` + `glowThickness`, men `procGlow` + `procGlowColor` andre steder.
- Farver: arrays `{1, 0, 0, 1}` i Kira-delen, `{r=, g=, b=, a=}` i Itrulia-delen.
- Font: Itrulia hardcoder `GothamNarrowBlack` ved frame-oprettelse; Kira har en global override; nogle Kira-moduler har fjernet font-valget helt.

## Død kode (verificeret)

- **18 options-sider uden reference** i Kira-vinduet (Player, Focus, Buff Watch, Combat Text, Crosshair, Raid Markers, Secondary Stats, Inspect, MDI Teleport, Healer External …): **2.183 linjer**.
- **Dungeon Reminders-siden** (modulet er fjernet, siden er uden reference): **1.498 linjer**.
- I alt ≈ **45 % af options-filen** kan ikke nås.
- `ns.ApplyAllSettings()` kalder ~30 Apply-funktioner for moduler, der ikke findes længere.
- Hele **dungeon-profilsystemet** (opret/skift/slet/import/export) i kernen, selvom modulet er væk.
- **KiraFPS-probes** i hver fil (et udviklerværktøj, der "aldrig shipper").
- **VersionCheck** tjekker stadig *KiraUI Installer*-versionen og sender addon-beskeder i gruppen.
- `Bindings.xml` til den fjernede Healer External.
- Medier: 73 lydfiler (980 KB, Quazii-pakke), Quazii-font, Kira-teksturer, Patreon/Twitch/web-ikoner, Great Vault-kort.
- `src/init.forever.xml` (WoW Forever/classic) indlæses aldrig.

## Fejl fundet

| Fejl | Sted | Konsekvens |
|---|---|---|
| `charDB` skrives som global | `XerionUI-Plugin.lua:1218` | Forurener `_G`; kan kollidere med andre addons |
| `function OnEvent` uden `local` | `src/flying-bar/init.lua:43` | Definerer en global `OnEvent` |
| Combat Timer kører `OnUpdate` hver frame, også uden for kamp | `src/combat-timer/init.lua` | Unødigt CPU-forbrug hele sessionen |
| Stoneform lytter på `UNIT_AURA` for **alle** units og scanner 40 auras med closures pr. event | `XerionUI-Plugin_Stoneform.lua` | Høj CPU i raids |
| `/xui` registreres med en hack, der sender visse ord videre til Itrulia | `XerionUI-Plugin.lua` | Uforudsigelig kommando-adfærd |
| Frame-navnet `XerionUIStoneform` m.fl. er globale | flere filer | Kolliderer, hvis to versioner er installeret |

## Licens — vigtigt hvis du nogensinde vil dele addon'et

- **KiraUI-Plugin**: *All Rights Reserved*. Licensen tillader at ændre din egen kopi til eget brug, men **ikke** at "incorporate its code into another addon" eller redistribuere. v1.20 er netop det. Til personligt brug er det OK; skal XerionUI deles (CurseForge/Wago), skal Kira-afledte features skrives om fra bunden eller have Kiratanks tilladelse.
- **ItruliaQoL**: MIT — må genbruges frit med kreditering (gjort i de porterede moduler og på General-siden).
- **EllesmereUI**: All Rights Reserved — **ingen kode er kopieret**. Den nye kerne er skrevet fra bunden; EllesmereUI bruges kun som reference for ambitionsniveau og via dens offentlige unlock-API.

Den nye kerne og options-UI'et er derfor rent dit eget, og du kan selv vælge licens.

## Hvad den nye kerne løser

| Problem i v1.20 | Ny løsning |
|---|---|
| 3 options-UI'er | Ét panel (`XerionUI_Options`, load-on-demand) |
| 2 databaser, 2 profilsystemer | Én database med profiler, import/export og defaults der strippes ved logout |
| Inkonsistente style-felter | Fælles style-blokke + `Use global style` pr. element; samme option-grupper overalt |
| 3 glow-motorer | Én (LibCustomGlow) bag `XUI.Style:ShowGlow` |
| 4 mover-systemer | Ét positionsformat; egen unlock mode **eller** EllesmereUI's unlock mode |
| Ace3 (≈15.300 linjer bibliotek) | Let eget framework; 6 små biblioteker |
| Deaktiverede moduler koster stadig | Deaktiverede moduler opretter ingen frames og registrerer ingen events |
| Ingen test | Mock-klient-harness der loader begge addons og rører hver kontrol |

Se `docs/ARCHITECTURE.md` for opbygningen og `docs/PORTERING.md` for planen for resten af features.
