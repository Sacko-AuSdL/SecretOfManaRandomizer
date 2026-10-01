param(
    [string]$AssemblyPath = (Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe'),
    [string]$SourceRom = 'D:\views\tools\bots\Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc'
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path $AssemblyPath).Path)
[byte[]]$originalRom = [IO.File]::ReadAllBytes((Resolve-Path $SourceRom).Path)
$commonType = $assembly.GetType('SoMRandomizer.config.settings.CommonSettings', $true)
$settingsType = $assembly.GetType('SoMRandomizer.config.settings.OpenWorldSettings', $true)
$contextType = $assembly.GetType('SoMRandomizer.processing.common.RandoContext', $true)
$startType = $assembly.GetType('SoMRandomizer.processing.openworld.OpenWorldStartingLocation', $true)
$newGameType = $assembly.GetType('SoMRandomizer.processing.openworld.events.NewGameEvent', $true)
$introType = $assembly.GetType('SoMRandomizer.processing.openworld.events.FlammieLogicIntroEvent', $true)
$swordType = $assembly.GetType('SoMRandomizer.processing.openworld.events.SwordGrabEvent', $true)
$requirementsType = $assembly.GetType('SoMRandomizer.processing.hacks.openworld.CrystalOrbRequirements', $true)
$vanillaEventUtilType = $assembly.GetType('SoMRandomizer.processing.common.VanillaEventUtil', $true)
$mapChangesType = $assembly.GetType('SoMRandomizer.processing.openworld.events.OpenWorldSupportingMapChanges', $true)
$eventScriptType = $assembly.GetType('SoMRandomizer.processing.common.structure.EventScript', $true)
$cannonModelType = $assembly.GetType('SoMRandomizer.processing.openworld.cannon.CannonTravelModel', $true)
$cannonRegionsType = $assembly.GetType('SoMRandomizer.processing.openworld.cannon.CannonTravelRegions', $true)
$regionType = $assembly.GetType('SoMRandomizer.processing.openworld.cannon.CannonTravelRegion', $true)
$getBytesDelay = $vanillaEventUtilType.GetMethods() | Where-Object {
    $_.Name -eq 'getBytesDelay' -and $_.GetParameters().Count -eq 3
} | Select-Object -First 1

function Assert-True([bool]$Condition, [string]$Message) {
    if(-not $Condition) { throw $Message }
}

function Assert-Bytes([byte[]]$Expected, [byte[]]$Actual, [string]$Message) {
    Assert-True ([Linq.Enumerable]::SequenceEqual($Expected, $Actual)) $Message
}

function Find-Bytes([byte[]]$Data, [byte[]]$Pattern) {
    for($i = 0; $i -le $Data.Length - $Pattern.Length; $i++) {
        $match = $true
        for($j = 0; $j -lt $Pattern.Length; $j++) {
            if($Data[$i + $j] -ne $Pattern[$j]) { $match = $false; break }
        }
        if($match) { return $i }
    }
    return -1
}

function New-Case([bool]$FlammieInLogic, [string]$Location = 'default',
    [string]$Goal = 'manabeast', [bool]$ShowOrbRequirement = $false) {
    $common = [Activator]::CreateInstance($commonType)
    $settings = [Activator]::CreateInstance($settingsType, [object[]]@($common))
    $settings.set('opFlammieDrumInLogic', $(if($FlammieInLogic) { 'yes' } else { 'no' })) | Out-Null
    $settings.set('opStartingLocation', $Location) | Out-Null
    $settings.set('showUpperLandOrbRequirement',
        $(if($ShowOrbRequirement) { 'on' } else { 'off' })) | Out-Null
    $context = [Activator]::CreateInstance($contextType)
    $context.workingData.set('openWorldGoalShortName', $Goal)
    $context.randomFunctional = [Random]::new(12345)
    return @($common, $settings, $context)
}

function Invoke-Processor([Type]$Type, $Settings, $Context, [byte[]]$Output) {
    $processor = [Activator]::CreateInstance($Type, $true)
    $method = $Type.GetMethod('process', [Reflection.BindingFlags]'Instance,NonPublic')
    return [bool]$method.Invoke($processor, [object[]]@($originalRom, $Output, 'Starting-Location-Test', $Settings, $Context))
}

function Get-EventBytes($Context, [int]$EventId) {
    return [byte[]]$Context.replacementEvents[$EventId].ToArray()
}

function Prepare-IntroEvent($Context) {
    $Context.replacementEvents[0x106] = [Activator]::CreateInstance($eventScriptType)
}

function Prepare-SwordData($Context) {
    $Context.workingData.setBool('startWithBoy', $true)
    $Context.workingData.setBool('startWithGirl', $false)
    $Context.workingData.setBool('startWithSprite', $false)
    $Context.workingData.set('startingCharacter', 'boy')
}

function Set-UpperLandOrbCache($Settings, $Context, [string]$Mode,
    [int]$RequirementType, [int]$RequirementValue, [int]$ElementValue = 0x81) {
    $Settings.set('crystalOrbWeaponBreaking', $Mode) | Out-Null
    $Context.workingData.setInt('orbElement41', $ElementValue)
    if($Mode -ne 'off') {
        $Context.workingData.setInt('crystalOrbRequirementsResolved', 1)
        $Context.workingData.setInt('crystalOrbRequirementType41', $RequirementType)
        $Context.workingData.setInt('crystalOrbRequirementValue41', $RequirementValue)
    }
}

function Get-TimedDialogueBox([string]$Text) {
    $result = [Collections.Generic.List[byte]]::new()
    $result.Add(0x50)
    foreach($b in $getBytesDelay.Invoke($null, @($Text, [byte]10, 0))) {
        $result.Add([byte]$b)
    }
    $result.Add(0x28)
    $result.Add(0x0A)
    $result.Add(0x51)
    return $result.ToArray()
}

function Build-SwordEvent($Case) {
    Prepare-SwordData $Case[2]
    Assert-True (Invoke-Processor $swordType $Case[1] $Case[2] ([byte[]]$originalRom.Clone())) `
        'Sword/startup event did not run.'
    return Get-EventBytes $Case[2] 0x103
}

Assert-True (([Activator]::CreateInstance($settingsType, [object[]]@([Activator]::CreateInstance($commonType))).getDefault('opStartingLocation')) -eq 'default') `
    'Starting Location default is not Default.'
$optionSettings = [Activator]::CreateInstance($settingsType, [object[]]@([Activator]::CreateInstance($commonType)))
Assert-True ([Linq.Enumerable]::SequenceEqual(
    [string[]]$optionSettings.getOptionsValues('opStartingLocation'),
    [string[]]@('default','kakkara'))) 'Starting Location serialized values are incorrect.'
Assert-True ([Linq.Enumerable]::SequenceEqual(
    [string[]]$optionSettings.getDisplayValues('opStartingLocation'),
    [string[]]@('Default','Kakkara'))) 'Starting Location display values are incorrect.'
Assert-True ($optionSettings.getDefault('showUpperLandOrbRequirement') -eq 'off') `
    'Show Upper Land Orb Requirement default is not Off.'
Assert-True ([Linq.Enumerable]::SequenceEqual(
    [string[]]$optionSettings.getOptionsValues('showUpperLandOrbRequirement'),
    [string[]]@('off','on'))) 'Orb startup information serialized values are incorrect.'
Assert-True ([Linq.Enumerable]::SequenceEqual(
    [string[]]$optionSettings.getDisplayValues('showUpperLandOrbRequirement'),
    [string[]]@('Off','On'))) 'Orb startup information display values are incorrect.'

$default = New-Case $true 'default'
$kakkara = New-Case $true 'kakkara'
$ignored = New-Case $false 'kakkara'
$christmas = New-Case $true 'kakkara' 'xmas2020b'
$useKakkara = $startType.GetMethod('useKakkara')
$getRegion = $startType.GetMethod('getStartingRegion')
Assert-True (-not [bool]$useKakkara.Invoke($null, @($default[1],$default[2]))) 'Default unexpectedly selected Kakkara.'
Assert-True ([bool]$useKakkara.Invoke($null, @($kakkara[1],$kakkara[2]))) 'Kakkara was not selected with Flammie in logic.'
Assert-True (-not [bool]$useKakkara.Invoke($null, @($ignored[1],$ignored[2]))) 'Kakkara altered the pedestal start with Flammie out of logic.'
Assert-True (-not [bool]$useKakkara.Invoke($null, @($christmas[1],$christmas[2]))) 'Kakkara replaced the Christmas start.'
Assert-True ($getRegion.Invoke($null, @($kakkara[1],$kakkara[2])).ToString() -eq 'Kakkara') 'Simulator start region is not Kakkara.'
Assert-True ($getRegion.Invoke($null, @($default[1],$default[2])).ToString() -eq 'PotosArea') 'Default simulator start region changed.'
Assert-True ($getRegion.Invoke($null, @($christmas[1],$christmas[2])).ToString() -eq 'IceCountry') 'Christmas simulator start region changed.'

# Door $228 is map 69's existing south-desert entrance into map 89 at (29,36).
# Its $81 source-exit transition is intentionally not copied to the cold-start door.
[int]$doorOffset = 0x83000
[byte[]]$sourceDoor = $originalRom[($doorOffset + 0x228 * 4)..($doorOffset + 0x228 * 4 + 3)]
Assert-Bytes ([byte[]](0x59,0x3A,0x48,0x81)) $sourceDoor 'Kakkara source door bytes changed unexpectedly.'

[byte[]]$defaultRom = [byte[]]$originalRom.Clone()
Assert-True (Invoke-Processor $mapChangesType $default[1] $default[2] $defaultRom) 'Default map changes did not run.'
[byte[]]$defaultDoor = $defaultRom[($doorOffset + 0x82 * 4)..($doorOffset + 0x82 * 4 + 3)]
Assert-Bytes ([byte[]](0x02,0x71,0x1B,0x00)) $defaultDoor 'Default no longer starts in Potos elder house at map 258, (56,13).'

[byte[]]$kakkaraRom = [byte[]]$originalRom.Clone()
Assert-True (Invoke-Processor $mapChangesType $kakkara[1] $kakkara[2] $kakkaraRom) 'Kakkara map changes did not run.'
[byte[]]$kakkaraDoor = $kakkaraRom[($doorOffset + 0x82 * 4)..($doorOffset + 0x82 * 4 + 3)]
Assert-Bytes ([byte[]](0x59,0x3A,0x48,0x00)) $kakkaraDoor 'Start door $82 does not use the Kakkara destination with startup-safe transition semantics.'
[byte[]]$unchangedSourceDoor = $kakkaraRom[($doorOffset + 0x228 * 4)..($doorOffset + 0x228 * 4 + 3)]
Assert-Bytes $sourceDoor $unchangedSourceDoor 'The normal desert-to-Kakkara door $228 was modified.'

[byte[]]$ignoredRom = [byte[]]$originalRom.Clone()
Assert-True (Invoke-Processor $mapChangesType $ignored[1] $ignored[2] $ignoredRom) 'Flammie-out-of-logic map changes did not run.'
[byte[]]$originalDoor82 = $originalRom[($doorOffset + 0x82 * 4)..($doorOffset + 0x82 * 4 + 3)]
[byte[]]$ignoredDoor82 = $ignoredRom[($doorOffset + 0x82 * 4)..($doorOffset + 0x82 * 4 + 3)]
Assert-Bytes $originalDoor82 $ignoredDoor82 'Kakkara changed the pedestal-path start door while Flammie was out of logic.'

# New game still enters through door $82 and hands off to the common event $106.
foreach($case in @($default,$kakkara)) {
    [byte[]]$out = [byte[]]$originalRom.Clone()
    Assert-True (Invoke-Processor $newGameType $case[1] $case[2] $out) 'New-game event did not run.'
    [byte[]]$event400 = Get-EventBytes $case[2] 0x400
    Assert-True ((Find-Bytes $event400 ([byte[]](0x18,0x82))) -ge 0) 'Flammie-in-logic start no longer uses door $82.'
    Assert-True ((Find-Bytes $event400 ([byte[]](0x11,0x06))) -ge 0) 'New game no longer continues through common event $106.'
}
[byte[]]$ignoredOut = [byte[]]$originalRom.Clone()
Assert-True (Invoke-Processor $newGameType $ignored[1] $ignored[2] $ignoredOut) 'Pedestal new-game event did not run.'
Assert-True ((Find-Bytes (Get-EventBytes $ignored[2] 0x400) ([byte[]](0x18,0x00))) -ge 0) `
    'Flammie-out-of-logic Kakkara selection no longer preserves vanilla start door $00.'

# Kakkara uses its existing music event; both variants continue through the exact same
# flag initialization and starter-weapon/common-inventory events.
Prepare-IntroEvent $default[2]
Prepare-IntroEvent $kakkara[2]
Assert-True (Invoke-Processor $introType $default[1] $default[2] ([byte[]]$originalRom.Clone())) 'Default intro did not run.'
Assert-True (Invoke-Processor $introType $kakkara[1] $kakkara[2] ([byte[]]$originalRom.Clone())) 'Kakkara intro did not run.'
[byte[]]$defaultIntro = Get-EventBytes $default[2] 0x106
[byte[]]$kakkaraIntro = Get-EventBytes $kakkara[2] 0x106
Assert-True ((Find-Bytes $defaultIntro ([byte[]](0x40,0x01,0x11,0x12,0x8F))) -ge 0) 'Default startup music command changed.'
Assert-True ((Find-Bytes $kakkaraIntro ([byte[]](0x27,0xC2))) -ge 0) 'Kakkara startup did not call existing music event $7C2.'
foreach($intro in @($defaultIntro,$kakkaraIntro)) {
    Assert-True ((Find-Bytes $intro ([byte[]](0x21,0x07))) -ge 0) 'Startup skipped common event-flag initialization $107.'
    Assert-True ((Find-Bytes $intro ([byte[]](0x11,0x03))) -ge 0) 'Startup skipped common starter-weapon event $103.'
}

Prepare-SwordData $default[2]
Prepare-SwordData $kakkara[2]
Assert-True (Invoke-Processor $swordType $default[1] $default[2] ([byte[]]$originalRom.Clone())) 'Default common initialization did not run.'
Assert-True (Invoke-Processor $swordType $kakkara[1] $kakkara[2] ([byte[]]$originalRom.Clone())) 'Kakkara common initialization did not run.'
[byte[]]$defaultCommon = Get-EventBytes $default[2] 0x103
[byte[]]$kakkaraCommon = Get-EventBytes $kakkara[2] 0x103
Assert-Bytes $defaultCommon $kakkaraCommon 'Kakkara changed common startup initialization.'
Assert-True ((Find-Bytes $kakkaraCommon ([byte[]](0x12,0x34,0x56,0x78,0x00))) -ge 0) 'Starter-weapon injection was removed.'
Assert-True ((Find-Bytes $kakkaraCommon ([byte[]](0x1E,0x46))) -ge 0) 'Magic Rope is not granted.'
Assert-True ((Find-Bytes $kakkaraCommon ([byte[]](0x1E,0x47))) -lt 0) 'Flammie Drum was granted despite being in logic.'

# The opt-in startup information reports the already-cached Upper Land Orb requirement
# immediately after the completion message for both Potos and Kakkara. No resolver or
# RNG call is made here.
[byte[]]$okayBox = Get-TimedDialogueBox 'Okay you can play now '

$offMagic = New-Case $true 'kakkara' 'manabeast' $true
Set-UpperLandOrbCache $offMagic[1] $offMagic[2] 'off' 0 0x81 0x81
[byte[]]$offMagicEvent = Build-SwordEvent $offMagic
[byte[]]$gnomeBox = Get-TimedDialogueBox "Upper Land Orb:`nGnome"
[int]$okayIndex = Find-Bytes $offMagicEvent $okayBox
[int]$gnomeIndex = Find-Bytes $offMagicEvent $gnomeBox
Assert-True ($okayIndex -ge 0) 'Kakkara startup lost the existing completion dialogue.'
Assert-True ($gnomeIndex -eq ($okayIndex + $okayBox.Length)) `
    'Upper Land Orb information was not inserted immediately after the completion dialogue.'

$defaultWithOrb = New-Case $true 'default' 'manabeast' $true
Set-UpperLandOrbCache $defaultWithOrb[1] $defaultWithOrb[2] 'off' 0 0x81 0x81
[byte[]]$defaultWithOrbEvent = Build-SwordEvent $defaultWithOrb
Assert-True ((Find-Bytes $defaultWithOrbEvent $gnomeBox) -ge 0) `
    'Default/Potos startup did not receive the enabled Upper Land Orb message.'

$kakkaraOptionOff = New-Case $true 'kakkara'
Set-UpperLandOrbCache $kakkaraOptionOff[1] $kakkaraOptionOff[2] 'off' 0 0x81 0x81
Assert-True ((Find-Bytes (Build-SwordEvent $kakkaraOptionOff) $gnomeBox) -lt 0) `
    'Option Off emitted the Upper Land Orb message in Kakkara.'
$defaultOptionOff = New-Case $true 'default'
Set-UpperLandOrbCache $defaultOptionOff[1] $defaultOptionOff[2] 'off' 0 0x81 0x81
Assert-True ((Find-Bytes (Build-SwordEvent $defaultOptionOff) $gnomeBox) -lt 0) `
    'Option Off emitted the Upper Land Orb message in Potos.'
$noFlammieLogic = New-Case $false 'kakkara' 'manabeast' $true
Set-UpperLandOrbCache $noFlammieLogic[1] $noFlammieLogic[2] 'off' 0 0x81 0x81
Assert-True ((Find-Bytes (Build-SwordEvent $noFlammieLogic) $gnomeBox) -lt 0) `
    'Flammie-out-of-logic pedestal startup emitted the Orb information message.'

$mixedMagic = New-Case $true 'kakkara' 'manabeast' $true
Set-UpperLandOrbCache $mixedMagic[1] $mixedMagic[2] 'on' 0 0x82 0x82
[byte[]]$mixedMagicEvent = Build-SwordEvent $mixedMagic
Assert-True ((Find-Bytes $mixedMagicEvent (Get-TimedDialogueBox "Upper Land Orb:`nUndine")) -ge 0) `
    'Mixed mode did not display its cached Magic requirement.'

$mixedWeapon = New-Case $true 'kakkara' 'manabeast' $true
Set-UpperLandOrbCache $mixedWeapon[1] $mixedWeapon[2] 'on' 1 5 0x83
[byte[]]$mixedWeaponEvent = Build-SwordEvent $mixedWeapon
[byte[]]$bowBox = Get-TimedDialogueBox "Upper Land Orb:`nBow"
Assert-True ((Find-Bytes $mixedWeaponEvent $bowBox) -ge 0) `
    'Mixed mode did not display its cached weapon requirement.'

$weaponOnly = New-Case $true 'kakkara' 'manabeast' $true
Set-UpperLandOrbCache $weaponOnly[1] $weaponOnly[2] 'weaponOnly' 1 1 0x84
[byte[]]$weaponOnlyEvent = Build-SwordEvent $weaponOnly
Assert-True ((Find-Bytes $weaponOnlyEvent (Get-TimedDialogueBox "Upper Land Orb:`nSword")) -ge 0) `
    'Weapon Only mode did not display its cached weapon requirement.'

$inactiveOrb = New-Case $true 'kakkara' 'manabeast' $true
Set-UpperLandOrbCache $inactiveOrb[1] $inactiveOrb[2] 'off' 0 0x81 0xFF
[byte[]]$inactiveOrbEvent = Build-SwordEvent $inactiveOrb
Assert-Bytes $kakkaraCommon $inactiveOrbEvent `
    'Inactive/precompleted Upper Land Orb emitted a misleading requirement message.'

# The startup display must equal the same immutable requirement reconstructed for logic.
$getResolved = $requirementsType.GetMethod('getResolvedRequirements')
$getDisplayName = $requirementsType.GetMethod('getDisplayName')
$getStartupDisplay = $swordType.GetMethod('getUpperLandOrbRequirementDisplayName',
    [Reflection.BindingFlags]'Static,NonPublic')
$cachedRequirements = $getResolved.Invoke($null, @($mixedWeapon[2]))
$cachedRequirement = $cachedRequirements[[int]41]
$cachedDisplay = [string]$getDisplayName.Invoke($null, @($cachedRequirement))
$startupDisplay = [string]$getStartupDisplay.Invoke($null, @($mixedWeapon[1],$mixedWeapon[2]))
Assert-True ($startupDisplay -eq $cachedDisplay -and $startupDisplay -eq 'Bow') `
    'Startup message diverged from the simulator/shared cached Upper Land requirement.'

# Cannon mode changes neither the cached requirement nor the generated message.
foreach($mode in @('off','open','shuffle','chaos')) {
    $cannonCase = New-Case $true 'kakkara' 'manabeast' $true
    $cannonCase[1].set('cannonTravelRandomization',$mode) | Out-Null
    Set-UpperLandOrbCache $cannonCase[1] $cannonCase[2] 'on' 1 5 0x83
    [byte[]]$cannonEvent = Build-SwordEvent $cannonCase
    Assert-True ((Find-Bytes $cannonEvent $bowBox) -ge 0) `
        "Cannon mode $mode changed or removed the cached Upper Land requirement message."
}

# Building the message must not advance the functional RNG.
$rngCase = New-Case $true 'kakkara' 'manabeast' $true
$rngCase[2].randomFunctional = [Random]::new(24680)
Set-UpperLandOrbCache $rngCase[1] $rngCase[2] 'on' 1 5 0x83
[void](Build-SwordEvent $rngCase)
$controlRng = [Random]::new(24680)
Assert-True ($rngCase[2].randomFunctional.Next() -eq $controlRng.Next()) `
    'Kakkara Upper Land requirement message consumed functional RNG.'

# Region reachability starts from Kakkara, not Potos. An empty network proves Potos is
# not implicit; the untouched vanilla route graph then reaches it only via actual routes.
$emptyContext = [Activator]::CreateInstance($contextType)
$emptyNetwork = $cannonModelType.GetMethod('getResolvedNetwork').Invoke($null, @($emptyContext))
$getReachable = $cannonRegionsType.GetMethod('getReachableRegions')
$kakkaraRegion = [Enum]::Parse($regionType, 'Kakkara')
$emptyReachable = $getReachable.Invoke($null, @($emptyNetwork,$kakkaraRegion,$false,$false))
Assert-True ($emptyReachable.Contains($kakkaraRegion)) 'Kakkara is not initially reachable.'
Assert-True (-not $emptyReachable.Contains([Enum]::Parse($regionType,'PotosArea'))) 'Potos was implicitly reachable without a route.'
$vanillaNetwork = $cannonModelType.GetMethod('getVanillaRegionNetwork').Invoke($null, @())
$vanillaBlocked = $getReachable.Invoke($null, @($vanillaNetwork,$kakkaraRegion,$false,$false))
Assert-True (-not $vanillaBlocked.Contains([Enum]::Parse($regionType,'PotosArea'))) `
    'Untouched Cannon routes incorrectly make Potos reachable from Kakkara.'
$vanillaOpen = $getReachable.Invoke($null, @($vanillaNetwork,$kakkaraRegion,$false,$true))
Assert-True ($vanillaOpen.Contains([Enum]::Parse($regionType,'PotosArea'))) `
    'Opening the real Matango-to-Upper-Land traversal no longer makes Potos reachable.'

foreach($mode in @('off','open','shuffle','chaos')) {
    $case = New-Case $true 'kakkara'
    $case[1].set('cannonTravelRandomization',$mode) | Out-Null
    if($mode -eq 'off') {
        $network = $cannonModelType.GetMethod('getVanillaRegionNetwork').Invoke($null, @())
    } else {
        $network = $cannonModelType.GetMethod('resolveAndStore').Invoke($null, @($case[1],$case[2]))
    }
    $reachable = $getReachable.Invoke($null, @($network,$kakkaraRegion,$false,$true))
    Assert-True ($reachable.Contains($kakkaraRegion)) "Cannon mode $mode lost the Kakkara starting region."
}

Write-Output 'PASS: Potos/Kakkara optionally show the cached Upper Land Orb requirement; setting Off, pedestal starts, RNG, Cannon modes, door $228, common initialization, and simulator reachability remain unchanged.'
