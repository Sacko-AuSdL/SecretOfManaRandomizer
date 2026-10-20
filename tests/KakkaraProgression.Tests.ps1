param(
 [string]$AssemblyPath='',
 [Parameter(Mandatory=$true)][string]$SourceRom,
 [string]$OutputRoot=(Join-Path ([IO.Path]::GetTempPath()) ('somr-kakkara-progression-'+[Guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference='Stop'
if(-not $AssemblyPath){$AssemblyPath=Join-Path $PSScriptRoot '../SoMRandomizer/bin/Debug/net462/SoMRandomizer.exe'}
$path=(Resolve-Path $AssemblyPath).Path
$assembly=[Reflection.Assembly]::LoadFrom($path)
$resolver=[Delegate]::CreateDelegate([ResolveEventHandler],$assembly.GetType('SoMRandomizer.Program').GetMethod('OnResolveAssembly',[Reflection.BindingFlags]'NonPublic,Static'))
[AppDomain]::CurrentDomain.add_AssemblyResolve($resolver)
$cp=[CodeDom.Compiler.CompilerParameters]::new();$cp.GenerateInMemory=$true
foreach($ref in @($path,'System.dll','System.Core.dll')){[void]$cp.ReferencedAssemblies.Add($ref)}
$compiled=([Microsoft.CSharp.CSharpCodeProvider]::new()).CompileAssemblyFromFile($cp,[string[]]@((Join-Path $PSScriptRoot 'support/SpellShuffleTestGenerator.cs'),(Join-Path $PSScriptRoot 'support/KakkaraProgressionChecks.cs')))
if($compiled.Errors.HasErrors){throw ($compiled.Errors|Out-String)}
$common=[Activator]::CreateInstance($assembly.GetType('SoMRandomizer.config.settings.CommonSettings'))
$settings=[Activator]::CreateInstance($assembly.GetType('SoMRandomizer.config.settings.OpenWorldSettings'),[object[]]@($common))
$common.set('mode','open');$common.set('version','1.49')
foreach($entry in @('opStartingLocation=kakkara','cannonTravelRandomization=chaos','opFlammieDrumInLogic=yes','crystalOrbWeaponBreaking=on','spellShuffle=party','opGoal=vlong','opLogic=restrictive')){$p=$entry.Split('=');$settings.set($p[0],$p[1])}
$g=[Activator]::CreateInstance($compiled.CompiledAssembly.GetType('SpellShuffleTestGenerator'))
[byte[]]$source=[IO.File]::ReadAllBytes((Resolve-Path $SourceRom).Path)
[byte[]]$original=[byte[]]::new(0x400000)
[Array]::Copy($source,$(if($source.Length -eq 0x200200){0x200}else{0}),$original,0,0x200000)
[void][IO.Directory]::CreateDirectory($OutputRoot)
$previous=[Environment]::CurrentDirectory;Push-Location $OutputRoot;[Environment]::CurrentDirectory=(Get-Location).Path
try{if(-not $g.generate($original,[byte[]]$original.Clone(),'370385E350F7D294',$settings)){throw 'Normal generation failed.'}}
finally{[Environment]::CurrentDirectory=$previous;Pop-Location}
# Generation owns/closes its file loggers. Solver fixtures below intentionally
# reject impossible plando placements and must not write through closed writers.
$assembly.GetType('SoMRandomizer.logging.Logging').GetMethod('ClearLoggers').Invoke($null,@())
[void]$compiled.CompiledAssembly.GetType('KakkaraProgressionChecks').GetMethod('Run').Invoke($null,@($g.LastContext))
Write-Output 'PASS: real location IDs/regions, staged Fire Palace dependencies, captain victory guard, Luna Flammie/Orb/Moon Seed gates, forbidden circular Drum placement, Drum-out-of-logic semantics, and unchanged Potos/Off policy.'
