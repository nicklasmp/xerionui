# XerionUI Plugin — tilpasset kopi

## Installation

Pak begge mapper direkte ud i `World of Warcraft/_retail_/Interface/AddOns/`:

- `XerionUI-Plugin` — hovedaddon.
- `XerionUI-Plugin_Options` — indstillinger og Edit Mode, indlæses efter behov.

Åbn indstillingerne med `/xerionplugin` (alias `/xerion`).

## Ændringer i denne version

Følgende funktioner er fjernet fra addonets indlæsning og/eller indstillingsmenu i overensstemmelse med ønskelisten:

- **General:** Vendor Search.
- **EllesmereUI:** Player, Focus, Nameplate Interrupt, Buff Reminders, Damage Meter Stretch og Cursor Circle.
- **Combat:** Cooldown Pulse, Spell History, Cooldown Manager stacks, Trinkets, DoT Coverage, Combat Text, Crosshair, Secondary Stats og Spell Queue.
- **Alerts:** Buff Watch, Augment Rune, Ready Check og Recuperate.
- **Group:** Healer External, Targeted Spells, Raid Markers og Inspect Talents.
- **Mythic+:** Instance Reset, Break Timer, MDI Teleports, MDT Compact, Auto Gossip og Great Vault.
- **Kira Reminders:** Dungeon Alerts/reminders.

Standalone featuremoduler, der alene implementerede disse funktioner, er taget ud af hoved-TOC’en og zippen. Cooldown Pulse, Spell History, Instance Reset og Break Timer lå indlejret i corefilen; deres konfigurationssider er fjernet, og de tvinges fra ved opstart. Player/Focus EUI-indstillinger nulstilles, herunder debuff borders, fokusmarkør/range fade og den præcise debufftimer, som pluginet eksponerede.

**Auto Buy** er bevaret, selvom den delte tidligere en optionsside med Auto Gossip. Den har nu sin egen Auto Buy-side. Andre funktioner og modulets indstillinger er bevaret.



## Struktur, manifest og afhængigheder

Hovedmanifestet `XerionUI-Plugin.toc` indeholder client interface-versionerne 120000, 120001, 120005, 120007 og 120100, `AllowLoadGameType: mainline`, samt saved variables `XerionUIChangesDB` og `XerionUIChangesCharDB`. Det indlæser først LibStub, LibSerialize og LibDeflate, derefter core og de resterende featuremoduler. Options-addonets TOC afhænger af `XerionUI-Plugin` og har `LoadOnDemand: 1`; Edit Mode indlæses før Options UI.

`Libs/` indeholder de tre indlejrede biblioteker med licenser. `Media/` indeholder resterende teksturer, billeder og lyd. `Bindings.xml` indeholder healer-external tastaturbindingen. Forfatterkrediteringer og tredjepartslicenser er bevaret; originalens Wago-ID er fjernet.

TOC’ens valgfrie integrationer omfatter ElvUI, EllesmereUI og relevante EllesmereUI-moduler. De er ikke nødvendige for de øvrige selvstændige funktioner. De funktioner, der er tilbage, omfatter EllesmereUI nameplates/party health/targeted spell bars, lust/potion/eksterne cooldowns, party interrupts/co-tank/shroud/Trix, CC tracker, klasseværktøjer, keystone vendor/Auto Buy og øvrige beholdte moduler.

## Senere tilpasning

For at fjerne en selvstændig feature permanent: fjern dens fil fra `XerionUI-Plugin.toc`, optionssiden fra `XerionUI-Plugin_Options.lua`, dens Edit Mode-entry fra `XerionUI-Plugin_EditMode.lua` og filen fra zippen. For features indlejret i core skal den tilhørende runtime-/eventkode også fjernes; i denne version er de fire nævnte corefeatures i stedet eksplicit deaktiveret.

Nye moduler skal registreres i hoved-TOC’en efter eventuelle afhængigheder. Når addonversion eller WoW interfaceversion ændres, skal `Interface` holdes ens i begge TOC-filer. VersionCheck annoncerer fortsat XerionUI-pluginversionen i grupper og kontrollerer fortsat KiraUI-installeren som i originalen.

## Verifikation

Alle Lua/XML-filer, der stadig står i begge TOC-filer, er kontrolleret for tilstedeværelse. Addonet er ikke kørt inde i WoW, så Midnight-klientens runtime-adfærd er ikke verificeret.
## Seneste ændringer

- Options-vinduet bruger nu kun tekstoverskriften `XerionUI Plugin`; X-logoet og de tilhørende billeder er fjernet.
- Under Alerts er `Lust & Potion` reduceret til `Lust`. Potion-ready-modulet er fjernet fra TOC og pakke.
- Bloodlust-siden styrer nu kun lyden, når Bloodlust er klar. Countdown-ikonet er slået fra, og Edit Mode viser ikke længere et flytbart Bloodlust-ikon.
- Lust & Potion Buffs-trackerens potion-buffs er fortsat en separat funktion under EllesmereUI.