param(
    [string]$AssemblyPath = (Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Release\net462\SoMRandomizer.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path $AssemblyPath).Path)
$commonType = $assembly.GetType('SoMRandomizer.config.settings.CommonSettings', $true)
$settingsType = $assembly.GetType('SoMRandomizer.config.settings.OpenWorldSettings', $true)
$processorType = $assembly.GetType('SoMRandomizer.processing.hacks.common.qol.WeaponUpgradeCosts', $true)
$contextType = $assembly.GetType('SoMRandomizer.processing.common.RandoContext', $true)

$common = [Activator]::CreateInstance($commonType)
$settings = [Activator]::CreateInstance($settingsType, [object[]]@($common))
$processor = [Activator]::CreateInstance($processorType)
$context = [Activator]::CreateInstance($contextType)
$process = $processorType.GetMethod('process', [Reflection.BindingFlags]'Instance,NonPublic')
$set = $commonType.GetMethod('set', [Type[]]@([string], [string]))

$tableOffset = 0x18FCFB
[byte[]]$vanillaBytes = 0xC8, 0x00, 0x90, 0x01, 0x20, 0x03, 0x40, 0x06,
    0xB8, 0x0B, 0x64, 0x19, 0xD4, 0x30, 0xA8, 0x61
[byte[]]$reducedBytes = 0x64, 0x00, 0x64, 0x00, 0xC8, 0x00, 0x90, 0x01,
    0xEE, 0x02, 0x72, 0x06, 0x4E, 0x0C, 0x6A, 0x18

function Invoke-WeaponUpgradeCosts([byte[]]$OriginalRom, [byte[]]$OutputRom) {
    [object[]]$arguments = [object[]]::new(5)
    $arguments[0] = $OriginalRom
    $arguments[1] = $OutputRom
    $arguments[2] = 'test-seed'
    $arguments[3] = $settings
    $arguments[4] = $context
    return [bool]$process.Invoke($processor, $arguments)
}

function Assert-True([bool]$Condition, [string]$Message) {
    if(-not $Condition) {
        throw $Message
    }
}

$default = $commonType.GetMethod('getDefault').Invoke($common, [object[]]@('weaponUpgradeCosts'))
Assert-True ($default -eq 'vanilla') "Expected Vanilla default, got '$default'."

[byte[]]$originalRom = [byte[]]::new(0x400000)
[Array]::Copy($vanillaBytes, 0, $originalRom, $tableOffset, $vanillaBytes.Length)

[byte[]]$vanillaOutput = [byte[]]$originalRom.Clone()
Assert-True (-not (Invoke-WeaponUpgradeCosts $originalRom $vanillaOutput)) 'Vanilla mode should skip the processor.'
Assert-True ([Linq.Enumerable]::SequenceEqual($originalRom, $vanillaOutput)) 'Vanilla mode changed ROM bytes.'

$set.Invoke($common, [object[]]@('weaponUpgradeCosts', 'reduced')) | Out-Null
[byte[]]$reducedOutput = [byte[]]$originalRom.Clone()
Assert-True (Invoke-WeaponUpgradeCosts $originalRom $reducedOutput) 'Reduced mode should apply the processor.'

for($i = 0; $i -lt $reducedBytes.Length; $i++) {
    Assert-True ($reducedOutput[$tableOffset + $i] -eq $reducedBytes[$i]) "Wrong reduced byte at table index $i."
}

[byte[]]$expectedReducedOutput = [byte[]]$originalRom.Clone()
[Array]::Copy($reducedBytes, 0, $expectedReducedOutput, $tableOffset, $reducedBytes.Length)
Assert-True ([Linq.Enumerable]::SequenceEqual($expectedReducedOutput, $reducedOutput)) 'Reduced mode changed bytes outside the price table.'

$total = 0
for($i = 0; $i -lt 8; $i++) {
    $total += [BitConverter]::ToUInt16($reducedOutput, $tableOffset + $i * 2)
}
Assert-True ($total -eq 12600) "Expected a 12,600 GP total, got $total."

Write-Output 'PASS: Vanilla is unchanged; Reduced writes only the eight forge prices; total is 12,600 GP.'
