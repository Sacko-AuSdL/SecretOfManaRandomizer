param([ValidateRange(0,2)][int]$Group=0,[Parameter(Mandatory=$true)][string]$AssemblyPath,[string]$SnapshotRoot='',[Parameter(Mandatory=$true)][string]$OutputRoot,[Parameter(Mandatory=$true)][string]$SourceRom)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));if(-not $SnapshotRoot){$SnapshotRoot=$repo}
[void][IO.Directory]::CreateDirectory($OutputRoot)
$sets=@(
 @('BossEncounterRegistry','BossArenaGeometry','BossDoppelgangerCompatibility','BossDoppelgangerExpansion','BossDoppelgangerScaling','BossDoppelgangerPureLands','DoppelgangerDeathLink','DoppelgangerExpandedDestinations','BossLimeSlimeCompatibility','BossDreadSlimeCompatibility','BossWallCompatibility','BossTripleTonpoleCompatibility','EnemySwapsNativeMapBounds'),
 @('SpellShuffle','PartySpellShuffle','SpellShuffleAffinity','CrystalOrbDialog','CrystalOrbRequirements','CrystalOrbWeaponBreaking','CrystalOrbHints','PlayerMagicDamage','WeaponUpgradeCosts','ManaBeastAppearance','SaveMusicRestoration','SoftResetMusic','AutosaveMusic','AlphaSettings','AlphaBossSafety','AlphaReleaseScope'),
 @('BossDoppelgangerGenerationSmoke','BossDoppelgangerExpansionGeneration','SpellShuffleGenerationSmoke','OpenWorldGenerationSmoke','OpenWorldStartingLocation','OpenWorldStartingLocationGenerationSmoke','OpenWorldStartingPrizes','FreeCannonTravel','CannonTravelRandomization','CannonTravelGenerationSmoke','Sandship','ChristmasFlammieLogic','ChristmasFlammieGenerationSmoke','KakkaraChaosReachability','KakkaraProgression','AlphaProductionGeneration')
)
$results=@()
foreach($name in $sets[$Group]){
 $test=Join-Path $repo ('tests/'+$name+'.Tests.ps1');$text=Get-Content -LiteralPath $test -Raw
 $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$test)
 if($text -match '\[string\]\$AssemblyPath'){$args+=@('-AssemblyPath',[IO.Path]::GetFullPath($AssemblyPath))}
 if($text -match '\[string\]\$SourceRom'){$args+=@('-SourceRom',$SourceRom)}
 if($text -match '\[string\]\$OutputRoot'){$args+=@('-OutputRoot',(Join-Path $OutputRoot $name))}
 if($name -eq 'AlphaReleaseScope'){$args+=@('-SnapshotRoot',$SnapshotRoot)}
 if($name -eq 'BossDoppelgangerPureLands'){$args+='-GenerationSmoke'}
 if($name -eq 'BossArenaGeometry'){$args+=@('-ReportPath',(Join-Path $OutputRoot 'BossCompatibilityCounts.json'))}
 $watch=[Diagnostics.Stopwatch]::StartNew();$previous=$ErrorActionPreference;$ErrorActionPreference='Continue'
 & powershell @args *> (Join-Path $OutputRoot ($name+'.log'))
 $code=$LASTEXITCODE;$ErrorActionPreference=$previous;$watch.Stop()
 $results+=[pscustomobject]@{Test=$name;ExitCode=$code;Seconds=[math]::Round($watch.Elapsed.TotalSeconds,2)}
 $results|Export-Csv -NoTypeInformation -LiteralPath (Join-Path $OutputRoot ('results-'+$Group+'.csv'))
 Write-Output ($name+': '+$code)
}
if(@($results|Where-Object ExitCode -ne 0).Count){exit 1}
