param(
 [string]$AssemblyPath=(Join-Path $PSScriptRoot '../SoMRandomizer/bin/Debug/net462/SoMRandomizer.exe'),
 [string]$SourceRom='D:/views/tools/bots/Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc',
 [string]$OutputRoot=(Join-Path ([IO.Path]::GetTempPath()) ('som-doppel-expansion-'+[Guid]::NewGuid().ToString('N'))),
 [switch]$Manual,
 [switch]$FinalAcceptance,
 [switch]$PureLandsAcceptance
)
. (Join-Path $PSScriptRoot 'support/BossArenaStage1.ps1')
$cp=[CodeDom.Compiler.CompilerParameters]::new(); $cp.GenerateInMemory=$true
foreach($r in @($assembly.Location,'System.dll','System.Core.dll')){[void]$cp.ReferencedAssemblies.Add($r)}
$compiled=([Microsoft.CSharp.CSharpCodeProvider]::new()).CompileAssemblyFromFile($cp,[string[]]@((Join-Path $PSScriptRoot 'support/DoppelgangerExpansionTestGenerator.cs'),(Join-Path $PSScriptRoot 'support/DoppelgangerManualProfile.cs')))
Assert-True (-not $compiled.Errors.HasErrors) ($compiled.Errors|Out-String)
$generator=$compiled.CompiledAssembly.GetType('DoppelgangerExpansionTestGenerator')
$base=T 'processing.common.RomGenerator'; $baseSettings=T 'config.settings.RandoSettings'
[void][IO.Directory]::CreateDirectory($OutputRoot); $OutputRoot=(Resolve-Path $OutputRoot).Path
$results=@()
function Generate([string]$Name,[string]$Mode,[string]$Forward,[string]$Reverse,[string]$Role='normal',[string]$Goal='vshort',[bool]$Pinned=$true,[string]$DeathLink='on') {
 $seed='Doppel-Expanded-'+(($Name -replace '-repeat$','') -replace '-LinkOff$','-LinkOn')+'-2026'; $dir=Join-Path $OutputRoot $Name; [void][IO.Directory]::CreateDirectory($dir)
 $rom=Join-Path $dir ($Name+'.sfc'); Assert-True (-not (Test-Path $rom)) 'Refuse to overwrite existing manual/control ROM.'
 $common=[Activator]::CreateInstance((T 'config.settings.CommonSettings')); $s=[Activator]::CreateInstance((T 'config.settings.OpenWorldSettings'),[object[]]@($common))
 $common.set('mode','open'); $common.set('version','1.49'); $common.set('spoilerLog','yes')
 $options=@{opBosses=$Mode;opCharacters='startboth';opFlammieDrumInLogic='no';opLogic='restrictive';opGoal=$Goal;
  opDifficulty='normal';opEnemies='swap';opStatGrowth='player';crystalOrbWeaponBreaking='on';spellShuffle='party';cannonTravelRandomization='shuffle';opMinLevel='no';opMaxLevel='no';doppelgangerDeathLink=$DeathLink}
 if($Manual){$options.opStartLevel='25';$options.opStartGold='65535';$options.opAllWeaponOrbs='yes'}
 if($Role -eq 'sprites'){foreach($r in @('opBoyRole','opGirlRole','opSpriteRole')){$options[$r]='OGsprite'}}
 if($Role -eq 'girls'){foreach($r in @('opBoyRole','opGirlRole','opSpriteRole')){$options[$r]='OGgirl'}}
 if($Role -eq 'solo'){$options.opCharacters='none';$options.opStartChar='boy';$options.crystalOrbWeaponBreaking='weaponOnly'}
 if($Role -eq 'two'){$options.opCharacters='findbothL1'}
 $pins=Native-Pins
 if($Forward){$pins[$Forward]='Doppelgangers'}
 $pins.doppelgangers=$Reverse
 $plando=''
 if($Pinned){foreach($key in ($pins.Keys|Sort-Object)){$plando+='P_'+$key+':'+$pins[$key]+';'}}
 if($Manual){
  foreach($p in @('Glove','Sword','Axe','Spear','Whip','Bow','Boomerang','Javelin','Water-Seed','Earth-Seed','Wind-Seed','Fire-Seed','Light-Seed','Dark-Seed','Moon-Seed','Dryad-Seed','Undine','Gnome','Sylphid','Salamando','Shade','Luna','Dryad')){$plando+='p_(Start-with):'+$p+';'}
  if($Role -ne 'sprites'){$plando+='p_(Start-with):Lumina;'}
  $plando+='p_Tropicallo-1:Sea-Hare-Tail;'
  $plando+=$(if($PureLandsAcceptance){'p_Dragon-Worm:Gold-Key;'}else{'p_Doppel:Gold-Key;'})
 }
 if($plando){$options.plandoSettings=$plando}
 foreach($p in $options.GetEnumerator()){$s.set($p.Key,$p.Value)}
 $g=[Activator]::CreateInstance($generator); $g.ManualSupplies=[bool]$Manual; $g.PureLandsShortcut=[bool]$PureLandsAcceptance
 $gs=[Activator]::CreateInstance([Collections.Generic.Dictionary``2].MakeGenericType([string],$base))
 $ss=[Activator]::CreateInstance([Collections.Generic.Dictionary``2].MakeGenericType([string],$baseSettings))
 $gs.Add('open',$g);$ss.Add('open',$s)
 $previous=[Environment]::CurrentDirectory; Push-Location $dir; [Environment]::CurrentDirectory=$dir
 try{[void]$base.GetMethod('initGeneration').Invoke($null,@([string]$SourceRom,[string]$rom,[string]$seed,$gs,$common,$ss))}finally{[Environment]::CurrentDirectory=$previous;Pop-Location}
 Assert-True (Test-Path $rom) ('Generation failed: '+$Name)
 $log=Get-Content (Join-Path $dir ('log_'+$seed+'.txt')) -Raw
 Assert-True ($log.Contains('[general] Done!') -and -not $log.Contains('Weapon Power calculator')) ('Simulator/generation failed or included unrelated experiment: '+$Name)
 $c=$g.LastContext;[byte[]]$r=[IO.File]::ReadAllBytes($rom)
 $table=([int]$r[0x1E7A3]-bor ([int]$r[0x1E7A4]-shl 8)-bor ([int]$r[0x1E7A5]-shl 16))-0xC00000
 foreach($e in @($c.replacementEvents.Keys|Where-Object {$_ -in @(0x103,0x4E5,0x5ED,0x62A,0x6D5,0x6D6,0x6B9,0x6BA,0x6BB)})) {
  $ptr=$table+3*$e; $at=([int]$r[$ptr]-bor ([int]$r[$ptr+1]-shl 8)-bor ([int]$r[$ptr+2]-shl 16))-0xC00000
  Assert-True (Same $r[$at..($at+$c.replacementEvents[$e].Count-1)] $c.replacementEvents[$e]) ('Final relocated event differs from generator: '+$e.ToString('X3')+' at '+$at.ToString('X6'))
 }
 # Decode Sword event: prohibit doors except the single explicit Pure Lands
 # test shortcut. Do not mistake text/parameters for event opcodes.
 $sword=$c.replacementEvents[0x103]
 $startupDoors=0
 for($i=0;$i -lt $sword.Count;) {
  $op=[int]$sword[$i]
  if($op -in @(0x18,0x19,0x1A,0x1B,0x1C,0x1D)) {
   Assert-True ([bool]$PureLandsAcceptance -and $op -eq 0x1B -and $sword[$i+1] -eq 0x75) 'Test teleport leaked into Sword event.'
   $startupDoors++
  }
  if($op -eq 0){break}
  if($op -ge 0x7F -or $op -in @(2,3,4,5,6,8,9,10,0x50,0x51,0x52,0x5D,0x5E,0x5F)){$i++}
  elseif(($op -ge 0x10 -and $op -le 0x2F) -or $op -in @(0x57,0x59,0x5A)){$i+=2}
  elseif($op -in @(0x30,0x31,0x32,0x34,0x36,0x37,0x42)){$i+=3}
  elseif($op -eq 0x39){$i+=4}elseif($op -eq 0x40){$i+=5}else{throw ('Unexpected startup command '+$op)}
 }
 Assert-True ($startupDoors -eq [int][bool]$PureLandsAcceptance) 'Unexpected manual shortcut count.'
 if($PureLandsAcceptance){
  Assert-True (Same $sword[($sword.Count-10)..($sword.Count-1)] @(0x42,0x46,0x1F,0x10,0,0x1B,0x75,0x16,0xD5,0)) 'Completed location must disable the manual shortcut.'
  Assert-True ($c.doppelgangerExpansion.ForeignSlot.originalMapNum -eq 204 -and $c.doppelgangerExpansion.Completion -eq 0x5ED) 'Wrong Pure Lands binding.'
  Assert-True (Same $r[(0x83000+4*0xCB)..(0x83003+4*0xCB)] $original[(0x83000+4*0xCB)..(0x83003+4*0xCB)]) 'Destination copy must not claim the old donor return door.'
  foreach($id in @(0x375,0x378)){
   $at=0x83000+4*$id
   Assert-True ((($r[$at]-bor (($r[$at+1]-band 1)-shl 8)) -eq 498) -and (($r[$at+1]-band 0xFE) -eq ($original[$at+1]-band 0xFE)) -and (Same $r[($at+2)..($at+3)] $original[($at+2)..($at+3)])) 'Destination copy changed native entry coordinates/layer/transition.'
  }
  $reward=$c.replacementEvents[0x5ED]
  Assert-True (Same $reward[0..5] @(0x24,0x1B,0x25,2,0x29,0x46)) 'Dragon Worm healing, fixed Axe Orb or progression increment changed.'
  Assert-True (Same $reward[($reward.Count-3)..($reward.Count-1)] @(0x16,0x2A,0)) 'Pure Lands rewards must finish in place through authoritative continuation.'
  $actualTriggers=Read-Map $r 'getTriggers' 204;$originalTriggers=Read-Map $original 'getTriggers' 204
  Assert-True (($actualTriggers -join ',') -eq ($originalTriggers -join ',')) 'Pure Lands exit triggers changed.'
  Assert-True (((Read-Map $r 'getTriggers' 498) -join ',') -eq '1749,1503,1503,1502,1502') 'Destination-copy walk-on/native exit triggers changed.'
 }
 Assert-True (Same $r[0x8E345..0x8E355] $original[0x8E345..0x8E355]) 'Native C8 combat corruption.'
 foreach($id in @(0x2E,0x3F,0x20)){ $at=0x100000+16*$id;Assert-True (Same $r[$at..($at+15)] $original[$at..($at+15)]) 'Shadow AI/appearance changed.' }
 foreach($patch in @(0x10A738,0x10A74D,0x10A762,0x10A70E,0x10A71C,0x10A72A)) {
  Assert-True ($r[$patch] -eq $(if($DeathLink -eq 'off'){0}else{$original[$patch]})) 'Final native AI Death Link setting lost.'
 }
 if($c.doppelgangerExpansion -and $c.doppelgangerExpansion.ForeignSlot){
  $plan=$c.doppelgangerExpansion
  $objects=Read-Map $r 'getObjects' 498
  Assert-True ($objects.Count -eq $(if($plan.ForeignSlot.originalMapNum -eq 290){5}else{3})) 'Final map object boundaries wrong.'
  $idle=[int]$r[0xB6A5]-bor ([int]$r[0xB6A6]-shl 8)-bor ([int]$r[0xB6A7]-shl 16)
  Assert-True ($idle-0xC00000 -eq $c.workingData.getInt('DoppelgangerDispatcher')) 'Final idle hook lost.'
  $at=$c.workingData.getInt('DoppelgangerDispatcher');$len=$c.workingData.getInt('DoppelgangerDispatcherLength')
  if($c.workingData.hasSetting('crystalOrbWeaponBreakingDeferredRoutineOffsetHirom')) {
   $tail=$at+$len-5
   Assert-True ($r[$tail] -eq 0x22 -and ([int]$r[$tail+1]-bor ([int]$r[$tail+2]-shl 8)-bor ([int]$r[$tail+3]-shl 16)) -eq $c.workingData.getInt('crystalOrbWeaponBreakingDeferredRoutineOffsetHirom')) 'Final Orb dispatcher chaining broken.'
  }
  $refs=Read-Map $r 'getMapPieceReference' 498
  foreach($p in @($refs.bgPieces)+@($refs.fgPieces)){[void](Read-Map $r 'loadVanillaMapPiece' $p.pieceIndex)}
 }
 $bindings=@($c.bossEncounters.Bindings|Where-Object {$_.DestinationMap -eq 72 -or $_.SelectedEncounter -eq 129}|Select-Object Destination,DestinationMap,SelectedEncounter,Execution,PhysicalMap,TemplateMap,DestinationCompletionEvent)
 Assert-True (@($c.bossEncounters.Bindings|Where-Object SelectedEncounter -eq 129).Count -le 1) 'Nonunique shadows in generated seed.'
 $spoiler=Join-Path $dir ('log_'+$seed+'_SPOILER.txt')
 $prizes=@(Get-Content $spoiler|Where-Object {$_ -match 'Tropicallo|Jehk|jehk|tropicallo|Frost Gigas|Dragon Worm|dragon worm'}|ForEach-Object {$_.Trim()})
 $complete='version=1.49 mode=open '+(($options.GetEnumerator()|Sort-Object Key|ForEach-Object {$_.Key+'='+$_.Value}) -join ' ')
 return [pscustomobject]@{Name=$Name;Seed=$seed;Settings=$complete;ManualSupplies=[bool]$Manual;NoTeleport=(-not [bool]$PureLandsAcceptance);Rom=$rom;Sha256=(Get-FileHash $rom -Algorithm SHA256).Hash;Bindings=$bindings;Prizes=$prizes;Spoiler=$spoiler}
}
if($PureLandsAcceptance){
 Assert-True ([bool]$Manual -and -not [bool]$FinalAcceptance) 'Pure Lands acceptance requires manual supplies and a single profile.'
 $results+=Generate 'PureLands-DragonWorm-Shadows-ArenaFix2' 'random' 'dragonWorm' 'Frost-Gigas' 'normal' 'vlong' $true 'off'
}elseif($FinalAcceptance){
 Assert-True ([bool]$Manual) 'Final acceptance requires explicit manual supplies.'
 $results+=Generate 'FireRoom-Shadows-Jehk-Frost-LinkOn' 'random' 'fireGigas' 'Frost-Gigas'
 $results+=Generate 'FireRoom-Shadows-Jehk-Frost-LinkOff' 'random' 'fireGigas' 'Frost-Gigas' 'normal' 'vshort' $true 'off'
 $results+=Generate 'DreadSlot-Shadows-ThreeSprites-Jehk-Minotaur' 'random' 'dreadSlime' 'Minotaur' 'sprites' 'vshort' $true 'off'
}elseif($Manual){
 $results+=Generate 'Tropicallo-Shadows-Jehk-Frost' 'random' 'tropicallo' 'Frost-Gigas'
 $results+=Generate 'FrostRoom-Shadows-Jehk-Minotaur' 'random' 'frostGigas' 'Minotaur'
 $results+=Generate 'Tropicallo-Shadows-ThreeSprites-Jehk-Thunder' 'random' 'tropicallo' 'Thunder-Gigas' 'sprites'
}else{
 $results+=Generate 'production-pair' 'random' 'tropicallo' 'Frost-Gigas'
 $results+=Generate 'production-pair-repeat' 'random' 'tropicallo' 'Frost-Gigas'
 Assert-True ($results[0].Sha256 -eq $results[1].Sha256) 'Normal production pair generation is not byte-deterministic.'
 $results+=Generate 'production-swap-pair' 'swap' 'tropicallo' 'Minotaur' 'girls' 'vlong'
 $results+=Generate 'production-frost-shadows' 'random' 'frostGigas' 'Metal-Mantis' 'sprites'
 $results+=Generate 'production-pureland-shadows' 'random' 'dragonWorm' 'Frost-Gigas' 'girls' 'vlong' $true 'off'
 $results+=Generate 'unplanned-random' 'random' '' 'Doppelgangers' 'solo' 'vshort' $false
 $results+=Generate 'unplanned-swap' 'swap' '' 'Doppelgangers' 'two' 'vlong' $false
}
$results|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $OutputRoot 'results.json')
$results|Select-Object Name,Seed,Rom,Sha256|Format-List
'PASS: production generator/simulator, final-ROM hooks/events/objects/native code, unique encounter; Sword shortcut restricted to explicit Pure Lands acceptance profile. Results: '+(Join-Path $OutputRoot 'results.json')
