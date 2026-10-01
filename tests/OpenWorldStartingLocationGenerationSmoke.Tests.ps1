param(
    [string]$AssemblyPath = (Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe'),
    [string]$SourceRom = 'D:\views\tools\bots\Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc',
    [string]$OutputRoot = (Join-Path ([IO.Path]::GetTempPath()) ('somr-start-location-smoke-' + [Guid]::NewGuid().ToString('N'))),
    [switch]$ManualOnly
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

function Invoke-Generation([string]$Name, [string]$Seed, [bool]$FlammieInLogic,
    [string]$StartingLocation, [string]$CannonMode, [bool]$SetLocationExplicitly = $true) {
    $caseDirectory = Join-Path $OutputRoot $Name
    [IO.Directory]::CreateDirectory($caseDirectory) | Out-Null
    $destination = Join-Path $caseDirectory ($Name + '.sfc')
    $common = [Activator]::CreateInstance($commonType)
    $settings = [Activator]::CreateInstance($settingsType, [object[]]@($common))
    $common.set('mode','open') | Out-Null
    $common.set('version','1.49') | Out-Null
    $common.set('spoilerLog','yes') | Out-Null
    $settings.set('opLogic','restrictive') | Out-Null
    $settings.set('opFlammieDrumInLogic',$(if($FlammieInLogic){'yes'}else{'no'})) | Out-Null
    $settings.set('cannonTravelRandomization',$CannonMode) | Out-Null
    $settings.set('opStartGold','100') | Out-Null
    if($SetLocationExplicitly) {
        $settings.set('opStartingLocation',$StartingLocation) | Out-Null
    }

    $generator = [Activator]::CreateInstance($openGeneratorType)
    $generatorDictionaryType = [Collections.Generic.Dictionary``2].MakeGenericType([string],$romGeneratorType)
    $settingsDictionaryType = [Collections.Generic.Dictionary``2].MakeGenericType([string],$randoSettingsType)
    $generators = [Activator]::CreateInstance($generatorDictionaryType)
    $settingsByMode = [Activator]::CreateInstance($settingsDictionaryType)
    $generators.Add('open',$generator)
    $settingsByMode.Add('open',$settings)

    Push-Location $caseDirectory
    try {
        [object[]]$args = @([string]$SourceRom,[string]$destination,[string]$Seed,$generators,$common,$settingsByMode)
        $romGeneratorType.GetMethod('initGeneration').Invoke($null,$args) | Out-Null
    }
    finally { Pop-Location }

    Assert-True (Test-Path $destination) "$Name did not emit a ROM."
    Assert-True ((Get-Item $destination).Length -eq 0x400000) "$Name ROM is not 4 MiB."
    foreach($suffix in @('.txt','_SPOILER.txt')) {
        $logName = 'log_' + $Seed + $suffix
        $emitted = Join-Path $launchDirectory $logName
        $wanted = Join-Path $caseDirectory $logName
        if((Test-Path $emitted) -and $emitted -ne $wanted) {
            if(Test-Path $wanted) { Remove-Item -LiteralPath $wanted -Force }
            [IO.File]::Move($emitted,$wanted)
        }
    }
    $logPath = Join-Path $caseDirectory ('log_' + $Seed + '.txt')
    Assert-True (Test-Path $logPath) "$Name did not emit a generation log."
    $log = Get-Content $logPath -Raw
    Assert-True ($log -match '\[general\] Done!') "$Name did not finish generation."
    Assert-True ($log -match ('opStartingLocation = ' + [regex]::Escape($StartingLocation))) `
        "$Name did not serialize the selected Starting Location."

    [byte[]]$rom = [IO.File]::ReadAllBytes($destination)
    [int]$door82 = 0x83000 + 0x82 * 4
    [byte[]]$startDoor = $rom[$door82..($door82 + 3)]
    [byte[]]$expectedDoor = if($FlammieInLogic -and $StartingLocation -eq 'kakkara') {
        [byte[]](0x59,0x3A,0x48,0x00)
    } elseif($FlammieInLogic) {
        [byte[]](0x02,0x71,0x1B,0x00)
    } else {
        [byte[]]$source = [IO.File]::ReadAllBytes((Resolve-Path $SourceRom).Path)
        [byte[]]($source[$door82..($door82 + 3)])
    }
    Assert-True ([Linq.Enumerable]::SequenceEqual($expectedDoor,$startDoor)) "$Name emitted the wrong start door."

    return [pscustomobject]@{
        Name=$Name; Seed=$Seed; Flammie=$FlammieInLogic; StartingLocation=$StartingLocation;
        Cannon=$CannonMode; Rom=$destination; Log=$logPath;
        Spoiler=(Join-Path $caseDirectory ('log_' + $Seed + '_SPOILER.txt'));
        Sha256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    }
}

[IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
$manual = Invoke-Generation 'Kakkara-Start-Manual-2026' 'Kakkara-Start-Manual-2026' $true 'kakkara' 'off'
if($ManualOnly) {
    Write-Output ("MANUAL: seed={0}; sha256={1}; rom={2}; log={3}; spoiler={4}" -f
        $manual.Seed,$manual.Sha256,$manual.Rom,$manual.Log,$manual.Spoiler)
    return
}
$results = @()
$results += Invoke-Generation 'default-implicit' 'StartingLocation-Default-Control' $true 'default' 'off' $false
$results += Invoke-Generation 'default-explicit' 'StartingLocation-Default-Control' $true 'default' 'off'
$results += Invoke-Generation 'pedestal-default' 'StartingLocation-Pedestal-Control' $false 'default' 'off'
$results += Invoke-Generation 'pedestal-kakkara-ignored' 'StartingLocation-Pedestal-Control' $false 'kakkara' 'off'
$results += $manual
$results += Invoke-Generation 'kakkara-off-b' 'Kakkara-Start-Manual-2026' $true 'kakkara' 'off'
$results += Invoke-Generation 'kakkara-open' 'Kakkara-Start-Open-2026' $true 'kakkara' 'open'
$results += Invoke-Generation 'kakkara-shuffle' 'Kakkara-Start-Shuffle-2026' $true 'kakkara' 'shuffle'
$results += Invoke-Generation 'kakkara-chaos' 'Kakkara-Start-Chaos-2026' $true 'kakkara' 'chaos'

Assert-True ($results[0].Sha256 -eq $results[1].Sha256) 'Explicit Default changed the existing seed output.'
Assert-True ($results[2].Sha256 -eq $results[3].Sha256) 'Kakkara changed the pedestal path while Flammie was out of logic.'
Assert-True ($results[4].Sha256 -eq $results[5].Sha256) 'Kakkara generation was not byte-deterministic.'

$results | ForEach-Object {
    Write-Output ("SMOKE {0}: seed={1}; cannon={2}; sha256={3}; rom={4}" -f $_.Name,$_.Seed,$_.Cannon,$_.Sha256,$_.Rom)
}
Write-Output "PASS: nine Starting Location generations completed in $OutputRoot"
