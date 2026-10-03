# XerionUI - QoL — tilpasset kopi

## Installation

Pak begge mapper direkte ud i `World of Warcraft/_retail_/Interface/AddOns/`:

- `XerionUI-QoL` — hovedaddon.
- `XerionUI-QoL_Options` — indstillinger og Edit Mode, indlæses efter behov.

Åbn indstillingerne med `/xui` (alias `/xerion`).

## Ændringer i denne version

Følgende funktioner er fjernet fra addonets indlæsning og/eller indstillingsmenu i overensstemmelse med ønskelisten:

- **General:** Vendor Search.
- **EllesmereUI:** Player, Focus, Nameplate Interrupt, Buff Reminders, Damage Meter Stretch og Cursor Circle.
- **Combat:** Cooldown Pulse, Spell History, Cooldown Manager stacks, Trinkets, DoT Coverage, Combat Text, Crosshair, Secondary Stats og Spell Queue.
- **Alerts:** Buff Watch, Augment Rune, Ready Check og Recuperate.
- **Group:** Healer External, Targeted Spells, Raid Markers og Inspect Talents.
- **Mythic+:** Instance Reset, Break Timer, MDI Teleports, MDT Compact, Auto Gossip og Great Vault.
- **Kira Reminders:** Dungeon Alerts/reminders.
- **Nameplates:** Health-tekstformatering, fjendens navnegennemsigtighed og Target Arrow er fjernet; tidligere gemte indstillinger for dem nulstilles. Shield amount er stadig tilgængelig.

Standalone featuremoduler, der alene implementerede disse funktioner, er taget ud af hoved-TOC’en og zippen. Cooldown Pulse, Spell History, Instance Reset og Break Timer lå indlejret i corefilen; deres konfigurationssider er fjernet, og de tvinges fra ved opstart. Player/Focus EUI-indstillinger nulstilles, herunder debuff borders, fokusmarkør/range fade og den præcise debufftimer, som pluginet eksponerede.

Party Interrupts bevarer cooldown-barerne og har nu også en ikonvariant, der kan placeres på venstre eller højre side af EllesmereUI-partyframes' healthbar. Auto Buy og Lust & Potion Buffs er siden taget helt ud af pakken.



## Struktur, manifest og afhængigheder

Hovedmanifestet `XerionUI-QoL.toc` indeholder client interface-versionerne 120000, 120001, 120005, 120007 og 120100, `AllowLoadGameType: mainline`, samt saved variables `XerionUIChangesDB` og `XerionUIChangesCharDB`. Det indlæser først LibStub, LibSerialize og LibDeflate, derefter core og de resterende featuremoduler. Options-addonets TOC afhænger af `XerionUI-QoL` og har `LoadOnDemand: 1`; Edit Mode indlæses før Options UI.

`Libs/` indeholder de tre indlejrede biblioteker med licenser. `Media/` indeholder resterende teksturer, billeder og lyd. `Bindings.xml` indeholder healer-external tastaturbindingen. Forfatterkrediteringer og tredjepartslicenser er bevaret; originalens Wago-ID er fjernet.

TOC’ens valgfrie integrationer omfatter ElvUI, EllesmereUI og relevante EllesmereUI-moduler. De er ikke nødvendige for de øvrige selvstændige funktioner. De funktioner, der er tilbage, omfatter EllesmereUI nameplates/party health/targeted spell bars, Bloodlust-ready-lyd, eksterne cooldowns, party interrupts/co-tank/shroud, CC Tracker, Aggro Check, klasseværktøjer, keystone vendor og øvrige beholdte moduler.

## Senere tilpasning

For at fjerne en selvstændig feature permanent: fjern dens fil fra `XerionUI-QoL.toc`, optionssiden fra `XerionUI-QoL_Options.lua`, dens Edit Mode-entry fra `XerionUI-QoL_EditMode.lua` og filen fra zippen. For features indlejret i core skal den tilhørende runtime-/eventkode også fjernes; i denne version er de fire nævnte corefeatures i stedet eksplicit deaktiveret.

Nye moduler skal registreres i hoved-TOC’en efter eventuelle afhængigheder. Når addonversion eller WoW interfaceversion ændres, skal `Interface` holdes ens i begge TOC-filer. VersionCheck annoncerer fortsat XerionUI-pluginversionen i grupper og kontrollerer fortsat KiraUI-installeren som i originalen.

## Verifikation

Alle Lua/XML-filer, der stadig står i begge TOC-filer, er kontrolleret for tilstedeværelse. Addonet er ikke kørt inde i WoW, så Midnight-klientens runtime-adfærd er ikke verificeret.
## Seneste ændringer

- Options-vinduet bruger nu kun tekstoverskriften `XerionUI - QoL`; X-logoet og de tilhørende billeder er fjernet.
- Bloodlust-ready-lyd findes som en indstilling under Group. Countdown-ikonet og Potion-ready-modulet er fjernet.
- Bloodlust-siden styrer nu kun lyden, når Bloodlust er klar. Countdown-ikonet er slået fra, og Edit Mode viser ikke længere et flytbart Bloodlust-ikon.
- Lust & Potion Buffs-trackerfunktionen er fjernet fra denne pakke.
## Seneste tilpasninger

- Lust & Potion Buffs og Auto Buy er fjernet fra addonets indlæsning og optionsmenu.
- Raid marker-indstillingerne er fjernet fra Targeted Spell Bars-siden.
- Auto Buy-modulet og dets optionsside er taget ud.
- Party Interrupts har to layoutvalg: eksisterende cooldown-bars eller ikoner forankret til EllesmereUI-partyframes. Ikonlayoutet tilbyder venstre/højre placering, størrelse og afstand.
- CC Tracker, CC Cast Notices, Lust og Aggro Check ligger nu under Group; Tricks & Misdirection samt Alerts- og Mythic+-sektionerne er fjernet.
- EllesmereUI-sektionen hedder nu EllesmereUI Tweaks. Bloodlust bruger WoW's indbyggede raid warning-lyd som standard, og siden har en testknap.

- **EllesmereUI Tweaks > Focus Cast Bar:** valgfri baggrundsfarve og opacitet på den separate focus-castbar under EllesmereUI Mythic+ Tools. Dette er Mythic+-baren, ikke focus-castbaren under Unit Frames. Pluginet genfinder Mythic+-baren efter dens refresh og farver dens baggrund bag cast-fyldet.

- **Externals:** ikonernes borderfarve og tykkelse kan tilpasses, og rækken kan vokse mod højre, venstre eller opad. Glow type har også **Auto Shine** ud over Pixel Glow og Shape Glow.

- **EllesmereUI Tweaks > Party Frames:** indstillingen for placering af staktallet på party-debuffikoner har valget **Top**, som placerer tallet centreret lige over ikonet og tilsidesætter EllesmereUI's offsets. **Preview** viser et eksempel over partyframes, og **Offset X/Y** finjusterer placeringen. For de øvrige placeringer lægges offsets til EllesmereUI's eksisterende stack offsets.

- **Group > CC Tracker** viser aktive CC-effekter på fjender gennem Midnight's secret-safe AuraContainer-system. Cap Totem, DH Silence og Shadowfury er med igen her, så de fortsat vises selv om klienten skjuler spell-ID'et i cast-events. Den særskilte **CC Cast Notices**-funktion kan ikke genkende redigerede cast-ID'er i Midnight.
- **Group > Shroud/Invis Bar:** bar texture kan nu vælges blandt LibSharedMedia-statusbarteksturer; **Default** bruger XerionUI's sædvanlige tekstur.
- **Misc > Stoneform:** nyt Bleed-alertikon, der vises for spillere med Stoneform, mens de har en bleed og Stoneform er klar. Det har preview, flytning via højreklik-træk, Edit Mode, justerbar størrelse, borderfarve/-tykkelse og Pixel Glow, Shape Glow eller Auto Cast Shine. Hvis klienten skjuler auraens type som en secret value, skjules alertet også, så det ikke fejlmelder.
- **Group > Shroud/Invis Bar:** begge barer kan nu bruge en valgfri brugerdefineret baggrundsfarve. Slå indstillingen fra for at vende tilbage til den tidligere mørke nuance af hver bars farve; opacity kan fortsat justeres separat.
- **EllesmereUI Tweaks > Nameplates:** **Show glow without purge or soothe** (standard til) tilsidesætter EllesmereUI Nameplates' klassekontrol og lader Magic/Enrage-dispel-glow vises uden offensiv purge/soothe. EllesmereUI's egen **Dispel Glow**-indstilling styrer stadig, om glow er slået til generelt.


- **Group:** Tricks & Misdirection er fjernet fra optionsmenuen og addonets indlæsning.

- **Externals glow:** Auto Cast Shine uses the same EllesmereUI sparkle engine as Stoneform when available, with WoW's native autocast overlay as fallback.

- **Group > Lust > Bloodlust ready:** optional text-to-speech announcement with editable phrase, voice selection and volume, plus a test button. It can play alongside the selected ready sound.

- **CC Tracker:** Cap Totem, DH Silence og Shadowfury er gendannet i AuraContainer-sporingen. Eksisterende profiler får automatisk de tre spells tilbage, hvis den tidligere opdeling havde fjernet dem.

- **Options menu:** Stoneform has moved into the new **Misc** group and uses its Dwarf racial spell icon (spell 20594; icon fallback 132275).

- **Misc > Stoneform:** The on-screen icon now resolves the Dwarf Stoneform spell's own icon, matching the options sidebar. Auto Cast Shine uses EllesmereUI's orbiting sparkle engine when available and the native WoW autocast overlay otherwise.
- **Misc > Stoneform > Bleed alert:** choose either Text to Speak or one of the existing LibSharedMedia sounds. The alert plays when the Stoneform icon appears after a bleed is detected; the selected mode, text, voice and volume are configurable, with a test button.

- **Externals:** The Extra Spells picker and its additional aura display have been removed.
