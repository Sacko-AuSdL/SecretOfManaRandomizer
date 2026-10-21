# Secret of Mana Randomizer — Expanded Open World Alpha 0.1

Ready to rediscover the world of Mana?

Welcome to the first public playtest of **Expanded Open World**, an unofficial fork of [Moppleton’s Secret of Mana Randomizer](https://github.com/Moppu/SecretOfManaRandomizer). This Alpha brings new ways to travel, unfamiliar spell combinations, weapon-based Crystal Orb puzzles, more randomized boss encounters, and a fresh starting point in Kakkara.

Mix a few options into a familiar run, or combine them for a very different adventure. We’re looking for community playtesters to explore normal seeds, complete runs, and help shape the next version. This is an experimental community release—not an official upstream or stable release.

## What’s New

### A new starting point—and more to explore

- **Kakkara Start:** Begin in the desert town instead of the usual Potos-area start. Available when **Flammie Drum in Logic** is enabled, so finding a way out and eventually obtaining Flammie becomes part of your route. With the Drum excluded from logic, the existing pedestal start remains unchanged; Christmas goals retain their special starts.
- **Sandship is now part of Open World:** Head south from Kakkara, then south again, to find the new entrance. Fight the location’s randomized boss without going through the original capture sequence. After victory, **Captain Meria awards a randomized prize**, **Morie offers a repeatable hint**, and the cleared ship can be revisited without repeating the fight or reward.
- **Optional Upper Land Orb information:** Enable **Show Upper Land Orb Requirement** to see the seed’s actual requirement for the Upper Land/Matango connection at startup. It works with Default and Kakkara starts when the Drum is in logic, and with every Cannon mode. It’s useful route information—not a promise that you must clear that Orb.

### Cannon Travel: build a different world map

Choose how the Cannon network shapes your journey:

- **Off:** Keep the existing Open World Cannon routes.
- **Open:** Every Cannon office offers **eight destinations**, excluding its own landing destination. A compact overview and three destination pages make the expanded routes easy to browse.
- **Shuffle:** Discover randomized routes forming a connected network between the Cannon regions, while offices retain their usual number of route choices.
- **Chaos:** Explore a less predictable network that may split into disconnected regions. Some offices can be closed entirely, making walking routes and finding Flammie more important. A closed office is an intentional possibility—not an indication that you need more gold.

Non-free randomized routes cost **50 GP** unless **Free Cannon Travel** is enabled. Free travel works with **all four modes**, including Off: you can travel with 0 GP and no fare is deducted. It does not reopen closed Chaos offices.

Item placement accounts for your starting region, Cannon connections, relevant walking routes, and Flammie access. Cannon Chaos is an Open World travel option, not the separate legacy Chaos game mode.

### More bosses in the Open World shuffle

The existing **Random** and **Swap** boss modes gain expanded, compatibility-aware encounter choices:

- **Lime Slime and Dread Slime** can appear at supported locations outside their original homes. Their original locations can also receive compatible replacement bosses.
- **Ice Palace has its own boss selection**, independent of the Undine Cave encounter. You no longer have to find the same choice in both locations.
- **Triple Tonpole joins the encounter pool** at supported locations, complete with all three enemies and their transformations. Both forms receive encounter-specific half-HP balancing; ordinary standalone Tonpole encounters are not reduced by this adjustment. The trio grants its final reward only after the whole encounter is cleared.
- **Doom’s Wall’s location can host regular bosses in Random mode**, opening up more surprises in Northtown Ruins.
- **Sandship’s Mech Rider location** participates in the boss shuffle and has its own post-battle prize location.

Some special fights use a separate arena suited to that boss. You still receive the reward, progression, and return path belonging to the location you entered—not the boss’s original story progression. Exact choices depend on the location and boss mode; this is not an unrestricted “every boss in every room” shuffle.

For players building their own scenarios, **Plando** also gains encounter selections for Sandship, Ice Palace/Triple Tonpole, and Jehk’s trial, subject to compatibility limits.

### Doppelgangers across the world—and new trials at Jehk

The full three-shadow encounter now has **18 supported locations**, including its original Jehk trial:

- Mantis Ant, Tropicallo, Wall Face and Jabberwocky.
- Frost Gigas, Fire Gigas, Mech Rider II, Mech Rider III and Watermelon.
- All six Pure Lands boss locations: Dragon Worm, Snow Dragon, Axe Beak, Red Dragon, Thunder Gigas and Blue Dragon.
- Lime Slime, Dread Slime, and the original Doppelganger trial.

Defeat all three shadows to complete the encounter. Its prize, progression and onward route belong to the **location**, not the shadows' original story. Some placements use a compatible private arena; Dragon Worm now uses a recognizable copy of its own clearing with natural travel through both exits after victory.

Jehk's trial also gains **17 encounter choices in total**—the original trio plus 16 compatible replacements, including Mantis Ant, Minotaur, Jabberwocky, the Gigas family and other regular bosses. Jehk retains its own rewards and party HP/status and MP restoration afterward. These choices are available through normal Random, Swap and supported Plando generation.

**Doppelganger Death Link** lets you choose the original mechanic or a tougher variant:

- **On — Vanilla (default):** Preserve the native link between each shadow and its corresponding party member.
- **Off — Challenge:** Remove the party-member defeat shortcut; defeat each shadow in combat.

The shadows' HP scaling has also been corrected so it follows the intended difficulty/scaling system rather than assigning these enemies an incorrectly inflated HP class. This is a correction, not a blanket reduction to other bosses or a change to shadow AI.

Arena-entry autosave safeguards preserve a safe continue location. The Dragon Worm reward, repeated re-entry, music and both exits have passed the maintainer's focused Mesen checks. That is targeted acceptance—not a claim that every possible randomized pairing has received a complete playthrough.

### Spell Shuffle: familiar spirits, unfamiliar spellbooks

Shuffle **individual spells**, not entire spirits. Gnome is still Gnome—but his spell menu might now contain Fireball!

- **Off:** Keep the usual spell assignments for each character’s role.
- **Per Character:** Independently rearrange each magic-capable character’s own spells among their spirit slots. Characters with the same role can have different layouts.
- **Party Shuffle:** Pool the shuffleable spells belonging to the characters available in the seed and redistribute them across their magic slots. Girl-role characters can receive Sprite-origin attacks, and Sprite-role characters can receive healing and support spells.

Spirits still unlock and level their own slots. The assigned spell keeps its effect, name, and MP cost, while **elemental damage affinity follows the destination spirit**. For example, Fireball cast from a Gnome slot uses Gnome’s elemental affinity for weakness/resistance checks and counts as Gnome magic for Crystal Orbs.

Existing spell copies are redistributed rather than added or discarded. Parties with repeated caster roles can therefore end up with repeated spells—even within one spirit menu. **Mana Magic remains in its Dryad slots** rather than joining the shuffle.

### Crystal Orbs: magic gates or weapon puzzles

Choose **Crystal Orb weapon breaking**:

- **Off:** Preserve the existing Open World magic-Orb behavior.
- **Mixed:** Each active Orb receives one requirement: a usable magic family **or** a particular weapon type.
- **Weapon Only:** Active Orbs require specific weapons instead of magic.

A weapon Orb needs a hit with its required weapon—not a particular forge rank or proficiency level. All eight weapon families can be selected: **Glove, Sword, Axe, Spear, Whip, Bow, Boomerang, and Javelin**. Ranged weapons use their projectiles; melee checks use the attacking character’s currently equipped weapon.

Requirements appear in targeting/Analyze text, with matching hints and spoiler information. Grand Palace hints account for weapon requirements, and Karon’s Luna Orb information reflects the actual requirement too. Weapon Orbs use a neutral appearance rather than advertising an unrelated magic element.

Magic requirements take the seed’s actual caster roles and shuffled spell access into account. A party without usable magic receives weapon requirements when this feature is enabled. Each Orb has **one requirement**, not a combination of a weapon and magic.

### Try unusual parties—including Three Sprites

The existing character-role options remain available. What’s new is how Spell Shuffle and weapon Orbs work alongside them: try two Girl roles, several Sprite roles, or a weapon-focused party without usable magic.

The bundled **ThreeSprites** configuration starts all three characters with Sprite gameplay roles and gives them Party Shuffle spell layouts. These are three independently addressed characters—not one shared spellbook, and not three identical appearance sprites. You can also keep the familiar roles and find your other party members during the run.

### More ways to tailor your adventure

- **Player magic damage:** Keep Vanilla damage, choose a Fixed percentage from **0–100% in 5% steps**, or let Random select one percentage for the seed. This adjusts player offensive spell HP damage, not enemy spell damage or healing/support effects. Random deterministically chooses **0–100% in 5% steps** for the seed, not a new roll on every cast. Fixed defaults to **40%** when selected; the overall default remains **Vanilla / 100%**.
- **Manabite:** Give the final Mana Beast a new look, palette, and in-game battle name. This option is **cosmetic only**—it does not make the final boss stronger or change its attacks.
- **Reduced Watts costs remain available:** The earlier optional reduced-forging setting is included, letting you spend less gold on ordinary weapon upgrades while retaining their weapon-orb requirements.
- **More informative spoilers:** Optional spoiler output includes Cannon routes and closed offices, per-character spell layouts, and the actual Crystal Orb requirements, alongside the existing world information.

## Recommended First Playthrough

Start with **Open World**, familiar character roles, **Vanilla Short**, and **Restrictive** logic. Try **Mixed Orbs**, **Per Character Spell Shuffle**, and **Cannon Shuffle** for a good introduction to the new systems. Keep Player magic damage on Vanilla unless you specifically want an extra challenge.

The ZIP includes ready-to-paste configurations:

- **First run:** `StarterSettings/Short.options.txt`, seed `Alpha01-RC4-Short`—a normal level-1 adventure with the other characters and Flammie still to find.
- **A different route:** `Long.options.txt`, seed `Alpha01-RC4-Long`—Kakkara Start, Vanilla Long, Swap bosses, Weapon Only Orbs, Party Shuffle, and free Open Cannons.
- **For adventurous testers:** `ThreeSprites.options.txt`, seed `Alpha01-RC4-ThreeSprites`—three Sprite roles, Party Shuffle, Mixed Orbs, and Chaos Cannons.

Paste the entire options string from the RC4 package. These are normal gameplay configurations, not shortcut boss-test profiles.

## Installation & Requirements

1. Download **`SecretOfManaRandomizer-Alpha-0.1-RC4.zip`** from this pre-release’s assets and extract the **entire ZIP** to a writable folder.
2. Run `SoMRandomizer.exe` on Windows with **.NET Framework 4.6.2 or a compatible later 4.x runtime**.
3. Supply your own unmodified **US Secret of Mana v1.0 ROM**: 2 MiB, optionally with a 512-byte copier header. Previously patched or translated ROMs are not supported base images.
4. Select Open World, enter your seed/settings, and generate to a **new filename**. Play the generated ROM in your emulator.

**No game ROM is included.** Buildable randomizer source, player documentation, licenses, starter settings, and checksums are included. No separate music pack is required.

RC4 ZIP SHA-256:

```text
FD0B64A50B6E64672CDDE7DD656DD2B991CABB7A4818A1221CDA563A0721C0B7
```

Use this RC4 package rather than earlier candidates. Historical RC3 files and the existing Alpha tag remain unchanged.

## Alpha Status & Known Limitations

This first public Alpha is intended for **Open World playtesting**. Individual features have received automated checks and maintainer emulator testing, but wider full-run, clean-Windows, emulator, and hardware coverage is still being gathered. Other game modes are outside this playtest’s acceptance scope.

- Boss compatibility remains selective; not every boss can appear in every location.
- With three Sprite roles, a defeated Doppelganger may occasionally leave a lingering ghost visual. Reported cases still completed successfully; please report any case that blocks progress.
- Back up saves and keep each seed/version’s saves separate. Save compatibility across Alpha updates is not guaranteed. Keep an ordinary save as well as relying on autosave.
- The application is unsigned and still displays upstream version **1.49**. Please identify this build as **Expanded Open World Alpha 0.1 RC4** in reports.

You do not need to be a speedrunner or complete every bundled configuration to help. A normal run, a careful bug report, or a fresh Windows installation test is valuable.

The remaining five Pure Lands shadow placements still use donor arenas and may include a brief completed-entry return transition. They were not converted to Dragon Worm's destination-copy layout in this release. Report any wrong return position, lost control or repeat encounter.


## Feedback & Bug Reports

Please report issues through [this fork’s GitHub Issues](https://github.com/Sacko-AuSdL/SecretOfManaRandomizer/issues).

Include:

- Your **seed and complete settings/options string**.
- The package version, emulator/version or hardware, and any cheats or other modifications.
- Where you were, your party/roles, what you did, what you expected, and what happened.
- Clear reproduction steps and, when useful, a screenshot or short video.

For possible softlocks, preserve a save from before the problem and describe the checks and routes still available. Logs/spoilers can help diagnosis, but redact personal paths and avoid posting unwanted seed spoilers publicly. **Never upload base or generated ROMs.**

## Credits

Huge thanks to **Moppleton and the upstream contributors** for [Secret of Mana Randomizer](https://github.com/Moppu/SecretOfManaRandomizer), the foundation of this unofficial expansion.

**Manabite artwork and palette: Tomm (Discord)**, with the creator’s permission for use and redistribution.

Thanks also to the community members and playtesters helping verify encounters, travel, magic, and progression. The included `LICENSE`, buildable source, `THIRD-PARTY-NOTICES.md`, and dependency licenses retain the applicable licensing and attribution information.

## Bug Fixes

- Corrected Doppelganger HP categorization, safe arena autosave/continue behavior and Dragon Worm's post-victory exit/re-entry transitions.

- Corrected Kakkara-start progression checks so unreachable Potos/Pandora rewards cannot be credited as starting-area items, addressing the reported closed-Chaos Cannon softlock.
- Restored intended map music after save/load, including soft-reset/autosave sequences and resets during or after boss music.
- Corrected special Slime encounter transitions and post-boss dialogue so level-up and reward messages render normally.
- Fixed wall-boss eye-stat handling and protected normal enemy/map data when generated boss arenas are present.
- Corrected start-with item simulation and starter-weapon interactions, plus Christmas delivery checks that require Flammie.
- Fixed shuffled-spell Crystal Orb context handling and related dialogue corruption, with weapon-Orb checks respecting the actual attacker and equipped weapon.

Thanks for giving Expanded Open World a try—we’re excited to see the routes, parties, and spell combinations you discover!
