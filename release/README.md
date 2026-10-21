# Alpha 0.1 RC4 release maintenance

This existing checkout contains the approved final review integration based on
RC3 commit a421186. It has490 explicit production source/resource inputs. No
new commit/tag is authorized by preparation alone. Do not rewrite alpha.1.

## Build and verify

Build THIS release checkout; no extra worktree or source checkout is required:

```powershell
dotnet restore SoMRandomizer.sln --locked-mode -p:NuGetAudit=true -p:NuGetAuditMode=all
dotnet build SoMRandomizer.sln -c Release --no-restore -p:OutputPath=C:/your/candidate/build-release/ -p:DebugType=None -p:DebugSymbols=false
```

Run Invoke-AlphaVerification.ps1 groups0,1,2 in separate PowerShell processes
with explicit AssemblyPath, SnapshotRoot=this checkout, OutputRoot and SourceRom.
All45 production suites must pass, including acknowledged/retested historical
RC3 assertions. Frozen RC3 ROM hashes are not a valid oracle for newly expanded
boss pools. Deterministic repeats and real reachability/runtime invariants remain
mandatory. Prototype-only harnesses and Weapon Power tests are excluded because
those features are absent, not because a production failure was ignored.

## Package

CandidateRoot contains build-release/, verification/results-0..2.csv and the
live NuGetAudit.json. Prepare-AlphaPackage.ps1 validates the source manifest,
copies the tested runtime/docs, creates the exact source archive and license
notices, and serializes normal starter profiles with real UI bindings.
Run Invoke-AlphaGameplayChecks.ps1 on package/ with RecordCandidate only for
the FIRST verification of a new approved source integration. Save its four
CLI results under gameplay-ui-final/. Later checks against RELEASE.json must
use the recorded hashes, not RecordCandidate.

Finalize-AlphaPackage.ps1 requires45 passing suites, source/runtime hashes,
CLI profiles/repeat and the live dependency audit. It labels the source honestly
as an uncommitted review integration, rejects ROMs/prototypes/private paths,
builds a NEW RC4 ZIP and extracts/checks every file. Then run the normal CLI
checker against that extracted package WITHOUT RecordCandidate.

Clean Windows GUI acceptance is separate from headless UI-binding/CLI checks.
Keep historical packages and manual ROMs. Never stage logs/ROMs/builds. Source
publication needs separate approval to commit, push, create a new tag (suggested
v0.1.0-alpha.2) and publish. No script here creates those Git mutations.
