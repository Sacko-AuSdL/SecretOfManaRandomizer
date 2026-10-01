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
$mapUtilType = $assembly.GetType('SoMRandomizer.processing.common.VanillaMapUtil', $true)
$namesType = $assembly.GetType('SoMRandomizer.processing.hacks.common.util.NamesOfThings', $true)
$plandoType = $assembly.GetType('SoMRandomizer.processing.openworld.PlandoProperties', $true)

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
$limeSlime = $bossMapsType.GetField('LIMESLIME').GetValue($null)
$dreadSlime = $bossMapsType.GetField('DREADSLIME').GetValue($null)
Assert-True ((Hex-Pool $wallFace.supportedSwapBosses) -eq '58 61 6E 73 75 77 79') 'Wall Face swap pool changed.'
Assert-True ((Hex-Pool $doomsWall.supportedSwapBosses) -eq '58 61') 'Doom Wall swap pool is not wall-only.'
Assert-True ((Hex-Pool $doomsWall.allSupportedBosses) -eq '58 61') 'Doom Wall random pool admitted a non-wall boss.'
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

    [byte[]]$outputRom = [byte[]]::new(0x400000)
    [Array]::Copy($originalRom, $outputRom, $originalRom.Length)
    $beforeOffset = $context.workingOffset
    $processor = [Activator]::CreateInstance($bossSwapsType)
    [object[]]$args = @($originalRom, $outputRom, "wall-test-$Seed", $settings, $context)
    Assert-True ([bool]$process.Invoke($processor, $args)) 'BossSwaps unexpectedly skipped.'
    Assert-True ($context.workingOffset -gt $beforeOffset -and $context.workingOffset -lt ($beforeOffset + 0x100)) `
        'BossSwaps free-space hook allocation escaped its expected bounded span.'
    Assert-True ($context.generatedMaps.Count -eq 0) 'BossSwaps unexpectedly generated a map.'
    Assert-True ($context.replacementEvents.Count -eq 0) 'BossSwaps unexpectedly replaced a death/reward event.'
    return ,@($outputRom, $context)
}

$wallFaceOffsetOriginal = Get-MapObjectOffset $originalRom $wallFace
$doomWallOffsetOriginal = Get-MapObjectOffset $originalRom $doomsWall
Assert-True ((Get-ObjectEvent $originalRom $wallFaceOffsetOriginal) -eq 0x16E) 'Unexpected native Wall Face death event.'
Assert-True ((Get-ObjectEvent $originalRom $doomWallOffsetOriginal) -eq 0x553) 'Unexpected native Doom Wall death event.'

# Force both directions in one ROM. Species changes, but coordinates and the
# dungeon slot's own object event remain authoritative.
$crossed = Invoke-ForcedWalls "Doom's-Wall" 'Wall-Face' 24680
[byte[]]$crossedRom = $crossed[0]
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
foreach($index in $eightBitStats) {
    Assert-True ($nativeRom[0x101C00 + 0x6C * 29 + $index] -eq $originalRom[0x101C00 + 0x6C * 29 + $index]) `
        "Native Doom Wall processing changed Chamber's Eye stat $index."
}

# Same seed + same forced selections must produce identical ROM bytes.
$crossedAgain = Invoke-ForcedWalls "Doom's-Wall" 'Wall-Face' 24680
Assert-True ([Linq.Enumerable]::SequenceEqual($crossedRom, [byte[]]$crossedAgain[0])) 'Wall selection is not deterministic.'

# Slot-owned Open World event tails stay in their authoritative event definitions.
$prizeEventsSource = Get-Content (Join-Path $PSScriptRoot '..\SoMRandomizer\processing\openworld\events\PrizeEvents.cs') -Raw
Assert-True ($prizeEventsSource.Contains('newEvent16E.Door(0x25)')) 'Pandora Wall post-boss door changed.'
Assert-True ($prizeEventsSource.Contains('newEvent16E.SetFlag(EventFlags.PANDORA_RUINS_FLAG, 0xA)')) 'Pandora Wall progression changed.'
Assert-True ($prizeEventsSource.Contains('newEvent553.IncrFlag(EventFlags.NORTHTOWN_RUINS_FLAG)')) 'Doom Wall progression changed.'
Assert-True ($prizeEventsSource.Contains('newEvent553.Jump(0x647)')) 'Doom Wall post-boss tail changed.'

Write-Output 'PASS: exact compatibility matrix, wall-only Doom pool, both wall directions, coordinates, slot events, child stats, and determinism verified.'
