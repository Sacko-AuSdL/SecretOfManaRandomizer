param(
    [string]$AssemblyPath = (Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path $AssemblyPath).Path)
$commonType = $assembly.GetType('SoMRandomizer.config.settings.CommonSettings', $true)
$settingsType = $assembly.GetType('SoMRandomizer.config.settings.OpenWorldSettings', $true)
$processorType = $assembly.GetType('SoMRandomizer.processing.hacks.common.other.ManaBeastAppearance', $true)
$contextType = $assembly.GetType('SoMRandomizer.processing.common.RandoContext', $true)
$uiOptionsType = $assembly.GetType('SoMRandomizer.config.ui.UiOptionsManager', $true)
$dataUtilType = $assembly.GetType('SoMRandomizer.util.DataUtil', $true)
$process = $processorType.GetMethod('process', [Reflection.BindingFlags]'Instance,NonPublic')
$set = $commonType.GetMethod('set', [Type[]]@([string], [string]))

function Assert-True([bool]$Condition, [string]$Message) {
    if(-not $Condition) {
        throw $Message
    }
}

function Assert-RangeEqual([byte[]]$Expected, [byte[]]$Actual, [int]$Offset, [int]$Length, [string]$Message) {
    for($i = 0; $i -lt $Length; $i++) {
        if($Expected[$Offset + $i] -ne $Actual[$Offset + $i]) {
            throw "$Message Difference at ROM offset 0x$('{0:X6}' -f ($Offset + $i))."
        }
    }
}

function New-TestObjects([string]$Appearance = 'vanilla') {
    $common = [Activator]::CreateInstance($commonType)
    $settings = [Activator]::CreateInstance($settingsType, [object[]]@($common))
    if($Appearance -ne 'vanilla') {
        $set.Invoke($common, [object[]]@('manaBeastAppearance', $Appearance)) | Out-Null
    }
    $processor = [Activator]::CreateInstance($processorType)
    $context = [Activator]::CreateInstance($contextType)
    return @($common, $settings, $processor, $context)
}

function Invoke-Appearance($Settings, $Processor, $Context, [byte[]]$OriginalRom, [byte[]]$OutputRom) {
    [object[]]$arguments = [object[]]::new(5)
    $arguments[0] = $OriginalRom
    $arguments[1] = $OutputRom
    $arguments[2] = 'cosmetic-test-seed'
    $arguments[3] = $Settings
    $arguments[4] = $Context
    return [bool]$process.Invoke($Processor, $arguments)
}

$assets = @(
    @{
        Name = 'close-up tiles'
        Path = Join-Path $PSScriptRoot '..\SoMRandomizer\Resources\manaBeast\manabeast_closeup-18.sombosstiles'
        Resource = 'SoMRandomizer.Resources.manaBeast.manabeast_closeup-18.sombosstiles'
        Offset = 0x1A1000
        Size = 0x14F4
        Sha256 = 'F5F6E610923F2932781079A9B146DF79F667014982107855E537BD482DC21187'
    },
    @{
        Name = 'normal tiles'
        Path = Join-Path $PSScriptRoot '..\SoMRandomizer\Resources\manaBeast\manabeast-19.sombosstiles'
        Resource = 'SoMRandomizer.Resources.manaBeast.manabeast-19.sombosstiles'
        Offset = 0x1A37F8
        Size = 0x210B
        Sha256 = '24FA9317E463599BE1EB22B6B7E5BF92A79E4F38F18627875B19D04E868FA45A'
    },
    @{
        Name = 'palette 65'
        Path = Join-Path $PSScriptRoot '..\SoMRandomizer\Resources\manaBeast\BossPalette65.palette'
        Resource = 'SoMRandomizer.Resources.manaBeast.BossPalette65.palette'
        Offset = 0x02F9DE
        Size = 0x1E
        Sha256 = '29BD12DE3642CE989C8D313EEF234700D88621CBF2F93B40273749FBB1572022'
    }
)

$defaults = New-TestObjects
$defaultCommon = $defaults[0]
Assert-True ($defaultCommon.getDefault('manaBeastAppearance') -eq 'vanilla') 'Mana Beast Appearance must default to Vanilla.'
Assert-True ([Linq.Enumerable]::SequenceEqual(
    [string[]]$defaultCommon.getOptionsValues('manaBeastAppearance'),
    [string[]]@('vanilla', 'superRabite'))) 'Serialized Mana Beast Appearance values are incorrect.'
Assert-True ([Linq.Enumerable]::SequenceEqual(
    [string[]]$defaultCommon.getDisplayValues('manaBeastAppearance'),
    [string[]]@('Vanilla', 'Super Rabite'))) 'Displayed Mana Beast Appearance values are incorrect.'

# Verify UI option serialization and loading use the stable superRabite value.
$sourceManager = [Activator]::CreateInstance($uiOptionsType)
$sourceCombo = [System.Windows.Forms.ComboBox]::new()
foreach($display in $defaultCommon.getDisplayValues('manaBeastAppearance')) { $sourceCombo.Items.Add($display) | Out-Null }
$sourceManager.addComboBox($sourceCombo, 'manaBeastAppearance', $defaultCommon)
$sourceCombo.SelectedIndex = $defaultCommon.getIndex('manaBeastAppearance', 'superRabite')
$serialized = $sourceManager.getOptionsString()
Assert-True ($serialized.Contains('manaBeastAppearance=superRabite')) 'Super Rabite selection was not serialized.'

$loadedCommon = [Activator]::CreateInstance($commonType)
$loadedManager = [Activator]::CreateInstance($uiOptionsType)
$loadedCombo = [System.Windows.Forms.ComboBox]::new()
foreach($display in $loadedCommon.getDisplayValues('manaBeastAppearance')) { $loadedCombo.Items.Add($display) | Out-Null }
$loadedManager.addComboBox($loadedCombo, 'manaBeastAppearance', $loadedCommon)
$loadedManager.setOptions($serialized)
Assert-True ($loadedCommon.get('manaBeastAppearance') -eq 'superRabite') 'Super Rabite selection did not survive an options round trip.'

$readResource = $dataUtilType.GetMethod('readResource', [Reflection.BindingFlags]'Static,Public')
$manifestNames = [string[]]$assembly.GetManifestResourceNames()
foreach($asset in $assets) {
    $resolvedPath = (Resolve-Path $asset.Path).Path
    [byte[]]$diskBytes = [IO.File]::ReadAllBytes($resolvedPath)
    Assert-True ($diskBytes.Length -eq $asset.Size) "$($asset.Name) has the wrong size."
    Assert-True ((Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedPath).Hash -eq $asset.Sha256) "$($asset.Name) has the wrong SHA-256."
    Assert-True ($manifestNames.Contains($asset.Resource)) "$($asset.Name) is not embedded under the expected resource name."
    [byte[]]$resourceBytes = $readResource.Invoke($null, [object[]]@($asset.Resource))
    Assert-True ([Linq.Enumerable]::SequenceEqual($diskBytes, $resourceBytes)) "$($asset.Name) embedded bytes differ from the source asset."
}

[byte[]]$originalRom = [byte[]]::new(0x400000)
[Random]::new(8675309).NextBytes($originalRom)

[byte[]]$vanillaOutput = [byte[]]$originalRom.Clone()
$vanillaObjects = New-TestObjects
$vanillaSettings = $vanillaObjects[1]
$vanillaProcessor = $vanillaObjects[2]
$vanillaContext = $vanillaObjects[3]
Assert-True (-not (Invoke-Appearance $vanillaSettings $vanillaProcessor $vanillaContext $originalRom $vanillaOutput)) 'Vanilla mode should skip the cosmetic processor.'
Assert-True ([Linq.Enumerable]::SequenceEqual($originalRom, $vanillaOutput)) 'Vanilla mode changed ROM bytes.'

$superObjects = New-TestObjects 'superRabite'
[byte[]]$superOutput = [byte[]]$originalRom.Clone()
$superSettings = $superObjects[1]
$superProcessor = $superObjects[2]
$superContext = $superObjects[3]
Assert-True (Invoke-Appearance $superSettings $superProcessor $superContext $originalRom $superOutput) 'Super Rabite mode did not apply the cosmetic processor.'

[byte[]]$expectedOutput = [byte[]]$originalRom.Clone()
foreach($asset in $assets) {
    [byte[]]$assetBytes = [IO.File]::ReadAllBytes((Resolve-Path $asset.Path).Path)
    [Array]::Copy($assetBytes, 0, $expectedOutput, $asset.Offset, $asset.Size)
    Assert-RangeEqual $expectedOutput $superOutput $asset.Offset $asset.Size "$($asset.Name) was not written byte-for-byte."
    Assert-True ($superOutput[$asset.Offset - 1] -eq $originalRom[$asset.Offset - 1]) "$($asset.Name) wrote before its validated span."
    Assert-True ($superOutput[$asset.Offset + $asset.Size] -eq $originalRom[$asset.Offset + $asset.Size]) "$($asset.Name) wrote after its validated span."
}
Assert-True ([Linq.Enumerable]::SequenceEqual($expectedOutput, $superOutput)) 'Super Rabite changed bytes outside the three validated cosmetic spans.'

# Explicitly preserve the Mana Beast structure/AI pointer, stat record, Mode-7 state machine,
# and its three special boss-weapon damage bytes.
Assert-RangeEqual $originalRom $superOutput 0x1007F0 0x10 'Mana Beast structure or AI pointer changed.'
Assert-RangeEqual $originalRom $superOutput 0x102A63 0x1D 'Mana Beast stat record changed.'
Assert-RangeEqual $originalRom $superOutput 0x028F1E 0x0862 'Mana Beast Mode-7 AI/state-machine code changed.'
foreach($offset in @(0x10C0CD, 0x10C0DB, 0x10C0E2)) {
    Assert-True ($superOutput[$offset] -eq $originalRom[$offset]) "Mana Beast weapon power changed at 0x$('{0:X6}' -f $offset)."
}

# The patch is purely data-driven and must be deterministic for identical settings.
$repeatObjects = New-TestObjects 'superRabite'
[byte[]]$repeatOutput = [byte[]]$originalRom.Clone()
$repeatSettings = $repeatObjects[1]
$repeatProcessor = $repeatObjects[2]
$repeatContext = $repeatObjects[3]
Assert-True (Invoke-Appearance $repeatSettings $repeatProcessor $repeatContext $originalRom $repeatOutput) 'Repeated Super Rabite processing did not run.'
Assert-True ([Linq.Enumerable]::SequenceEqual($superOutput, $repeatOutput)) 'Super Rabite output was not deterministic.'

Write-Output 'PASS: setting round trip, exact embedded assets, Vanilla no-write behavior, bounded Super Rabite writes, gameplay-data preservation, and determinism are correct.'
