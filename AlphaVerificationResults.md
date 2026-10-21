# Alpha 0.1 RC4 verification

The existing release checkout was built independently from the development
checkout. Release/net462 passed: 0 errors, 25 existing warnings. Locked restore
and live all-transitive vulnerability audit passed without reported findings.

All 45 production suites passed. These cover boss registry/geometry, expanded
Doppelgangers, Death Link/scaling/returns, Slime/Wall/Triple compatibility, native
map bounds, spells/affinity, Orbs/hints, gameplay options, save/reset music,
normal starting prizes, Cannon travel, Sandship, Christmas and Kakkara/Luna logic.
The final pool has 38 destinations, 1,444 possible pairings, 1,077 Random and
864 Swap admissions, 18 Doppelganger locations and 17 Jehk encounter choices.

Two initial failures were obsolete RC3 expectations, not suppressed defects:

- Source scope now admits the required neutral geometry value types and approved
  production encounters, while still rejecting actual prototype catalogues,
  historical pilot APIs and Weapon Power. All 490 source hashes are checked.
- The Kakkara test now verifies real initial reachability and actual ROM reward
  bytes rather than a frozen Cannon count/chest. All nine cases passed, including
  the exact seed/repeat and equal free/paid route topology and initial checks.
  Seed `370385E350F7D294` has closed Kakkara and Sandship Captain grants the Drum
  in cycle zero. The forced-closed-network solver regression remains unchanged.

Initial failed logs and retest evidence are preserved in private build output;
none of the 45 production suites was excluded. Expanded boss pools intentionally
change old RC3 world hashes; deterministic generation remains required.

The package workflow additionally verifies real UI-binding serialization,
three normal production CLI worlds and a repeat, exact source/runtime/archive
hashes, excluded/private artifact checks and ZIP extraction. Final package
metadata and the handoff report give the results and checksum, not old fixtures.

Manual Mesen acceptance of the integrated features was supplied by the
maintainer, including the final Dragon Worm arena/return correction. No new
emulator run, exhaustive pairing playthrough or clean Windows GUI test is
claimed by this repository-only preparation. Those remain distinct coverage.
