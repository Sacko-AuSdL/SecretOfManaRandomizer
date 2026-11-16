param([string]$AssemblyPath=(Join-Path $PSScriptRoot '../SoMRandomizer/bin/Debug/net462/SoMRandomizer.exe'),[string]$SourceRom='D:/views/tools/bots/Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc',[string]$OutputRoot=(Join-Path $PSScriptRoot '../.codex-build/interim-alpha3/diagnostics'),[switch]$DiagnosticsOnly,[switch]$AdditionalScenariosOnly)
. (Join-Path $PSScriptRoot 'support/BossArenaStage1.ps1')
$cp=[CodeDom.Compiler.CompilerParameters]::new();$cp.GenerateInMemory=$true;foreach($ref in @($assembly.Location,'System.dll','System.Core.dll')){[void]$cp.ReferencedAssemblies.Add($ref)}
$b=([Microsoft.CSharp.CSharpCodeProvider]::new()).CompileAssemblyFromFile($cp,[string[]]@('TownStartChecks.cs','SpellShuffleMachine.cs','DoppelgangerAutosaveChecks.cs'|ForEach-Object{Join-Path $PSScriptRoot ('support/'+$_)}));Assert-True (-not $b.Errors.HasErrors) ($b.Errors|Out-String)
$gt=$b.CompiledAssembly.GetType('TownStartTestGenerator');$checks=$b.CompiledAssembly.GetType('TownStartChecks');[byte[]]$padded=[byte[]]::new(0x400000);[Array]::Copy($original,$padded,$original.Length)
function Generate([string]$town,[string]$mode,[string]$goal='vshort'){
 $common=[Activator]::CreateInstance((T config.settings.CommonSettings));$common.set('mode','open');$common.set('version','1.49');$common.set('testOnly','yes')
 $s=[Activator]::CreateInstance((T config.settings.OpenWorldSettings),[object[]]@($common));foreach($pair in @(@('opStartingLocation',$town),@('opFlammieDrumInLogic','yes'),@('cannonTravelRandomization',$mode),@('freeCannonTravel','on'),@('opLogic','restrictive'),@('opGoal',$goal),@('opStartChar','girl'),@('opCharacters','startboth'),@('opStartWeapon','1'),@('opStartGold','1000'),@('opDifficulty','easy'),@('opMinLevel','no'),@('opMaxLevel','no'),@('crystalOrbWeaponBreaking','on'))){$s.set($pair[0],$pair[1])}
 $g=[Activator]::CreateInstance($gt);[byte[]]$r=$padded.Clone();$seed='TownStart-'+$town+'-2026';Assert-True ((T processing.common.RomGenerator).GetMethod('generate',[type[]]@([byte[]],[byte[]],[string],(T config.settings.RandoSettings))).Invoke($g,@($padded,$r,$seed,$s))) 'Town generation failed.'
 $c=$gt.GetField('Context').GetValue($null);$checks.GetMethod('Run').Invoke($null,@($padded,$r,$s,$c))|Write-Host
 $script:LastSettings=$s;$script:LastContext=$c;return ,$r
}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($OutputRoot));$results=@()
foreach($town in @('iceCountry','southtown')){
 if($AdditionalScenariosOnly){foreach($mode in @('shuffle','chaos')){[void](Generate $town $mode)};[void](Generate $town 'off' $(if($town-eq 'iceCountry'){'vlong'}else{'mtr'}));continue}
 [byte[]]$r=Generate $town 'off';[byte[]]$again=Generate $town 'off';Assert-True (Same $r $again) 'Town generation not deterministic.'
 $checks.GetMethod('Logic').Invoke($null,@($LastSettings,$LastContext))|Write-Host
 $name=$(if($town-eq 'iceCountry'){'IceCountry-Todo'}else{'Southtown'})+'-Start-Alpha3.sfc';$file=Join-Path ([IO.Path]::GetFullPath($OutputRoot)) $name
 if(Test-Path $file){Assert-True (Same ([IO.File]::ReadAllBytes($file)) $r) 'Refusing changed diagnostic overwrite.'}else{[IO.File]::WriteAllBytes($file,$r)}
 $results+=[pscustomobject]@{Town=$town;File=$file;SHA256=(Hash $r).Replace('-','');Seed=('TownStart-'+$town+'-2026');Options='version=1.49 mode=open opStartingLocation='+$town+' opFlammieDrumInLogic=yes cannonTravelRandomization=off freeCannonTravel=on opLogic=restrictive opGoal=vshort opStartChar=girl opCharacters=startboth opStartWeapon=1 opStartGold=1000 opDifficulty=easy opMinLevel=no opMaxLevel=no crystalOrbWeaponBreaking=on'}
 if(-not $DiagnosticsOnly){foreach($mode in @('shuffle','chaos')){[void](Generate $town $mode)};[void](Generate $town 'off' $(if($town-eq 'iceCountry'){'vlong'}else{'mtr'}))}
}
if($results.Count){$results|ConvertTo-Json -Depth 5|Set-Content (Join-Path $OutputRoot 'manifest.json') -Encoding UTF8}
'PASS two real-town starts, deterministic generation, native startup/save and closed-network progression fixtures.'
