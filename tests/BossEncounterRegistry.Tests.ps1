param(
    [string]$AssemblyPath=(Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe'),
    [string]$SourceRom='',
    [string]$BaselinePath='',
    [switch]$WriteBaseline
)
. (Join-Path $PSScriptRoot 'support\BossArenaStage1.ps1')
$adapter=T 'processing.common.DoppelgangerBossArenaRedirect'
$registry=$assembly.GetType('SoMRandomizer.processing.common.BossEncounterRegistry',$false)
Assert-True ($WriteBaseline -or $registry -ne $null) 'Registry not built.'
$rows=Import-Csv (Join-Path $PSScriptRoot 'BossCompatibilityMatrix.csv')
$matrix=@(); $randomCount=0; $swapCount=0
foreach($row in $rows) {
    $slot=$maps.GetField($row.Arena).GetValue($null)
    [byte[]]$pool=$adapter.GetMethod('getOpenWorldRandomPool').Invoke($null,@($slot))
    if($registry) { Assert-True (Same $pool ($registry.GetMethod('GetRandomPool').Invoke($null,@($slot)))) 'Registry reordered/widened candidate pool.' }
    foreach($col in $rows) {
        $id=[byte][Convert]::ToInt32($col.NativeBoss,16)
        $random=$pool -contains $id; $swap=[bool]$adapter.GetMethod('canSwapInOpenWorld').Invoke($null,@($slot,$id))
        if($random) { $randomCount++ }; if($swap) { $swapCount++ }
        $matrix+=('{0}:{1}:{2}:{3}' -f $row.Arena,$id,$random,$swap)
        if($registry) { Assert-True ($swap -eq $registry.GetMethod('CanSwap').Invoke($null,@($slot,$id))) 'Registry widened Swap.' }
    }
}
Assert-True ($rows.Count -eq 38 -and $randomCount -eq 1046 -and $swapCount -eq 833) 'Admission snapshot changed.'
$fixtures=@{}
foreach($mode in @('vanilla','random','swap','coexist')) {
    $pins=@{}
    if($mode -eq 'coexist') {
        $pins=Native-Pins
        $pins.mantisAnt='Doppelgangers'; $pins.doppelgangers='Mantis-Ant'
        $pins.tropicallo='Triple-Tonpole'; $pins.tripleTonpole='Mantis-Ant'
        $pins.jabberwocky='Lime-Slime'; $pins.limeSlime='Minotaur'
        $pins.frostGigas='Dread-Slime'; $pins.dreadSlime='Mantis-Ant'; $pins.doomsWall='Mantis-Ant'
    }
    $case=New-Case $(if($mode -eq 'coexist') { 'random' } else { $mode }) $pins
    Apply 'processing.common.BossSwaps' $case
    if($registry) {
        $all=$case.Context.bossEncounters.Bindings
        Assert-True ($all.Count -eq 38 -and @($all | Select-Object -ExpandProperty DestinationMap -Unique).Count -eq 38) 'Missing/duplicate logical assignment.'
        Assert-True (@($all | Where-Object Capability -eq 'Unsupported').Count -eq 0) 'Existing assignment not described as implemented.'
        if($mode -eq 'vanilla') { Assert-True (@($all | Where-Object Execution -ne 'Native').Count -eq 0) 'Vanilla metadata not native.' }
        if($mode -eq 'coexist') {
            foreach($name in @('DoomWallBossArenaRedirect','LimeSlimeBossArenaRedirect','DreadSlimeBossArenaRedirect','TripleTonpoleBossArenaRedirect','DoppelgangerBossArenaRedirect')) {
                Assert-True (@($all | Where-Object Adapter -eq $name).Count -gt 0) ('Adapter absent: '+$name)
            }
        }
    }
    Events $case
    [byte[]]$doors=[byte[]]::new(4096)
    foreach($door in $case.Context.replacementDoors.GetEnumerator()) { $door.Value.put($doors,4*$door.Key) }
    $events=@($case.Context.replacementEvents.GetEnumerator() | Sort-Object Key | ForEach-Object { $_.Key.ToString()+':'+[BitConverter]::ToString([byte[]]$_.Value) }) -join '|'
    $fixtures[$mode]=[pscustomobject]@{Rom=Hash $case.Rom;Doors=Hash $doors;Events=Hash ([Text.Encoding]::UTF8.GetBytes($events));WorkingOffset=$case.Context.workingOffset;NextRandom=$case.Context.randomFunctional.Next()}
}
$snapshot=[pscustomobject]@{Matrix=$matrix;Fixtures=$fixtures}
if($WriteBaseline) {
    Assert-True ($BaselinePath -ne '') 'Specify a baseline path.'
    $snapshot | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $BaselinePath
} elseif($BaselinePath -ne '') {
    $baseline=Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json
    Assert-True (($baseline.Matrix -join '|') -eq ($matrix -join '|')) 'Baseline admission matrix changed.'
    foreach($mode in $fixtures.Keys) {
        foreach($field in @('Rom','Doors','Events','WorkingOffset','NextRandom')) {
            Assert-True ($baseline.Fixtures.$mode.$field -eq $fixtures[$mode].$field) ("Baseline changed: $mode/$field")
        }
    }
}
if($registry) {
    $jehk=$maps.GetField('DOPPELGANGERS').GetValue($null)
    Assert-True ($registry.GetMethod('Capability').Invoke($null,@($jehk,[byte]0x5E)).ToString() -eq 'Unsupported') 'Removed Frost pilot is still classified as supported.'
    Assert-True (-not $registry.GetMethod('CanSwap').Invoke($null,@($jehk,[byte]0x5E))) 'Pilot exposed to Swap.'
    $pins=Native-Pins; $pins.doppelgangers='Frost-Gigas'; $rejected=$false
    try { Apply 'processing.common.BossSwaps' (New-Case 'random' $pins) } catch { $rejected=$_.Exception.ToString().Contains('plando is incompatible') }
    Assert-True $rejected 'Public Frost/Jehk plando admitted.'
}
'PASS: 38 destinations, 1444 pairing equivalence, all adapter descriptions; Random/Swap/native/coexist ROM, events, doors and RNG fingerprints.'
