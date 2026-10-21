# Dragon Worm destination-copy acceptance

## Defect and scope

The old production binding unconditionally changed both Door375 and Door378
from map204 to the native-Jehk cave copy (map498). After flag46 reached1,
event6D5 immediately jumped to6B9 and Door0CB, whose coordinates always came
from the lower Door375. Every completed re-entry therefore visited the cave
and returned to the lower approach, even when entering from above. The Sword
shortcut and autosave were not necessary to reproduce that routing defect.
The earlier event test checked reward counts, but accepted that extra return.

## Implemented contract

- Reuse the existing destination-copy adapter and existing map498 allocation.
  Original map204 has one actor slot; map205 already owns the next four.
  In-place insertion would require a wider object-bank relocation, not an
  extra two writes. FullMapReplacer is not a partial native-map insertion API.
- Copy the original 34x40 clearing, header/display/palette and pieces36D/36E.
  No collision tiles, native map204/205 pointers, AI or artwork are changed.
- Three native actors2E/3F/20 retain priority/graphics metadata and event0.
  Spawns21,11;23,14;14,17 have 3x3 floor pockets connected to BOTH native
  approaches18,27 and23,5. Tileset30 uses ground collision00 and passive
  foreground collision17; canopy decoration is preserved, not flattened.
- Door375/378 retain their own coordinates/layer/facing and enter the copy.
  Walk-on6D5 starts the original boss music7C4 if uncleared. If flag46>=1 it
  selects area music727 WITHOUT a door. Four exit triggers remain exactly
  5DF,5DF,5DE,5DE, using original doors377/376 and native progress guards.
- All-three dispatcher and native4A checks still select Dragon Worm event5ED.
  That event is now byte-identical to the ordinary destination reward:
  41B, fixed Axe Orb502, increment46, randomized prize,62A/727. Victory stays
  on the recognizable clearing; Dragon Worm no longer claims Door0CB.
- Private-copy entry never overwrites a safe autosave. The normal two exits
  can autosave; continue loads the saved world door, not the arena door.
- The manual-only Sword shortcut additionally rejects flag46>=1. Normal
  generation has neither the shortcut nor manual supplies.

## Verification versus remaining acceptance

`BossDoppelgangerPureLands.Tests.ps1 -GenerationSmoke` checks all eight death
masks, emitted dispatcher/native actor code, native exits before victory,
ten completed upper/lower round trips, exact-once rewards/flags, collision
connectivity, safe save/load/wipe gates, and four normal in-memory worlds
(Random/Swap x Death Link On/Off). Normal Sword commands are decoded to
reject test teleports. This is not a combat, camera, graphics or PPU emulator.
The new final ROM still requires Mesen combat and transition acceptance.

## Other recent destinations: audit only, NOT enabled here

Already using destination geometry: Tropicallo and Frost Gigas (copies).
Promising regular-geometry candidates for a separate measured adapter pass:
Axe Beak(map213), Thunder Gigas(226), Fire Gigas(495), Mech Rider III(237).
Each still needs floor/actor/trigger/music/return validation. Jabberwocky(143)
has three existing objects and eight triggers; preserve those contracts rather
than copying only its scenery. Mech Rider II(100) has two native objects and
a Flammie-specific exit, so needs separate actor/exit work.

Wall Face(166), Watermelon(238), Snow/Red/Blue Dragon(230/231/232), Lime(489)
and Dread(488) have special-display headers; ordinary shadow display there
is not established by room size. Keep their current donor adapters. The other
Pure Lands donor placements retain their old completed-entry return trip;
they were not silently generalized or runtime-approved by this Dragon Worm fix.
No selector eligibility, weighting, scaling or Death Link behavior is changed.
