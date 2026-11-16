param(
    [string]$AssemblyPath=(Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe'),
    [string]$SourceRom='D:\views\tools\bots\Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc'
)
$ErrorActionPreference='Stop'
function Assert-True([bool]$Condition,[string]$Message) { if(-not $Condition) { throw $Message } }
function Equal-Bytes($A,$B) { return [Linq.Enumerable]::SequenceEqual([byte[]]$A,[byte[]]$B) }
function Contains-Bytes($Data,[byte[]]$Bytes) {
    for($i=0;$i -le $Data.Count-$Bytes.Length;$i++) {
        if(Equal-Bytes $Data[$i..($i+$Bytes.Length-1)] $Bytes) { return $true }
    }
    return $false
}
$assembly=[Reflection.Assembly]::LoadFrom((Resolve-Path $AssemblyPath).Path)
function RepoType([string]$Name) { return $assembly.GetType('SoMRandomizer.'+$Name,$true) }
$commonType=RepoType 'config.settings.CommonSettings'
$settingsType=RepoType 'config.settings.OpenWorldSettings'
$contextType=RepoType 'processing.common.RandoContext'
$mapsType=RepoType 'processing.common.VanillaBossMaps'
$mapType=RepoType 'processing.common.VanillaBossMaps+VanillaBossMap'
$swapsType=RepoType 'processing.common.BossSwaps'
$redirect=RepoType 'processing.common.TripleTonpoleBossArenaRedirect'
$mapUtil=RepoType 'processing.common.VanillaMapUtil'
$eventUtil=RepoType 'processing.common.VanillaEventUtil'
$namesType=RepoType 'processing.hacks.common.util.NamesOfThings'
$flags=[Reflection.BindingFlags]'Instance,NonPublic'
[byte[]]$original=[IO.File]::ReadAllBytes((Resolve-Path $SourceRom).Path)
function MapValue([string]$Name) { return $mapsType.GetField($Name).GetValue($null) }
function Read-Map($Rom,[string]$Method,[int]$Id) { return ,($mapUtil.GetMethod($Method).Invoke($null,@($Rom,$Id))) }
function New-Case([string]$Target='MANTISANT',[string]$Ice='Mantis-Ant',[string]$Undine='Minotaur',[bool]$Coexist=$false,[string]$Mode='random',[bool]$UnplannedIce=$false) {
    $s=[Activator]::CreateInstance($settingsType,[object[]]@([Activator]::CreateInstance($commonType)))
    $s.set('opBosses',$Mode); $s.set('crystalOrbWeaponBreaking','off')
    $c=[Activator]::CreateInstance($contextType); $c.randomFunctional=[Random]::new(19283)
    $c.namesOfThings=[Activator]::CreateInstance($namesType,[object[]]@(,$original))
    # Pin all remaining slots, so assertions cover only this focused feature.
    $p=RepoType 'processing.openworld.PlandoProperties'
    $idNames=@{}
    foreach($pair in $p.GetField('BOSS_IDS_BY_PLANDO_VALUE').GetValue($null).GetEnumerator()) { $idNames[[int]$pair.Value]=$pair.Key }
    $pins=@{
        mantisAnt='Mantis-Ant'; wallFace='Wall-Face'; tropicallo='Tropicallo'; minotaur='Minotaur';
        spikeyTiger='Spikey-Tiger'; jabberwocky='Jabberwocky'; springBeak='Spring-Beak'; frostGigas='Frost-Gigas';
        snapDragon='Snap-Dragon'; doomsWall="Doom's-Wall"; vampire='Vampire'; metalMantis='Metal-Mantis';
        mechRider2='Mech-Rider-2'; kilroy='Kilroy'; gorgonBull='Gorgon-Bull'; borealFace='Boreal-Face';
        greatViper='Great-Viper'; limeSlime='Lime-Slime'; blueSpike='Blue-Spike'; hydra='Hydra';
        watermelon='Watermelon'; hexas='Hexas'; kettleKin='Kettle-Kin'; tonpole=$Undine;
        mechRider3='Mech-Rider-3'; snowDragon='Snow-Dragon'; fireGigas='Fire-Gigas'; redDragon='Red-Dragon';
        axeBeak='Axe-Beak'; blueDragon='Blue-Dragon'; buffy='Buffy'; darkLich='Dark-Lich';
        dragonWorm='Dragon-Worm'; dreadSlime='Dread-Slime'; thunderGigas='Thunder-Gigas'; tripleTonpole=$Ice
    }
    # Use the repository's actual stable property/value spellings, not display guesses.
    foreach($field in $p.GetFields() | Where-Object Name -Like 'KEY_BOSS_*') {
        if($field.Name -like '*ELEMENT*') { continue }
        $key=[string]$field.GetValue($null)
        if($pins.ContainsKey($key.Substring(2))) {
            $value=$pins[$key.Substring(2)]
            if(-not $p.GetField('BOSS_IDS_BY_PLANDO_VALUE').GetValue($null).ContainsKey($value)) {
                $mapName=$field.Name.Substring(9).Replace('JABBERWOCKY','JABBER').Replace('GORGONBULL','GORGON').Replace('BOREALFACE','BOREAL').Replace('WATERMELON','AEGRTOJNFSDGHOPALNIAPLEIAN')
                $map=MapValue $mapName; $value=$idNames[[int]$map.getOriginalBossId($original)]
            }
            $c.plandoSettings[$key]=[Collections.Generic.List[string]]::new([string[]]@($value))
        }
    }
    $c.plandoSettings['P_tonpole']=[Collections.Generic.List[string]]::new([string[]]@($Undine))
    if($Target -ne 'native') {
        $slot=MapValue $Target
        $keyByMap=@{260='P_mantisAnt';166='P_wallFace';290='P_tropicallo';143='P_jabberwocky';100='P_mechRider2';238='P_watermelon';237='P_mechRider3';364='P_frostGigas';495='P_fireGigas';277='P_tonpole'}
        $c.plandoSettings[$keyByMap[$slot.originalMapNum]]=[Collections.Generic.List[string]]::new([string[]]@('Triple-Tonpole'))
    }
    if($Coexist) {
        $c.plandoSettings['P_tropicallo']=[Collections.Generic.List[string]]::new([string[]]@('Lime-Slime'))
        $c.plandoSettings['P_limeSlime']=[Collections.Generic.List[string]]::new([string[]]@('Minotaur'))
        $c.plandoSettings['P_jabberwocky']=[Collections.Generic.List[string]]::new([string[]]@('Dread-Slime'))
        $c.plandoSettings['P_dreadSlime']=[Collections.Generic.List[string]]::new([string[]]@('Mantis-Ant'))
        $c.plandoSettings['P_doomsWall']=[Collections.Generic.List[string]]::new([string[]]@('Mantis-Ant'))
    }
    if($UnplannedIce) { [void]$c.plandoSettings.Remove('P_tripleTonpole') }
    [byte[]]$r=[byte[]]::new(0x400000); [Array]::Copy($original,$r,$original.Length)
    $c.originalRom=$original; $c.outputRom=$r
    [void]$swapsType.GetMethod('process',$flags).Invoke([Activator]::CreateInstance($swapsType),@($original,$r,'triple-test',$s,$c))
    return ,@($r,$c,$s)
}
function Generate-Events($C,$S) {
    $C.workingData.set('openWorldGoalShortName','manabeast'); $C.workingData.setBool('fastManaFort',$true)
    $C.workingData.setBool('anyMagicExists',$true)
    $C.workingData.set('boyClass','OGboy'); $C.workingData.set('girlClass','OGgirl'); $C.workingData.set('spriteClass','OGsprite')
    $C.workingData.setInt('manaSeedsRequired',8)
    $element=RepoType 'processing.ElementSwaps'; $C.workingData.setInt($element.GetField('ORBELEMENT_PREFIX').GetValue($null)+35,0x81)
    foreach($name in @('PrizeEvents','OpenWorldSupportingEvents','OpenWorldSupportingMapChanges')) {
        $t=RepoType ('processing.openworld.events.'+$name)
        [void]$t.GetMethod('process',$flags).Invoke([Activator]::CreateInstance($t),@($original,$C.outputRom,'triple-events',$S,$C))
    }
}
# Execute the actual emitted death counter prefix (not a hard-coded model).
function Count-Death($Bytes,[int[]]$State,[int]$Flag) {
    $pc=0
    while($pc -lt $Bytes.Count) {
        switch($Bytes[$pc]) {
            0x42 {
                $f=$Bytes[$pc+1]; $low=$Bytes[$pc+2]-shr 4; $high=$Bytes[$pc+2]-band 15
                if($State[$f] -ge $low -and $State[$f] -le $high) { return $false }
                $pc+=5
            }
            0x29 { $State[$Bytes[$pc+1]]++; $pc+=2 }
            default { return $true }
        }
    }
    throw 'Counter lacks completion tail.'
}
# Follow the generated event transfers AND native music callees. In particular,
# END terminates the whole event even when reached through JSR; only RETURN
# resumes the caller. Treat the unchanged fixed-orb/victory callees as observed
# boundaries, not every JSR as an automatically returning call.
function New-UndineState {
    return @{ Flags=[int[]]::new(256); Doors=[Collections.Generic.List[int]]::new();
        Sounds=[Collections.Generic.List[int]]::new(); FixedOrbs=0; Victories=0; Refreshes=0 }
}
function Run-UndineEvent($Context,[int]$Id,$State) {
    $pc=0; $stack=[Collections.Generic.Stack[object]]::new()
    for($steps=0;$steps -lt 200;$steps++) {
        if($Id -eq 0) { return }
        $script=if($Context.replacementEvents.ContainsKey($Id)) { $Context.replacementEvents[$Id] }
            else { $eventUtil.GetMethod('getVanillaEvent').Invoke($null,@($original,$Id)) }
        $op=[int]$script[$pc]
        if($op -eq 0) { return } # native END does NOT return to a JSR caller
        elseif($op -eq 2) {
            if($stack.Count -eq 0) { return }
            $frame=$stack.Pop(); $Id=$frame[0]; $pc=$frame[1]
        }
        elseif($op -eq 0x42) {
            $value=$State.Flags[$script[$pc+1]]; $range=$script[$pc+2]
            if($value -ge ($range-shr 4) -and $value -le ($range-band 15)) { $pc+=3 } else { $pc+=5 }
        }
        elseif($op -ge 0x10 -and $op -le 0x17) { $Id=(($op-0x10)-shl 8)-bor $script[$pc+1]; $pc=0 }
        elseif($op -ge 0x18 -and $op -le 0x1B) { $State.Doors.Add((($op-0x18)-shl 8)-bor $script[$pc+1]); $pc+=2 }
        elseif($op -ge 0x20 -and $op -le 0x27) {
            $call=(($op-0x20)-shl 8)-bor $script[$pc+1]
            if($call -eq 0x500) { $State.FixedOrbs++; $pc+=2 }
            elseif($call -eq 0x784) { $State.Victories++; $pc+=2 }
            else { $stack.Push(@($Id,($pc+2))); $Id=$call; $pc=0 }
        }
        elseif($op -eq 0x29) { $State.Flags[$script[$pc+1]]=($State.Flags[$script[$pc+1]]+1)-band 15; $pc+=2 }
        elseif($op -eq 0x30) { $State.Flags[$script[$pc+1]]=$script[$pc+2]; $pc+=3 }
        elseif($op -eq 0x0A) { $State.Refreshes++; $pc++ }
        elseif($op -eq 0x40) { $State.Sounds.Add($script[$pc+2]); $pc+=5 }
        else { throw ('Unsupported Undine event opcode '+$op.ToString('X2')) }
    }
    throw 'Undine event failed to terminate.'
}
$safe=@('MANTISANT','WALLFACE','TROPICALLO','JABBER','MECHRIDER2','AEGRTOJNFSDGHOPALNIAPLEIAN','MECHRIDER3','FROSTGIGAS','FIREGIGAS','TONPOLE','TRIPLE_TONPOLE')
foreach($field in $mapsType.GetFields() | Where-Object FieldType -eq $mapType) {
    $pool=$redirect.GetMethod('getOpenWorldRandomPool').Invoke($null,@($field.GetValue($null)))
    $count=@($pool | Where-Object { $_ -eq 0x80 }).Count
    Assert-True ($count -eq [int]($safe -contains $field.Name)) ('Triple weighting/compatibility wrong: '+$field.Name)
}
$native=Read-Map $original 'getObjects' 361
Assert-True ($native.Count -eq 3) 'Native triple actor count changed.'
for($i=0;$i -lt 3;$i++) {
    Assert-True ($native[$i].getSpecies() -eq 0x71 -and $native[$i].getEvent() -eq 0x66A -and $native[$i].getUnknownB7() -eq 8) 'Native species/death contract changed.'
}
Assert-True (Equal-Bytes $original[0x26294..0x2629A] @(0xA9,0x7A,0,0x22,0x3F,0,0xC0)) 'Transformation no longer uses full stat initialization.'
foreach($id in @(0x1F3,0x1F4,0x1F5)) {
    Assert-True ((Read-Map $original 'getObjects' $id).Count -eq 0 -and (Read-Map $original 'getTriggers' $id).Count -eq 0) 'Map allocation not empty.'
    for($door=0;$door -lt 0x400;$door++) {
        $at=0x83000+4*$door
        Assert-True (($original[$at]+(($original[$at+1]-band 1)-shl 8)) -ne $id) 'Generated map has native entrance.'
    }
}
foreach($id in @(0x6D2,0x6D3,0x6D4)) {
    Assert-True (Equal-Bytes ($eventUtil.GetMethod('getVanillaEvent').Invoke($null,@($original,$id))) @(0)) 'Event allocation not empty.'
    for($map=0;$map -lt 511;$map++) {
        Assert-True (-not ((Read-Map $original 'getTriggers' $map).Contains([uint16]$id))) 'Allocated event already used by native trigger.'
        foreach($obj in (Read-Map $original 'getObjects' $map)) { Assert-True ($obj.getEvent() -ne $id) 'Allocated event used by native actor.' }
    }
}
$case=New-Case; $r=$case[0]; $c=$case[1]; $s=$case[2]
Generate-Events $c $s
Assert-True ((Read-Map $r 'getObjects' 277)[0].getSpecies() -eq 0x5A -and (Read-Map $r 'getObjects' 361)[0].getSpecies() -eq 0x57) 'Undine/Ice assignment not independent.'
Assert-True (-not $c.replacementDoors.ContainsKey(0x2C2)) 'Ordinary Ice boss redirected away from native arena.'
Assert-True ((Read-Map $r 'getObjects' 361)[0].getEvent() -eq 0x66A -and (Read-Map $r 'getObjects' 361)[1].getEventVisMinimum() -eq 15) 'Ordinary Ice lost slot event/single-object behavior.'
Assert-True (Contains-Bytes $c.replacementEvents[0x66A] @(0x29,0x25,0x29,0x25,0x29,0x25,0x30,0x56,5,0x30,0x26,3)) 'Ordinary Ice progression changed.'
Assert-True (Contains-Bytes $c.replacementEvents[0x66A] @(0x1A,0xC3,0x17,0x15,0)) 'Ice continuation changed.'
Assert-True (Contains-Bytes $c.replacementEvents[0x66A] @(0x12,0x34,0x56,0x78,0)) 'Ice reward injection lost.'
$objs=Read-Map $r 'getObjects' 0x1F4; $h=Read-Map $r 'getHeader' 0x1F4
Assert-True ($objs.Count -eq 3 -and -not $h.getMode7Enabled() -and $h.getDisplaySetting() -eq 2 -and $h.getPaletteSet() -eq 0x54) 'Foreign triple is not the regular native arena.'
for($i=0;$i -lt 3;$i++) {
    Assert-True ($objs[$i].getSpecies() -eq 0x71 -and $objs[$i].getEvent() -eq 0x6D2 -and $objs[$i].getEventVisFlag() -eq 0xE3 -and $objs[$i].getXpos() -eq $native[$i].getXpos() -and $objs[$i].getYpos() -eq $native[$i].getYpos() -and $objs[$i].getUnknownB7() -eq 8) 'Foreign triple layout/ownership changed.'
}
Assert-True (Equal-Bytes $r[0x8FF40..0x8FF4B] @(0xFE,0,15,0xD7,1,0,0xFF,0,15,0xD8,1,0)) 'Triple references not native.'
foreach($id in @(0x1D7,0x1D8)) {
    $decoded=$mapUtil.GetMethod('loadVanillaMapPiece').Invoke($null,@($r,$id))
    Assert-True ($decoded.GetLength(0) -eq 24 -and $decoded.GetLength(1) -eq 28) 'Triple geometry changed.'
}
Assert-True (Contains-Bytes $c.replacementEvents[0x6D2] @(0x11,0x12,0)) 'Foreign completion does not use Mantis event.'
Assert-True (-not (Contains-Bytes $c.replacementEvents[0x6D2] @(0x30,0x56)) -and -not (Contains-Bytes $c.replacementEvents[0x6D2] @(0x1A,0xC3))) 'Foreign triple invokes Ice progression.'
[int[]]$state=[int[]]::new(256); $completions=0
for($death=0;$death -lt 6;$death++) { if(Count-Death $c.replacementEvents[0x6D2] $state 0xE3) { $completions++ } }
Assert-True ($completions -eq 1 -and $state[0xE3] -eq 3 -and $state[0x25] -eq 0) 'Foreign completion repeats or changes native count.'
$nativeCase=New-Case 'native' 'Triple-Tonpole'
Generate-Events $nativeCase[1] $nativeCase[2]
Assert-True (Equal-Bytes $nativeCase[0][0x8D298..0x8D2B7] $original[0x8D298..0x8D2B7]) 'Native triple header/layout changed.'
[int[]]$state=[int[]]::new(256); $completions=0
for($death=0;$death -lt 6;$death++) { if(Count-Death $nativeCase[1].replacementEvents[0x66A] $state 0x25) { $completions++ } }
Assert-True ($completions -eq 1 -and $state[0x25] -eq 3) 'Native completion repeats or occurs before third kill.'
# Real emitted HP routine: both forms, odd/1 HP, other species/maps, actor indices,
# scaled and unscaled contexts all share the same post-initialization hook.
Add-Type -Path (Join-Path $PSScriptRoot 'support\SlimeDialogueMachine.cs')
$balance=RepoType 'processing.hacks.openworld.TripleTonpoleBalance'
foreach($testCase in @($case,$nativeCase)) {
    $before=$testCase[0].Clone()
    Assert-True ($balance.GetMethod('process',$flags).Invoke([Activator]::CreateInstance($balance),@($original,$testCase[0],'hp',$testCase[2],$testCase[1]))) 'Triple balance skipped.'
    Assert-True (Equal-Bytes $before[0x101C00..0x102A7F] $testCase[0][0x101C00..0x102A7F]) 'Local balance changed global stats.'
    $start=$testCase[1].workingData.getInt('tripleTonpoleHpRoutine')+0xC00000
    foreach($map in @(361,500,277)) { foreach($species in @(0x71,0x7A,0x57)) { foreach($hp in @(1,600,771)) { foreach($actor in @(0x600,0x800,0xA00)) {
        $cpu=[SlimeDialogueMachine]::new($testCase[0]); $cpu.A=0xBEEF; $cpu.X=$species*29; $cpu.Y=$actor; $cpu.P=0x21
        $cpu.Write(0x7E00DC,$map,2); $cpu.Write(0x7EE1E7+$actor,$species,1)
        $cpu.Write(0x7EE184+$actor,$hp,2); $cpu.Write(0x7EE182+$actor,$hp,2)
        $cpu.Run($start,$true)
        $isNative=$redirect.GetMethod('isNativeTriple').Invoke($null,@($testCase[1]))
        $matches=($species -in @(0x71,0x7A)) -and (($isNative -and $map -eq 361) -or (-not $isNative -and $map -eq 500))
        $expected=$hp; if($matches) { $expected=[Math]::Max(1,[Math]::Floor($hp/2)) }
        Assert-True ($cpu.Read(0x7EE184+$actor,2) -eq $expected -and $cpu.Read(0x7EE182+$actor,2) -eq $expected) 'Encounter-local HP guard/rounding incorrect.'
        Assert-True ($cpu.X -eq $species*29 -and $cpu.Y -eq $actor -and ($cpu.P-band 0x21) -eq 0x21 -and $cpu.DB -eq 0x7E) 'HP hook damaged registers/width/carry.'
    } } } }
}
$cave=New-Case 'TONPOLE'
Generate-Events $cave[1] $cave[2]
Assert-True (Contains-Bytes $cave[1].replacementEvents[0x233] @(0x19,0x47,0x17,0x0B,0)) 'Undine return must precede the terminal music jump.'
Assert-True (Contains-Bytes $cave[1].replacementEvents[0x6D3] @(0x42,0xA0,0x1F,0x16,0xD4)) 'Completed Undine encounter respawns trio.'
Assert-True (Equal-Bytes $cave[1].replacementEvents[0x6D4] @(0x42,0xA0,0x1F,0x19,0x47,0x42,0xA0,0,0x19,0x44,0)) 'Undine source gate must choose only the uncleared or completed door.'
Assert-True (([string]::Join(',',(Read-Map $cave[0] 'getTriggers' 275))) -eq '560,1748,1748,2369,2369') 'Both source portals must test completion before loading the trio.'
# This native callee ends the entire event; it cannot be called before a door.
Assert-True (Equal-Bytes ($eventUtil.GetMethod('getVanillaEvent').Invoke($null,@($original,0x70B))) @(0x40,1,0x0B,0x17,0x8F,0)) 'Native dungeon music event contract changed.'
Assert-True (Equal-Bytes $original[0x1E9C4..0x1E9C7] @(0x64,0xF1,0x64,0xD0)) 'Native END no longer terminates interpreter state.'
$undineState=New-UndineState
Run-UndineEvent $cave[1] 0x6D3 $undineState
Assert-True ($undineState.Flags[0xE3] -eq 0 -and $undineState.Doors.Count -eq 0) 'Uncleared entry skips the trio.'
for($death=1;$death -le 3;$death++) {
    # Each native Tonpole transforms to Biting Lizard, retaining this callback;
    # feed its final death, not its intermediate transformation, to the event.
    Run-UndineEvent $cave[1] 0x6D2 $undineState
    Assert-True ($undineState.Flags[0xE3] -eq $death) 'Final transformed deaths were not counted.'
    if($death -lt 3) { Assert-True ($undineState.Flags[0xA0] -eq 0 -and $undineState.FixedOrbs -eq 0 -and $undineState.Doors.Count -eq 0) 'Premature Undine completion.' }
}
Assert-True ($undineState.Flags[0xA0] -eq 1 -and $undineState.FixedOrbs -eq 1 -and $undineState.Victories -eq 1 -and $undineState.Refreshes -eq 1) 'Undine victory/reward/progression did not run exactly once.'
Assert-True ($undineState.Doors.Count -eq 1 -and $undineState.Doors[0] -eq 0x147 -and $undineState.Sounds.Contains(0x0B)) 'Third death did not return to the cleared cave and restore its music.'
$flagsAfter=$undineState.Flags.Clone()
Run-UndineEvent $cave[1] 0x6D2 $undineState
Run-UndineEvent $cave[1] 0x6D3 $undineState
Assert-True ($undineState.Doors.Count -eq 2 -and $undineState.Doors[1] -eq 0x147 -and $undineState.FixedOrbs -eq 1 -and $undineState.Victories -eq 1 -and (Equal-Bytes $undineState.Flags $flagsAfter)) 'Duplicate death/completed re-entry respawns or rewards the trio.'
# Reproduce the shipped bug with the actual native callee: JSR $70B reaches
# END before Door $147. A byte-presence-only assertion used to miss this.
$fixedTail=$cave[1].replacementEvents[0x233]
try {
    $broken=[Collections.Generic.List[byte]]::new([byte[]]$fixedTail.GetRange(0,$fixedTail.Count-5))
    $broken.AddRange([byte[]]@(0x27,0x0B,0x19,0x47,0)); $cave[1].replacementEvents[0x233]=$broken
    $oldState=New-UndineState; $oldState.Flags[0xE3]=2
    Run-UndineEvent $cave[1] 0x6D2 $oldState
    Assert-True ($oldState.Flags[0xA0] -eq 1 -and $oldState.FixedOrbs -eq 1 -and $oldState.Doors.Count -eq 0) 'Regression no longer reproduces the shipped unreachable return door.'
} finally { $cave[1].replacementEvents[0x233]=$fixedTail }
# A normal compatible boss still completes in the native room without an
# injected return. Compare its full death script with the trio variant minus
# only the added door, and preserve native exits and visibility flag $A0.
$normal=New-Case 'native' 'Mantis-Ant' 'Minotaur'; Generate-Events $normal[1] $normal[2]
$withoutDoor=[Collections.Generic.List[byte]]::new($fixedTail); $withoutDoor.RemoveRange($withoutDoor.Count-5,2)
Assert-True (Equal-Bytes $normal[1].replacementEvents[0x233] $withoutDoor) 'Normal Undine death event changed beyond the trio return door.'
Assert-True (Equal-Bytes $cave[1].replacementEvents[0x581] $normal[1].replacementEvents[0x581]) 'Undine NPC randomized rewards changed.'
foreach($prizeIndex in @(0,1)) {
    Assert-True (Contains-Bytes $cave[1].replacementEvents[0x581] @(0x12,0x34,0x56,0x78,$prizeIndex)) 'An Undine NPC randomized prize was lost.'
}
$normalState=New-UndineState; Run-UndineEvent $normal[1] 0x233 $normalState
Assert-True ($normalState.Flags[0xA0] -eq 1 -and $normalState.FixedOrbs -eq 1 -and $normalState.Doors.Count -eq 0 -and $normalState.Flags[0xE3] -eq 0) 'Normal Undine boss completion changed.'
foreach($testCase in @($cave,$normal)) {
    Assert-True (([string]::Join(',',(Read-Map $testCase[0] 'getTriggers' 277))) -eq ([string]::Join(',',(Read-Map $original 'getTriggers' 277)))) 'Native cave exits changed.'
    $nativeActor=(Read-Map $testCase[0] 'getObjects' 277)[0]
    Assert-True ($nativeActor.getEventVisFlag() -eq 0xA0 -and $nativeActor.getEventVisMaximum() -eq 0) 'Completed native boss visibility no longer uses Undine progression.'
    Assert-True (Equal-Bytes $testCase[0][0x8351C..0x8351F] $original[0x8351C..0x8351F]) 'Door $147 return destination changed.'
    $refs=0x80000+[int]$testCase[0][0x8522A]+([int]$testCase[0][0x8522B]-shl 8)
    Assert-True (Equal-Bytes $testCase[0][($refs+6)..($refs+7)] @(0xA0,0x1F)) 'First native exit does not open at Undine completion.'
    Assert-True (Equal-Bytes $testCase[0][($refs+11)..($refs+12)] @(0xA0,0x1F)) 'Second native exit does not open at Undine completion.'
    foreach($door in @(0x143,0x146)) {
        $at=0x83000+4*$door
        Assert-True (Equal-Bytes $testCase[0][$at..($at+3)] $original[$at..($at+3)]) 'Native cave exit/Undine reward-room door changed.'
    }
    Assert-True ($testCase[0][0xD635F] -eq 0xAF -and $testCase[0][0xD636A] -eq 0xAF) 'Native cave exit tile repair was bypassed.'
}
# Coexistence through real processors, not just theoretical span comparisons.
$coexist=New-Case 'MANTISANT' 'Mantis-Ant' 'Minotaur' $true
Generate-Events $coexist[1] $coexist[2]
$snapshot=$coexist[0][0x8FF20..0x8FF4D]
$coexist[1].randomCosmetic=[Random]::new(1)
for($i=0;$i -lt 3;$i++) { $coexist[1].workingData.set('nesoPrize'+$i,'sword'); $coexist[1].workingData.set('nesoHint'+$i,'Potos') }
$neso=RepoType 'processing.hacks.openworld.Nesoberi'
[void]$neso.GetMethod('process',$flags).Invoke([Activator]::CreateInstance($neso),@($original,$coexist[0],'coexist',$coexist[2],$coexist[1]))
Assert-True (Equal-Bytes $coexist[0][0x8FF20..0x8FF4D] $snapshot) 'Later processor clobbered Triple.'
Assert-True ((Read-Map $coexist[0] 'getObjects' 0x1FA)[0].getSpecies() -eq 0x6A -and (Read-Map $coexist[0] 'getObjects' 0x1F6)[0].getSpecies() -eq 0x7C -and (Read-Map $coexist[0] 'getObjects' 0x1FE)[0].getEvent() -eq 0x553) 'Slime/Doom coexistence failed.'
Assert-True (Equal-Bytes $coexist[0][0x88FBE..0x88FC9] @(0xE0,1,0x2F,9,0x30,9,0x8B,1,0x2B,9,0x2B,9)) 'Nesoberi changed.'
# Also exercise the reverse allocation order: Dread can be drawn earlier than
# Triple. Unused sentinel intervals must not be mistaken for occupied maps.
$reverse=New-Case 'native' 'Mantis-Ant'
$dread=RepoType 'processing.common.DreadSlimeBossArenaRedirect'
[void]$dread.GetMethod('createDreadInForeignSlot').Invoke($null,@($reverse[0],$reverse[1],(MapValue 'MANTISANT'),[uint16]0x112))
[void]$redirect.GetMethod('create').Invoke($null,@($reverse[0],$reverse[1],(MapValue 'FROSTGIGAS'),[uint16]0x66D))
Assert-True ((Read-Map $reverse[0] 'getObjects' 0x1F4).Count -eq 3 -and (Read-Map $reverse[0] 'getObjects' 0x1F6)[0].getSpecies() -eq 0x7C) 'Reverse allocation order failed.'
# Run the real final serializers in memory; no extra generation/ROM files.
foreach($name in @('EventExpander','MapPieceExpander')) {
    $t=RepoType ('processing.hacks.common.util.'+$name)
    $data=$coexist[1].replacementEvents; if($name -eq 'MapPieceExpander') { $data=$coexist[1].replacementMapPieces }
    [object[]]$args=@($coexist[0],$data,[int]$coexist[1].workingOffset)
    [void]$t.GetMethod('process').Invoke([Activator]::CreateInstance($t),$args)
    $coexist[1].workingOffset=[int]$args[2]
}
Assert-True (Equal-Bytes $coexist[0][0x8FF20..0x8FF4D] $snapshot) 'Final serializers clobbered Triple arena.'
$doors=RepoType 'processing.hacks.common.util.DoorReplacer'
[void]$doors.GetMethod('process').Invoke([Activator]::CreateInstance($doors),@($r,$c))
Assert-True (Equal-Bytes $r[0x83234..0x83237] @(0xF4,0x17,0x26,0x80)) 'Foreign Triple entry contract wrong.'
Assert-True (Equal-Bytes $r[0x83B08..0x83B0F] $original[0x83B08..0x83B0F]) 'Ice native entry/continuation doors changed.'
# Native donor bytes, all already-owned allocations, and transformation code
# must stay untouched by the private Triple writer itself.
$isolated=New-Case 'native' 'Triple-Tonpole'
$before=$isolated[0].Clone()
$redirect.GetMethod('create').Invoke($null,@($isolated[0],$isolated[1],(MapValue 'MANTISANT'),[uint16]0x112)) | Out-Null
$allowed=[Collections.Generic.HashSet[int]]::new()
foreach($span in @(@(0x8FF20,0x8FF4D),@(0x843E8,0x843EB),@(0x853E8,0x853EB),@(0x873E8,0x873EB))) {
    for($i=$span[0];$i -le $span[1];$i++) { [void]$allowed.Add($i) }
}
for($i=0;$i -lt $before.Length;$i++) {
    if($before[$i] -ne $isolated[0][$i]) { Assert-True ($allowed.Contains($i)) ('Private writer escaped allocation at '+$i.ToString('X6')) }
}
foreach($at in @(0x8FF20,0x8FF40,0x8FF4C)) {
    $conflict=New-Case 'native' 'Triple-Tonpole'; $conflict[0][$at]=0
    try {
        [void]$redirect.GetMethod('create').Invoke($null,@($conflict[0],$conflict[1],(MapValue 'MANTISANT'),[uint16]0x112))
        throw 'Allocation conflict was silently accepted.'
    } catch { Assert-True ($_.Exception.ToString().Contains('Triple allocation already owned')) 'Wrong allocation conflict failure.' }
}
try { [void](New-Case 'MANTISANT' 'Triple-Tonpole'); throw 'Duplicate trio accepted.' }
catch { Assert-True ($_.Exception.ToString().Contains('incompatible or duplicated')) 'Wrong duplicate failure.' }
try { [void](New-Case 'native' 'Wall-Face'); throw 'Unsupported native Ice boss accepted.' }
catch { Assert-True ($_.Exception.ToString().Contains('Ice Palace plando boss is incompatible')) 'Wrong Ice compatibility failure.' }
$off=New-Case 'native' 'Mantis-Ant' 'Minotaur' $false 'vanilla'
Assert-True (Equal-Bytes $off[0][0..($original.Length-1)] $original) 'Boss-off behavior changed.'
Assert-True (-not $balance.GetMethod('process',$flags).Invoke([Activator]::CreateInstance($balance),@($original,$off[0],'off',$off[2],$off[1]))) 'Boss-off balance installed.'
$nonOpen=$original.Clone(); (MapValue 'TONPOLE').process($nonOpen,0x5A)
foreach($obj in (Read-Map $nonOpen 'getObjects' 361)) { Assert-True ($obj.getSpecies() -eq 0x5A) 'Vanilla-rando coupling changed.' }
$again=New-Case
Generate-Events $again[1] $again[2]
[void]$balance.GetMethod('process',$flags).Invoke([Activator]::CreateInstance($balance),@($original,$again[0],'hp',$again[2],$again[1]))
[void]$doors.GetMethod('process').Invoke([Activator]::CreateInstance($doors),@($again[0],$again[1]))
Assert-True (Equal-Bytes $r $again[0]) 'Triple generation not deterministic.'
$swap=New-Case 'MANTISANT' 'Mantis-Ant' 'Minotaur' $false 'swap'
Assert-True ((Read-Map $swap[0] 'getObjects' 361)[0].getSpecies() -eq 0x57 -and $redirect.GetMethod('hasForeignTriple').Invoke($null,@($swap[1]))) 'Swap mode lost planned independent encounters.'
foreach($target in @('MANTISANT','WALLFACE')) {
    $swap=New-Case $target 'Mantis-Ant' 'Minotaur' $false 'swap' $true
    Assert-True (-not $redirect.GetMethod('isNativeTriple').Invoke($null,@($swap[1])) -and $redirect.GetMethod('hasForeignTriple').Invoke($null,@($swap[1]))) 'Swap plando retained a second native trio.'
    # Ice is deliberately unplanned, so ordinary compatible swaps may follow
    # the initial displacement; only compatibility/single-instance is fixed.
    $iceSpecies=(Read-Map $swap[0] 'getObjects' 361)[0].getSpecies()
    Assert-True ($redirect.GetField('ICE_BOSSES').GetValue($null).Contains([byte]$iceSpecies) -and $iceSpecies -ne 0x80) 'Swap plando did not preserve safe native-Ice compatibility.'
}
Write-Output 'PASS: independent Ice draw, pools, native/foreign layout, transformations, exact-once completion, local HP machine, Undine return, coexistence, doors, and determinism.'
