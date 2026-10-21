param(
 [Parameter(Mandatory=$true)][string]$AssemblyPath,
 [Parameter(Mandatory=$true)][string]$SnapshotRoot
)
$ErrorActionPreference='Stop'
function Assert-True([bool]$Value,[string]$Message) { if(-not $Value) { throw $Message } }
$path=(Resolve-Path $AssemblyPath).Path; $snapshot=(Resolve-Path $SnapshotRoot).Path
$a=[Reflection.Assembly]::LoadFrom($path)
Assert-True ($null -eq $a.GetType('SoMRandomizer.processing.hacks.common.util.WeaponPowerCalculator',$false)) 'Weapon Power calculator compiled into release.'
foreach($type in @('DoppelgangerManualProfile','SpellShuffleTestGenerator','DirectBossPlacementTestGenerator','TropicalloDirectTestGenerator','SpikeyDirectTestGenerator')) { Assert-True ($null -eq $a.GetType($type,$false)) ('Manual harness compiled into release: '+$type) }
$g=[Activator]::CreateInstance($a.GetType('SoMRandomizer.processing.openworld.OpenWorldGenerator',$true))
$base=$a.GetType('SoMRandomizer.processing.common.RomGenerator',$true)
$processors=$base.GetField('commonHacks',[Reflection.BindingFlags]'Instance,NonPublic').GetValue($g)
Assert-True (@($processors|Where-Object {$_.GetType().Name -match 'WeaponPower|TestBootstrap'}).Count -eq 0) 'Excluded processor registered.'
$settings=[Activator]::CreateInstance($a.GetType('SoMRandomizer.config.settings.OpenWorldSettings',$true),[object[]]@([Activator]::CreateInstance($a.GetType('SoMRandomizer.config.settings.CommonSettings',$true))))
Assert-True ($settings.ToString() -notmatch '(?i)weaponPower|TEST_PROFILE') 'Experimental setting leaked.'
Assert-True ($g.GetType().Name -eq 'OpenWorldGenerator') 'Not the ordinary production generator.'
$manifest=Get-Content (Join-Path $snapshot 'RELEASE-SOURCE-MANIFEST.json') -Raw | ConvertFrom-Json
foreach($file in $manifest.Files) {
 Assert-True ((Get-FileHash -LiteralPath (Join-Path $snapshot $file.Path) -Algorithm SHA256).Hash -eq $file.SnapshotSha256) ('Snapshot changed after inventory: '+$file.Path)
 Assert-True ($file.Path -notmatch '(?i)(^|/)(tests|bin|obj|\.codex[^/]*)(/|$)|WeaponPowerCalculator|\.(sfc|smc|srm|pdb|log)$') 'Disallowed snapshot input.'
}
Assert-True (-not (Test-Path (Join-Path $snapshot 'SoMRandomizer/processing/hacks/common/util/WeaponPowerCalculator.cs'))) 'Excluded source file present.'
[xml]$project=Get-Content (Join-Path $snapshot 'SoMRandomizer/SoMRandomizer.csproj')
Assert-True ($project.Project.PropertyGroup.TargetFramework -contains 'net462') 'Target framework changed.'
$json=@($project.Project.ItemGroup.PackageReference|Where-Object Include -eq 'System.Text.Json')
Assert-True ($json.Count -eq 1 -and $json[0].Version -eq '8.0.6') 'Unpatched direct JSON dependency.'
$lock=Get-Content (Join-Path $snapshot 'SoMRandomizer/packages.lock.json') -Raw | ConvertFrom-Json
Assert-True ($lock.dependencies.'.NETFramework,Version=v4.6.2'.'System.Text.Json'.resolved -eq '8.0.6') 'Lock does not pin patched JSON dependency.'
$jsonPath=Join-Path ([IO.Path]::GetDirectoryName($path)) 'System.Text.Json.dll'
$jsonVersion=[Diagnostics.FileVersionInfo]::GetVersionInfo($jsonPath).ProductVersion
# NuGet 8.0.6 contains the runtime 8.0.18 servicing binary. ProductVersion is
# NOT the NuGet version; prove identity against the locked/restored net462 asset.
$assets=Get-Content (Join-Path $snapshot 'SoMRandomizer/obj/project.assets.json') -Raw | ConvertFrom-Json
Assert-True ($null -ne $assets.libraries.'System.Text.Json/8.0.6') 'Patched asset missing from resolved graph.'
$cache=@($assets.packageFolders.PSObject.Properties)[0].Name
$asset=Join-Path $cache 'system.text.json/8.0.6/lib/net462/System.Text.Json.dll'
Assert-True ((Get-FileHash $jsonPath -Algorithm SHA256).Hash -eq (Get-FileHash $asset -Algorithm SHA256).Hash) 'Output does not match the locked patched net462 asset.'
Assert-True ($jsonVersion.StartsWith('8.0.18+')) 'Unexpected JSON servicing binary product version.'
$resource=$a.GetManifestResourceStream('System.Text.Json.dll')
Assert-True ($null -ne $resource) 'Patched embedded dependency missing.'
$sha=[Security.Cryptography.SHA256]::Create()
try { $embedded=[BitConverter]::ToString($sha.ComputeHash($resource)).Replace('-','') } finally { $resource.Dispose(); $sha.Dispose() }
Assert-True ($embedded -eq (Get-FileHash $jsonPath -Algorithm SHA256).Hash) 'Embedded and loose JSON dependency differ.'
$registry=$a.GetType('SoMRandomizer.processing.common.BossEncounterRegistry',$true)
$maps=$a.GetType('SoMRandomizer.processing.common.VanillaBossMaps',$true)
$jehk=$maps.GetField('DOPPELGANGERS').GetValue($null)
Assert-True ($registry.GetMethod('CanSwap').Invoke($null,@($jehk,[byte]0x5E))) 'Approved production Frost/Jehk binding missing.'
$contextType=$a.GetType('SoMRandomizer.processing.common.RandoContext',$true)
Assert-True ($null -eq $contextType.GetField('frostJehkManualPilot',[Reflection.BindingFlags]'Instance,NonPublic')) 'Pilot switch remains compiled.'
foreach($name in @('AllowsManualPilot','GetDirectPrototype','AssessDirect')) {
 Assert-True ($null -eq $registry.GetMethod($name,[Reflection.BindingFlags]'Static,Public,NonPublic')) ('Experimental registry API remains: '+$name)
}
Assert-True (@($a.GetTypes() | Where-Object {$_.Name -match '^(DirectBoss|BossDirect)' -and $_.Name -notin @('DirectBossSpawn','DirectBossFloor')}).Count -eq 0) 'Prototype types remain compiled.'
Assert-True ($null -ne $a.GetType('SoMRandomizer.processing.common.BossArenaGeometry',$false)) 'Required shared production geometry helpers missing.'
Assert-True ($registry.GetMethod('Capability').Invoke($null,@($jehk,[byte]0x5E)).ToString() -eq 'Implemented') 'Approved Frost/Jehk production classification missing.'
foreach($file in $manifest.Files | Where-Object Path -like '*.cs') {
 Assert-True ((Get-Content -LiteralPath (Join-Path $snapshot $file.Path) -Raw) -notmatch 'frostJehkManualPilot|AllowsManualPilot|DirectBossPlacement|BossDirectAssessment|DirectBossJumpPositions|GetDirectPrototype|AssessDirect') ('Experimental source dependency: '+$file.Path)
}
Assert-True ($manifest.Files.Count -eq 490 -and $manifest.Candidate -eq 'Alpha 0.1 RC4') 'Unexpected final runtime inventory.'
'PASS: RC4 ordinary generator; required runtime geometry/approved expansion present; Weapon Power and prototype catalogue/APIs/pilot absent; all 490 source hashes and patched dependencies intact.'
