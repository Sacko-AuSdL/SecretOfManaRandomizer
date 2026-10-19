# Secret of Mana Randomizer — unofficial Alpha 0.1

This is Sacko's experimental Open World fork of
[Moppleton's Secret of Mana Randomizer](https://github.com/Moppu/SecretOfManaRandomizer),
not an official upstream release. The source on `release/alpha-0.1` corresponds
to the verified **Alpha 0.1 RC2** package. Publication is still pending approval.

See [the tester guide](AlphaTesterGuide.md), [changelog](AlphaChangelog.md),
[known issues](AlphaKnownIssues.md), and [RC2 provenance](AlphaReleaseCandidate.md).
New direct-arena experiments and Weapon Power are not included.

## Playing

Extract the complete approved Windows ZIP. Requires .NET Framework 4.6.2 or a
compatible later 4.x runtime and your own unmodified US Secret of Mana v1.0 ROM
(2 MiB, optionally a 512-byte copier header). No ROM or external music pack is
supplied. Keep separate saves per seed/version. Start with
`release/StarterSettings/Short.options.txt` and seed `Alpha01-RC1-Short`.
RC1 labels in seed strings are intentional for paired RC1/RC2 verification.

The Alpha focuses on Open World: conservative special-boss integrations,
Sandship, Crystal Orb modes, Per Character/Party Spell Shuffle, Cannon networks,
travel QoL, reduced forging, player magic scaling, cosmetic Manabite and music
restoration. Other upstream modes remain outside this playtest's acceptance scope.

## Building and verification

On Windows with a compatible SDK/MSBuild and .NET Framework targeting references:

```powershell
dotnet restore .\SoMRandomizer.sln --locked-mode
dotnet build .\SoMRandomizer.sln -c Release --no-restore
```

[Release maintenance](release/README.md) documents exact source export,
the 36 production suites, required user-supplied test ROM and starter hash checks.
Build outputs and generated ROMs are ignored, not source inputs.
The pre-existing wildcard assembly version prevents a promise of reproducible
EXE timestamps; all 487 build-input bytes are pinned by the source manifest.

## Credits and support

Moppleton and upstream contributors retain their original authorship.
Manabite artwork/palette by **Tomm (Discord)**; creator permission for use and
redistribution is confirmed by the maintainer. Existing credits/licenses remain;
no additional creator URL or asset license is invented.

See [LICENSE](LICENSE) and [third-party notices](THIRD-PARTY-NOTICES.md).
Report seed, complete options, emulator/version and reproducible steps in the
[fork's Issues](https://github.com/Sacko-AuSdL/SecretOfManaRandomizer/issues).
Never upload ROMs. Community Discord: https://discord.gg/YfmUHqU
