param(
 [string]$AssemblyPath=(Join-Path $PSScriptRoot '../SoMRandomizer/bin/Debug/net462/SoMRandomizer.exe'),
 [string]$SourceRom='D:/views/tools/bots/Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc',
 [string]$ReportPath=''
)
. (Join-Path $PSScriptRoot 'support/BossArenaStage1.ps1')
$x=T 'processing.common.DoppelgangerEncounterExpansion'; $registry=T 'processing.common.BossEncounterRegistry'
$rows=Import-Csv (Join-Path $PSScriptRoot 'BossCompatibilityMatrix.csv')
$matrix=@(); $added=@(); $beforeRandom=0; $afterRandom=0; $beforeSwap=0; $afterSwap=0
foreach($row in $rows) {
 $slot=$maps.GetField($row.Arena).GetValue($null)
 $pool=$registry.GetMethod('GetRandomPool').Invoke($null,@($slot))
 # Exact Phase-1 admission: delegated Triple/Slime/Wall rules, Mantis-only
 # synthetic ID, and {native shadows,Mantis} at Jehk. No regenerated baseline.
 $old=(T 'processing.common.TripleTonpoleBossArenaRedirect').GetMethod('getOpenWorldRandomPool').Invoke($null,@($slot))
 if($row.Arena -eq 'DOPPELGANGERS') { $old=@(0x81,0x57) }
 elseif($row.Arena -eq 'MANTISANT') { $old=@($old)+@(0x81) }
 foreach($col in $rows) {
  $id=[byte][Convert]::ToInt32($col.NativeBoss,16)
  $br=$old -contains $id; $ar=$pool -contains $id
  $bs=if($row.Arena -eq 'DOPPELGANGERS') {$id -in @(0x81,0x57)} elseif($id -eq 0x81) {$row.Arena -eq 'MANTISANT'} else {(T 'processing.common.TripleTonpoleBossArenaRedirect').GetMethod('canSwapInOpenWorld').Invoke($null,@($slot,$id))}
  $as=$registry.GetMethod('CanSwap').Invoke($null,@($slot,$id))
  $beforeRandom += [int]$br; $afterRandom += [int]$ar; $beforeSwap += [int]$bs; $afterSwap += [int]$as
  Assert-True (-not $br -or $ar) 'Removed existing Random pairing.'
  Assert-True (-not $bs -or $as) 'Removed existing Swap pairing.'
  $record=[pscustomobject]@{Destination=$row.Arena;Encounter=$col.Arena;BeforeRandom=$br;AfterRandom=$ar;BeforeSwap=$bs;AfterSwap=$as}
  $matrix+=$record
  if(($ar -and -not $br) -or ($as -and -not $bs)) {
   Assert-True ($row.Arena -eq 'DOPPELGANGERS' -or ($id -eq 0x81 -and $x.GetMethod('SupportsShadows').Invoke($null,@($slot)))) 'Unrelated admission changed.'
   $added+=$record
  }
 }
}
Assert-True ($beforeRandom -eq 1046 -and $beforeSwap -eq 833 -and $afterRandom -eq 1077 -and $afterSwap -eq 864 -and $added.Count -eq 31) 'Unexpected full-matrix delta.'
if($ReportPath) { [pscustomobject]@{BeforeRandom=$beforeRandom;AfterRandom=$afterRandom;BeforeSwap=$beforeSwap;AfterSwap=$afterSwap;Added=$added;Matrix=$matrix}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ReportPath }

$cp=[CodeDom.Compiler.CompilerParameters]::new(); $cp.GenerateInMemory=$true
foreach($ref in @((Resolve-Path $AssemblyPath).Path,'System.dll','System.Core.dll')) { [void]$cp.ReferencedAssemblies.Add($ref) }
$compiled=([Microsoft.CSharp.CSharpCodeProvider]::new()).CompileAssemblyFromFile($cp,[string[]]@((Join-Path $PSScriptRoot 'support/DoppelgangerEventMachine.cs'),(Join-Path $PSScriptRoot 'support/TropicalloDirectMachines.cs')))
Assert-True (-not $compiled.Errors.HasErrors) ($compiled.Errors|Out-String)
$cpu=$compiled.CompiledAssembly.GetType('TropicalloDispatchMachine')
$events=$compiled.CompiledAssembly.GetType('DoppelgangerEventMachine')
function Dispatch($Case,[int]$Mask=7,[int]$Players=3,[bool]$Wipe=$false) {
 $m=[Activator]::CreateInstance($cpu,[object[]]@(,$Case.Rom)); $m.Put(0xDC,498)
 for($i=0;$i -lt 3;$i++) {
  $at=0x600+0x200*$i; $dead=($Mask-band (1-shl $i))-ne 0
  $m.Put(0xE1E7+$at,@(0x2E,0x3F,0x20)[$i]); $m.Put(0xE191+$at,$(if($dead){128}else{0})); $m.Put(0xE182+$at,$(if($dead){0}else{25}))
  $m.Put(0xE03E+$at,0xFFF) # leftover visual must NOT prevent completion
  $m.Put(0xE000+0x200*$i,$(if($i -lt $Players){2}else{0}))
  if($i -ge $Players){$m.Put(0xE060+0x200*$i,255);$m.Put(0xE01C+0x200*$i,255)}
  $m.Put(0xE182+0x200*$i,$(if($Wipe){0}else{100})); $m.Put(0xE191+0x200*$i,$(if($Wipe){128}else{0}))
 }
 $m.Run($Case.Context.workingData.getInt('DoppelgangerDispatcher')); return $m
}

foreach($destination in @('tropicallo','frostGigas')) {
 $pins=Native-Pins; $pins[$destination]='Doppelgangers'; $pins.doppelgangers='Frost-Gigas'
 $case=New-Case 'random' $pins; Apply 'processing.common.BossSwaps' $case
 $c=$case.Context; $r=$case.Rom; $plan=$c.doppelgangerExpansion
 Assert-True ($plan -ne $null -and $plan.DirectJehk) 'Normal production selection did not bind both directions.'
 $private=Read-Map $r 'getObjects' 498
 Assert-True ($private.Count -eq $(if($destination -eq 'tropicallo'){5}else{3})) 'Wrong private object span.'
 for($i=0;$i -lt 3;$i++) {
  Assert-True ($private[$i].getSpecies() -eq @(0x2E,0x3F,0x20)[$i] -and $private[$i].getEvent() -eq 0 -and $private[$i].getSpawnPriority()) 'Shadow identities/callback/priority changed.'
  Assert-True ($private[$i].getXpos() -eq $plan.Spawns[$i].X -and $private[$i].getYpos() -eq $plan.Spawns[$i].Y) 'Wrong bound spawn.'
 }
 Assert-True ($c.replacementDoors[$plan.EntryDoor].getTargetMap() -eq 498 -and $c.replacementDoors[0x304].getTargetMap() -eq 72) 'Wrong independent entry destinations.'
 $jehk=Read-Map $r 'getObjects' 72
 Assert-True ($jehk[0].getSpecies() -eq 0x5E -and $jehk[0].getXpos() -eq 14 -and $jehk[0].getYpos() -eq 16 -and $jehk[0].getEvent() -eq 0x6BB) 'Jehk direct Frost actor wrong.'
 Events $case
 $control=New-Case 'random' (Native-Pins); Apply 'processing.common.BossSwaps' $control; Events $control
 Assert-True (Same $c.replacementEvents[$plan.Completion] $control.Context.replacementEvents[$plan.Completion]) 'Destination prize/progression was rewritten.'
 Assert-True (Same $r[0x8E0B5..0x8FED5] $original[0x8E0B5..0x8FED5]) 'Native C8 code changed.'
 foreach($table in @(0x84000,0x85000,0x87000)) { Assert-True (Same $r[($table+990)..($table+993)] $original[($table+990)..($table+993)]) 'Map495 boundary changed.' }
 foreach($mask in 0..7) {
  foreach($players in 1..3) {
   $m=Dispatch $case $mask $players
   Assert-True ($m.Calls -eq [int]($mask -eq 7)) 'Completion differs by party count or fires prematurely.'
   Assert-True ($m.X -eq 0x56 -and $m.Y -eq 0x78 -and $m.DB -eq 0x7E -and $m.DP -eq 0 -and $m.S -eq 0x1F0 -and $m.A -eq 0xAB00 -and $m.P -eq 0x37) 'Dispatcher register/status/stack mismatch.'
  }
 }
 Assert-True ((Dispatch $case 7 3 $true).Calls -eq 0) 'Completion steals normal Game Over.'
 $nativeDefeat=Dispatch $case; $nativeDefeat.Calls=0
 foreach($actor in @(0x600,0x800,0xA00)){$nativeDefeat.Put(0xE182+$actor,800)}
 $nativeDefeat.Run($c.workingData.getInt('DoppelgangerDispatcher'))
 Assert-True ($nativeDefeat.Calls -eq 1) 'Extra HP prerequisite blocks a native status-only shadow defeat.'
 $m=Dispatch $case; $m.Calls=0; $m.Put(0xDC,72); $m.Run($c.workingData.getInt('DoppelgangerDispatcher')); Assert-True ($m.Calls -eq 0) 'Wrong-map dispatch.'
 $m=Dispatch $case; $m.Calls=0; $m.Put(0xE7E7,0x57); $m.Run($c.workingData.getInt('DoppelgangerDispatcher')); Assert-True ($m.Calls -eq 0) 'Wrong actor dispatch.'
 $m=Dispatch $case; $m.Calls=0; $m.Put(0xCF00+$plan.Flag,$plan.Completed); $m.Run($c.workingData.getInt('DoppelgangerDispatcher')); Assert-True ($m.Calls -eq 0) 'Completed state dispatch.'
 $m=Dispatch $case; $m.Calls=0; $m.Put(0xD0,1); $m.Run($c.workingData.getInt('DoppelgangerDispatcher')); Assert-True ($m.Calls -eq 0) 'Busy interpreter dispatch.'
 $ev=[Activator]::CreateInstance($events,[object[]]@($r,$c.replacementEvents))
 $ev.Flags[0x3F]=4; $ev.Run(0x4E5); Assert-True ($ev.Prizes -eq 0) 'Touching exit grants Jehk prize.'
 $ev.Run(0x6BB); $ev.Run(0x6BB); $ev.Run(0x3DB)
 Assert-True ($ev.Prizes -eq 1 -and $ev.Flags[0x3F] -eq 6 -and $ev.JehkRestorations -eq 1 -and $ev.PartyMpRestorations -eq 1 -and $ev.LastDoor -eq 0x38) 'Jehk reward/healing/reentry not exact-once.'
 Assert-True ($ev.Sequence.Contains('call:626')) 'Jehk return music missing.'
 if($destination -eq 'tropicallo') {
  foreach($mask in 0..7) {
   $reward=[Activator]::CreateInstance($compiled.CompiledAssembly.GetType('TropicalloEventMachine'),[object[]]@($r,$c.replacementEvents))
   $reward.Flags[0x15]=7
   for($i=0;$i -lt 3;$i++){$reward.Status[$i]=$(if($mask-band (1-shl $i)){128}else{0})}
   $reward.Run(0x6D6)
   Assert-True ($reward.Prizes -eq $(if($mask -eq 7){2}else{0}) -and $reward.Orbs -eq [int]($mask -eq 7)) 'Tropicallo prize/orb awarded before all three native status checks pass.'
   if($mask -eq 7){
    Assert-True ($reward.Flags[0x15] -eq 8 -and $reward.LastDoor -eq 0x52 -and $reward.Trace.Contains('call:7CF') -and $reward.Heals -eq 0) 'Tropicallo completion lost destination state/music or inherited Jehk healing.'
    $reward.Run(0x6D6);$reward.Run(0x6D5)
    Assert-True ($reward.Prizes -eq 2 -and $reward.Orbs -eq 1) 'Completed re-entry repeats Tropicallo rewards.'
   }
  }
 }
 Apply 'processing.hacks.openworld.NoEnemies' $case
 Assert-True ((Read-Map $r 'getObjects' 498)[0].getEventVisMaximum() -eq $plan.Completed-1) 'NoEnemies removed private shadows.'
 $case.Settings.set('opMinLevel','yes'); $case.Settings.set('opMaxLevel','yes'); Apply 'processing.hacks.openworld.MinMaxLevel' $case
 foreach($field in @('MINMAXLEVEL_MIN_OFFSET_HIROM','MINMAXLEVEL_MAX_OFFSET_HIROM')) {
  $at=$c.workingData.getInt((T 'processing.hacks.openworld.MinMaxLevel').GetField($field).GetValue($null))-0xC00000
  Assert-True ($r[$at+498] -eq $r[$at+$plan.ForeignSlot.originalMapNum]) 'Shadow level follows Mantis instead of destination.'
 }
}

# Every declared Jehk replacement constructs without relying on manual gates.
foreach($boss in $x.GetField('JehkBosses').GetValue($null)|Where-Object {$_ -notin @(0x81,0x57)}) {
 $nativeMap=(T 'processing.common.VanillaBossMaps').GetField('BY_VANILLA_BOSS_ID').GetValue($null)[$boss]
 $plandoName=(T 'processing.openworld.PlandoProperties').GetField('BOSS_IDS_BY_PLANDO_VALUE').GetValue($null).GetEnumerator()|Where-Object Value -eq $boss|Select-Object -First 1 -ExpandProperty Key
 $pins=Native-Pins; $pins.doppelgangers=$plandoName
 $case=New-Case 'random' $pins; Apply 'processing.common.BossSwaps' $case; Events $case
 $map=if($case.Context.doppelgangerExpansion.DirectJehk){72}else{497}
 $actors=Read-Map $case.Rom 'getObjects' $map
 Assert-True ($actors[0].getSpecies() -eq $boss -and $actors[0].getEvent() -eq 0x6BB) ('Jehk replacement failed native actor binding: '+$boss+' '+$plandoName+' map '+$map+' species '+$actors[0].getSpecies()+' event '+$actors[0].getEvent())
 if($map -eq 497) {
  Assert-True ($actors.Count -eq 1 -and $case.Context.replacementMapPieces.Count -eq 2) 'Donor has extra actors/piece collision.'
  Assert-True ((Read-Map $case.Rom 'getTriggers' 497)[0] -eq 0x3DB) 'Donor progression trigger leaked.'
 }
}
# A real existing Orb-hook call is retained as the tail of the new hook, with
# its advertised address validated before replacing it. Unknown owners reject.
$pins=Native-Pins; $pins.tropicallo='Doppelgangers'; $pins.doppelgangers='Frost-Gigas'
$chained=New-Case 'random' $pins
$chained.Rom[0xB6A4]=0x22; $chained.Rom[0xB6A5]=0x45; $chained.Rom[0xB6A6]=0x23; $chained.Rom[0xB6A7]=0xE1
$chained.Context.workingData.setInt('crystalOrbWeaponBreakingDeferredRoutineOffsetHirom',0xE12345)
Apply 'processing.common.BossSwaps' $chained
$offset=$chained.Context.workingData.getInt('DoppelgangerDispatcher'); $len=$chained.Context.workingData.getInt('DoppelgangerDispatcherLength')
Assert-True (Same $chained.Rom[($offset+$len-5)..($offset+$len-1)] @(0x22,0x45,0x23,0xE1,0x6B)) 'Known Orb dispatcher not chained.'
$machine=[Activator]::CreateInstance($cpu,[object[]]@(,$chained.Rom)); $machine.ChainedAddress=0xE12345
$machine.Run($offset)
Assert-True ($machine.ChainedCalls -eq 1 -and $machine.Calls -eq 0 -and $machine.S -eq 0x1F0 -and $machine.A -eq 0xAB00) 'Wrong-map path loses/duplicates Orb dispatcher or corrupts state.'
$bad=New-Case 'random' $pins; $bad.Rom[0xB6A4]=0x22
$rejected=$false; try{Apply 'processing.common.BossSwaps' $bad}catch{$rejected=$_.Exception.ToString().Contains('declared Crystal Orb dispatcher')}
Assert-True $rejected 'Unrecognized hook owner overwritten.'

# Real coexistence: destination shadows + direct Jehk + Triple + both slime
# directions + Doom. Each private map/event block has independent ownership.
$pins=Native-Pins; $pins.tropicallo='Doppelgangers'; $pins.doppelgangers='Minotaur'
$pins.mantisAnt='Triple-Tonpole'; $pins.tripleTonpole='Mantis-Ant'
$pins.jabberwocky='Lime-Slime'; $pins.limeSlime='Minotaur'
$pins.frostGigas='Dread-Slime'; $pins.dreadSlime='Mantis-Ant'; $pins.doomsWall='Mantis-Ant'
$coexist=New-Case 'random' $pins; Apply 'processing.common.BossSwaps' $coexist; Events $coexist
foreach($pair in @(@(498,5),@(500,3),@(502,1),@(504,1),@(506,1),@(508,1),@(510,1))) {
 Assert-True ((Read-Map $coexist.Rom 'getObjects' $pair[0]).Count -eq $pair[1]) ('Map allocation collision at '+$pair[0])
}
Assert-True (Same $coexist.Rom[0x8E345..0x8E355] $original[0x8E345..0x8E355]) 'Coexistence damages C8 executable.'
# Singleton conflicts fail early; Vanilla is still untouched.
$pins=Native-Pins; $pins.tropicallo='Doppelgangers'
$rejected=$false; try { Apply 'processing.common.BossSwaps' (New-Case 'random' $pins) } catch {$rejected=$_.Exception.ToString().Contains('unique')}
Assert-True $rejected 'Duplicate native/foreign shadows accepted.'
# A planned Tropicallo trio with unplanned Jehk needs a three-way bridge:
# Tropicallo's globally positioned boss cannot be copied into Jehk directly.
# Conserve the original 38-encounter multiset rather than substituting Mantis.
$pins=Native-Pins; $pins.tropicallo='Doppelgangers'; $pins.Remove('doppelgangers'); $pins.Remove('minotaur')
$swap=New-Case 'swap' $pins; Apply 'processing.common.BossSwaps' $swap
$before=@($rows|ForEach-Object {[Convert]::ToInt32($_.NativeBoss,16)}|Sort-Object)
$after=@($swap.Context.bossEncounters.Bindings|ForEach-Object {[int]$_.SelectedEncounter}|Sort-Object)
Assert-True (($before -join ',') -eq ($after -join ',')) 'Planned Swap bridge loses/duplicates an encounter.'
$off=New-Case 'vanilla'; Apply 'processing.common.BossSwaps' $off
Assert-True (Same $off.Rom[0..($original.Length-1)] $original) 'Vanilla mode mutated ROM.'
'PASS: 1444-pair audit (Random 1046->1077; Swap 833->864), 31 intentional additions; production direct/private/donor construction, all-three emitted-machine dispatch, partial deaths/roles/wipe/busy/ghost guards, exact-once Jehk rewards/music/restoration and native-code ownership.'
