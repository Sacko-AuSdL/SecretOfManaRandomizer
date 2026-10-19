# Open World Alpha 0.1 RC2 changelog

Unofficial experimental candidate **Alpha 0.1 RC2**. Fork changes relative to the upstream
1.49 experience, not a claim that these were all introduced in one commit.
Awaiting release approval and clean Windows GUI smoke testing; volunteer
complete-run coverage is still being gathered. Nothing has been published.

## RC2 source cleanup

- Removed direct-arena prototype catalogue, assessment and geometry helper
  classes, and the disabled Frost/Jehk pilot, its switch and admission bypass.
- Retained the production encounter registry and all approved adapters. Public
  Random/Swap/plando eligibility and normal ROM generation are unchanged.
- Manabite assets are credited to Tomm (Discord); creator permission for use
  and redistribution is confirmed by the maintainer. No asset license invented.
- RC1 package remains archived unchanged; RC2 has its own source manifest,
  independently buildable source archive, binaries and checksums.

## World and travel

- Sandship adds a normal boss/reward location, one-time Captain prize, repeatable
  Morie hint and cleared revisits.
- Cannon Travel supports Off, Open, Shuffle and Chaos with progression-aware
  network integration, destination spoilers and a three-page Open menu.
- Optional Free Cannon Travel, Kakkara starting location and startup Upper Land
  Orb requirement information.
- Christmas delivery logic respects the Flammie requirement for mountain NPCs.

## Bosses and progression

- Conservative regular-boss replacements for Doom's Wall, with eye-stat fixes.
- Lime/Dread Slime private-arena redirects, neutral display restoration and
  shared multiline reward-dialogue cleanup.
- Independent Triple Tonpole/Ice Palace randomization, transformations,
  Triple-only half HP and exact-once completion.
- Restricted Doppelganger ↔ Mantis/Jehk replacements preserving destination
  prizes, return routes and Jehk restoration.
- Native map traversal protects generated arena pointers and native executable
  data. NoEnemies preserves the untouched Jehk trial even with Vanilla bosses.

## Magic and optional gameplay

- Crystal Orb Off/Mixed/Weapon Only requirements shared by runtime, hints,
  target text, colors, spoilers and logic.
- Per Character and Party Spell Shuffle, including repeated character roles;
  originating spirit context for Orbs and destination-spirit damage affinity.
- Optional reduced forging prices and configurable player magic damage.
- Cosmetic Manabite graphics/palette and battle name; no combat/stat changes.
- Inherited map music restored after save/load, including soft-reset autosaves.

## Release preparation

- Scope-clean source snapshot includes the approved production integration,
  but excludes Weapon Power and manual test generators.
- System.Text.Json updated from 8.0.4 to 8.0.6; dependency versions/content hashes
  are locked. Known direct and transitive advisories checked before packaging.
- Includes three reproducible normal gameplay configurations, licenses/buildable
  source, known issues, clean Windows checklist and file hashes. No ROM included.

## Not included

New direct-arena experiments, unrestricted boss compatibility, Weapon Power,
Weapon Master/Mana Fortress weapon gates and harder Manabite combat. Legacy
non-Open-World modes are outside this Alpha's validation scope.

Known issue: an occasional lingering defeated-shadow ghost visual with three
Sprite roles. See the player guide for bug reports and the readiness report for
distribution blockers.
