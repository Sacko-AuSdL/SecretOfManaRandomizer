param(
    [string]$AssemblyPath = (Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe'),
    [string]$SourceRom = 'D:\views\tools\bots\Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc',
    [switch]$AutosaveOnly
)
$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path $AssemblyPath).Path)
Add-Type -Path (Join-Path $PSScriptRoot 'support\MusicRoutineMachine.cs')
$commonType = $assembly.GetType('SoMRandomizer.config.settings.CommonSettings', $true)
$settingsType = $assembly.GetType('SoMRandomizer.config.settings.OpenWorldSettings', $true)
$vanillaSettingsType = $assembly.GetType('SoMRandomizer.config.settings.VanillaRandoSettings', $true)
$contextType = $assembly.GetType('SoMRandomizer.processing.common.RandoContext', $true)
$restoreType = $assembly.GetType('SoMRandomizer.processing.hacks.common.music.SaveMusicRestoration', $true)
$autosaveType = $assembly.GetType('SoMRandomizer.processing.hacks.common.qol.Autosave', $true)
$randomType = $assembly.GetType('SoMRandomizer.processing.hacks.common.music.RandomMusicHack', $true)
[byte[]]$native = [IO.File]::ReadAllBytes((Resolve-Path $SourceRom).Path)

function Assert-True([bool]$Condition, [string]$Message) { if(-not $Condition) { throw $Message } }
function Hook-Address([byte[]]$Rom, [int]$Offset) {
    return [int]$Rom[$Offset + 1] -bor ([int]$Rom[$Offset + 2] -shl 8) -bor ([int]$Rom[$Offset + 3] -shl 16)
}
function Invoke-Processor($Type, [byte[]]$Rom, $Settings, $Context) {
    return $Type.GetMethod('process', [Reflection.BindingFlags]'Instance,NonPublic').Invoke(
        [Activator]::CreateInstance($Type), [object[]]@($native, $Rom, 'music-test', $Settings, $Context))
}
function New-TestRom([bool]$RandomMusic, [bool]$Autosave, [string]$Mode = 'open', [bool]$Mute = $false, [int]$StartOffset = 0x300000) {
    [byte[]]$rom = [byte[]]::new(0x400000)
    [Array]::Copy($native, $rom, $native.Length)
    $common = [Activator]::CreateInstance($commonType)
    $activeSettingsType = $(if($Mode -eq 'rando') { $vanillaSettingsType } else { $settingsType })
    $settings = [Activator]::CreateInstance($activeSettingsType, [object[]]@($common))
    $common.set('mode', $Mode)
    $common.set('muteMusic', $(if($Mute) { 'yes' } else { 'no' }))
    $autosaveKey = [string]$activeSettingsType.GetField('PROPERTYNAME_AUTOSAVE').GetRawConstantValue()
    $settings.set($autosaveKey, $(if($Autosave) { 'yes' } else { 'no' }))
    $context = [Activator]::CreateInstance($contextType)
    $context.workingOffset = $StartOffset
    $context.randomFunctional = [Random]::new(4242)
    if($RandomMusic) {
        $replacements = [Collections.Generic.Dictionary[string,Collections.Generic.List[Collections.Generic.List[byte]]]]::new()
        $candidates = [Collections.Generic.List[Collections.Generic.List[byte]]]::new()
        $candidates.Add([Collections.Generic.List[byte]]::new([byte[]]@(0x2A,0x24,0xAA)))
        $replacements.Add('Dungeon', $candidates)
        $songTypes = [Collections.Generic.Dictionary[byte,string]]::new()
        $songTypes.Add(0x0A, 'Dungeon')
        [object[]]$args = @($rom, $context.workingOffset, $replacements, $songTypes)
        $randomType.GetMethod('process').Invoke([Activator]::CreateInstance($randomType), $args) | Out-Null
        $context.workingOffset = [int]$args[1]
    }
    $randomStart = $(if($RandomMusic) { Hook-Address $rom 0x301AD } else { 0 })
    if($Autosave) { Invoke-Processor $autosaveType $rom $settings $context | Out-Null }
    $before = [byte[]]$rom.Clone()
    $restoreStart = $context.workingOffset
    $applied = Invoke-Processor $restoreType $rom $settings $context
    return [pscustomobject]@{ Rom=$rom; Before=$before; Applied=$applied;
        Start=$restoreStart; End=$context.workingOffset; RandomStart=$randomStart; RngAfter=$context.randomFunctional.Next() }
}
function New-Machine($Case) {
    $m = [MusicRoutineMachine]::new($Case.Rom)
    $m.Write(0x7E00DC, 368, 2) # Shade inherited-music interior
    $m.Write(0x7EE000, 1, 1)
    $m.Write(0x7EE182, 100, 2)
    $m.Write(0x7E1E05, 0xFFFF, 2)
    $m.Write(0x7E042F, 0xFF, 1)
    return $m
}
function Request($Machine, $Case, [byte[]]$Packet, [bool]$Event = $true) {
    for($i=0; $i -lt 4; $i++) { $Machine.Write((0x7E1E00 + $i), $Packet[$i], 1) }
    $Machine.DP = 0; $Machine.DB = 0x7E; $Machine.P = 0x10
    $Machine.Run($(if($Event) { Hook-Address $Case.Rom 0x1F109 } else { 0xC30004 }))
}
function Save($Machine, $Case, [int]$Slot, [int]$Checksum = 0x4567) {
    $base = $Slot * 0x400
    $Machine.Write(0x7EA211, $Slot, 1)
    $Machine.P = 0x20; $Machine.DB = 0x7E
    $Machine.Run((Hook-Address $Case.Rom 0x755D6))
    Assert-True ($Machine.X -eq $base) 'Native slot calculation/PHX changed.'
    # Shared native save writer fills both world copies and computes its checksum.
    foreach($bank in @(0x306000,0x307000)) {
        $Machine.Write(($bank+$base+0x2B7), 7, 1)
        $Machine.Write(($bank+$base+0x2B8), 9, 1)
        $Machine.Write(($bank+$base+1), $Checksum, 2)
    }
    $Machine.A = $Checksum; $Machine.X = $base; $Machine.P = 0
    $Machine.Run((Hook-Address $Case.Rom 0x756C5))
    Assert-True ($Machine.A -eq $Checksum -and $Machine.X -eq $base -and $Machine.P -eq 0) 'Save hook changes native register/status contract.'
}
function Load($Machine, $Case, [int]$Slot, [bool]$Backup = $false) {
    $Machine.X = $Slot * 0x400 + 1 + $(if($Backup) { 0x1000 } else { 0 })
    $Machine.P = 0x20; $Machine.DP = 0; $Machine.DB = 0x7E
    # A25A has already been decoded by C7:592E before the load hook.
    $Machine.Write(0x7EA25A, 0x11B, 2)
    $door = [int]$Machine.Rom[0x83000+0x11B*4] -bor (([int]$Machine.Rom[0x83001+0x11B*4] -band 1) -shl 8)
    $Machine.Run((Hook-Address $Case.Rom 0x755C7))
    $Machine.Write(0x7E00DC, $door, 2)
    Assert-True ($Machine.X -eq 0x400 -and $Machine.ActorInitializations -gt 0) 'Native actor initialization was not chained with its original X-clobber.'
    return $door
}
function Tick($Machine, $Case) {
    $Machine.DP = 0; $Machine.DB = 0; $Machine.P = 0x20
    $Machine.Run((Hook-Address $Case.Rom 0xB0BF))
}
function Assert-Packet([byte[]]$Actual, [byte[]]$Expected, [string]$Message) {
    Assert-True (([BitConverter]::ToString($Actual)) -eq ([BitConverter]::ToString($Expected))) $Message
}
function Has-Bytes([byte[]]$Data, [byte[]]$Needle, [int]$Start, [int]$End) {
    for($i=$Start; $i -le $End-$Needle.Length; $i++) {
        $match = $true
        for($j=0; $j -lt $Needle.Length; $j++) { if($Data[$i+$j] -ne $Needle[$j]) { $match=$false; break } }
        if($match) { return $true }
    }
    return $false
}

$cases = @()
foreach($random in @($false,$true)) {
    foreach($auto in @($false,$true)) {
        if($AutosaveOnly -and -not $auto) { continue }
        $case = New-TestRom $random $auto
        $cases += $case
        Assert-True $case.Applied 'Supported music restoration processor was not applied.'
        if($auto) {
            Assert-True ($case.Rom[0x1E7D6] -eq 0x22 -and
                (Has-Bytes $case.Rom ([byte[]]@(0x22,0xD6,0x55,0xC7)) 0x300000 $case.Start)) `
                'Autosave no longer reaches the same native save entry as ordinary saves.'
        }
        foreach($slot in 0..3) {
            $m = New-Machine $case
            Request $m $case ([byte[]]@(1,0x0A,0x13,0x8F))
            [byte[]]$expected = $(if($random) { @(1,0x2A,0x24,0xAA) } else { @(1,0x0A,0x13,0x8F) })
            Assert-Packet $m.Commands[$m.Commands.Count-1] $expected 'Captured post-RandomMusic packet differs from actual send.'
            Assert-Packet ([byte[]]$m.Memory[0x7E0447..0x7E0449]) ([byte[]]$expected[1..3]) 'WRAM snapshot is not effective request.'
            if($random) {
                $beforeDuplicate = $m.Commands.Count; $rngBeforeDuplicate = $m.RngCalls
                Request $m $case ([byte[]]@(1,0x0A,0x13,0x8F))
                Assert-True ($m.Commands.Count -eq $beforeDuplicate -and $m.RngCalls -eq $rngBeforeDuplicate -and
                    $m.S -eq 0x1FF -and $m.Read(0x7E044A,1) -eq 0) 'RandomMusic stack-sensitive duplicate path changed.'
            }
            $rng = $m.RngCalls
            Save $m $case $slot
            $base = $slot * 0x400
            $sramWrites = @($m.Writes | Where-Object { $_ -ge 0x306000 -and $_ -le 0x307FFF })
            foreach($write in $sramWrites) {
                $relative = ($write - 0x306000) % 0x1000 - $base
                Assert-True ($relative -in @(1,2,0x2B7,0x2B8) -or
                    ($relative -ge 0x2BC -and $relative -le 0x2C5)) 'Metadata writes outside audited slot allocation.'
            }
            Assert-Packet ([byte[]]$m.Memory[(0x3062BC+$base)..(0x3062C5+$base)]) `
                ([byte[]]$m.Memory[(0x3072BC+$base)..(0x3072C5+$base)]) 'Metadata backup differs.'
            foreach($backup in @($false,$true)) {
                # Cold launch: retain only SRAM, not WRAM/RNG/song caches.
                $cold = New-Machine $case
                [Array]::Copy($m.Memory,0x306000,$cold.Memory,0x306000,0x2000)
                $cold.Run((Hook-Address $case.Rom 0x10010))
                Request $cold $case ([byte[]]@(0x80,0x20,0,0)) $false
                $cold.Commands.Clear()
                $doorMap = Load $cold $case $slot $backup
                Assert-True ($cold.Read(0x7E044C,1) -eq 1) 'Valid primary/backup load did not arm pending restoration.'
                if($auto) { Assert-True ($cold.Read(0x7E0439,1) -eq 1) 'Autosave one-shot suppression flag was lost.' }
                $cold.Write(0x7E00D0,1,1); Tick $cold $case
                Assert-True ($cold.Commands.Count -eq 0) 'Fallback runs before entry event completes.'
                $cold.Write(0x7E00D0,0,1); $cold.Write(0x7E00FF,0x40,1); Tick $cold $case
                Assert-True ($cold.Commands.Count -eq 0) 'Fallback runs during door transition.'
                $cold.Write(0x7E00FF,0,1)
                Tick $cold $case
                Assert-True ($cold.Commands.Count -eq 1) 'Inherited-room fallback did not send exactly one request.'
                Assert-Packet $cold.Commands[0] $expected 'Cold/backup load rerolled or corrupted effective request.'
                Tick $cold $case
                Assert-True ($cold.Commands.Count -eq 1 -and $cold.RngCalls -eq 0) 'Fallback repeats or consumes RNG.'
                Assert-True ($cold.Read(0x7E044C,1) -eq 0 -and $cold.Read(0x7E044B,1) -eq 0) 'Replay state leaked after send.'
            }

            foreach($resetMode in @('ordinary-load','alive-reset','death-reset')) {
                $warm = New-Machine $case
                [Array]::Copy($m.Memory,0x306000,$warm.Memory,0x306000,0x2000)
                Request $warm $case ([byte[]]@(1,0x0B,0x18,0x8F)) $false
                if($resetMode -eq 'death-reset') {
                    $warm.Write(0x7EE182,0,2)
                    Request $warm $case ([byte[]]@(1,7,0x18,0x8F))
                }
                if($resetMode -ne 'ordinary-load') { $warm.Run((Hook-Address $case.Rom 0x10010)) }
                Request $warm $case ([byte[]]@(0x80,0x20,0,0)) $false
                $warm.Write(0x7EE182,100,2) # the native load restores saved HP
                Load $warm $case $slot | Out-Null
                $warm.Commands.Clear(); $beforeRng = $warm.RngCalls
                Tick $warm $case
                Assert-True ($warm.Commands.Count -eq 1 -and $warm.RngCalls -eq $beforeRng) "$resetMode failed or rerolled."
                Assert-Packet $warm.Commands[0] $expected "$resetMode did not restore the saved request."
            }

            # Normal load / warm reset / death-reset all retain SRAM, but exclude transient requests.
            foreach($transient in @(
                ([byte[]]@(2,0x33,0x44,0x55)), ([byte[]]@(0x80,0x20,0,0)),
                ([byte[]]@(1,7,0x18,0x8F)))) {
                Request $m $case $transient
                Assert-Packet ([byte[]]$m.Memory[0x7E0447..0x7E0449]) ([byte[]]$expected[1..3]) 'SFX/fade/death overwrites gameplay snapshot.'
            }
            Request $m $case ([byte[]]@(1,0x0B,0x18,0x8F)) $false # menu/title request, not event $40
            Assert-Packet ([byte[]]$m.Memory[0x7E0447..0x7E0449]) ([byte[]]$expected[1..3]) 'Menu/title overwrites gameplay snapshot.'
            Request $m $case ([byte[]]@(1,0x10,0x18,0x8F)) # ordinary live gameplay request
            # Reset the saved packet via load before death simulation.
            Load $m $case $slot | Out-Null
            $m.Write(0x7EE182,0,2)
            Request $m $case ([byte[]]@(1,0x12,0x18,0x8F))
            Assert-Packet ([byte[]]$m.Memory[0x7E0447..0x7E0449]) ([byte[]]$expected[1..3]) 'Dead-party request overwrites snapshot.'
            $m.Write(0x7EE182,100,2)

            foreach($excludedMap in @(8,256)) {
                $m.Write(0x7E00DC,$excludedMap,2)
                Request $m $case ([byte[]]@(1,0x14,0x18,0x8F))
                Assert-Packet ([byte[]]$m.Memory[0x7E0447..0x7E0449]) ([byte[]]$expected[1..3]) 'Death/intro-map event overwrites gameplay snapshot.'
            }

            # Destination has explicit song: normal event wins and no later fallback is sent.
            Load $m $case $slot | Out-Null
            Request $m $case ([byte[]]@(1,0x11,0x18,0x8F))
            Assert-True ($m.Read(0x7E044C,1) -eq 0) 'Explicit accepted entry request does not cancel fallback.'
            $count = $m.Commands.Count; Tick $m $case
            Assert-True ($m.Commands.Count -eq $count) 'Fallback overrides explicit destination music.'

            # Native updates another slot's counters/checksum, not its music metadata.
            [byte[]]$metadataBefore = $m.Memory[(0x3062BC+$base)..(0x3062C5+$base)]
            $m.Write(0x7E044F,(($slot+1)%4)*0x400,2)
            $m.Write((0x3062B8+$base),10,1)
            $m.A = 0x4568; $m.X = $base; $m.P = 0
            $m.Run((Hook-Address $case.Rom 0x756C5))
            Assert-Packet ([byte[]]$m.Memory[(0x3062BC+$base)..(0x3062C5+$base)]) $metadataBefore 'Saving another slot overwrites this slot music.'
            Load $m $case $slot | Out-Null
            Assert-True ($m.Read(0x7E044C,1) -eq 1) 'Generation-counter changes invalidate existing music metadata.'
            $m.Write(0x7E00DC,499,2); $count = $m.Commands.Count; Tick $m $case
            Assert-True ($m.Read(0x7E044C,1) -eq 0 -and $m.Commands.Count -eq $count) 'Stale target map receives fallback.'

            foreach($field in 0..9) {
                $bad = New-Machine $case
                [Array]::Copy($m.Memory,0x306000,$bad.Memory,0x306000,0x2000)
                $bad.Memory[0x3062BC+$base+$field] = $bad.Memory[0x3062BC+$base+$field] -bxor 1
                Load $bad $case $slot | Out-Null
                Assert-True ($bad.Read(0x7E044C,1) -eq 0 -and $bad.Read(0x7E0446,1) -eq 0) 'Corrupt metadata was accepted.'
            }
            $old = New-Machine $case
            $old.Write(0x7E0446,1,1); $old.Write(0x7E044C,1,1)
            Load $old $case $slot | Out-Null; Tick $old $case
            Assert-True ($old.Commands.Count -eq 0 -and $old.Read(0x7E044C,1) -eq 0) 'Old saves emit garbage requests.'

            $changedWorld = New-Machine $case
            [Array]::Copy($m.Memory,0x306000,$changedWorld.Memory,0x306000,0x2000)
            $changedWorld.Write((0x306001+$base),0x4569,2)
            Load $changedWorld $case $slot | Out-Null
            Assert-True ($changedWorld.Read(0x7E044C,1) -eq 0) 'Metadata from an overwritten/different saved world was accepted.'
            Save $old $case $slot
            Assert-True ($old.Read((0x3062BC+$base),1) -eq 0) 'Save without authoritative music emits valid garbage metadata.'
        }
    }
}

# Fixed-ROM scope: native save format/checksum/load fade, reset trampoline and unrelated hacks.
$allowed = [Collections.Generic.HashSet[int]]::new()
foreach($span in @(@(0x10010,4),@(0x755D6,4),@(0x756C5,4),@(0x755C7,4),@(0x1F109,4),@(0x301E4,5),@(0xB0BF,4),@(0x301AD,4))) {
    foreach($at in $span[0]..($span[0]+$span[1]-1)) { $allowed.Add($at) | Out-Null }
}
foreach($case in $cases) {
    Assert-True ($case.RngAfter -eq ([Random]::new(4242)).Next()) 'Restoration processor consumes seed RNG.'
    $unexpected = ([MusicRoutineMachine]::new($case.Rom)).UnexpectedRomWrite($case.Before,$case.Start,$allowed)
    Assert-True ($unexpected -eq -1) ('Unexpected ROM write at ${0:X6}' -f $unexpected)
    Assert-Packet ([byte[]]$case.Rom[0xFD5..0xFE0]) ([byte[]]$native[0xFD5..0xFE0]) 'Intentional load fade changed.'
    Assert-Packet ([byte[]]$case.Rom[0x75C04..0x75CFF]) ([byte[]]$native[0x75C04..0x75CFF]) 'Native checksum/version/mirror validation changed.'
    if($case.RandomStart -ne 0) {
        Assert-Packet ([byte[]]$case.Rom[0x300000..($case.Start-1)]) ([byte[]]$case.Before[0x300000..($case.Start-1)]) 'Existing RandomMusic/Autosave routine rewritten instead of chained.'
    }
}
$unsupported = New-TestRom $false $false 'ancientcave'
Assert-True (-not $unsupported.Applied -and $unsupported.Start -eq $unsupported.End) 'Unsupported mode is modified.'
$muted = New-TestRom $false $false 'open' $true
Assert-True (-not $muted.Applied -and $muted.Start -eq $muted.End) 'Muted music is restarted.'
foreach($auto in @($false,$true)) {
    $vanillaCase = New-TestRom $false $auto 'rando'
    $m = New-Machine $vanillaCase
    Request $m $vanillaCase ([byte[]]@(1,0x0A,0x13,0x8F))
    Save $m $vanillaCase 3
    Load $m $vanillaCase 3 | Out-Null
    $m.Commands.Clear(); Tick $m $vanillaCase
    Assert-Packet $m.Commands[0] ([byte[]]@(1,0x0A,0x13,0x8F)) 'Vanilla-music/Vanilla-Rando load restoration failed.'
}
$boundary = New-TestRom $false $false 'open' $false 0x31FFF0
$m = New-Machine $boundary
Request $m $boundary ([byte[]]@(1,0x0A,0x13,0x8F))
Save $m $boundary 0; Load $m $boundary 0 | Out-Null
$m.Commands.Clear(); Tick $m $boundary
Assert-True ($m.Commands.Count -eq 1 -and (Hook-Address $boundary.Rom 0x10010) -ge 0xF20000) 'In-bank allocation/relative branches fail at bank boundary.'
Assert-True ($restoreType.GetField('METADATA_OFFSET').GetRawConstantValue() -eq 0x2BC -and
    $restoreType.GetField('METADATA_LENGTH').GetRawConstantValue() -eq 10) 'SRAM allocation changed.'
Assert-True (0x2BC -gt 0x2BB -and 0x2C5 -lt 0x400 -and 0x7C00+0x2C5 -lt 0x7FFF) 'Metadata overlaps native slot data/next slot/Autosave preference.'
Assert-Packet ([byte[]]$native[0x75CDF..0x75CE1]) ([byte[]]@(0xA9,0xB8,0x02)) 'Native checksum span no longer ends at +2BA.'
Assert-Packet ([byte[]]$native[0x75C95..0x75C97]) ([byte[]]@(0xA0,0xBB,0x02)) 'Native mirror comparison allocation changed.'
$again = New-TestRom $true $true
$matching = $cases | Where-Object { $_.RandomStart -ne 0 -and $_.Before[0x1E7D6] -eq 0x22 } | Select-Object -First 1
Assert-Packet ([byte[]]$again.Rom[$again.Start..($again.End-1)]) `
    ([byte[]]$matching.Rom[$matching.Start..($matching.End-1)]) 'Same settings produce nondeterministic generated restoration routines.'
Write-Output 'PASS: emitted save/music hooks; all four slots/primary+backup; cold/normal/reset loads; one-shot override; transient exclusion; effective RandomMusic/no RNG; old/corrupt saves; ownership/scope.'
