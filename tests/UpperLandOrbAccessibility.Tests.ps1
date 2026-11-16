param(
 [string]$AssemblyPath=(Join-Path $PSScriptRoot '../.codex-build/upperland-orb-access/bin/SoMRandomizer.exe'),
 [string]$SourceRom='D:/views/tools/bots/Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc',
 [switch]$Manual,
 [ValidateSet('West','East')][string]$Approach='West',
 [ValidateSet('Sword','Javelin')][string]$Weapon='Sword',
 [string]$OutputRoot=(Join-Path $PSScriptRoot '../.codex-build/upperland-orb-access/roms')
)
. (Join-Path $PSScriptRoot 'support/BossArenaStage1.ps1')
$cp=[CodeDom.Compiler.CompilerParameters]::new();$cp.GenerateInMemory=$true
foreach($r in @($assembly.Location,'System.dll','System.Core.dll')){[void]$cp.ReferencedAssemblies.Add($r)}
$files=@('UpperLandOrbAccessibilityChecks.cs','SpellShuffleMachine.cs','DoppelgangerManualProfile.cs')
$b=([Microsoft.CSharp.CSharpCodeProvider]::new()).CompileAssemblyFromFile($cp,[string[]]@($files|ForEach-Object{Join-Path $PSScriptRoot ('support/'+$_)}))
Assert-True (-not $b.Errors.HasErrors) ($b.Errors|Out-String)
$checks=$b.CompiledAssembly.GetType('UpperLandOrbAccessibilityChecks')
$gt=$b.CompiledAssembly.GetType('UpperLandOrbAccessTestGenerator')
$checks.GetMethod('Run').Invoke($null,@(,$original))
$seed='UpperLand-Matango-WeaponAccess-2026'
function Generate([bool]$manual){
 $common=[Activator]::CreateInstance((T config.settings.CommonSettings))
 foreach($x in @(@('mode','open'),@('version','1.49'),@('testOnly','yes'),@('starterGear','yes'))){$common.set($x[0],$x[1])}
 $s=[Activator]::CreateInstance((T config.settings.OpenWorldSettings),[object[]]@($common))
 foreach($x in @(@('opBosses','vanilla'),@('opEnemies','vanilla'),@('opShop','no'),@('opDisableHints','yes'),
  @('opLogic','restrictive'),@('opGoal','vshort'),@('opDifficulty','easy'),@('opCharacters','startboth'),
  @('opStartChar','girl'),@('opStartLevel','20'),@('opStartGold','65535'),@('opAllWeaponOrbs','yes'),
  @('opFlammieDrumInLogic','yes'),@('crystalOrbWeaponBreaking','weaponOnly'),@('spellShuffle','off'),
  @('cannonTravelRandomization','off'),@('opMinLevel','no'),@('opMaxLevel','no'))){$s.set($x[0],$x[1])}
 if($manual){
  $plando=''
  foreach($item in @('Glove','Sword','Axe','Spear','Whip','Bow','Boomerang','Javelin','Flammie-Drum','Undine','Gnome','Sylphid','Salamando','Lumina','Shade','Luna','Dryad')){$plando+='p_(Start-with):'+$item+';'}
  $s.set('plandoSettings',$plando)
 }
 $g=[Activator]::CreateInstance($gt);$g.Manual=$manual;$g.EastStart=$Approach -eq 'East';$g.RequiredWeapon=$(if($Weapon-eq 'Javelin'){7}else{1})
 [byte[]]$r=[byte[]]::new(0x400000);[Array]::Copy($original,$r,$original.Length)
 Assert-True ((T processing.common.RomGenerator).GetMethod('generate',[type[]]@([byte[]],[byte[]],[string],(T config.settings.RandoSettings))).Invoke($g,@($original,$r,$seed,$s))) 'Generation failed.'
 $c=$gt.GetField('Context').GetValue($null)
 [void]$checks.GetMethod('Final').Invoke($null,@($original,$r,$c,$manual))
 return ,$r
}
[byte[]]$normal=Generate $false
[byte[]]$normalAgain=Generate $false
Assert-True (Same $normal $normalAgain) 'Production generation is not deterministic.'
if($Manual){
 [byte[]]$rom=Generate $true
 [byte[]]$again=Generate $true
 Assert-True (Same $rom $again) 'Manual generation is not deterministic.'
 $root=[IO.Path]::GetFullPath($OutputRoot);[void][IO.Directory]::CreateDirectory($root)
 $name='UpperLand-Matango-WeaponOrb-Access-Fix2'+$(if($Weapon-eq 'Javelin'){'-Javelin'}else{''})+$(if($Approach -eq 'East'){'-East'}else{''})
 $file=Join-Path $root ($name+'.sfc')
 Assert-True (-not(Test-Path $file)) 'Refusing to overwrite manual ROM.'
 [IO.File]::WriteAllBytes($file,$rom)
 [pscustomobject]@{Seed=$seed;ROM=$file;SHA256=(Hash $rom).Replace('-','');Requirement=($Weapon+' (test-only forced before hooks/placement)');Start=('Girl; unopened '+$Approach+' approach; startX='+$(if($Approach -eq 'East'){30}else{26})+' Y=62; original Orb28,62');SpellShuffle='Off';FlammieInLogic=$true}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $root ($name+'.json'))
 Get-Content (Join-Path $root ($name+'.json'))
}
'PASS: Upper Land Orb accessibility, native gate/door/progression preservation and deterministic production generation.'
