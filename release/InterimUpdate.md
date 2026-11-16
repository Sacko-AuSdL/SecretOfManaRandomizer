# Alpha 0.1 Update 3 candidate

Parent: published v0.1.0-alpha.2 (11af11a6da7ef102e45d1e50f209ddf268a21d73).

The production delta is limited to Todo/Southtown starting locations, the accepted Upper Land hedge, accepted Undine completion/return fixes, Mara's empty-prize collection guard, and Alpha.3 display/assembly metadata. Internal settings/ROM version remains 1.49. No advanced boss campaign or Weapon Power changes are included.

Build on Windows:

```powershell
dotnet restore SoMRandomizer.sln --locked-mode
dotnet build SoMRandomizer.sln -c Release --no-restore -p:DebugType=None -p:DebugSymbols=false
```

Run the focused release suites with `release/Invoke-InterimVerification.ps1`, supplying the built assembly, a legally supplied compatible US ROM and an output directory. Run `tests/OpenWorldTownStarts.Tests.ps1 -AssemblyPath ...` for bounded town/cannon/goal scenarios. `tests/UpperLandOrbAccessibility.Tests.ps1 -AssemblyPath ...` includes native uncharged Javelin contact checks from both approaches.

`release/Verify-InterimSource.py` compares all production inputs with the published parent and rejects unaudited production-file changes. It requires a Git checkout containing the parent tag. The standalone source ZIP is sufficient to rebuild the application without Git.

Use `Prepare-AlphaPackage.ps1` and `Finalize-AlphaPackage.ps1` with a fresh candidate output directory. Never overwrite prior packages. The finalizer requires ten focused suite results, baseline-isolation proof, dependency audit and five actual packaged CLI cases plus their deterministic repeat. These do not constitute full emulator playthroughs.

Todo and Southtown startup, movement, Ring Menu, exits/re-entry and save/load passed user Mesen testing. Mara's intentional empty reward now reports Already got this on subsequent visits; genuine prizes retain their original guards. Native event closure and packed SRAM save/load checks passed. Live uncharged Javelin launch/animation remains a recommended narrow check, separate from the accepted bidirectional Sword access. Keep the published Alpha.2 tag and original package unchanged. Explicit publication approval remains pending; do not treat a local candidate as a published release.
