param(
    [string]$AssemblyPath = (Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe'),
    [string]$SourceRom = 'D:\views\tools\bots\Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc'
)

$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if(-not $Condition) { throw $Message }
}

function Contains-Sequence([System.Collections.IList]$Data, [byte[]]$Sequence) {
    for($i = 0; $i -le $Data.Count - $Sequence.Length; $i++) {
        $matches = $true
        for($j = 0; $j -lt $Sequence.Length; $j++) {
            if($Data[$i + $j] -ne $Sequence[$j]) { $matches = $false; break }
        }
        if($matches) { return $true }
    }
    return $false
}

$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path $AssemblyPath).Path)
$commonType = $assembly.GetType('SoMRandomizer.config.settings.CommonSettings', $true)
$settingsType = $assembly.GetType('SoMRandomizer.config.settings.OpenWorldSettings', $true)
$contextType = $assembly.GetType('SoMRandomizer.processing.common.RandoContext', $true)
$bossSwapsType = $assembly.GetType('SoMRandomizer.processing.common.BossSwaps', $true)
$bossMapsType = $assembly.GetType('SoMRandomizer.processing.common.VanillaBossMaps', $true)
$redirectType = $assembly.GetType('SoMRandomizer.processing.common.LimeSlimeBossArenaRedirect', $true)
$mapUtilType = $assembly.GetType('SoMRandomizer.processing.common.VanillaMapUtil', $true)
$mapCompressorType = $assembly.GetType('SoMRandomizer.processing.common.SomMapCompressor', $true)
$namesType = $assembly.GetType('SoMRandomizer.processing.hacks.common.util.NamesOfThings', $true)
$plandoType = $assembly.GetType('SoMRandomizer.processing.openworld.PlandoProperties', $true)
$eventScriptType = $assembly.GetType('SoMRandomizer.processing.common.structure.EventScript', $true)
$doorReplacerType = $assembly.GetType('SoMRandomizer.processing.hacks.common.util.DoorReplacer', $true)
$doorUtilType = $assembly.GetType('SoMRandomizer.processing.common.VanillaDoorUtil', $true)
$nesoberiType = $assembly.GetType('SoMRandomizer.processing.hacks.openworld.Nesoberi', $true)

[byte[]]$originalRom = [IO.File]::ReadAllBytes((Resolve-Path $SourceRom).Path)
$process = $bossSwapsType.GetMethod('process', [Reflection.BindingFlags]'Instance,NonPublic')
$mantis = $bossMapsType.GetField('MANTISANT').GetValue($null)
$lime = $bossMapsType.GetField('LIMESLIME').GetValue($null)
$blueSpike = $bossMapsType.GetField('BLUESPIKE').GetValue($null)

function Invoke-ForcedLimeCross([int]$Seed) {
    $common = [Activator]::CreateInstance($commonType)
    $settings = [Activator]::CreateInstance($settingsType, [object[]]@($common))
    $settings.set('opBosses', 'random')
    $context = [Activator]::CreateInstance($contextType)
    $context.randomFunctional = [Random]::new($Seed)
    $context.namesOfThings = [Activator]::CreateInstance($namesType, [object[]]@(,$originalRom))
    $context.plandoSettings[$plandoType.GetField('KEY_BOSS_MANTISANT').GetValue($null)] =
        [Collections.Generic.List[string]]::new([string[]]@('Lime-Slime'))
    $context.plandoSettings[$plandoType.GetField('KEY_BOSS_LIMESLIME').GetValue($null)] =
        [Collections.Generic.List[string]]::new([string[]]@('Mantis-Ant'))

    [byte[]]$outputRom = [byte[]]::new(0x400000)
    [Array]::Copy($originalRom, $outputRom, $originalRom.Length)
    $context.originalRom = $originalRom
    $context.outputRom = $outputRom
    [object[]]$args = @($originalRom, $outputRom, "lime-test-$Seed", $settings, $context)
    Assert-True ([bool]$process.Invoke([Activator]::CreateInstance($bossSwapsType), $args)) `
        'BossSwaps unexpectedly skipped.'
    return ,@($outputRom, $context, $settings)
}

$limeMap = $redirectType.GetField('LIME_IN_FOREIGN_SLOT_MAP_ID').GetRawConstantValue()
$stagingMap = $redirectType.GetField('LIME_REWARD_STAGING_MAP_ID').GetRawConstantValue()
$shadeMap = $redirectType.GetField('FOREIGN_IN_SHADE_SLOT_MAP_ID').GetRawConstantValue()
$stagingDoor = $redirectType.GetField('LIME_REWARD_STAGING_DOOR').GetRawConstantValue()
$limeBg = $redirectType.GetField('LIME_BG_PIECE_ID').GetRawConstantValue()
$limeFg = $redirectType.GetField('LIME_FG_PIECE_ID').GetRawConstantValue()
$shadeBg = $redirectType.GetField('SHADE_BG_PIECE_ID').GetRawConstantValue()
$shadeFg = $redirectType.GetField('SHADE_FG_PIECE_ID').GetRawConstantValue()
$stagingObjectOffset = $redirectType.GetField('LIME_REWARD_STAGING_OBJECT_DATA_OFFSET').GetRawConstantValue()
$limePieceOffset = $redirectType.GetField('LIME_PIECE_DATA_OFFSET').GetRawConstantValue()
$stagingPieceOffset = $redirectType.GetField('LIME_REWARD_STAGING_PIECE_DATA_OFFSET').GetRawConstantValue()
$blankPiece = $redirectType.GetField('LIME_REWARD_STAGING_BLANK_PIECE_ID').GetRawConstantValue()
$shadePieceOffset = $redirectType.GetField('SHADE_PIECE_DATA_OFFSET').GetRawConstantValue()
$limeTriggerOffset = $redirectType.GetField('LIME_TRIGGER_DATA_OFFSET').GetRawConstantValue()
$shadeTriggerOffset = $redirectType.GetField('SHADE_TRIGGER_DATA_OFFSET').GetRawConstantValue()
Assert-True ($limeMap -eq 0x1FA -and $stagingMap -eq 0x1FB -and $shadeMap -eq 0x1FC) `
    'Unexpected generated Lime redirect/staging map IDs.'
Assert-True ($stagingDoor -eq 0x10B -and $stagingObjectOffset -eq 0x8E090) `
    'Unexpected neutral reward staging allocation.'
Assert-True ($limePieceOffset -eq 0x88FCA -and $stagingPieceOffset -eq 0x88FD6 `
    -and $shadePieceOffset -eq 0x88FE2 `
    -and $limeTriggerOffset -eq 0x88FEE -and $shadeTriggerOffset -eq 0x88FEE) `
    'Generated Lime/Shade bank-8 allocation changed.'
Assert-True (0x88FCA -le $limePieceOffset `
    -and ($limePieceOffset + 12) -le $stagingPieceOffset `
    -and ($stagingPieceOffset + 12) -le $shadePieceOffset `
    -and ($shadePieceOffset + 12) -le $limeTriggerOffset) `
    'Generated Lime/Shade spans overlap the Nesoberi range or each other.'

# The effective Open World pools are deliberately narrower than direct arena
# compatibility.  Lime is admitted only where both entry and exit adapters are proven.
$getPool = $redirectType.GetMethod('getOpenWorldRandomPool')
[byte[]]$mantisPool = $getPool.Invoke($null, @($mantis))
[byte[]]$bluePool = $getPool.Invoke($null, @($blueSpike))
[byte[]]$shadePool = $getPool.Invoke($null, @($lime))
Assert-True ($mantisPool.Contains([byte]0x6A)) 'Mantis slot does not admit redirected Lime Slime.'
Assert-True (-not $bluePool.Contains([byte]0x6A)) 'Unsafe Blue Spike slot admits Lime Slime.'
foreach($excluded in @(0x58,0x61,0x70,0x71,0x7C,0x7E,0x7F,0x80)) {
    Assert-True (-not $shadePool.Contains([byte]$excluded)) `
        ('Excluded boss {0:X2} entered the Shade redirect pool.' -f $excluded)
}
Assert-True ($shadePool.Contains([byte]0x57) -and $shadePool.Contains([byte]0x6A)) `
    'Shade pool lost Mantis Ant or native Lime Slime.'

# Prove the reserved maps and pieces are unused by every vanilla full map/door.
$usedPieces = [Collections.Generic.HashSet[int]]::new()
for($mapId = 0; $mapId -lt 512; $mapId++) {
    $pieces = $mapUtilType.GetMethod('getMapPieceReference', [Type[]]@([byte[]], [int])).Invoke(
        $null, [object[]]@($originalRom, $mapId))
    foreach($piece in $pieces.bgPieces) { [void]$usedPieces.Add($piece.pieceIndex) }
    foreach($piece in $pieces.fgPieces) { [void]$usedPieces.Add($piece.pieceIndex) }
}
foreach($pieceId in @($limeBg,$limeFg,$shadeBg,$shadeFg)) {
    Assert-True (-not $usedPieces.Contains($pieceId)) ('Reserved piece {0:X3} is used by vanilla.' -f $pieceId)
}
foreach($mapId in @($limeMap,($limeMap+1),$shadeMap,($shadeMap+1))) {
    $objects = $mapUtilType.GetMethod('getObjects', [Type[]]@([byte[]], [int])).Invoke($null,@($originalRom,$mapId))
    $triggers = $mapUtilType.GetMethod('getTriggers', [Type[]]@([byte[]], [int])).Invoke($null,@($originalRom,$mapId))
    $pieces = $mapUtilType.GetMethod('getMapPieceReference', [Type[]]@([byte[]], [int])).Invoke($null,@($originalRom,$mapId))
    Assert-True ($objects.Count -eq 0 -and $triggers.Count -eq 0 `
        -and $pieces.bgPieces.Count -eq 0 -and $pieces.fgPieces.Count -eq 0) `
        ('Reserved map {0:X3} is not empty in vanilla.' -f $mapId)
    for($doorId = 0; $doorId -lt 0x400; $doorId++) {
        $offset = 0x83000 + $doorId * 4
        $target = [int]$originalRom[$offset] + (([int]$originalRom[$offset + 1] -band 1) -shl 8)
        Assert-True ($target -ne $mapId) ('Vanilla door {0:X3} targets reserved map {1:X3}.' -f $doorId,$mapId)
    }
}

# Door $10B is a dead vanilla descriptor: no event command and no map trigger
# dispatches it.  This proves the staging redirect cannot steal a reachable
# vanilla transition.  Door triggers encode $800 + door ID.
$doorCommand = [byte](0x18 + ($stagingDoor -shr 8))
$doorLow = [byte]($stagingDoor -band 0xFF)
for($eventId = 0; $eventId -lt 0x800; $eventId++) {
    $event = $assembly.GetType('SoMRandomizer.processing.common.VanillaEventUtil', $true).GetMethod(
        'getVanillaEvent').Invoke($null,@($originalRom,$eventId))
    Assert-True (-not (Contains-Sequence $event ([byte[]]@($doorCommand,$doorLow)))) `
        ('Vanilla event {0:X3} references reserved staging Door $10B.' -f $eventId)
}
for($mapId = 0; $mapId -lt 512; $mapId++) {
    $triggers = $mapUtilType.GetMethod('getTriggers', [Type[]]@([byte[]], [int])).Invoke(
        $null,@($originalRom,$mapId))
    Assert-True (-not $triggers.Contains([uint16](0x800 + $stagingDoor))) `
        ('Vanilla map {0:X3} references reserved staging Door $10B.' -f $mapId)
}

$result = Invoke-ForcedLimeCross 424242
[byte[]]$rom = $result[0]
$context = $result[1]
Assert-True ([Linq.Enumerable]::SequenceEqual([byte[]]$originalRom[0x88FB6..0x88FC9],
    [byte[]]$rom[0x88FB6..0x88FC9]) -and [Linq.Enumerable]::SequenceEqual(
    [byte[]]$originalRom[0x88FEE..0x88FFF], [byte[]]$rom[0x88FEE..0x88FFF])) `
    'Generated map references wrote outside their audited allocation.'
Assert-True ($context.generatedMaps.Count -eq 0) 'Lime redirects entered the destructive FullMapReplacer path.'
Assert-True ($context.replacementMapPieces.Count -eq 4) 'Lime cross generated an unexpected piece count.'
foreach($pieceId in @($limeBg,$limeFg,$shadeBg,$shadeFg)) {
    Assert-True ($context.replacementMapPieces.ContainsKey($pieceId)) ('Missing generated piece {0:X3}.' -f $pieceId)
}
[Array]$limeBgDecoded = $mapCompressorType.GetMethod('DecodeMap').Invoke(
    $null, [object[]]@(,[byte[]]$context.replacementMapPieces[$limeBg].ToArray()))
[Array]$limeFgDecoded = $mapCompressorType.GetMethod('DecodeMap').Invoke(
    $null, [object[]]@(,[byte[]]$context.replacementMapPieces[$limeFg].ToArray()))
Assert-True ($limeBgDecoded.GetLength(0) -eq 24 -and $limeBgDecoded.GetLength(1) -eq 24 `
    -and $limeFgDecoded.GetLength(0) -eq 24 -and $limeFgDecoded.GetLength(1) -eq 24) `
    'Generated Lime map pieces are not 24x24.'

# Both native source maps remain byte-identical; only their slot entry doors
# are redirected to private generated copies.
foreach($nativeMap in @([int]$mantis.originalMapNum,[int]$lime.originalMapNum)) {
    foreach($offsetMethod in @('getObjectOffset','getPiecePlacementOffset','getTriggerOffset')) {
        $method = $mapUtilType.GetMethod($offsetMethod, [Type[]]@([byte[]], [int]))
        $start = [int]$method.Invoke($null,@($originalRom,$nativeMap))
        $end = [int]$method.Invoke($null,@($originalRom,($nativeMap + 1)))
        if($end -gt $start) {
            Assert-True ([Linq.Enumerable]::SequenceEqual(
                [byte[]]$originalRom[$start..($end-1)], [byte[]]$rom[$start..($end-1)])) `
                ('Native map {0:X3} {1} data was overwritten.' -f $nativeMap,$offsetMethod)
        }
    }
}

# Direction A: Mantis entrance -> native Lime geometry/species -> Mantis death event.
$limeHeader = $mapUtilType.GetMethod('getHeader', [Type[]]@([byte[]], [int])).Invoke($null,@($rom,$limeMap))
$limeObjects = $mapUtilType.GetMethod('getObjects', [Type[]]@([byte[]], [int])).Invoke($null,@($rom,$limeMap))
$limeTriggers = $mapUtilType.GetMethod('getTriggers', [Type[]]@([byte[]], [int])).Invoke($null,@($rom,$limeMap))
Assert-True ($limeHeader.getMode7Enabled() -and $limeHeader.getPaletteSet() -eq 0x2F `
    -and $limeHeader.getDisplaySetting() -eq 0x0E) 'Redirected Lime arena lost native Mode-7 metadata.'
Assert-True ($limeObjects.Count -eq 1 -and $limeObjects[0].getSpecies() -eq 0x6A `
    -and $limeObjects[0].getEvent() -eq 0x112) 'Redirected Lime object lost Mantis slot ownership.'
Assert-True ($limeObjects[0].getUnknownB7() -eq 8) 'Redirected Lime object lost its native high event/object bits.'
Assert-True ($limeTriggers.Count -eq 0) 'Redirected Lime arena retained native/foreign triggers.'

# Redirected Lime leaves Mode-7 for a private regular-display map with real
# blank pieces on both layers. It owns no objects, triggers, or walk-on event;
# the still-running
# death event cannot yield control or execute Dread/Shade progression there.
$stagingHeader = $mapUtilType.GetMethod('getHeader', [Type[]]@([byte[]], [int])).Invoke(
    $null,@($rom,$stagingMap))
$stagingObjects = $mapUtilType.GetMethod('getObjects', [Type[]]@([byte[]], [int])).Invoke(
    $null,@($rom,$stagingMap))
$stagingPieces = $mapUtilType.GetMethod('getMapPieceReference', [Type[]]@([byte[]], [int])).Invoke(
    $null,@($rom,$stagingMap))
$stagingTriggers = $mapUtilType.GetMethod('getTriggers', [Type[]]@([byte[]], [int])).Invoke(
    $null,@($rom,$stagingMap))
Assert-True (-not $stagingHeader.getMode7Enabled() `
    -and $stagingHeader.getDisplaySetting() -eq 0x00 `
    -and -not $stagingHeader.getWalkonEventEnabled() `
    -and -not $stagingHeader.getSpecialEventEnabled()) `
    'Neutral Lime reward stage does not restore inert ordinary display state.'
Assert-True ($stagingObjects.Count -eq 0 -and $stagingTriggers.Count -eq 0 `
    -and $stagingPieces.bgPieces.Count -eq 1 -and $stagingPieces.fgPieces.Count -eq 1 `
    -and $blankPiece -eq 0x0E9 `
    -and $stagingPieces.bgPieces[0].pieceIndex -eq $blankPiece `
    -and $stagingPieces.fgPieces[0].pieceIndex -eq $blankPiece) `
    'Neutral Lime reward stage must contain only its two real blank layers.'
Assert-True ([Linq.Enumerable]::SequenceEqual([byte[]]$rom[0x8E090..0x8E097],
    [byte[]]@(0x15,0x2D,0x95,0,0,0,0,0xFF))) 'Neutral stage lost compatible regular-display settings.'
[Array]$blankDecoded = $mapUtilType.GetMethod('loadVanillaMapPiece').Invoke($null,@($rom,[int]$blankPiece))
Assert-True ($blankDecoded.GetLength(0) -eq 120 -and $blankDecoded.GetLength(1) -eq 120) `
    'Reused blank piece dimensions changed.'
foreach($tile in $blankDecoded) { Assert-True ($tile -eq 0) 'Staging piece contains recognizable geometry.' }
Assert-True (-not $context.replacementMapPieces.ContainsKey($blankPiece)) 'Existing blank piece was overwritten.'
$tilesetUtil = $assembly.GetType('SoMRandomizer.processing.common.VanillaTilesetUtil', $true)
$compressedTileset = $tilesetUtil.GetMethod('getCompressedVanillaTileset16').Invoke($null,@($rom,0x15))
$tileset = $tilesetUtil.GetMethod('DecodeTileset16').Invoke($null,[object[]]@(,$compressedTileset))
foreach($tileIndex in @(0,192)) {
    foreach($subtile in $tileset.Tiles[$tileIndex].Tiles) {
        Assert-True ($subtile.ToBinary() -eq 0x035F) 'Blank layer tile maps to visible dungeon graphics.'
    }
}
Assert-True ($rom[0x80107] -eq 0 -and $rom[0x80108] -eq 0) 'Regular display backdrop is not black.'

# Direction B: Shade entrance -> native Mantis geometry/species -> Shade death event.
$shadeHeader = $mapUtilType.GetMethod('getHeader', [Type[]]@([byte[]], [int])).Invoke($null,@($rom,$shadeMap))
$shadeObjects = $mapUtilType.GetMethod('getObjects', [Type[]]@([byte[]], [int])).Invoke($null,@($rom,$shadeMap))
Assert-True (-not $shadeHeader.getMode7Enabled()) 'Mantis replacement was forced into Mode-7 rendering.'
Assert-True ($shadeObjects.Count -eq 1 -and $shadeObjects[0].getSpecies() -eq 0x57 `
    -and $shadeObjects[0].getEvent() -eq 0x544) 'Shade replacement retained Mantis native progression.'

foreach($pair in @(@(0x08D,$limeMap,16,12,0x80),@($stagingDoor,$stagingMap,16,16,0x80),@(0x03A,$shadeMap,16,18,0x00))) {
    $door = $context.replacementDoors[[int]$pair[0]]
    Assert-True ($null -ne $door -and $door.getTargetMap() -eq $pair[1] `
        -and $door.getXpos() -eq $pair[2] -and $door.getYpos() -eq $pair[3] `
        -and $door.getTransitionType() -eq $pair[4]) ('Redirected door {0:X3} is incorrect.' -f $pair[0])
}

# The generated Lime target changes only the native door's map ID.  This exact
# entry contract is what initializes the native slime camera/Mode-7 coordinate
# frame: FA 21 18 80 = map 1FA, x16, y12, layer1, transition 80.
$nativeLimeDoorOffset = 0x83000 + 0x03A * 4
Assert-True ([Linq.Enumerable]::SequenceEqual(
    [byte[]]$originalRom[$nativeLimeDoorOffset..($nativeLimeDoorOffset + 3)],
    [byte[]]@(0xE9,0x21,0x18,0x80))) 'Native Lime entry door contract changed.'

# Serialize doors and prove the final ROM—not only context structures—contains them.
$doorReplacerType.GetMethod('process').Invoke([Activator]::CreateInstance($doorReplacerType), @($rom,$context))
foreach($pair in @(@(0x08D,$limeMap,0x80),@($stagingDoor,$stagingMap,0x80),@(0x03A,$shadeMap,0x00))) {
    $offset = 0x83000 + [int]$pair[0] * 4
    $target = [int]$rom[$offset] + (([int]$rom[$offset + 1] -band 1) -shl 8)
    Assert-True ($target -eq $pair[1] -and $rom[$offset + 3] -eq $pair[2]) `
        ('Final door {0:X3} does not preserve its required transition.' -f $pair[0])
}
$mantisDoorOffset = 0x83000 + 0x08D * 4
Assert-True ([Linq.Enumerable]::SequenceEqual(
    [byte[]]$rom[$mantisDoorOffset..($mantisDoorOffset + 3)],
    [byte[]]@(0xFA,0x21,0x18,0x80))) 'Final foreign-slot Lime door is not FA 21 18 80.'
$stagingDoorOffset = 0x83000 + $stagingDoor * 4
Assert-True ([Linq.Enumerable]::SequenceEqual(
    [byte[]]$rom[$stagingDoorOffset..($stagingDoorOffset + 3)],
    [byte[]]@(0xFB,0x21,0x20,0x80))) 'Final neutral staging door is not FB 21 20 80.'

# The generated map pointer pairs stay inside their exact reserved spans.
function Get-Offset([string]$Method,[int]$Map) {
    return [int]$mapUtilType.GetMethod($Method, [Type[]]@([byte[]], [int])).Invoke($null,@($rom,$Map))
}
Assert-True ((Get-Offset 'getObjectOffset' $limeMap) -eq 0x8E080 `
    -and (Get-Offset 'getObjectOffset' ($limeMap+1)) -eq 0x8E090 `
    -and (Get-Offset 'getPiecePlacementOffset' $limeMap) -eq 0x88FCA `
    -and (Get-Offset 'getPiecePlacementOffset' ($limeMap+1)) -eq 0x88FD6 `
    -and (Get-Offset 'getTriggerOffset' $limeMap) -eq 0x88FEE) 'Foreign-slot Lime spans changed.'
Assert-True ((Get-Offset 'getObjectOffset' $stagingMap) -eq 0x8E090 `
    -and (Get-Offset 'getObjectOffset' ($stagingMap+1)) -eq 0x8E098 `
    -and (Get-Offset 'getPiecePlacementOffset' $stagingMap) -eq 0x88FD6 `
    -and (Get-Offset 'getPiecePlacementOffset' ($stagingMap+1)) -eq 0x88FE2 `
    -and (Get-Offset 'getTriggerOffset' $stagingMap) -eq 0x88FEE `
    -and (Get-Offset 'getTriggerOffset' ($stagingMap+1)) -eq 0x88FEE) `
    'Neutral staging spans overlap adjacent generated-map data.'
Assert-True ((Get-Offset 'getObjectOffset' $shadeMap) -eq 0x8E098 `
    -and (Get-Offset 'getObjectOffset' ($shadeMap+1)) -eq 0x8E0A8 `
    -and (Get-Offset 'getPiecePlacementOffset' $shadeMap) -eq 0x88FE2 `
    -and (Get-Offset 'getPiecePlacementOffset' ($shadeMap+1)) -eq 0x88FEE `
    -and (Get-Offset 'getTriggerOffset' $shadeMap) -eq 0x88FEE) 'Shade-slot replacement spans changed.'

$expectedLimeRefs = [byte[]]@(0xFE,0x00,0x0F,0xE4,0x01,0x01,0xFF,0x00,0x0F,0xE5,0x01,0x01)
$expectedShadeRefs = [byte[]]@(0xFE,0x00,0x0F,0xE6,0x01,0x01,0xFF,0x00,0x0F,0xDA,0x01,0x01)
$expectedStagingRefs = [byte[]]@(0xFE,0x00,0x0F,0xE9,0x00,0x00,0xFF,0x00,0x0F,0xE9,0x00,0x00)
Assert-True ([Linq.Enumerable]::SequenceEqual(
    [byte[]]$rom[0x88FCA..0x88FD5], $expectedLimeRefs)) `
    'Map $1FA does not serialize the exact $3E4/$3E5 piece references.'
Assert-True ([Linq.Enumerable]::SequenceEqual(
    [byte[]]$rom[0x88FE2..0x88FED], $expectedShadeRefs)) `
    'Map $1FC does not serialize the exact $3E6/$3DA piece references.'
Assert-True ([Linq.Enumerable]::SequenceEqual(
    [byte[]]$rom[0x88FD6..0x88FE1], $expectedStagingRefs)) `
    'Map $1FB does not serialize blank $0E9 on both layers.'

# Entry-event patching is narrow: only the matched Mantis entry door gains
# Lime's $0F death type, immediately after the door command.
$entryEvent = [Activator]::CreateInstance($eventScriptType)
$entryEvent.Door(0x08D)
$entryEvent.Jsr(0x7C4)
$entryEvent.End()
$context.replacementEvents[0x10C] = $entryEvent
$redirectType.GetMethod('patchLimeEntryEvent').Invoke($null,@($context))
Assert-True (Contains-Sequence $context.replacementEvents[0x10C] ([byte[]]@(0x18,0x8D,0x30,0x0B,0x0F))) `
    'Lime entry event did not receive death type $0F after its matched door.'

# Preserve leading slot state, then restore ordinary death/display state before
# the first fixed-orb message.  The randomized slot's own return door remains.
$deathEvent = [Activator]::CreateInstance($eventScriptType)
$deathEvent.IncrFlag(0x22)
$deathEvent.Jsr(0x501)
$deathEvent.Add(0x50)
$deathEvent.Add(0x12)
$deathEvent.Add(0x34)
$deathEvent.Add(0x56)
$deathEvent.Add(0x78)
$deathEvent.Add(0x00)
$deathEvent.Door(0x08E)
$deathEvent.End()
$context.replacementEvents[0x112] = $deathEvent
$redirectType.GetMethod('patchLimeDeathEvent').Invoke($null,@($context))
Assert-True (Contains-Sequence $context.replacementEvents[0x112] `
    ([byte[]]@(0x29,0x22,0x30,0x0B,0x02,0x19,0x0B,0x25,0x01))) `
    'Redirected Lime cleanup is not ordered between leading slot state and the fixed-orb message.'
Assert-True (-not (Contains-Sequence $context.replacementEvents[0x112] ([byte[]]@(0x18,0xC0))) `
    -and -not (Contains-Sequence $context.replacementEvents[0x112] ([byte[]]@(0x27,0x31)))) `
    'Redirected Lime cleanup still invokes Dread staging/progression behavior.'
Assert-True (Contains-Sequence $context.replacementEvents[0x112] `
    ([byte[]]@(0x50,0x12,0x34,0x56,0x78,0x00,0x18,0x8E,0x00))) `
    'Redirected Lime cleanup changed the slot prize or authoritative return door.'

# Slot-owned event sources remain authoritative for reward/progression/return.
$prizeSource = Get-Content (Join-Path $PSScriptRoot '..\SoMRandomizer\processing\openworld\events\PrizeEvents.cs') -Raw
$supportSource = Get-Content (Join-Path $PSScriptRoot '..\SoMRandomizer\processing\openworld\events\OpenWorldSupportingEvents.cs') -Raw
Assert-True ($prizeSource.Contains('context.replacementEvents[0x112] = newEvent112') `
    -and $prizeSource.Contains('newEvent112.Door(0x8E)')) 'Mantis reward/return event changed.'
Assert-True ($supportSource.Contains('context.replacementEvents[0x544] = newEvent544') `
    -and $supportSource.Contains('newEvent544.SetFlag(EventFlags.SHADE_PALACE_PROGRESS_FLAG_1, 6)') `
    -and $supportSource.Contains('newEvent544.Door(0x286)')) 'Shade progression/return event changed.'

# Same seed and forced placements must reproduce every byte and generated asset.
$again = Invoke-ForcedLimeCross 424242
$doorReplacerType.GetMethod('process').Invoke(
    [Activator]::CreateInstance($doorReplacerType), @($again[0],$again[1]))
Assert-True ([Linq.Enumerable]::SequenceEqual($result[0], [byte[]]$again[0])) 'Forced Lime cross is not deterministic.'
foreach($pieceId in @($limeBg,$limeFg,$shadeBg,$shadeFg)) {
    Assert-True ([Linq.Enumerable]::SequenceEqual(
        [byte[]]$context.replacementMapPieces[$pieceId].ToArray(),
        [byte[]]$again[1].replacementMapPieces[$pieceId].ToArray())) `
        ('Generated piece {0:X3} is not deterministic.' -f $pieceId)
}

# Nesoberi runs after BossSwaps in Open World and owns $88FBE-$88FC9.  Execute
# that real processor and prove its trigger relocation and both generated arena
# references coexist byte-for-byte in the final ordering.
$context.randomCosmetic = [Random]::new(777)
for($i = 0; $i -lt 3; $i++) {
    $context.workingData.set('nesoPrize' + $i, 'sword')
    $context.workingData.set('nesoHint' + $i, 'near Potos')
}
[byte[]]$generatedArenaDataBeforeNeso = [byte[]]$rom[0x88FCA..0x88FED]
$nesoberiProcess = $nesoberiType.GetMethod('process', [Reflection.BindingFlags]'Instance,NonPublic')
[object[]]$nesoberiArgs = @($originalRom,$rom,'lime-nesoberi-overlap-test',$result[2],$context)
Assert-True ([bool]$nesoberiProcess.Invoke([Activator]::CreateInstance($nesoberiType),$nesoberiArgs)) `
    'Nesoberi processor unexpectedly skipped.'
$expectedNesoberi = [byte[]]@(0xE0,0x01,0x2F,0x09,0x30,0x09,0x8B,0x01,0x2B,0x09,0x2B,0x09)
Assert-True ([Linq.Enumerable]::SequenceEqual(
    [byte[]]$rom[0x88FBE..0x88FC9], $expectedNesoberi)) `
    'Nesoberi trigger relocation bytes changed.'
Assert-True ([Linq.Enumerable]::SequenceEqual(
    [byte[]]$rom[0x88FCA..0x88FED], $generatedArenaDataBeforeNeso)) `
    'Nesoberi overwrote relocated Lime/Shade generated-map data.'
Assert-True ([Linq.Enumerable]::SequenceEqual(
    [byte[]]$rom[0x88FCA..0x88FD5], $expectedLimeRefs) `
    -and [Linq.Enumerable]::SequenceEqual(
    [byte[]]$rom[0x88FE2..0x88FED], $expectedShadeRefs) `
    -and [Linq.Enumerable]::SequenceEqual(
    [byte[]]$rom[0x88FD6..0x88FE1], $expectedStagingRefs)) `
    'Final Open World processor ordering changed unrelated generated-map data.'

Write-Output 'PASS: Lime Slime foreign-slot Mode-7 redirect, regular Shade replacement, slot-owned progression, bounded ROM spans, exclusions, and determinism verified.'
