# Doppelganger Phase 1 ownership reference

Open World only; initial compatibility is Doppelgangers <-> Mantis Ant.
Logical selection ID `81` is never written as an actor species, stat-row index,
or native arena-import dictionary entry. Native shadows are `2E / 3F / 20`.

## Maps and native boundary protection

| Map | Owner |
| --- | --- |
| 496 / 1F0 | Remains unused; its original three pointers are unchanged. These terminate reachable Fire Gigas map 495. |
| 497 / 1F1 | Private native-geometry Mantis arena for the Jehk logical slot. |
| 498 / 1F2 | Private native-geometry three-shadow arena for the Mantis logical slot. |
| 499 / 1F3 | Unreachable end-pointer sentinel. |
| 500-511 / 1F4-1FF | Existing Triple/Dread/Fortress/Lime/staging/Shade/Doom allocations; unchanged. |

The US native ROM has zero objects, triggers and pieces in maps 496-499.
There are no native doors targeting 497-499. Door `0CB` targets unused 496,
but no native event contains its door command and no native tile trigger uses
`8CB`. The door is not repurposed. Final generated-event scans must also remain
free of callers. Do not expose 496/499 as playable maps: they are boundaries,
not newly initialized arenas.

EnemySwaps and NoEnemies must continue reading **both native span boundaries
from origRom**, even after generated pointers are published in outRom.

## Bank-8 data

| Inclusive ROM span | Contents |
| --- | --- |
| 08FF50-08FF5F | Mantis header and one native boss object. |
| 08FF60-08FF7F | Trial header and three native shadow objects. |
| 08FF80-08FF8B | Native Mantis piece references: BG 014, FG 015. |
| 08FF8C-08FF97 | Native trial references: BG 2C8, FG 2C9. |
| 08FF98-08FF99 | Mantis walk-on event 3DB. |
| 08FF9A-08FFA3 | Shadow walk-on 6D5 and four exit-tile entries 6D6. |

All are native FF padding, after Triple's last byte at 08FF4D. No compressed
piece IDs/data are allocated: both geometries reuse their native pieces.
Allocation is fail-closed on occupied bytes, map pointers, maps or events.
These spans are disjoint from native C8 code and Doom/Nesoberi/slime data.

## Events and state

| Event | Purpose |
| --- | --- |
| 6D5 | Foreign shadows entry; claimed Mantis returns via 6B9. |
| 6D6 | Native three-actor defeat tests, then authoritative Mantis prize 112. |
| 6B9 | Return-only Door 08E; no reward or progression mutation. |
| 6BA | Return-only Door 038 for completed reverse-slot entry. |
| 6BB | Actual Mantis death callback; arm Jehk flag 3F=5, then original check 4E5. |
| 3DB | Reverse arena entry only when Mantis replaces Jehk. |
| 4E5 | Retains original Jehk prize identity/tail; reverse form requires death-arm state rather than three absent shadows. |

Private event IDs were END-only and unreferenced by native events/map triggers
and objects. Cannon, existing boss redirects, prizes and hints do not own them.

Foreign shadows use Potos flag `7ECF10`: alive through B, claimed at C. They
never mutate Jehk flag `7ECF3F`. The three actor tests read `7EE791`, `7EE991`,
`7EEB91` (actor offsets 0600/0800/0A00, attribute 91). All must exceed 7F.
The actual native comparison handler is CPU `C1F1F1`, ROM `01F1F1`, with the
comparison branch at `C1F248`. No new global death/initialization hook is added.

Native shadow AI remains ROM `105605`, CPU `D05605`, and metadata pointers at
`100000 + species * 16 + 9`. Native role-independent appearances are preserved.
Existing boss-growth classification counts Shadow X1 only, not all three.

Door 08D uses native trial coordinates/transition into map 498:
`F2 21 28 81`. Door 304 uses native Mantis coordinates/transition into map 497:
`F1 21 24 80`. Native return doors 08E and 038 remain unchanged.

The retained native trial still uses 3DB -> 3DF -> 4E5 and its original three
checks. NoEnemies protection is limited to that selected trial; generated
arenas are outside native object spans and ordinary enemy exclusions remain.

Automated event/machine/ROM tests are not Mesen runtime acceptance.

## Manual startup isolation

The immediate Sword-event teleport is intentionally **manual-profile only**.
`tests/support/DoppelgangerManualProfile.cs` is not a production project input.
Only the ignored `ManualDoppelGenerator` calls it, after normal generation and
before event serialization. Production `SwordGrabEvent` and
`DoppelgangerBossArenaRedirect` do not inject a door into event `103`.
The final-ROM generation smoke test decodes event `103`, rejects every door or
transport command and manual MP/proficiency write, and retains the normal Potos
ready flag, Magic Rope and END. Coverage includes Drum-in-logic and pedestal
starts, Random/Swap/Vanilla bosses and duplicate Sprite roles.

Regular play enters through the randomized slot, not Sword acquisition:
Mantis entry `10C -> Door 08D -> map 498`; reverse Jehk entry
`3DB -> Door 304 -> map 497`. Mantis completion still owns event `112`,
fixed Sword Orb, the Mantis randomized prize and Door `08E`.
The reverse slot owns `6BB -> 4E5`, the Jehk randomized prize and Door `038`.
Never substitute the donor boss's reward/progression event.

## Next-phase feasibility audit (NOT enabled compatibility)

Phase 1 remains Mantis-only in both directions. The following are static
engineering candidates, not runtime-approved placements. Piece extents are
not a proof of walkable floor, AI boundaries or correct graphics loading.

| Destination slot | Native map/piece extent | Existing entry and completion | Direct three-shadow candidate | Private-trial redirect candidate |
| --- | --- | --- | --- | --- |
| Mantis | 260, 30x30 | `10C/08D -> 112/08E` | Best first geometry/graphics experiment; native span has only one object. | Current Phase 1. |
| Tropicallo | 290, 50x80 base + 22x13 overlay | `1BE/051 -> 1B9/052` | Plausible normal display; arena-floor patch and two post-fight NPCs must be retained. | Good next candidate; completion owns **two** random prizes and flag `15` progression; preserve flag `14` object visibility separately. |
| Jabberwocky | 143, 40x72 plus buttons/doors | `084/0A0 -> 20C/0A1` | Plausible; three native objects are mutually exclusive Jabber phases, not three spare slots. Preserve hostility/door logic and all non-arena traversal. | Good next candidate; boss unlocks Luka, rather than awarding a new randomized boss prize directly. |
| Frost Gigas | 364, 20x24 | `66B/2CA -> 66D/2CB` | Normal display, but smaller arena needs actual collision/spacing validation. | Good next candidate; preserve Ice/Santa flags, fixed orb, prize and post-return dialogue. |
| Fire Gigas | 495, 32x52 | `236/14B -> 237` | Plausible normal display; one-object span must expand safely. | Later candidate using authoritative Earth Palace return/progression. |
| Minotaur / Metal Mantis | 347, 40x40 / 377, 32x28 base | `2CA` / `527` death events | Plausible normal display; map gates/NPCs and actor ordering still require dedicated tests. | Not just a pool addition: enumerate every entry/exit and preserve each slot's flags. |
| Mech Rider II / Snap Dragon / Great Viper | 100 / 430 / 325 | Destination-owned events | Higher risk: scrolling; shared NPC/puzzle map; layer-2 collision respectively. | Later, only after auditing alternate entries and return paths. |
| Lime / Shade | 489, 24x24, special Mode-7 display | `543/03A -> 544/286 -> 542` | Do **not** put three regular actors into unchanged native slime display. | Possible via regular trial copy; must force ordinary death type and preserve Shade access, not invent a boss prize. |
| Dread / Fortress | 488, 24x24, special Mode-7 display | `424/152 -> 425` | Do **not** reuse unchanged native slime display. | Possible later; keep native `0C0 -> prize -> 0C0 -> 42C` tail, Fortress flag and death-type handling. |
| Wall Face / Doom / Watermelon / dragons / Dark Lich | Special-display or layered boss arenas | Slot-specific | Not part of first direct-replacement experiment; room size alone is insufficient. | Later private-arena candidates, requiring their existing special-entry/completion contracts. |
| Triple Tonpole / Kettle Kin | 361, 24x28 / 46, 22x22 | Existing multi-actor or NPC-to-boss transition | Physical room may fit, but native counter/transformation or NPC lifecycle is incompatible with naive replacement. | Defer until their separate completion state is explicitly adapted. |

Direct replacement is NOT simply changing one species byte to `81`: that is a
logical selection ID. It needs three actual objects (`2E/3F/20`), priority and
layer-correct positions, reliable actor identities, and one slot-local all-three
completion gate. Native shadow event zero plus no exit/checker would strand the
player; giving all three the slot death event would award too early/repeatedly.
One-object native spans cannot be overwritten with three objects in place.
Allocate an audited object block and preserve native traversal boundaries.
Character graphics/palettes, spell/projectile load and free movement must be
validated in the destination room before calling any direct placement safe.

In the reverse direction, Tropicallo/Jabberwocky/Frost Gigas and ordinary regular
bosses are candidates for private native-geometry donor arenas with Jehk's prize
and return tail. Their position tables/map processors still have to use the
donor's physical geometry. Actual Lime/Dread fights in the Jehk slot additionally
need the existing Mode-7 entry/death/neutral-stage restoration architecture
before executing Jehk dialogue. Do not mix Shade/Fortress progression into it.

The current redirect holds one foreign-slot binding, uses Potos completion state
and one private trial map. It cannot safely support several randomized foreign
slots merely by appending `81` to candidate pools. A later expansion must bind
each admitted destination to its own authoritative completion/re-entry state,
and resolve simultaneous-slot ownership first.

After Phase 1 manual acceptance, recommend a **test-only**, one-placement-per-ROM
expansion: Tropicallo first (two-prize/exact-once check), Jabberwocky second
(Luka/doors), Frost third (Santa/return). For each, force a paired reverse ROM
with that ordinary boss in Jehk; keep every other special boss pinned native.
Suggested fixed seeds: `Doppel-Tropicallo-Phase2-2026`,
`Doppel-Jabberwocky-Phase2-2026`, `Doppel-FrostGigas-Phase2-2026` and corresponding
`<Boss>-Jehk-Phase2-2026`. These are a proposed test plan, not generated or enabled
worlds. Separately test direct three-shadow replacement in Mantis before moving
that architecture to any other destination arena.
