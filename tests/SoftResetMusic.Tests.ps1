param(
    [string]$AssemblyPath = (Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path $AssemblyPath).Path)

function Assert-True([bool]$Condition, [string]$Message) {
    if(-not $Condition) { throw $Message }
}

$hackType = $assembly.GetType('SoMRandomizer.processing.hacks.common.music.RandomMusicHack', $true)
$ramType = $assembly.GetType('SoMRandomizer.processing.common.CustomRamOffsets', $true)
$listType = [Collections.Generic.List[byte]]
$replacementListType = [Collections.Generic.List``1].MakeGenericType($listType)
$replacementDictionaryType = [Collections.Generic.Dictionary``2].MakeGenericType([string], $replacementListType)
$songTypeDictionaryType = [Collections.Generic.Dictionary``2].MakeGenericType([byte], [string])

$rom = [byte[]]::new(0x400000)
# Preserve the relevant vanilla entry points so the test can prove the patch's scope.
[byte[]]$hardwareResetVector = @(0x5C, 0x10, 0x00, 0xC1)
[Array]::Copy($hardwareResetVector, 0, $rom, 0x8004, 4)
[byte[]]$resetEntry = @(0x5C, 0xE5, 0x4C, 0xC1)
[Array]::Copy($resetEntry, 0, $rom, 0x10010, 4)
[byte[]]$musicStart = @(0xA5, 0x02, 0x29, 0xF0)
[Array]::Copy($musicStart, 0, $rom, 0x301AD, 4)
[byte[]]$ordinaryLoad = @(0x22, 0x21, 0x00, 0xC0)
[Array]::Copy($ordinaryLoad, 0, $rom, 0x755C7, 4)

$before = [byte[]]$rom.Clone()
$replacements = [Activator]::CreateInstance($replacementDictionaryType)
$songTypes = [Activator]::CreateInstance($songTypeDictionaryType)
$offset = 0x300000
$arguments = [object[]]@($rom, $offset, $replacements, $songTypes)
$process = $hackType.GetMethod('process', [Reflection.BindingFlags]'Instance,Public')
$process.Invoke([Activator]::CreateInstance($hackType), $arguments) | Out-Null
$finalOffset = [int]$arguments[1]

Assert-True ($rom[0x8004] -eq 0x5C -and $rom[0x8005] -eq 0x10 -and
    $rom[0x8006] -eq 0x00 -and $rom[0x8007] -eq 0xC1) `
    'The hardware reset vector was changed instead of retaining the shared reset entry.'
Assert-True ($rom[0x10010] -eq 0x5C) 'The shared hard/soft reset entry was not hooked.'

$hookOffset = $rom[0x10011] -bor ($rom[0x10012] -shl 8) -bor (($rom[0x10013] - 0xC0) -shl 16)
$cacheAddress = [int]$ramType.GetField('MUSICRANDO_LASTSONG_BYTE').GetValue($null)
[byte[]]$expectedHook = @(
    0xE2, 0x20,
    0xA9, 0xFF,
    0x8F, ($cacheAddress -band 0xFF), (($cacheAddress -shr 8) -band 0xFF), (($cacheAddress -shr 16) -band 0xFF),
    0x5C, 0xE5, 0x4C, 0xC1
)
Assert-True ($hookOffset -eq 0x300000) 'Reset cache hook was emitted at an unexpected location.'
Assert-True (([BitConverter]::ToString($rom[$hookOffset..($hookOffset + 11)])) -eq
    ([BitConverter]::ToString($expectedHook))) `
    'Reset cache hook does not invalidate $7E042F and resume at the original reset target.'
Assert-True ($finalOffset -gt ($hookOffset + 11)) 'Music hook generation did not continue after reset handling.'

Assert-True (([BitConverter]::ToString($rom[0x755C7..0x755CA])) -eq
    ([BitConverter]::ToString($ordinaryLoad))) `
    'Ordinary/manual/autosave load code was modified.'
Assert-True ($rom[0x301AD] -eq 0x22) 'The normal music-start path is no longer routed through RandomMusicHack.'

$allowedFixedOffsets = [Collections.Generic.HashSet[int]]::new()
foreach($i in 0x10010..0x10013) { $allowedFixedOffsets.Add($i) | Out-Null }
foreach($i in 0x301AD..0x301B0) { $allowedFixedOffsets.Add($i) | Out-Null }
for($i = 0; $i -lt 0x300000; $i++) {
    if($rom[$i] -ne $before[$i] -and -not $allowedFixedOffsets.Contains($i)) {
        throw ('Unexpected fixed-ROM modification at ${0:X6}.' -f $i)
    }
}

Write-Output 'PASS: shared reset invalidates the random-music cache; ordinary loads and unrelated music/event data remain unchanged.'
