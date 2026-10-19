param(
    [string]$AssemblyPath=(Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe'),
    [string]$SourceRom='',
    [string]$OutputRoot=(Join-Path ([IO.Path]::GetTempPath()) ('somr-doppel-'+[Guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference='Stop'
function Assert-True([bool]$Value,[string]$Message) { if(-not $Value) { throw $Message } }
function Same($A,$B) { return [Linq.Enumerable]::SequenceEqual([byte[]]$A,[byte[]]$B) }
function Assert-NormalSwordEvent([byte[]]$Data) {
    # Decode startup commands so parameter bytes cannot be mistaken for doors.
    # This deliberately rejects ANY door/teleport in normal event $103, including
    # the manual-only $08D/$304 auto-entry and the manual MP/proficiency writes.
    $potosReady=$false; $magicRope=$false; $ended=$false
    for($i=0;$i -lt $Data.Length;) {
        $op=[int]$Data[$i]
        Assert-True (-not ($op -ge 0x18 -and $op -le 0x1D)) 'Manual Sword-event teleport leaked into normal generation.'
        if($op -eq 0) { Assert-True ($i -eq $Data.Length-1) 'Unexpected startup END/trailing test profile.'; $ended=$true; break }
        if($op -eq 0x30 -and $Data[$i+1] -eq 0x10 -and $Data[$i+2] -eq 0xB) { $potosReady=$true }
        if($op -eq 0x1E -and $Data[$i+1] -eq 0x46) { $magicRope=$true }
        if($op -eq 0x39) { Assert-True ($Data[$i+2] -eq 0x90) 'Manual actor supplies leaked into normal startup.' }
        if($op -ge 0x7F -or $op -in @(2,3,4,5,6,8,9,0xA,0x50,0x51,0x52,0x5D,0x5E,0x5F)) { $i++ }
        elseif(($op -ge 0x10 -and $op -le 0x2F) -or $op -in @(0x57,0x59,0x5A)) { $i+=2 }
        elseif($op -in @(0x30,0x31,0x32,0x34,0x36,0x37,0x42)) { $i+=3 }
        elseif($op -eq 0x39) { $i+=4 }
        elseif($op -eq 0x40) { $i+=5 }
        else { throw ('Unexpected startup opcode {0:X2}; extend decoder explicitly.' -f $op) }
    }
    Assert-True ($ended -and $potosReady -and $magicRope) 'Normal Sword/startup initialization was not retained.'
}
$path=(Resolve-Path $AssemblyPath).Path
$a=[Reflection.Assembly]::LoadFrom($path)
Assert-True ($a.GetType('DoppelgangerManualProfile',$false) -eq $null) 'Manual profile was compiled into the production assembly.'
$cp=[CodeDom.Compiler.CompilerParameters]::new(); $cp.GenerateInMemory=$true
foreach($reference in @($path,'System.dll','System.Core.dll')) { [void]$cp.ReferencedAssemblies.Add($reference) }
$compiled=([Microsoft.CSharp.CSharpCodeProvider]::new()).CompileAssemblyFromFile($cp,(Join-Path $PSScriptRoot 'support\DoppelgangerTestGenerator.cs'))
if($compiled.Errors.HasErrors) { throw ($compiled.Errors|Out-String) }
$capture=$compiled.CompiledAssembly.GetType('DoppelgangerTestGenerator',$true)
function T([string]$Name) { return $a.GetType('SoMRandomizer.'+$Name,$true) }
$common=T 'config.settings.CommonSettings'; $settings=T 'config.settings.OpenWorldSettings'
$generator=T 'processing.common.RomGenerator'; $baseSettings=T 'config.settings.RandoSettings'
$util=T 'processing.common.VanillaMapUtil'; $eventUtil=T 'processing.common.VanillaEventUtil'
[byte[]]$native=[IO.File]::ReadAllBytes((Resolve-Path $SourceRom).Path)
[void][IO.Directory]::CreateDirectory($OutputRoot); $OutputRoot=(Resolve-Path $OutputRoot).Path
function Generate([string]$Name,[string]$Mode,[bool]$Roles=$false,[bool]$DrumInLogic=$true) {
    $directory=Join-Path $OutputRoot $Name; [void][IO.Directory]::CreateDirectory($directory)
    $destination=Join-Path $directory ($Name+'.sfc'); $seed='Doppelganger-Regression-2026'
    $c=[Activator]::CreateInstance($common); $s=[Activator]::CreateInstance($settings,[object[]]@($c))
    $c.set('mode','open'); $c.set('version','1.49'); $c.set('spoilerLog','yes')
    $s.set('opBosses',$Mode); $s.set('opCharacters','startboth'); $s.set('opLogic','restrictive')
    $s.set('crystalOrbWeaponBreaking','off')
    $s.set('opFlammieDrumInLogic',$(if($DrumInLogic) { 'yes' } else { 'no' }))
    if($Mode -ne 'vanilla') {
        $s.set('plandoSettings','P_mantisAnt:Doppelgangers;P_doppelgangers:Mantis-Ant;P_tripleTonpole:Triple-Tonpole;P_limeSlime:Lime-Slime;P_dreadSlime:Dread-Slime;P_doomsWall:Doom''s-Wall;')
    }
    if($Roles) {
        foreach($role in @('opBoyRole','opGirlRole','opSpriteRole')) { $s.set($role,'OGsprite') }
        $s.set('opEnemies','none'); $s.set('opAiRando','swap'); $s.set('opStatGrowth','bosses')
        $s.set('opMinLevel','yes'); $s.set('opMaxLevel','yes')
    }
    $g=[Activator]::CreateInstance($capture)
    $gs=[Activator]::CreateInstance([Collections.Generic.Dictionary``2].MakeGenericType([string],$generator))
    $ss=[Activator]::CreateInstance([Collections.Generic.Dictionary``2].MakeGenericType([string],$baseSettings))
    $gs.Add('open',$g); $ss.Add('open',$s)
    $previous=[Environment]::CurrentDirectory; Push-Location $directory; [Environment]::CurrentDirectory=$directory
    try { [void]$generator.GetMethod('initGeneration').Invoke($null,@([string]$SourceRom,[string]$destination,[string]$seed,$gs,$c,$ss)) }
    finally { [Environment]::CurrentDirectory=$previous; Pop-Location }
    Assert-True (Test-Path $destination) 'Generation failed.'
    Assert-True ((Get-Content (Join-Path $directory ('log_'+$seed+'.txt')) -Raw) -match '\[general\] Done!') 'Simulation/generation did not complete.'
    $ctx=$capture.GetField('LastContext').GetValue($null)
    [byte[]]$r=[IO.File]::ReadAllBytes($destination)
    # Check ACTUAL relocated ROM bytes as well as the generator's final event.
    $tableBase=[int]$r[0x1E7A3]+([int]$r[0x1E7A4]-shl 8)+(([int]$r[0x1E7A5]-0xC0)-shl 16)
    $table=$tableBase+3*0x103
    $at=[int]$r[$table]+([int]$r[$table+1]-shl 8)+(([int]$r[$table+2]-0xC0)-shl 16)
    [byte[]]$sword=$ctx.replacementEvents[0x103]
    Assert-True (Same $r[$at..($at+$sword.Length-1)] $sword) 'Emitted normal Sword event differs from generated initialization.'
    Assert-NormalSwordEvent $r[$at..($at+$sword.Length-1)]
    if($Mode -eq 'vanilla') {
        foreach($table in @(0x84000,0x85000,0x87000)) { Assert-True (Same $r[($table+992)..($table+999)] $native[($table+992)..($table+999)]) 'Vanilla boss mode claimed private pointers.' }
        Assert-True (Same $r[0x8FF50..0x8FFA3] $native[0x8FF50..0x8FFA3]) 'Vanilla mode wrote arena data.'
    } else {
        $objects=$util.GetMethod('getObjects').Invoke($null,@($r,498))
        Assert-True ($objects.Count -eq 3) 'Final ROM lost shadow actors.'
        for($i=0;$i -lt 3;$i++) { Assert-True ($objects[$i].getSpecies() -eq @(0x2E,0x3F,0x20)[$i] -and $objects[$i].getEventVisMinimum() -eq 0) 'Final shadow species/visibility wrong.' }
        $objects=$util.GetMethod('getObjects').Invoke($null,@($r,497))
        Assert-True ($objects.Count -eq 1 -and $objects[0].getSpecies() -eq 0x57 -and $objects[0].getEvent() -eq 0x6BB) 'Final reverse actor wrong.'
        Assert-True (Same $r[0x83234..0x83237] @(0xF2,0x21,0x28,0x81)) 'Final shadow entry differs from native trial.'
        Assert-True (Same $r[0x83C10..0x83C13] @(0xF1,0x21,0x24,0x80)) 'Final reverse entry differs from native Mantis.'
        foreach($event in @(0x6D5,0x6D6,0x6B9,0x6BA,0x6BB)) {
            # EventExpander's relocated event table is authoritative in final ROM.
            $tableBase=[int]$r[0x1E7A3]+([int]$r[0x1E7A4]-shl 8)+(([int]$r[0x1E7A5]-0xC0)-shl 16)
            $table=$tableBase+3*$event; $at=[int]$r[$table]+([int]$r[$table+1]-shl 8)+(([int]$r[$table+2]-0xC0)-shl 16)
            $data=$ctx.replacementEvents[$event]
            Assert-True (Same $r[$at..($at+$data.Count-1)] $data) ("Final private event {0:X3} at {1:X6} differs from generated event." -f $event,$at)
        }
        $jehk=$ctx.replacementEvents[0x4E5]
        Assert-True (Same $jehk[0..9] @(0x42,0x3F,0x6F,0x14,0x60,0x42,0x3F,0x04,0x10,0)) 'Final Jehk checker still assumes three shadows.'
        $locs=(T 'processing.openworld.randomization.OpenWorldLocations').GetMethod('getForSelectedOptions').Invoke($null,@($s,$ctx))
        $loc=$locs|Where-Object locationName -eq 'jehk'
        Assert-True ($loc -ne $null -and $loc.eventNum -eq 0x4E5 -and $loc.lockedByPrizes.Contains('axe') -and $loc.lockedByPrizes.Contains('whip')) 'Jehk logical check/dependencies changed.'
    }
    foreach($table in @(0x84000,0x85000,0x87000)) { Assert-True (Same $r[($table+990)..($table+993)] $native[($table+990)..($table+993)]) 'Final ROM damaged map 495 boundary.' }
    Assert-True (Same $r[0x8E345..0x8E355] $native[0x8E345..0x8E355]) 'Critical C8 executable sequence corrupted.'
    Assert-True (Same $r[0x105605..0x105704] $native[0x105605..0x105704]) 'Final native shadow AI changed.'
    foreach($id in @(0x2E,0x3F,0x20)) { $at=0x100000+16*$id; Assert-True (Same $r[$at..($at+15)] $native[$at..($at+15)]) 'Final native shadow metadata changed.' }
    foreach($id in @(0x2E,0x3F,0x20)) {
        $at=0x101C00+29*$id+20
        # Despite BossSwaps' old row comment, native $C0:5644 loads this
        # WORD into $E1AA,Y: it is status immunity, not a death-animation ID.
        Assert-True (Same $r[$at..($at+1)] $native[$at..($at+1)]) 'Shadow native status immunity changed with party roles.'
    }
    # Native status notification / visual cleanup remains authoritative for
    # players AND shadows. A role permutation must not rewrite these branches.
    foreach($span in @(@(0x180B8,0x1810D),@(0x193E4,0x19462),@(0x194EA,0x1950C))) {
        Assert-True (Same $r[$span[0]..$span[1]] $native[$span[0]..$span[1]]) 'Native actor death/animation cleanup was modified.'
    }
    # Jehk heals AFTER Door 038; it must not depend on the donor boss's event.
    $table=$tableBase+3*0x4E5
    $at=[int]$r[$table]+([int]$r[$table+1]-shl 8)+(([int]$r[$table+2]-0xC0)-shl 16)
    [byte[]]$jehk=$ctx.replacementEvents[0x4E5]
    Assert-True (Same $r[$at..($at+$jehk.Length-1)] $jehk) 'Emitted Jehk completion event differs.'
    Assert-True (Same $jehk[($jehk.Length-8)..($jehk.Length-1)] @(0x18,0x38,6,0x24,0x1B,0x2F,0x84,0)) 'Final Jehk return/heal tail lost.'
    Assert-True (Same $r[0x830E0..0x830E3] $native[0x830E0..0x830E3]) 'Jehk Door 038 changed.'
    [byte[]]$heal=[byte[]]$eventUtil.GetMethod('getVanillaEvent').Invoke($null,@($native,0x41B))
    $table=$tableBase+3*0x41B
    $at=[int]$r[$table]+([int]$r[$table+1]-shl 8)+(([int]$r[$table+2]-0xC0)-shl 16)
    Assert-True (Same $r[$at..($at+$heal.Length-1)] $heal) 'Native Jehk HP/status restoration subroutine changed.'
    Assert-True (Same $r[0x1EDEF..0x1EE8B] $native[0x1EDEF..0x1EE8B]) 'Native HP/MP restoration handler changed.'
    Assert-True (Same $r[0x8332C..0x8332F] $native[0x8332C..0x8332F]) 'Door CB changed.'
    return (Get-FileHash $destination -Algorithm SHA256).Hash
}
$one=Generate 'random-a' 'random'; $two=Generate 'random-b' 'random'
Assert-True ($one -eq $two) 'Full generation not deterministic.'
[void](Generate 'swap' 'swap'); [void](Generate 'three-sprites-no-enemies' 'random' $true); [void](Generate 'vanilla-control' 'vanilla')
[void](Generate 'normal-pedestal-start' 'random' $false $false)
'PASS: six final-ROM/simulator generations; no manual Sword teleport/supplies in normal Drum-in-logic or pedestal starts; paired determinism, Random/Swap/Vanilla, three Sprite roles + NoEnemies/AI/scaling, exact relocated events, native code/AI and map ownership.'
