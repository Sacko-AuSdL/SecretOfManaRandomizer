param(
    [string]$AssemblyPath = (Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe'),
    [string]$SourceRom = 'D:\views\tools\bots\Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc'
)
$ErrorActionPreference = 'Stop'
function Assert-True([bool]$Condition, [string]$Message) { if(-not $Condition) { throw $Message } }
function Equal-Bytes($A,$B) { return [Linq.Enumerable]::SequenceEqual([byte[]]$A,[byte[]]$B) }
function Contains-Bytes($Data,[byte[]]$Bytes) {
    for($i=0;$i -le $Data.Count-$Bytes.Length;$i++) {
        if(Equal-Bytes $Data[$i..($i+$Bytes.Length-1)] $Bytes) { return $true }
    }
    return $false
}
$assembly=[Reflection.Assembly]::LoadFrom((Resolve-Path $AssemblyPath).Path)
function Get-RepoType([string]$Name) { return $assembly.GetType('SoMRandomizer.'+$Name,$true) }
$commonType=Get-RepoType 'config.settings.CommonSettings'
$settingsType=Get-RepoType 'config.settings.OpenWorldSettings'
$contextType=Get-RepoType 'processing.common.RandoContext'
$swapsType=Get-RepoType 'processing.common.BossSwaps'
$mapsType=Get-RepoType 'processing.common.VanillaBossMaps'
$redirect=Get-RepoType 'processing.common.DreadSlimeBossArenaRedirect'
$mapUtil=Get-RepoType 'processing.common.VanillaMapUtil'
$eventUtil=Get-RepoType 'processing.common.VanillaEventUtil'
$namesType=Get-RepoType 'processing.hacks.common.util.NamesOfThings'
$flags=[Reflection.BindingFlags]'Instance,NonPublic'
[byte[]]$original=[IO.File]::ReadAllBytes((Resolve-Path $SourceRom).Path)
function MapValue([string]$Name) {
    if($Name -eq 'WATERMELON') { $Name='AEGRTOJNFSDGHOPALNIAPLEIAN' }
    return $mapsType.GetField($Name).GetValue($null)
}
function Read-Map($Rom,[string]$Method,[int]$Id) {
    return $mapUtil.GetMethod($Method,[Type[]]@([byte[]],[int])).Invoke($null,@($Rom,$Id))
}
function New-Case([int]$Seed=424242,[bool]$Coexist=$false,[string]$BossMode='random') {
    $settings=[Activator]::CreateInstance($settingsType,[object[]]@([Activator]::CreateInstance($commonType)))
    $settings.set('opBosses',$BossMode); $settings.set('crystalOrbWeaponBreaking','off')
    $context=[Activator]::CreateInstance($contextType)
    $context.randomFunctional=[Random]::new($Seed)
    $context.namesOfThings=[Activator]::CreateInstance($namesType,[object[]]@(,$original))
    $context.plandoSettings['P_doppelgangers']=[Collections.Generic.List[string]]::new([string[]]@('Doppelgangers'))
    $context.plandoSettings['P_tripleTonpole']=[Collections.Generic.List[string]]::new([string[]]@('Triple-Tonpole'))
    $context.plandoSettings['P_mantisAnt']=[Collections.Generic.List[string]]::new([string[]]@('Dread-Slime'))
    $context.plandoSettings['P_dreadSlime']=[Collections.Generic.List[string]]::new([string[]]@('Mantis-Ant'))
    $context.plandoSettings['P_limeSlime']=[Collections.Generic.List[string]]::new([string[]]@('Lime-Slime'))
    $context.plandoSettings['P_doomsWall']=[Collections.Generic.List[string]]::new([string[]]@("Doom's-Wall"))
    if($Coexist) {
        $context.plandoSettings['P_tropicallo']=[Collections.Generic.List[string]]::new([string[]]@('Lime-Slime'))
        $context.plandoSettings['P_limeSlime']=[Collections.Generic.List[string]]::new([string[]]@('Minotaur'))
        $context.plandoSettings['P_doomsWall']=[Collections.Generic.List[string]]::new([string[]]@('Mantis-Ant'))
    }
    [byte[]]$rom=[byte[]]::new(0x400000); [Array]::Copy($original,$rom,$original.Length)
    $context.originalRom=$original; $context.outputRom=$rom
    Assert-True ($swapsType.GetMethod('process',$flags).Invoke([Activator]::CreateInstance($swapsType),@($original,$rom,'dread-test',$settings,$context))) 'BossSwaps skipped.'
    return ,@($rom,$context,$settings)
}
function Generate-Events($Context,$Settings) {
    $Context.workingData.set('openWorldGoalShortName','manabeast')
    $Context.workingData.setBool('fastManaFort', $true)
    $Context.workingData.setBool('anyMagicExists', $true)
    $Context.workingData.set('boyClass','OGboy'); $Context.workingData.set('girlClass','OGgirl'); $Context.workingData.set('spriteClass','OGsprite')
    $Context.workingData.setInt('manaSeedsRequired',8)
    $elementType=Get-RepoType 'processing.ElementSwaps'
    $prefix=$elementType.GetField('ORBELEMENT_PREFIX').GetValue($null)
    $Context.workingData.setInt($prefix+35,0x81)
    foreach($name in @('PrizeEvents','OpenWorldSupportingEvents')) {
        $type=Get-RepoType ('processing.openworld.events.'+$name)
        try {
            [void]$type.GetMethod('process',$flags).Invoke([Activator]::CreateInstance($type),@($original,$Context.outputRom,'dread-events',$Settings,$Context))
        } catch { throw $_.Exception.ToString() }
    }
}

# Native fight contract, not guessed camera/player coordinates.
Assert-True (Equal-Bytes $original[0x83548..0x8354B] @(0xE8,0x21,0x18,0x80)) 'Native Dread Door $152 changed.'
Assert-True (Equal-Bytes $original[0x83300..0x83303] @(0xFA,0xC2,0xB6,0x80)) 'Native Fortress cleanup Door $C0 changed.'
$nativeHeader=Read-Map $original 'getHeader' 488
$nativeObject=(Read-Map $original 'getObjects' 488)[0]
Assert-True ($nativeObject.getSpecies() -eq 0x7C -and $nativeObject.getEvent() -eq 0x425 -and $nativeObject.getUnknownB7() -eq 8) 'Native Dread object contract changed.'
$nativePieces=Read-Map $original 'getMapPieceReference' 488
foreach($piece in @($nativePieces.bgPieces)+@($nativePieces.fgPieces)) {
    Assert-True ($piece.pieceIndex -eq 0x1B7) 'Native Dread geometry differs.'
    $decoded=$mapUtil.GetMethod('loadVanillaMapPiece').Invoke($null,@($original,[int]$piece.pieceIndex))
    Assert-True ($decoded.GetLength(0) -eq 24 -and $decoded.GetLength(1) -eq 24) 'Native Dread is not 24x24.'
}
# Empty map/sentinel pairs and unused piece IDs. No reachable native door is stolen.
$used=[Collections.Generic.HashSet[int]]::new()
for($id=0;$id -lt 512;$id++) {
    $p=Read-Map $original 'getMapPieceReference' $id
    foreach($piece in @($p.bgPieces)+@($p.fgPieces)) { [void]$used.Add($piece.pieceIndex) }
}
foreach($id in @(0x3D3,0x3D4)) { Assert-True (-not $used.Contains($id)) 'New piece ID already used.' }
foreach($id in @(0x1F6,0x1F7,0x1F8,0x1F9)) {
    $p=Read-Map $original 'getMapPieceReference' $id
    Assert-True ((Read-Map $original 'getObjects' $id).Count -eq 0 -and (Read-Map $original 'getTriggers' $id).Count -eq 0 -and $p.bgPieces.Count -eq 0 -and $p.fgPieces.Count -eq 0) 'Reserved map is not empty.'
    for($door=0;$door -lt 0x400;$door++) {
        $offset=0x83000+4*$door
        Assert-True (($original[$offset]+(($original[$offset+1]-band 1)-shl 8)) -ne $id) 'Reserved map has a native entrance.'
    }
}
foreach($b in $original[0x8FEE0..0x8FF17]) { Assert-True ($b -eq 0xFF) 'New allocation is not padding.' }
foreach($method in @('getObjectOffset','getPiecePlacementOffset','getTriggerOffset')) {
    for($id=0;$id -lt 511;$id++) {
        $start=Read-Map $original $method $id; $end=Read-Map $original $method ($id+1)
        Assert-True (-not ($start -lt 0x8FF18 -and $end -gt 0x8FEE0)) 'New allocation overlaps a native map.'
    }
}
$safe=@('MANTISANT','WALLFACE','TROPICALLO','JABBER','MECHRIDER2','WATERMELON','MECHRIDER3','FROSTGIGAS','FIREGIGAS')
foreach($name in $safe) {
    Assert-True ($redirect.GetMethod('getOpenWorldRandomPool').Invoke($null,@((MapValue $name))).Contains([byte]0x7C)) "$name rejects Dread."
}
Assert-True (-not $redirect.GetMethod('getOpenWorldRandomPool').Invoke($null,@((MapValue 'BLUESPIKE'))).Contains([byte]0x7C)) 'Unsafe Blue Spike admits Dread.'
$fortressPool=$redirect.GetMethod('getOpenWorldRandomPool').Invoke($null,@((MapValue 'DREADSLIME')))
foreach($excluded in @(0x58,0x61,0x6A,0x70,0x71,0x7E,0x7F,0x80)) { Assert-True (-not $fortressPool.Contains([byte]$excluded)) 'Unsafe Fortress replacement admitted.' }

$case=New-Case; [byte[]]$rom=$case[0]; $context=$case[1]
. (Join-Path $PSScriptRoot 'support\AssertSlimeDialogueReset.ps1')
Assert-SlimeDialogueReset $rom $original
Assert-True ($context.generatedMaps.Count -eq 0 -and $context.replacementMapPieces.Count -eq 2) 'Unexpected destructive map replacement/piece allocation.'
foreach($map in @(0x1F6,0x1F8)) {
    $obj=(Read-Map $rom 'getObjects' $map)[0]; $header=Read-Map $rom 'getHeader' $map
    Assert-True ((Read-Map $rom 'getTriggers' $map).Count -eq 0 -and -not $header.getWalkonEventEnabled() -and -not $header.getSpecialEventEnabled()) 'Generated arena retained progression triggers.'
    if($map -eq 0x1F6) {
        Assert-True ($header.getMode7Enabled() -and $header.getPaletteSet() -eq 0x2F -and $header.getDisplaySetting() -eq 0x0E) 'Dread lost Mode-7 display.'
        Assert-True ($obj.getSpecies() -eq 0x7C -and $obj.getEvent() -eq 0x112 -and $obj.getUnknownB7() -eq 8 -and $obj.getXpos() -eq 12 -and $obj.getYpos() -eq 12) 'Dread lost native actor/slot ownership.'
        $p=Read-Map $rom 'getMapPieceReference' $map
        Assert-True ($p.bgPieces[0].pieceIndex -eq 0x1B7 -and $p.fgPieces[0].pieceIndex -eq 0x1B7 -and -not $context.replacementMapPieces.ContainsKey(0x1B7)) 'Dread native collision geometry changed.'
    } else {
        Assert-True (-not $header.getMode7Enabled() -and $obj.getSpecies() -eq 0x57 -and $obj.getEvent() -eq 0x425) 'Fortress boss retained donor progression/Mode-7.'
    }
}
Assert-True (Equal-Bytes $rom[0x8FF00..0x8FF0B] @(0xFE,0,0x0F,0xB7,1,0,0xFF,0,0x0F,0xB7,1,0)) 'Dread references wrong.'
Assert-True (Equal-Bytes $rom[0x8FF0C..0x8FF17] @(0xFE,0,0x0F,0xD3,1,1,0xFF,0,0x0F,0xD4,1,1)) 'Fortress references wrong.'
$importer=Get-RepoType 'processing.common.GeneratedMapUtil'
$donor=$importer.GetMethod('importVanillaBossArena').Invoke($null,@($context,[byte]0x57))
$compressor=Get-RepoType 'processing.common.SomMapCompressor'
foreach($layer in @(@(0x3D3,$donor.layer1Data),@(0x3D4,$donor.layer2Data))) {
    $encoded=$compressor.GetMethod('EncodeMap',[Type[]]@([byte[,]])).Invoke($null,[object[]]@(,$layer[1]))
    Assert-True (Equal-Bytes $encoded $context.replacementMapPieces[[int]$layer[0]]) 'Fortress geometry differs from its filtered native donor.'
}
Assert-True (Equal-Bytes $rom[0x28455..0x288FE] $original[0x28455..0x288FE]) 'Dread redirect changed shared slime AI/MP.'
foreach($map in @(488,489,260)) {
    foreach($method in @('getObjectOffset','getPiecePlacementOffset','getTriggerOffset')) {
        $start=Read-Map $original $method $map; $end=Read-Map $original $method ($map+1)
        if($end -gt $start) { Assert-True (Equal-Bytes $original[$start..($end-1)] $rom[$start..($end-1)]) 'Native arena overwritten.' }
    }
}
foreach($pair in @(@(0x08D,0x1F6,16,12,0x80),@(0x152,0x1F8,16,18,0))) {
    $door=$context.replacementDoors[[int]$pair[0]]
    Assert-True ($door.getTargetMap() -eq $pair[1] -and $door.getXpos() -eq $pair[2] -and $door.getYpos() -eq $pair[3] -and $door.getTransitionType() -eq $pair[4]) 'Entry/camera contract changed.'
}
Generate-Events $context $case[2]
$baseline=[Activator]::CreateInstance($contextType); $baseline.originalRom=$original; $baseline.outputRom=$original.Clone()
Generate-Events $baseline $case[2]
Assert-True (Equal-Bytes $context.replacementEvents[0x425] $baseline.replacementEvents[0x425]) 'Fortress flag/prize/autosave/music event changed.'
Assert-True (Equal-Bytes $context.replacementEvents[0x424] @(0x29,0x4E,0x30,0x0B,2,0x19,0x52,0x17,4,0)) 'Fortress entry changed beyond ordinary death type.'
Assert-True (Contains-Bytes $context.replacementEvents[0x425] @(0x29,0x4E,0x30,0x0B,2,0x27,0x31,0x18,0xC0)) 'Fortress cleanup/music ordering changed.'
Assert-True (Contains-Bytes $context.replacementEvents[0x425] @(0x18,0xC0,0x14,0x2C,0)) 'Fortress post-prize autosave/continuation changed.'
Assert-True (Contains-Bytes $context.replacementEvents[0x10C] @(0x18,0x8D,0x30,0x0B,0x0F)) 'Foreign Dread lacks special death type.'
$expected=[Collections.Generic.List[byte]]::new([byte[]]$baseline.replacementEvents[0x112])
$at=-1
for($i=0;$i+1 -lt $expected.Count;$i++) { if($expected[$i] -eq 0x25 -and $expected[$i+1] -le 7) { $at=$i; break } }
Assert-True ($at -ge 0) 'Slot has no orb boundary.'
$expected.InsertRange($at,[byte[]]@(0x30,0x0B,2,0x19,0x0B))
Assert-True (Equal-Bytes $context.replacementEvents[0x112] $expected) 'Foreign Dread changed slot rewards/flags/return beyond cleanup.'
$limeRedirect=Get-RepoType 'processing.common.LimeSlimeBossArenaRedirect'
$sharedTransition=$limeRedirect.GetMethod('getNeutralRewardStagingTransition',
    [Reflection.BindingFlags]'Static,NonPublic').Invoke($null,@())
Assert-True (Equal-Bytes $sharedTransition @(0x30,0x0B,2,0x19,0x0B)) 'Dread/Lime shared staging transition diverged.'
# Ordinary events remain byte-identical, apart from the one redirected slot.
foreach($eventId in @(0x233,0x1BF,0x544,0x425)) {
    Assert-True ($context.replacementEvents.ContainsKey($eventId) -eq $baseline.replacementEvents.ContainsKey($eventId)) ('Unrelated event replacement changed: '+$eventId)
    if($baseline.replacementEvents.ContainsKey($eventId)) {
        Assert-True (Equal-Bytes $context.replacementEvents[$eventId] $baseline.replacementEvents[$eventId]) ('Unrelated/native reward event changed: '+$eventId)
    }
}
Assert-True (-not (Contains-Bytes $context.replacementEvents[0x112] @(0x29,0x4E)) -and -not (Contains-Bytes $context.replacementEvents[0x112] @(0x18,0xC0)) -and -not (Contains-Bytes $context.replacementEvents[0x112] @(0x14,0x2C))) 'Foreign Dread invokes Fortress progression.'
# All admitted entry events must have the exact door expected by the adapter.
$entries=@(@('WALLFACE',0x16D,0x032),@('TROPICALLO',0x1BE,0x051),@('JABBER',0x084,0x0A0),@('MECHRIDER2',0x52E,0x35D),@('WATERMELON',0x4B3,0x358),@('MECHRIDER3',0x4A3,0x3F6),@('FROSTGIGAS',0x66B,0x2CA),@('FIREGIGAS',0x236,0x14B))
foreach($entry in $entries) {
    Assert-True (Contains-Bytes $baseline.replacementEvents[[int]$entry[1]] ([byte[]]@((0x18+($entry[2]-shr 8)),($entry[2]-band 255)))) ('Wrong entry event for '+$entry[0])
}
# Exercise the real entry/death events for EVERY admitted foreign slot, not
# merely a synthetic Mantis event. Each must retain its own cleanup/return tail.
foreach($name in $safe) {
    $slot=MapValue $name
    $deathId=[uint16](Read-Map $original 'getObjects' $slot.originalMapNum)[$slot.originalObjNum].getEvent()
    $c=[Activator]::CreateInstance($contextType); $c.originalRom=$original; $c.outputRom=[byte[]]::new(0x400000)
    [Array]::Copy($original,$c.outputRom,$original.Length)
    $redirect.GetMethod('createDreadInForeignSlot').Invoke($null,@($c.outputRom,$c,$slot,$deathId))
    Generate-Events $c $case[2]
    Assert-True (Contains-Bytes $c.replacementEvents[[int]$deathId] @(0x30,0x0B,2,0x19,0x0B)) ('Missing shared cleanup for '+$name)
}
$doorReplacer=Get-RepoType 'processing.hacks.common.util.DoorReplacer'
[void]$doorReplacer.GetMethod('process').Invoke([Activator]::CreateInstance($doorReplacer),@($rom,$context))
Assert-True (Equal-Bytes $rom[0x83234..0x83237] @(0xF6,0x21,0x18,0x80)) 'Final foreign Dread door bytes changed.'
Assert-True (Equal-Bytes $rom[0x83548..0x8354B] @(0xF8,0x21,0x24,0)) 'Final Fortress donor door bytes changed.'
Assert-True (Equal-Bytes $rom[0x83300..0x83303] $original[0x83300..0x83303]) 'Fortress cleanup door overwritten.'
$again=New-Case
[void]$doorReplacer.GetMethod('process').Invoke([Activator]::CreateInstance($doorReplacer),@($again[0],$again[1]))
Assert-True (Equal-Bytes $rom $again[0]) 'Dread generation is not deterministic.'
$swap=New-Case 123 $false 'swap'
Assert-True ((Read-Map $swap[0] 'getObjects' 0x1F6)[0].getSpecies() -eq 0x7C -and (Read-Map $swap[0] 'getObjects' 0x1F8)[0].getSpecies() -eq 0x57) 'Open World swap mode lost either redirect.'
$bypassSettings=[Activator]::CreateInstance($settingsType,[object[]]@([Activator]::CreateInstance($commonType)))
$bypassSettings.set('opBosses','vanilla')
$bypassContext=[Activator]::CreateInstance($contextType)
$bypassContext.namesOfThings=[Activator]::CreateInstance($namesType,[object[]]@(,$original))
[byte[]]$bypassRom=$original.Clone()
Assert-True (-not $swapsType.GetMethod('process',$flags).Invoke([Activator]::CreateInstance($swapsType),@($original,$bypassRom,'bypass',$bypassSettings,$bypassContext))) 'Vanilla bosses no longer bypass.'
Assert-True (Equal-Bytes $original $bypassRom) 'Boss-randomization Off changed ROM bytes.'
# Guard occupied new padding rather than silently clobbering another processor.
$conflict=New-Case; $conflict[0][0x8FEE0]=0
try {
    $redirect.GetMethod('createDreadInForeignSlot').Invoke($null,@($conflict[0],$conflict[1],(MapValue 'MANTISANT'),[uint16]0x112))
    throw 'Missing allocation conflict guard.'
} catch { Assert-True ($_.Exception.ToString().Contains('Dread allocation already owned')) 'Wrong conflict failure.' }
# Real processor coexistence: Doom, Lime, Shade, the shared blank stage, and Nesoberi.
$coexist=New-Case 777 $true
Generate-Events $coexist[1] $coexist[2]
[byte[]]$dreadBefore=$coexist[0][0x8FEE0..0x8FF17]
[byte[]]$limeBefore=$coexist[0][0x88FCA..0x88FED]
$coexist[1].randomCosmetic=[Random]::new(777)
for($i=0;$i -lt 3;$i++) { $coexist[1].workingData.set('nesoPrize'+$i,'sword'); $coexist[1].workingData.set('nesoHint'+$i,'near Potos') }
$neso=Get-RepoType 'processing.hacks.openworld.Nesoberi'
[void]$neso.GetMethod('process',$flags).Invoke([Activator]::CreateInstance($neso),@($original,$coexist[0],'coexist',$coexist[2],$coexist[1]))
Assert-True (Equal-Bytes $coexist[0][0x8FEE0..0x8FF17] $dreadBefore) 'Nesoberi overwrote Dread.'
Assert-True (Equal-Bytes $coexist[0][0x88FCA..0x88FED] $limeBefore) 'Shared stage or Nesoberi overwrote Lime/Shade.'
Assert-True (Equal-Bytes $coexist[0][0x88FBE..0x88FC9] @(0xE0,1,0x2F,9,0x30,9,0x8B,1,0x2B,9,0x2B,9)) 'Nesoberi contract changed.'
Assert-True ((Read-Map $coexist[0] 'getObjects' 0x1FE)[0].getEvent() -eq 0x553) 'Doom redirect changed.'
# Optional minimum-level logic follows the logical slot, not the physical donor.
$case[2].set('opMinLevel','yes')
$minmax=Get-RepoType 'processing.hacks.openworld.MinMaxLevel'
[void]$minmax.GetMethod('process',$flags).Invoke([Activator]::CreateInstance($minmax),@($original,$rom,'min-level',$case[2],$context))
$minTable=$context.workingData.getInt('enemyMinLevelOffset')-0xC00000
Assert-True ($rom[$minTable+0x1F6] -eq $rom[$minTable+260] -and $rom[$minTable+0x1F8] -eq $rom[$minTable+488] -and $rom[$minTable+488] -gt 0) 'Redirected map minimum levels no longer match slot ownership.'
Write-Output 'PASS: Dread native contract, both redirects, Fortress event preservation, cleanup, exclusions, ownership/coexistence, entry events, and determinism.'
