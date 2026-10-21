param(
 [string]$AssemblyPath=(Join-Path $PSScriptRoot '../SoMRandomizer/bin/Debug/net462/SoMRandomizer.exe'),
 [string]$SourceRom='D:/views/tools/bots/Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc',
 [string]$ReportPath=''
)
. (Join-Path $PSScriptRoot 'support/BossArenaStage1.ps1')
$cp=[CodeDom.Compiler.CompilerParameters]::new(); $cp.GenerateInMemory=$true
foreach($r in @($assembly.Location,'System.dll','System.Core.dll')){[void]$cp.ReferencedAssemblies.Add($r)}
$compiled=([Microsoft.CSharp.CSharpCodeProvider]::new()).CompileAssemblyFromFile($cp,[string[]]@((Join-Path $PSScriptRoot 'support/DoppelgangerScalingChecks.cs'),(Join-Path $PSScriptRoot 'support/SpellShuffleMachine.cs')))
Assert-True (-not $compiled.Errors.HasErrors) ($compiled.Errors|Out-String)
$check=$compiled.CompiledAssembly.GetType('DoppelgangerScalingChecks'); $reports=@()
[void]$check.GetMethod('RevivalControl').Invoke($null,@(,$original))
foreach($difficulty in @('easy','normal','hard','impossible')) {
 $c=New-Case 'vanilla'; $c.Settings.set('opStatGrowth','player'); $c.Settings.set('opDifficulty',$difficulty)
 Apply 'processing.openworld.OpenWorldDifficultyProcessor' $c
 Apply 'processing.hacks.openworld.MinMaxLevel' $c
 Apply 'processing.hacks.openworld.CustomTopOfScreenText' $c
 $start=$c.Context.workingOffset
 Apply 'processing.hacks.openworld.EnemiesAtYourLevel' $c
 $loaders=$check.GetMethod('Loaders').Invoke($null,@($c.Rom,$start,$c.Context.workingOffset))
 if($difficulty -eq 'normal') {
  $baseline=Get-Content (Join-Path $PSScriptRoot 'DoppelgangerScalingBaseline.json') -Raw|ConvertFrom-Json
  foreach($entry in $loaders.GetEnumerator()) {
   $hex=$baseline.Tables.($entry.Key.ToString('X4'))
   Assert-True ($hex.Length -eq 256) ('Missing pre-fix emitted table fixture: '+$entry.Key.ToString('X4'))
   foreach($species in (0..127|Where-Object {$_ -notin @(0x2E,0x3F,0x20)})) {
    $expected=[Convert]::ToInt32($hex.Substring($species*2,2),16)
    Assert-True ($c.Rom[$entry.Value[2]+$species] -eq $expected) ('Unrelated species class changed: '+$species+' stat '+$entry.Key)
   }
  }
 }
 foreach($species in @(0x2E,0x3F,0x20)) {
  $at=0x101C00+29*$species
  Assert-True ($original[$at] -eq 0 -and [BitConverter]::ToUInt16($original,$at+1) -eq $(if($species -eq 0x2E){999}else{800})) 'Native shadow stats changed.'
  Assert-True ($c.Rom[$loaders[0xE182][2]+$species] -eq 3 -and $c.Rom[$loaders[0xE188][2]+$species] -eq 3 -and $c.Rom[$loaders[0xE1A5][2]+$species] -eq 3) 'Zero-level divisor still inflates HP/STR/DEF classes.'
  foreach($level in @(1,10,25,30,50,70)) {
   $hp=$check.GetMethod('Value').Invoke($null,@($c.Rom,$loaders[0xE182],$species,$level))
   $str=$check.GetMethod('Value').Invoke($null,@($c.Rom,$loaders[0xE188],$species,$level))
   $def=$check.GetMethod('Value').Invoke($null,@($c.Rom,$loaders[0xE1A5],$species,$level))
   Assert-True ($hp -gt 0 -and $hp -le 65535 -and $str -gt 0) 'Invalid machine-executed scaled stat.'
   $reports+=[pscustomobject]@{Difficulty=$difficulty;Species=$species;Level=$level;HP=$hp;CombinedHP=$hp*3;STR=$str;DEF=$def}
  }
 }
 # A pure role change is not an input to the enemy-stat classifier/tables.
 $roles=New-Case 'vanilla'; $roles.Settings.set('opStatGrowth','player'); $roles.Settings.set('opDifficulty',$difficulty)
 foreach($role in @('boyClass','girlClass','spriteClass')){$roles.Context.workingData.set($role,'OGsprite')}
 Apply 'processing.openworld.OpenWorldDifficultyProcessor' $roles; Apply 'processing.hacks.openworld.MinMaxLevel' $roles
 Apply 'processing.hacks.openworld.CustomTopOfScreenText' $roles; Apply 'processing.hacks.openworld.EnemiesAtYourLevel' $roles
 Assert-True (Same $c.Rom $roles.Rom) 'Party gameplay roles alter shadow/other enemy scaling.'
}
if($ReportPath){$reports|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $ReportPath}
'PASS: native 999/800/800 HP; actual emitted 65816 HP/STR/DEF loaders at early/mid/late levels across four difficulty variants; finite low shadow classes and byte-identical three-Sprite role controls.'
