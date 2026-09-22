param(
    [string]$AssemblyPath = (Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe'),
    [string]$SourceRom = 'D:\views\tools\bots\Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc',
    [string]$OutputRoot = (Join-Path ([IO.Path]::GetTempPath()) ('somr-cannon-smoke-' + [Guid]::NewGuid().ToString('N')))
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path $AssemblyPath).Path)
$commonType = $assembly.GetType('SoMRandomizer.config.settings.CommonSettings', $true)
$settingsType = $assembly.GetType('SoMRandomizer.config.settings.OpenWorldSettings', $true)
$randoSettingsType = $assembly.GetType('SoMRandomizer.config.settings.RandoSettings', $true)
$romGeneratorType = $assembly.GetType('SoMRandomizer.processing.common.RomGenerator', $true)
$openGeneratorType = $assembly.GetType('SoMRandomizer.processing.openworld.OpenWorldGenerator', $true)
$launchDirectory = (Get-Location).Path

function Assert-True([bool]$Condition, [string]$Message) {
    if(-not $Condition) { throw $Message }
}

function Invoke-CannonSmoke([string]$Name, [string]$Seed, [string]$Mode,
    [string]$Goal = 'vshort', [string]$StartCharacter = 'boy',
    [string]$OtherCharacters = 'findbothL1', [bool]$FlammieInLogic = $false,
    [int]$StartGold = 0) {
    $caseDirectory = Join-Path $OutputRoot $Name
    [IO.Directory]::CreateDirectory($caseDirectory) | Out-Null
    $destination = Join-Path $caseDirectory ($Name + '.sfc')

    $common = [Activator]::CreateInstance($commonType)
    $settings = [Activator]::CreateInstance($settingsType, [object[]]@($common))
    $common.set('mode', 'open') | Out-Null
    $common.set('version', '1.49') | Out-Null
    $common.set('spoilerLog', 'yes') | Out-Null
    $settings.set('cannonTravelRandomization', $Mode) | Out-Null
    $settings.set('opGoal', $Goal) | Out-Null
    $settings.set('opStartChar', $StartCharacter) | Out-Null
    $settings.set('opCharacters', $OtherCharacters) | Out-Null
    $settings.set('opFlammieDrumInLogic', $(if($FlammieInLogic) { 'yes' } else { 'no' })) | Out-Null
    $settings.set('opStartGold', $StartGold.ToString()) | Out-Null

    $generator = [Activator]::CreateInstance($openGeneratorType)
    $generatorDictionaryType = [Collections.Generic.Dictionary``2].MakeGenericType(
        [string], $romGeneratorType)
    $settingsDictionaryType = [Collections.Generic.Dictionary``2].MakeGenericType(
        [string], $randoSettingsType)
    $generators = [Activator]::CreateInstance($generatorDictionaryType)
    $settingsByMode = [Activator]::CreateInstance($settingsDictionaryType)
    $generators.Add('open', $generator)
    $settingsByMode.Add('open', $settings)

    Push-Location $caseDirectory
    try {
        [object[]]$generationArgs = [object[]]::new(6)
        $generationArgs[0] = [string]$SourceRom
        $generationArgs[1] = [string]$destination
        $generationArgs[2] = [string]$Seed
        $generationArgs[3] = $generators
        $generationArgs[4] = $common
        $generationArgs[5] = $settingsByMode
        $romGeneratorType.GetMethod('initGeneration').Invoke($null, $generationArgs) | Out-Null
    }
    finally {
        Pop-Location
    }

    Assert-True (Test-Path $destination) "$Name did not emit a ROM."
    Assert-True ((Get-Item $destination).Length -eq 0x400000) "$Name ROM is not 4 MiB."
    $generalLog = Join-Path $caseDirectory ('log_' + $Seed + '.txt')
    $spoilerLog = Join-Path $caseDirectory ('log_' + $Seed + '_SPOILER.txt')
    $logNames = @(
        ('log_' + $Seed + '.txt'),
        ('log_' + $Seed + '_SPOILER.txt')
    )
    foreach($logName in $logNames) {
        $emitted = Join-Path $launchDirectory $logName
        $wanted = Join-Path $caseDirectory $logName
        if((Test-Path $emitted) -and $emitted -ne $wanted) { [IO.File]::Move($emitted, $wanted) }
    }
    Assert-True (Test-Path $generalLog) "$Name did not emit a generation log."
    Assert-True ((Get-Content $generalLog -Raw) -match '\[general\] Done!') "$Name did not finish generation."
    Assert-True (Test-Path $spoilerLog) "$Name did not emit a spoiler log."
    $spoiler = Get-Content $spoilerLog -Raw
    if($Mode -eq 'off') {
        Assert-True ($spoiler -notmatch '\[Cannon Travel\]') 'Off emitted a Cannon spoiler section.'
    } else {
        Assert-True ($spoiler -match '\[Cannon Travel\]') "$Name omitted the Cannon spoiler section."
        Assert-True ($spoiler -match ("Mode: " + $Mode)) "$Name logged the wrong Cannon mode."
    }

    $sectionLines = @()
    $allLines = Get-Content $spoilerLog
    $inSection = $false
    foreach($line in $allLines) {
        if($line -match '\[Cannon Travel\]') { $inSection = $true; continue }
        if($inSection -and $line -match '\[spoiler\] \[') { break }
        if($inSection) { $sectionLines += ($line -replace '^.*\[spoiler\]\s*','') }
    }

    return [pscustomobject]@{
        Name = $Name
        Seed = $Seed
        Mode = $Mode
        Goal = $Goal
        FlammieInLogic = $FlammieInLogic
        Rom = $destination
        Sha256 = (Get-FileHash $destination -Algorithm SHA256).Hash
        CannonSpoiler = ($sectionLines -join "`n")
    }
}

function Get-ChaosTraits([string]$CannonSpoiler) {
    $officeRegions = @{
        'Upper Land'='UpperLand'; 'Southtown'='SouthtownEmpire'; 'Ice Country'='IceCountry';
        'Kakkara'='Kakkara'; 'Matango'='Matango'; 'Potos'='PotosArea'; "Gaia's Navel"='PotosArea'
    }
    $destinationRegions = @{
        'Potos'='PotosArea'; "Gaia's Navel"='PotosArea'; 'Water Palace'='PotosArea';
        'Upper Land'='UpperLand'; 'Pandora'='PotosArea'; 'Kakkara'='Kakkara';
        'Matango'='Matango'; 'Ice Country'='IceCountry'; 'Southtown'='SouthtownEmpire'
    }
    $graph = @{}
    foreach($region in @('PotosArea','UpperLand','Matango','Kakkara','IceCountry','SouthtownEmpire')) {
        $graph[$region] = [Collections.Generic.HashSet[string]]::new()
    }
    $allDestinations = @()
    $closed = $false
    foreach($line in ($CannonSpoiler -split "`n")) {
        if($line -notmatch '^(.+?): (.+)$') { continue }
        $officeName = $Matches[1]
        $routeText = $Matches[2]
        if(-not $officeRegions.ContainsKey($officeName)) { continue }
        if($routeText -match '^CLOSED') { $closed = $true; continue }
        foreach($destinationName in ($routeText -split ', ')) {
            if($destinationRegions.ContainsKey($destinationName)) {
                $allDestinations += $destinationName
                $graph[$officeRegions[$officeName]].Add($destinationRegions[$destinationName]) | Out-Null
            }
        }
    }

    function Reach([string]$Start, [string]$Target) {
        $seen = [Collections.Generic.HashSet[string]]::new()
        $queue = [Collections.Generic.Queue[string]]::new()
        $seen.Add($Start) | Out-Null; $queue.Enqueue($Start)
        while($queue.Count -gt 0) {
            $current = $queue.Dequeue()
            if($current -eq $Target) { return $true }
            foreach($next in $graph[$current]) { if($seen.Add($next)) { $queue.Enqueue($next) } }
        }
        return $false
    }

    $regions = @($graph.Keys)
    $multipleComponents = $false
    foreach($a in $regions) { foreach($b in $regions) {
        if(-not (Reach $a $b) -or -not (Reach $b $a)) { $multipleComponents = $true }
    }}
    $duplicate = @($allDestinations | Group-Object | Where-Object Count -gt 1).Count -gt 0
    $missing = @($destinationRegions.Keys | Where-Object { $allDestinations -notcontains $_ }).Count -gt 0
    $flammieRelevant = @($regions | Where-Object { -not (Reach 'PotosArea' $_) }).Count -gt 0
    return [pscustomobject]@{
        Closed = $closed; Duplicate = $duplicate; Missing = $missing;
        MultipleComponents = $multipleComponents; FlammieRelevant = $flammieRelevant
    }
}

[IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
$results = @()
$results += Invoke-CannonSmoke 'off-control' 'Cannon-Off-Control' 'off'
$results += Invoke-CannonSmoke 'open-control' 'Cannon-Open-Control' 'open' 'vlong' 'girl' 'findbothCL' $true 1000

$shuffleCases = @(
    @('shuffle-a','Cannon-Shuffle-A','vshort','boy','findbothL1',$false),
    @('shuffle-b','Cannon-Shuffle-B','vlong','sprite','start1find1',$true),
    @('shuffle-c','Cannon-Shuffle-C','mtr','girl','findbothCL',$true),
    @('shuffle-d','Cannon-Shuffle-D','reindeer','boy','findbothL1',$false)
)
foreach($case in $shuffleCases) {
    $results += Invoke-CannonSmoke $case[0] $case[1] 'shuffle' $case[2] $case[3] $case[4] $case[5]
}
$results += Invoke-CannonSmoke 'shuffle-a-repeat' 'Cannon-Shuffle-A' 'shuffle' 'vshort' 'boy' 'findbothL1' $false

$chaosCases = @(
    @('chaos-a','Cannon-Chaos-A','vshort','boy','findbothL1',$true),
    @('chaos-b','Cannon-Chaos-B','vlong','girl','start1only',$true),
    @('chaos-c','Cannon-Chaos-C','mtr','sprite','findbothCL',$true),
    @('chaos-d','Cannon-Chaos-D','gift','boy','findbothL1',$true),
    @('chaos-e','Cannon-Chaos-E','reindeer','girl','findbothL1',$true),
    @('chaos-f','Cannon-Chaos-F','vshort','sprite','none',$true)
)
foreach($case in $chaosCases) {
    $results += Invoke-CannonSmoke $case[0] $case[1] 'chaos' $case[2] $case[3] $case[4] $case[5]
}
$results += Invoke-CannonSmoke 'chaos-a-repeat' 'Cannon-Chaos-A' 'chaos' 'vshort' 'boy' 'findbothL1' $true

$shuffleA = $results | Where-Object Name -eq 'shuffle-a'
$shuffleRepeat = $results | Where-Object Name -eq 'shuffle-a-repeat'
$chaosA = $results | Where-Object Name -eq 'chaos-a'
$chaosRepeat = $results | Where-Object Name -eq 'chaos-a-repeat'
Assert-True ($shuffleA.Sha256 -eq $shuffleRepeat.Sha256) 'Repeated Shuffle ROM hash diverged.'
Assert-True ($shuffleA.CannonSpoiler -eq $shuffleRepeat.CannonSpoiler) 'Repeated Shuffle spoiler diverged.'
Assert-True ($chaosA.Sha256 -eq $chaosRepeat.Sha256) 'Repeated Chaos ROM hash diverged.'
Assert-True ($chaosA.CannonSpoiler -eq $chaosRepeat.CannonSpoiler) 'Repeated Chaos spoiler diverged.'

$traits = @($results | Where-Object Mode -eq 'chaos' | ForEach-Object { Get-ChaosTraits $_.CannonSpoiler })
Assert-True (@($traits | Where-Object Closed).Count -gt 0) 'Chaos smokes did not include a closed office.'
Assert-True (@($traits | Where-Object Duplicate).Count -gt 0) 'Chaos smokes did not include a repeated destination.'
Assert-True (@($traits | Where-Object Missing).Count -gt 0) 'Chaos smokes did not include a missing destination.'
Assert-True (@($traits | Where-Object MultipleComponents).Count -gt 0) 'Chaos smokes did not include multiple SCCs.'
Assert-True (@($traits | Where-Object FlammieRelevant).Count -gt 0) 'Chaos smokes did not make Flammie relevant.'

$results | ForEach-Object {
    Write-Output ("SMOKE {0}: mode={1}; goal={2}; flammieLogic={3}; seed={4}; sha256={5}" -f
        $_.Name,$_.Mode,$_.Goal,$_.FlammieInLogic,$_.Seed,$_.Sha256)
    if($_.Mode -ne 'off') { Write-Output $_.CannonSpoiler }
}
Write-Output "PASS: $($results.Count) Cannon Travel Open World generations completed in $OutputRoot"
