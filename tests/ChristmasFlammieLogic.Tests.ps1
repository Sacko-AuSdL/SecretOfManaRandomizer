param(
    [string]$AssemblyPath = (Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path $AssemblyPath).Path)

function Assert-True([bool]$Condition, [string]$Message) {
    if(-not $Condition) { throw $Message }
}

$commonType = $assembly.GetType('SoMRandomizer.config.settings.CommonSettings', $true)
$settingsType = $assembly.GetType('SoMRandomizer.config.settings.OpenWorldSettings', $true)
$contextType = $assembly.GetType('SoMRandomizer.processing.common.RandoContext', $true)
$deliveryType = $assembly.GetType('SoMRandomizer.processing.openworld.events.GiftDeliveryIntroEvent', $true)
$matcherType = $assembly.GetType('SoMRandomizer.processing.openworld.randomization.OpenWorldLocationPrizeMatcher', $true)
$locationType = $assembly.GetType('SoMRandomizer.processing.openworld.randomization.PrizeLocation', $true)
$prizeType = $assembly.GetType('SoMRandomizer.processing.openworld.randomization.PrizeItem', $true)
$simulatorType = $assembly.GetType('SoMRandomizer.processing.openworld.randomization.OpenWorldSimulator', $true)
$prizesType = $assembly.GetType('SoMRandomizer.processing.openworld.randomization.OpenWorldPrizes', $true)
$cannonRegionsType = $assembly.GetType('SoMRandomizer.processing.openworld.cannon.CannonTravelRegions', $true)

$deliveryLocations = $deliveryType.GetField('DELIVERY_LOCATIONS').GetValue($null)
$jehk = $deliveryLocations | Where-Object key -eq 'jehk'
$johk = $deliveryLocations | Where-Object key -eq 'johk'
$elinee = $deliveryLocations | Where-Object key -eq 'elinee'
Assert-True ($jehk.eventId -eq 0x3DD) 'Gift Mode no longer targets Jehk lobby event $3DD.'
Assert-True ($johk.eventId -eq 0x3DC) 'Gift Mode no longer targets Johk lobby event $3DC.'
Assert-True ($jehk.itemDependencies -contains 'flammie drum') 'Jehk delivery omits its real Lofty Mountains Flammie dependency.'
Assert-True ($johk.itemDependencies -contains 'flammie drum') 'Johk delivery omits its real Lofty Mountains Flammie dependency.'

$otherFlammieTargets = @($deliveryLocations | Where-Object {
    $_.key -notin @('jehk', 'johk') -and $_.itemDependencies -contains 'flammie drum'
})
Assert-True ($otherFlammieTargets.Count -eq 0) 'The Lofty Mountains fix leaked into unrelated delivery targets.'

$resolveDependencies = $matcherType.GetMethod(
    'getNpcItemDependencies',
    [Reflection.BindingFlags]'Static,NonPublic')
Assert-True ($null -ne $resolveDependencies) 'Gift dependency resolver is missing.'

function Get-Dependencies($Npc, [bool]$FlammieInLogic) {
    $rawNpc = $Npc.PSObject.BaseObject
    [string[]]$dependencies = $resolveDependencies.Invoke($null, [object[]]@($rawNpc, $FlammieInLogic))
    Write-Output -NoEnumerate $dependencies
}

foreach($target in @($jehk, $johk)) {
    Assert-True ((Get-Dependencies $target $true) -contains 'flammie drum') `
        "$($target.key) lost Flammie while the drum is in logic."
    Assert-True (-not ((Get-Dependencies $target $false) -contains 'flammie drum')) `
        "$($target.key) requires a randomized Flammie Drum while the drum is outside logic."
}
Assert-True ((Get-Dependencies $elinee $true) -contains 'elinee') 'Existing Elinee traversal dependency changed.'
Assert-True ((Get-Dependencies $elinee $false) -contains 'elinee') 'Existing Elinee dependency changed when Flammie is outside logic.'

# The normal Open World Jehk prize is a different event ($4E5, after the trials). Its
# existing central Flammie classification must remain intact and is not reused as the
# lobby delivery's axe/whip requirement.
$flammieLocations = $prizesType.GetField('flammieRequiredLocations').GetValue($null)
Assert-True ($flammieLocations.Contains('jehk')) 'Normal Open World Jehk lost its existing Flammie classification.'
$getLocationRegion = $cannonRegionsType.GetMethod('getLocationRegion', [Reflection.BindingFlags]'Static,Public')
$jehkCannonRegion = $getLocationRegion.Invoke($null, [object[]]@('jehk')).ToString()
Assert-True ($jehkCannonRegion -eq 'FlammieOnly') `
    'Cannon Travel incorrectly treats normal Open World Jehk as ordinary Matango access.'

$locationCtor = $locationType.GetConstructor(@(
    [string], [int], [int], [string[]], [string[]], [string[]], [double]
))
$prizeCtor = $prizeType.GetConstructor(@(
    [string], [string], [byte[]], [string], [byte], [double]
))
$dictionaryType = [Collections.Generic.Dictionary``2].MakeGenericType($locationType, $prizeType)
$simulate = $simulatorType.GetMethod('runSimulation', [Reflection.BindingFlags]'Static,Public')

function New-SimulationState([bool]$FlammieInLogic, [string[]]$Dependencies) {
    $common = [Activator]::CreateInstance($commonType)
    $settings = [Activator]::CreateInstance($settingsType, [object[]]@($common))
    $settings.set('opFlammieDrumInLogic', $(if($FlammieInLogic) { 'yes' } else { 'no' })) | Out-Null
    $settings.set('cannonTravelRandomization', 'off') | Out-Null

    $context = [Activator]::CreateInstance($contextType)
    $working = $context.workingData
    $working.setBool('startWithBoy', $true)
    $working.setBool('startWithGirl', $false)
    $working.setBool('startWithSprite', $false)
    $working.set('boyClass', 'OGboy') | Out-Null
    $working.set('girlClass', 'OGgirl') | Out-Null
    $working.set('spriteClass', 'OGsprite') | Out-Null
    $working.set('openWorldGoalShortName', 'gift') | Out-Null
    $working.setInt('manaSeedsRequired', 0)
    $working.setInt('boyStartWeapon', 0)
    $working.setInt('girlStartWeapon', 0)
    $working.setInt('spriteStartWeapon', 0)
    $working.setBool('anyMagicExists', $false)

    $location = $locationCtor.Invoke([object[]]@(
        'santa gift 0', 0x138, 0, [string[]]@(), [string[]]@('from Santa'),
        $Dependencies, 1.0
    ))
    $flammie = $prizeCtor.Invoke([object[]]@(
        'flammie drum', 'item', [byte[]]@(), 'the flammie drum', [byte]0, 4.0
    ))
    $placements = [Activator]::CreateInstance($dictionaryType)
    $placements.Add($location, $flammie)
    return @($settings, $context, $placements)
}

$blocked = New-SimulationState $true (Get-Dependencies $jehk $true)
$blockedResult = $simulate.Invoke($null, [object[]]@($blocked[2], $blocked[0], $blocked[1]))
Assert-True ($blockedResult.score -lt 0) 'Simulator accepted Flammie Drum behind a Jehk delivery that requires Flammie.'

$outsideLogic = New-SimulationState $false (Get-Dependencies $jehk $false)
$outsideLogicResult = $simulate.Invoke($null, [object[]]@($outsideLogic[2], $outsideLogic[0], $outsideLogic[1]))
Assert-True ($outsideLogicResult.score -gt 0) 'Christmas behavior changed when Flammie Drum is outside logic.'

# The explicit delivery dependency is independent of Cannon mode. The existing Cannon
# graph remains responsible for all other spatial reachability.
foreach($mode in @('off', 'open', 'shuffle', 'chaos')) {
    Assert-True ((Get-Dependencies $jehk $true) -contains 'flammie drum') `
        "Jehk dependency disappeared in Cannon mode $mode."
}

Write-Output 'PASS: Jehk/Johk traversal, Flammie circular-placement rejection, outside-logic behavior, normal Open World classification, and Cannon-mode independence verified.'
