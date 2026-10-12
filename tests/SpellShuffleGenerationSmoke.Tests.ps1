param(
    [string]$AssemblyPath = (Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe'),
    [string]$SourceRom = 'D:\views\tools\bots\Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc'
)
$ErrorActionPreference = 'Stop'
$path = (Resolve-Path $AssemblyPath).Path
$a = [Reflection.Assembly]::LoadFrom($path)
$compiler = [Microsoft.CSharp.CSharpCodeProvider]::new()
$parameters = [CodeDom.Compiler.CompilerParameters]::new()
$parameters.GenerateInMemory = $true
foreach($reference in @($path, 'System.dll', 'System.Core.dll')) { [void]$parameters.ReferencedAssemblies.Add($reference) }
$compiled = $compiler.CompileAssemblyFromFile($parameters, (Join-Path $PSScriptRoot 'support\SpellShuffleTestGenerator.cs'))
if($compiled.Errors.HasErrors) { throw ($compiled.Errors | Out-String) }
$generatorType = $compiled.CompiledAssembly.GetType('SpellShuffleTestGenerator', $true)
$commonType = $a.GetType('SoMRandomizer.config.settings.CommonSettings', $true)
$settingsType = $a.GetType('SoMRandomizer.config.settings.OpenWorldSettings', $true)
$original = [byte[]]::new(0x400000)
$native = [IO.File]::ReadAllBytes((Resolve-Path $SourceRom).Path)
[Array]::Copy($native, $original, $native.Length)
function Generate([string]$Seed, [string[]]$Roles, [string]$OrbMode, [string]$Party='findbothL1',
    [string]$Shuffle='perCharacter', [bool]$Omit=$false, [string]$Cannon='off') {
    $common = [Activator]::CreateInstance($commonType)
    $settings = [Activator]::CreateInstance($settingsType, [object[]]@($common))
    $common.set('mode', 'open'); $common.set('testOnly', 'yes'); $common.set('version', '1.49')
    $settings.set('spellShuffle', $Shuffle); $settings.set('crystalOrbWeaponBreaking', $OrbMode)
    $settings.set('opCharacters', $Party); $settings.set('opFlammieDrumInLogic', 'yes')
    $settings.set('opBoyRole', $Roles[0]); $settings.set('opGirlRole', $Roles[1]); $settings.set('opSpriteRole', $Roles[2])
    $settings.set('cannonTravelRandomization', $Cannon)
    $g = [Activator]::CreateInstance($generatorType, [object[]]@($Omit))
    $rom = [byte[]]$original.Clone()
    if(-not $g.generate($original, $rom, $Seed, $settings)) { throw "Generation failed: $Seed/$OrbMode/$Shuffle" }
    $signature = $generatorType.GetMethod('Validate').Invoke($null, [object[]]@($settings, $g.LastContext))
    [pscustomobject]@{Rom=$rom;Context=$g.LastContext;Signature=$signature}
}
$normal = @('OGboy','OGgirl','OGsprite')
$off = Generate 'SpellShuffle-Off-Control' $normal 'on' 'findbothL1' 'off'
$upstream = Generate 'SpellShuffle-Off-Control' $normal 'on' 'findbothL1' 'off' $true
if(-not [Linq.Enumerable]::SequenceEqual([byte[]]$off.Rom, [byte[]]$upstream.Rom)) { throw 'Off ROM differs from generator without shuffle processors.' }
if($off.Context.randomFunctional.Next() -ne $upstream.Context.randomFunctional.Next()) { throw 'Off advances extra RNG.' }
Write-Output 'PASS: Off is byte-identical to unchanged processor list, with identical final RNG.'
$cases = @(
    @('normal-magic', $normal, 'off', 'findbothL1', 'off'),
    @('normal-mixed', $normal, 'on', 'findbothL1', 'shuffle'),
    @('normal-weapons', $normal, 'weaponOnly', 'findbothL1', 'chaos'),
    @('three-sprites', @('OGsprite','OGsprite','OGsprite'), 'off', 'startboth', 'off'),
    @('three-girls', @('OGgirl','OGgirl','OGgirl'), 'off', 'startboth', 'off'),
    @('girls-sprite', @('OGgirl','OGgirl','OGsprite'), 'on', 'findbothL1', 'open'),
    @('boy-sprites', @('OGboy','OGsprite','OGsprite'), 'on', 'findbothL1', 'off'),
    @('girl-only', @('OGgirl','OGgirl','OGgirl'), 'off', 'none', 'off'),
    @('boy-only', $normal, 'on', 'none', 'off'),
    @('boy-only-orbs-off', $normal, 'off', 'none', 'off'),
    @('findable-caster', @('OGboy','OGboy','OGsprite'), 'off', 'findbothL1', 'off'))
$count=2
foreach($shuffleMode in @('perCharacter','party')) { foreach($case in $cases) {
    $name=[string]$case[0]
    $result=Generate ('SpellShuffle-Smoke-'+$name) $case[1] $case[2] $case[3] $shuffleMode $false $case[4]
    Write-Output "PASS: $shuffleMode / $name normal generation/simulation."
    $count++
    if($name -eq 'three-sprites') {
        $repeat=Generate ('SpellShuffle-Smoke-'+$name) $case[1] $case[2] $case[3] $shuffleMode
        if(-not [Linq.Enumerable]::SequenceEqual([byte[]]$result.Rom, [byte[]]$repeat.Rom)) { throw 'Repeated seed/settings ROM differs.' }
        $count++
    }
} }
Write-Output "PASS: $count in-memory Open World generations; no ROMs/per-seed logs emitted."
