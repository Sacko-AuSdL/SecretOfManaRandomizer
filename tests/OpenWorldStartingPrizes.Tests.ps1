param(
    [string]$AssemblyPath = (Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path $AssemblyPath).Path)
$commonType = $assembly.GetType('SoMRandomizer.config.settings.CommonSettings', $true)
$settingsType = $assembly.GetType('SoMRandomizer.config.settings.OpenWorldSettings', $true)
$contextType = $assembly.GetType('SoMRandomizer.processing.common.RandoContext', $true)
$simulatorType = $assembly.GetType('SoMRandomizer.processing.openworld.randomization.OpenWorldSimulator', $true)
$prizeLocationType = $assembly.GetType('SoMRandomizer.processing.openworld.randomization.PrizeLocation', $true)
$prizeItemType = $assembly.GetType('SoMRandomizer.processing.openworld.randomization.PrizeItem', $true)

function Assert-True([bool]$Condition, [string]$Message) {
    if(-not $Condition) { throw $Message }
}

function New-TestObjects {
    $common = [Activator]::CreateInstance($commonType)
    $settings = [Activator]::CreateInstance($settingsType, [object[]]@($common))
    $context = [Activator]::CreateInstance($contextType)
    return @($settings, $context)
}

function Set-SimulatorWorkingData($Context) {
    $workingData = $contextType.GetField('workingData').GetValue($Context)
    foreach($key in @('startWithBoy', 'startWithGirl', 'startWithSprite')) {
        $workingData.setBool($key, $true)
    }
    foreach($entry in @(
        @('boyClass', 'OGboy'), @('girlClass', 'OGgirl'), @('spriteClass', 'OGsprite'),
        @('openWorldGoalShortName', 'manabeast')
    )) { $workingData.set($entry[0], $entry[1]) }
    $workingData.setBool('anyMagicExists', $true)
    foreach($entry in @(
        @('manaSeedsRequired', 0), @('boyStartWeapon', 0),
        @('girlStartWeapon', 2), @('spriteStartWeapon', 3)
    )) { $workingData.setInt($entry[0], [int]$entry[1]) }
}

function New-RequirementPlacements {
    $dictionaryType = [System.Collections.Generic.Dictionary``2].MakeGenericType($prizeLocationType, $prizeItemType)
    $placements = [Activator]::CreateInstance($dictionaryType)
    [string[]]$requirements = @(
        'glove', 'sword', 'axe', 'spear', 'whip', 'bow', 'boomerang', 'javelin',
        'undine spells', 'gnome spells', 'sylphid spells', 'salamando spells',
        'lumina spells', 'shade spells', 'luna spells', 'dryad spells'
    )
    $locationConstructor = $prizeLocationType.GetConstructor([Type[]]@(
        [string], [int], [int], [int], [int], [string[]], [string[]], [string[]], [double]
    ))
    $prizeConstructor = $prizeItemType.GetConstructor([Type[]]@(
        [string], [string], [byte[]], [string], [byte], [double]
    ))
    for($i = 0; $i -lt $requirements.Length; $i++) {
        $location = $locationConstructor.Invoke([object[]]@(
            "start-with requirement $i", -1, -1, 0, 0,
            [string[]]@(), [string[]]@(), [string[]]@($requirements[$i]), 1.0))
        $prize = $prizeConstructor.Invoke([object[]]@(
            "nothing $i", '', [byte[]]@(), '', [byte]0, 1.0))
        $placements.Add($location, $prize)
    }
    return ,$placements
}

function Invoke-Simulation($Settings, $Context) {
    Set-SimulatorWorkingData $Context
    return $simulatorType.GetMethod('runSimulation').Invoke(
        $null, [object[]]@((New-RequirementPlacements), $Settings, $Context))
}

Assert-True ($null -eq $assembly.GetType(
    'SoMRandomizer.processing.openworld.CrystalOrbSequenceBreakTestBootstrap', $false)) `
    'Temporary Crystal Orb bootstrap type still exists.'

$objects = New-TestObjects
$settings = $objects[0]; $context = $objects[1]
$plando = $contextType.GetField('plandoSettings').GetValue($context)
$startingPrizeList = [System.Collections.Generic.List[string]]::new()
foreach($prize in @(
    'Glove', 'Sword', 'Axe', 'Spear', 'Whip', 'Bow', 'Boomerang', 'Javelin',
    'Undine', 'Gnome', 'Sylphid', 'Salamando', 'Lumina', 'Shade', 'Luna', 'Dryad'
)) { $startingPrizeList.Add($prize) }
$plando['p_(Start-with)'] = $startingPrizeList

$result = Invoke-Simulation $settings $context
Assert-True ($result.score -eq 16) 'Simulator did not credit all explicit start-with prizes.'
Assert-True ($result.collectionCycles[0].Count -eq 16) 'Start-with requirements were not reachable in cycle zero.'

$control = New-TestObjects
$controlResult = Invoke-Simulation $control[0] $control[1]
Assert-True ($controlResult.score -eq -1) 'Control simulation unexpectedly received start-with prizes.'

Write-Output 'PASS: simulator credits supported explicit Start-with weapons/spells, and the Crystal Orb bootstrap is absent.'
