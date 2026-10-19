param(
 [string]$AssemblyPath=(Join-Path $PSScriptRoot '..\.codex-build\alpha-audit\out\SoMRandomizer.exe'),
 [string]$SourceRom='',
 [string]$OutputRoot=(Join-Path $PSScriptRoot '..\.codex-build\alpha-audit\production-worlds')
)
$ErrorActionPreference='Stop'
$path=(Resolve-Path $AssemblyPath).Path
$a=[Reflection.Assembly]::LoadFrom($path)
function Assert-True([bool]$Value,[string]$Message) { if(-not $Value) { throw $Message } }
function T([string]$Name) { $a.GetType('SoMRandomizer.'+$Name,$true) }
# Reuse normal generation capture and final spell/orb/Mana Magic validation.
# It excludes local Weapon Power on the INSTANCE only, never edits user work.
$cp=[CodeDom.Compiler.CompilerParameters]::new(); $cp.GenerateInMemory=$true
foreach($reference in @($path,'System.dll','System.Core.dll')) { [void]$cp.ReferencedAssemblies.Add($reference) }
$compiled=([Microsoft.CSharp.CSharpCodeProvider]::new()).CompileAssemblyFromFile($cp,(Join-Path $PSScriptRoot 'support\SpellShuffleTestGenerator.cs'))
Assert-True (-not $compiled.Errors.HasErrors) ($compiled.Errors|Out-String)
$capture=$compiled.CompiledAssembly.GetType('SpellShuffleTestGenerator',$true)
# Reuse the strict command-aware normal Sword check, not a byte substring search.
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'BossDoppelgangerGenerationSmoke.Tests.ps1'),[ref]$tokens,[ref]$errors)
$fn=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-NormalSwordEvent'},$true)
Assert-True ($null -ne $fn) 'Normal Sword validator missing.'
. ([scriptblock]::Create($fn.Extent.Text))
$cases=@(
 @{Name='random-short'; Boss='random'; Goal='vshort'; Shuffle='off'; Orb='off'; Cannon='off'},
 @{Name='swap-long-party'; Boss='swap'; Goal='vlong'; Shuffle='party'; Orb='on'; Cannon='shuffle'},
 @{Name='vanilla-long'; Boss='vanilla'; Goal='vlong'; Shuffle='off'; Orb='off'; Cannon='off'; NoEnemies=$true},
 @{Name='three-sprites'; Boss='random'; Goal='vshort'; Shuffle='party'; Orb='on'; Cannon='open'; Sprites=$true; NoEnemies=$true},
 @{Name='mixed-per-character'; Boss='random'; Goal='vlong'; Shuffle='perCharacter'; Orb='weaponOnly'; Cannon='chaos'; Kakkara=$true},
 @{Name='special-coexist'; Boss='random'; Goal='vshort'; Shuffle='party'; Orb='on'; Cannon='shuffle'; Pins='P_mantisAnt:Doppelgangers;P_doppelgangers:Mantis-Ant;P_tropicallo:Triple-Tonpole;P_tripleTonpole:Mantis-Ant;P_jabberwocky:Lime-Slime;P_limeSlime:Minotaur;P_frostGigas:Dread-Slime;P_dreadSlime:Mantis-Ant;P_doomsWall:Mantis-Ant;'},
 @{Name='random-short-repeat'; Boss='random'; Goal='vshort'; Shuffle='off'; Orb='off'; Cannon='off'}
)
$results=@(); [void][IO.Directory]::CreateDirectory($OutputRoot)
$native=[IO.File]::ReadAllBytes((Resolve-Path $SourceRom).Path)
foreach($case in $cases) {
 $seed='Alpha-20261016-'+$case.Name
 if($case.Name -eq 'random-short-repeat') { $seed='Alpha-20261016-random-short' }
 $directory=[IO.Path]::GetFullPath((Join-Path $OutputRoot $case.Name)); [void][IO.Directory]::CreateDirectory($directory)
 $romPath=Join-Path $directory ($case.Name+'.sfc')
 $common=[Activator]::CreateInstance((T 'config.settings.CommonSettings'))
 $s=[Activator]::CreateInstance((T 'config.settings.OpenWorldSettings'),[object[]]@($common))
 $common.set('mode','open'); $common.set('version','1.49'); $common.set('spoilerLog','yes')
 foreach($pair in @(@('opBosses',$case.Boss),@('opGoal',$case.Goal),@('spellShuffle',$case.Shuffle),@('crystalOrbWeaponBreaking',$case.Orb),@('cannonTravelRandomization',$case.Cannon))) { $s.set($pair[0],$pair[1]) }
 $s.set('opLogic','restrictive'); $s.set('opFlammieDrumInLogic','yes')
 if($case.Sprites) { foreach($key in @('opBoyRole','opGirlRole','opSpriteRole')) { $s.set($key,'OGsprite') }; $s.set('opCharacters','startboth') }
 if($case.NoEnemies) { $s.set('opEnemies','none'); $s.set('opStatGrowth','bosses'); $s.set('opMinLevel','yes'); $s.set('opMaxLevel','yes') }
 if($case.Kakkara) { $s.set('opStartingLocation','kakkara'); $s.set('showUpperLandOrbRequirement','on'); $s.set('freeCannonTravel','on') }
 if($case.Pins) { $s.set('plandoSettings',$case.Pins) }
 Assert-True ($s.get('opStartLevel') -eq '1' -and $s.get('opStartGold') -eq '0' -and $s.get('opAllWeaponOrbs') -eq 'no') 'Manual equipment/supplies enabled.'
 $g=[Activator]::CreateInstance($capture)
 $generator=T 'processing.common.RomGenerator'
 $gs=[Activator]::CreateInstance([Collections.Generic.Dictionary``2].MakeGenericType([string],$generator))
 $ss=[Activator]::CreateInstance([Collections.Generic.Dictionary``2].MakeGenericType([string],(T 'config.settings.RandoSettings')))
 $gs.Add('open',$g); $ss.Add('open',$s)
 $previous=[Environment]::CurrentDirectory; Push-Location $directory; [Environment]::CurrentDirectory=$directory
 try { [void]$generator.GetMethod('initGeneration').Invoke($null,@([string]$SourceRom,[string]$romPath,[string]$seed,$gs,$common,$ss)) }
 finally { [Environment]::CurrentDirectory=$previous; Pop-Location }
 Assert-True (Test-Path $romPath) ('No ROM: '+$case.Name)
 $log=Get-Content (Join-Path $directory ('log_'+$seed+'.txt')) -Raw
 Assert-True ($log -match '\[general\] Done!' -and $log -match 'Open world generation finished!') 'Generation/simulation did not succeed.'
 Assert-True ($log -notmatch 'Short-circuiting open world simulator|TEST_PROFILE|test bootstrap') 'Validation bypass/bootstrap enabled.'
 $ctx=$g.LastContext
 if($case.NoEnemies -and $case.Boss -eq 'vanilla') {
  $objects=(T 'processing.common.VanillaMapUtil').GetMethod('getObjects').Invoke($null,@($ctx.outputRom,72))
  foreach($obj in $objects) { Assert-True ($obj.getEventVisMinimum() -ne 15) 'Vanilla+NoEnemies removed Jehk encounter.' }
 }
 [void]$capture.GetMethod('Validate').Invoke($null,@($s,$ctx))
 Assert-True (-not $ctx.workingData.hasSetting('weaponPowerRoutineOffsetHirom')) 'Weapon Power emitted in scope-controlled Alpha test.'
 [byte[]]$rom=[IO.File]::ReadAllBytes($romPath)
 Assert-True ($rom.Length -eq 0x400000) 'Output size changed.'
 Assert-True ([Linq.Enumerable]::SequenceEqual([byte[]]$rom[0x8E345..0x8E355],[byte[]]$native[0x8E345..0x8E355])) 'Critical native C8 code corrupted.'
 $table=([int]$rom[0x1E7A3]+([int]$rom[0x1E7A4]-shl 8)+([int]$rom[0x1E7A5]-shl 16))-0xC00000
 foreach($entry in $ctx.replacementEvents.GetEnumerator()) {
  $pointer=$table+3*$entry.Key
  Assert-True ($pointer -ge 0 -and $pointer+2 -lt $rom.Length) 'Event table outside ROM.'
  $at=([int]$rom[$pointer]+([int]$rom[$pointer+1]-shl 8)+([int]$rom[$pointer+2]-shl 16))-0xC00000
  [byte[]]$expected=$entry.Value
  if($expected.Length -eq 0) { continue }
  Assert-True ($at -ge 0 -and $at+$expected.Length -le $rom.Length) 'Event outside ROM.'
  Assert-True ([Linq.Enumerable]::SequenceEqual([byte[]]$rom[$at..($at+$expected.Length-1)],$expected)) ('Final event differs: '+$entry.Key)
 }
 Assert-NormalSwordEvent ([byte[]]$ctx.replacementEvents[0x103])
 Assert-True ($a.GetType('DoppelgangerManualProfile',$false) -eq $null) 'Test profile compiled into production.'
 $options=$s.ToString()
 $results += [pscustomobject]@{Name=$case.Name;Seed=$seed;Bosses=$case.Boss;Goal=$case.Goal;SpellShuffle=$case.Shuffle;Orb=$case.Orb;Cannon=$case.Cannon;Sha256=(Get-FileHash $romPath -Algorithm SHA256).Hash;Rom=$romPath;Simulation='passed';HumanCompletion='not tested';Settings=$options}
 $results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutputRoot 'results.json')
 Write-Output ('PASS: '+$case.Name+' normal generation, simulator, actual final event bytes, native code and normal Sword initialization.')
}
Assert-True ($results[0].Sha256 -eq $results[6].Sha256) 'Normal seed regeneration differs.'
'PASS: seven normal-progression ROMs; paired byte determinism; no manual teleport/gear/bypass. Simulator acceptance is NOT an emulator playthrough.'
