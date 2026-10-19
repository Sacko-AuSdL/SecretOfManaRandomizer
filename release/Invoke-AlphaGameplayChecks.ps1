param(
 [Parameter(Mandatory=$true)][string]$PackageRoot,
 [Parameter(Mandatory=$true)][string]$SourceRom,
 [string]$OutputRoot=''
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if(-not $OutputRoot) { $OutputRoot=Join-Path $repo '.codex-build\gameplay-checks' }
$package=(Resolve-Path $PackageRoot).Path; $source=(Resolve-Path $SourceRom).Path
$output=[IO.Path]::GetFullPath($OutputRoot); [void][IO.Directory]::CreateDirectory($output)
$exe=Join-Path $package 'SoMRandomizer.exe'
function Assert-True([bool]$Value,[string]$Message) { if(-not $Value) { throw $Message } }
$a=[Reflection.Assembly]::LoadFrom($exe)
Assert-True ($null -eq $a.GetType('SoMRandomizer.processing.hacks.common.util.WeaponPowerCalculator',$false)) 'Package contains Weapon Power.'
$original=[IO.File]::ReadAllBytes($source)
if($original.Length -eq 0x200200) { $original=[byte[]]$original[0x200..($original.Length-1)] }
Assert-True ($original.Length -eq 0x200000) 'Expected the compatible 2 MiB source ROM.'
# The actual production EXE is launched; no generator subclass or processor removal.
$profilesPath=Join-Path $package 'StarterSettings/Profiles.json'
if(-not (Test-Path $profilesPath)) { $profilesPath=Join-Path $PSScriptRoot 'StarterSettings/Profiles.json' }
$profiles=Get-Content $profilesPath -Raw | ConvertFrom-Json
$baselinePath=Join-Path $package 'RELEASE.json'
if(-not (Test-Path $baselinePath)) { $baselinePath=Join-Path $PSScriptRoot 'RC2-PACKAGE.json' }
$baseline=Get-Content $baselinePath -Raw | ConvertFrom-Json
$results=@()
foreach($profile in @($profiles)+@($profiles[0])) {
 $name=$profile.Name; if($results.Count -eq 3) { $name='Short-Repeat' }
 $directory=Join-Path $output $name; [void][IO.Directory]::CreateDirectory($directory)
 $destination=Join-Path $directory ($name+'.sfc')
 $start=[Diagnostics.ProcessStartInfo]::new($exe)
 $start.WorkingDirectory=$directory; $start.UseShellExecute=$false; $start.CreateNoWindow=$true
 $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
 $start.Arguments='srcRom="'+$source+'" dstRom="'+$destination+'" seed="'+$profile.Seed+'" options="'+$profile.Options+'"'
 $process=[Diagnostics.Process]::Start($start)
 Assert-True ($process.WaitForExit(60000)) 'CLI generation timed out; no GUI process was killed.'
 $stdout=$process.StandardOutput.ReadToEnd(); $stderr=$process.StandardError.ReadToEnd()
 [IO.File]::WriteAllText((Join-Path $directory 'cli-output.txt'),$stdout+"`n"+$stderr)
 Assert-True (Test-Path $destination) ('CLI did not generate '+$name)
 $log=Get-Content (Join-Path $directory ('log_'+$profile.Seed+'.txt')) -Raw
 Assert-True ($log -match '\[general\] Done!' -and $log -match 'Open world generation finished!') 'Production simulation/generation did not finish.'
 Assert-True ($log -notmatch 'Short-circuiting open world simulator|TEST_PROFILE|test bootstrap|Adding: \[Weapon Power') 'Manual bypass or excluded processor active.'
 [byte[]]$rom=[IO.File]::ReadAllBytes($destination)
 Assert-True ($rom.Length -eq 0x400000) 'Invalid generated size.'
 Assert-True ([Linq.Enumerable]::SequenceEqual([byte[]]$rom[0x8E345..0x8E355],[byte[]]$original[0x8E345..0x8E355])) 'Critical native C8 sequence changed.'
 $table=([int]$rom[0x1E7A3]+([int]$rom[0x1E7A4]-shl 8)+([int]$rom[0x1E7A5]-shl 16))-0xC00000
 Assert-True ($table -ge 0 -and $table+3*0xA01 -le $rom.Length) 'Event table outside ROM.'
 for($event=0;$event -lt 0xA01;$event++) {
  $pointer=$table+3*$event
  $at=([int]$rom[$pointer]+([int]$rom[$pointer+1]-shl 8)+([int]$rom[$pointer+2]-shl 16))-0xC00000
  Assert-True ($at -ge 0 -and $at -lt $rom.Length) ('Event pointer outside ROM: '+$event)
 }
 $pointer=$table+3*0x103
 $at=([int]$rom[$pointer]+([int]$rom[$pointer+1]-shl 8)+([int]$rom[$pointer+2]-shl 16))-0xC00000
 # Command-aware parsing of actual event 103: parameter bytes may be zero.
 $ready=$false; $rope=$false; $ended=$false
 for($i=$at;$i -lt $at+4096;) {
  $op=[int]$rom[$i]
  Assert-True (-not ($op -ge 0x18 -and $op -le 0x1D)) 'Manual Sword teleport present.'
  if($op -eq 0) { $ended=$true; break }
  if($op -eq 0x30 -and $rom[$i+1] -eq 0x10 -and $rom[$i+2] -eq 0xB) { $ready=$true }
  if($op -eq 0x1E -and $rom[$i+1] -eq 0x46) { $rope=$true }
  if($op -eq 0x39) { Assert-True ($rom[$i+2] -eq 0x90) 'Manual actor supplies present in Sword event.' }
  if($op -ge 0x7F -or $op -in @(2,3,4,5,6,8,9,0xA,0x50,0x51,0x52,0x5D,0x5E,0x5F)) { $i++ }
  elseif(($op -ge 0x10 -and $op -le 0x2F) -or $op -in @(0x57,0x59,0x5A)) { $i+=2 }
  elseif($op -in @(0x30,0x31,0x32,0x34,0x36,0x37,0x42)) { $i+=3 }
  elseif($op -eq 0x39) { $i+=4 }
  elseif($op -eq 0x40) { $i+=5 }
  else { throw ('Unexpected startup opcode {0:X2}' -f $op) }
 }
 Assert-True ($ready -and $rope -and $ended) 'Normal Sword initialization lost.'
 foreach($key in @('opStartLevel = 1','opStartGold = 0','opAllWeaponOrbs = no')) { Assert-True ($log.Contains($key)) ('Normal profile missing '+$key) }
 $spoiler=[IO.File]::ReadAllLines((Join-Path $directory ('log_'+$profile.Seed+'_SPOILER.txt')))
 $expectations=@($spoiler|Where-Object { $_ -match '\[spoiler\]\s+.+ -> (flammie drum|axe|whip|boy|girl|sprite) \[event' }|ForEach-Object { [regex]::Match($_,'\[spoiler\]\s+(.+)').Groups[1].Value })
 $romHash=(Get-FileHash $destination).Hash
 $baselineName=if($name -eq 'Short-Repeat') { 'Short' } else { $name }
 $expected=@($baseline.Profiles | Where-Object Name -eq $baselineName)
 Assert-True ($expected.Count -eq 1 -and $romHash -ceq $expected[0].ExpectedRomSha256) ('Committed source changed RC2 starter ROM: '+$name)
 $results += [pscustomobject]@{Name=$name;Seed=$profile.Seed;Goal=$profile.Goal;Options=$profile.Options;Sha256=$romHash;Simulation='passed';NormalSword='passed';GameplayCompletion='pending';KeyPlacements=$expectations}
 $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'results.json') -Encoding UTF8
 Write-Output ('PASS: standalone production CLI '+$name+'; normal Sword/no supplies, simulation and pointer/native-code checks.')
}
Assert-True ($results[0].Sha256 -eq $results[3].Sha256) 'Packaged CLI regeneration is not deterministic.'
'PASS: three normal production configurations plus deterministic repeat. Clean Windows and full gameplay NOT tested.'
