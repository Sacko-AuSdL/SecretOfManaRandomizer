# Expanded Open World Alpha 0.1 RC4 — player guide

Welcome to this unofficial expansion of Moppleton's Secret of Mana Randomizer!
The package is a local review candidate until the maintainer approves publication.

## Install and play

1. On Windows, extract the entire ZIP into a writable folder. Do not run the EXE
   inside the archive. Requires .NET Framework 4.6.2 or a compatible later 4.x runtime.
2. Run `SoMRandomizer.exe`. Supply your own unmodified US Secret of Mana v1.0 ROM:
   2 MiB, optionally with a 512-byte copier header. Patched/translated ROMs are not
   compatible base inputs. No game ROM or external music pack is supplied.
3. Choose Open World, enter a seed and settings, and generate to a NEW filename.
   Save the complete options string. A successful output is4 MiB; keep the logs.
4. Start a NEW game in your emulator. Keep each seed/version's SRAM and save
   states separate. Autosave uses the fourth slot; also keep ordinary saves.

## First playthrough

Try `StarterSettings/Short.options.txt`, seed `Alpha01-RC4-Short`: Vanilla Short,
Restrictive, Random bosses, ordinary roles, Drum in logic, Mixed Orbs, Per Character
spells and Cannon Shuffle. Characters/items still have to be found normally.

Then try `Long.options.txt` / `Alpha01-RC4-Long` (Kakkara, Swap bosses, Weapon Only,
Party spells, free Open Cannons), or `ThreeSprites.options.txt` /
`Alpha01-RC4-ThreeSprites` (three physical characters with Sprite gameplay roles,
Party spells and free Chaos Cannons). These are normal level 1 profiles, not
manual boss teleports or equipment grants. Death Link defaults to On/Vanilla.
RC4's expanded pools intentionally produce different worlds from RC3.

## New choices worth trying

- Kakkara Start with Flammie Drum in Logic; optional Upper Land Orb information.
- Cannon Off/Open/Shuffle/Chaos and optional Free Cannon Travel. Closed Chaos
  offices stay closed even with free travel. Open has eight non-self destinations.
- Sandship: south from Kakkara, then south again. Defeat its randomized boss;
  Captain Meria awards one prize, Morie gives a repeatable hint, and cleared
  revisits do not repeat the capture story or fight.
- Doppelgangers across 18 supported locations, 17 total Jehk choices, and the
  Death Link challenge option. Every shadow must be defeated; the destination
  owns the rewards/flags/return. Jehk retains HP/status and MP restoration.
- Mixed/Weapon Only Crystal Orbs: use the displayed magic family or required
  weapon. No Weapon Power/forge threshold is involved. Targeting, Analyze,
  ferryman/Grand Palace hints and spoilers share the seed's requirement.
- Per Character or Party Spell Shuffle. Spirits retain identities/unlocks/levels;
  spell effects/names/MP costs move between slots. Offensive affinity and Orb
  identity follow the destination spirit. Mana Magic remains in Dryad slots.
- Player magic damage: Vanilla 100%, Fixed 0–100% in 5% steps (Fixed default 40%),
  or one deterministic Random percentage per seed. Enemy damage/healing/buffs
  are not globally scaled by this option.
- Cosmetic Manabite, optional reduced Watts costs, and expanded spoilers.

## What to test

Play normal routes toward the actual goal. After special bosses verify the
correct destination, one reward, readable text and clean completed re-entry.
Check ordinary saves and alive/death/boss-music soft reset to autosave; music
and sound effects should resume. Intentional party defeat should reach Game Over.
For a blocker, preserve evidence before using cheats or overwriting saves.

The maintainer has manually accepted the focused final Doppelganger cases,
including Dragon Worm's exits in both directions, music, autosave and no loops.
Broader full-run/clean-machine coverage remains volunteer work. Read KnownIssues.md.

## Report a bug

Use https://github.com/Sacko-AuSdL/SecretOfManaRandomizer/issues with:

- Package identifier/EXE hash, seed, FULL options and generated-ROM hash.
- Emulator/version or hardware; cheats; normal save versus save state.
- Location, entrance, party roles, active character/weapon, useful inventory,
  exact reproduction steps, expected and actual result.
- A screenshot/video and pre-failure save when useful. Share logs/spoilers
  privately or redact paths/spoilers. Never upload a game ROM.

## Credits

Moppleton and upstream contributors: https://github.com/Moppu/SecretOfManaRandomizer.
Manabite graphics/palette by Tomm (Discord), with creator permission for use and
redistribution confirmed by the maintainer. Existing credits are retained; no
creator URL or extra license terms are invented. See LICENSE, buildable Source,
THIRD-PARTY-NOTICES.md and ThirdPartyLicenses.
