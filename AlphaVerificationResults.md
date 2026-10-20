# Alpha verification results

## RC3 verification

Completed 2026-10-20 from the independently exported RC3 source: Release/net462
build passed (0 errors, 25 existing warnings); all 38 production suites passed;
locked restore and the fresh all-transitive NuGet vulnerability audit passed.
The 1,444 registry pairings and four baseline fingerprints are unchanged.
All seven production controls match AlphaProduction.RC3.csv. The reported seed
and repeat are identical: 97EC839534864B8968EED37D89A43BFDF26DBCB580B775F0162E23898FD9E827.
The first Fire Palace chest grants the Drum and all seven Chaos offices remain
closed. Three packaged CLI starter worlds and the repeat retain RC2 hashes.
Headless UI options serialization/round trips passed; no visible GUI/Mesen
acceptance of this package is claimed.

The current runner includes 38 production suites: the inherited 36 plus
KakkaraChaosReachability and KakkaraProgression. The latter asserts Luna stays
Flammie-gated in every Cannon mode, retains Orb/Moon Seed gates, rejects circular
Drum placement, and preserves Drum-out-of-logic initial flight. Ferry events
are unchanged. The exact reported seed and deterministic repeat require the
first Fire Palace chest to grant the Drum; all seven Chaos offices remain closed.

AlphaProduction.RC3.csv changes only mixed-per-character (Kakkara Chaos), to
76BCF20871086CBA7C965A0B6298BEB38B3FBACABCFDCA4DD059177DB603C861.
Six controls retain RC2 hashes. Three real CLI starter profiles plus a repeat
retain their RC2 output hashes. Final results and package hashes are reported
by the release handoff and RELEASE.json; logs/ROMs remain ignored.

## Existing RC2 package

Recorded 2026-10-18: 37 suites passed; Release/net462 build 0 errors and
25 existing warnings; locked restore and live transitive audit passed;
1,444 boss pairings and four ROM/event/door/RNG fixtures matched;
seven control ROMs and three starters plus repeat matched RC1.
All 170 packaged checksums and the source input manifest were verified.

Those are original package checks, not claims of a clean Windows GUI test or
new emulator completion. The package remains immutable.

## Historical RC2 committed-branch verification

Use `release/Invoke-AlphaVerification.ps1` against an independently built
executable exported from this committed source. Its three groups comprise
36 production suites. The one manual-profile-only test from RC2 is omitted
because that manual ROM scaffolding is deliberately not committed.

The runner compares all seven generated control ROM hashes to
`tests/fixtures/AlphaProduction.RC2.csv`; the registry uses
`tests/fixtures/BossEncounterRegistry.RC2.json` for 1,444 admissions and four
fixed ROM/event/door/RNG fingerprints. Fixtures contain hashes, not ROM bytes.

`release/Invoke-AlphaGameplayChecks.ps1` launches the real executable for all
three canonical starter options and a repeat. It checks successful production
simulation, normal Sword/start inventory, native executable/event bounds and
all RC2 starter hashes. No manual subclass or debug profile is used there.

The local handoff reports the exact verified commit and command outcomes.
Raw logs/ROMs stay in ignored output directories, not public source.
Rebuilt EXE hashes need not equal RC2 because of wildcard build metadata;
487 input hashes and gameplay-output hashes must match exactly.

## Human coverage

Clean Windows GUI and complete package-level playthroughs have not been
performed by this repository-only process. Previous maintainer Mesen approvals
for individual features remain acknowledged. Full runs may be performed by
volunteer Alpha testers after technical distribution checks and approval.
