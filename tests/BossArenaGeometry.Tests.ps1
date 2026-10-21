param([string]$AssemblyPath=(Join-Path $PSScriptRoot '../SoMRandomizer/bin/Release/net462/SoMRandomizer.exe'),[string]$SourceRom='',[string]$ReportPath='')
. (Join-Path $PSScriptRoot 'support/BossArenaStage1.ps1')
$helper=T 'processing.common.BossArenaGeometry';$case=New-Case
$helper.GetMethod('RequireUnusedEvents').Invoke($null,@($original,$case.Context,[int[]]@(0x6D5,0x6D6)))
$case.Context.replacementEvents[0x6D5]=[Collections.Generic.List[byte]]::new([byte[]]@(0));$rejected=$false
try{$helper.GetMethod('RequireUnusedEvents').Invoke($null,@($original,$case.Context,[int[]]@(0x6D5)))}catch{$rejected=$true}
Assert-True $rejected 'Occupied event was accepted.'
$helper.GetMethod('RequireNativeBoundaries').Invoke($null,@($original,$case.Rom,496,499,$true))
$case.Rom[0x87000+2*498]=$case.Rom[0x87000+2*498]-bxor 1;$rejected=$false
try{$helper.GetMethod('RequireNativeBoundaries').Invoke($null,@($original,$case.Rom,496,499,$true))}catch{$rejected=$true}
Assert-True $rejected 'Changed native boundary was accepted.'
$floor=[Activator]::CreateInstance((T 'processing.common.DirectBossFloor'),[object[]]@($original,204,$null,[byte]0x17))
Assert-True ($floor.Width -eq 34 -and $floor.Height -eq 40) 'Dragon Worm geometry changed.'
$floor.RequirePocket(14,17,1,0,255)
$rejected=$false;try{$floor.RequirePocket(0,0,1,0,255)}catch{$rejected=$true};Assert-True $rejected 'Invalid floor accepted.'
$trial=[Activator]::CreateInstance((T 'processing.common.DirectBossFloor'),[object[]]@($original,72));$trial.RequirePocket(14,16,1,0x4A,0)
$registry=T 'processing.common.BossEncounterRegistry';$destinations=$registry.GetMethod('Destinations').Invoke($null,@())
$counts=@();$random=0;$swap=0
foreach($d in $destinations){
 $pool=$registry.GetMethod('GetRandomPool').Invoke($null,@($d));$r=@($pool|Select-Object -Unique).Count
 Assert-True ($r -eq $pool.Count) ('Duplicate encounter candidate: '+$d.name)
 $s=0;foreach($other in $destinations){if($registry.GetMethod('CanSwap').Invoke($null,@($d,[byte]$other.getOriginalBossId($original)))){$s++}}
 $counts+=[pscustomobject]@{Destination=$d.name;Random=$r;Swap=$s};$random+=$r;$swap+=$s
}
$exp=T 'processing.common.DoppelgangerEncounterExpansion'
$result=[pscustomobject]@{Destinations=$destinations.Count;PossiblePairings=($destinations.Count*$destinations.Count);Random=$random;Swap=$swap;DoppelgangerLocations=($exp.GetField('ShadowDestinations').GetValue($null).Count+1);JehkChoices=$exp.GetField('JehkBosses').GetValue($null).Count;ByLocation=$counts}
if($ReportPath){$result|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $ReportPath}
Assert-True ($result.DoppelgangerLocations -eq 18 -and $result.JehkChoices -eq 17) 'Approved encounter scope changed.'
'PASS: shared production geometry/ownership checks; actual final build: Random='+$random+', Swap='+$swap+', 18 Doppelganger locations, 17 Jehk choices.'
