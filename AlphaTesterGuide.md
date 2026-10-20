# Open World Alpha player guide

Candidate: **Unofficial Alpha 0.1 RC3 — experimental, awaiting release approval**.
The goal is volunteer testing of normal Open World progression, not shortcut
boss-test ROMs. Clean Windows GUI smoke testing remains pending. Complete personal
playthroughs are not required before inviting volunteers after technical checks
and explicit publication approval. No release has been published yet.

## Install and generate

1. On Windows, extract the entire approved ZIP to a writable folder. Run
   `SoMRandomizer.exe`; .NET Framework 4.6.2 or a compatible later 4.x runtime is
   required. Windows-only packaging is the initial target.
2. Supply your own legally obtained, unmodified **US Secret of Mana v1.0** ROM.
   The generator accepts 2,097,152 bytes or 2,097,664 bytes with a 512-byte copier
   header; it strips the header and produces a 4 MiB game. Translations and
   previously patched/randomized ROMs are not supported base images.
3. Select Open World. Enter a seed and select settings below. Keep a copy of the
   full options string and package version. Pick a new output filename, not your
   source ROM, and generate. Enable/save the spoiler log for later diagnosis;
   you do not need to read it during the run.
4. Open the generated `.sfc` in your emulator. Mesen 2 has been used for the
   maintainer's individual runtime checks; other emulators and flash hardware
   need separate compatibility confirmation. Record the exact version/device.
5. Start a new game. Keep this seed's SRAM/save states separate from other ROMs
   and versions. Autosave uses the fourth save slot; keep an ordinary save too.

Never share the base/generated ROM. A tester package contains the randomizer,
not the game. Do not assume saves remain compatible across Alpha revisions.

## Recommended first playthrough

Use the package's `StarterSettings/Short.options.txt` with seed
`Alpha01-RC1-Short`. Paste the WHOLE line into Open World options. This normal
level-1 run has Random bosses, Vanilla Short, Restrictive logic, Drum in logic,
Mixed Orbs, Per Character spells, Cannon Shuffle and reduced forging. Other
characters and progression still have to be found normally.

Then use `Long.options.txt` / `Alpha01-RC1-Long` (Long, Swap bosses, Kakkara,
Weapon Only, Party spells, free Open Cannons), and `ThreeSprites.options.txt` /
`Alpha01-RC1-ThreeSprites` (three Sprite gameplay roles, Party spells, Mixed
Orbs, Chaos Cannons). See `StarterSettings/README.md` for exact goals and caveats.
These are ordinary configurations, not shortcut boss-test profiles.
Seed strings deliberately retain their RC1 labels for exact RC1/RC2 output
comparison; the package and source are RC2.

This is a control run, not the only supported configuration. Follow with
separate targeted runs rather than changing every option at once:

- Mixed or Weapon Only Crystal Orbs; the target name/hints show the actual
  requirement. Weapon Only does not use Weapon Power or forging thresholds.
- Per Character or Party Spell Shuffle. Spirits still unlock/level their slots;
  offensive affinity follows the destination spirit. Mana Magic remains special
  Dryad endgame magic.
- Cannon Open (eight non-self destinations, three pages), Shuffle or Chaos.
  Optional Free Cannon Travel removes fares. Cannon Chaos is NOT the separate
  legacy Chaos game mode.
- Kakkara start with Drum in logic; optionally show the Upper Land Orb startup
  requirement. It is information, not a claim that clearing it is mandatory.
- Reduced forging, cosmetic Manabite and player magic damage scaling are
  optional; Vanilla remains their default.

## What to check

Play through normal Sword acquisition and ordinary world routes to the actual
goal. Note inaccessible mandatory items, Orb requirements you cannot satisfy,
unexpected doors, repeated prizes or rewards that disappear. After special
bosses, verify readable level-up/orb/prize text, the correct return destination,
and completed-room re-entry without respawning or paying a second prize.

Keep ordinary saves before risky encounters. Test ordinary save/load and
soft reset → autosave after normal and boss music. Intentional party defeat
should reach Game Over. Do not use cheats to bypass a progression problem
before preserving a reproducible save and reporting it.

## Known limitations

Occasionally a defeated shadow can leave a ghost visual with three Sprite
roles; completion has worked in the supplied tests. Report it, especially if it
blocks progress. Not every boss can appear in every arena. Frost/Jehk direct,
shadows/Tropicallo direct and other arena prototypes are not Alpha choices.
Weapon Power and harder Manabite combat are not included. Non-Open-World modes
are outside this playtest's scope.

## Report a bug or possible softlock

Send the maintainer:

- Package identifier and application SHA-256, seed, **complete options string**,
  and generated-ROM SHA-256 (not the ROM itself).
- Emulator/version or hardware, cheats/modifications, normal save vs save state,
  and whether a fresh generation reproduces it.
- Exact location, entrance used, party roles/current character, equipped weapon,
  learned spirits, relevant inventory, last boss/prize and steps to reproduce.
- Expected versus actual result, screenshot/video, generation log and spoiler
  privately if requested. Remove personal paths before sharing logs publicly.
- For a progression blocker: the earliest pre-failure save, remaining reachable
  checks, requirement shown by the Orb/hint, and whether leaving/re-entering or
  an ordinary reload changes it. Do not overwrite the only useful save.

Report reproducible issues at https://github.com/Sacko-AuSdL/SecretOfManaRandomizer/issues
or the maintainer's agreed playtest channel. Please distinguish a visual artifact from an actual
loss of control/progression.

## Credits

Unofficial fork of Moppleton's Secret of Mana Randomizer and its upstream
contributors: https://github.com/Moppu/SecretOfManaRandomizer.
Manabite artwork/palette by **Tomm (Discord)**. The maintainer confirms the
original creator granted permission for use and redistribution. Existing
credits are retained; no additional permission condition or creator URL was
supplied or invented. See LICENSE and THIRD-PARTY-NOTICES.md.
