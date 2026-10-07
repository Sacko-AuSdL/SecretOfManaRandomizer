param(
    [string]$AssemblyPath=(Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe'),
    [string]$SourceRom='D:\views\tools\bots\Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc'
)
$ErrorActionPreference='Stop'
function Assert-True([bool]$Condition,[string]$Message) { if(-not $Condition) { throw $Message } }
function Equal-Bytes($A,$B) { return [Linq.Enumerable]::SequenceEqual([byte[]]$A,[byte[]]$B) }
$assembly=[Reflection.Assembly]::LoadFrom((Resolve-Path $AssemblyPath).Path)
function RepoType([string]$Name) { return $assembly.GetType('SoMRandomizer.'+$Name,$true) }
$mapUtil=RepoType 'processing.common.VanillaMapUtil'
$commonType=RepoType 'config.settings.CommonSettings'
$settingsType=RepoType 'config.settings.OpenWorldSettings'
$contextType=RepoType 'processing.common.RandoContext'
[byte[]]$original=[IO.File]::ReadAllBytes((Resolve-Path $SourceRom).Path)
function Object-Offset($Rom,[int]$Map) {
    return [int]$mapUtil.GetMethod('getObjectOffset').Invoke($null,@($Rom,$Map))
}
Assert-True ((Object-Offset $original 499) -eq 0x8E068) 'Unexpected native map 499 start.'
Assert-True ((Object-Offset $original 500) -eq 0x8E068) 'Native map 499 must be empty.'
Assert-True ($mapUtil.GetMethod('getObjects').Invoke($null,@($original,499)).Count -eq 0) 'Native empty-span fixture is invalid.'
function New-Output([bool]$Published,[bool]$ChangedStart=$false) {
    [byte[]]$r=New-Object byte[] 0x400000
    [Array]::Copy($original,$r,$original.Length)
    if($Published) {
        # Reproduce the earlier arena processor's published map 500 start/end pointers.
        $r[0x873E8]=0x20; $r[0x873E9]=0xFF
        $r[0x873EA]=0x40; $r[0x873EB]=0xFF
        for($i=0x8FF20;$i -lt 0x8FF40;$i++) { $r[$i]=0xA5 }
        if($ChangedStart) {
            # Independently catch a traversal that fixes only the next pointer.
            $r[0x873E6]=0x00; $r[0x873E7]=0xE0
        }
    }
    return ,$r
}
function Run-Processor([string]$Name,[byte[]]$Rom) {
    $common=[Activator]::CreateInstance($commonType); $common.set('mode','open')
    $settings=[Activator]::CreateInstance($settingsType,[object[]]@($common)); $settings.set('opEnemies','swap')
    $context=[Activator]::CreateInstance($contextType); $context.randomFunctional=[Random]::new(19283)
    $type=RepoType $Name; $processor=[Activator]::CreateInstance($type)
    $method=$type.GetMethod('process',[Reflection.BindingFlags]'Instance,NonPublic')
    Assert-True ([bool]$method.Invoke($processor,@($original,$Rom,'NativeBounds',$settings,$context))) 'Processor did not run.'
}
function Check-Code([byte[]]$Rom) {
    # This whole executable interval has no legitimate writer in these isolated processors.
    Assert-True (Equal-Bytes $Rom[0x8E0B5..0x8FED5] $original[0x8E0B5..0x8FED5]) 'Native C8 executable bytes were treated as fake objects.'
    Assert-True (Equal-Bytes $Rom[0x8E342..0x8E34A] $original[0x8E342..0x8E34A]) 'C8:E345 ORA/STA sequence was corrupted.'
}
foreach($processor in @('processing.common.EnemySwaps','processing.hacks.openworld.NoEnemies')) {
    [byte[]]$control=New-Output $false
    Run-Processor $processor $control
    Check-Code $control
    $legitimate=0
    for($map=16;$map -lt 500;$map++) {
        $start=(Object-Offset $original $map)+8; $end=Object-Offset $original ($map+1)
        for($at=$start;$at -lt $end;$at+=8) {
            if(-not (Equal-Bytes $control[$at..($at+7)] $original[$at..($at+7)])) { $legitimate++ }
        }
    }
    Assert-True ($legitimate -gt 0) 'Legitimate native enemies were not changed.'
    foreach($changedStart in @($false,$true)) {
        [byte[]]$test=New-Output $true $changedStart
        [byte[]]$before=$test.Clone()
        if(-not $changedStart) {
            $fakeCount=[int][Math]::Ceiling(((Object-Offset $test 500)-(Object-Offset $test 499)-8)/8.0)
            Assert-True ($fakeCount -eq 982) 'Fixture no longer reproduces the original fake-object traversal.'
        }
        Run-Processor $processor $test
        Check-Code $test
        # Entire would-be 982-object span remains untouched: zero fake object mutations,
        # including generated actors. Compare whole outputs against the unmodified-pointer control.
        Assert-True (Equal-Bytes $test[0x8E070..0x8FF1F] $before[0x8E070..0x8FF1F]) 'Map 499 expanded into native code.'
        Assert-True (Equal-Bytes $test[0x8FF20..0x8FF3F] $before[0x8FF20..0x8FF3F]) 'Generated map 500 actors changed.'
        Assert-True ((Object-Offset $test 500) -eq 0x8FF20) 'Published map 500 pointer was lost.'
        # Normalize only the fixture's earlier-processor mutations, not processor results.
        [Array]::Copy($control,0x873E6,$test,0x873E6,6)
        [Array]::Copy($control,0x8FF20,$test,0x8FF20,0x20)
        Assert-True (Equal-Bytes $test $control) 'Generated boundaries changed unrelated native randomization.'
    }
    "$processor PASS: native empty span; both original boundaries; C8 code intact; $legitimate legitimate native objects changed."
}
# NoEnemies must inspect output object state, without overwriting prior randomization.
$at=$null
for($map=16;$map -lt 500 -and $null -eq $at;$map++) {
    $start=(Object-Offset $original $map)+8; $end=Object-Offset $original ($map+1)
    for($i=$start;$i -lt $end;$i+=8) {
        if($original[$i+5] -lt 84) { $at=$i; break }
    }
}
Assert-True ($null -ne $at) 'No native enemy available for output-state fixture.'
[byte[]]$output=New-Output $true
[byte[]]$prior=@(0x12,0x34,0x85,0x86,0x78,0x90,0x9A,0xBC)
[Array]::Copy($prior,0,$output,$at,8)
Run-Processor 'processing.hacks.openworld.NoEnemies' $output
Assert-True (Equal-Bytes $output[$at..($at+7)] $prior) 'NoEnemies discarded prior NPC/output changes.'
[byte[]]$output=New-Output $true
$prior[5]=1
[Array]::Copy($prior,0,$output,$at,8)
Run-Processor 'processing.hacks.openworld.NoEnemies' $output
$objectType=RepoType 'processing.common.structure.MapObject'
$expected=[Activator]::CreateInstance($objectType,[object[]]@(,$prior.Clone()))
$expected.setNeverVisible(); [byte[]]$expectedRom=New-Object byte[] 8; $expected.put($expectedRom,0)
Assert-True (Equal-Bytes $output[$at..($at+7)] $expectedRom) 'NoEnemies changed output fields beyond visibility.'
'PASS: NoEnemies preserves prior output species and all non-visibility fields.'
