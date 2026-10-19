# Alpha verification results

## Existing RC2 package

Recorded 2026-10-18: 37 suites passed; Release/net462 build 0 errors and
25 existing warnings; locked restore and live transitive audit passed;
1,444 boss pairings and four ROM/event/door/RNG fixtures matched;
seven control ROMs and three starters plus repeat matched RC1.
All 170 packaged checksums and the source input manifest were verified.

Those are original package checks, not claims of a clean Windows GUI test or
new emulator completion. The package remains immutable.

## Committed branch verification

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
