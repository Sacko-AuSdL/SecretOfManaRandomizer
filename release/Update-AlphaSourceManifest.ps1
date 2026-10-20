# RC2 -> RC3 is deliberately a single-production-file update, not a new audit.
param()
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$path=Join-Path $repo 'RELEASE-SOURCE-MANIFEST.json'
$manifest=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
if($manifest.Candidate -ne 'Alpha 0.1 RC2' -or $manifest.Files.Count -ne 487) { throw 'Expected unchanged RC2 manifest.' }
$changed='SoMRandomizer/processing/openworld/cannon/CannonTravelRegions.cs'
foreach($file in $manifest.Files) {
 $hash=(Get-FileHash -LiteralPath (Join-Path $repo $file.Path) -Algorithm SHA256).Hash
 if($file.Path -eq $changed) {
  if($hash -eq $file.SnapshotSha256) { throw 'Kakkara fix missing.' }
  $file.ParentSnapshotSha256=$file.SnapshotSha256
  $file.SnapshotSha256=$hash
  $file.Transform='RC3: retain geographic ownership of physical Potos/Pandora checks; Luna unchanged'
 } elseif($hash -ne $file.SnapshotSha256) { throw ('Unexpected production delta: '+$file.Path) }
}
$manifest.Candidate='Alpha 0.1 RC3'
$manifest.ParentCandidate='Alpha 0.1 RC2'
$manifest.ParentPackageSha256='7EE6E1B5A82B0C0EFBB8B7E375126844823CF9BF9E451038606EB5EF3B63B98F'
$manifest.ProductionIntegration='Clean release branch; RC2 inputs plus verified geographic Kakkara softlock correction'
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
'PASS: 487 RC3 inputs; exactly one production file differs from RC2.'
