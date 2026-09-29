param(
    [string]$AssemblyPath = (Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path $AssemblyPath).Path)
$commonType = $assembly.GetType('SoMRandomizer.config.settings.CommonSettings', $true)
$settingsType = $assembly.GetType('SoMRandomizer.config.settings.OpenWorldSettings', $true)
$processorType = $assembly.GetType('SoMRandomizer.processing.hacks.common.other.ManaBeastAppearance', $true)
$sillyNamesType = $assembly.GetType('SoMRandomizer.processing.openworld.OpenWorldSillyEnemyNamePicker', $true)
$contextType = $assembly.GetType('SoMRandomizer.processing.common.RandoContext', $true)
$namesType = $assembly.GetType('SoMRandomizer.processing.hacks.common.util.NamesOfThings', $true)
$vanillaEventUtilType = $assembly.GetType('SoMRandomizer.processing.common.VanillaEventUtil', $true)
$uiOptionsType = $assembly.GetType('SoMRandomizer.config.ui.UiOptionsManager', $true)
$dataUtilType = $assembly.GetType('SoMRandomizer.util.DataUtil', $true)
$process = $processorType.GetMethod('process', [Reflection.BindingFlags]'Instance,NonPublic')
$sillyNamesProcess = $sillyNamesType.GetMethod('process', [Reflection.BindingFlags]'Instance,NonPublic')
$set = $commonType.GetMethod('set', [Type[]]@([string], [string]))
$getTextBytes = $vanillaEventUtilType.GetMethod('getBytes', [Type[]]@([string]))
$getTextChar = $vanillaEventUtilType.GetMethod('getChar', [Type[]]@([byte]))
$setAllNames = $namesType.GetMethod('setAllNames', [Type[]]@([byte[]], [int].MakeByRefType()))
$newNamesField = $namesType.GetField('newNames', [Reflection.BindingFlags]'Instance,NonPublic')

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

function Assert-BytesAt([byte[]]$Expected, [byte[]]$Actual, [int]$ActualOffset, [string]$Message) {
    for($i = 0; $i -lt $Expected.Length; $i++) {
        if($Expected[$i] -ne $Actual[$ActualOffset + $i]) {
            throw "$Message Difference at ROM offset 0x$('{0:X6}' -f ($ActualOffset + $i))."
        }
    }
}

function Set-SyntheticThingName([byte[]]$Rom, [int]$EventId, [string]$Name, [ref]$Cursor) {
    [int]$pointerOffset = 0xA0000 + ($EventId - 0x400) * 2
    [int]$dataOffset = 0xA0000 + $Cursor.Value
    $Rom[$pointerOffset] = [byte]($Cursor.Value -band 0xFF)
    $Rom[$pointerOffset + 1] = [byte](($Cursor.Value -shr 8) -band 0xFF)
    [byte[]]$bytes = $getTextBytes.Invoke($null, [object[]]@($Name))
    [Array]::Copy($bytes, 0, $Rom, $dataOffset, $bytes.Length)
    $Rom[$dataOffset + $bytes.Length] = 0
    $Cursor.Value += $bytes.Length + 1
}

function Initialize-SyntheticThingNames([byte[]]$Rom) {
    [int]$cursorValue = 0xB000
    for($eventId = 0x800; $eventId -le 0x94E; $eventId++) {
        $name = 'N' + $eventId.ToString('X3')
        if($eventId -eq 0x8BA) { $name = 'Flammie Drum' }
        if($eventId -eq 0x94E) { $name = 'Mana Beast' }
        Set-SyntheticThingName $Rom $eventId $name ([ref]$cursorValue)
    }
}

function Attach-ThingNames($Context, [byte[]]$Rom) {
    $Context.namesOfThings = [Activator]::CreateInstance($namesType, [object[]]@(,$Rom))
}

function Read-ExpandedThingName([byte[]]$Rom, [int]$EventId, [int]$DataBankOffset) {
    [int]$pointerOffset = 0xA0000 + ($EventId - 0x400) * 2
    [int]$pointer = [int]$Rom[$pointerOffset] -bor ([int]$Rom[$pointerOffset + 1] -shl 8)
    [int]$offset = $DataBankOffset + $pointer
    [Text.StringBuilder]$result = [Text.StringBuilder]::new()
    while($Rom[$offset] -ne 0) {
        [void]$result.Append([char]$getTextChar.Invoke($null, [object[]]@([byte]$Rom[$offset])))
        $offset++
    }
    return $result.ToString()
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

function Invoke-SillyNames($Settings, $Context, [byte[]]$OriginalRom, [byte[]]$OutputRom) {
    $processor = [Activator]::CreateInstance($sillyNamesType)
    [object[]]$arguments = [object[]]::new(5)
    $arguments[0] = $OriginalRom
    $arguments[1] = $OutputRom
    $arguments[2] = 'cosmetic-test-seed'
    $arguments[3] = $Settings
    $arguments[4] = $Context
    return [bool]$sillyNamesProcess.Invoke($processor, $arguments)
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
    [string[]]@('Vanilla', 'Manabite'))) 'Displayed Mana Beast Appearance values are incorrect.'

# Verify UI option serialization and loading use the stable superRabite value.
$sourceManager = [Activator]::CreateInstance($uiOptionsType)
$sourceCombo = [System.Windows.Forms.ComboBox]::new()
foreach($display in $defaultCommon.getDisplayValues('manaBeastAppearance')) { $sourceCombo.Items.Add($display) | Out-Null }
$sourceManager.addComboBox($sourceCombo, 'manaBeastAppearance', $defaultCommon)
$sourceCombo.SelectedIndex = $defaultCommon.getIndex('manaBeastAppearance', 'superRabite')
$serialized = $sourceManager.getOptionsString()
Assert-True ($serialized.Contains('manaBeastAppearance=superRabite')) 'Manabite selection was not serialized with the stable value.'

$loadedCommon = [Activator]::CreateInstance($commonType)
$loadedManager = [Activator]::CreateInstance($uiOptionsType)
$loadedCombo = [System.Windows.Forms.ComboBox]::new()
foreach($display in $loadedCommon.getDisplayValues('manaBeastAppearance')) { $loadedCombo.Items.Add($display) | Out-Null }
$loadedManager.addComboBox($loadedCombo, 'manaBeastAppearance', $loadedCommon)
$loadedManager.setOptions($serialized)
Assert-True ($loadedCommon.get('manaBeastAppearance') -eq 'superRabite') 'Manabite selection did not survive an options round trip.'

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
Initialize-SyntheticThingNames $originalRom

[byte[]]$vanillaOutput = [byte[]]$originalRom.Clone()
$vanillaObjects = New-TestObjects
$vanillaSettings = $vanillaObjects[1]
$vanillaProcessor = $vanillaObjects[2]
$vanillaContext = $vanillaObjects[3]
Attach-ThingNames $vanillaContext $originalRom
Assert-True (-not (Invoke-Appearance $vanillaSettings $vanillaProcessor $vanillaContext $originalRom $vanillaOutput)) 'Vanilla mode should skip the cosmetic processor.'
Assert-True ([Linq.Enumerable]::SequenceEqual($originalRom, $vanillaOutput)) 'Vanilla mode changed ROM bytes.'
Assert-True ($vanillaContext.namesOfThings.getOriginalName(0xCF + 0x7F) -eq 'Mana Beast') 'Vanilla mode did not retain the original Mana Beast name.'
Assert-True ($newNamesField.GetValue($vanillaContext.namesOfThings).Count -eq 0) 'Vanilla mode registered an unexpected name replacement.'

$superObjects = New-TestObjects 'superRabite'
[byte[]]$superOutput = [byte[]]$originalRom.Clone()
$superSettings = $superObjects[1]
$superProcessor = $superObjects[2]
$superContext = $superObjects[3]
Attach-ThingNames $superContext $originalRom
Assert-True (Invoke-Appearance $superSettings $superProcessor $superContext $originalRom $superOutput) 'Manabite mode did not apply the cosmetic processor.'

[byte[]]$expectedOutput = [byte[]]$originalRom.Clone()
foreach($asset in $assets) {
    [byte[]]$assetBytes = [IO.File]::ReadAllBytes((Resolve-Path $asset.Path).Path)
    [Array]::Copy($assetBytes, 0, $expectedOutput, $asset.Offset, $asset.Size)
    Assert-RangeEqual $expectedOutput $superOutput $asset.Offset $asset.Size "$($asset.Name) was not written byte-for-byte."
    Assert-True ($superOutput[$asset.Offset - 1] -eq $originalRom[$asset.Offset - 1]) "$($asset.Name) wrote before its validated span."
    Assert-True ($superOutput[$asset.Offset + $asset.Size] -eq $originalRom[$asset.Offset + $asset.Size]) "$($asset.Name) wrote after its validated span."
}
Assert-True ([Linq.Enumerable]::SequenceEqual($expectedOutput, $superOutput)) 'Manabite changed bytes outside the three validated cosmetic spans.'

# Enemy species $7F maps to the final enemy-name entry: 0x8CF + 0x7F = event 0x94E.
# This is the lookup consumed by both normal targeting and Analyze/Scan.
[int]$manaBeastNameIndex = 0xCF + 0x7F
Assert-True ((0x800 + $manaBeastNameIndex) -eq 0x94E) 'Mana Beast species does not resolve to the expected dedicated name event.'
$pendingNames = $newNamesField.GetValue($superContext.namesOfThings)
Assert-True ($pendingNames.Count -eq 1) 'Manabite registered unrelated name replacements.'
Assert-True ($pendingNames[$manaBeastNameIndex] -eq 'Manabite') 'Manabite mode did not register the Manabite boss name.'

$originalThingNames = @{}
for($eventId = 0x800; $eventId -le 0x94E; $eventId++) {
    $originalThingNames[$eventId] = $superContext.namesOfThings.getOriginalName($eventId - 0x800)
}
[byte[]]$namedOutput = [byte[]]$superOutput.Clone()
[object[]]$setAllNamesArguments = @($namedOutput, [int]0x300000)
$setAllNames.Invoke($superContext.namesOfThings, $setAllNamesArguments) | Out-Null
Assert-True ((Read-ExpandedThingName $namedOutput 0x94E 0x300000) -eq 'Manabite') 'Generated enemy-name data does not decode to Manabite.'
for($eventId = 0x800; $eventId -lt 0x94E; $eventId++) {
    Assert-True ((Read-ExpandedThingName $namedOutput $eventId 0x300000) -eq $originalThingNames[$eventId]) "Thing-name event 0x$($eventId.ToString('X3')) changed unexpectedly."
}
Assert-True ((Read-ExpandedThingName $namedOutput 0x8BA 0x300000) -eq 'Flammie Drum') 'Flammie Drum item text changed unexpectedly.'
Assert-RangeEqual $originalRom $namedOutput 0x90000 0x10800 'Event/dialogue data changed while applying the Manabite enemy name.'

[int]$manabitePointerOffset = 0xA0000 + (0x94E - 0x400) * 2
[int]$manabitePointer = [int]$namedOutput[$manabitePointerOffset] -bor ([int]$namedOutput[$manabitePointerOffset + 1] -shl 8)
[int]$manabiteDataOffset = 0x300000 + $manabitePointer
[byte[]]$expectedManabiteBytes = [byte[]](0xA7, 0x81, 0x8E, 0x81, 0x82, 0x89, 0x94, 0x85, 0x00)
Assert-BytesAt $expectedManabiteBytes $namedOutput $manabiteDataOffset 'Manabite was not encoded exactly.'

# Open World's silly-name processor must leave the dedicated species $7F entry alone for both
# Vanilla and Manabite, while retaining its historical cosmetic RNG consumption.
$vanillaSillyObjects = New-TestObjects
$vanillaSillySettings = $vanillaSillyObjects[1]
$vanillaSillyContext = $vanillaSillyObjects[3]
Attach-ThingNames $vanillaSillyContext $originalRom
$vanillaSillyContext.randomCosmetic = [Random]::new(0)
[byte[]]$vanillaSillyOutput = [byte[]]$originalRom.Clone()
Assert-True (Invoke-SillyNames $vanillaSillySettings $vanillaSillyContext $originalRom $vanillaSillyOutput) 'Open World silly-name processor did not run.'
$vanillaSillyPending = $newNamesField.GetValue($vanillaSillyContext.namesOfThings)
Assert-True (-not $vanillaSillyPending.ContainsKey($manaBeastNameIndex)) 'Vanilla Mana Beast name was replaced by an Open World joke name.'
Assert-True ($vanillaSillyContext.namesOfThings.getOriginalName($manaBeastNameIndex) -eq 'Mana Beast') 'Open World did not preserve the original Mana Beast name.'

$superContext.randomCosmetic = [Random]::new(0)
Assert-True (Invoke-SillyNames $superSettings $superContext $originalRom $superOutput) 'Open World silly-name processor did not run for Manabite.'
Assert-True ($pendingNames[$manaBeastNameIndex] -eq 'Manabite') 'Open World replaced the Manabite boss name.'

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
Attach-ThingNames $repeatContext $originalRom
Assert-True (Invoke-Appearance $repeatSettings $repeatProcessor $repeatContext $originalRom $repeatOutput) 'Repeated Manabite processing did not run.'
Assert-True ([Linq.Enumerable]::SequenceEqual($superOutput, $repeatOutput)) 'Manabite output was not deterministic.'

Write-Output 'PASS: setting round trip, exact embedded assets, dedicated Manabite target/Analyze name, Vanilla no-write behavior, unrelated-name preservation, bounded writes, gameplay-data preservation, and determinism are correct.'
