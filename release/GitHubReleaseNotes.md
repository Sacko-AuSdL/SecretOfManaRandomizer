# Secret of Mana Randomizer - Expanded Open World Alpha 0.1 Update 3

This focused update to the unofficial community Alpha adds two starting locations and improves world progression. All gameplay options from the published Alpha 0.1 remain available.

**Local release candidate: both new starts passed community emulator testing. Publication awaits maintainer approval.**

## What's new

- **Ice Country town (Todo) start:** begin inside the snowy town, with its normal paths, NPCs and exits.
- **Southtown start:** begin inside the Empire town and explore from there.
- Both join Default/Potos and Kakkara in the existing **Starting Location** selector. Enable **Find Flammie Drum in Logic** to use an alternate start. Christmas goals keep their dedicated start.
- **Upper Land / Matango weapon Orb access:** the accepted narrow hedge preserves the original Orb position and closed gate while allowing attacks from both approaches. Weapon requirements still apply. Native-code checks cover ordinary uncharged Javelin contact without a level-4 charge.
- **Undine Cave stability:** accepted Triple Tonpole completion/re-entry and NPC-room autosave-return fixes prevent the Ice Palace detour and invalid cached-room exit.

- **Southtown reward check:** Mara now remembers an intentionally empty reward, so repeat conversations report that the check is already collected. Real randomized items are unchanged.

The new starts use their actual region for item-placement and Cannon Travel reachability, including closed Chaos offices. They do not grant extra progression items or open locked routes.

This update retains the published Alpha boss roster and compatibility rules. The ongoing advanced direct-arena campaign, singleton experiments, Weapon Power and Watts enhancements are **not included**.

## Installation

Download **`SecretOfManaRandomizer-Alpha-0.1-Update3.zip`**, extract the complete folder, and run `SoMRandomizer.exe` on Windows with .NET Framework 4.6.2 or a compatible newer 4.x runtime. Supply your own compatible US Secret of Mana ROM. **No game ROM is included.**

Use a new generated ROM and separate saves. Starter settings for Potos, Kakkara, Three Sprites, Ice Country and Southtown are included. Internal ROM/settings version remains **1.49**; application metadata identifies **0.1.0-alpha.3**.

ZIP SHA-256:

```text
CFA5BA8665C99D51AD28C9F632337DEF68C4B54BF43C3D45DED425D92C6266BA
```

## Alpha limitations and feedback

Automated build, generation, reachability, native event/save and package checks passed. Todo and Southtown startup, controls, Ring Menu, exits/re-entry and save/reload passed user Mesen testing; live Javelin launch/animation verification is recommended. Existing bounded boss compatibility and the reported nonblocking Three-Sprites shadow visual remain unchanged. Automated checks are not full playthrough coverage.

For bug reports, include the seed, complete settings, emulator/version and exact steps. Preserve a pre-failure save when possible. Do not share copyrighted base or generated ROMs.

## Credits

Based on [Moppleton's Secret of Mana Randomizer](https://github.com/Moppu/SecretOfManaRandomizer). Manabite artwork and palette by **Tomm (Discord)**, with permission for use and redistribution. The application remains LGPL-2.1-or-later; buildable source and applicable dependency licenses are included.
