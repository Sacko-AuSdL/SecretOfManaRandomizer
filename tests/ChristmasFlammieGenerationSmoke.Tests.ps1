param(
    [string]$AssemblyPath = (Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe'),
    [string]$SourceRom = 'D:\views\tools\bots\Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc',
    [string]$OutputRoot = (Join-Path ([IO.Path]::GetTempPath()) ('somr-christmas-flammie-' + [Guid]::NewGuid().ToString('N')))
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

function Invoke-ChristmasSmoke(
    [string]$Name,
    [string]$Seed,
    [string]$CannonMode,
    [string]$Goal = 'gift',
    [bool]$FlammieInLogic = $true
) {
    $caseDirectory = Join-Path $OutputRoot $Name
    [IO.Directory]::CreateDirectory($caseDirectory) | Out-Null
    $destination = Join-Path $caseDirectory ($Name + '.sfc')

    $common = [Activator]::CreateInstance($commonType)
    $settings = [Activator]::CreateInstance($settingsType, [object[]]@($common))
    $common.set('mode', 'open') | Out-Null
    $common.set('version', '1.49') | Out-Null
    $common.set('spoilerLog', 'yes') | Out-Null
    $settings.set('opGoal', $Goal) | Out-Null
    $settings.set('opStartChar', 'boy') | Out-Null
    $settings.set('opCharacters', 'findbothL1') | Out-Null
    $settings.set('opFlammieDrumInLogic', $(if($FlammieInLogic) { 'yes' } else { 'no' })) | Out-Null
    $settings.set('cannonTravelRandomization', $CannonMode) | Out-Null

    $generator = [Activator]::CreateInstance($openGeneratorType)
    $generatorDictionaryType = [Collections.Generic.Dictionary``2].MakeGenericType([string], $romGeneratorType)
    $settingsDictionaryType = [Collections.Generic.Dictionary``2].MakeGenericType([string], $randoSettingsType)
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

    foreach($suffix in @('.txt', '_SPOILER.txt')) {
        $logName = 'log_' + $Seed + $suffix
        $emitted = Join-Path $launchDirectory $logName
        $wanted = Join-Path $caseDirectory $logName
        if((Test-Path $emitted) -and $emitted -ne $wanted) {
            [IO.File]::Move($emitted, $wanted)
        }
    }

    $generalLog = Join-Path $caseDirectory ('log_' + $Seed + '.txt')
    $spoilerLog = Join-Path $caseDirectory ('log_' + $Seed + '_SPOILER.txt')
    Assert-True (Test-Path $destination) "$Name did not emit a ROM."
    Assert-True ((Get-Item $destination).Length -eq 0x400000) "$Name ROM is not 4 MiB."
    Assert-True (Test-Path $generalLog) "$Name did not emit a generation log."
    Assert-True ((Get-Content $generalLog -Raw) -match '\[general\] Done!') "$Name did not finish generation."
    Assert-True (Test-Path $spoilerLog) "$Name did not emit a spoiler log."
    $spoiler = Get-Content $spoilerLog -Raw

    return [pscustomobject]@{
        Name = $Name
        Seed = $Seed
        CannonMode = $CannonMode
        Goal = $Goal
        FlammieInLogic = $FlammieInLogic
        Sha256 = (Get-FileHash $destination -Algorithm SHA256).Hash
        Spoiler = $spoiler
    }
}

[IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
$results = @()
$results += Invoke-ChristmasSmoke 'gift-off' 'Christmas-Flammie-Off' 'off'
$results += Invoke-ChristmasSmoke 'gift-open' 'Christmas-Flammie-Open' 'open'
$results += Invoke-ChristmasSmoke 'gift-shuffle' 'Christmas-Flammie-Shuffle' 'shuffle'
$results += Invoke-ChristmasSmoke 'gift-chaos' 'Christmas-Flammie-Chaos' 'chaos'
$results += Invoke-ChristmasSmoke 'gift-outside-logic' 'Christmas-Flammie-Outside-Logic' 'off' 'gift' $false
$results += Invoke-ChristmasSmoke 'reindeer-control' 'Christmas-Reindeer-Control' 'shuffle' 'reindeer' $true
$results += Invoke-ChristmasSmoke 'gift-off-repeat' 'Christmas-Flammie-Off' 'off'

$first = $results | Where-Object Name -eq 'gift-off'
$repeat = $results | Where-Object Name -eq 'gift-off-repeat'
$open = $results | Where-Object Name -eq 'gift-open'
$chaos = $results | Where-Object Name -eq 'gift-chaos'
Assert-True ($first.Sha256 -eq $repeat.Sha256) 'Repeated Christmas generation produced a different ROM hash.'
Assert-True ($first.Spoiler -match 'Xmas gift -- Jehk in the mountains') `
    'Cannon Off regression seed no longer selects Jehk as a delivery target.'
Assert-True ($open.Spoiler -match 'Xmas gift -- Johk in the mountains') `
    'Cannon Open regression seed no longer selects Johk as a delivery target.'
Assert-True ($chaos.Spoiler -match 'Xmas gift -- Jehk in the mountains') `
    'Cannon Chaos regression seed no longer selects Jehk as a delivery target.'
foreach($case in @($first, $open, $chaos)) {
    Assert-True ($case.Spoiler -notmatch 'santa gift \d+ -> flammie drum') `
        "$($case.Name) placed Flammie behind its Lofty Mountains delivery chain."
}

$results | ForEach-Object {
    Write-Output ('SMOKE {0}: goal={1}; cannon={2}; flammieLogic={3}; seed={4}; sha256={5}' -f
        $_.Name, $_.Goal, $_.CannonMode, $_.FlammieInLogic, $_.Seed, $_.Sha256)
}
Write-Output "PASS: $($results.Count) Christmas/Reindeer generations completed deterministically in $OutputRoot"
