param(
    [string]$AssemblyPath = (Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe'),
    [string]$SourceRom = 'D:\views\tools\bots\Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc',
    [string]$OutputRoot = (Join-Path ([IO.Path]::GetTempPath()) ('somr-crystal-orb-smoke-' + [Guid]::NewGuid().ToString('N')))
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

function Invoke-SmokeGeneration([string]$Name, [string]$Seed, [bool]$Enabled,
    [string]$StartingCharacter = 'boy', [string]$OtherCharacters = 'findbothL1') {
    $caseDirectory = Join-Path $OutputRoot $Name
    [IO.Directory]::CreateDirectory($caseDirectory) | Out-Null
    $destination = Join-Path $caseDirectory ($Name + '.sfc')

    $common = [Activator]::CreateInstance($commonType)
    $settings = [Activator]::CreateInstance($settingsType, [object[]]@($common))
    $common.set('mode', 'open') | Out-Null
    $common.set('version', '1.49') | Out-Null
    $common.set('spoilerLog', 'yes') | Out-Null
    $settings.set('crystalOrbWeaponBreaking', $(if($Enabled) { 'on' } else { 'off' })) | Out-Null
    $settings.set('opStartChar', $StartingCharacter) | Out-Null
    $settings.set('opCharacters', $OtherCharacters) | Out-Null

    $generator = [Activator]::CreateInstance($openGeneratorType)
    $generatorDictionaryType = [System.Collections.Generic.Dictionary``2].MakeGenericType(
        [string], $romGeneratorType)
    $settingsDictionaryType = [System.Collections.Generic.Dictionary``2].MakeGenericType(
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
    $emittedGeneralLog = Join-Path $launchDirectory ('log_' + $Seed + '.txt')
    $emittedSpoilerLog = Join-Path $launchDirectory ('log_' + $Seed + '_SPOILER.txt')
    if((Test-Path $emittedGeneralLog) -and $emittedGeneralLog -ne $generalLog) {
        [IO.File]::Move($emittedGeneralLog, $generalLog)
    }
    if((Test-Path $emittedSpoilerLog) -and $emittedSpoilerLog -ne $spoilerLog) {
        [IO.File]::Move($emittedSpoilerLog, $spoilerLog)
    }
    Assert-True (Test-Path $generalLog) "$Name did not emit its generation log."
    Assert-True ((Get-Content $generalLog -Raw) -match '\[general\] Done!') "$Name did not finish generation."
    $allLogText = (Get-Content $generalLog -Raw) + $(if(Test-Path $spoilerLog) { Get-Content $spoilerLog -Raw } else { '' })
    Assert-True ($allLogText -notmatch 'TEST_PROFILE|TEMPORARY Crystal Orb requirement test bootstrap|CrystalOrbSequenceBreakTestBootstrap') `
        "$Name contains diagnostic bootstrap output."
    Assert-True ($allLogText -notmatch 'crystalOrbWeaponBreaking = sequenceBreak') `
        "$Name serialized the retired setting value."
    Assert-True ($allLogText -match ('crystalOrbWeaponBreaking = ' + $(if($Enabled) { 'on' } else { 'off' }))) `
        "$Name did not serialize the expected feature value."

    $requirements = @()
    if(Test-Path $spoilerLog) {
        $lines = Get-Content $spoilerLog
        $section = [Array]::IndexOf($lines, ($lines | Where-Object { $_ -match '\[Crystal Orb requirements\]' } | Select-Object -First 1))
        if($section -ge 0) {
            for($i = $section + 1; $i -lt $lines.Count; $i++) {
                if($lines[$i] -match '\[spoiler\] \[') { break }
                if($lines[$i] -match '\[spoiler\] ((?:Earth Palace|Matango|Fire Palace [123]|Upper Land|Luna Palace|Grand Palace [1-7])): (.+)$') {
                    $requirements += $Matches[1] + ': ' + $Matches[2]
                } else {
                    break
                }
            }
        }
    }
    if($Enabled) {
        Assert-True ($requirements.Count -gt 0) "$Name did not log resolved Crystal Orb requirements."
        Assert-True ($allLogText -notmatch '\[Orb elements\]') `
            "$Name logged the legacy Orb Elements section while custom requirements were active."
    } else {
        Assert-True ($requirements.Count -eq 0) "$Name logged custom requirements while Off."
        Assert-True ($allLogText -match '\[Orb elements\]') `
            "$Name removed the upstream Orb Elements section while the feature was Off."
    }

    return [pscustomobject]@{
        Name = $Name
        Seed = $Seed
        Rom = $destination
        Sha256 = (Get-FileHash $destination -Algorithm SHA256).Hash
        Requirements = $requirements
    }
}

[IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
$results = @()
$results += Invoke-SmokeGeneration 'normal-on' 'CrystalOrb-Polish-Normal' $true
$results += Invoke-SmokeGeneration 'boy-only-on' 'CrystalOrb-Polish-BoyOnly' $true 'boy' 'none'
$results += Invoke-SmokeGeneration 'girl-only-on' 'CrystalOrb-Polish-GirlOnly' $true 'girl' 'none'
$results += Invoke-SmokeGeneration 'off-control' 'CrystalOrb-Polish-Off' $false
$results += Invoke-SmokeGeneration 'full-playthrough-a' 'CrystalOrb-FullPlaythrough-2026' $true
$results += Invoke-SmokeGeneration 'full-playthrough-b' 'CrystalOrb-FullPlaythrough-2026' $true

$fullA = $results | Where-Object Name -eq 'full-playthrough-a'
$fullB = $results | Where-Object Name -eq 'full-playthrough-b'
Assert-True ($fullA.Sha256 -eq $fullB.Sha256) 'Repeated full-playthrough generation was not byte-deterministic.'
Assert-True (($fullA.Requirements -join '|') -eq ($fullB.Requirements -join '|')) `
    'Repeated full-playthrough requirement resolution diverged.'

$results | ForEach-Object {
    Write-Output ("SMOKE {0}: seed={1}; sha256={2}; requirements={3}" -f
        $_.Name, $_.Seed, $_.Sha256, ($_.Requirements -join ' | '))
}
Write-Output "PASS: six Open World smoke generations completed in $OutputRoot"
