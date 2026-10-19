# Alpha release maintenance

This branch contains the exact 487 RC2 production build inputs, plus permanent
tests, documentation, licenses and maintenance scripts. It contains no game ROM
or manual profile installer. Supply your own compatible US Secret of Mana v1.0
test ROM via `-SourceRom`; tests do not download one.

## Verify committed source independently

From this checkout, choose a NEW ignored export directory:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\release\New-AlphaSourceSnapshot.ps1 -SnapshotRoot .\.codex-build\source-check
dotnet restore .\.codex-build\source-check\SoMRandomizer.sln --locked-mode -p:NuGetAudit=true -p:NuGetAuditMode=all -p:NuGetAuditLevel=low -p:TreatWarningsAsErrors=true
dotnet build .\.codex-build\source-check\SoMRandomizer.sln -c Release --no-restore -p:OutputPath=C:/your/absolute/verification-build/ -p:DebugType=None -p:DebugSymbols=false
```

Use a writable ignored output directory, replacing the illustrative output path.
Run each group in a separate PowerShell process with explicit paths:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\release\Invoke-AlphaVerification.ps1 -Group 0 -AssemblyPath C:/your/verification-build/SoMRandomizer.exe -SnapshotRoot .\.codex-build\source-check -SourceRom C:/your/legal-base.sfc
powershell -NoProfile -ExecutionPolicy Bypass -File .\release\Invoke-AlphaVerification.ps1 -Group 1 -AssemblyPath C:/your/verification-build/SoMRandomizer.exe -SnapshotRoot .\.codex-build\source-check -SourceRom C:/your/legal-base.sfc
powershell -NoProfile -ExecutionPolicy Bypass -File .\release\Invoke-AlphaVerification.ps1 -Group 2 -AssemblyPath C:/your/verification-build/SoMRandomizer.exe -SnapshotRoot .\.codex-build\source-check -SourceRom C:/your/legal-base.sfc
powershell -NoProfile -ExecutionPolicy Bypass -File .\release\Invoke-AlphaGameplayChecks.ps1 -PackageRoot C:/your/verification-build -SourceRom C:/your/legal-base.sfc
```

The 36 suites omit only RC2's manual-profile-only test; the manual supplies/
teleport code is not shipped in this branch. All production regressions remain.
The registry uses the committed admission/hash fixture rather than a developer's
local baseline. The starter checker falls back to committed canonical options
and RC2 package metadata when the fresh build directory has no packaged docs.
All generated ROM hashes must match the fixed references.

Run a fresh NuGet transitive audit and `git diff --check`. Outputs go to ignored
folders. Never stage verification logs, caches, ROMs or builds. Nine historical
trailing-space-only lines in two RC2 source files are preserved to retain exact
source bytes; do not silently trim them or change the frozen manifest.

## Distribution boundary

The existing RC2 ZIP, not a newly rebuilt package, is the approved artifact.
See AlphaReleaseCandidate.md and RC2-PACKAGE.json for hashes. The wildcard
assembly version can change EXE metadata; normal ROM behavior must not change.
Tomm's Manabite assets, upstream authorship and dependency notices are retained.
Clean Windows GUI/full-run coverage is not established by these scripts.
