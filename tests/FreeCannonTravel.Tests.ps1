param(
    [string]$AssemblyPath = (Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe'),
    [string]$SourceRom = 'D:\views\tools\bots\Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc'
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path $AssemblyPath).Path)
$commonType = $assembly.GetType('SoMRandomizer.config.settings.CommonSettings', $true)
$settingsType = $assembly.GetType('SoMRandomizer.config.settings.OpenWorldSettings', $true)
$contextType = $assembly.GetType('SoMRandomizer.processing.common.RandoContext', $true)
$processorType = $assembly.GetType('SoMRandomizer.processing.openworld.cannon.CannonTravelRandomization', $true)
$modelType = $assembly.GetType('SoMRandomizer.processing.openworld.cannon.CannonTravelModel', $true)
$randomType = $assembly.GetType('SoMRandomizer.util.rng.DotNet110Random', $true)
$vanillaEventType = $assembly.GetType('SoMRandomizer.processing.common.VanillaEventUtil', $true)
$getDialogueBytes = $vanillaEventType.GetMethod('getBytes', [Type[]]@([string]))
$getVanillaEvent = $vanillaEventType.GetMethod('getVanillaEvent', [Type[]]@([byte[]],[int]))
$process = $processorType.GetMethod('process', [Reflection.BindingFlags]'Instance,NonPublic')
[byte[]]$sourceBytes = [IO.File]::ReadAllBytes((Resolve-Path $SourceRom).Path)
[byte[]]$sourceRom = [byte[]]::new(0x400000)
[Array]::Copy($sourceBytes,$sourceRom,[Math]::Min($sourceBytes.Length,$sourceRom.Length))

function Assert-True([bool]$Condition, [string]$Message) {
    if(-not $Condition) { throw $Message }
}

function Contains-Bytes([byte[]]$Haystack, [byte[]]$Needle) {
    if($Needle.Count -eq 0) { return $true }
    for($i = 0; $i -le $Haystack.Count - $Needle.Count; $i++) {
        $match = $true
        for($j = 0; $j -lt $Needle.Count; $j++) {
            if($Haystack[$i + $j] -ne $Needle[$j]) { $match = $false; break }
        }
        if($match) { return $true }
    }
    return $false
}

function New-State([string]$Mode, [bool]$Free, [int]$Seed) {
    $common = [Activator]::CreateInstance($commonType)
    $settings = [Activator]::CreateInstance($settingsType, [object[]]@($common))
    $settings.set('cannonTravelRandomization',$Mode) | Out-Null
    $settings.set('freeCannonTravel',$(if($Free){'on'}else{'off'})) | Out-Null
    $context = [Activator]::CreateInstance($contextType)
    $context.randomFunctional = [Activator]::CreateInstance($randomType,[object[]]@($Seed))
    return @($settings,$context)
}

function Invoke-Cannon([string]$Mode, [bool]$Free, [int]$Seed) {
    $state = New-State $Mode $Free $Seed
    [byte[]]$output = [byte[]]$sourceRom.Clone()
    $processor = [Activator]::CreateInstance($processorType)
    $changed = [bool]$process.Invoke($processor,
        [object[]]@($sourceRom,$output,'Free-Cannon-Test',$state[0],$state[1]))
    return @($state[0],$state[1],$output,$changed)
}

function Network-Signature($Network) {
    return (@($Network.Offices | ForEach-Object {
        $_.Office.Id + '=' + (@($_.Routes | ForEach-Object { $_.Destination.Id }) -join ',')
    }) -join '|')
}

$settingsProbe = [Activator]::CreateInstance($settingsType,
    [object[]]@([Activator]::CreateInstance($commonType)))
Assert-True ($settingsProbe.getDefault('freeCannonTravel') -eq 'off') `
    'Free Cannon Travel default is not Off.'
Assert-True (([string[]]$settingsProbe.getOptionsValues('freeCannonTravel') -join ',') -eq 'off,on') `
    'Free Cannon Travel serialized values are not off/on.'
Assert-True (([string[]]$settingsProbe.getDisplayValues('freeCannonTravel') -join ',') -eq 'Off,On') `
    'Free Cannon Travel display values are not Off/On.'

[byte[]]$remove50 = @(0x37,0x32,0x00,0x5F)
[byte[]]$insufficientFunds = @(0x42,0x0F,0x1F,0x10,0xF8)
[byte[]]$openGp = @(0x5D,0x5F)
[byte[]]$setFareFlag = @(0x30,0x0F,0x00)
[byte[]]$paidText = $getDialogueBytes.Invoke($null,[object[]]@('50 GP')).ToArray()
[byte[]]$freeText = $getDialogueBytes.Invoke($null,[object[]]@('0 GP')).ToArray()
$offices = @($modelType.GetField('OFFICES').GetValue($null))

# Default Off remains completely inert and preserves the current paid events.
$offPaid = Invoke-Cannon 'off' $false 11111
Assert-True (-not $offPaid[3]) 'Travel Off / Free Off unexpectedly changed output.'
Assert-True ($offPaid[1].replacementEvents.Count -eq 0) `
    'Travel Off / Free Off replaced events.'
Assert-True ([Linq.Enumerable]::SequenceEqual($sourceRom,[byte[]]$offPaid[2])) `
    'Travel Off / Free Off changed ROM bytes.'

# Travel Off / Free On patches only the seven existing menus and fourteen route events.
$offFree = Invoke-Cannon 'off' $true 11111
Assert-True ($offFree[3]) 'Travel Off / Free On did not apply the fare patch.'
Assert-True ([Linq.Enumerable]::SequenceEqual($sourceRom,[byte[]]$offFree[2])) `
    'Travel Off / Free On changed raw ROM data instead of scoped event replacements.'
$expectedEventIds = @($offices | ForEach-Object { @($_.MenuEvent) + @($_.ExistingRouteEvents) } |
    ForEach-Object { $_ } | Sort-Object -Unique)
Assert-True ($offFree[1].replacementEvents.Count -eq $expectedEventIds.Count) `
    'Travel Off / Free On changed events outside the Cannon menus/routes.'
foreach($eventId in $offFree[1].replacementEvents.Keys) {
    Assert-True ($expectedEventIds -contains $eventId) `
        ("Unrelated event 0x{0:X3} was modified by Free Cannon Travel." -f $eventId)
}
foreach($office in $offices) {
    [byte[]]$menu = $offFree[1].replacementEvents[$office.MenuEvent].ToArray()
    Assert-True (-not (Contains-Bytes $menu $setFareFlag)) `
        "$($office.Id) free menu retained the fare flag reset."
    Assert-True (-not (Contains-Bytes $menu $openGp)) `
        "$($office.Id) free menu retained the GP window."
    Assert-True (-not (Contains-Bytes $menu $paidText)) `
        "$($office.Id) free menu still displays 50 GP."
    Assert-True (Contains-Bytes $menu $freeText) `
        "$($office.Id) free menu does not display 0 GP."
    Assert-True (Contains-Bytes $menu ([byte[]]@(0x24,0x08))) `
        "$($office.Id) free menu removed common Cannon event `$408."
    foreach($routeEventId in $office.ExistingRouteEvents) {
        [byte[]]$route = $offFree[1].replacementEvents[$routeEventId].ToArray()
        Assert-True (-not (Contains-Bytes $route $remove50)) `
            ("Free vanilla route 0x{0:X3} still deducts 50 GP." -f $routeEventId)
        Assert-True (-not (Contains-Bytes $route $insufficientFunds)) `
            ("Free vanilla route 0x{0:X3} still rejects 0-GP players." -f $routeEventId)
        Assert-True (Contains-Bytes $route ([byte[]]@(0x1D))) `
            ("Free vanilla route 0x{0:X3} lost its Cannon flight command." -f $routeEventId)
    }
}
$offControlRng = [Activator]::CreateInstance($randomType,[object[]]@(11111))
Assert-True ($offFree[1].randomFunctional.Next() -eq $offControlRng.Next()) `
    'Travel Off / Free On consumed functional RNG.'

# Generated modes resolve the identical network and descriptor table. Only their fare bytes
# and fare labels differ; Chaos vacation offices remain byte-identical and closed.
foreach($mode in @('open','shuffle','chaos')) {
    $seed = if($mode -eq 'chaos'){5}else{24680}
    $paid = Invoke-Cannon $mode $false $seed
    $free = Invoke-Cannon $mode $true $seed
    Assert-True ($paid[3] -and $free[3]) "$mode did not generate both fare variants."
    $paidNetwork = $modelType.GetMethod('getResolvedNetwork').Invoke($null,@($paid[1]))
    $freeNetwork = $modelType.GetMethod('getResolvedNetwork').Invoke($null,@($free[1]))
    Assert-True ((Network-Signature $paidNetwork) -eq (Network-Signature $freeNetwork)) `
        "$mode topology changed when Free Cannon Travel was toggled."
    Assert-True ([Linq.Enumerable]::SequenceEqual([byte[]]$paid[2],[byte[]]$free[2])) `
        "$mode descriptor/hook ROM bytes changed with the fare setting."
    Assert-True ($paid[1].randomFunctional.Next() -eq $free[1].randomFunctional.Next()) `
        "$mode consumed different functional RNG with free travel."

    $openRouteEvents = if($mode -eq 'open') {
        [int[]]$processorType.GetField('OPEN_ROUTE_EVENTS',
            [Reflection.BindingFlags]'Static,NonPublic').GetValue($null)
    } else { @() }
    $routeIndex = 0
    foreach($paidOffice in $paidNetwork.Offices) {
        $freeOffice = @($freeNetwork.Offices | Where-Object { $_.Office.Id -eq $paidOffice.Office.Id })[0]
        if($paidOffice.IsClosed) {
            [byte[]]$paidClosed = $paid[1].replacementEvents[$paidOffice.Office.MenuEvent].ToArray()
            [byte[]]$freeClosed = $free[1].replacementEvents[$freeOffice.Office.MenuEvent].ToArray()
            Assert-True ([Linq.Enumerable]::SequenceEqual($paidClosed,$freeClosed)) `
                "$mode changed a CLOSED/vacation office when free travel was enabled."
            continue
        }
        for($index = 0; $index -lt $paidOffice.Routes.Count; $index++) {
            $routeEventId = if($mode -eq 'open') {
                $openRouteEvents[$routeIndex]
            } else {
                $paidOffice.Office.ExistingRouteEvents[$index]
            }
            [byte[]]$paidRoute = $paid[1].replacementEvents[$routeEventId].ToArray()
            [byte[]]$freeRoute = $free[1].replacementEvents[$routeEventId].ToArray()
            Assert-True (Contains-Bytes $paidRoute $remove50) `
                "$mode paid route lost its 50 GP deduction."
            Assert-True (Contains-Bytes $paidRoute $insufficientFunds) `
                "$mode paid route lost its affordability check."
            Assert-True (-not (Contains-Bytes $freeRoute $remove50)) `
                "$mode free route still deducts 50 GP."
            Assert-True (-not (Contains-Bytes $freeRoute $insufficientFunds)) `
                "$mode free route still rejects a 0-GP player."
            Assert-True (Contains-Bytes $freeRoute ([byte[]]@(0x1D))) `
                "$mode free route lost its Cannon command."
            $routeIndex++
        }
    }
    foreach($event in $free[1].replacementEvents.Values) {
        Assert-True (-not (Contains-Bytes ([byte[]]$event.ToArray()) $paidText)) `
            "$mode free Cannon events still display 50 GP."
    }
}

Write-Output 'PASS: Free Cannon Travel preserves paid defaults, removes only Cannon fare checks/deductions in all modes, accepts 0 GP, preserves topology/RNG/closed offices, and leaves unrelated ROM data unchanged.'
