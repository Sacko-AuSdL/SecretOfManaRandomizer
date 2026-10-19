# Alpha 0.1 RC2 dependency security

RC2 rechecked 2026-10-18: locked restore with all-dependency/low-severity auditing
and warnings-as-errors passes; a live transitive vulnerability query reports
no known vulnerable packages. Project and lock bytes are unchanged from RC1.
The servicing version remains 8.0.6, target net462; release-scope tests verify
the actual locked, embedded and loose DLLs. The RC1 analysis below is retained.

Checked 2026-10-16. The target remains **.NET Framework 4.6.2**; no runtime or
dependency-major migration is part of this change.

## Advisory and application reachability

The direct `System.Text.Json 8.0.4` PackageReference triggered
**CVE-2024-43485 / GHSA-8g4q-xg66-9fp4**, a high-severity algorithmic-complexity
denial of service involving deserialization into models with
`[JsonExtensionData]`. Affected NuGet ranges are 8.0.0–8.0.4 and 6.0.0–6.0.9;
the first patched releases are 8.0.5 and 6.0.10.
[Microsoft's advisory](https://github.com/dotnet/runtime/security/advisories/GHSA-8g4q-xg66-9fp4)
describes the trigger and mitigation.

The application's only System.Text.Json call is
`util/UpdateCheck.cs: JsonDocument.Parse(responseBody)`, followed by a `tag_name`
lookup in the GitHub update response. This is reachable from the update check,
but the repository contains no JsonSerializer deserialization or
JsonExtensionData model. The specific published trigger is therefore not used
by current application code. That is not a reason to ship the vulnerable
package, nor a general claim that arbitrary JSON parsing is risk-free.

## Selected update

Use **System.Text.Json 8.0.6**, a servicing update in the same major line, rather
than the locally cached 10.x major version. NuGet provides a net462 asset for
8.0.6; its dependencies retain the existing 8.0 interfaces/encoding packages.
[Package compatibility and dependency metadata](https://www.nuget.org/packages/System.Text.Json/8.0.6)
support this choice.

Persistent dependency changes:

- `SoMRandomizer/SoMRandomizer.csproj`: 8.0.4 → 8.0.6.
- New `SoMRandomizer/packages.lock.json`: pins the resolved graph, including the
  pre-existing floating 4.x references, with content hashes. No lock previously
  existed. Release restoration uses `--locked-mode`.
- Generated `obj/project.assets.json` and NuGet caches change during restore;
  they are not source/distribution inputs.

## Verification and remaining limits

The first restricted restore could not open the NuGet socket. An authorized
network-enabled restore succeeded. The isolated source snapshot then passed a
locked restore with audit enabled for **all** dependencies at **low** severity
and warnings treated as errors. The follow-up command is:

```powershell
dotnet list <snapshot-project> package --vulnerable --include-transitive --no-restore --format json
```

Its live NuGet response reported no vulnerable packages. No audit suppression,
ignored feed, severity downgrade or wholesale dependency upgrade was used.
The source-snapshot Release build and regression suites use the patched graph.
The release-scope test checks the lock, output DLL product version and equality
of embedded/loose System.Text.Json bytes.

This records known advisory coverage at the check date, not a guarantee against
future disclosures. Re-audit before any later public release. Clean-machine UI
smoke testing and volunteer full-run coverage remain outstanding; personal
playthrough completion is not a prerequisite for inviting Alpha testers.
