param([Parameter(Mandatory=$true)][string]$CandidateRoot,[string]$StageName='package',[string]$ArtifactsName='artifacts')
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));$root=[IO.Path]::GetFullPath($CandidateRoot)
$stage=Join-Path $root $StageName;$build=Join-Path $root 'build-release'
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Hash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
$results=@();foreach($group in 0..2){$results+=Import-Csv (Join-Path $root ('verification/results-'+$group+'.csv'))}
Require ($results.Count -eq 45 -and @($results|Select-Object -ExpandProperty Test -Unique).Count -eq 45 -and @($results|Where-Object ExitCode -ne '0').Count -eq 0) 'Require all 45 final production suites, including recorded retests.'
$game=Get-Content (Join-Path $root 'gameplay-ui-final/results.json') -Raw|ConvertFrom-Json
Require ($game.Count -eq 4 -and @($game|Where-Object Simulation -ne 'passed').Count -eq 0 -and $game[0].Sha256 -eq $game[3].Sha256) 'Standalone CLI cases/repeat missing.'
$audit=Get-Content (Join-Path $root 'NuGetAudit.json') -Raw|ConvertFrom-Json
Require ($audit.version -eq 1 -and $audit.parameters -match 'include-transitive' -and $audit.projects.Count -eq 1 -and ($audit|ConvertTo-Json -Depth 30) -notmatch 'vulnerabilities|"problems"') 'Dependency audit missing or has findings.'
$manifest=Get-Content (Join-Path $repo 'RELEASE-SOURCE-MANIFEST.json') -Raw|ConvertFrom-Json
Require ($manifest.Candidate -eq 'Alpha 0.1 RC4' -and $manifest.Files.Count -eq 490) 'Unexpected final source inventory.'
foreach($file in $manifest.Files){Require ((Hash (Join-Path $repo $file.Path)) -eq $file.SnapshotSha256) ('Source changed after verification: '+$file.Path)}
foreach($file in Get-ChildItem $build -File|Where-Object {$_.Extension -eq '.dll' -or $_.Name -in @('SoMRandomizer.exe','SoMRandomizer.exe.config')}){
 Require ((Hash $file.FullName) -eq (Hash (Join-Path $stage $file.Name))) ('Packaged runtime differs from tested build: '+$file.Name)
}
$counts=Get-Content (Join-Path $root 'verification/BossCompatibilityCounts.json') -Raw|ConvertFrom-Json
$head=(& git -c ('safe.directory='+$repo.Replace('\','/')) -C $repo rev-parse HEAD).Trim()
Require ($head -eq 'a4211863f5fce354f63d0018b1dc31ec3cfd501c') 'Parent release commit changed; do not rewrite tags/history.'
@('# Exact buildable RC4 source','','Alpha-0.1-RC4-source.zip contains the 490 verified production source/resource inputs and their SHA-256 manifest. It excludes Weapon Power, prototype catalogues/pilots, tests/manual generators and game ROMs.','','On Windows with an SDK/MSBuild, extract the archive and run:','','    dotnet restore SoMRandomizer.sln --locked-mode','    dotnet build SoMRandomizer.sln -c Release --no-restore -p:DebugType=None -p:DebugSymbols=false','','Target remains .NET Framework 4.6.2. Restore obtains the targeting assemblies and locked dependencies; no developer cache is included. Source hashes establish the exact inputs; wildcard assembly version metadata means independent EXE bytes can differ.','','This is an uncommitted review integration based on RC3, not a claim that the old published commit/tag contains these changes. No new commit or tag has been created. See LICENSE and THIRD-PARTY-NOTICES.md.')|Set-Content -LiteralPath (Join-Path $stage 'Source/README.md') -Encoding UTF8
$release=[ordered]@{Version='Alpha 0.1 RC4';Status='local review candidate; not published';HistoricalBaseline=$manifest.HistoricalBaseline;ParentReleaseCommit=$head;SourceState=$manifest.SourceState;SuggestedTag='v0.1.0-alpha.2';TargetFramework='net462';ApplicationSha256=(Hash (Join-Path $stage 'SoMRandomizer.exe'));SourceManifestSha256=(Hash (Join-Path $repo 'RELEASE-SOURCE-MANIFEST.json'));SourceArchiveSha256=(Hash (Join-Path $stage 'Source/Alpha-0.1-RC4-source.zip'));ProductionSuitesPassed=45;BossCompatibility=$counts;StandaloneGenerationCases=3;DeterministicRepeat='passed';DependencyAuditUtc=[DateTime]::UtcNow.ToString('yyyy-MM-dd');KnownVulnerabilitiesReported=0;CleanWindowsGui='not tested';ManualMesen='Maintainer confirms accepted Doppelganger expansion, Death Link, scaling, Jehk, Three Sprites, save/reset and Dragon Worm ArenaFix2';ExhaustivePairingPlaythrough='not claimed';WeaponPower='excluded';UnsupportedPrototypes='excluded';Profiles=@($game|Where-Object Name -ne 'Short-Repeat'|ForEach-Object {[ordered]@{Name=$_.Name;Seed=$_.Seed;Goal=$_.Goal;ExpectedRomSha256=$_.Sha256;OptionsFile=('StarterSettings/'+$_.Name+'.options.txt')}})}
$release|ConvertTo-Json -Depth 9|Set-Content -LiteralPath (Join-Path $stage 'RELEASE.json') -Encoding UTF8
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$private='(?i)apzca|D:[\\/]views[\\/]tools[\\/]bots|C:[\\/]Users[\\/][^\\/\s]+|AKIA[0-9A-Z]{16}|-----BEGIN (RSA )?PRIVATE KEY-----'
$forbidden='(?i)(^|/)(obj|bin|tests|\.git|\.codex[^/]*)(/|$)|WeaponPowerCalculator|DirectBossPlacement|BossDirectAssessment|DirectBossJumpPositions|\.(sfc|smc|srm|state|pdb|log|ps1|py)$'
foreach($file in Get-ChildItem $stage -Recurse -File){
 $relative=$file.FullName.Substring($stage.Length+1).Replace('\','/');Require ($relative -notmatch $forbidden) ('Excluded artifact: '+$relative)
 if($file.Extension -eq '.zip'){
  $archive=[IO.Compression.ZipFile]::OpenRead($file.FullName)
  try{
   Require ($archive.Entries.Count -eq $manifest.Files.Count+1) 'Source archive inventory mismatch.'
   $sourceEntries=@{}
   foreach($entry in $archive.Entries){
    Require (-not $sourceEntries.ContainsKey($entry.FullName)) 'Duplicate source archive path.'
    $sourceEntries[$entry.FullName]=$true
    Require ($entry.FullName -notmatch $forbidden -and $entry.FullName -notmatch '(^|/)\.\.(/|$)') 'Excluded source/archive path.'
    $stream=$entry.Open();$buffer=[IO.MemoryStream]::new()
    try{$stream.CopyTo($buffer);$bytes=$buffer.ToArray()}finally{$stream.Dispose();$buffer.Dispose()}
    $expected=if($entry.FullName -eq 'RELEASE-SOURCE-MANIFEST.json'){Hash (Join-Path $repo $entry.FullName)}else{
     $inputEntry=@($manifest.Files|Where-Object Path -ceq $entry.FullName)
     Require ($inputEntry.Count -eq 1) ('Unlisted source archive entry: '+$entry.FullName)
     $inputEntry[0].SnapshotSha256
    }
    $sourceSha=[Security.Cryptography.SHA256]::Create()
    try{$actual=[BitConverter]::ToString($sourceSha.ComputeHash($bytes)).Replace('-','')}finally{$sourceSha.Dispose()}
    Require ($actual -eq $expected) ('Source archive byte mismatch: '+$entry.FullName)
    Require ([Text.Encoding]::UTF8.GetString($bytes) -notmatch $private -and [Text.Encoding]::Unicode.GetString($bytes) -notmatch $private) ('Private data in source: '+$entry.FullName)
   }
  }finally{$archive.Dispose()}
 }else{
  $bytes=[IO.File]::ReadAllBytes($file.FullName)
  Require ([Text.Encoding]::UTF8.GetString($bytes) -notmatch $private -and [Text.Encoding]::Unicode.GetString($bytes) -notmatch $private) ('Private data in package: '+$relative)
 }
}
$hashes=foreach($file in Get-ChildItem $stage -Recurse -File|Sort-Object FullName){if($file.Name -ne 'SHA256SUMS.txt'){(Hash $file.FullName).ToLowerInvariant()+'  '+$file.FullName.Substring($stage.Length+1).Replace('\','/')}}
[IO.File]::WriteAllLines((Join-Path $stage 'SHA256SUMS.txt'),[string[]]$hashes,[Text.UTF8Encoding]::new($false))
$artifacts=Join-Path $root $ArtifactsName;[void][IO.Directory]::CreateDirectory($artifacts)
$zipPath=Join-Path $artifacts 'SecretOfManaRandomizer-Alpha-0.1-RC4.zip'
Require (-not (Test-Path -LiteralPath $zipPath)) 'Never overwrite an existing candidate ZIP.'
[IO.Compression.ZipFile]::CreateFromDirectory($stage,$zipPath,[IO.Compression.CompressionLevel]::Optimal,$false)
$extract=Join-Path $root 'extracted RC4 review'
Require (-not (Test-Path -LiteralPath $extract)) 'Do not overwrite an existing extraction.'
$archive=[IO.Compression.ZipFile]::OpenRead($zipPath)
try{
 Require ($archive.Entries.Count -eq $hashes.Count+1) 'ZIP inventory mismatch.'
 foreach($entry in $archive.Entries){
  Require ($entry.FullName -notmatch '(^|/)\.\.(/|$)' -and -not [IO.Path]::IsPathRooted($entry.FullName)) 'Unsafe ZIP path.'
  $stream=$entry.Open();$sha=[Security.Cryptography.SHA256]::Create()
  try{$actual=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')}finally{$stream.Dispose();$sha.Dispose()}
  Require ($actual -eq (Hash (Join-Path $stage $entry.FullName))) ('ZIP entry byte mismatch: '+$entry.FullName)
 }
}finally{$archive.Dispose()}
[IO.Compression.ZipFile]::ExtractToDirectory($zipPath,$extract)
foreach($line in $hashes){$parts=$line -split '  ',2;Require ((Hash (Join-Path $extract $parts[1])) -eq $parts[0]) ('Extraction hash mismatch: '+$parts[1])}
$zipHash=Hash $zipPath
[IO.File]::WriteAllText(($zipPath+'.sha256'),($zipHash.ToLowerInvariant()+'  '+[IO.Path]::GetFileName($zipPath)+"`n"),[Text.UTF8Encoding]::new($false))
[ordered]@{Zip=$zipPath;Sha256=$zipHash;ChecksumFile=($zipPath+'.sha256');Extracted=$extract;Files=($hashes.Count+1);ApplicationSha256=$release.ApplicationSha256;SourceManifestSha256=$release.SourceManifestSha256}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'PACKAGE-RESULT.json')
'PASS: exact source/runtime/package inventory, no excluded/private artifacts, ZIP extraction and every file hash.'
'ZIP: '+$zipPath
'SHA256: '+$zipHash
