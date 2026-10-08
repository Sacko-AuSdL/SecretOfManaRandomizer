param(
    [string]$AssemblyPath=(Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe'),
    [string]$SourceRom='D:\views\tools\bots\Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc',
    [string]$OutputRoot=(Join-Path ([IO.Path]::GetTempPath()) ('somr-sandship-'+[Guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference='Stop'
function Assert-True([bool]$Condition,[string]$Message) { if(-not $Condition) { throw $Message } }
function Same($A,$B) { return [Linq.Enumerable]::SequenceEqual([byte[]]$A,[byte[]]$B) }
$path=(Resolve-Path $AssemblyPath).Path
$a=[Reflection.Assembly]::LoadFrom($path)
$compiler=[Microsoft.CSharp.CSharpCodeProvider]::new()
$params=[CodeDom.Compiler.CompilerParameters]::new(); $params.GenerateInMemory=$true
[void]$params.ReferencedAssemblies.Add($path); [void]$params.ReferencedAssemblies.Add('System.Core.dll')
$compiled=$compiler.CompileAssemblyFromFile($params,(Join-Path $PSScriptRoot 'support\SandshipTestGenerator.cs'))
if($compiled.Errors.HasErrors) { throw ($compiled.Errors | Out-String) }
$capture=$compiled.CompiledAssembly.GetType('SandshipTestGenerator',$true)
[byte[]]$original=[IO.File]::ReadAllBytes((Resolve-Path $SourceRom).Path)
[void]$capture.GetMethod('CheckNative').Invoke($null,@(,$original))
'PASS: native routes, local terrain, trigger ownership, boss/crew state, entry and compatibility pool.'
function T($Name) { return $a.GetType('SoMRandomizer.'+$Name,$true) }
$common=T 'config.settings.CommonSettings'; $settings=T 'config.settings.OpenWorldSettings'
$generator=T 'processing.common.RomGenerator'; $baseSettings=T 'config.settings.RandoSettings'
$locations=T 'processing.openworld.randomization.OpenWorldLocations'
$mapUtil=T 'processing.common.VanillaMapUtil'
function Generate([string]$Name,[string]$Cannon) {
    $directory=Join-Path $OutputRoot $Name; [void][IO.Directory]::CreateDirectory($directory)
    $rom=Join-Path $directory ($Name+'.sfc'); $seed='Sandship-Structural-2026'
    $c=[Activator]::CreateInstance($common); $s=[Activator]::CreateInstance($settings,[object[]]@($c))
    $c.set('mode','open'); $c.set('version','1.49'); $c.set('spoilerLog','yes'); $c.set('debugLoggingEnabled','yes')
    foreach($p in @(@('opStartingLocation','kakkara'),@('opFlammieDrumInLogic','yes'),@('opBosses','random'),@('opLogic','restrictive'),@('opCharacters','startboth'),@('cannonTravelRandomization',$Cannon),@('crystalOrbWeaponBreaking','off'),@('plandoSettings','P_mechRider1:Mantis-Ant;p_Sandship-Captain:Sea-Hare-Tail;'))) {$s.set($p[0],$p[1])}
    $g=[Activator]::CreateInstance($capture)
    $gs=[Activator]::CreateInstance([Collections.Generic.Dictionary``2].MakeGenericType([string],$generator))
    $ss=[Activator]::CreateInstance([Collections.Generic.Dictionary``2].MakeGenericType([string],$baseSettings))
    $gs.Add('open',$g); $ss.Add('open',$s)
    $old=[Environment]::CurrentDirectory
    Push-Location $directory; [Environment]::CurrentDirectory=$directory
    try {[void]$generator.GetMethod('initGeneration').Invoke($null,@([string]$SourceRom,[string]$rom,$seed,$gs,$c,$ss))}
    finally { [Environment]::CurrentDirectory=$old; Pop-Location }
    Assert-True (Test-Path $rom) "$Name did not generate."
    $log=Get-Content (Join-Path $directory ('log_'+$seed+'.txt')) -Raw
    $spoiler=Get-Content (Join-Path $directory ('log_'+$seed+'_SPOILER.txt')) -Raw
    Assert-True ($log -match '\[general\] Done!') "$Name failed simulation/generation."
    Assert-True ($spoiler -match 'sandship captain') 'Captain absent from spoiler.'
    Assert-True ($spoiler -match 'Morie at Sandship.*useful|useful.*Morie at Sandship') 'Morie hint not useful/logged.'
    $ctx=$capture.GetField('LastContext').GetValue($null)
    $locs=$capture.GetField('LastLocations').GetValue($null)
    $captains=@($locs | Where-Object locationName -eq 'sandship captain')
    Assert-True ($captains.Count -eq 1) 'Captain location not unique.'
    Assert-True ($captains[0].cannonTravelRegion.ToString() -eq 'Kakkara') 'Captain not in Kakkara region.'
    Assert-True ($captains[0].lockedByPrizes.Count -eq 0) 'Arbitrary traversal dependency added.'
    [byte[]]$ev=$ctx.replacementEvents[0x2A3].ToArray()
    Assert-True (Same $ev[0..4] ([byte[]]@(0x42,0x28,0x0E,0x10,0))) 'Captain boss-clear guard missing.'
    Assert-True ($ev[5] -eq 0x50 -and $ev[6] -eq 0x42 -and $ev[8] -eq 0x1F -and $ev[9] -eq 0x13 -and $ev[10] -eq 0x96) 'Normal one-shot prize guard missing.'
    Assert-True ($ev[11] -eq 0x30 -and $ev[12] -eq 0x29 -and $ev[13] -eq 1) 'Plando item did not reach Captain.'
    $state=[byte[]]::new(256)
    Assert-True ($capture.GetMethod('RunCaptain').Invoke($null,@($ev,14,$state)) -eq 0) 'Captain grants before victory.'
    $amount=$capture.GetMethod('RunCaptain').Invoke($null,@($ev,15,$state))
    Assert-True ($amount -gt 0) 'Captain does not grant first reward.'
    Assert-True ($capture.GetMethod('RunCaptain').Invoke($null,@($ev,15,$state)) -eq 0) 'Captain duplicates reward.'
    [byte[]]$r=[IO.File]::ReadAllBytes($rom)
    $obj=$mapUtil.GetMethod('getObjects').Invoke($null,@($r,340))
    Assert-True ($obj[0].getSpecies() -eq 0x57 -and $obj[0].getEvent() -eq 0x2A1) 'Sandship plando/death callback incorrect.'
    Assert-True (Same $r[0x8E345..0x8E34A] $original[0x8E345..0x8E34A]) 'Native C8 combat code corrupted.'
    Assert-True (Same $r[0x8364C..0x8364F] ([byte[]]@(0x54,0x21,0x28,0x80))) 'Boss entry door changed.'
    $triggers=$mapUtil.GetMethod('getTriggers').Invoke($null,@($r,92))
    Assert-True ($triggers.Count -eq 13 -and @($triggers | Where-Object {$_ -eq 0x28A}).Count -eq 3) 'Final south triggers incorrect.'
    return [pscustomobject]@{Cannon=$Cannon;Rom=$rom;Hash=(Get-FileHash $rom -Algorithm SHA256).Hash;Hint=[byte[]]$ctx.replacementEvents[0x2A2].ToArray();Event=$ev}
}
$first=Generate 'Off' 'off'; $repeat=Generate 'OffRepeat' 'off'
Assert-True ($first.Hash -eq $repeat.Hash -and (Same $first.Hint $repeat.Hint) -and (Same $first.Event $repeat.Event)) 'Seed/hint not deterministic.'
foreach($mode in @('open','shuffle','chaos')) {[void](Generate $mode $mode)}
'PASS: five generated worlds (paired determinism + all Cannon modes), Captain plando/check/spoiler, hint, simulation and final ROM.'
