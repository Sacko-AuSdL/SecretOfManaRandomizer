param(
    [string]$AssemblyPath = (Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path $AssemblyPath).Path)
$hintType = $assembly.GetType('SoMRandomizer.processing.openworld.randomization.OpenWorldHints', $true)
$requirementType = $assembly.GetType('SoMRandomizer.processing.hacks.openworld.CrystalOrbRequirement', $true)
$requirementEnum = $assembly.GetType('SoMRandomizer.processing.hacks.openworld.CrystalOrbRequirementType', $true)
$contextType = $assembly.GetType('SoMRandomizer.processing.common.RandoContext', $true)
$randomType = $assembly.GetType('SoMRandomizer.util.rng.DotNet110Random', $true)

function Assert-True([bool]$Condition, [string]$Message) {
    if(-not $Condition) { throw $Message }
}

function New-Requirement([int]$Map, [string]$Kind, [byte]$Value) {
    $ctor = $requirementType.GetConstructors([Reflection.BindingFlags]'Instance,NonPublic')[0]
    $enumValue = [Enum]::Parse($requirementEnum, $Kind)
    return $ctor.Invoke([object[]]@($Map, 0x570, 'hint test', $enumValue, $Value))
}

$compositionMethod = $hintType.GetMethod('getGrandPalaceCompositionHint', [Reflection.BindingFlags]'Static,NonPublic')
$candidateMethod = $hintType.GetMethod('getGrandPalaceHintCandidates', [Reflection.BindingFlags]'Static,NonPublic')
$dependencyMethod = $hintType.GetMethod('getGrandPalaceDependencyHint', [Reflection.BindingFlags]'Static,NonPublic')
$cacheMethod = $hintType.GetMethod('getCachedGrandPalaceRequirements', [Reflection.BindingFlags]'Static,NonPublic')

$requirementListType = [System.Collections.Generic.List``1].MakeGenericType($requirementType)
$requirements = [Activator]::CreateInstance($requirementListType)
$requirements.Add((New-Requirement 420 Magic 0x81))
$requirements.Add((New-Requirement 421 Magic 0x81))
$requirements.Add((New-Requirement 422 SpecificWeapon 1))
$requirements.Add((New-Requirement 423 SpecificWeapon 1))
$requirements.Add((New-Requirement 424 SpecificWeapon 4))
[object[]]$oneArg = [object[]]::new(1)
$oneArg[0] = $requirements
$composition = [string]$compositionMethod.Invoke($null, $oneArg)
Assert-True ($composition -eq 'Grand Palace requires 1 magic type and 2 weapons.') `
    "Unique requirement composition changed: '$composition'."

$singular = [Activator]::CreateInstance($requirementListType)
$singular.Add((New-Requirement 420 Magic 0x81))
$singular.Add((New-Requirement 421 SpecificWeapon 4))
$oneArg[0] = $singular
$singularText = [string]$compositionMethod.Invoke($null, $oneArg)
Assert-True ($singularText -eq 'Grand Palace requires 1 magic type and 1 weapon.') `
    'Grand Palace singular grammar is incorrect.'

$oneArg[0] = [byte[]](0x81,0x83,0x83)
$candidates = $candidateMethod.Invoke($null, $oneArg)
Assert-True ($candidates.Count -eq 10) 'Hint candidate pool did not deduplicate Magic or include all 8 weapons.'
$weaponNames = @($candidates | Where-Object { $_.Type.ToString() -eq 'SpecificWeapon' } |
    ForEach-Object { $_.Value } | Sort-Object)
Assert-True (($weaponNames -join ',') -eq '0,1,2,3,4,5,6,7') 'Weapon hint candidates are incomplete.'

$magic = New-Requirement 420 Magic 0x81
$sword = New-Requirement 421 SpecificWeapon 1
$requiredHints = [Activator]::CreateInstance($requirementListType)
$requiredHints.Add($magic)
$requiredHints.Add($sword)
[object[]]$twoArgs = [object[]]::new(2)
$twoArgs[0] = $magic; $twoArgs[1] = $requiredHints
Assert-True ([string]$dependencyMethod.Invoke($null, $twoArgs) -eq
    'Needed for grand palace: Gnome') 'Magic needed hint changed.'
$twoArgs[0] = $sword
Assert-True ([string]$dependencyMethod.Invoke($null, $twoArgs) -eq
    'Needed for grand palace: Sword') 'Weapon needed hint is missing.'
$bow = New-Requirement 422 SpecificWeapon 5
$twoArgs[0] = $bow
Assert-True ([string]$dependencyMethod.Invoke($null, $twoArgs) -eq
    'Not needed for grand palace: Bow') 'Weapon not-needed hint is incorrect.'

# A cache read must neither resolve requirements nor consume functional RNG.
$context = [Activator]::CreateInstance($contextType)
$context.randomFunctional = [Activator]::CreateInstance($randomType, [object[]]@(424242))
$control = [Activator]::CreateInstance($randomType, [object[]]@(424242))
$oneArg[0] = $context
$cached = $cacheMethod.Invoke($null, $oneArg)
Assert-True ($cached.Count -eq 0) 'Hint cache reader reconstructed unresolved requirements.'
Assert-True ($context.randomFunctional.Next() -eq $control.Next()) 'Hint cache reader advanced functional RNG.'

$source = Get-Content (Join-Path $PSScriptRoot '..\SoMRandomizer\processing\openworld\randomization\OpenWorldHints.cs') -Raw
Assert-True ($source -match 'Total elements needed for grand palace: ') `
    'Feature-off aggregate wording was removed.'
Assert-True ($source -match '!crystalOrbRequirementsEnabled && randomGrandPalaceElements && anySpellsExists') `
    'Feature-off hint gate is no longer preserved.'

Write-Output 'PASS: Crystal Orb hints preserve off behavior, count unique requirements, include weapons, and read only cached data.'
