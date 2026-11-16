param([Parameter(Mandatory=$true)][string]$AssemblyPath,[Parameter(Mandatory=$true)][string]$SourceRom,[Parameter(Mandatory=$true)][string]$OutputRoot,[string]$SourceRoot=(Join-Path $PSScriptRoot '..'))
$ErrorActionPreference='Stop';$SourceRoot=[IO.Path]::GetFullPath($SourceRoot);$AssemblyPath=[IO.Path]::GetFullPath($AssemblyPath);[void][IO.Directory]::CreateDirectory($OutputRoot)
$cases=@('OpenWorldStartingLocation','FreeCannonTravel','CannonTravelRandomization','CrystalOrbRequirements','CrystalOrbWeaponBreaking','UpperLandOrbAccessibility','BossTripleTonpoleReentry','UndineCachedReturn','KakkaraProgression','MaraEmptyPrize');$results=@()
foreach($name in $cases){
 $test=Join-Path $SourceRoot ('tests/'+$name+'.Tests.ps1');$text=Get-Content $test -Raw;$args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$test,'-AssemblyPath',$AssemblyPath)
 if($text -match '\[string\]\$SourceRom'){$args+=@('-SourceRom',$SourceRom)}
 if($text -match '\[string\]\$OutputRoot'){$args+=@('-OutputRoot',(Join-Path $OutputRoot $name))}
 $prior=$ErrorActionPreference;$ErrorActionPreference='Continue';& powershell @args *> (Join-Path $OutputRoot ($name+'.log'));$code=$LASTEXITCODE;$ErrorActionPreference=$prior
 $results+=[pscustomobject]@{Test=$name;ExitCode=$code};$results|Export-Csv -NoTypeInformation (Join-Path $OutputRoot 'results.csv');Write-Output ($name+': '+$code)
}
if(@($results|Where-Object ExitCode -ne 0).Count){throw 'Focused verification failed; inspect named logs.'}
