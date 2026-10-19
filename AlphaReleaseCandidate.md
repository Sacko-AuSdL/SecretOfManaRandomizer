# Alpha 0.1 RC2 source and package provenance

This isolated release branch records RC2's exact production source.
Local release commits are authorized; push, tags, publication and announcements
remain unauthorized. The original development checkout and RC2 ZIP are unchanged.

## Approved artifact

- Filename: `SecretOfManaRandomizer-Alpha-0.1-RC2.zip`
- Size: 5,664,295 bytes; 171 files.
- ZIP SHA-256: `7EE6E1B5A82B0C0EFBB8B7E375126844823CF9BF9E451038606EB5EF3B63B98F`
- Original EXE SHA-256: `F62B9E8AE903034012822A1F44CCFC41ABE15751B2298173B5635D4420ED1BD2`
- Source archive SHA-256: `30EE4E3BE0AFFCE76A21FF6F87CE10A9E50741652418B10301E425336D63DFD4`
- Manifest SHA-256: `22E854AB32903F56C1C9C7C17A7DB50F306E498CA1EC081855F3B1C444D730E3`

`RELEASE-SOURCE-MANIFEST.json` is copied unchanged from that package and lists
all 487 exact build inputs. `release/RC2-PACKAGE.json` retains the original
package metadata and starter ROM hashes. No ZIP/EXE/ROM is committed.

## History and cleanup

Base commit: `1fabbb3741a4b6843d25ef933a6a0985c5fe2f1f`.
The base alone omitted the approved Doppelganger/registry integration.
This branch adds the clean RC2 version, not the dirty development version.

Excluded prototype files/types: DirectBossPlacement, BossDirectAssessment and
DirectBossJumpPositions, including their exclusively experimental nested types.
Also removed: the Frost/Jehk pilot field, construction branch, template/log
special cases, ManualPilot capability, assessment APIs and plando bypass.
Weapon Power, manual profile installers and prototype generators are absent.

Retained: production BossEncounterRegistry/BossEncounterBinding admission and
destination metadata, approved Mantis/Jehk Doppelganger adapters, NoEnemies
native-trial preservation and all existing Slime/Wall/Triple/Sandship behavior.
No new public boss combinations or RNG draws are introduced.

Ten inherited source files differ from raw base blobs by EOL only; preserving
these bytes is necessary to match the approved manifest. `.gitattributes`
prevents checkout normalization of build inputs. Ignore-EOL review confirms no
behavior edits in those ten files. Nine pre-existing trailing-space-only lines
in MainForm_OpenWorldPresets.cs and Tileset16.cs are intentionally retained.
No source formatting cleanup or replacement candidate is hidden in this branch.

## Verification evidence and reproduction

Original RC2 verification (2026-10-18): 37 suites passed, 1,444 registry pairings
and four baseline fixtures passed; seven production controls and all three
starter/repeat outputs matched RC1. Fresh extraction verified 170 checksums.
Both Release builds passed with 0 errors / 25 existing warnings.

The public branch excludes the manual-equipment profile and its one profile-only
test. Its **36 production suites** preserve all relevant production coverage and
add no manual teleport or debug grants. Run committed-source verification as
documented in `release/README.md`; results identify the verified local Git tip.
The permanent fixtures contain hashes/admission metadata only, not ROM data.

`release/New-AlphaSourceSnapshot.ps1` verifies and exports all 487 inputs from
this checkout, refusing hash mismatches or extra compiled C# files. Restore/build
the exported source independently to verify committed build provenance.
Normal ROM hashes must match RC2; source-scope tests require excluded types/APIs
and settings to be absent.

The target remains net462 and System.Text.Json remains 8.0.6 with a locked graph.
The original wildcard version/Deterministic=false mean a new EXE hash may differ
because of build metadata even when input bytes and ROM behavior match.
The approved ZIP must not be replaced with the new verification build.

## Credits and pending acceptance

Manabite by **Tomm (Discord)**, with permission for use and redistribution
confirmed by the maintainer. Upstream authorship and all applicable notices
are preserved. No additional asset terms or creator URL are invented.

Clean Windows GUI smoke testing is still pending. No new Mesen/full-playthrough
acceptance is claimed. Full runs are volunteer coverage, not a mandatory personal
playthrough gate before inviting Alpha testers after distribution checks.
