param(
 [string]$AssemblyPath=(Join-Path $PSScriptRoot '../SoMRandomizer/bin/Debug/net462/SoMRandomizer.exe'),
 [string]$SourceRom='D:/views/tools/bots/Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc',
 [switch]$GenerationSmoke
)
. (Join-Path $PSScriptRoot 'support/BossArenaStage1.ps1')
function Assert-NormalSword($Script){
 for($i=0;$i -lt $Script.Count;){
  $op=[int]$Script[$i];Assert-True ($op -lt 0x18 -or $op -gt 0x1D) 'Manual teleport leaked into normal Sword acquisition.'
  if($op -eq 0){Assert-True ($i -eq $Script.Count-1) 'Unexpected trailing startup commands.';return}
  if($op -ge 0x7F -or $op -in @(2,3,4,5,6,8,9,10,0x50,0x51,0x52,0x5D,0x5E,0x5F)){$i++}
  elseif(($op -ge 0x10 -and $op -le 0x2F) -or $op -in @(0x57,0x59,0x5A)){$i+=2}
  elseif($op -in @(0x30,0x31,0x32,0x34,0x36,0x37,0x42)){$i+=3}
  elseif($op -eq 0x39){Assert-True ($Script[$i+2] -eq 0x90) 'Manual actor supplies leaked into normal generation.';$i+=4}
  elseif($op -eq 0x40){$i+=5}else{throw ('Unexpected startup opcode '+$op)}
 }
 throw 'Normal Sword event has no END.'
}
$cp=[CodeDom.Compiler.CompilerParameters]::new();$cp.GenerateInMemory=$true
foreach($r in @($assembly.Location,'System.dll','System.Core.dll')){[void]$cp.ReferencedAssemblies.Add($r)}
$files=@('DoppelgangerEventMachine.cs','TropicalloDirectMachines.cs','DoppelgangerExpansionTestGenerator.cs','DoppelgangerManualProfile.cs','SpellShuffleMachine.cs','DoppelgangerAutosaveChecks.cs','DoppelgangerDeathLinkChecks.cs')|ForEach-Object {Join-Path $PSScriptRoot ('support/'+$_)}
$compiled=([Microsoft.CSharp.CSharpCodeProvider]::new()).CompileAssemblyFromFile($cp,[string[]]$files)
Assert-True (-not $compiled.Errors.HasErrors) ($compiled.Errors|Out-String)
$eventMachine=$compiled.CompiledAssembly.GetType('DoppelgangerEventMachine')
$dispatchMachine=$compiled.CompiledAssembly.GetType('TropicalloDispatchMachine')
$pins=Native-Pins;$pins.dragonWorm='Doppelgangers';$pins.doppelgangers='Frost-Gigas'
$case=New-Case 'random' $pins;Apply 'processing.common.BossSwaps' $case;Events $case
$c=$case.Context;$plan=$c.doppelgangerExpansion
Assert-True ($plan.ForeignSlot.originalMapNum -eq 204 -and $plan.Completion -eq 0x5ED -and $plan.Flag -eq 0x46 -and $plan.Completed -eq 1) 'Dragon Worm destination contract changed.'
Assert-True ($plan.PreservesDestinationTraversal -and -not $plan.UsesDonor -and $plan.ReturnDoor -eq -1 -and -not $c.replacementDoors.ContainsKey(0xCB)) 'Dragon Worm still depends on a donor/return bounce.'
foreach($door in @(0x375,0x378)){
 $d=$c.replacementDoors[$door];$native=(T 'processing.common.VanillaDoorUtil').GetMethod('getDoor').Invoke($null,@($original,$door))
 Assert-True ($d.getTargetMap() -eq 498 -and $d.getXpos() -eq $native.getXpos() -and $d.getYpos() -eq $native.getYpos() -and $d.getTransitionType() -eq $native.getTransitionType() -and $d.getLayer2Collision() -eq $native.getLayer2Collision()) 'Native lower/upper entry coordinates or facing changed.'
}
$control=New-Case 'random' (Native-Pins);Apply 'processing.common.BossSwaps' $control;Events $control
Assert-True (Same $c.replacementEvents[0x5ED] $control.Context.replacementEvents[0x5ED]) 'Dragon Worm reward/flags changed; no return-door insertion is needed.'
Assert-True (Same $c.replacementEvents[0x62A] $control.Context.replacementEvents[0x62A]) 'Pure Lands goal/music continuation changed.'
$worm=(Read-Map $case.Rom 'getObjects' 204)[0]
Assert-True ($worm.getEventVisFlag() -eq 0x46 -and $worm.getEventVisMaximum() -eq 0) 'Original Worm must disappear at completed progress1.'
foreach($table in @(0x84000,0x85000,0x87000)){
 Assert-True (Same $case.Rom[($table+408)..($table+411)] $original[($table+408)..($table+411)]) 'Native Dragon Worm map boundaries changed.'
}
$triggers=Read-Map $case.Rom 'getTriggers' 498
Assert-True (($triggers -join ',') -eq '1749,1503,1503,1502,1502') 'Copy must preserve both pairs of native exit tiles with only its walk-on adapted.'
Assert-True (Same (T 'processing.common.VanillaMapUtil').GetMethod('makeMapPieceReference').Invoke($null,@((Read-Map $case.Rom 'getMapPieceReference' 498))) (T 'processing.common.VanillaMapUtil').GetMethod('makeMapPieceReference').Invoke($null,@((Read-Map $original 'getMapPieceReference' 204)))) 'Not the original Dragon Worm geometry.'
$floor=[Activator]::CreateInstance((T 'processing.common.DirectBossFloor'),[object[]]@($original,204,$null,[byte]0x17))
foreach($spawn in $plan.Spawns){$floor.RequirePocket($spawn.X,$spawn.Y,1,0,255)}
foreach($door in @(0x375,0x378)){
 $d=$c.replacementDoors[$door];Assert-True ($floor.RequireConnected($d.getXpos(),$d.getYpos(),$plan.Spawns,0,255) -gt 100) 'Actors disconnected from a Pure Lands approach.'
}
$actors=Read-Map $case.Rom 'getObjects' 498
Assert-True ($actors.Count -eq 3) 'Three fixed actor slots required.'
foreach($i in 0..2){Assert-True ($actors[$i].getSpecies() -eq @(0x2E,0x3F,0x20)[$i] -and $actors[$i].getSpawnPriority() -and $actors[$i].getEvent() -eq 0 -and $actors[$i].getEventVisFlag() -eq 0x46 -and $actors[$i].getEventVisMaximum() -eq 0) 'Native shadow identity/priority/visibility/callback changed.'}
foreach($id in @(0x5DE,0x5DF)){
 $exit=(T 'processing.common.VanillaEventUtil').GetMethod('getVanillaEvent').Invoke($null,@($original,$id))
 Assert-True (-not $c.replacementEvents.ContainsKey($id) -and (Same $exit[0..4] @(0x42,0x46,0,0x10,0))) 'Native Pure Lands exit/progression guard changed.'
 $c.replacementEvents[$id]=$exit # execute unchanged native guards below
}
foreach($mask in 0..7){
 # Execute the actual emitted deferred dispatcher, including register/stack
 # restoration, then the real native actor-test opcode for each shadow.
 $m=[Activator]::CreateInstance($dispatchMachine,[object[]]@(,$case.Rom));$m.Put(0xDC,498)
 for($i=0;$i -lt 3;$i++){
  $actor=0x600+0x200*$i;$dead=($mask-band (1-shl $i))-ne 0
  $m.Put(0xE1E7+$actor,@(0x2E,0x3F,0x20)[$i]);$m.Put(0xE191+$actor,$(if($dead){128}else{0}))
  $m.Put(0xE000+0x200*$i,2);$m.Put(0xE182+0x200*$i,100)
 }
 $m.Run($c.workingData.getInt('DoppelgangerDispatcher'))
 Assert-True ($m.Calls -eq [int]($mask -eq 7) -and $m.S -eq 0x1F0) 'Dispatcher fires before all three defeats or damages stack.'
 $ev=[Activator]::CreateInstance($eventMachine,[object[]]@($case.Rom,$c.replacementEvents))
 for($i=0;$i -lt 3;$i++){$ev.ActorStatus[$i]=$(if($mask-band (1-shl $i)){128}else{0})}
 $ev.Run(0x6D6)
 if($mask -ne 7){
  Assert-True ($ev.Prizes -eq 0 -and $ev.LastDoor -eq -1 -and $ev.Flags[0x46] -eq 0 -and $ev.Sequence.Count -eq 1) 'Partial defeat changes rewards/progression or returns early.'
 }else{
  Assert-True ($ev.Prizes -eq 1 -and $ev.Flags[0x46] -eq 1 -and $ev.LastDoor -eq -1) 'All-three completion must award once and remain on the clearing.'
  Assert-True (($ev.Sequence -join ',') -eq 'jump:5ED,call:41B,call:502,prize,jump:62A,jump:727') 'Destination-owned healing, Axe Orb, prize and Pure Lands music order changed.'
  foreach($flag in 0..255){if($flag -ne 0x46){Assert-True ($ev.Flags[$flag] -eq 0) 'Foreign story/progression flag was inherited.'}}
  $ev.Run(0x6D6)
  foreach($roundTrip in 1..5){foreach($exit in @(0x5DE,0x5DF)){
   $ev.Run($exit);Assert-True ($ev.LastDoor -eq $(if($exit -eq 0x5DE){0x376}else{0x377})) 'Native lower/upper exit selected the wrong destination.'
   $before=$ev.Sequence.Count;$ev.Run(0x6D5)
   Assert-True (($ev.Sequence.Count -eq $before+1) -and $ev.Sequence[$before] -eq 'jump:727') 'Completed approach bounces into an arena/return door.'
  }}
  Assert-True ($ev.Prizes -eq 1 -and $ev.Flags[0x46] -eq 1 -and (@($ev.Sequence|Where-Object {$_ -eq 'call:502'}).Count -eq 1)) 'Completed re-entry repeats orb/prize/progression.'
 }
}
# Both exits remain blocked before victory, exactly as in the native clearing.
foreach($exit in @(0x5DE,0x5DF)){
 $ev=[Activator]::CreateInstance($eventMachine,[object[]]@($case.Rom,$c.replacementEvents));$ev.Run($exit)
 Assert-True ($ev.LastDoor -eq -1 -and $ev.Prizes -eq 0) 'Native unfinished-boss exit guard bypassed.'
}
# Register a real party wipe: completion must defer to native Game Over.
$m=[Activator]::CreateInstance($dispatchMachine,[object[]]@(,$case.Rom));$m.Put(0xDC,498)
foreach($i in 0..2){$m.Put(0xE1E7+0x600+512*$i,@(0x2E,0x3F,0x20)[$i]);$m.Put(0xE191+0x600+512*$i,128);$m.Put(0xE000+512*$i,2);$m.Put(0xE191+512*$i,128)}
$m.Run($c.workingData.getInt('DoppelgangerDispatcher'));Assert-True ($m.Calls -eq 0) 'Victory steals Game Over from a defeated party.'
foreach($door in $c.replacementDoors.GetEnumerator()){$door.Value.put($case.Rom,0x83000+4*$door.Key)}
Apply 'processing.hacks.common.qol.Autosave' $case
$save=$compiled.CompiledAssembly.GetType('DoppelgangerAutosaveChecks')
foreach($door in @(0x375,0x378)){
 foreach($hp in @(100,0)){$p=$save.GetMethod('Probe').Invoke($null,@($case.Rom,$door,$hp));Assert-True ($p[0] -eq 0 -and $p[1] -eq 0x2D0) 'Continue save overwritten by arena entry or party wipe.'}
 Assert-True ($save.GetMethod('LoadDoor').Invoke($null,@($case.Rom,0x2D0,$door)) -eq 0x2D0) 'Continue uses current arena door instead of saved safe door.'
}
foreach($door in @(0x376,0x377)){Assert-True (($save.GetMethod('Probe').Invoke($null,@($case.Rom,$door,100)))[0] -eq 1) 'Ordinary Pure Lands exit no longer autosaves.'}
foreach($mode in @('random','swap')){
 $selection=New-Case $mode $pins;Apply 'processing.common.BossSwaps' $selection
 Assert-True (($selection.Context.bossEncounters.Bindings|Where-Object DestinationMap -eq 204).Execution.ToString() -eq 'DestinationCopy') 'Random/Swap/Plando did not select destination geometry.'
}
$together=Native-Pins;$together.dragonWorm='Doppelgangers';$together.doppelgangers='Frost-Gigas'
$together.mantisAnt='Triple-Tonpole';$together.tripleTonpole='Mantis-Ant';$together.jabberwocky='Lime-Slime';$together.limeSlime='Minotaur'
$together.frostGigas='Dread-Slime';$together.dreadSlime='Mantis-Ant';$together.doomsWall='Mantis-Ant'
$coexist=New-Case 'random' $together;Apply 'processing.common.BossSwaps' $coexist;Events $coexist
Assert-True ((Read-Map $coexist.Rom 'getObjects' 498).Count -eq 3 -and ((Read-Map $coexist.Rom 'getTriggers' 498) -join ',') -eq '1749,1503,1503,1502,1502') 'Other special encounters overwrite Dragon Worm actors/exits.'
Assert-True (Same $coexist.Rom[0x8E0B5..0x8FED5] $original[0x8E0B5..0x8FED5]) 'Slime/Triple/Wall coexistence overwrites native C8 combat code.'
Assert-True (Same $coexist.Context.replacementEvents[0x5ED] $control.Context.replacementEvents[0x5ED]) 'Other special encounters replace Dragon Worm rewards.'
Assert-True (Same $case.Rom[0x1939C..0x19462] $original[0x1939C..0x19462]) 'Native status/Game Over handler changed.'
Assert-True (Same $case.Rom[0x8E345..0x8E355] $original[0x8E345..0x8E355]) 'Native combat code allocation collision.'
# Test-only shortcut is opt-in and absent from a newly created normal generator.
$g=[Activator]::CreateInstance($compiled.CompiledAssembly.GetType('DoppelgangerExpansionTestGenerator'))
Assert-True (-not $g.PureLandsShortcut -and -not $g.ManualSupplies) 'Manual shortcut became a default.'
# A completed location skips even an explicit repeat call of the manual tail.
$manualEvents=[Collections.Generic.Dictionary[int,Collections.Generic.List[byte]]]::new()
$manualEvents.Add(0x103,[Collections.Generic.List[byte]]::new([byte[]]@(0x42,0x46,0x1F,0x10,0,0x1B,0x75,0x16,0xD5,0)))
$ev=[Activator]::CreateInstance($eventMachine,[object[]]@($case.Rom,$manualEvents));$ev.Flags[0x46]=1;$ev.Run(0x103)
Assert-True ($ev.LastDoor -eq -1) 'Manual shortcut can reactivate a completed encounter.'
if($GenerationSmoke){
 # Four targeted normal worlds, in memory only: no supplies/shortcut/ROM files.
 foreach($mode in @('random','swap')){foreach($link in @('on','off')){
  $common=[Activator]::CreateInstance((T 'config.settings.CommonSettings'))
  $settings=[Activator]::CreateInstance((T 'config.settings.OpenWorldSettings'),[object[]]@($common))
  $common.set('mode','open');$common.set('version','1.49');$common.set('testOnly','yes')
  foreach($entry in @{opBosses=$mode;opCharacters='startboth';opLogic='restrictive';opFlammieDrumInLogic='yes';opGoal='vlong';opEnemies='swap';crystalOrbWeaponBreaking='on';spellShuffle='party';cannonTravelRandomization='shuffle';doppelgangerDeathLink=$link}.GetEnumerator()){$settings.set($entry.Key,$entry.Value)}
  $settings.set('plandoSettings',(($pins.GetEnumerator()|Sort-Object Key|ForEach-Object {'P_'+$_.Key+':'+$_.Value+';'}) -join ''))
  $generator=[Activator]::CreateInstance($compiled.CompiledAssembly.GetType('DoppelgangerExpansionTestGenerator'))
  [byte[]]$out=[byte[]]::new(0x400000);[Array]::Copy($original,$out,$original.Length)
  Assert-True ($generator.generate($original,$out,('PureLands-ArenaRegression-'+$mode),$settings)) ('Normal generation/simulation failed: '+$mode+'/'+$link)
  $context=$generator.LastContext
  Assert-True (($context.bossEncounters.Bindings|Where-Object DestinationMap -eq 204).TemplateMap -eq 204) 'Final generated world uses donor geometry.'
  Assert-NormalSword $context.replacementEvents[0x103]
  Assert-True (Same $out[0x1939C..0x19462] $original[0x1939C..0x19462]) 'Normal generated world changed Game Over.'
  foreach($at in @(0x10A70E,0x10A71C,0x10A72A,0x10A738,0x10A74D,0x10A762)){
   Assert-True ($out[$at] -eq $(if($link -eq 'off'){0}else{$original[$at]})) 'Final Death Link mode changed.'
  }
  $table=([int]$out[0x1E7A3]-bor ([int]$out[0x1E7A4]-shl 8)-bor ([int]$out[0x1E7A5]-shl 16))-0xC00000
  foreach($id in @(0x103,0x5ED,0x62A,0x6D5,0x6D6)){
   $ptr=$table+3*$id;$at=([int]$out[$ptr]-bor ([int]$out[$ptr+1]-shl 8)-bor ([int]$out[$ptr+2]-shl 16))-0xC00000
   Assert-True (Same $out[$at..($at+$context.replacementEvents[$id].Count-1)] $context.replacementEvents[$id]) 'Final serialized completion/startup differs from verified events.'
  }
  'PASS normal in-memory world: '+$mode+', Death Link '+$link
 }}
}
'PASS: recognizable Dragon Worm destination copy, 3x3 spawns/both entry paths, all-eight defeat masks, exact-once rewards/flags, ten upper/lower round trips without a teleport bounce, native exit guards, safe autosave/continue/wipe, Random/Swap/Plando, guarded manual shortcut.'
