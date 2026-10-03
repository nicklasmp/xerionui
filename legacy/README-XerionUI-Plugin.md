# XerionUI Plugin — merged build

This package merges the current XerionUI QoL addon with the feature set and module/options structure from ItruliaQoL.

## Install

Extract both addon folders directly into `World of Warcraft/_retail_/Interface/AddOns/`:

- `XerionUI-Plugin`
- `XerionUI-Plugin_Options`

After installing, disable or remove the separate `ItruliaQoL` addon so its original modules do not display alongside the imported copies. The imported features begin with a fresh Xerion profile; their old Itrulia saved settings are not migrated automatically.

Open the Itrulia-style options and all imported modules with `/xui`. Open the retained Xerion-specific options with `/xqol` (legacy aliases `/xerion`, `/xerionplugin`, and `/kc` remain available).

## Included ItruliaQoL feature areas

Character indicator; combat alert and timer; cursor circle; death alert; defensive indicator; dungeon teleports; flying bar; focus interrupt indicator and focus target marker; friendly nameplates; healer mana indicator; keystone lister; LFG improvements; macro factory; melee indicator; misc; movement alert; no-target indicator; pet missing and pet passive indicators; potion alert; prevent release; raid frame manager; repair indicator; runeforge alert; self-dispel alert; stance alert; stealth indicator; summon helper. The original Ace profile, import/export, preview and Edit Mode/ElvUI/EllesmereUI integrations are retained.

The current Xerion custom feature modules and their separate options remain packaged as well.

## Font

Gotham Narrow Black is the default across the imported modules and Xerion features. This build uses the `GothamNarrowBlack` LibSharedMedia font registration supplied by `SharedMedia_MyMedia` and declares it as an optional dependency. The font file is not redistributed inside this archive.

## Notes

The addon keeps Itrulia's upstream module structure and credits. It is renamed in-game to XerionUI Plugin, and Itrulia's former `/itrulia` command is replaced with `/xui`. `/xui` opens the imported options framework by default; the prior Xerion settings are available with `/xqol`.

The archive was assembled from the supplied local ItruliaQoL zip and the current XerionUI-QoL build. It has not been loaded inside the WoW client, so runtime behavior still needs in-game validation.

## Duplicate-feature and cleanup review

The combined source was reviewed for overlapping behavior and abandoned implementation. Similar-looking modules that serve different events or targets remain separate:

- **CC Tracker** watches enemy CC auras; **CC Cast Notices** report the cast itself.
- **Party Interrupts** show group interrupt cooldown/readiness; **Focus Kick Sound** reacts to focus-target casts.
- **Externals** track external defensive auras on group members; **Defensive Indicator** shows the player's own defensives.
- **Keystone Lister** displays/trades group keystones; **Key Vendor** assists with merchant purchases.
- **Combat Alert/Timer**, **Bloodlust ready**, and **Potion Alert** respond to different combat or cooldown conditions.

Removed abandoned legacy implementations that had no place in the retained feature set: Instance Reset, M+ Break Timer, Cooldown Pulse, and Spell History (including their options pages, event handlers, saved defaults, profile copies, and old character data). Removed the TOC-excluded AutoBuy and LustPots Lua files, and the orphaned Great Vault, Vendor Search, MDT Compact, and Trinkets options builders. Removed stale `LPApply`, `GVApply`, and `VSApply` entries from the settings reapply list.

The CC Cast Notices frame now runs its `OnUpdate` only while a notice or preview is visible and drops the handler when idle. Its existing 0.1-second display behavior during notices is unchanged. Remaining short tickers are feature-scoped (active ability windows, aura/cooldown observation, or visible preview) and are not redundant copies of a single global loop.

## Later customization

- Feature inclusion: `XerionUI-Plugin.toc`, `src/init.xml`, and `src/init.retail.xml`.
- Imported feature implementation/options: matching folders below `XerionUI-Plugin/src/`; module order and integrations: `src/init*.xml` and `src/integrations/`.
- Xerion-specific features: `XerionUI-Plugin_*.lua`; their settings pages and navigation: `XerionUI-Plugin_Options/XerionUI-Plugin_Options.lua`.
- Shared registration, profiles, slash commands, and global settings: `XerionUI-Plugin.lua`.

Legacy reset/cooldown/history/break settings are discarded on load, including old profile snapshots, so switching profiles cannot restore dead configuration.
