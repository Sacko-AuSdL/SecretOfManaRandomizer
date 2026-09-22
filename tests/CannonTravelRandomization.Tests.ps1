param(
    [string]$AssemblyPath = (Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe'),
    [string]$SourceRom = 'D:\views\tools\bots\Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc'
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path $AssemblyPath).Path)
$commonType = $assembly.GetType('SoMRandomizer.config.settings.CommonSettings', $true)
$settingsType = $assembly.GetType('SoMRandomizer.config.settings.OpenWorldSettings', $true)
$contextType = $assembly.GetType('SoMRandomizer.processing.common.RandoContext', $true)
$modelType = $assembly.GetType('SoMRandomizer.processing.openworld.cannon.CannonTravelModel', $true)
$processorType = $assembly.GetType('SoMRandomizer.processing.openworld.cannon.CannonTravelRandomization', $true)
$regionsType = $assembly.GetType('SoMRandomizer.processing.openworld.cannon.CannonTravelRegions', $true)
$regionType = $assembly.GetType('SoMRandomizer.processing.openworld.cannon.CannonTravelRegion', $true)
$randomType = $assembly.GetType('SoMRandomizer.util.rng.DotNet110Random', $true)
$eventScriptType = $assembly.GetType('SoMRandomizer.processing.common.structure.EventScript', $true)
$eventCommandType = $assembly.GetType('SoMRandomizer.processing.common.EventCommandEnum', $true)
$vanillaEventType = $assembly.GetType('SoMRandomizer.processing.common.VanillaEventUtil', $true)
$getDialogueBytes = $vanillaEventType.GetMethod('getBytes', [Type[]]@([string]))

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

function Find-Bytes([byte[]]$Haystack, [byte[]]$Needle) {
    if($Needle.Count -eq 0) { return 0 }
    for($i = 0; $i -le $Haystack.Count - $Needle.Count; $i++) {
        $match = $true
        for($j = 0; $j -lt $Needle.Count; $j++) {
            if($Haystack[$i + $j] -ne $Needle[$j]) { $match = $false; break }
        }
        if($match) { return $i }
    }
    return -1
}

function Get-ChoiceCounts([byte[]]$Script) {
    $counts = @()
    $inside = $false
    $count = 0
    foreach($value in $Script) {
        if(-not $inside -and $value -eq 0x58) {
            $inside = $true
            $count = 0
        } elseif($inside -and $value -eq 0x5A) {
            $count++
        } elseif($inside -and $value -eq 0x5B) {
            $counts += $count
            $inside = $false
        }
    }
    return ,$counts
}

function New-TestState([string]$Mode, [int]$Seed) {
    $common = [Activator]::CreateInstance($commonType)
    $settings = [Activator]::CreateInstance($settingsType, [object[]]@($common))
    $settings.set('cannonTravelRandomization', $Mode)
    $context = [Activator]::CreateInstance($contextType)
    $context.randomFunctional = [Activator]::CreateInstance($randomType, [object[]]@($Seed))
    return ,@($settings, $context)
}

function Resolve-Network([string]$Mode, [int]$Seed) {
    $state = New-TestState $Mode $Seed
    $network = $modelType.GetMethod('resolveAndStore').Invoke($null, [object[]]@($state[0], $state[1]))
    return ,@($state[0], $state[1], $network)
}

function Network-Signature($Network) {
    return (@($Network.Offices | ForEach-Object {
        $_.Office.Id + '=' + (@($_.Routes | ForEach-Object { $_.Destination.Id }) -join ',')
    }) -join '|')
}

function Get-RegionGraph($Network) {
    $graph = @{}
    foreach($office in $modelType.GetField('OFFICES').GetValue($null)) {
        $key = $office.LogicalRegion.ToString()
        if(-not $graph.ContainsKey($key)) { $graph[$key] = [Collections.Generic.HashSet[string]]::new() }
    }
    foreach($office in $Network.Offices) {
        $source = $office.Office.LogicalRegion.ToString()
        foreach($route in $office.Routes) {
            $graph[$source].Add($route.Destination.LogicalRegion.ToString()) | Out-Null
        }
    }
    return $graph
}

function Can-Reach($Graph, [string]$Start, [string]$Target) {
    $seen = [Collections.Generic.HashSet[string]]::new()
    $pending = [Collections.Generic.Queue[string]]::new()
    $seen.Add($Start) | Out-Null
    $pending.Enqueue($Start)
    while($pending.Count -gt 0) {
        $current = $pending.Dequeue()
        if($current -eq $Target) { return $true }
        foreach($next in $Graph[$current]) {
            if($seen.Add($next)) { $pending.Enqueue($next) }
        }
    }
    return $false
}

$probe = [Activator]::CreateInstance($settingsType,
    [object[]]@([Activator]::CreateInstance($commonType)))
Assert-True ($probe.getDefault('cannonTravelRandomization') -eq 'off') 'Cannon Travel default is not Off.'
Assert-True (([string[]]$probe.getOptionsValues('cannonTravelRandomization') -join ',') -eq 'off,open,shuffle,chaos') `
    'Cannon Travel serialized options are incorrect.'
Assert-True (([string[]]$probe.getDisplayValues('cannonTravelRandomization') -join ',') -eq 'Off,Open,Shuffle,Chaos') `
    'Cannon Travel display options are incorrect.'

$destinations = @($modelType.GetField('DESTINATIONS').GetValue($null))
$offices = @($modelType.GetField('OFFICES').GetValue($null))
Assert-True ($destinations.Count -eq 9) 'Expected exactly nine safe Cannon destinations.'
Assert-True ($offices.Count -eq 7) 'Expected exactly seven Cannon offices.'
$expectedEndpoints = @{
    potos='9B-BF'; gaiasNavel='85-CA'; waterPalace='84-B7'; upperLand='88-98';
    pandora='95-D8'; kakkara='28-5D'; matango='68-97'; iceCountry='A7-0B'; southtown='E4-65'
}
$openOverviewNames = @{
    potos='Potos'; gaiasNavel='Gaia'; waterPalace='Water'; upperLand='Upper';
    pandora='Pandora'; kakkara='Kakkara'; matango='Matango'; iceCountry='Ice';
    southtown='Southtown'
}
foreach($destination in $destinations) {
    $actual = '{0:X2}-{1:X2}' -f $destination.WorldX,$destination.WorldY
    Assert-True ($actual -eq $expectedEndpoints[$destination.Id]) "Endpoint $($destination.Id) changed to $actual."
}

# Off is an inert default: the processor does not resolve, advance RNG, write ROM, or replace events.
$offState = New-TestState 'off' 12345
$offControl = [Activator]::CreateInstance($randomType, [object[]]@(12345))
$offProcessor = [Activator]::CreateInstance($processorType)
[byte[]]$offOrig = [byte[]]::new(0x400000)
[byte[]]$offOut = [byte[]]::new(0x400000)
$offOrig[0x1E849] = 0xBF; $offOrig[0x1E863] = 0xBF
[Array]::Copy($offOrig, $offOut, $offOrig.Length)
$process = $processorType.GetMethod('process', [Reflection.BindingFlags]'Instance,NonPublic')
$offResult = [bool]$process.Invoke($offProcessor,
    [object[]]@($offOrig, $offOut, 'off-test', $offState[0], $offState[1]))
Assert-True (-not $offResult) 'Off unexpectedly reported a ROM change.'
Assert-True ([Linq.Enumerable]::SequenceEqual($offOrig, $offOut)) 'Off changed ROM bytes.'
Assert-True ($offState[1].replacementEvents.Count -eq 0) 'Off replaced Cannon events.'
Assert-True ($offState[1].randomFunctional.Next() -eq $offControl.Next()) 'Off consumed functional RNG.'

# Resolution is deterministic, cached, and cached reads consume no RNG.
$shuffleA = Resolve-Network 'shuffle' 24680
$shuffleB = Resolve-Network 'shuffle' 24680
Assert-True ((Network-Signature $shuffleA[2]) -eq (Network-Signature $shuffleB[2])) 'Same Shuffle seed diverged.'
$repeat = $modelType.GetMethod('resolveAndStore').Invoke($null, [object[]]@($shuffleA[0], $shuffleA[1]))
Assert-True ((Network-Signature $repeat) -eq (Network-Signature $shuffleA[2])) 'Cached Shuffle network changed.'
Assert-True ($shuffleA[1].randomFunctional.Next() -eq $shuffleB[1].randomFunctional.Next()) 'Cached network read advanced RNG.'

$sawDifferent = $false
foreach($seed in 24681..24695) {
    if((Network-Signature (Resolve-Network 'shuffle' $seed)[2]) -ne (Network-Signature $shuffleA[2])) {
        $sawDifferent = $true; break
    }
}
Assert-True $sawDifferent 'Different Shuffle seeds never changed the network.'

foreach($seed in 1..100) {
    $shuffle = (Resolve-Network 'shuffle' $seed)[2]
    $routes = @($shuffle.Offices | ForEach-Object { @($_.Routes) })
    Assert-True ($routes.Count -eq 14) "Shuffle seed $seed did not retain 14 slots."
    Assert-True ((@($routes | ForEach-Object { $_.Destination.Id } | Sort-Object -Unique)).Count -eq 9) `
        "Shuffle seed $seed omitted a destination."
    foreach($office in $shuffle.Offices) {
        Assert-True ((@($office.Routes | ForEach-Object { $_.Destination.Id } | Sort-Object -Unique)).Count -eq $office.Routes.Count) `
            "Shuffle seed $seed duplicated an office-local destination."
        foreach($route in $office.Routes) {
            Assert-True ($route.Destination.LogicalRegion -ne $office.Office.LogicalRegion) `
                "Shuffle seed $seed emitted a self-region route."
        }
    }
    # Verify the same region-level property enforced by the production validator.
    $graph = Get-RegionGraph $shuffle
    foreach($source in $graph.Keys) {
        foreach($target in $graph.Keys) {
            Assert-True (Can-Reach $graph $source $target) "Shuffle seed $seed is not strongly connected."
        }
    }
}

# Open serves every canonical endpoint except the office's own landing identity.
$openResolved = Resolve-Network 'open' 777
$open = $openResolved[2]
foreach($office in $open.Offices) {
    Assert-True ($office.Routes.Count -eq 8) "Open office $($office.Office.Id) does not serve eight destinations."
    Assert-True ((@($office.Routes | ForEach-Object { $_.Destination.Id } | Sort-Object -Unique)).Count -eq 8) `
        "Open office $($office.Office.Id) has duplicate destinations."
    Assert-True (@($office.Routes | Where-Object {
        $_.Destination.Id -eq $office.Office.HomeDestinationId }).Count -eq 0) `
        "Open office $($office.Office.Id) offers its own landing destination."
    $expected = @($destinations | Where-Object Id -ne $office.Office.HomeDestinationId |
        ForEach-Object Id | Sort-Object)
    $actual = @($office.Routes | ForEach-Object { $_.Destination.Id } | Sort-Object)
    Assert-True (($actual -join ',') -eq ($expected -join ',')) `
        "Open office $($office.Office.Id) does not offer every non-self destination."
}
$openControl = [Activator]::CreateInstance($randomType, [object[]]@(777))
Assert-True ($openResolved[1].randomFunctional.Next() -eq $openControl.Next()) `
    'Open consumed functional RNG despite having no random selection.'

# Chaos may partition the world, but every emitted edge remains inside a mutually reachable SCC.
$chaosA = Resolve-Network 'chaos' 314159
$chaosB = Resolve-Network 'chaos' 314159
Assert-True ((Network-Signature $chaosA[2]) -eq (Network-Signature $chaosB[2])) `
    'Same Chaos seed diverged.'
$chaosRepeat = $modelType.GetMethod('resolveAndStore').Invoke($null, [object[]]@($chaosA[0], $chaosA[1]))
Assert-True ((Network-Signature $chaosRepeat) -eq (Network-Signature $chaosA[2])) `
    'Cached Chaos network changed.'
Assert-True ($chaosA[1].randomFunctional.Next() -eq $chaosB[1].randomFunctional.Next()) `
    'Cached Chaos read advanced RNG.'

$sawClosed = $false; $sawDisconnected = $false; $sawChaosDifference = $false
$sawDuplicate = $false; $sawMissing = $false
$firstChaosSignature = $null
foreach($seed in 1..150) {
    $chaos = (Resolve-Network 'chaos' $seed)[2]
    $chaosRouteCount = @($chaos.Offices | ForEach-Object { $_.Routes }).Count
    Assert-True ($chaosRouteCount -le 14) `
        "Chaos seed $seed would exceed the six-bit `$20-`$2D generated route range."
    $signature = Network-Signature $chaos
    if($null -eq $firstChaosSignature) { $firstChaosSignature = $signature }
    elseif($signature -ne $firstChaosSignature) { $sawChaosDifference = $true }
    $closedOffices = @($chaos.Offices | Where-Object IsClosed)
    if($closedOffices.Count -gt 0) {
        $sawClosed = $true
        foreach($closedOffice in $closedOffices) {
            Assert-True ($closedOffice.ClosedMessage -eq "Sorry! I'm on vacation!") `
                "Chaos seed $seed used a noncanonical closed-office message."
        }
    }
    $destinationIds = @($chaos.Offices | ForEach-Object { $_.Routes } |
        ForEach-Object { $_.Destination.Id })
    if(@($destinationIds | Group-Object | Where-Object Count -gt 1).Count -gt 0) { $sawDuplicate = $true }
    if(@($destinations.Id | Where-Object { $destinationIds -notcontains $_ }).Count -gt 0) { $sawMissing = $true }
    $graph = Get-RegionGraph $chaos
    $keys = @($graph.Keys)
    if(-not (Can-Reach $graph $keys[0] $keys[1]) -or -not (Can-Reach $graph $keys[1] $keys[0])) {
        $sawDisconnected = $true
    }
    foreach($office in $chaos.Offices) {
        foreach($route in $office.Routes) {
            $source = $office.Office.LogicalRegion.ToString()
            $target = $route.Destination.LogicalRegion.ToString()
            Assert-True ($source -ne $target) "Chaos seed $seed emitted a self-region route."
            Assert-True (Can-Reach $graph $target $source) `
                "Chaos seed $seed emitted a one-way edge into a different component."
        }
    }
}
Assert-True ($sawClosed -and $sawDisconnected -and $sawChaosDifference -and
    $sawDuplicate -and $sawMissing) `
    'Chaos sampling did not exercise closed, partitioned, duplicate, missing, and varying networks.'

# Region reachability keeps the Matango/Upper-Land foot connection conditional and Flammie global.
$offNetwork = (Resolve-Network 'off' 1)[2]
$matango = [Enum]::Parse($regionType, 'Matango')
$upperLand = [Enum]::Parse($regionType, 'UpperLand')
$withoutOrb = $regionsType.GetMethod('getReachableRegions').Invoke(
    $null, [object[]]@($offNetwork, $matango, $false, $false))
$withOrb = $regionsType.GetMethod('getReachableRegions').Invoke(
    $null, [object[]]@($offNetwork, $matango, $false, $true))
$withFlammie = $regionsType.GetMethod('getReachableRegions').Invoke(
    $null, [object[]]@($offNetwork, $matango, $true, $false))
Assert-True (-not $withoutOrb.Contains($upperLand)) 'Upper Land crossed without its Orb prerequisite.'
Assert-True ($withOrb.Contains($upperLand)) 'Upper Land did not open when its Orb prerequisite was met.'
Assert-True ($withFlammie.Count -eq 8) 'Flammie did not make every logical region reachable.'

# Byte-level processor checks use the authoritative source ROM for unused-event validation.
if(-not (Test-Path $SourceRom)) { throw "Source ROM not found: $SourceRom" }
[byte[]]$sourceBytes = [IO.File]::ReadAllBytes((Resolve-Path $SourceRom).Path)
Assert-True ([Linq.Enumerable]::SequenceEqual(
    [byte[]]$sourceBytes[0x67D00..0x67D03], [byte[]]@(0x9B,0xBF,0x84,0xB7))) `
    'Vanilla route $20 is not restored to Potos -> Water Palace.'
Assert-True ([Linq.Enumerable]::SequenceEqual(
    [byte[]]$sourceBytes[0x1E843..0x1E845], [byte[]]@(0x29,0x7F,0x00))) `
    'Vanilla descriptor lookup no longer applies its later $007F mask.'
Assert-True ([Linq.Enumerable]::SequenceEqual(
    [byte[]]$sourceBytes[0x1EB47..0x1EB49], [byte[]]@(0x29,0x3F,0x00))) `
    'Event command $1D no longer masks Cannon route operands to six bits at $C1:EB47.'
Assert-True ((0x49 -band 0x3F) -eq 0x09) `
    'Regression setup no longer demonstrates broken route $49 becoming runtime route $09.'
Assert-True ([Linq.Enumerable]::SequenceEqual(
    [byte[]]$sourceBytes[0x1E86A..0x1E86D], [byte[]]@(0x22,0x01,0xBC,0x00))) `
    'Vanilla Cannon flight initializer call at $C1:E86A changed.'
$processorFlags = [Reflection.BindingFlags]'Static,NonPublic'
Assert-True ([int]$processorType.GetField('GENERATED_ROUTE_TABLE_SIZE',
    $processorFlags).GetRawConstantValue() -eq 0x100) `
    'Generated Cannon table is not exactly 64 four-byte descriptors.'
Assert-True ($null -eq $processorType.GetMethod('installFlightInitializerWrapper',
    $processorFlags)) 'Obsolete Cannon flight wrapper installer still exists.'
Assert-True ($null -eq $processorType.GetField('FLIGHT_WRAPPER_WORKING_DATA_KEY',
    $processorFlags)) 'Obsolete Cannon flight-wrapper working-data key still exists.'
[byte[]]$origRom = [byte[]]::new(0x400000)
[Array]::Copy($sourceBytes, $origRom, [Math]::Min($sourceBytes.Length, $origRom.Length))
foreach($mode in @('shuffle', 'chaos', 'open')) {
    $processorSeed = if($mode -eq 'chaos') { 5 } else { 13579 }
    $state = New-TestState $mode $processorSeed
    [byte[]]$outRom = [byte[]]$origRom.Clone()
    $processor = [Activator]::CreateInstance($processorType)
    $processed = [bool]$process.Invoke($processor,
        [object[]]@($origRom, $outRom, 'byte-test', $state[0], $state[1]))
    Assert-True $processed "$mode processor did not run."
    Assert-True ($outRom[0x1E849] -eq 0xBF -and $outRom[0x1E863] -eq 0xBF) `
        "$mode changed either runtime-confirmed lookup opcode."
    $sourceCpu = [int]$outRom[0x1E84A] + ([int]$outRom[0x1E84B] -shl 8) + ([int]$outRom[0x1E84C] -shl 16)
    $targetCpu = [int]$outRom[0x1E864] + ([int]$outRom[0x1E865] -shl 8) + ([int]$outRom[0x1E866] -shl 16)
    Assert-True ($targetCpu -eq $sourceCpu + 2) "$mode source/target tables diverged."
    $tableOffset = $state[1].workingData.getInt('cannonTravelRouteTableOffset')
    Assert-True ($sourceCpu -eq $tableOffset + 0xC00000) "$mode hook operand does not point to its table."
    Assert-True ([Linq.Enumerable]::SequenceEqual(
        [byte[]]$outRom[0x1E86A..0x1E86D], [byte[]]@(0x22,0x01,0xBC,0x00))) `
        "$mode altered the vanilla JSL `$C0:BC01 at `$C1:E86A."
    Assert-True ([Linq.Enumerable]::SequenceEqual(
        [byte[]]$outRom[0x1EB47..0x1EB49], [byte[]]@(0x29,0x3F,0x00))) `
        "$mode altered the event command's `$003F route-ID mask."

    $network = $modelType.GetMethod('getResolvedNetwork').Invoke($null, [object[]]@($state[1]))
    $generatedOpenRouteEvents = [int[]]$processorType.GetField('OPEN_ROUTE_EVENTS',
        [Reflection.BindingFlags]'Static,NonPublic').GetValue($null)
    $routeIndex = 0
    $firstRouteId = if($mode -eq 'open') { 0x00 } else { 0x20 }
    foreach($office in $network.Offices) {
        for($officeRouteIndex = 0; $officeRouteIndex -lt $office.Routes.Count; $officeRouteIndex++) {
            $route = $office.Routes[$officeRouteIndex]
            $routeId = $firstRouteId + $routeIndex
            Assert-True ($routeId -le 0x3F) `
                "$mode generated route ID exceeds the event command's `$003F mask."
            Assert-True (($routeId -band 0x40) -eq 0) `
                "$mode generated route ID accidentally enables the `$40/`$E3 behavior."
            $offset = $tableOffset + $routeId * 4
            Assert-True ($outRom[$offset] -eq $office.Office.SourceWorldX -and
                $outRom[$offset + 1] -eq $office.Office.SourceWorldY -and
                $outRom[$offset + 2] -eq $route.Destination.WorldX -and
                $outRom[$offset + 3] -eq $route.Destination.WorldY) `
                "$mode descriptor $routeId does not match its resolved route."
            $routeEvent = if($mode -eq 'open') {
                $generatedOpenRouteEvents[$routeIndex]
            } else {
                $office.Office.ExistingRouteEvents[$officeRouteIndex]
            }
            [byte[]]$routeScript = $state[1].replacementEvents[$routeEvent].ToArray()
            Assert-True (Contains-Bytes $routeScript ([byte[]]@(0x37,0x32,0x00,0x5F))) `
                "$mode route event 0x$($routeEvent.ToString('X3')) does not charge exactly 50 GP."
            $cannonCommandOffset = Find-Bytes $routeScript ([byte[]]@(0x1D))
            Assert-True ($cannonCommandOffset -ge 0) `
                "$mode route event 0x$($routeEvent.ToString('X3')) has no Cannon command."
            $routeOperand = $routeScript[$cannonCommandOffset + 1]
            Assert-True ($routeOperand -eq $routeId -and
                ($routeOperand -band 0x3F) -eq $routeId) `
                "$mode route event 0x$($routeEvent.ToString('X3')) runtime ID differs from its descriptor."
            Assert-True (($routeOperand -band 0x40) -eq 0) `
                "$mode route event 0x$($routeEvent.ToString('X3')) sets the non-route `$40 flag."
            [byte[]]$destinationLabel = $getDialogueBytes.Invoke(
                $null, [object[]]@($route.Destination.DisplayName)).ToArray()
            Assert-True (Contains-Bytes $routeScript $destinationLabel) `
                "$mode route event label does not match $($route.Destination.DisplayName)."
            $routeIndex++
        }
    }
    for($slot = 0; $slot -lt 64; $slot++) {
        if($slot -ge $firstRouteId -and $slot -lt $firstRouteId + $routeIndex) { continue }
        $generatedOffset = $tableOffset + $slot * 4
        $sourceOffset = 0x67C80 + $slot * 4
        Assert-True ([Linq.Enumerable]::SequenceEqual(
            [byte[]]$outRom[$generatedOffset..($generatedOffset + 3)],
            [byte[]]$origRom[$sourceOffset..($sourceOffset + 3)])) `
            ("$mode did not preserve unused route-table slot `${0:X2}." -f $slot)
    }
    if($mode -eq 'open') {
        Assert-True ($routeIndex -eq 56) 'Open did not emit 56 non-self descriptors.'
        Assert-True ($firstRouteId -eq 0x00 -and
            $firstRouteId + $routeIndex - 1 -eq 0x37) `
            'Open did not use the deterministic six-bit route range $00-$37.'
        Assert-True ($state[1].replacementEvents.Count -eq 91) `
            'Open did not emit 7 roots + 7 selectors + 21 pages + 56 routes.'
        $pageEvents = [int[]]$processorType.GetField('OPEN_PAGE_EVENTS',
            [Reflection.BindingFlags]'Static,NonPublic').GetValue($null)
        $routeEvents = [int[]]$processorType.GetField('OPEN_ROUTE_EVENTS',
            [Reflection.BindingFlags]'Static,NonPublic').GetValue($null)
        $selectorEvents = [int[]]$processorType.GetField('OPEN_SELECTOR_EVENTS',
            [Reflection.BindingFlags]'Static,NonPublic').GetValue($null)
        Assert-True ($pageEvents.Count -eq 21) 'Open page event pool is not exactly 21 events.'
        Assert-True ($routeEvents.Count -eq 56) 'Open route event pool is not exactly 56 events.'
        Assert-True ($selectorEvents.Count -eq 7) 'Open selector event pool is not exactly 7 events.'
        [byte[]]$eightChoicePrefix = @(
            0x58,0x5A,0x01,0xB6,0x5A,0x03,0xB7,0x5A,0x05,0xB8,
            0x5A,0x07,0xB9,0x5A,0x09,0xBA,0x5A,0x0B,0xBB,0x5A,0x0D,
            0xBC,0x5A,0x0F,0xBD,0x5B)
        for($officeIndex = 0; $officeIndex -lt 7; $officeIndex++) {
            [byte[]]$menu = $state[1].replacementEvents[$network.Offices[$officeIndex].Office.MenuEvent].ToArray()
            $overviewLines = @()
            for($page = 0; $page -lt 3; $page++) {
                $first = $page * 3
                $pageNames = @($network.Offices[$officeIndex].Routes |
                    Select-Object -Skip $first -First 3 |
                    ForEach-Object { $openOverviewNames[$_.Destination.Id] })
                $line = "$($page + 1):$($pageNames -join '/')"
                Assert-True ($line.Length -le 28) `
                    "Open menu $officeIndex overview page $($page + 1) exceeds 28 characters."
                Assert-True ($line -notmatch "`r|`n") `
                    "Open menu $officeIndex overview page $($page + 1) is not one line."
                $overviewLines += $line
            }
            Assert-True ($overviewLines.Count -eq 3) `
                "Open menu $officeIndex overview is not exactly three lines."
            $overviewText = $overviewLines -join "`n"
            Assert-True (($overviewText -split "`n").Count -eq 3) `
                "Open menu $officeIndex overview encodes more than three lines."
            [byte[]]$overviewBytes = $getDialogueBytes.Invoke(
                $null, [object[]]@($overviewText)).ToArray()
            [byte[]]$framedOverview = @([byte]0x50) + $overviewBytes +
                [byte[]]@(0x28,0x00,0x51)
            Assert-True (Contains-Bytes $menu $framedOverview) `
                "Open menu $officeIndex does not contain the single framed three-line overview."

            [byte[]]$selectorJump = $eventScriptType.GetMethod('GetJumpCmd').Invoke(
                $null, [object[]]@($selectorEvents[$officeIndex]))
            Assert-True ($menu[$menu.Length - 3] -eq $selectorJump[0] -and
                $menu[$menu.Length - 2] -eq $selectorJump[1] -and
                $menu[$menu.Length - 1] -eq 0x00) `
                "Open menu $officeIndex does not transfer from the closed overview to its standalone selector."

            [byte[]]$selector = $state[1].replacementEvents[
                $selectorEvents[$officeIndex]].ToArray()
            [byte[]]$selectorText = $getDialogueBytes.Invoke(
                $null, [object[]]@("50 GP! Choose page:`n")).ToArray()
            [byte[]]$threeChoicePrefix = @(
                0x58,0x5A,0x02,0xB6,0x5A,0x07,0xB7,0x5A,0x0C,0xB8,0x5B)
            [byte[]]$framedSelector = @([byte]0x50) + $selectorText + $threeChoicePrefix
            Assert-True ([Linq.Enumerable]::SequenceEqual(
                [byte[]]$selector[0..($framedSelector.Length - 1)], $framedSelector)) `
                "Open menu $officeIndex selector does not begin with the known-good `$50/`$58/`$5A structure."
            Assert-True (-not (Contains-Bytes $menu $threeChoicePrefix)) `
                "Open menu $officeIndex still appends its selector directly after the overview close."
            Assert-True (-not (Contains-Bytes $selector $eightChoicePrefix)) `
                "Open menu $officeIndex retained the unsupported direct 1-8 selector."
            $rootChoiceCounts = @(Get-ChoiceCounts $selector)
            Assert-True ($rootChoiceCounts.Count -eq 1 -and $rootChoiceCounts[0] -eq 3) `
                "Open menu $officeIndex generated a non-three-choice selector."

            $rootSelectionEnd = (Find-Bytes $selector $threeChoicePrefix) + $threeChoicePrefix.Length - 1
            [byte[]]$cancelJump = $eventScriptType.GetMethod('GetJumpCmd').Invoke(
                $null, [object[]]@(0x0FF))
            Assert-True ($selector[$rootSelectionEnd + 1] -eq $cancelJump[0] -and
                $selector[$rootSelectionEnd + 2] -eq $cancelJump[1]) `
                "Open menu $officeIndex selector cancel target is not event `$0FF."
            for($page = 0; $page -lt 3; $page++) {
                [byte[]]$pageJump = $eventScriptType.GetMethod('GetJumpCmd').Invoke(
                    $null, [object[]]@($pageEvents[$officeIndex * 3 + $page]))
                $rootCommandOffset = $rootSelectionEnd + 3 + $page * 2
                Assert-True ($selector[$rootCommandOffset] -eq $pageJump[0] -and
                    $selector[$rootCommandOffset + 1] -eq $pageJump[1]) `
                    "Open menu $officeIndex page option $($page + 1) branches incorrectly."

                [byte[]]$pageScript = $state[1].replacementEvents[
                    $pageEvents[$officeIndex * 3 + $page]].ToArray()
                Assert-True (-not (Contains-Bytes $pageScript $eightChoicePrefix)) `
                    "Open menu $officeIndex page $($page + 1) contains an eight-choice selector."
                $pageChoiceCounts = @(Get-ChoiceCounts $pageScript)
                Assert-True ($pageChoiceCounts.Count -eq 1 -and $pageChoiceCounts[0] -eq 3) `
                    "Open menu $officeIndex page $($page + 1) is not exactly three choices."

                $selectionStart = [Array]::IndexOf($pageScript, [byte]0x58)
                $selectionEnd = -1
                for($i = $selectionStart + 1; $i -lt $pageScript.Length; $i++) {
                    if($pageScript[$i] -eq 0x5B) { $selectionEnd = $i; break }
                }
                Assert-True ($selectionEnd -gt $selectionStart) `
                    "Open menu $officeIndex page $($page + 1) has no selection terminator."
                Assert-True ($pageScript[$selectionEnd + 1] -eq $selectorJump[0] -and
                    $pageScript[$selectionEnd + 2] -eq $selectorJump[1]) `
                    "Open menu $officeIndex page $($page + 1) cancel does not return to the selector."

                $firstOption = $page * 3
                $routeCount = [Math]::Min(3, 8 - $firstOption)
                Assert-True (($page -lt 2 -and $routeCount -eq 3) -or
                    ($page -eq 2 -and $routeCount -eq 2)) `
                    "Open menu $officeIndex page $($page + 1) has the wrong destination count."
                for($localOption = 0; $localOption -lt $routeCount; $localOption++) {
                    $globalOption = $firstOption + $localOption
                    $destination = $network.Offices[$officeIndex].Routes[$globalOption].Destination
                    [byte[]]$routeJump = $eventScriptType.GetMethod('GetJumpCmd').Invoke(
                        $null, [object[]]@($routeEvents[$officeIndex * 8 + $globalOption]))
                    $commandOffset = $selectionEnd + 3 + $localOption * 2
                    Assert-True ($pageScript[$commandOffset] -eq $routeJump[0] -and
                        $pageScript[$commandOffset + 1] -eq $routeJump[1]) `
                        "Open menu $officeIndex page $($page + 1) number $($globalOption + 1) maps incorrectly."
                    [byte[]]$numberBytes = $getDialogueBytes.Invoke(
                        $null, [object[]]@(($globalOption + 1).ToString())).ToArray()
                    Assert-True (Contains-Bytes $pageScript (@([byte]0x5A,
                        [byte](2 + $localOption * 5)) + $numberBytes)) `
                        "Open menu $officeIndex page $($page + 1) omits choice number $($globalOption + 1)."
                    [byte[]]$fullNameBytes = $getDialogueBytes.Invoke(
                        $null, [object[]]@("$($globalOption + 1):$($destination.DisplayName)")).ToArray()
                    Assert-True (Contains-Bytes $pageScript $fullNameBytes) `
                        "Open menu $officeIndex page $($page + 1) omits full destination name $($destination.DisplayName)."
                }
                if($page -eq 2) {
                    $backCommandOffset = $selectionEnd + 3 + 2 * 2
                    Assert-True ($pageScript[$backCommandOffset] -eq $selectorJump[0] -and
                        $pageScript[$backCommandOffset + 1] -eq $selectorJump[1]) `
                        "Open menu $officeIndex page 3 Back does not return to the selector."
                    [byte[]]$backBytes = $getDialogueBytes.Invoke(
                        $null, [object[]]@('Back')).ToArray()
                    Assert-True (Contains-Bytes $pageScript (@([byte]0x5A,0x0C) + $backBytes)) `
                        "Open menu $officeIndex page 3 does not label its Back choice."
                }
            }
        }

        $potosOfficeIndex = 0
        while($network.Offices[$potosOfficeIndex].Office.Id -ne 'potos') { $potosOfficeIndex++ }
        $potosOffice = $network.Offices[$potosOfficeIndex]
        foreach($expectedRoute in @(
            @('waterPalace',0x29,0x84,0xB7), @('kakkara',0x2C,0x28,0x5D),
            @('iceCountry',0x2E,0xA7,0x0B), @('pandora',0x2B,0x95,0xD8))) {
            $localIndex = 0
            while($potosOffice.Routes[$localIndex].Destination.Id -ne $expectedRoute[0]) { $localIndex++ }
            $globalIndex = $potosOfficeIndex * 8 + $localIndex
            $routeId = $globalIndex
            Assert-True ($routeId -eq $expectedRoute[1]) `
                (("Open Potos -> {0} route ID is `${1:X2}; expected `${2:X2}." -f
                    $expectedRoute[0],$routeId,$expectedRoute[1]))
            $descriptorOffset = $tableOffset + $routeId * 4
            Assert-True ($outRom[$descriptorOffset] -eq 0x9B -and
                $outRom[$descriptorOffset + 1] -eq 0xBF -and
                $outRom[$descriptorOffset + 2] -eq $expectedRoute[2] -and
                $outRom[$descriptorOffset + 3] -eq $expectedRoute[3]) `
                "Open Potos -> $($expectedRoute[0]) descriptor is not canonical."
            [byte[]]$routeScript = $state[1].replacementEvents[$routeEvents[$globalIndex]].ToArray()
            $commandOffset = Find-Bytes $routeScript ([byte[]]@(0x1D))
            $operand = $routeScript[$commandOffset + 1]
            Assert-True ($operand -eq $routeId -and ($operand -band 0x3F) -eq $routeId -and
                ($operand -band 0x40) -eq 0) `
                "Open Potos -> $($expectedRoute[0]) event operand does not address its descriptor exactly."
        }
    } elseif($mode -eq 'shuffle') {
        Assert-True ($routeIndex -eq 14) 'Shuffle did not emit 14 descriptors.'
        Assert-True ($firstRouteId -eq 0x20 -and
            $firstRouteId + $routeIndex - 1 -eq 0x2D) `
            'Shuffle did not retain its six-bit route range $20-$2D.'
        foreach($office in $network.Offices) {
            [byte[]]$menu = $state[1].replacementEvents[$office.Office.MenuEvent].ToArray()
            foreach($route in $office.Routes) {
                [byte[]]$nameBytes = $getDialogueBytes.Invoke(
                    $null, [object[]]@($route.Destination.DisplayName)).ToArray()
                Assert-True (Contains-Bytes $menu $nameBytes) `
                    "Shuffle menu label does not match $($route.Destination.DisplayName)."
            }
        }
    } else {
        Assert-True ($routeIndex -eq 0) 'All-closed Chaos test unexpectedly emitted a route.'
        $optionSelection = [byte]$eventCommandType.GetField('OPTION_SELECTION').GetValue($null).Value
        foreach($office in $network.Offices) {
            Assert-True $office.IsClosed 'All-closed Chaos test left an office functioning.'
            [byte[]]$closedScript = $state[1].replacementEvents[$office.Office.MenuEvent].ToArray()
            Assert-True (-not ($closedScript -contains $optionSelection)) `
                "Closed Chaos office $($office.Office.Id) opened a choice menu."
        }
    }
}

Write-Output 'PASS: Cannon Travel setting, deterministic networks, constraints, reachability, hooks, tables, and events verified.'
