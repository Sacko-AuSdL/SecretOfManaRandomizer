param(
 [ValidateRange(0,2)][int]$Group=0,
 [string]$AssemblyPath='',
 [string]$SnapshotRoot='',
 [string]$OutputRoot='',
 [Parameter(Mandatory=$true)][string]$SourceRom
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if(-not $AssemblyPath) { $AssemblyPath=Join-Path $repo 'SoMRandomizer\bin\Release\net462\SoMRandomizer.exe' }
if(-not $SnapshotRoot) { $SnapshotRoot=$repo }
if(-not $OutputRoot) { $OutputRoot=Join-Path $repo '.codex-build\verification' }
$output=[IO.Path]::GetFullPath($OutputRoot); [void][IO.Directory]::CreateDirectory($output)
$assembly=(Resolve-Path $AssemblyPath).Path
$sets=@(
 @('BossEncounterRegistry','BossDoppelgangerCompatibility','BossLimeSlimeCompatibility','BossDreadSlimeCompatibility','BossWallCompatibility','BossTripleTonpoleCompatibility','EnemySwapsNativeMapBounds'),
 @('SpellShuffle','PartySpellShuffle','SpellShuffleAffinity','CrystalOrbDialog','CrystalOrbRequirements','CrystalOrbWeaponBreaking','CrystalOrbHints','PlayerMagicDamage','WeaponUpgradeCosts','ManaBeastAppearance','SaveMusicRestoration','SoftResetMusic','AutosaveMusic','AlphaSettings','AlphaBossSafety','AlphaReleaseScope'),
 @('BossDoppelgangerGenerationSmoke','SpellShuffleGenerationSmoke','OpenWorldGenerationSmoke','OpenWorldStartingLocation','OpenWorldStartingLocationGenerationSmoke','OpenWorldStartingPrizes','FreeCannonTravel','CannonTravelRandomization','CannonTravelGenerationSmoke','Sandship','ChristmasFlammieLogic','ChristmasFlammieGenerationSmoke','KakkaraChaosReachability','KakkaraProgression','AlphaProductionGeneration')
)
$results=@(); $run=[Guid]::NewGuid().ToString('N')
foreach($name in $sets[$Group]) {
 $test=Join-Path $repo ('tests\'+$name+'.Tests.ps1')
 $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$test)
 $text=Get-Content -LiteralPath $test -Raw
 if($text -match '\[string\]\$AssemblyPath') { $arguments+=@('-AssemblyPath',$assembly) }
 $caseOutput=Join-Path $output ($run+'\'+$name)
 if($text -match '\[string\]\$OutputRoot') { $arguments+=@('-OutputRoot',$caseOutput) }
 if($SourceRom -and $text -match '\[string\]\$SourceRom') { $arguments+=@('-SourceRom',$SourceRom) }
 if($name -eq 'BossEncounterRegistry') { $arguments+=@('-BaselinePath',(Join-Path $repo 'tests\fixtures\BossEncounterRegistry.RC2.json')) }
 if($name -eq 'AlphaReleaseScope') { $arguments+=@('-SnapshotRoot',[IO.Path]::GetFullPath($SnapshotRoot)) }
 $watch=[Diagnostics.Stopwatch]::StartNew()
 $previousPolicy=$ErrorActionPreference; $ErrorActionPreference='Continue'
 & powershell @arguments *> (Join-Path $output ($name+'.log'))
 $code=$LASTEXITCODE; $ErrorActionPreference=$previousPolicy; $watch.Stop()
 if($code -eq 0 -and $name -eq 'AlphaProductionGeneration') {
  $baseline=Import-Csv (Join-Path $repo 'tests\fixtures\AlphaProduction.RC3.csv')
  $generated=Get-Content (Join-Path $caseOutput 'results.json') -Raw | ConvertFrom-Json
  foreach($case in $generated) {
   $expected=@($baseline | Where-Object Name -eq $case.Name)
   if($expected.Count -ne 1 -or $case.Sha256 -notmatch '^[A-F0-9]{64}$' -or $case.Sha256 -cne $expected[0].Sha256) { throw ('Source changed RC3 ROM: '+$case.Name) }
  }
 }
 $results += [pscustomobject]@{Test=$name;ExitCode=$code;Seconds=[math]::Round($watch.Elapsed.TotalSeconds,2)}
 $results | Export-Csv -NoTypeInformation -LiteralPath (Join-Path $output ('results-'+$Group+'.csv'))
 Write-Output ($name+': '+$code)
}
if(@($results|Where-Object ExitCode -ne 0).Count) { exit 1 }
