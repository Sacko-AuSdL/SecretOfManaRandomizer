param(
    [string]$AssemblyPath = (Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path $AssemblyPath).Path)
$commonType = $assembly.GetType('SoMRandomizer.config.settings.CommonSettings', $true)
$settingsType = $assembly.GetType('SoMRandomizer.config.settings.OpenWorldSettings', $true)
$processorType = $assembly.GetType('SoMRandomizer.processing.hacks.common.qol.PlayerMagicDamage', $true)
$statisticsType = $assembly.GetType('SoMRandomizer.processing.hacks.common.procgen.Statistics', $true)
$contextType = $assembly.GetType('SoMRandomizer.processing.common.RandoContext', $true)
$rngType = $assembly.GetType('SoMRandomizer.util.rng.DotNet110Random', $true)
$uiOptionsType = $assembly.GetType('SoMRandomizer.config.ui.UiOptionsManager', $true)

function Assert-True([bool]$Condition, [string]$Message) {
    if(-not $Condition) {
        throw $Message
    }
}

function New-TestObjects([int]$Seed = 12345) {
    $common = [Activator]::CreateInstance($commonType)
    $settings = [Activator]::CreateInstance($settingsType, [object[]]@($common))
    $processor = [Activator]::CreateInstance($processorType)
    $context = [Activator]::CreateInstance($contextType)
    $contextType.GetField('randomFunctional').SetValue($context, [Random]::new($Seed))
    return @($common, $settings, $processor, $context)
}

function Invoke-Processor($Type, $Processor, $Settings, $Context, [byte[]]$OriginalRom, [byte[]]$OutputRom) {
    $process = $Type.GetMethod('process', [Reflection.BindingFlags]'Instance,NonPublic')
    [object[]]$arguments = @($OriginalRom, $OutputRom, 'test-seed', $Settings, $Context)
    return [bool]$process.Invoke($Processor, $arguments)
}

function Get-HookAddress([byte[]]$Rom, [int]$Offset) {
    return [int]$Rom[$Offset + 1] + ([int]$Rom[$Offset + 2] -shl 8) + ([int]$Rom[$Offset + 3] -shl 16)
}

$objects = New-TestObjects
$common = $objects[0]
$settings = $objects[1]
$processor = $objects[2]
$context = $objects[3]
$set = $commonType.GetMethod('set', [Type[]]@([string], [string]))

Assert-True ($common.getDefault('playerMagicDamage') -eq 'vanilla') 'Overall player magic damage default must be Vanilla.'
Assert-True ($common.getDefault('playerMagicDamagePercent') -eq '40') 'Fixed player magic damage default must be 40%.'
Assert-True ([Linq.Enumerable]::SequenceEqual(
    [string[]]$common.getOptionsValues('playerMagicDamage'),
    [string[]]@('vanilla', 'fixed', 'random'))) 'Player magic damage mode options are incorrect.'
$fixedOptions = [string[]]$common.getOptionsValues('playerMagicDamagePercent')
Assert-True ($fixedOptions.Length -eq 21) 'Fixed percentages should contain 0% through 100% in 5% steps.'
for($i = 0; $i -lt $fixedOptions.Length; $i++) {
    Assert-True ([int]$fixedOptions[$i] -eq $i * 5) "Fixed percentage option $i is incorrect."
}

$set.Invoke($common, [object[]]@('playerMagicDamage', 'fixed')) | Out-Null
$set.Invoke($common, [object[]]@('playerMagicDamagePercent', '25')) | Out-Null
Assert-True ($common.get('playerMagicDamage') -eq 'fixed') 'Fixed mode did not serialize through CommonSettings.'
Assert-True ($common.get('playerMagicDamagePercent') -eq '25') 'Fixed percentage did not serialize through CommonSettings.'
Assert-True ($common.ToString().Contains('playerMagicDamagePercent = 25')) 'Settings text omitted the fixed percentage.'

function Test-OptionsRoundTrip([string]$Mode, [string]$Percent, [bool]$ExpectPercent) {
    $source = [Activator]::CreateInstance($commonType)
    $sourceManager = [Activator]::CreateInstance($uiOptionsType)
    $sourceMode = [System.Windows.Forms.ComboBox]::new()
    $sourcePercent = [System.Windows.Forms.ComboBox]::new()
    foreach($display in $source.getDisplayValues('playerMagicDamage')) { $sourceMode.Items.Add($display) | Out-Null }
    foreach($display in $source.getDisplayValues('playerMagicDamagePercent')) { $sourcePercent.Items.Add($display) | Out-Null }
    $sourceManager.addComboBox($sourceMode, 'playerMagicDamage', $source)
    $sourceManager.addComboBox($sourcePercent, 'playerMagicDamagePercent', $source)
    $sourceMode.SelectedIndex = $source.getIndex('playerMagicDamage', $Mode)
    $sourcePercent.SelectedIndex = $source.getIndex('playerMagicDamagePercent', $Percent)
    $serialized = $sourceManager.getOptionsString()

    Assert-True ($serialized.Contains("playerMagicDamage=$Mode")) "Generated options omitted mode '$Mode'."
    Assert-True ($serialized.Contains("playerMagicDamagePercent=$Percent") -eq $ExpectPercent) "Generated options percentage presence is wrong for mode '$Mode'."
    Assert-True (-not $serialized.Contains('playerMagicDamageFixedPercent')) 'Generated options contain the obsolete percentage key.'

    $loaded = [Activator]::CreateInstance($commonType)
    $loadedManager = [Activator]::CreateInstance($uiOptionsType)
    $loadedMode = [System.Windows.Forms.ComboBox]::new()
    $loadedPercent = [System.Windows.Forms.ComboBox]::new()
    foreach($display in $loaded.getDisplayValues('playerMagicDamage')) { $loadedMode.Items.Add($display) | Out-Null }
    foreach($display in $loaded.getDisplayValues('playerMagicDamagePercent')) { $loadedPercent.Items.Add($display) | Out-Null }
    $loadedManager.addComboBox($loadedMode, 'playerMagicDamage', $loaded)
    $loadedManager.addComboBox($loadedPercent, 'playerMagicDamagePercent', $loaded)
    $loadedManager.setOptions($serialized)
    Assert-True ($loaded.get('playerMagicDamage') -eq $Mode) "Round trip did not restore mode '$Mode'."
    if($ExpectPercent) {
        Assert-True ($loaded.get('playerMagicDamagePercent') -eq $Percent) "Round trip did not restore fixed percentage '$Percent'."
    }
    else {
        Assert-True ($loaded.get('playerMagicDamagePercent') -eq '40') 'Non-Fixed round trip should leave the fixed percentage at its default.'
    }
    return $serialized
}

foreach($percentage in @('50', '75', '100')) {
    Test-OptionsRoundTrip 'fixed' $percentage $true | Out-Null
}
Test-OptionsRoundTrip 'random' '50' $false | Out-Null

$resolve = $processorType.GetMethod('resolvePercentage', [Reflection.BindingFlags]'Static,NonPublic')
$scale = $processorType.GetMethod('scaleDamage', [Reflection.BindingFlags]'Static,NonPublic')
Assert-True ([int]$processorType.GetField('MIN_RANDOM_PERCENT', [Reflection.BindingFlags]'Static,NonPublic').GetRawConstantValue() -eq 0) 'Random minimum must be 0%.'
Assert-True ([int]$processorType.GetField('MAX_RANDOM_PERCENT', [Reflection.BindingFlags]'Static,NonPublic').GetRawConstantValue() -eq 100) 'Random maximum must be 100%.'
Assert-True ([int]$resolve.Invoke($null, [object[]]@('vanilla', 75, [Random]::new(1))) -eq 100) 'Vanilla must resolve to exactly 100%.'
Assert-True ([int]$resolve.Invoke($null, [object[]]@('fixed', 25, [Random]::new(1))) -eq 25) 'Fixed mode ignored its percentage.'
for($seed = 0; $seed -lt 100; $seed++) {
    $firstRng = [Activator]::CreateInstance($rngType, [object[]]@($seed))
    $secondRng = [Activator]::CreateInstance($rngType, [object[]]@($seed))
    $first = [int]$resolve.Invoke($null, [object[]]@('random', 75, $firstRng))
    $second = [int]$resolve.Invoke($null, [object[]]@('random', 75, $secondRng))
    Assert-True ($first -eq $second) "Random resolution was not deterministic for seed $seed."
    Assert-True ($first -ge 0 -and $first -le 100) "Random resolution $first is outside 0%-100%."
    Assert-True ($first % 5 -eq 0) "Random resolution $first is not a 5% step."
}

$scaleCases = @(
    @{ Damage = 0; Percent = 75; Expected = 0 },
    @{ Damage = 1; Percent = 5; Expected = 1 },
    @{ Damage = 3; Percent = 25; Expected = 1 },
    @{ Damage = 100; Percent = 75; Expected = 75 },
    @{ Damage = 999; Percent = 95; Expected = 949 },
    @{ Damage = 999; Percent = 0; Expected = 0 },
    @{ Damage = 999; Percent = 100; Expected = 999 }
)
foreach($case in $scaleCases) {
    $actual = [int]$scale.Invoke($null, [object[]]@($case.Damage, $case.Percent))
    Assert-True ($actual -eq $case.Expected) "Scale helper returned $actual for $($case.Damage) at $($case.Percent)%; expected $($case.Expected)."
}

[byte[]]$originalRom = [byte[]]::new(0x400000)
[byte[]]$firstOriginal = @(0x9D, 0xF1, 0xE1, 0xA5, 0xA4)
[byte[]]$secondOriginal = @(0x9D, 0xF1, 0xE1, 0xE2, 0x20)
[Array]::Copy($firstOriginal, 0, $originalRom, 0x8EB90, 5)
[Array]::Copy($secondOriginal, 0, $originalRom, 0x8E9F6, 5)

$objects = New-TestObjects
$vanillaSettings = $objects[1]
$vanillaProcessor = $objects[2]
$vanillaContext = $objects[3]
[byte[]]$vanillaOutput = [byte[]]$originalRom.Clone()
Assert-True (-not (Invoke-Processor $processorType $vanillaProcessor $vanillaSettings $vanillaContext $originalRom $vanillaOutput)) 'Vanilla should skip the ROM processor.'
Assert-True ([Linq.Enumerable]::SequenceEqual($originalRom, $vanillaOutput)) 'Vanilla mode changed ROM bytes.'

$objects = New-TestObjects
$fixedCommon = $objects[0]
$fixedSettings = $objects[1]
$fixedProcessor = $objects[2]
$fixedContext = $objects[3]
$set.Invoke($fixedCommon, [object[]]@('playerMagicDamage', 'fixed')) | Out-Null
$set.Invoke($fixedCommon, [object[]]@('playerMagicDamagePercent', '75')) | Out-Null
[byte[]]$fixedOutput = [byte[]]$originalRom.Clone()
Assert-True (Invoke-Processor $processorType $fixedProcessor $fixedSettings $fixedContext $originalRom $fixedOutput) 'Fixed 75% should emit the runtime multiplier.'
$workingData = $contextType.GetField('workingData').GetValue($fixedContext)
Assert-True ($workingData.getInt('playerMagicDamageResolvedPercentage') -eq 75) 'Fixed resolved percentage was not published.'
$scalerAddress = $workingData.getInt('playerMagicDamageRoutineOffsetHirom')
$scalerOffset = $scalerAddress - 0xC00000
[byte[]]$expectedGate = @(0xE0, 0x00, 0x06, 0x90, 0x00, 0xC0, 0x00, 0x06, 0xB0, 0x00,
    0x48, 0xE2, 0x20, 0xBF, 0xE7, 0xE1, 0x7E, 0xC9, 0x55, 0xC2, 0x20, 0xD0, 0x00, 0x68, 0x6B, 0x68,
    0xC9, 0x00, 0x00, 0xF0, 0x00)
for($i = 0; $i -lt $expectedGate.Length; $i++) {
    if($i -notin @(4, 9, 22, 30)) {
        Assert-True ($fixedOutput[$scalerOffset + $i] -eq $expectedGate[$i]) 'Runtime scaler source/target/Crystal-Orb/zero gate is incorrect.'
    }
}
Assert-True ($fixedOutput[0x8EB90] -eq 0x22 -and $fixedOutput[0x8EB94] -eq 0xEA) 'First final-damage store hook is incorrect.'
Assert-True ($fixedOutput[0x8E9F6] -eq 0x22 -and $fixedOutput[0x8E9FA] -eq 0xEA) 'Second final-damage store hook is incorrect.'
$firstWrapper = (Get-HookAddress $fixedOutput 0x8EB90) - 0xC00000
$secondWrapper = (Get-HookAddress $fixedOutput 0x8E9F6) - 0xC00000
[byte[]]$expectedFirstWrapperTail = @(0x9D, 0xF1, 0xE1, 0xA5, 0xA4, 0x6B)
[byte[]]$expectedSecondWrapperTail = @(0x9D, 0xF1, 0xE1, 0xE2, 0x20, 0x6B)
foreach($wrapper in @($firstWrapper, $secondWrapper)) {
    Assert-True ($fixedOutput[$wrapper] -eq 0x22) 'Store wrapper does not call the shared scaler.'
    Assert-True ((Get-HookAddress $fixedOutput $wrapper) -eq $scalerAddress) 'Store wrapper calls the wrong scaler.'
}
for($i = 0; $i -lt 6; $i++) {
    Assert-True ($fixedOutput[$firstWrapper + 4 + $i] -eq $expectedFirstWrapperTail[$i]) 'First wrapper failed to replay displaced code.'
    Assert-True ($fixedOutput[$secondWrapper + 4 + $i] -eq $expectedSecondWrapperTail[$i]) 'Second wrapper failed to replay displaced code.'
}

# Statistics runs after common hacks in procgen modes and replaces the same stores. It must
# chain the published scaler before storing/tracking damage instead of dropping the setting.
$statistics = [Activator]::CreateInstance($statisticsType)
Assert-True (Invoke-Processor $statisticsType $statistics $fixedSettings $fixedContext $originalRom $fixedOutput) 'Statistics processor did not run.'
$statisticsFirstWrapper = (Get-HookAddress $fixedOutput 0x8EB90) - 0xC00000
$statisticsSecondWrapper = (Get-HookAddress $fixedOutput 0x8E9F6) - 0xC00000
foreach($wrapper in @($statisticsFirstWrapper, $statisticsSecondWrapper)) {
    Assert-True ($fixedOutput[$wrapper] -eq 0x22) 'Statistics magic hook does not call the shared scaler first.'
    Assert-True ((Get-HookAddress $fixedOutput $wrapper) -eq $scalerAddress) 'Statistics magic hook calls the wrong scaler.'
    Assert-True ($fixedOutput[$wrapper + 4] -eq 0x9D -and $fixedOutput[$wrapper + 5] -eq 0xF1 -and $fixedOutput[$wrapper + 6] -eq 0xE1) 'Statistics hook does not store scaled pending damage.'
}

Write-Output 'PASS: defaults, Fixed 50/75/100 option round trips, Random 0%-100% bounds/serialization/determinism, scaling helper, vanilla no-write behavior, final-store hooks, and Statistics chaining are correct.'
