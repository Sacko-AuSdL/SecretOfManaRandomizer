param(
    [string]$AssemblyPath = (Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe'),
    [string]$SourceRom = 'D:\views\tools\bots\Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc'
)

$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if(-not $Condition) { throw $Message }
}

function Hex-Pool([byte[]]$Pool) {
    return (@($Pool | ForEach-Object { '{0:X2}' -f $_ }) -join ' ')
}

$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path $AssemblyPath).Path)
$commonType = $assembly.GetType('SoMRandomizer.config.settings.CommonSettings', $true)
$settingsType = $assembly.GetType('SoMRandomizer.config.settings.OpenWorldSettings', $true)
$contextType = $assembly.GetType('SoMRandomizer.processing.common.RandoContext', $true)
$bossSwapsType = $assembly.GetType('SoMRandomizer.processing.common.BossSwaps', $true)
$bossMapsType = $assembly.GetType('SoMRandomizer.processing.common.VanillaBossMaps', $true)
$bossMapType = $assembly.GetType('SoMRandomizer.processing.common.VanillaBossMaps+VanillaBossMap', $true)
$redirectType = $assembly.GetType('SoMRandomizer.processing.common.DoomWallBossArenaRedirect', $true)
$mapUtilType = $assembly.GetType('SoMRandomizer.processing.common.VanillaMapUtil', $true)
$namesType = $assembly.GetType('SoMRandomizer.processing.hacks.common.util.NamesOfThings', $true)
$plandoType = $assembly.GetType('SoMRandomizer.processing.openworld.PlandoProperties', $true)
$prizeEventsType = $assembly.GetType('SoMRandomizer.processing.openworld.events.PrizeEvents', $true)
$doorReplacerType = $assembly.GetType('SoMRandomizer.processing.hacks.common.util.DoorReplacer', $true)

[byte[]]$originalRom = [IO.File]::ReadAllBytes((Resolve-Path $SourceRom).Path)
$getObjectOffset = $mapUtilType.GetMethod('getObjectOffset', [Type[]]@([byte[]], [int]))
$process = $bossSwapsType.GetMethod('process', [Reflection.BindingFlags]'Instance,NonPublic')

# The checked-in CSV is the machine-readable compatibility audit. Lock every
# declared arena's map, native species, swap pool, and random pool to that snapshot.
$matrixPath = Join-Path $PSScriptRoot 'BossCompatibilityMatrix.csv'
$matrix = @(Import-Csv $matrixPath)
$mapFields = @($bossMapsType.GetFields([Reflection.BindingFlags]'Public,Static') |
    Where-Object { $_.FieldType -eq $bossMapType })
Assert-True ($matrix.Count -eq $mapFields.Count) 'Compatibility matrix does not cover every declared boss arena.'

foreach($row in $matrix) {
    $field = $bossMapsType.GetField($row.Arena, [Reflection.BindingFlags]'Public,Static')
    Assert-True ($null -ne $field) "Missing arena field $($row.Arena)."
    $map = $field.GetValue($null)
    Assert-True ($map.originalMapNum -eq [int]$row.Map) "$($row.Arena) map changed."
    Assert-True ($map.getOriginalBossId($originalRom) -eq [Convert]::ToByte($row.NativeBoss, 16)) `
        "$($row.Arena) native boss changed."
    Assert-True ((Hex-Pool $map.supportedSwapBosses) -eq $row.SwapPool) "$($row.Arena) swap pool changed."
    Assert-True ((Hex-Pool $map.allSupportedBosses) -eq $row.RandomPool) "$($row.Arena) random pool changed."
}

$bossSwapSource = Get-Content (Join-Path $PSScriptRoot '..\SoMRandomizer\processing\common\BossSwaps.cs') -Raw
foreach($row in @($matrix | Where-Object { $_.OpenWorldSlot -eq 'true' })) {
    Assert-True ($bossSwapSource.Contains("swapMaps.Add(VanillaBossMaps.$($row.Arena));")) `
        "$($row.Arena) is marked as an Open World slot but is not registered by BossSwaps."
}
foreach($row in @($matrix | Where-Object { $_.OpenWorldSlot -eq 'false' })) {
    Assert-True (-not $bossSwapSource.Contains("swapMaps.Add(VanillaBossMaps.$($row.Arena));")) `
        "$($row.Arena) unexpectedly participates in Open World BossSwaps."
}

$wallFace = $bossMapsType.GetField('WALLFACE').GetValue($null)
$doomsWall = $bossMapsType.GetField('DOOMSWALL').GetValue($null)
$mantisAnt = $bossMapsType.GetField('MANTISANT').GetValue($null)
$limeSlime = $bossMapsType.GetField('LIMESLIME').GetValue($null)
$dreadSlime = $bossMapsType.GetField('DREADSLIME').GetValue($null)
Assert-True ((Hex-Pool $wallFace.supportedSwapBosses) -eq '58 61 6E 73 75 77 79') 'Wall Face swap pool changed.'
Assert-True ((Hex-Pool $doomsWall.supportedSwapBosses) -eq '58 61') 'Doom Wall swap pool is not wall-only.'
$doomRandomPool = '57 58 59 5A 5B 5C 5D 5E 5F 60 61 62 63 64 65 66 68 69 6B 6D 6E 6F 70 71 72 73 74 75 76 77 78 79 7B 7D'
Assert-True ((Hex-Pool $doomsWall.allSupportedBosses) -eq $doomRandomPool) 'Doom Wall redirect pool changed.'
foreach($excluded in @(0x67, 0x6A, 0x6C, 0x7A, 0x7C, 0x7E, 0x7F, 0x80)) {
    Assert-True (-not $doomsWall.allSupportedBosses.Contains([byte]$excluded)) `
        ('Excluded special boss {0:X2} entered the Doom redirect pool.' -f $excluded)
}
Assert-True ((Hex-Pool $limeSlime.allSupportedBosses) -eq '6A') 'Lime Slime is no longer native-only.'
Assert-True ((Hex-Pool $dreadSlime.allSupportedBosses) -eq '7C') 'Dread Slime is no longer native-only.'

function Get-MapObjectOffset([byte[]]$Rom, $BossMap) {
    return [int]$getObjectOffset.Invoke($null, [object[]]@($Rom, $BossMap.originalMapNum)) + 8 + 8 * $BossMap.originalObjNum
}

function Get-ObjectEvent([byte[]]$Rom, [int]$Offset) {
    return [int]$Rom[$Offset + 6] + (([int]$Rom[$Offset + 7] -band 0x07) -shl 8)
}

function Invoke-ForcedWalls([string]$WallFaceBoss, [string]$DoomWallBoss, [int]$Seed) {
    $common = [Activator]::CreateInstance($commonType)
    $settings = [Activator]::CreateInstance($settingsType, [object[]]@($common))
    $settings.set('opBosses', 'random')
    $context = [Activator]::CreateInstance($contextType)
    $context.randomFunctional = [Random]::new($Seed)
    $context.namesOfThings = [Activator]::CreateInstance($namesType, [object[]]@(,$originalRom))
    $context.plandoSettings[$plandoType.GetField('KEY_BOSS_WALLFACE').GetValue($null)] =
        [Collections.Generic.List[string]]::new([string[]]@($WallFaceBoss))
    $context.plandoSettings[$plandoType.GetField('KEY_BOSS_DOOMSWALL').GetValue($null)] =
        [Collections.Generic.List[string]]::new([string[]]@($DoomWallBoss))
    # Keep the independent Lime Slime slot native so this focused Doom test
    # continues to assert only the Doom redirect's generated assets.
    $context.plandoSettings[$plandoType.GetField('KEY_BOSS_LIMESLIME').GetValue($null)] =
        [Collections.Generic.List[string]]::new([string[]]@('Lime-Slime'))

    [byte[]]$outputRom = [byte[]]::new(0x400000)
    [Array]::Copy($originalRom, $outputRom, $originalRom.Length)
    $context.originalRom = $originalRom
    $context.outputRom = $outputRom
    $beforeOffset = $context.workingOffset
    $processor = [Activator]::CreateInstance($bossSwapsType)
    [object[]]$args = @($originalRom, $outputRom, "wall-test-$Seed", $settings, $context)
    Assert-True ([bool]$process.Invoke($processor, $args)) 'BossSwaps unexpectedly skipped.'
    Assert-True ($context.workingOffset -gt $beforeOffset -and $context.workingOffset -lt ($beforeOffset + 0x100)) `
        'BossSwaps free-space hook allocation escaped its expected bounded span.'
    Assert-True ($context.replacementEvents.Count -eq 0) 'BossSwaps unexpectedly replaced a death/reward event.'
    return ,@($outputRom, $context, $settings)
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

$wallFaceOffsetOriginal = Get-MapObjectOffset $originalRom $wallFace
$doomWallOffsetOriginal = Get-MapObjectOffset $originalRom $doomsWall
Assert-True ((Get-ObjectEvent $originalRom $wallFaceOffsetOriginal) -eq 0x16E) 'Unexpected native Wall Face death event.'
Assert-True ((Get-ObjectEvent $originalRom $doomWallOffsetOriginal) -eq 0x553) 'Unexpected native Doom Wall death event.'

# Force both directions in one ROM. Species changes, but coordinates and the
# dungeon slot's own object event remain authoritative.
$crossed = Invoke-ForcedWalls "Doom's-Wall" 'Wall-Face' 24680
[byte[]]$crossedRom = $crossed[0]
$crossedContext = $crossed[1]
Assert-True ($crossedContext.generatedMaps.Count -eq 0) 'Wall Face in the Doom slot should retain native map 407.'
Assert-True (-not $crossedContext.replacementDoors.ContainsKey(0x14F) -and -not $crossedContext.replacementDoors.ContainsKey(0x150)) `
    'Wall Face in the Doom slot unexpectedly redirected the native wall entry doors.'
$wallFaceOffset = Get-MapObjectOffset $crossedRom $wallFace
$doomWallOffset = Get-MapObjectOffset $crossedRom $doomsWall
Assert-True ($crossedRom[$wallFaceOffset + 5] -eq 0x61) 'Doom Wall was not placed in the Wall Face slot.'
Assert-True ($crossedRom[$doomWallOffset + 5] -eq 0x58) 'Wall Face was not placed in the Doom Wall slot.'
Assert-True (($crossedRom[$wallFaceOffset + 2] -band 0x7F) -eq 14 -and ($crossedRom[$wallFaceOffset + 3] -band 0x7F) -eq 6) `
    'Wall Face arena coordinates changed.'
Assert-True (($crossedRom[$doomWallOffset + 2] -band 0x7F) -eq 14 -and ($crossedRom[$doomWallOffset + 3] -band 0x7F) -eq 8) `
    'Doom Wall arena coordinates changed.'
Assert-True ((Get-ObjectEvent $crossedRom $wallFaceOffset) -eq 0x16E) 'Pandora slot lost death/reward event 016E.'
Assert-True ((Get-ObjectEvent $crossedRom $doomWallOffset) -eq 0x553) 'Northtown slot lost death/reward event 0553.'

$eightBitStats = @(0, 11, 26, 3, 4, 5, 6, 7, 8, 18, 19)
$sixteenBitStats = @(1, 16, 27, 9, 12)
foreach($index in $eightBitStats) {
    Assert-True ($crossedRom[0x101C00 + 0x6C * 29 + $index] -eq $originalRom[0x101C00 + 0x7E * 29 + $index]) `
        "Chamber's Eye 8-bit stat $index did not inherit Doom's Eye's slot stat."
    Assert-True ($crossedRom[0x101C00 + 0x7E * 29 + $index] -eq $originalRom[0x101C00 + 0x6C * 29 + $index]) `
        "Doom's Eye 8-bit stat $index did not inherit Chamber's Eye's slot stat."
}
foreach($index in $sixteenBitStats) {
    foreach($byteOffset in 0..1) {
        Assert-True ($crossedRom[0x101C00 + 0x6C * 29 + $index + $byteOffset] -eq $originalRom[0x101C00 + 0x7E * 29 + $index + $byteOffset]) `
            "Chamber's Eye 16-bit stat $index did not inherit Doom's Eye's slot stat."
        Assert-True ($crossedRom[0x101C00 + 0x7E * 29 + $index + $byteOffset] -eq $originalRom[0x101C00 + 0x6C * 29 + $index + $byteOffset]) `
            "Doom's Eye 16-bit stat $index did not inherit Chamber's Eye's slot stat."
    }
}

# Regression for the fixed constant-true condition: leaving each wall in its
# native slot must not copy Doom's Eye's 8-bit stats over Chamber's Eye.
$native = Invoke-ForcedWalls 'Wall-Face' "Doom's-Wall" 13579
[byte[]]$nativeRom = $native[0]
Assert-True ($native[1].generatedMaps.Count -eq 0) 'Native Doom Wall should retain native map 407.'
Assert-True (-not $native[1].replacementDoors.ContainsKey(0x14F) -and -not $native[1].replacementDoors.ContainsKey(0x150)) `
    'Native Doom Wall unexpectedly redirected the native wall entry doors.'
foreach($index in $eightBitStats) {
    Assert-True ($nativeRom[0x101C00 + 0x6C * 29 + $index] -eq $originalRom[0x101C00 + 0x6C * 29 + $index]) `
        "Native Doom Wall processing changed Chamber's Eye stat $index."
}

# Same seed + same forced selections must produce identical ROM bytes.
$crossedAgain = Invoke-ForcedWalls "Doom's-Wall" 'Wall-Face' 24680
Assert-True ([Linq.Enumerable]::SequenceEqual($crossedRom, [byte[]]$crossedAgain[0])) 'Wall selection is not deterministic.'

# An ordinary boss in the Doom slot is imported into the reserved generated map.
$redirected = Invoke-ForcedWalls 'Wall-Face' 'Mantis-Ant' 97531
[byte[]]$redirectedRom = $redirected[0]
$redirectedContext = $redirected[1]
$redirectedSettings = $redirected[2]
$generatedMapId = $redirectType.GetField('GENERATED_MAP_ID').GetRawConstantValue()
$bgPieceId = $redirectType.GetField('GENERATED_BG_PIECE_ID').GetRawConstantValue()
$fgPieceId = $redirectType.GetField('GENERATED_FG_PIECE_ID').GetRawConstantValue()
Assert-True ($generatedMapId -eq 0x1FE) 'Unexpected Doom redirect map ID.'
Assert-True ($redirectedContext.generatedMaps.Count -eq 0) `
    'Sparse Doom arena must not enter the destructive global FullMapReplacer path.'
Assert-True ($redirectedContext.replacementMapPieces.Count -eq 2 `
    -and $redirectedContext.replacementDoors.Count -eq 2) `
    'Ordinary Doom-slot redirect generated unrelated map pieces or doors.'
Assert-True ($redirectedContext.replacementMapPieces.ContainsKey($bgPieceId) -and $redirectedContext.replacementMapPieces.ContainsKey($fgPieceId)) `
    'Generated arena pieces were not registered.'

$serializedObjects = $mapUtilType.GetMethod('getObjects', [Type[]]@([byte[]], [int])).Invoke(
    $null, [object[]]@($redirectedRom, $generatedMapId))
$serializedTriggers = $mapUtilType.GetMethod('getTriggers', [Type[]]@([byte[]], [int])).Invoke(
    $null, [object[]]@($redirectedRom, $generatedMapId))
$serializedPieces = $mapUtilType.GetMethod('getMapPieceReference', [Type[]]@([byte[]], [int])).Invoke(
    $null, [object[]]@($redirectedRom, $generatedMapId))
$serializedHeader = $mapUtilType.GetMethod('getHeader', [Type[]]@([byte[]], [int])).Invoke(
    $null, [object[]]@($redirectedRom, $generatedMapId))
Assert-True ($serializedObjects.Count -eq 1 -and $serializedObjects[0].getSpecies() -eq 0x57 -and $serializedObjects[0].getEvent() -eq 0x553) `
    'Serialized generated map lost its Mantis Ant or Doom-slot death event.'
Assert-True ($serializedObjects[0].getEvent() -ne 0x112) 'Generated boss retained Mantis Ant native progression.'
Assert-True ($serializedHeader.getWalkonEventEnabled()) 'Generated arena lost Doom slot walk-on event.'
Assert-True ($serializedTriggers.Count -eq 1 -and $serializedTriggers[0] -eq 0x552) `
    'Generated arena retained native triggers or lost Doom slot event 552.'
Assert-True ($serializedPieces.bgPieces.Count -eq 1 -and $serializedPieces.bgPieces[0].pieceIndex -eq $bgPieceId `
    -and $serializedPieces.fgPieces.Count -eq 1 -and $serializedPieces.fgPieces[0].pieceIndex -eq $fgPieceId) `
    'Serialized generated map lost its isolated piece references.'
foreach($doorId in @(0x14F, 0x150)) {
    Assert-True ($redirectedContext.replacementDoors.ContainsKey($doorId)) ('Missing redirected entry door {0:X3}.' -f $doorId)
    $door = $redirectedContext.replacementDoors[$doorId]
    Assert-True ($door.getTargetMap() -eq $generatedMapId) ('Entry door {0:X3} targets the wrong map.' -f $doorId)
    Assert-True ($door.getXpos() -eq $mantisAnt.entryPos.xpos -and $door.getYpos() -eq $mantisAnt.entryPos.ypos) `
        ('Entry door {0:X3} lost Mantis arena entry coordinates.' -f $doorId)
    Assert-True ($door.getTransitionType() -eq 0) ('Entry door {0:X3} retained wall-only transition semantics.' -f $doorId)
}

# Map 510 and the replacement piece IDs are unused in vanilla, so the generated
# arena cannot overwrite another reachable map/piece.  No vanilla door targets it.
Assert-True (($mapUtilType.GetMethod('getObjects', [Type[]]@([byte[]], [int])).Invoke($null, [object[]]@($originalRom, $generatedMapId))).Count -eq 0) `
    'Reserved generated map is not empty in vanilla.'
Assert-True (($mapUtilType.GetMethod('getTriggers', [Type[]]@([byte[]], [int])).Invoke($null, [object[]]@($originalRom, $generatedMapId))).Count -eq 0) `
    'Reserved generated map has vanilla triggers.'
$usedPieceIds = [Collections.Generic.HashSet[int]]::new()
for($mapId = 0; $mapId -lt 512; $mapId++) {
    $pieces = $mapUtilType.GetMethod('getMapPieceReference', [Type[]]@([byte[]], [int])).Invoke($null, [object[]]@($originalRom, $mapId))
    foreach($piece in $pieces.bgPieces) { [void]$usedPieceIds.Add($piece.pieceIndex) }
    foreach($piece in $pieces.fgPieces) { [void]$usedPieceIds.Add($piece.pieceIndex) }
}
Assert-True (-not $usedPieceIds.Contains($bgPieceId) -and -not $usedPieceIds.Contains($fgPieceId)) `
    'Reserved generated piece ID is referenced by a vanilla map.'
for($doorId = 0; $doorId -lt 0x400; $doorId++) {
    $offset = 0x83000 + $doorId * 4
    $targetMap = [int]$originalRom[$offset] + (([int]$originalRom[$offset + 1] -band 1) -shl 8)
    Assert-True ($targetMap -ne $generatedMapId) ('Vanilla door {0:X3} already targets reserved map 1FE.' -f $doorId)
}

# PrizeEvents builds event 553 after BossSwaps.  Redirected fights retain its
# Northtown prize/flags/tail and add the native Northtown return Door 314.
$prizeProcess = $prizeEventsType.GetMethod('process', [Reflection.BindingFlags]'Instance,NonPublic')
$prizeProcessor = [Activator]::CreateInstance($prizeEventsType)
[object[]]$prizeArgs = @($originalRom, $redirectedRom, 'redirect-prize', $redirectedSettings, $redirectedContext)
Assert-True ([bool]$prizeProcess.Invoke($prizeProcessor, $prizeArgs)) 'PrizeEvents unexpectedly skipped.'
$redirected553 = $redirectedContext.replacementEvents[0x553]
Assert-True (Contains-Sequence $redirected553 ([byte[]]@(0x25, 0x04, 0x29, 0x2D, 0x29, 0x2D))) `
    'Redirected event 553 lost its orb reward or two Northtown flag increments.'
Assert-True (Contains-Sequence $redirected553 ([byte[]]@(0x12, 0x34, 0x56, 0x78, 0x00))) `
    'Redirected event 553 lost the Doom-slot randomized prize injection point.'
Assert-True (Contains-Sequence $redirected553 ([byte[]]@(0x1B, 0x14))) 'Redirected event 553 does not use return Door 314.'
Assert-True (Contains-Sequence $redirected553 ([byte[]]@(0x16, 0x47))) 'Redirected event 553 lost Jump 647.'

$wallPrizeContext = $crossed[1]
$wallPrizeSettings = $crossed[2]
[object[]]$wallPrizeArgs = @($originalRom, $crossedRom, 'wall-prize', $wallPrizeSettings, $wallPrizeContext)
Assert-True ([bool]$prizeProcess.Invoke([Activator]::CreateInstance($prizeEventsType), $wallPrizeArgs)) 'Wall PrizeEvents unexpectedly skipped.'
Assert-True (-not (Contains-Sequence $wallPrizeContext.replacementEvents[0x553] ([byte[]]@(0x1B, 0x14)))) `
    'Native wall event 553 was incorrectly forced through Door 314.'

$redirectedAgain = Invoke-ForcedWalls 'Wall-Face' 'Mantis-Ant' 97531
Assert-True ([Linq.Enumerable]::SequenceEqual($redirectedRom, [byte[]]$redirectedAgain[0])) 'Redirected boss selection is not deterministic.'
Assert-True ([Linq.Enumerable]::SequenceEqual(
    [byte[]]$redirectedContext.replacementMapPieces[$bgPieceId].ToArray(),
    [byte[]]$redirectedAgain[1].replacementMapPieces[$bgPieceId].ToArray())) 'Generated arena data is not deterministic.'

# Map 510 is serialized into unused tails of the vanilla bank-8 collections.
# Its map-511 sentinels advance without touching any preceding map data.
$doorReplacerType.GetMethod('process').Invoke(
    [Activator]::CreateInstance($doorReplacerType),
    [object[]]@($redirectedRom, $redirectedContext))
$serializedObjectStart = $mapUtilType.GetMethod('getObjectOffset', [Type[]]@([byte[]], [int])).Invoke(
    $null, [object[]]@($redirectedRom, $generatedMapId))
$serializedObjectEnd = $mapUtilType.GetMethod('getObjectOffset', [Type[]]@([byte[]], [int])).Invoke(
    $null, [object[]]@($redirectedRom, ($generatedMapId + 1)))
$serializedPieceStart = $mapUtilType.GetMethod('getPiecePlacementOffset', [Type[]]@([byte[]], [int])).Invoke(
    $null, [object[]]@($redirectedRom, $generatedMapId))
$serializedPieceEnd = $mapUtilType.GetMethod('getPiecePlacementOffset', [Type[]]@([byte[]], [int])).Invoke(
    $null, [object[]]@($redirectedRom, ($generatedMapId + 1)))
$serializedTriggerStart = $mapUtilType.GetMethod('getTriggerOffset', [Type[]]@([byte[]], [int])).Invoke(
    $null, [object[]]@($redirectedRom, $generatedMapId))
$serializedTriggerEnd = $mapUtilType.GetMethod('getTriggerOffset', [Type[]]@([byte[]], [int])).Invoke(
    $null, [object[]]@($redirectedRom, ($generatedMapId + 1)))
Assert-True ($serializedObjectStart -eq 0x8E068 -and $serializedObjectEnd -eq 0x8E078 `
    -and $serializedPieceStart -eq 0x88FA8 -and $serializedPieceEnd -eq 0x88FB4 `
    -and $serializedTriggerStart -eq 0x88FB4 -and $serializedTriggerEnd -eq 0x88FB6) `
    'Generated arena serialization escaped or overlapped its bounded vanilla free-space span.'
$vanillaTriggerEnd = $mapUtilType.GetMethod('getTriggerOffset', [Type[]]@([byte[]], [int])).Invoke(
    $null, [object[]]@($originalRom, 511))
$vanillaPieceEnd = $mapUtilType.GetMethod('getPiecePlacementOffset', [Type[]]@([byte[]], [int])).Invoke(
    $null, [object[]]@($originalRom, 511))
$vanillaObjectEnd = $mapUtilType.GetMethod('getObjectOffset', [Type[]]@([byte[]], [int])).Invoke(
    $null, [object[]]@($originalRom, 511))
Assert-True ($vanillaPieceEnd -eq 0x888F7 -and $vanillaTriggerEnd -eq 0x88FA8 `
    -and $vanillaObjectEnd -eq 0x8E068 -and $serializedTriggerEnd -le 0x89000) `
    'Reserved map data does not begin at the proven vanilla collection tails.'
$makePieceReference = $mapUtilType.GetMethod('makeMapPieceReference')
$originalBuffyPieces = $mapUtilType.GetMethod('getMapPieceReference', [Type[]]@([byte[]], [int])).Invoke(
    $null, [object[]]@($originalRom, 0x0F4))
$redirectedBuffyPieces = $mapUtilType.GetMethod('getMapPieceReference', [Type[]]@([byte[]], [int])).Invoke(
    $null, [object[]]@($redirectedRom, 0x0F4))
Assert-True ([Linq.Enumerable]::SequenceEqual(
    [byte[]]$makePieceReference.Invoke($null, [object[]]@($originalBuffyPieces)),
    [byte[]]$makePieceReference.Invoke($null, [object[]]@($redirectedBuffyPieces)))) `
    'Generated arena overwrote Buffy map-piece references near the old $087400 scratch area.'
foreach($doorId in @(0x14F, 0x150)) {
    $offset = 0x83000 + $doorId * 4
    $targetMap = [int]$redirectedRom[$offset] + (([int]$redirectedRom[$offset + 1] -band 1) -shl 8)
    Assert-True ($targetMap -eq $generatedMapId) ('Serialized entry door {0:X3} targets the wrong map.' -f $doorId)
    Assert-True ($redirectedRom[$offset + 3] -eq 0) ('Serialized entry door {0:X3} lost transition 0.' -f $doorId)
}

# Slot-owned Open World event tails stay in their authoritative event definitions.
$prizeEventsSource = Get-Content (Join-Path $PSScriptRoot '..\SoMRandomizer\processing\openworld\events\PrizeEvents.cs') -Raw
Assert-True ($prizeEventsSource.Contains('newEvent16E.Door(0x25)')) 'Pandora Wall post-boss door changed.'
Assert-True ($prizeEventsSource.Contains('newEvent16E.SetFlag(EventFlags.PANDORA_RUINS_FLAG, 0xA)')) 'Pandora Wall progression changed.'
Assert-True ($prizeEventsSource.Contains('newEvent553.IncrFlag(EventFlags.NORTHTOWN_RUINS_FLAG)')) 'Doom Wall progression changed.'
Assert-True ($prizeEventsSource.Contains('newEvent553.Jump(0x647)')) 'Doom Wall post-boss tail changed.'

Write-Output 'PASS: exact compatibility matrix, native walls, ordinary Doom-slot redirect, isolated arena data, slot events, child stats, and determinism verified.'
