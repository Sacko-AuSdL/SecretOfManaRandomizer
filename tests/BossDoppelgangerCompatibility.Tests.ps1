param(
    [string]$AssemblyPath=(Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe'),
    [string]$SourceRom='D:\views\tools\bots\Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc'
)
$ErrorActionPreference='Stop'
function Assert-True([bool]$Condition,[string]$Message) { if(-not $Condition) { throw $Message } }
function Equal-Bytes($A,$B) { return [Linq.Enumerable]::SequenceEqual([byte[]]$A,[byte[]]$B) }
$assembly=[Reflection.Assembly]::LoadFrom((Resolve-Path $AssemblyPath).Path)
function RepoType([string]$Name) { return $assembly.GetType('SoMRandomizer.'+$Name,$true) }
$settingsType=RepoType 'config.settings.OpenWorldSettings'; $commonType=RepoType 'config.settings.CommonSettings'
$contextType=RepoType 'processing.common.RandoContext'; $mapsType=RepoType 'processing.common.VanillaBossMaps'
$redirect=RepoType 'processing.common.DoppelgangerBossArenaRedirect'; $mapUtil=RepoType 'processing.common.VanillaMapUtil'
$eventUtil=RepoType 'processing.common.VanillaEventUtil'; $namesType=RepoType 'processing.hacks.common.util.NamesOfThings'
$binding=[Reflection.BindingFlags]'Instance,NonPublic'
[byte[]]$original=[IO.File]::ReadAllBytes((Resolve-Path $SourceRom).Path)
function MapValue([string]$Name) { return $mapsType.GetField($Name).GetValue($null) }
function Read-Map($Rom,[string]$Method,[int]$Id) { return ,($mapUtil.GetMethod($Method).Invoke($null,@($Rom,$Id))) }
function Apply([string]$Name,$Case) {
    $t=RepoType $Name
    [void]$t.GetMethod('process',$binding).Invoke([Activator]::CreateInstance($t),@($original,$Case[0],'doppel-test',$Case[2],$Case[1]))
}
function New-Case([string]$Mantis='Doppelgangers',[string]$Jehk='Mantis-Ant',[string]$Mode='random',[bool]$Coexist=$false) {
    $s=[Activator]::CreateInstance($settingsType,[object[]]@([Activator]::CreateInstance($commonType)))
    $s.set('opBosses',$Mode); $s.set('crystalOrbWeaponBreaking','off')
    $c=[Activator]::CreateInstance($contextType); $c.randomFunctional=[Random]::new(21377)
    $c.namesOfThings=[Activator]::CreateInstance($namesType,[object[]]@(,$original))
    $pins=@{
        mantisAnt=$Mantis;doppelgangers=$Jehk;wallFace='Wall-Face';tropicallo='Tropicallo';minotaur='Minotaur';
        spikeyTiger='Spikey-Tiger';jabberwocky='Jabberwocky';springBeak='Spring-Beak';frostGigas='Frost-Gigas';
        snapDragon='Snap-Dragon';mechRider1='Mech-Rider-1';doomsWall="Doom's-Wall";vampire='Vampire';metalMantis='Metal-Mantis';
        mechRider2='Mech-Rider-2';kilroy='Kilroy';gorgonBull='Gorgon-Bull';borealFace='Boreal-Face';
        greatViper='Great-Viper';limeSlime='Lime-Slime';blueSpike='Blue-Spike';hydra='Hydra';
        watermelon='Watermelon';hexas='Hexas';kettleKin='Kettle-Kin';tonpole='Tonpole';
        mechRider3='Mech-Rider-3';snowDragon='Snow-Dragon';fireGigas='Fire-Gigas';redDragon='Red-Dragon';
        axeBeak='Axe-Beak';blueDragon='Blue-Dragon';buffy='Buffy';darkLich='Dark-Lich';
        dragonWorm='Dragon-Worm';dreadSlime='Dread-Slime';thunderGigas='Thunder-Gigas';tripleTonpole='Triple-Tonpole'
    }
    foreach($key in $pins.Keys) { $c.plandoSettings['P_'+$key]=[Collections.Generic.List[string]]::new([string[]]@($pins[$key])) }
    if($Coexist) {
        $c.plandoSettings['P_tropicallo']=[Collections.Generic.List[string]]::new([string[]]@('Triple-Tonpole'))
        $c.plandoSettings['P_tripleTonpole']=[Collections.Generic.List[string]]::new([string[]]@('Mantis-Ant'))
        $c.plandoSettings['P_jabberwocky']=[Collections.Generic.List[string]]::new([string[]]@('Lime-Slime'))
        $c.plandoSettings['P_limeSlime']=[Collections.Generic.List[string]]::new([string[]]@('Minotaur'))
        $c.plandoSettings['P_frostGigas']=[Collections.Generic.List[string]]::new([string[]]@('Dread-Slime'))
        $c.plandoSettings['P_dreadSlime']=[Collections.Generic.List[string]]::new([string[]]@('Mantis-Ant'))
        $c.plandoSettings['P_doomsWall']=[Collections.Generic.List[string]]::new([string[]]@('Mantis-Ant'))
    }
    [byte[]]$r=[byte[]]::new(0x400000); [Array]::Copy($original,$r,$original.Length)
    $c.originalRom=$original; $c.outputRom=$r
    $case=@($r,$c,$s); Apply 'processing.common.BossSwaps' $case
    return ,$case
}
function Generate-Events($Case) {
    $c=$Case[1]
    $c.workingData.set('openWorldGoalShortName','manabeast'); $c.workingData.setBool('fastManaFort',$true)
    $c.workingData.setBool('anyMagicExists',$true); $c.workingData.setInt('manaSeedsRequired',8)
    $c.workingData.set('boyClass','OGboy'); $c.workingData.set('girlClass','OGgirl'); $c.workingData.set('spriteClass','OGsprite')
    $element=RepoType 'processing.ElementSwaps'; $c.workingData.setInt($element.GetField('ORBELEMENT_PREFIX').GetValue($null)+35,0x81)
    Apply 'processing.openworld.events.PrizeEvents' $Case
    Apply 'processing.openworld.events.OpenWorldSupportingEvents' $Case
}
$compiler=[Microsoft.CSharp.CSharpCodeProvider]::new()
$cp=[CodeDom.Compiler.CompilerParameters]::new(); $cp.GenerateInMemory=$true
$compiled=$compiler.CompileAssemblyFromFile($cp,(Join-Path $PSScriptRoot 'support\DoppelgangerEventMachine.cs'))
Assert-True (-not $compiled.Errors.HasErrors) ($compiled.Errors | Out-String)
$machineType=$compiled.CompiledAssembly.GetType('DoppelgangerEventMachine',$true)
function Machine($Case) { return [Activator]::CreateInstance($machineType,[object[]]@($Case[0],$Case[1].replacementEvents)) }

# Native allocation ownership. Door $CB remains untouched and unreferenced.
foreach($map in 496..499) {
    Assert-True ((Read-Map $original 'getObjects' $map).Count -eq 0) 'Candidate map has native objects.'
    Assert-True ((Read-Map $original 'getTriggers' $map).Count -eq 0) 'Candidate map has native triggers.'
    $pieces=Read-Map $original 'getMapPieceReference' $map
    Assert-True ($pieces.bgPieces.Count+$pieces.fgPieces.Count -eq 0) 'Candidate map has native geometry.'
}
for($d=0;$d -lt 0x400;$d++) {
    $at=0x83000+4*$d; $m=[int]$original[$at]+(([int]$original[$at+1]-band 1)-shl 8)
    Assert-True ($m -notin @(497,498,499)) 'Private arena has native door.'
    if($m -eq 496) { Assert-True ($d -eq 0xCB) 'Unexpected map-496 entrance.' }
}
for($event=0;$event -lt 0x7FF;$event++) {
    $bytes=$eventUtil.GetMethod('getVanillaEvent').Invoke($null,@($original,$event))
    for($i=0;$i -lt $bytes.Count-1;$i++) {
        Assert-True (-not ($bytes[$i] -eq 0x18 -and $bytes[$i+1] -eq 0xCB)) 'Native event can enter unused map 496.'
        foreach($private in @(0x6D5,0x6D6,0x6B9,0x6BA,0x6BB)) {
            Assert-True (-not ($bytes[$i] -in @((0x10+($private-shr 8)),(0x20+($private-shr 8))) -and $bytes[$i+1] -eq ($private-band 255))) 'Private event already called by native script.'
        }
    }
}
$privateEvents=@(0x6D5,0x6D6,0x6B9,0x6BA,0x6BB)
foreach($event in $privateEvents) { Assert-True (Equal-Bytes ($eventUtil.GetMethod('getVanillaEvent').Invoke($null,@($original,$event))) @(0)) 'Event allocation is not END-only.' }
for($map=0;$map -lt 511;$map++) {
    $triggers=Read-Map $original 'getTriggers' $map
    Assert-True (-not $triggers.Contains([uint16]0x8CB)) 'Native tile uses Door CB.'
    foreach($event in $privateEvents) {
        Assert-True (-not $triggers.Contains([uint16]$event)) 'Private event used by native map.'
        foreach($obj in (Read-Map $original 'getObjects' $map)) { Assert-True ($obj.getEvent() -ne $event) 'Private event used by native object.' }
    }
}

# Restricted logical pools; no changes to other slots or global native import table.
foreach($field in $mapsType.GetFields() | Where-Object FieldType -eq (RepoType 'processing.common.VanillaBossMaps+VanillaBossMap')) {
    $slot=$field.GetValue($null)
    $pool=$redirect.GetMethod('getOpenWorldRandomPool').Invoke($null,@($slot))
    $supported=($field.Name -eq 'DOPPELGANGERS') -or (RepoType 'processing.common.DoppelgangerEncounterExpansion').GetMethod('SupportsShadows').Invoke($null,@($slot))
    Assert-True (@($pool | Where-Object { $_ -eq 0x81 }).Count -eq [int]$supported) 'Doppelganger pool escaped audited destinations.'
    if(-not $supported) {
        $old=(RepoType 'processing.common.TripleTonpoleBossArenaRedirect').GetMethod('getOpenWorldRandomPool').Invoke($null,@($slot))
        Assert-True (Equal-Bytes $old $pool) 'Unrelated boss pool changed.'
    }
}
Assert-True (-not $mapsType.GetField('BY_VANILLA_BOSS_ID').GetValue($null).ContainsKey([byte]0x81)) 'Synthetic encounter leaked into native import table.'
$case=New-Case; Generate-Events $case; $r=$case[0]; $c=$case[1]
$native=Read-Map $original 'getObjects' 72; $shadows=Read-Map $r 'getObjects' 498
Assert-True ($shadows.Count -eq 3) 'Private arena actor count wrong.'
for($i=0;$i -lt 3;$i++) {
    Assert-True ($shadows[$i].getSpecies() -eq @(0x2E,0x3F,0x20)[$i] -and $shadows[$i].getEvent() -eq 0) 'Shadow species/native death semantics wrong.'
    Assert-True ($shadows[$i].getXpos() -eq $native[$i].getXpos() -and $shadows[$i].getYpos() -eq $native[$i].getYpos()) 'Shadow native position changed.'
    Assert-True ($shadows[$i].getEventVisFlag() -eq 0x10 -and $shadows[$i].getEventVisMaximum() -eq 11) 'Foreign shadows use Jehk state.'
    $at=0x8FF68+8*$i
    Assert-True (Equal-Bytes $r[($at+2)..($at+7)] $original[(0x8A382+8*$i)..(0x8A387+8*$i)]) 'Priority/direction/event metadata changed.'
}
Assert-True (Equal-Bytes $r[0x8FF8C..0x8FF97] @(0xFE,0,15,0xC8,0,1,0xFF,0,15,0xC9,0,1)) 'Trial geometry references changed.'
Assert-True (Equal-Bytes $r[0x8FF80..0x8FF8B] @(0xFE,0,15,0x14,0,0,0xFF,0,15,0x15,0,0)) 'Mantis geometry references changed.'
Assert-True ((Read-Map $r 'getObjects' 497).Count -eq 1 -and (Read-Map $r 'getObjects' 497)[0].getSpecies() -eq 0x57 -and (Read-Map $r 'getObjects' 497)[0].getEvent() -eq 0x6BB) 'Reverse placement is not one Mantis.'
foreach($obj in (Read-Map $r 'getObjects' 72)) { Assert-True ($obj.getEventVisMinimum() -eq 15) 'Native shadow still active beside Mantis.' }
Assert-True ($c.replacementDoors[0x8D].getTargetMap() -eq 498 -and $c.replacementDoors[0x304].getTargetMap() -eq 497) 'Entry doors not bound to private arenas.'
Assert-True (Equal-Bytes $r[0x8332C..0x8332F] $original[0x8332C..0x8332F]) 'Door CB overwritten.'
foreach($table in @(0x84000,0x85000,0x87000)) {
    Assert-True (Equal-Bytes $r[($table+990)..($table+993)] $original[($table+990)..($table+993)]) 'Reachable map 495 boundary changed.'
}

# Execute every defeat subset, all checker boundary values, and repeat/partial entry.
for($mask=0;$mask -lt 8;$mask++) {
    $m=Machine $case; $m.Flags[0x10]=11; $m.Flags[0x3F]=4
    for($i=0;$i -lt 3;$i++) { $m.ActorStatus[$i]=$(if($mask -band (1 -shl $i)) { 0x80 } else { 0x7F }) }
    $m.Run(0x6D6)
    Assert-True ($m.Prizes -eq [int]($mask -eq 7) -and $m.FixedSwordOrbs -eq [int]($mask -eq 7)) 'All-three/exact-once reward condition failed.'
    Assert-True ($m.Flags[0x3F] -eq 4) 'Foreign encounter changed Jehk progression.'
    if($mask -eq 7) {
        Assert-True ($m.LastDoor -eq 0x8E -and $m.Flags[0x10] -eq 12) 'Mantis return/progression lost.'
        $m.Run(0x6D6); $m.Run(0x6D5)
        Assert-True ($m.Prizes -eq 1 -and $m.FixedSwordOrbs -eq 1 -and $m.LastDoor -eq 0x8E) 'Completed entry duplicated reward.'
    } else {
        $m.Run(0x6D5); Assert-True ($m.Prizes -eq 0 -and $m.Flags[0x10] -eq 11) 'Partial entry cleared or claimed encounter.'
        for($i=0;$i -lt 3;$i++) { $m.ActorStatus[$i]=0x80 }
        $m.Run(0x6D6); Assert-True ($m.Prizes -eq 1) 'Partial encounter cannot finish.'
    }
}
foreach($value in @(0,1,0x7E,0x7F,0x80,0x81,0xFF)) {
    $advance=$machineType.GetMethod('NativeActorAdvance').Invoke($null,@($r,[byte[]]@(0x4A,4,0x91,0x7F,0x10,0),[byte[]]@($value,0,0)))
    Assert-True ($advance -eq $(if($value -gt 0x7F) { 6 } else { 4 })) 'Native actor compare width/boundary wrong.'
}
$m=Machine $case; $m.Flags[0x3F]=4; $m.Run(0x4E5)
Assert-True ($m.Prizes -eq 0) 'Exit/early Jehk event can claim before Mantis death.'
$m.Run(0x6BB)
Assert-True ($m.Prizes -eq 1 -and $m.Flags[0x3F] -eq 6 -and $m.LastDoor -eq 0x38) 'Reverse death did not use Jehk prize/progression/return.'
Assert-True ($m.JehkRestorations -eq 1 -and $m.PartyMpRestorations -eq 1) 'Reverse Jehk completion lost its location-owned HP/status/MP restoration.'
[byte[]]$jehkTail=@(0x18,0x38,6,0x24,0x1B,0x2F,0x84,0)
$jehkEvent=$case[1].replacementEvents[0x4E5]
Assert-True (Equal-Bytes $jehkEvent[($jehkEvent.Count-8)..($jehkEvent.Count-1)] $jehkTail) 'Jehk restoration must remain after its return door.'
$m.Run(0x6BB); $m.Run(0x3DB)
Assert-True ($m.Prizes -eq 1 -and $m.LastDoor -eq 0x38) 'Reverse re-entry/callback duplicates prize.'
Assert-True ($m.JehkRestorations -eq 1 -and $m.PartyMpRestorations -eq 1) 'Completed re-entry unexpectedly repeats first-completion restoration.'

# Original native trial still works when retained, and NoEnemies protects only it.
$retained=New-Case 'Mantis-Ant' 'Doppelgangers'; Generate-Events $retained
Apply 'processing.hacks.openworld.NoEnemies' $retained
foreach($obj in (Read-Map $retained[0] 'getObjects' 72)) { Assert-True ($obj.getEventVisMinimum() -ne 15) 'NoEnemies removed selected native shadows.' }
Assert-True ((Read-Map $retained[0] 'getObjects' 498).Count -eq 0) 'Retained native trial allocated a duplicate foreign trio.'
$nativeMachine=Machine $retained; $nativeMachine.Flags[0x3F]=4
$nativeMachine.Run(0x4E5); Assert-True ($nativeMachine.Prizes -eq 0) 'Native completion bypassed.'
for($i=0;$i -lt 3;$i++) { $nativeMachine.ActorStatus[$i]=0x80 }
$nativeMachine.Run(0x4E5); Assert-True ($nativeMachine.Prizes -eq 1 -and $nativeMachine.Flags[0x3F] -eq 6) 'Native trial completion lost.'
Assert-True ($nativeMachine.JehkRestorations -eq 1 -and $nativeMachine.PartyMpRestorations -eq 1) 'Retained native trial lost restoration.'

# No private writer touches AI, other actors, native executable code or existing arenas.
foreach($caseToCheck in @($case,$retained)) {
    Apply 'processing.common.EnemySwaps' $caseToCheck
    Apply 'processing.hacks.openworld.EnemyRandomizer' $caseToCheck
    $caseToCheck[2].set('opAiRando','swap')
    Apply 'processing.hacks.openworld.AISwap' $caseToCheck
    foreach($id in @(0x2E,0x3F,0x20)) {
        $at=0x100000+16*$id
        Assert-True (Equal-Bytes $caseToCheck[0][$at..($at+15)] $original[$at..($at+15)]) 'Shadow graphics/AI pointer changed.'
    }
    Assert-True (Equal-Bytes $caseToCheck[0][0x105605..0x105704] $original[0x105605..0x105704]) 'Native shadow AI changed.'
    Assert-True (Equal-Bytes $caseToCheck[0][0x8E0B5..0x8FED5] $original[0x8E0B5..0x8FED5]) 'Native C8 executable code corrupted.'
}
$roles=New-Case
foreach($key in @('boyClass','girlClass','spriteClass')) { $roles[1].workingData.set($key,'OGsprite') }
Apply 'processing.hacks.openworld.CharacterClasses' $roles
foreach($id in @(0x2E,0x3F,0x20)) {
    $at=0x100000+16*$id
    Assert-True (Equal-Bytes $roles[0][$at..($at+15)] $original[$at..($at+15)]) 'Duplicate gameplay roles changed fixed shadow appearance/AI.'
}
$scaled=New-Case; $scaled[2].set('opStatGrowth','bosses'); $scaled[2].set('opMinLevel','yes'); $scaled[2].set('opMaxLevel','yes')
Apply 'processing.openworld.OpenWorldDifficultyProcessor' $scaled
Apply 'processing.hacks.openworld.MinMaxLevel' $scaled
$minType=RepoType 'processing.hacks.openworld.MinMaxLevel'
foreach($field in @('MINMAXLEVEL_MIN_OFFSET_HIROM','MINMAXLEVEL_MAX_OFFSET_HIROM')) {
    $at=$scaled[1].workingData.getInt($minType.GetField($field).GetValue($null))-0xC00000
    Assert-True ($scaled[0][$at+498] -eq $scaled[0][$at+260] -and $scaled[0][$at+497] -eq $scaled[0][$at+72]) 'Private arena lost original slot level bounds.'
}
Apply 'processing.hacks.openworld.CustomTopOfScreenText' $scaled
Apply 'processing.hacks.openworld.EnemiesAtYourLevel' $scaled
foreach($id in @(0x2E,0x3F,0x20,0,0x57)) {
    $isBoss=$machineType.GetMethod('CountsAsBoss').Invoke($null,@($scaled[0],[byte]$id))
    Assert-True ($isBoss -eq ($id -in @(0x2E,0x57))) 'Shadow logical boss scaling count changed.'
}
$coexist=New-Case 'Doppelgangers' 'Mantis-Ant' 'random' $true; Generate-Events $coexist
Assert-True ((Read-Map $coexist[0] 'getObjects' 500).Count -eq 3 -and (Read-Map $coexist[0] 'getObjects' 498).Count -eq 3) 'Triple/shadow allocations overlap.'
Assert-True ($coexist[1].replacementDoors.ContainsKey(0x10B) -and $coexist[1].replacementDoors[0x14F].getTargetMap() -eq 510) 'Slime/Doom staging lost.'
Assert-True (Equal-Bytes $coexist[0][0x8FF20..0x8FF4D] (New-Case 'Mantis-Ant' 'Doppelgangers' 'random' $true)[0][0x8FF20..0x8FF4D]) 'Triple allocation changed.'
foreach($mode in @('random','swap')) {
    $a=New-Case 'Doppelgangers' 'Mantis-Ant' $mode; $b=New-Case 'Doppelgangers' 'Mantis-Ant' $mode
    Assert-True (Equal-Bytes $a[0] $b[0]) 'Focused boss assignment not deterministic.'
}
$off=New-Case 'Mantis-Ant' 'Doppelgangers' 'vanilla'
Assert-True (Equal-Bytes $off[0][0..($original.Length-1)] $original) 'Vanilla boss mode modified native ROM.'
Assert-True (Equal-Bytes $off[0][0x8FF50..0x8FFA3] $original[0x8FF50..0x8FFA3]) 'Vanilla boss mode allocated maps.'
foreach($at in @(0x8FF50,0x8FF80,0x8FF98,0x8FFA3)) {
    $collision=New-Case 'Mantis-Ant' 'Doppelgangers'; $collision[0][$at]=0
    try { $redirect.GetMethod('createForeign').Invoke($null,@($collision[0],$collision[1])); throw 'Occupied allocation accepted.' }
    catch { Assert-True ($_.Exception.ToString().Contains('allocation already owned')) 'Wrong allocation collision failure.' }
}
Write-Output 'PASS: Doppelganger bidirectional Mantis placement, native-machine actor checks, exact-once rewards, native trial, allocation coexistence, enemy/AI exclusion and determinism.'
