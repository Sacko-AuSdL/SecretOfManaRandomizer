param([string]$AssemblyPath=(Join-Path $PSScriptRoot '../SoMRandomizer/bin/Debug/net462/SoMRandomizer.exe'),[string]$SourceRom='D:/views/tools/bots/Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc')
. (Join-Path $PSScriptRoot 'support/BossArenaStage1.ps1')
$registry=T 'processing.common.BossEncounterRegistry';$x=T 'processing.common.DoppelgangerEncounterExpansion'
$native=New-Case 'random' (Native-Pins);Apply 'processing.common.BossSwaps' $native;Events $native
$cp=[CodeDom.Compiler.CompilerParameters]::new();$cp.GenerateInMemory=$true
foreach($r in @($assembly.Location,'System.dll','System.Core.dll')){[void]$cp.ReferencedAssemblies.Add($r)}
$compiled=([Microsoft.CSharp.CSharpCodeProvider]::new()).CompileAssemblyFromFile($cp,[string[]]@((Join-Path $PSScriptRoot 'support/SpellShuffleMachine.cs'),(Join-Path $PSScriptRoot 'support/DoppelgangerAutosaveChecks.cs')))
Assert-True (-not $compiled.Errors.HasErrors) ($compiled.Errors|Out-String);$machine=$compiled.CompiledAssembly.GetType('DoppelgangerAutosaveChecks')
$count=0
foreach($d in $x.GetField('ShadowDestinations').GetValue($null)) {
 $slot=@($registry.GetMethod('Destinations').Invoke($null,@())|Where-Object originalMapNum -eq $d.Map)[0]
 $key=($native.Context.bossEncounters.Bindings|Where-Object DestinationMap -eq $d.Map).Destination
 $pins=Native-Pins
 # Plando names are serialized by native encounter ID; the registry's map is authoritative.
 $nativeId=$slot.getOriginalBossId($original)
 $prop=T 'processing.openworld.PlandoProperties'
 $name=($prop.GetField('BOSS_IDS_BY_PLANDO_VALUE').GetValue($null).GetEnumerator()|Where-Object Value -eq $nativeId|Select-Object -First 1).Key
 $pinKey=($pins.Keys|Where-Object {$pins[$_] -eq $name}|Select-Object -First 1)
 Assert-True ($pinKey -ne $null) ('No Plando key for '+$key)
 $pins[$pinKey]='Doppelgangers';$pins.doppelgangers='Minotaur'
 $c=New-Case 'random' $pins;Apply 'processing.common.BossSwaps' $c;Events $c
 $plan=$c.Context.doppelgangerExpansion
 if($plan.UsesDonor -and $d.EntryEvent -ge 0){
  Assert-True (Same $c.Context.replacementEvents[$d.EntryEvent][0..4] @(0x42,$d.Flag,($d.Completed*16+15),0x16,0xB9)) 'Completed re-entry repeats pre-door flags.'
 }
 $objs=Read-Map $c.Rom 'getObjects' 498
 Assert-True ($objs.Count -eq $(if($slot.name -eq 'Tropicallo'){5}else{3})) 'Shadow count/NPC preservation failed.'
 foreach($door in $d.Doors){Assert-True ($c.Context.replacementDoors[$door].getTargetMap() -eq 498) 'An entry side still enters native boss.'}
 Assert-True ($plan.Completion -eq $d.Death -and $plan.Flag -eq $d.Flag -and $plan.Completed -eq $d.Completed) 'Wrong destination-owned contract.'
 if($slot -ne $maps.GetField('MANTISANT').GetValue($null)) {
  $before=$native.Context.replacementEvents[$d.Death];if(-not $before){$before=(T 'processing.common.VanillaEventUtil').GetMethod('getVanillaEvent').Invoke($null,@($original,$d.Death))}
  $after=$c.Context.replacementEvents[$d.Death];if(-not $after){$after=(T 'processing.common.VanillaEventUtil').GetMethod('getVanillaEvent').Invoke($null,@($original,$d.Death))}
  if($d.Return -eq 0xCB){
   $without=[Collections.Generic.List[byte]]::new([byte[]]$after);$without.RemoveRange($without.Count-5,2)
   Assert-True (Same $before $without) 'Pure Lands reward changed beyond its required return.'
   Assert-True ($c.Context.replacementDoors[0xCB].getTargetMap() -eq $d.Map) 'Pure Lands return enters a donor story map.'
   Assert-True ((Read-Map $original 'getObjects' $d.Map)[0].getEventVisMaximum() -lt $d.Completed) 'Original boss remains visible after return.'
  }else{Assert-True (Same $before $after) ('Reward/flags/return altered for '+$key)}
 }
 if($plan.UsesDonor){
  $refs=Read-Map $c.Rom 'getMapPieceReference' 498
  Assert-True ($refs.bgPieces[0].pieceIndex -eq 0x2C8 -and $refs.fgPieces[0].pieceIndex -eq 0x2C9) 'Wrong native-shadow donor geometry.'
 }
 # Serialize doors as RomGenerator does before executing emitted Autosave code.
 foreach($pair in $c.Context.replacementDoors.GetEnumerator()){$pair.Value.put($c.Rom,0x83000+4*$pair.Key)}
 Apply 'processing.hacks.common.qol.Autosave' $c
 Assert-True ($machine.GetMethod('LoadDoor').Invoke($null,@($c.Rom,0x2D0,[int]$d.Doors[0])) -eq 0x2D0) 'Load incorrectly restores the current private-entry door.'
 foreach($door in $d.Doors){
  foreach($hp in @(100,0)){
   $result=$machine.GetMethod('Probe').Invoke($null,@($c.Rom,[int]$door,$hp))
   Assert-True ($result[0] -eq 0 -and $result[1] -eq 0x2D0 -and $result[2] -eq $door) 'Private arena saved as continue location, or native current-door state broken.'
  }
 }
 $count++
}
Assert-True (($machine.GetMethod('Probe').Invoke($null,@($c.Rom,0x8E,100)))[0] -eq 1) 'Safe world return no longer autosaves.'
Assert-True (($machine.GetMethod('Probe').Invoke($null,@($c.Rom,0x8E,0)))[0] -eq 0) 'Party wipe overwrites a valid save.'
Assert-True ($count -eq 17) 'Destination coverage changed.'
$pins=Native-Pins;$pins.dreadSlime='Doppelgangers';$pins.doppelgangers='Minotaur';$pins.jabberwocky='Dread-Slime';$pins.tropicallo='Lime-Slime';$pins.limeSlime='Mantis-Ant';$pins.mantisAnt='Triple-Tonpole';$pins.tripleTonpole='Mantis-Ant';$pins.doomsWall='Mantis-Ant'
$coexist=New-Case 'random' $pins;Apply 'processing.common.BossSwaps' $coexist;Events $coexist
Assert-True ($coexist.Context.doppelgangerExpansion.ForeignSlot.originalMapNum -eq 488) 'Dread logical slot lost its shadows.'
Assert-True ($coexist.Context.replacementDoors[0x152].getTargetMap() -eq 498 -and $coexist.Context.replacementDoors[0xA0].getTargetMap() -eq 502) 'Shadow/Dread entry allocation collision.'
Assert-True (Same $coexist.Rom[0x8E345..0x8E355] $original[0x8E345..0x8E355]) 'Special coexistence corrupts native combat.'
'PASS: all 17 foreign destinations construct through production Plando; every entry side redirected, destination reward/flag tails unchanged; actual emitted autosave machine preserves safe saved door on entry and party wipe.'
