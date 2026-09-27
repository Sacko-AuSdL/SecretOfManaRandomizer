param(
    [string]$AssemblyPath = (Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path $AssemblyPath).Path)
$commonType = $assembly.GetType('SoMRandomizer.config.settings.CommonSettings', $true)
$settingsType = $assembly.GetType('SoMRandomizer.config.settings.OpenWorldSettings', $true)
$processorType = $assembly.GetType('SoMRandomizer.processing.hacks.openworld.CrystalOrbWeaponBreaking', $true)
$requirementsType = $assembly.GetType('SoMRandomizer.processing.hacks.openworld.CrystalOrbRequirements', $true)
$requirementType = $assembly.GetType('SoMRandomizer.processing.hacks.openworld.CrystalOrbRequirementType', $true)
$colorsType = $assembly.GetType('SoMRandomizer.processing.hacks.openworld.CrystalOrbColors', $true)
$supportingEventsType = $assembly.GetType('SoMRandomizer.processing.openworld.events.OpenWorldSupportingEvents', $true)
$contextType = $assembly.GetType('SoMRandomizer.processing.common.RandoContext', $true)
$ramType = $assembly.GetType('SoMRandomizer.processing.common.CustomRamOffsets', $true)
$randomType = $assembly.GetType('SoMRandomizer.util.rng.DotNet110Random', $true)

function Assert-True([bool]$Condition, [string]$Message) {
    if(-not $Condition) { throw $Message }
}

function New-ByteList([byte[]]$Bytes) {
    $list = [System.Collections.Generic.List[byte]]::new()
    foreach($value in $Bytes) { $list.Add($value) }
    return ,$list
}

function New-TestObjects {
    $common = [Activator]::CreateInstance($commonType)
    $settings = [Activator]::CreateInstance($settingsType, [object[]]@($common))
    $processor = [Activator]::CreateInstance($processorType)
    $context = [Activator]::CreateInstance($contextType)
    return @($settings, $processor, $context)
}

function Set-CrystalOrbFeatureOn($Settings) {
    $settingsType.GetMethod('set', [Type[]]@([string], [string])).Invoke(
        $Settings, [object[]]@('crystalOrbWeaponBreaking', 'on')) | Out-Null
}

function Set-Word([byte[]]$Rom, [int]$Offset, [int]$Value) {
    $Rom[$Offset] = [byte]($Value -band 0xFF)
    $Rom[$Offset + 1] = [byte](($Value -shr 8) -band 0xFF)
}

function Invoke-Processor($Processor, $Settings, $Context, [byte[]]$OriginalRom, [byte[]]$OutputRom) {
    $process = $processorType.GetMethod('process', [Reflection.BindingFlags]'Instance,NonPublic')
    return [bool]$process.Invoke($Processor, [object[]]@(
        $OriginalRom, $OutputRom, 'test-seed', $Settings, $Context))
}

function Find-ByteSequence([byte[]]$Haystack, [int]$Start, [int]$Length, [byte[]]$Needle) {
    for($i = $Start; $i -le $Start + $Length - $Needle.Length; $i++) {
        $match = $true
        for($j = 0; $j -lt $Needle.Length; $j++) {
            if($Haystack[$i + $j] -ne $Needle[$j]) { $match = $false; break }
        }
        if($match) { return $i }
    }
    return -1
}

function Assert-Sequence([byte[]]$Haystack, [int]$Start, [int]$Length, [byte[]]$Needle, [string]$Message) {
    Assert-True ((Find-ByteSequence $Haystack $Start $Length $Needle) -ge 0) $Message
}

function Get-OrbDefinitions {
    return @(
        @{ Name='Earth Palace'; Map=291; Event=0x239; Element=0x81; Checker=0x350; Flag=0x98; Type='SpecificWeapon'; Value=5; Display='Bow'; Bytes=[byte[]](0x23,0x50,0x42,0x18,0x2F,0x10,0x00,0x42,0x98,0x13,0x10,0x38,0x00) },
        @{ Name='Matango'; Map=307; Event=0x27E; Element=0x81; Checker=0x350; Flag=0x98; Type='SpecificWeapon'; Value=6; Display='Boomerang'; Bytes=[byte[]](0x23,0x50,0x42,0x24,0x4F,0x10,0x00,0x42,0x98,0x13,0x12,0x7C,0x27,0x99,0x00) },
        @{ Name='Fire Palace 1'; Map=348; Event=0x2C8; Element=0x83; Checker=0x353; Flag=0x9B; Type='SpecificWeapon'; Value=1; Display='Sword'; Bytes=[byte[]](0x23,0x53,0x42,0x9B,0x13,0x12,0xC9,0x00) },
        @{ Name='Fire Palace 2'; Map=345; Event=0x6CB; Element=0x83; Checker=0x353; Flag=0x9B; Type='SpecificWeapon'; Value=2; Display='Axe'; Bytes=[byte[]](0x23,0x53,0x42,0x9B,0x13,0x16,0xCA,0x00) },
        @{ Name='Fire Palace 3'; Map=240; Event=0x6CE; Element=0x82; Checker=0x351; Flag=0x99; Type='SpecificWeapon'; Value=3; Display='Spear'; Bytes=[byte[]](0x23,0x51,0x42,0x99,0x13,0x16,0xC7,0x00) },
        @{ Name='Upper Land'; Map=41; Event=0x25A; Element=0x85; Checker=0x352; Flag=0x9A; Type='SpecificWeapon'; Value=1; Display='Sword'; Bytes=[byte[]](0x23,0x52,0x42,0x9A,0x13,0x12,0x5B,0x00) },
        @{ Name='Luna Palace'; Map=35; Event=0x2C4; Element=0x87; Checker=0x356; Flag=0x9E; Type='SpecificWeapon'; Value=2; Display='Axe'; Bytes=[byte[]](0x23,0x56,0x42,0x9E,0x13,0x12,0xC5,0x00) },
        @{ Name='Grand Palace 1'; Map=420; Event=0x570; Element=0x81; Checker=0x350; Flag=0x98; Type='SpecificWeapon'; Value=7; Display='Javelin'; GrandFlag=0xE8 },
        @{ Name='Grand Palace 2'; Map=421; Event=0x571; Element=0x82; Checker=0x351; Flag=0x99; Type='SpecificWeapon'; Value=1; Display='Sword'; GrandFlag=0xE9 },
        @{ Name='Grand Palace 3'; Map=422; Event=0x572; Element=0x85; Checker=0x352; Flag=0x9A; Type='SpecificWeapon'; Value=2; Display='Axe'; GrandFlag=0xEA },
        @{ Name='Grand Palace 4'; Map=423; Event=0x573; Element=0x83; Checker=0x353; Flag=0x9B; Type='Magic'; Value=0x83; Display='Salamando'; GrandFlag=0xEB },
        @{ Name='Grand Palace 5'; Map=424; Event=0x574; Element=0x84; Checker=0x354; Flag=0x9C; Type='Magic'; Value=0x84; Display='Lumina'; GrandFlag=0xEC },
        @{ Name='Grand Palace 6'; Map=425; Event=0x575; Element=0x86; Checker=0x355; Flag=0x9D; Type='Magic'; Value=0x86; Display='Shade'; GrandFlag=0xED },
        @{ Name='Grand Palace 7'; Map=426; Event=0x576; Element=0x87; Checker=0x356; Flag=0x9E; Type='Magic'; Value=0x87; Display='Luna'; GrandFlag=0xEE }
    )
}

function Complete-GrandEventDefinitions($Definitions) {
    foreach($definition in $Definitions) {
        if($definition.ContainsKey('GrandFlag')) {
            $definition.Bytes = [byte[]](
                [byte](0x20 + ($definition.Checker -shr 8)),
                [byte]($definition.Checker -band 0xFF),
                0x42,[byte]$definition.Flag,0x00,0x10,0x00,
                0x29,[byte]$definition.GrandFlag,0x15,0x78,0x00)
        }
    }
}

function Add-GeneratedOrbEvents($Context, $Definitions) {
    $workingData = $contextType.GetField('workingData').GetValue($Context)
    $events = $contextType.GetField('replacementEvents').GetValue($Context)
    foreach($definition in $Definitions) {
        $workingData.setInt('orbElement' + $definition.Map, [int]$definition.Element)
        $events[$definition.Event] = New-ByteList $definition.Bytes
    }
}

function Seed-VanillaGrandEvents([byte[]]$OriginalRom, $Definitions) {
    $cursor = 0x0800
    foreach($definition in $Definitions | Where-Object { $_.ContainsKey('GrandFlag') }) {
        Set-Word $OriginalRom (0xA0000 + ($definition.Event - 0x400) * 2) $cursor
        [Array]::Copy($definition.Bytes, 0, $OriginalRom, 0xA0000 + $cursor, $definition.Bytes.Length)
        $cursor += $definition.Bytes.Length
    }
    Set-Word $OriginalRom (0xA0000 + (0x577 - 0x400) * 2) $cursor
}

$definitions = Get-OrbDefinitions
Complete-GrandEventDefinitions $definitions

# Domain model: exactly one active requirement per map and no WeaponPower category.
$enumNames = [Enum]::GetNames($requirementType)
Assert-True ($enumNames.Count -eq 2) 'Crystal Orb runtime should expose exactly two requirement types.'
Assert-True ($enumNames -contains 'Magic' -and $enumNames -contains 'SpecificWeapon') 'Magic/SpecificWeapon requirement types are missing.'
Assert-True (-not ($enumNames -contains 'WeaponPower')) 'WeaponPower remains in the active Crystal Orb requirement model.'

$settings = $null; $processor = $null; $context = $null; $requirements = $null
$selectedSeed = -1
# Pick a deterministic resolver seed that exercises Magic, melee, and every ranged family so the
# byte-level runtime test remains comprehensive without a production TEST_PROFILE.
for($candidateSeed = 1; $candidateSeed -le 20000; $candidateSeed++) {
    $objects = New-TestObjects
    $candidateSettings = $objects[0]; $candidateProcessor = $objects[1]; $candidateContext = $objects[2]
    Set-CrystalOrbFeatureOn $candidateSettings
    $candidateWorkingData = $contextType.GetField('workingData').GetValue($candidateContext)
    $candidateWorkingData.setBool('girlMagicExists', $true)
    $candidateWorkingData.setBool('spriteMagicExists', $true)
    Add-GeneratedOrbEvents $candidateContext $definitions
    $candidateContext.randomFunctional = [Activator]::CreateInstance($randomType, [object[]]@($candidateSeed))
    $candidateRequirements = $requirementsType.GetMethod('resolveAndStore').Invoke(
        $null, [object[]]@($candidateSettings, $candidateContext))
    $candidateWeapons = @($candidateRequirements.Values |
        Where-Object { $_.Type.ToString() -eq 'SpecificWeapon' } | ForEach-Object { [int]$_.Value })
    $candidateMagicCount = @($candidateRequirements.Values |
        Where-Object { $_.Type.ToString() -eq 'Magic' }).Count
    if(($candidateWeapons -contains 5) -and ($candidateWeapons -contains 6) -and
        ($candidateWeapons -contains 7) -and
        (@($candidateWeapons | Where-Object { $_ -lt 5 }).Count -gt 0) -and
        $candidateMagicCount -gt 0) {
        $settings = $candidateSettings; $processor = $candidateProcessor
        $context = $candidateContext; $requirements = $candidateRequirements
        $selectedSeed = $candidateSeed
        break
    }
}
Assert-True ($selectedSeed -gt 0) 'Could not find a seeded mixed runtime requirement set.'

[byte[]]$originalRom = [byte[]]::new(0x400000)
[byte[]]$outputRom = [byte[]]::new(0x400000)
Assert-True ($requirements.Count -eq 14) 'Expected one resolved requirement for every active supported Orb.'
$weaponIds = [System.Collections.Generic.HashSet[int]]::new()
foreach($definition in $definitions) {
    Assert-True ($requirements.ContainsKey($definition.Map)) "Missing requirement for $($definition.Name)."
    $requirement = $requirements[$definition.Map]
    $definition.Type = $requirement.Type.ToString()
    $definition.Value = [int]$requirement.Value
    $definition.Display = $requirementsType.GetMethod('getDisplayName').Invoke($null, [object[]]@($requirement))
    Assert-True ($requirement.OrbEvent -eq $definition.Event) "Wrong individual event for $($definition.Name)."
    Assert-True ($requirement.Type.ToString() -eq $definition.Type) "Wrong requirement type for $($definition.Name)."
    Assert-True ($requirement.Value -eq $definition.Value) "Wrong requirement value for $($definition.Name)."
    $displayName = $requirementsType.GetMethod('getDisplayName').Invoke($null, [object[]]@($requirement))
    Assert-True ($displayName -eq $definition.Display) "Wrong target display for $($definition.Name): '$displayName'."
    Assert-True ($displayName -notmatch 'Weaponpower|WP') "Weapon Power leaked into $($definition.Name) target text."
    if($definition.Type -eq 'SpecificWeapon') { $weaponIds.Add([int]$definition.Value) | Out-Null }
}
foreach($weaponId in $weaponIds) {
    Assert-True ($weaponId -ge 0 -and $weaponId -le 7) "Resolver emitted invalid weapon ID $weaponId."
}

# Targeting and Analyze consume the same resolved requirement object and display helper.
$targetTextMethod = $colorsType.GetMethod('getInjectedOrbTargetText', [Reflection.BindingFlags]'Static,NonPublic')
$analyzeTextMethod = $colorsType.GetMethod('getInjectedOrbAnalyzeText', [Reflection.BindingFlags]'Static,NonPublic')
$orbColorMethod = $colorsType.GetMethod('getOrbColorValue', [Reflection.BindingFlags]'Static,NonPublic')
foreach($definition in $definitions) {
    $targetText = $targetTextMethod.Invoke($null, [object[]]@([byte]$definition.Element, $requirements[$definition.Map]))
    Assert-True ($targetText -eq $definition.Display) "Target-name helper diverged for $($definition.Name)."
    $analyzeText = $analyzeTextMethod.Invoke($null, [object[]]@([byte]$definition.Element, $requirements[$definition.Map]))
    Assert-True ($analyzeText -eq $definition.Display) "Analyze-name helper diverged for $($definition.Name)."
    Assert-True ($analyzeText -eq $targetText) "Analyze and targeting text diverged for $($definition.Name)."
    Assert-True ($targetText.Length -le 28) "Target text exceeds safe length for $($definition.Name)."
    $orbColor = [byte]$orbColorMethod.Invoke($null, [object[]]@([byte]$definition.Element, $requirements[$definition.Map]))
    $expectedColor = if($definition.Type -eq 'SpecificWeapon') { [byte]0x80 } else { [byte]$definition.Element }
    Assert-True ($orbColor -eq $expectedColor) "Orb color category diverged for $($definition.Name)."
}
$inactiveTargetPrefix = $targetTextMethod.Invoke($null, [object[]]@([byte]0x81, $null))
Assert-True ($inactiveTargetPrefix -eq 'Gnome ') 'Inactive/absent requirement no longer preserves vanilla element-plus-Orb naming.'
$inactiveColor = [byte]$orbColorMethod.Invoke($null, [object[]]@([byte]0x81, $null))
Assert-True ($inactiveColor -eq 0x81) 'Inactive/ordinary Orb color no longer preserves its element.'

# Luna ferry dialogue consumes the same resolved requirement object as runtime/name/color.
$lunaDialogueMethod = $supportingEventsType.GetMethod('getLunaOrbRequirementDialogue', [Reflection.BindingFlags]'Static,NonPublic')
$magicDefinition = @($definitions | Where-Object { $_.Type -eq 'Magic' })[0]
$weaponDefinition = @($definitions | Where-Object { $_.Type -eq 'SpecificWeapon' })[0]
$magicRequirement = $requirements[[int]$magicDefinition.Map]
$weaponRequirement = $requirements[[int]$weaponDefinition.Map]
$magicDialogue = [string]$lunaDialogueMethod.Invoke($null, [object[]]@([byte]$magicRequirement.Value, $magicRequirement))
Assert-True ($magicDialogue -eq ("Today's element:`n" + $requirementsType.GetMethod('getDisplayName').Invoke($null, [object[]]@($magicRequirement)) + '!')) 'Magic requirement dialogue diverged from the resolver.'
$weaponDialogue = [string]$lunaDialogueMethod.Invoke($null, [object[]]@([byte]0x87, $weaponRequirement))
Assert-True ($weaponDialogue -eq ("Today's weapon:`n" + $requirementsType.GetMethod('getDisplayName').Invoke($null, [object[]]@($weaponRequirement)) + '!')) 'SpecificWeapon dialogue does not use the resolved weapon name.'
$legacyDialogue = [string]$lunaDialogueMethod.Invoke($null, [object[]]@([byte]0x87, $null))
Assert-True ($legacyDialogue -eq "Today's orb element is:`nLuna!") 'Feature-off Luna dialogue changed.'

# Off mode remains inert and does not resolve requirements or consume its RNG.
$offObjects = New-TestObjects
$offSettings = $offObjects[0]; $offProcessor = $offObjects[1]; $offContext = $offObjects[2]
$offContext.randomFunctional = [Activator]::CreateInstance($randomType, [object[]]@(1234))
[byte[]]$offOutput = [byte[]]::new(0x400000)
Assert-True (-not (Invoke-Processor $offProcessor $offSettings $offContext $originalRom $offOutput)) 'Off mode should skip the Crystal Orb processor.'
Assert-True ($offContext.workingOffset -eq 0x200000) 'Off mode advanced the working offset.'
Assert-True ([Linq.Enumerable]::SequenceEqual($offOutput, [byte[]]::new($offOutput.Length))) 'Off mode wrote ROM bytes.'
Assert-True (($requirementsType.GetMethod('getResolvedRequirements').Invoke($null, [object[]]@($offContext))).Count -eq 0) 'Off mode published custom requirements.'

# Feature-on generation and architecture-B hooks.
$outputRom[0x1D29A] = 0x10
$outputRom[0x1D29B] = 0x10
$outputRom[0x1D22B] = 0xE2
$outputRom[0x1D22C] = 0x20
$outputRom[0x1D22D] = 0xA9
$outputRom[0x1D22E] = 0x01
$outputRom[0x2C529] = 0xE2
$outputRom[0x2C52A] = 0x20
$outputRom[0x2C52B] = 0xB9
$outputRom[0x2C52C] = 0x00
$outputRom[0x2C52D] = 0xD0
Assert-True (Invoke-Processor $processor $settings $context $originalRom $outputRom) 'On mode should emit Crystal Orb routines.'
$workingData = $contextType.GetField('workingData').GetValue($context)
$handlerOffset = $workingData.getInt('crystalOrbWeaponBreakingPhysicalPassCommandOffsetHirom') - 0xC00000
$deferredOffset = $workingData.getInt('crystalOrbWeaponBreakingDeferredRoutineOffsetHirom') - 0xC00000
$proximityOffset = $workingData.getInt('crystalOrbWeaponBreakingRoutineOffsetHirom') - 0xC00000
$rangedOffset = $workingData.getInt('crystalOrbWeaponBreakingRangedProjectileRoutineOffsetHirom') - 0xC00000
$handlerLength = $deferredOffset - $handlerOffset
$deferredLength = $proximityOffset - $deferredOffset
$proximityLength = $rangedOffset - $proximityOffset
$rangedLength = $context.workingOffset - $rangedOffset
Assert-True ($handlerLength -le 512) "Physical-pass handler reservation exceeded: $handlerLength."
Assert-True ($deferredLength -le 512) "Deferred dispatcher reservation exceeded: $deferredLength."
Assert-True ($proximityLength -le 448) "Proximity routine reservation exceeded: $proximityLength."
Assert-True ($rangedLength -le 384) "Ranged projectile routine reservation exceeded: $rangedLength."

Assert-Sequence $outputRom 0xB6A4 4 ([byte[]](0x22)) 'Deferred hook is absent at $C0:B6A4.'
Assert-Sequence $outputRom 0x1D376 4 ([byte[]](0x22)) 'Collision hook is absent at $01:D376.'
Assert-Sequence $outputRom 0x2C529 5 ([byte[]](0x22)) 'Ranged projectile hook is absent at $C2:C529.'
Assert-True ($outputRom[0x2C52D] -eq 0xEA) 'Ranged projectile hook did not NOP the fifth displaced byte.'
Assert-Sequence $outputRom 0x1D22B 4 ([byte[]](0xE2,0x20,0xA9,0x01)) 'Failed speculative $C1:D22B hook was not removed.'
Assert-True ($outputRom[0x1D29A] -eq 0x10 -and $outputRom[0x1D29B] -eq 0x10) '$01:D29A LDA #$1010 was modified.'
Assert-True ($outputRom[0x4FD0] -eq 0) 'Obsolete $C0:4FD0 hook was restored.'
Assert-True ((Find-ByteSequence $outputRom $proximityOffset $proximityLength ([byte[]](0xA9,0xFF,0x1A))) -lt 0) 'Obsolete synthesized $1AFF returned.'

# The tile/proximity routine accepts only melee map/weapon pairs. Exact $FF directional tile
# contacts skip only the body-proximity rectangle; fallback contacts retain the same inclusive
# 40x40 checks. Ranged requirements are deliberately absent and require $C2:C529 below.
Assert-Sequence $outputRom $proximityOffset $proximityLength ([byte[]](0xC9,0xFF,0xF0)) 'Exact $FF contact route is missing.'
Assert-Sequence $outputRom $proximityOffset $proximityLength ([byte[]](0xA3,0x05,0xD0)) 'Exact-contact marker does not bypass only the proximity checks.'
Assert-Sequence $outputRom $proximityOffset $proximityLength ([byte[]](0xB9,0xE7,0xE1,0xC9,0x55)) 'Species $55 restriction is missing.'
Assert-Sequence $outputRom $proximityOffset $proximityLength ([byte[]](0xBD,0x2C,0xE0,0xD0)) 'Vanilla $E02C,X interaction-actor eligibility guard is missing.'
Assert-Sequence $outputRom $proximityOffset $proximityLength ([byte[]](0xBD,0xE8,0xE1)) 'Interaction actor current-weapon read is missing.'
Assert-True ((Find-ByteSequence $outputRom $proximityOffset $proximityLength ([byte[]](0xB9,0xEC,0xE1))) -lt 0) 'Melee detector still treats the Orb $E1EC field as an attacker index.'
Assert-True ((Find-ByteSequence $outputRom $proximityOffset $proximityLength ([byte[]](0xBD,0xE3,0xE1))) -lt 0) 'Melee detector still reads the stale cached weapon at $E1E3,X.'
Assert-True ((Find-ByteSequence $outputRom $proximityOffset $proximityLength ([byte[]](0xBD,0xE8,0xE1,0x29,0x07))) -lt 0) 'Full current weapon ID is incorrectly masked with $07.'
$radiusCompare = [byte[]](0xC9,0x29,0x00)
$firstRadius = Find-ByteSequence $outputRom $proximityOffset $proximityLength $radiusCompare
Assert-True ($firstRadius -ge 0) 'Horizontal inclusive 40px radius is missing.'
Assert-True ((Find-ByteSequence $outputRom ($firstRadius + 3) ($proximityOffset + $proximityLength - $firstRadius - 3) $radiusCompare) -ge 0) 'Vertical inclusive 40px radius is missing.'
Assert-Sequence $outputRom $proximityOffset $proximityLength ([byte[]](0x98,0x8F,0x42,0x04,0x7E,0xAF,0xDC,0x00,0x7E,0x8F,0x44,0x04,0x7E,0xE2,0x20,0xA9,0x01,0x8F,0x41,0x04,0x7E)) 'Target/map are not published before queued state.'
foreach($definition in $definitions) {
    [byte[]]$mapCompare = @(0xC9,[byte]($definition.Map -band 0xFF),[byte](($definition.Map -shr 8) -band 0xFF),0xD0,0x03,0x82)
    $inProximity = (Find-ByteSequence $outputRom $proximityOffset $proximityLength $mapCompare) -ge 0
    $expectedInProximity = $definition.Type -eq 'SpecificWeapon' -and $definition.Value -lt 5
    if($expectedInProximity) {
        Assert-True $inProximity "Melee SpecificWeapon map missing from proximity routing: $($definition.Name)."
    } else {
        Assert-True (-not $inProximity) "Non-melee map incorrectly accepts the tile/proximity path: $($definition.Name)."
    }
}

# Decode every emitted melee full-weapon-ID range and prove each handler contains exactly the
# maps assigned to that family. Ranged requirements must not occur in this routine.
$weaponReadOffset = Find-ByteSequence $outputRom $proximityOffset $proximityLength ([byte[]](0xBD,0xE8,0xE1))
$decodedRanges = @{}
$meleeWeaponIds = @($definitions | Where-Object { $_.Type -eq 'SpecificWeapon' -and $_.Value -lt 5 } | ForEach-Object { $_.Value } | Sort-Object -Unique)
foreach($weaponId in $meleeWeaponIds) {
    $rangeStart = 9 * $weaponId
    $rangeEnd = $rangeStart + 9
    [byte[]]$weaponEntry = @(0xC9,[byte]$rangeStart,0x90,0x07,0xC9,[byte]$rangeEnd,0xB0,0x03,0x82)
    $entryOffset = Find-ByteSequence $outputRom ($weaponReadOffset + 3) 120 $weaponEntry
    Assert-True ($entryOffset -ge 0) "Full-ID range dispatch entry missing for weapon family $weaponId."
    $rangeRecord = @{ Family=$weaponId; Start=[int]$outputRom[$entryOffset + 1]; End=[int]$outputRom[$entryOffset + 5]; Maps=@() }
    $decodedRanges[$weaponId] = $rangeRecord
    $displacement = [int]$outputRom[$entryOffset + 9] + 256 * [int]$outputRom[$entryOffset + 10]
    if($displacement -ge 0x8000) { $displacement -= 0x10000 }
    $groupOffset = $entryOffset + 11 + $displacement
    Assert-Sequence $outputRom $groupOffset 6 ([byte[]](0xC2,0x20,0xAF,0xDC,0x00,0x7E)) "Map handler missing for weapon ID $weaponId."
    $actualMaps = @()
    $cursor = $groupOffset + 6
    while($outputRom[$cursor] -eq 0xC9) {
        Assert-True ($outputRom[$cursor + 3] -eq 0xD0 -and $outputRom[$cursor + 4] -eq 0x03 -and $outputRom[$cursor + 5] -eq 0x82) "Malformed map entry for weapon ID $weaponId."
        $actualMaps += [int]$outputRom[$cursor + 1] + 256 * [int]$outputRom[$cursor + 2]
        $cursor += 8
    }
    $expectedMaps = @($definitions | Where-Object { $_.Type -eq 'SpecificWeapon' -and $_.Value -eq $weaponId -and $_.Value -lt 5 } | ForEach-Object { $_.Map })
    $actualMapText = ($actualMaps | Sort-Object) -join ','
    $expectedMapText = ($expectedMaps | Sort-Object) -join ','
    Assert-True ($actualMapText -eq $expectedMapText) "Wrong map set for weapon ID $weaponId`: expected $expectedMapText; got $actualMapText."
    $rangeRecord.Maps = $actualMaps
}

foreach($weaponId in $meleeWeaponIds) {
    for($fullWeaponId = 9 * $weaponId; $fullWeaponId -lt 9 * $weaponId + 9; $fullWeaponId++) {
        $range = $decodedRanges[$weaponId]
        Assert-True ($fullWeaponId -ge $range.Start -and $fullWeaponId -lt $range.End) "Forge rank ID $fullWeaponId is missing from melee family $weaponId."
    }
}
foreach($definition in $definitions | Where-Object { $_.Type -eq 'SpecificWeapon' -and $_.Value -lt 5 }) {
    foreach($family in $meleeWeaponIds) {
        $accepted = $decodedRanges[$family].Maps -contains $definition.Map
        Assert-True ($accepted -eq ($family -eq $definition.Value)) "$($definition.Name) weapon-family match is not exact for family $family."
    }
}
foreach($definition in $definitions | Where-Object { $_.Type -eq 'SpecificWeapon' -and $_.Value -ge 5 }) {
    [byte[]]$mapCompare = @(0xC9,[byte]($definition.Map -band 0xFF),[byte](($definition.Map -shr 8) -band 0xFF),0xD0,0x03,0x82)
    Assert-True ((Find-ByteSequence $outputRom $proximityOffset $proximityLength $mapCompare) -lt 0) "Ranged requirement leaked into tile/proximity routing: $($definition.Name)."
}

# Model the byte-verified vanilla interaction-owner/current-weapon selection for party-member
# regressions. $C1:D293 enters with X=$0000/$0200/$0400, and vanilla's $C1:D389 guard accepts
# only actors whose $E02C,X player-control number is nonzero. Cached room-entry weapons are
# supplied only to make the stale/current distinction explicit; the fixed routine ignores them.
function Test-InteractionActorWeaponMatch([int]$ActorIndex, [int[]]$PlayerControlNumbers,
    [int[]]$CurrentWeaponIds, [int[]]$CachedWeaponIds, [int]$RequiredFamily) {
    if($ActorIndex -lt 0 -or $ActorIndex -ge 3) { return $false }
    if($PlayerControlNumbers[$ActorIndex] -eq 0) { return $false }
    $actorOffset = $ActorIndex * 0x200
    Assert-True ($actorOffset -eq @(0x0000,0x0200,0x0400)[$ActorIndex]) 'Actor index to player-record offset changed.'
    $fullWeaponId = $CurrentWeaponIds[$ActorIndex]
    return $fullWeaponId -ge (9 * $RequiredFamily) -and $fullWeaponId -lt (9 * ($RequiredFamily + 1))
}

$boyLanceSpriteSword = [int[]]@(67,20,14)
$roomEntrySpriteSwordCache = [int[]]@(67,20,14)
$boyIsInteractionActor = [int[]]@(1,0,0)
Assert-True (-not (Test-InteractionActorWeaponMatch 0 $boyIsInteractionActor $boyLanceSpriteSword $roomEntrySpriteSwordCache 1)) `
    'Boy Lance incorrectly inherits the Sprite room-entry Sword requirement.'
$spriteIsInteractionActor = [int[]]@(0,0,1)
Assert-True (Test-InteractionActorWeaponMatch 2 $spriteIsInteractionActor $boyLanceSpriteSword $roomEntrySpriteSwordCache 1) `
    'Sprite Sword does not satisfy its own Sword requirement.'
Assert-True (-not (Test-InteractionActorWeaponMatch 2 $boyIsInteractionActor $boyLanceSpriteSword $roomEntrySpriteSwordCache 1)) `
    'Uncontrolled Sprite probe bypasses the vanilla $E02C eligibility guard.'

$spriteSwitchedToSword = [int[]]@(67,20,12)
$spriteEnteredWithWhip = [int[]]@(67,20,39)
Assert-True (Test-InteractionActorWeaponMatch 2 $spriteIsInteractionActor $spriteSwitchedToSword $spriteEnteredWithWhip 1) `
    'In-room Whip-to-Sword switch does not take effect immediately.'
$spriteSwitchedToWhip = [int[]]@(67,20,39)
$spriteEnteredWithSword = [int[]]@(67,20,12)
Assert-True (-not (Test-InteractionActorWeaponMatch 2 $spriteIsInteractionActor $spriteSwitchedToWhip $spriteEnteredWithSword 1)) `
    'In-room Sword-to-Whip switch still uses the room-entry Sword cache.'

foreach($family in 0..4) {
    $attacker = $family % 3
    $otherFamily = ($family + 1) % 5
    $current = [int[]]@((9 * $otherFamily + 1),(9 * $otherFamily + 2),(9 * $otherFamily + 3))
    $current[$attacker] = 9 * $family + 8
    $otherPartyCurrent = [int[]]@((9 * $otherFamily + 1),(9 * $otherFamily + 2),(9 * $otherFamily + 3))
    $otherPartyCurrent[($attacker + 1) % 3] = 9 * $family + 2
    $actorControls = [int[]]@(0,0,0)
    $actorControls[$attacker] = 1
    Assert-True (Test-InteractionActorWeaponMatch $attacker $actorControls $current @(0,0,0) $family) `
        "Melee family $family does not match the actual attacker's current weapon."
    Assert-True (-not (Test-InteractionActorWeaponMatch $attacker $actorControls $otherPartyCurrent @(0,0,0) $family)) `
        "Melee family $family was inherited from another party member."
}

# The real ranged path owns $7E:D000 projectile records. X must be one of the three players;
# Y supplies projectile type and moving map coordinates. Projectile types map exactly to the
# three ranged families before map-specific routing.
Assert-Sequence $outputRom $rangedOffset $rangedLength ([byte[]](0xE0,0x00,0x00,0xF0)) 'Projectile path does not accept player 1 as owner.'
Assert-Sequence $outputRom $rangedOffset $rangedLength ([byte[]](0xE0,0x00,0x02,0xF0)) 'Projectile path does not accept player 2 as owner.'
Assert-Sequence $outputRom $rangedOffset $rangedLength ([byte[]](0xE0,0x00,0x04,0xF0)) 'Projectile path does not accept player 3 as owner.'
Assert-Sequence $outputRom $rangedOffset $rangedLength ([byte[]](0xE2,0x20,0xB9,0x00,0xD0)) 'Projectile type is not read from the active $D000,Y record.'
Assert-True ((Find-ByteSequence $outputRom $rangedOffset $rangedLength ([byte[]](0xB9,0xEC,0xE1))) -lt 0) 'Ranged detector was coupled to melee last-attacker state.'
Assert-Sequence $outputRom $rangedOffset $rangedLength ([byte[]](0xBD,0xE7,0xE1,0xC9,0x55)) 'Projectile detector does not require Orb species $55.'
Assert-Sequence $outputRom $rangedOffset $rangedLength ([byte[]](0xB9,0x02,0xD0,0x38,0xFD,0x02,0xE0)) 'Projectile/Orb X comparison is missing.'
Assert-Sequence $outputRom $rangedOffset $rangedLength ([byte[]](0xB9,0x04,0xD0,0x38,0xFD,0x04,0xE0)) 'Projectile/Orb Y comparison is missing.'
$projectileRadiusCompare = [byte[]](0xC9,0x11,0x00)
$firstProjectileRadius = Find-ByteSequence $outputRom $rangedOffset $rangedLength $projectileRadiusCompare
Assert-True ($firstProjectileRadius -ge 0) 'Horizontal inclusive 16px projectile radius is missing.'
Assert-True ((Find-ByteSequence $outputRom ($firstProjectileRadius + 3) ($rangedOffset + $rangedLength - $firstProjectileRadius - 3) $projectileRadiusCompare) -ge 0) 'Vertical inclusive 16px projectile radius is missing.'
Assert-Sequence $outputRom $rangedOffset $rangedLength ([byte[]](0xAF,0x41,0x04,0x7E,0xC9,0x00,0xF0)) 'Repeated projectile overlap is not gated on pending state none.'
Assert-Sequence $outputRom $rangedOffset $rangedLength ([byte[]](0x8A,0x8F,0x42,0x04,0x7E,0xAF,0xDC,0x00,0x7E,0x8F,0x44,0x04,0x7E,0xE2,0x20,0xA9,0x01,0x8F,0x41,0x04,0x7E)) 'Projectile hit does not publish the standard architecture-B binding.'
Assert-Sequence $outputRom $rangedOffset $rangedLength ([byte[]](0xE2,0x20,0xB9,0x00,0xD0,0x6B)) 'Projectile hook does not replay SEP #$20; LDA $D000,Y.'
Assert-True ((Find-ByteSequence $outputRom $rangedOffset $rangedLength ([byte[]](0x9E,0x00,0xD0))) -lt 0) 'Projectile detector unexpectedly destroys the vanilla projectile record.'


$projectileTypesByFamily = @{
    5 = @(1)
    6 = @(3,5)
    7 = @(2)
}
foreach($family in @(5,6,7)) {
    $groupOffsets = @()
    foreach($projectileType in $projectileTypesByFamily[$family]) {
        [byte[]]$typeBranch = @(0xC9,[byte]$projectileType,0xF0)
        $branchOffset = Find-ByteSequence $outputRom $rangedOffset $rangedLength $typeBranch
        Assert-True ($branchOffset -ge 0) "Projectile type $projectileType is missing for ranged family $family."
        $relative = [int]$outputRom[$branchOffset + 3]
        if($relative -ge 0x80) { $relative -= 0x100 }
        $groupOffsets += $branchOffset + 4 + $relative
    }
    Assert-True (($groupOffsets | Sort-Object -Unique).Count -eq 1) "Projectile variants for family $family do not share one map router."
    $groupOffset = $groupOffsets[0]
    Assert-Sequence $outputRom $groupOffset 6 ([byte[]](0xC2,0x20,0xAF,0xDC,0x00,0x7E)) "Map router missing for ranged family $family."
    $actualMaps = @()
    $cursor = $groupOffset + 6
    while($outputRom[$cursor] -eq 0xC9) {
        $actualMaps += [int]$outputRom[$cursor + 1] + 256 * [int]$outputRom[$cursor + 2]
        $cursor += 8
    }
    $expectedMaps = @($definitions | Where-Object { $_.Type -eq 'SpecificWeapon' -and $_.Value -eq $family } | ForEach-Object { $_.Map })
    Assert-True ((($actualMaps | Sort-Object) -join ',') -eq (($expectedMaps | Sort-Object) -join ',')) "Wrong projectile map set for ranged family $family."
}
foreach($definition in $definitions) {
    [byte[]]$mapCompare = @(0xC9,[byte]($definition.Map -band 0xFF),[byte](($definition.Map -shr 8) -band 0xFF),0xD0,0x03,0x82)
    $inRanged = (Find-ByteSequence $outputRom $rangedOffset $rangedLength $mapCompare) -ge 0
    $expectedRanged = $definition.Type -eq 'SpecificWeapon' -and $definition.Value -ge 5
    Assert-True ($inRanged -eq $expectedRanged) "Unexpected ranged projectile route for $($definition.Name)."
}

# The old Earth weapon-smack event contained vanilla dialogue and the temporary PoC later
# redirected it to success event $038. It must now be an intentionally empty replacement.
$supportingEventsSource = Get-Content (Join-Path $PSScriptRoot '..\SoMRandomizer\processing\openworld\events\OpenWorldSupportingEvents.cs') -Raw
Assert-True ($supportingEventsSource -notmatch 'newEvent23a\.Jsr') 'Temporary Earth $23A -> $038 success transfer remains.'

# Deferred dispatch selects individual events for weapon routes only.
foreach($definition in $definitions) {
    [byte[]]$eventSelection = @(0xA9,[byte]($definition.Event -band 0xFF),[byte](($definition.Event -shr 8) -band 0xFF),0x82)
    $isDispatched = (Find-ByteSequence $outputRom $deferredOffset $deferredLength $eventSelection) -ge 0
    if($definition.Type -eq 'SpecificWeapon') {
        Assert-True $isDispatched "Individual event is not dispatched for $($definition.Name)."
    } else {
        Assert-True (-not $isDispatched) "Magic Orb was added to physical deferred dispatch: $($definition.Name)."
    }
}
Assert-True ((Find-ByteSequence $outputRom $deferredOffset $deferredLength ([byte[]](0xA9,0x78,0x05,0x82))) -lt 0) 'Grand Palace still dispatches final event $578 directly.'

# One-shot lifecycle and target/map/actor binding.
$pendingState = $ramType.GetField('CRYSTAL_ORB_PENDING_STATE').GetValue($null)
$pendingTarget = $ramType.GetField('CRYSTAL_ORB_PENDING_TARGET_16BIT').GetValue($null)
$pendingMap = $ramType.GetField('CRYSTAL_ORB_PENDING_MAP_16BIT').GetValue($null)
Assert-True ($pendingState -eq 0x7E0441 -and $pendingTarget -eq 0x7E0442 -and $pendingMap -eq 0x7E0444) 'Unexpected pending RAM layout.'
Assert-True ($context.initialValues[$pendingState] -eq 0) 'Pending state is not initialized to none.'
Assert-Sequence $outputRom $deferredOffset $deferredLength ([byte[]](0xAF,0x44,0x04,0x7E,0xCF,0xDC,0x00,0x7E)) 'Deferred map validation is missing.'
Assert-Sequence $outputRom $deferredOffset $deferredLength ([byte[]](0xAF,0x42,0x04,0x7E,0xCF,0xD4,0x00,0x7E)) 'Armed target binding is missing.'
Assert-Sequence $outputRom $deferredOffset $deferredLength ([byte[]](0xBF,0x00,0xE0,0x7E)) 'Active actor validation is missing.'
Assert-Sequence $outputRom $deferredOffset $deferredLength ([byte[]](0xBF,0xE7,0xE1,0x7E,0xC9,0x55)) 'Deferred species validation is missing.'
Assert-Sequence $outputRom $deferredOffset $deferredLength ([byte[]](0xA9,0x02,0x8F,0x41,0x04,0x7E)) 'Armed transition is missing.'
Assert-Sequence $outputRom $deferredOffset $deferredLength ([byte[]](0x22,0x6D,0xE7,0xC1,0xE2,0x20,0xAF,0xD0,0x00,0x7E,0xD0)) 'Asynchronous event-start validation is missing.'
Assert-Sequence $outputRom $handlerOffset $handlerLength ([byte[]](0xAF,0x41,0x04,0x7E,0xC9,0x02)) 'Physical command does not require armed state.'
Assert-Sequence $outputRom $handlerOffset $handlerLength ([byte[]](0xAF,0x44,0x04,0x7E,0xCF,0xDC,0x00,0x7E)) 'Physical command map binding is missing.'
Assert-Sequence $outputRom $handlerOffset $handlerLength ([byte[]](0xAF,0x42,0x04,0x7E,0xCF,0xD4,0x00,0x7E)) 'Physical command target binding is missing.'
Assert-Sequence $outputRom $handlerOffset $handlerLength ([byte[]](0xA9,0x00,0x8F,0x41,0x04,0x7E)) 'Physical command does not consume/clear state.'

# SpecificWeapon events skip only their original checker call. Magic events remain byte-for-byte
# unchanged, so correct/wrong magic semantics stay owned by their original checker. A non-armed
# (normal Magic) call leaves the checker result at zero; armed physical success validates the
# saved map/actor binding and supplies the accepted checker result.
$events = $contextType.GetField('replacementEvents').GetValue($context)
$eventManager = $contextType.GetField('eventHackMgr').GetValue($context)
$commandIndex = $eventManager.getCommandIndex('crystal orb physical pass')
foreach($definition in $definitions) {
    [byte[]]$actual = $events[$definition.Event].ToArray()
    if($definition.Type -eq 'SpecificWeapon') {
        [byte[]]$prefix = @(0x30,[byte]$definition.Flag,0x00,0x57,$commandIndex)
        for($i = 0; $i -lt $prefix.Length; $i++) {
            Assert-True ($actual[$i] -eq $prefix[$i]) "Wrong weapon-event wrapper for $($definition.Name) at byte $i."
        }
        Assert-True ($actual.Length -eq $definition.Bytes.Length + 3) "Unexpected wrapper length for $($definition.Name)."
        for($i = 2; $i -lt $definition.Bytes.Length; $i++) {
            Assert-True ($actual[$i + 3] -eq $definition.Bytes[$i]) "Original event tail changed for $($definition.Name)."
        }
    } else {
        Assert-True ([Linq.Enumerable]::SequenceEqual($actual, $definition.Bytes)) "Magic event changed for $($definition.Name)."
    }
    if($definition.ContainsKey('GrandFlag')) {
        Assert-Sequence $actual 0 $actual.Length ([byte[]](0x29,[byte]$definition.GrandFlag,0x15,0x78,0x00)) "Grand Palace inline flag mutation changed for $($definition.Name)."
    }
}

# Vanilla-backed Grand Palace weapon events are copied and wrapped; Magic events remain untouched
# and therefore do not need replacement entries.
$vanillaObjects = New-TestObjects
$vanillaSettings = $vanillaObjects[0]; $vanillaProcessor = $vanillaObjects[1]; $vanillaContext = $vanillaObjects[2]
Set-CrystalOrbFeatureOn $vanillaSettings
[byte[]]$vanillaOriginal = [byte[]]::new(0x400000)
[byte[]]$vanillaOutput = [byte[]]::new(0x400000)
$vanillaWorkingData = $contextType.GetField('workingData').GetValue($vanillaContext)
$vanillaWorkingData.setBool('girlMagicExists', $true)
$vanillaWorkingData.setBool('spriteMagicExists', $true)
foreach($definition in $definitions) { $vanillaWorkingData.setInt('orbElement' + $definition.Map, [int]$definition.Element) }
$vanillaContext.randomFunctional = [Activator]::CreateInstance($randomType, [object[]]@($selectedSeed))
Seed-VanillaGrandEvents $vanillaOriginal $definitions
# Non-Grand physical events are normally generated by ElementSwaps and remain supplied here.
$vanillaEvents = $contextType.GetField('replacementEvents').GetValue($vanillaContext)
foreach($definition in $definitions | Where-Object { $_.Type -eq 'SpecificWeapon' -and -not $_.ContainsKey('GrandFlag') }) {
    $vanillaEvents[$definition.Event] = New-ByteList $definition.Bytes
}
Assert-True (Invoke-Processor $vanillaProcessor $vanillaSettings $vanillaContext $vanillaOriginal $vanillaOutput) 'Vanilla-backed Grand Palace generation failed.'
foreach($definition in $definitions | Where-Object { $_.ContainsKey('GrandFlag') }) {
    if($definition.Type -eq 'SpecificWeapon') {
        Assert-True ($vanillaEvents.ContainsKey($definition.Event)) "Vanilla weapon event was not copied/wrapped: $($definition.Name)."
        [byte[]]$actual = $vanillaEvents[$definition.Event].ToArray()
        Assert-Sequence $actual 0 $actual.Length ([byte[]](0x29,[byte]$definition.GrandFlag,0x15,0x78,0x00)) "Vanilla Grand Palace tail changed: $($definition.Name)."
    } else {
        Assert-True (-not $vanillaEvents.ContainsKey($definition.Event)) "Vanilla Magic event was unnecessarily replaced: $($definition.Name)."
    }
}

# Missing/$FF entries, including the Upper Land Flammie guard, produce no active requirement.
$guardObjects = New-TestObjects
$guardSettings = $guardObjects[0]; $guardContext = $guardObjects[2]
Set-CrystalOrbFeatureOn $guardSettings
$guardWorkingData = $contextType.GetField('workingData').GetValue($guardContext)
$guardWorkingData.setBool('girlMagicExists', $true)
$guardWorkingData.setBool('spriteMagicExists', $true)
foreach($definition in $definitions) {
    if($definition.Map -ne 41) { $guardWorkingData.setInt('orbElement' + $definition.Map, [int]$definition.Element) }
}
$guardWorkingData.setInt('orbElement348', 0xFF)
$guardContext.randomFunctional = [Activator]::CreateInstance($randomType, [object[]]@(12345))
$requirementsType.GetMethod('resolveAndStore').Invoke($null, [object[]]@($guardSettings, $guardContext)) | Out-Null
$guardRequirements = $requirementsType.GetMethod('getResolvedRequirements').Invoke($null, [object[]]@($guardContext))
Assert-True (-not $guardRequirements.ContainsKey(41)) 'Upper Land requirement exists without its generated Orb.'
Assert-True (-not $guardRequirements.ContainsKey(348)) '$FF Fire Palace requirement was not removed.'
Assert-True ($guardRequirements.Count -eq 12) 'Absent/$FF guard removed the wrong requirements.'

Write-Output "PASS: seeded per-Orb Magic/SpecificWeapon requirements and architecture B generated correctly with resolver seed $selectedSeed (handler $handlerLength, deferred $deferredLength, proximity $proximityLength, ranged $rangedLength bytes)."
