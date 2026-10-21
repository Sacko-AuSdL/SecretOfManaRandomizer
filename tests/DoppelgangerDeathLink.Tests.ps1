param([string]$AssemblyPath=(Join-Path $PSScriptRoot '../SoMRandomizer/bin/Debug/net462/SoMRandomizer.exe'),[string]$SourceRom='D:/views/tools/bots/Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc')
. (Join-Path $PSScriptRoot 'support/BossArenaStage1.ps1')
$on=New-Case 'vanilla';$off=New-Case 'vanilla'
Assert-True ($on.Settings.get('doppelgangerDeathLink') -eq 'on') 'Backward-compatible default lost.'
$parsed=New-Case 'vanilla';$values=[Collections.Generic.Dictionary[string,string]]::new();$values.Add('doppelgangerDeathLink','off')
$parsed.Settings.processNewSettings($values)
Assert-True ($parsed.Settings.get('doppelgangerDeathLink') -eq 'off' -and (Same ([Text.Encoding]::UTF8.GetBytes(($parsed.Settings.getOptionsValues('doppelgangerDeathLink') -join ','))) ([Text.Encoding]::UTF8.GetBytes('on,off')))) 'Serialized settings did not restore Challenge mode.'
$off.Settings.set('doppelgangerDeathLink','off');Apply 'processing.hacks.openworld.DoppelgangerDeathLink' $on;Apply 'processing.hacks.openworld.DoppelgangerDeathLink' $off
Assert-True (Same $on.Rom[0..($original.Length-1)] $original) 'On changes vanilla bytes.'
$allowed=@(0x10A738,0x10A74D,0x10A762,0x10A70E,0x10A71C,0x10A72A)
$cp=[CodeDom.Compiler.CompilerParameters]::new();$cp.GenerateInMemory=$true
foreach($r in @($assembly.Location,'System.dll','System.Core.dll')){[void]$cp.ReferencedAssemblies.Add($r)}
$compiled=([Microsoft.CSharp.CSharpCodeProvider]::new()).CompileAssemblyFromFile($cp,[string[]]@((Join-Path $PSScriptRoot 'support/SpellShuffleMachine.cs'),(Join-Path $PSScriptRoot 'support/DoppelgangerDeathLinkChecks.cs')))
Assert-True (-not $compiled.Errors.HasErrors) ($compiled.Errors|Out-String);$machine=$compiled.CompiledAssembly.GetType('DoppelgangerDeathLinkChecks')
$diff=$machine.GetMethod('Changes').Invoke($null,@($on.Rom,$off.Rom))
Assert-True ($diff.Count -eq 6) 'Expected exactly six script operand changes.'
Assert-True (@($diff|Where-Object {$_ -notin $allowed}).Count -eq 0) 'Unrelated AI/death/player bytes changed.'
foreach($i in 0..2){
 $species=@(0x20,0x2E,0x3F)[$i];$slot=@(2,0,1)[$i]
 foreach($hp in @(0,100)){
  $args=@($on.Rom,0x10A735,$species,$slot,$hp,0)
  Assert-True ($machine.GetMethod('Check').Invoke($null,$args) -eq ($hp -eq 0)) 'Native HP death link not reproduced.'
  $args[0]=$off.Rom;Assert-True (-not $machine.GetMethod('Check').Invoke($null,$args)) 'Challenge still links counterpart HP.'
 }
 foreach($dead in @(0,128)){
  $script=@(0x10A70B,0x10A719,0x10A727)[$i]
  $args=@($on.Rom,$script,0x2E,$i,100,$dead)
  Assert-True ($machine.GetMethod('Check').Invoke($null,$args) -eq ($dead -eq 128)) 'Native status death link not reproduced.'
  $args[0]=$off.Rom;Assert-True (-not $machine.GetMethod('Check').Invoke($null,$args)) 'Challenge still links counterpart status.'
 }
}
foreach($rom in @($on.Rom,$off.Rom)){Assert-True ($machine.GetMethod('OwnDeath').Invoke($null,@(,$rom))) 'Own HP-zero death no longer works.'}
'PASS: default On byte-identical; Off six isolated AI operands; actual native VM executes HP/status counterpart branches, revival controls and own combat death. Physical slots independent of gameplay roles.'
