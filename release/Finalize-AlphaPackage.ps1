param(
 [Parameter(Mandatory=$true)][string]$CandidateRoot,
 [Parameter(Mandatory=$true)][string]$DevelopmentRoot,
 [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9-]*$')][string]$StageName='package-final',
 [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9-]*$')][string]$ArtifactsName='artifacts-final'
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')); $root=[IO.Path]::GetFullPath($CandidateRoot)
$stage=Join-Path $root $StageName; $snapshot=Join-Path $root 'source'
function Require([bool]$Value,[string]$Message) { if(-not $Value) { throw $Message } }
function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
$results=@(); foreach($group in 0..2) { $results+=Import-Csv (Join-Path $root ('verification/results-'+$group+'.csv')) }
Require ($results.Count -eq 38 -and @($results|Where-Object ExitCode -ne '0').Count -eq 0 -and @($results|Select-Object -ExpandProperty Test -Unique).Count -eq 38) 'Require all 38 production-scope suites, including Kakkara/Luna regressions.'
$game=Get-Content (Join-Path $root 'gameplay-ui-final/results.json') -Raw | ConvertFrom-Json
Require ($game.Count -eq 4 -and @($game|Where-Object Simulation -ne 'passed').Count -eq 0 -and $game[0].Sha256 -eq $game[3].Sha256) 'Require three successful standalone cases and deterministic repeat.'
$audit=Get-Content (Join-Path $root 'NuGetAudit.json') -Raw | ConvertFrom-Json
Require ($audit.version -eq 1 -and $audit.parameters -match 'include-transitive' -and $audit.projects.Count -eq 1) 'Require a recorded live dependency audit.'
Require (($audit|ConvertTo-Json -Depth 30) -notmatch 'vulnerabilities|"problems"') 'Dependency audit contains findings.'
$assets=Get-Content (Join-Path $snapshot 'SoMRandomizer/obj/project.assets.json') -Raw | ConvertFrom-Json
Require (@($assets.logs|Where-Object {$_.code -match '^NU(190|1301|1801)'}).Count -eq 0) 'Restore contains vulnerability/feed errors.'
Require ($null -ne $assets.libraries.'System.Text.Json/8.0.6') 'Patched dependency not resolved.'
$originals=Get-Content (Join-Path $root 'protected-original-hashes.json') -Raw | ConvertFrom-Json
foreach($property in $originals.PSObject.Properties) { Require ((Hash (Join-Path $DevelopmentRoot $property.Name)) -eq $property.Value) ('Protected original modified: '+$property.Name) }
$sourceManifest=Get-Content (Join-Path $snapshot 'RELEASE-SOURCE-MANIFEST.json') -Raw | ConvertFrom-Json
foreach($inputFile in $sourceManifest.Files) { Require ((Hash (Join-Path $snapshot $inputFile.Path)) -eq $inputFile.SnapshotSha256) 'Source snapshot changed after verification.' }
$build=Join-Path $root 'build-release'
foreach($file in Get-ChildItem $build -File | Where-Object { $_.Extension -eq '.dll' -or $_.Name -in @('SoMRandomizer.exe','SoMRandomizer.exe.config') }) {
 Require ((Hash $file.FullName) -eq (Hash (Join-Path $stage $file.Name))) ('Packaged runtime differs from tested build: '+$file.Name)
}
# Refresh only player documents; never replace the tested executable or sources.
$documents=@{ 'AlphaTesterGuide.md'='PlayerGuide.md';'AlphaChangelog.md'='Changelog.md';'AlphaKnownIssues.md'='KnownIssues.md';'AlphaCleanWindowsChecklist.md'='CleanWindowsChecklist.md' }
foreach($key in $documents.Keys) { Copy-Item -LiteralPath (Join-Path $repo $key) -Destination (Join-Path $stage $documents[$key]) }
@('# Buildable source','','Alpha-0.1-RC3-source.zip contains all 487 exact production source/resource inputs plus the content-hash manifest. Excluded: Weapon Power, prototype classes/APIs, Frost/Jehk pilot, manual generators/tests.','','On Windows with an SDK/MSBuild and .NET Framework 4.6.2 targeting references, extract it and run:','','    dotnet restore SoMRandomizer.sln --locked-mode -p:NuGetAudit=true -p:NuGetAuditMode=all -p:NuGetAuditLevel=low -p:TreatWarningsAsErrors=true','    dotnet build SoMRandomizer.sln -c Release --no-restore -p:DebugType=None -p:DebugSymbols=false','','Verify input hashes against RELEASE-SOURCE-MANIFEST.json. Relative to RC2, only CannonTravelRegions.cs changes: physical Potos/Pandora checks no longer travel with the starting party. Luna remains Flammie-gated.','NuGet access is needed to restore development dependencies, not to run the supplied application. The wildcard assembly version and Deterministic=false mean independent EXE bytes can differ; source hashes and recorded build/package hashes establish provenance, not reproducible PE timestamps.','See LICENSE and THIRD-PARTY-NOTICES.md. This is an unofficial experimental fork; normal GUI/full-run acceptance remains outstanding.') | Set-Content -LiteralPath (Join-Path $stage 'Source/README.md') -Encoding UTF8
$releaseCommit=(& git -c ('safe.directory='+$repo.Replace('\','/')) -C $repo rev-parse HEAD).Trim()
Require ($LASTEXITCODE -eq 0 -and $releaseCommit -match '^[a-f0-9]{40}$') 'Cannot identify release source commit.'
Require (-not (& git -c ('safe.directory='+$repo.Replace('\','/')) -C $repo status --porcelain --untracked-files=normal)) 'Commit verified release sources before final packaging.'
$release=[ordered]@{Version='Alpha 0.1 RC3';Status='unofficial experimental candidate; awaiting approval and clean Windows smoke test';BaseCommit=$sourceManifest.BaseCommit;ReleaseCommit=$releaseCommit;IncludesUncommittedProductionIntegration=$false;TargetFramework='net462';ApplicationSha256=(Hash (Join-Path $stage 'SoMRandomizer.exe'));SystemTextJsonPackage='8.0.6';SystemTextJsonBinaryProductVersion='8.0.18';KnownVulnerabilitiesReported=0;AuditDateUtc=[DateTime]::UtcNow.ToString('yyyy-MM-dd');FocusedSuitesPassed=38;StandaloneGenerationCases=3;DeterministicRepeat='passed';CleanWindows='not tested';FullGameplay='volunteer coverage pending, not an invitation prerequisite';WeaponPower='excluded';ManualHarnesses='excluded';ExperimentalPilotCode='removed';ManabitePermission='Tomm (Discord); creator permission for use and redistribution confirmed by maintainer 2026-10-18; no additional conditions supplied';Profiles=@($game|Where-Object Name -ne 'Short-Repeat'|ForEach-Object { [ordered]@{Name=$_.Name;Seed=$_.Seed;Goal=$_.Goal;ExpectedRomSha256=$_.Sha256;OptionsFile=('StarterSettings/'+$_.Name+'.options.txt')} })}
$release['SourceArchiveSha256']=Hash (Join-Path $stage 'Source/Alpha-0.1-RC3-source.zip')
$release['SourceManifestSha256']=Hash (Join-Path $snapshot 'RELEASE-SOURCE-MANIFEST.json')
$release | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $stage 'RELEASE.json') -Encoding UTF8
# Inspect both the outer staging tree and every entry of the bundled source ZIP.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$privatePattern='(?i)apzca|D:[\\/]views[\\/]tools[\\/]bots|C:[\\/]Users[\\/][^\\/\s]+|AKIA[0-9A-Z]{16}|-----BEGIN (RSA )?PRIVATE KEY-----'
foreach($file in Get-ChildItem $stage -Recurse -File) {
 $relative=$file.FullName.Substring($stage.Length+1).Replace('\','/')
 Require ($relative -notmatch '(?i)(^|/)(obj|bin|tests|\.git|\.codex[^/]*)(/|$)|\.(sfc|smc|srm|state|pdb|log|ps1)$|WeaponPowerCalculator') ('Disallowed package file: '+$relative)
 if($file.Extension -eq '.zip') {
  $zip=[IO.Compression.ZipFile]::OpenRead($file.FullName)
  try {
   Require ($zip.Entries.Count -eq $sourceManifest.Files.Count+1) 'Source archive has unexpected entries.'
   foreach($entry in $zip.Entries) {
    Require ($entry.FullName -notmatch '(?i)(^|/)(obj|bin|tests|\.git|\.codex[^/]*)(/|$)|WeaponPowerCalculator|\.(sfc|smc|srm|pdb|log|ps1)$') 'Development/test data in source archive.'
    $stream=$entry.Open(); $buffer=[IO.MemoryStream]::new()
    try { $stream.CopyTo($buffer); $bytes=$buffer.ToArray() } finally { $stream.Dispose(); $buffer.Dispose() }
    Require ([Text.Encoding]::UTF8.GetString($bytes) -notmatch $privatePattern -and [Text.Encoding]::Unicode.GetString($bytes) -notmatch $privatePattern) ('Private data in source entry: '+$entry.FullName)
   }
  } finally { $zip.Dispose() }
 } else {
  $bytes=[IO.File]::ReadAllBytes($file.FullName)
  Require ([Text.Encoding]::UTF8.GetString($bytes) -notmatch $privatePattern -and [Text.Encoding]::Unicode.GetString($bytes) -notmatch $privatePattern) ('Private data in package file: '+$relative)
 }
}
$hashes=@(); foreach($file in Get-ChildItem $stage -Recurse -File | Sort-Object FullName) { if($file.Name -eq 'SHA256SUMS.txt') { continue }; $relative=$file.FullName.Substring($stage.Length+1).Replace('\','/'); $hashes+=((Hash $file.FullName).ToLowerInvariant()+'  '+$relative) }
[IO.File]::WriteAllLines((Join-Path $stage 'SHA256SUMS.txt'),[string[]]$hashes,[Text.UTF8Encoding]::new($false))
$artifacts=Join-Path $root $ArtifactsName; [void][IO.Directory]::CreateDirectory($artifacts)
$zipPath=Join-Path $artifacts 'SecretOfManaRandomizer-Alpha-0.1-RC3.zip'
Require (-not (Test-Path $zipPath)) 'Never overwrite a completed RC ZIP; choose a new candidate.'
[IO.Compression.ZipFile]::CreateFromDirectory($stage,$zipPath,[IO.Compression.CompressionLevel]::Optimal,$false)
$zip=[IO.Compression.ZipFile]::OpenRead($zipPath)
try {
 Require ($zip.Entries.Count -eq $hashes.Count+1) 'ZIP file inventory differs.'
 foreach($entry in $zip.Entries) {
  $stream=$entry.Open(); $sha=[Security.Cryptography.SHA256]::Create()
  try { $actual=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','') } finally { $stream.Dispose(); $sha.Dispose() }
  Require ($actual -eq (Hash (Join-Path $stage $entry.FullName))) ('ZIP byte mismatch: '+$entry.FullName)
 }
} finally { $zip.Dispose() }
$zipHash=Hash $zipPath
[IO.File]::WriteAllText(($zipPath+'.sha256'),($zipHash.ToLowerInvariant()+'  '+[IO.Path]::GetFileName($zipPath)+"`n"),[Text.UTF8Encoding]::new($false))
Write-Output ('PRIVATE RC ZIP: '+$zipPath)
Write-Output ('SHA-256: '+$zipHash)
Write-Output ('Files: '+($hashes.Count+1)+'. Unofficial Alpha; clean Windows and volunteer full-run coverage remain pending. Nothing published.')
