param([Parameter(Mandatory=$true)][string]$SnapshotRoot)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$destination=[IO.Path]::GetFullPath($SnapshotRoot)
if(Test-Path -LiteralPath $destination) { throw 'Never overwrite an existing source export.' }
if($destination -eq $repo -or $repo.StartsWith($destination+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Do not export over this checkout or its parent.' }
$manifestPath=Join-Path $repo 'RELEASE-SOURCE-MANIFEST.json'
$manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if($manifest.Candidate -ne 'Alpha 0.1 RC3' -or $manifest.Files.Count -ne 487) { throw 'Unexpected release manifest.' }
# Validate everything BEFORE creating output. No HEAD substitution, experiment
# removal, manual profile or dirty-development-tree reconstruction is needed.
$allowed=@{}
foreach($file in $manifest.Files) {
 if($file.Path -match '(^|/)\.\.(/|$)|WeaponPowerCalculator|DirectBossPlacement|BossDirectAssessment|DirectBossJumpPositions|\.(sfc|smc|srm|pdb|log)$') { throw 'Disallowed source input.' }
 $source=[IO.Path]::GetFullPath((Join-Path $repo $file.Path))
 if(-not $source.StartsWith($repo+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid source path.' }
 if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $file.SnapshotSha256) { throw ('RC3 source mismatch: '+$file.Path) }
 $allowed[$source]=$true
}
foreach($file in Get-ChildItem (Join-Path $repo 'SoMRandomizer') -Recurse -File -Filter '*.cs') {
 if($file.FullName -match '[\\/](obj|bin)[\\/]') { continue }
 if(-not $allowed.ContainsKey($file.FullName)) { throw ('Unlisted C# source: '+$file.FullName) }
}
[void][IO.Directory]::CreateDirectory($destination)
foreach($file in $manifest.Files) {
 $target=Join-Path $destination $file.Path
 [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
 Copy-Item -LiteralPath (Join-Path $repo $file.Path) -Destination $target
}
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $destination 'RELEASE-SOURCE-MANIFEST.json')
'PASS: exported all 487 exact RC3 build inputs and manifest. No ROMs, tests, manual profiles or build outputs.'
