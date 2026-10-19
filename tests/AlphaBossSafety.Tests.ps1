param(
 [string]$AssemblyPath=(Join-Path $PSScriptRoot '..\.codex-build\alpha-audit\out\SoMRandomizer.exe'),
 [string]$SourceRom=''
)
. (Join-Path $PSScriptRoot 'support\BossArenaStage1.ps1')
foreach($mode in @('vanilla','random','swap')) {
 $case=New-Case $mode (Native-Pins)
 Apply 'processing.common.BossSwaps' $case
 $before=Read-Map $case.Rom 'getObjects' 72
 $expected=@($before|ForEach-Object { '{0}:{1}:{2}' -f $_.getSpecies(),$_.getEventVisMinimum(),$_.getEventVisMaximum() })
 Apply 'processing.hacks.openworld.NoEnemies' $case
 $after=Read-Map $case.Rom 'getObjects' 72
 $actual=@($after|ForEach-Object { '{0}:{1}:{2}' -f $_.getSpecies(),$_.getEventVisMinimum(),$_.getEventVisMaximum() })
 Assert-True (($actual -join '|') -eq ($expected -join '|')) ("NoEnemies hid native Jehk bosses in $mode mode.")
 $type=T 'processing.common.DoppelgangerBossArenaRedirect'
 $preserve=$type.GetMethod('preserveNativeShadow')
 foreach($species in @(0x2E,0x3F,0x20)) {
  Assert-True (-not $preserve.Invoke($null,@($case.Context,73,[byte]$species))) 'Unrelated ordinary enemy protected.'
 }
 Assert-True (-not $preserve.Invoke($null,@($case.Context,72,[byte]0x01))) 'Unrelated species protected.'
}
$reverse=New-Case 'random' @{mantisAnt='Doppelgangers';doppelgangers='Mantis-Ant'}
Apply 'processing.common.BossSwaps' $reverse
Apply 'processing.hacks.openworld.NoEnemies' $reverse
foreach($obj in (Read-Map $reverse.Rom 'getObjects' 72)) { Assert-True ($obj.getEventVisMinimum() -eq 15) 'Replaced native trial was resurrected.' }
'PASS: Vanilla/Random/Swap + NoEnemies preserve native Jehk shadows; reverse placement and unrelated ordinary enemies unchanged.'
