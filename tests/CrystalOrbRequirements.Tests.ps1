param(
    [string]$AssemblyPath = (Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path $AssemblyPath).Path)
$commonType = $assembly.GetType('SoMRandomizer.config.settings.CommonSettings', $true)
$settingsType = $assembly.GetType('SoMRandomizer.config.settings.OpenWorldSettings', $true)
$contextType = $assembly.GetType('SoMRandomizer.processing.common.RandoContext', $true)
$requirementsType = $assembly.GetType('SoMRandomizer.processing.hacks.openworld.CrystalOrbRequirements', $true)
$locationsType = $assembly.GetType('SoMRandomizer.processing.openworld.randomization.OpenWorldLocations', $true)
$elementSwapsType = $assembly.GetType('SoMRandomizer.processing.ElementSwaps', $true)
$randomType = $assembly.GetType('SoMRandomizer.util.rng.DotNet110Random', $true)
$simulatorType = $assembly.GetType('SoMRandomizer.processing.openworld.randomization.OpenWorldSimulator', $true)
$prizeLocationType = $assembly.GetType('SoMRandomizer.processing.openworld.randomization.PrizeLocation', $true)
$prizeItemType = $assembly.GetType('SoMRandomizer.processing.openworld.randomization.PrizeItem', $true)

$maps = @(291,307,348,345,240,41,35,420,421,422,423,424,425,426)
$defaultElements = @(0x81,0x81,0x83,0x83,0x82,0x85,0x87,0x81,0x82,0x85,0x83,0x84,0x86,0x87)

function Assert-True([bool]$Condition, [string]$Message) {
    if(-not $Condition) { throw $Message }
}

$settingProbe = [Activator]::CreateInstance($settingsType,
    [object[]]@([Activator]::CreateInstance($commonType)))
Assert-True ($settingProbe.getDefault('crystalOrbWeaponBreaking') -eq 'off') `
    'Crystal Orb feature default is not off.'
Assert-True (([string[]]$settingProbe.getOptionsValues('crystalOrbWeaponBreaking') -join ',') -eq 'off,on,weaponOnly') `
    'Crystal Orb serialized options are not exactly off/on/weaponOnly.'
Assert-True (([string[]]$settingProbe.getDisplayValues('crystalOrbWeaponBreaking') -join ',') -eq 'Off,Mixed,Weapon Only') `
    'Crystal Orb display options are not exactly Off/Mixed/Weapon Only.'
$settingProbe.set('crystalOrbWeaponBreaking', 'sequenceBreak')
Assert-True (-not [bool]$requirementsType.GetMethod('isEnabled').Invoke($null, [object[]]@($settingProbe))) `
    'Legacy sequenceBreak literal still enables the production feature.'

function New-Resolved([int]$Seed, [bool]$GirlMagic, [bool]$SpriteMagic,
    [int[]]$Elements = $defaultElements, [bool]$Enabled = $true, [string]$Mode = 'on') {
    $common = [Activator]::CreateInstance($commonType)
    $settings = [Activator]::CreateInstance($settingsType, [object[]]@($common))
    if($Enabled) {
        $settingsType.GetMethod('set', [Type[]]@([string], [string])).Invoke(
            $settings, [object[]]@('crystalOrbWeaponBreaking', $Mode)) | Out-Null
    }
    $context = [Activator]::CreateInstance($contextType)
    $workingData = $contextType.GetField('workingData').GetValue($context)
    $workingData.setBool('girlMagicExists', $GirlMagic)
    $workingData.setBool('spriteMagicExists', $SpriteMagic)
    for($i = 0; $i -lt $maps.Count; $i++) {
        if($Elements[$i] -ge 0) { $workingData.setInt('orbElement' + $maps[$i], $Elements[$i]) }
    }
    $context.randomFunctional = [Activator]::CreateInstance($randomType, [object[]]@($Seed))
    $requirements = $requirementsType.GetMethod('resolveAndStore').Invoke(
        $null, [object[]]@($settings, $context))
    return ,@($settings, $context, $requirements)
}

function Requirement-Signature($Requirements) {
    return (@($Requirements.Keys | Sort-Object | ForEach-Object {
        $r = $Requirements[$_]
        "$_`:$($r.Type)`:$($r.Value)"
    }) -join '|')
}

# Same seed/settings produce the same full result; reads after resolution do not reroll or advance RNG.
$a = New-Resolved 123456 $true $true
$b = New-Resolved 123456 $true $true
Assert-True ((Requirement-Signature $a[2]) -eq (Requirement-Signature $b[2])) 'Same seed/settings diverged.'
$repeat = $requirementsType.GetMethod('resolveAndStore').Invoke($null, [object[]]@($a[0], $a[1]))
Assert-True ((Requirement-Signature $a[2]) -eq (Requirement-Signature $repeat)) 'Repeated resolver call rerolled requirements.'
$nextAfterRepeat = $a[1].randomFunctional.Next()
$nextWithoutRepeat = $b[1].randomFunctional.Next()
Assert-True ($nextAfterRepeat -eq $nextWithoutRepeat) 'Cached resolver call advanced functional RNG.'

$differentFound = $false
foreach($seed in 123457..123470) {
    $other = New-Resolved $seed $true $true
    if((Requirement-Signature $other[2]) -ne (Requirement-Signature $a[2])) {
        $differentFound = $true
        break
    }
}
Assert-True $differentFound 'Different seeds did not produce a different requirement set.'

$sawMagic = $false; $sawWeapon = $false
foreach($requirement in $a[2].Values) {
    if($requirement.Type.ToString() -eq 'Magic') {
        $sawMagic = $true
        Assert-True ($requirement.Value -ge 0x81 -and $requirement.Value -le 0x88) 'Invalid Magic family emitted.'
    } else {
        $sawWeapon = $true
        Assert-True ($requirement.Value -ge 0 -and $requirement.Value -le 7) 'SpecificWeapon ID is outside 0-7.'
    }
}
Assert-True ($sawMagic -and $sawWeapon) 'Selected normal-party test seed does not cover both categories.'

# Weapon Only uses the same cached resolver, but skips the Magic/category roll and selects one
# uniformly distributed weapon ID for every active Orb regardless of generated spell roles.
$weaponOnlyA = New-Resolved 24680 $true $true $defaultElements $true 'weaponOnly'
$weaponOnlyB = New-Resolved 24680 $true $true $defaultElements $true 'weaponOnly'
Assert-True ((Requirement-Signature $weaponOnlyA[2]) -eq (Requirement-Signature $weaponOnlyB[2])) `
    'Weapon Only is not deterministic for identical seed/settings.'
$weaponOnlyRepeat = $requirementsType.GetMethod('resolveAndStore').Invoke(
    $null, [object[]]@($weaponOnlyA[0], $weaponOnlyA[1]))
Assert-True ((Requirement-Signature $weaponOnlyA[2]) -eq (Requirement-Signature $weaponOnlyRepeat)) `
    'Weapon Only cached resolver call rerolled requirements.'
Assert-True ($weaponOnlyA[1].randomFunctional.Next() -eq $weaponOnlyB[1].randomFunctional.Next()) `
    'Weapon Only cached resolver call advanced functional RNG.'

$weaponOnlyIds = [System.Collections.Generic.HashSet[int]]::new()
$roleCases = @(
    [pscustomobject]@{ Girl = $false; Sprite = $false },
    [pscustomobject]@{ Girl = $true; Sprite = $false },
    [pscustomobject]@{ Girl = $false; Sprite = $true },
    [pscustomobject]@{ Girl = $true; Sprite = $true }
)
foreach($roles in $roleCases) {
    foreach($seed in 1..40) {
        $weaponOnly = New-Resolved $seed $roles.Girl $roles.Sprite $defaultElements $true 'weaponOnly'
        Assert-True ($weaponOnly[2].Count -eq 14) 'Weapon Only lost an active Orb.'
        foreach($requirement in $weaponOnly[2].Values) {
            Assert-True ($requirement.Type.ToString() -eq 'SpecificWeapon') `
                'Weapon Only emitted a Magic requirement.'
            Assert-True ($requirement.Value -ge 0 -and $requirement.Value -le 7) `
                'Weapon Only emitted a weapon outside IDs 0-7.'
            $weaponOnlyIds.Add([int]$requirement.Value) | Out-Null
        }
    }
}
Assert-True ((@($weaponOnlyIds) | Sort-Object) -join ',' -eq '0,1,2,3,4,5,6,7') `
    'Weapon Only sampling did not exercise all eight weapon families.'

# Missing and $FF entries are intentionally absent.
$guardElements = [int[]]$defaultElements.Clone()
$guardElements[0] = -1
$guardElements[2] = 0xFF
$guard = New-Resolved 7 $true $true $guardElements
Assert-True (-not $guard[2].ContainsKey(291)) 'Missing Orb received a requirement.'
Assert-True (-not $guard[2].ContainsKey(348)) '$FF/pre-completed Orb received a requirement.'
Assert-True ($guard[2].Count -eq 12) 'Inactive-Orb filtering removed the wrong routes.'

# No Orb-capable role means every retained Orb is SpecificWeapon. Feature Off publishes nothing.
$noCaster = New-Resolved 99 $false $false
Assert-True ($noCaster[2].Count -eq 14) 'Feature-enabled no-caster configuration lost supported Orbs.'
foreach($requirement in $noCaster[2].Values) {
    Assert-True ($requirement.Type.ToString() -eq 'SpecificWeapon') 'No-caster Orb selected Magic.'
}
$off = New-Resolved 99 $false $false $defaultElements $false
Assert-True ($off[2].Count -eq 0) 'Feature Off published custom requirements.'

# The real role model says OGgirl can activate only Salamando, Lumina, and Sylphid Orbs.
$allFamilies = @(0x81,0x82,0x83,0x84,0x85,0x86,0x87,0x88,0x81,0x82,0x83,0x84,0x85,0x86)
$girlMagicValues = [System.Collections.Generic.HashSet[int]]::new()
foreach($seed in 1..100) {
    $girlOnly = New-Resolved $seed $true $false $allFamilies
    foreach($requirement in $girlOnly[2].Values) {
        if($requirement.Type.ToString() -eq 'Magic') {
            $girlMagicValues.Add([int]$requirement.Value) | Out-Null
            Assert-True (@(0x83,0x84,0x85) -contains [int]$requirement.Value) `
                "Girl-only selected unsupported family $($requirement.Value.ToString('X2'))."
        }
    }
}
Assert-True ((@($girlMagicValues) | Sort-Object) -join ',' -eq '131,132,133') `
    'Girl-only tests did not exercise exactly Salamando/Lumina/Sylphid.'

# Verify the feature-gated no-caster existence behavior at the actual ElementSwaps boundary.
function Run-NoCasterElementSwaps([bool]$Enabled) {
    # Use a fresh context because New-Resolved has already populated its synthetic element map.
    $common = [Activator]::CreateInstance($commonType)
    $settings = [Activator]::CreateInstance($settingsType, [object[]]@($common))
    if($Enabled) { $settings.set('crystalOrbWeaponBreaking', 'on') }
    $context = [Activator]::CreateInstance($contextType)
    $workingData = $contextType.GetField('workingData').GetValue($context)
    $workingData.setBool('girlMagicExists', $false)
    $workingData.setBool('spriteMagicExists', $false)
    $context.randomFunctional = [Activator]::CreateInstance($randomType, [object[]]@(500))
    $processor = [Activator]::CreateInstance($elementSwapsType)
    [byte[]]$rom = [byte[]]::new(0x400000)
    $ok = $elementSwapsType.GetMethod('process', [Reflection.BindingFlags]'Instance,NonPublic').Invoke(
        $processor, [object[]]@($rom, $rom, 'no-caster', $settings, $context))
    Assert-True ([bool]$ok) 'ElementSwaps rejected no-caster test context.'
    return ,@($settings, $context)
}
$offElements = Run-NoCasterElementSwaps $false
$onElements = Run-NoCasterElementSwaps $true
$offData = $contextType.GetField('workingData').GetValue($offElements[1])
$onData = $contextType.GetField('workingData').GetValue($onElements[1])
foreach($map in @(291,307,348,345,240,35)) {
    Assert-True ($offData.getInt('orbElement' + $map) -eq 0xFF) "Feature Off changed upstream no-caster map $map."
    Assert-True ($onData.getInt('orbElement' + $map) -ne 0xFF) "Feature On did not retain no-caster map $map."
}
Assert-True ($offData.getInt('orbElement41') -eq 0xFF -and $onData.getInt('orbElement41') -eq 0xFF) `
    'Flammie-off Upper Land production guard changed.'

# Weapon Only uses the same feature-controlled Orb-existence rules as Mixed.
$weaponOnlyCommon = [Activator]::CreateInstance($commonType)
$weaponOnlySettings = [Activator]::CreateInstance($settingsType, [object[]]@($weaponOnlyCommon))
$weaponOnlySettings.set('crystalOrbWeaponBreaking', 'weaponOnly') | Out-Null
$weaponOnlyContext = [Activator]::CreateInstance($contextType)
$weaponOnlyData = $contextType.GetField('workingData').GetValue($weaponOnlyContext)
$weaponOnlyData.setBool('girlMagicExists', $false)
$weaponOnlyData.setBool('spriteMagicExists', $false)
$weaponOnlyContext.randomFunctional = [Activator]::CreateInstance($randomType, [object[]]@(500))
$weaponOnlyProcessor = [Activator]::CreateInstance($elementSwapsType)
[byte[]]$weaponOnlyRom = [byte[]]::new(0x400000)
$weaponOnlyOk = $elementSwapsType.GetMethod('process', [Reflection.BindingFlags]'Instance,NonPublic').Invoke(
    $weaponOnlyProcessor, [object[]]@($weaponOnlyRom, $weaponOnlyRom, 'weapon-only-no-caster',
        $weaponOnlySettings, $weaponOnlyContext))
Assert-True ([bool]$weaponOnlyOk) 'ElementSwaps rejected Weapon Only no-caster context.'
foreach($map in @(291,307,348,345,240,35)) {
    Assert-True ($weaponOnlyData.getInt('orbElement' + $map) -ne 0xFF) `
        "Weapon Only did not retain no-caster map $map."
}
Assert-True ($weaponOnlyData.getInt('orbElement41') -eq 0xFF) `
    'Weapon Only changed the Flammie-off Upper Land production guard.'

# Actual location construction consumes the cached resolver values, including Grand Palace.
$placement = $null
foreach($seed in 1..1000) {
    $candidate = New-Resolved $seed $true $true
    if($candidate[2][291].Type.ToString() -eq 'SpecificWeapon' -and
        @($candidate[2].Values | Where-Object { $_.MapNumber -ge 420 -and $_.MapNumber -le 426 -and $_.Type.ToString() -eq 'Magic' }).Count -gt 0 -and
        @($candidate[2].Values | Where-Object { $_.MapNumber -ge 420 -and $_.MapNumber -le 426 -and $_.Type.ToString() -eq 'SpecificWeapon' }).Count -gt 0) {
        $placement = $candidate
        break
    }
}
Assert-True ($null -ne $placement) 'Could not find mixed placement test seed.'
$placementData = $contextType.GetField('workingData').GetValue($placement[1])
$placementData.set('openWorldGoalShortName', 'manabeast')
$placementData.setBool('manaFortAccessible', $false)
$placementData.setBool('startSolo', $false)
$locations = $locationsType.GetMethod('getForSelectedOptions').Invoke(
    $null, [object[]]@($placement[0], $placement[1]))
$earthDependency = $requirementsType.GetMethod('getPrizeDependency').Invoke(
    $null, [object[]]@($placement[2][291]))
$gnomeLocation = @($locations | Where-Object { $_.locationName -eq 'gnome item 1 (spells)' })[0]
Assert-True ($gnomeLocation.lockedByPrizes -contains $earthDependency) 'Earth location lacks resolved requirement.'
$gpExpectedList = [System.Collections.Generic.List[string]]::new()
foreach($map in 420..426) {
    $dependency = [string]$requirementsType.GetMethod('getPrizeDependency').Invoke(
        $null, [object[]]@($placement[2][$map]))
    if(-not $gpExpectedList.Contains($dependency)) { $gpExpectedList.Add($dependency) }
}
$gpExpected = @($gpExpectedList)
$mechRider = @($locations | Where-Object { $_.locationName -eq 'mech rider 3 (new item)' })[0]
foreach($dependency in $gpExpected) {
    Assert-True ($mechRider.lockedByPrizes -contains $dependency) "Grand Palace lacks $dependency."
}
$gpResolvedMagic = @($gpExpected | Where-Object { $_ -like '* spells' })
$gpActualMagic = @($mechRider.lockedByPrizes | Where-Object { $_ -like '* spells' })
Assert-True ((($gpActualMagic | Sort-Object) -join ',') -eq (($gpResolvedMagic | Sort-Object) -join ',')) `
    'Grand Palace retained obsolete magic-family locks.'

$weaponOnlyPlacement = New-Resolved 314159 $true $true $defaultElements $true 'weaponOnly'
$weaponOnlyPlacementData = $contextType.GetField('workingData').GetValue($weaponOnlyPlacement[1])
$weaponOnlyPlacementData.set('openWorldGoalShortName', 'manabeast')
$weaponOnlyPlacementData.setBool('manaFortAccessible', $false)
$weaponOnlyPlacementData.setBool('startSolo', $false)
$weaponOnlyLocations = $locationsType.GetMethod('getForSelectedOptions').Invoke(
    $null, [object[]]@($weaponOnlyPlacement[0], $weaponOnlyPlacement[1]))
$weaponOnlyMechRider = @($weaponOnlyLocations | Where-Object { $_.locationName -eq 'mech rider 3 (new item)' })[0]
$weaponOnlyGpDependencies = [System.Collections.Generic.HashSet[string]]::new()
foreach($map in 420..426) {
    $requirement = $weaponOnlyPlacement[2][$map]
    Assert-True ($requirement.Type.ToString() -eq 'SpecificWeapon') `
        'Weapon Only Grand Palace emitted Magic.'
    $dependency = [string]$requirementsType.GetMethod('getPrizeDependency').Invoke(
        $null, [object[]]@($requirement))
    $weaponOnlyGpDependencies.Add($dependency) | Out-Null
}
foreach($dependency in $weaponOnlyGpDependencies) {
    Assert-True ($weaponOnlyMechRider.lockedByPrizes -contains $dependency) `
        "Weapon Only Grand Palace lacks $dependency."
}

# The ordinary reachability simulator must enforce the exact resolved dependency. A different
# weapon or spell family cannot clear the gate; the matching starting inventory can.
function Invoke-SingleGateSimulation([string]$Dependency, [int]$StarterWeapon,
    [string]$StartingSpell = '') {
    $common = [Activator]::CreateInstance($commonType)
    $settings = [Activator]::CreateInstance($settingsType, [object[]]@($common))
    $context = [Activator]::CreateInstance($contextType)
    $workingData = $contextType.GetField('workingData').GetValue($context)
    $workingData.setBool('startWithBoy', $true)
    $workingData.setBool('startWithGirl', $true)
    $workingData.setBool('startWithSprite', $false)
    $workingData.set('boyClass', 'OGboy')
    $workingData.set('girlClass', 'OGgirl')
    $workingData.set('spriteClass', 'OGsprite')
    $workingData.set('openWorldGoalShortName', 'manabeast')
    $workingData.setBool('anyMagicExists', $true)
    $workingData.setInt('manaSeedsRequired', 0)
    $workingData.setInt('boyStartWeapon', $StarterWeapon)
    $workingData.setInt('girlStartWeapon', 2)
    $workingData.setInt('spriteStartWeapon', 3)
    if($StartingSpell -ne '') {
        $startingPrizes = [System.Collections.Generic.List[string]]::new()
        $startingPrizes.Add($StartingSpell)
        $contextType.GetField('plandoSettings').GetValue($context)['p_(Start-with)'] = $startingPrizes
    }

    $dictionaryType = [System.Collections.Generic.Dictionary``2].MakeGenericType(
        $prizeLocationType, $prizeItemType)
    $placements = [Activator]::CreateInstance($dictionaryType)
    $locationConstructor = $prizeLocationType.GetConstructor([Type[]]@(
        [string], [int], [int], [int], [int], [string[]], [string[]], [string[]], [double]
    ))
    $prizeConstructor = $prizeItemType.GetConstructor([Type[]]@(
        [string], [string], [byte[]], [string], [byte], [double]
    ))
    $location = $locationConstructor.Invoke([object[]]@(
        'resolved Orb gate', -1, -1, 0, 0, [string[]]@(), [string[]]@(),
        [string[]]@($Dependency), 1.0))
    $prize = $prizeConstructor.Invoke([object[]]@(
        'nothing', '', [byte[]]@(), '', [byte]0, 1.0))
    $placements.Add($location, $prize)
    return $simulatorType.GetMethod('runSimulation').Invoke(
        $null, [object[]]@($placements, $settings, $context)).score
}

Assert-True ((Invoke-SingleGateSimulation 'bow' 5) -eq 1) `
    'Matching resolved weapon was not initially reachable.'
Assert-True ((Invoke-SingleGateSimulation 'bow' 6) -eq -1) `
    'Different weapon incorrectly satisfied resolved weapon dependency.'
Assert-True ((Invoke-SingleGateSimulation 'salamando spells' 0 'Salamando') -eq 1) `
    'Matching usable spell family was not initially reachable.'
Assert-True ((Invoke-SingleGateSimulation 'salamando spells' 0 'Gnome') -eq -1) `
    'Different spell family incorrectly satisfied resolved magic dependency.'

Write-Output 'PASS: seeded Crystal Orb requirements are cached, role-aware, feature-gated, and enforced by Open World reachability.'
