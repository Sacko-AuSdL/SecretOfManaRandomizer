param(
    [string]$AssemblyPath = '',
    [Parameter(Mandatory=$true)][string]$SourceRom,
    [string]$OutputRoot = (Join-Path ([IO.Path]::GetTempPath()) ('somr-kakkara-chaos-' + [Guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference = 'Stop'
if(-not $AssemblyPath) { $AssemblyPath = Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe' }
$path = (Resolve-Path $AssemblyPath).Path
$assembly = [Reflection.Assembly]::LoadFrom($path)
function Assert-True([bool]$Value, [string]$Message) { if(-not $Value) { throw $Message } }
function T([string]$Name) { $assembly.GetType('SoMRandomizer.' + $Name, $true) }

# Fixtures exercise the real solver. Full generations below launch the production EXE,
# including its assembly-resolution setup, rather than approximating its CLI environment.
$source = @'
using System;
using System.Collections.Generic;
using System.Linq;
using SoMRandomizer.config.settings;
using SoMRandomizer.processing.common;
using SoMRandomizer.processing.openworld;
using SoMRandomizer.processing.openworld.cannon;
using SoMRandomizer.processing.openworld.randomization;
public static class KakkaraReachabilityChecks
{
    static void Require(bool condition, string message)
    { if(!condition) throw new Exception(message); }
    public static void CheckSimulator()
    {
        Require(CannonTravelRegions.getLocationRegion("girl") == CannonTravelRegion.PotosArea,
            "Pandora event $188 is incorrectly treated as a portable startup reward.");
        Require(CannonTravelRegions.getLocationRegion("sword pedestal") == CannonTravelRegion.PotosArea,
            "Physical sword-map event $532 is incorrectly treated as a portable startup reward.");
        foreach(string start in new[] {"starter weapon (main)", "starter weapon (alt)"})
            Require(CannonTravelRegions.getLocationRegion(start) == CannonTravelRegion.Unrestricted,
                "Actual event $103 startup reward lost its unrestricted ownership.");
        // The observed all-closed graph: the old code falsely collected a remote drum.
        foreach(string goal in new[] {"manabeast", "xmas2020", "xmas2020b"})
        foreach(bool drumInLogic in new[] {true, false})
        foreach(string drumLocation in new[] {"sword pedestal", "girl", "local"})
        {
            bool localDrum = drumLocation == "local";
            var settings = new OpenWorldSettings(new CommonSettings());
            settings.set("opStartingLocation", "kakkara");
            settings.set("opFlammieDrumInLogic", drumInLogic ? "yes" : "no");
            settings.set("cannonTravelRandomization", "chaos");
            var context = new RandoContext();
            var w = context.workingData;
            w.set("openWorldGoalShortName", goal);
            w.setInt("manaSeedsRequired", 0);
            w.setBool("anyMagicExists", false);
            w.setInt("cannonTravelResolved", 1);
            w.set("cannonTravelResolvedMode", "chaos");
            foreach(var office in CannonTravelModel.OFFICES)
            {
                w.setInt("cannonTravelRouteCount_" + office.Id, 0);
                w.set("cannonTravelClosedMessage_" + office.Id, CannonTravelModel.CLOSED_OFFICE_MESSAGE);
            }
            foreach(string actor in new[] {"boy", "girl", "sprite"})
            {
                w.setBool("startWith" + char.ToUpper(actor[0]) + actor.Substring(1), actor == "boy");
                w.set(actor + "Class", "OGboy");
                w.setInt(actor + "StartWeapon", 2); // Axe satisfies the real pedestal cutting lock.
            }
            bool christmas = goal != "manabeast";
            string local = christmas ? "salamando" : "sandship captain";
            var placements = new Dictionary<PrizeLocation, PrizeItem>();
            foreach(string name in new[] {"girl", "sword pedestal", local, "starter weapon (main)"})
            {
                var loc = new PrizeLocation(name, 0, 0, new string[0], new string[0], 1);
                string prize = name == (localDrum ? local : drumLocation)
                    ? "flammie drum" : "glove";
                placements.Add(loc, new PrizeItem(prize, "item", new byte[0], "", 0, 1));
            }
            var result = OpenWorldSimulator.runSimulation(placements, settings, context);
            Require((result.score > 0) == (localDrum || !drumInLogic),
                "Closed-start circular Flammie validation failed: " + goal + "/" + drumInLogic + "/" + localDrum);
            if(drumInLogic)
                Require(!result.collectionCycles[0].Contains("girl") &&
                    !result.collectionCycles[0].Contains("sword pedestal"),
                    "Remote Potos check credited before any actual escape.");
        }
    }
}
'@
$parameters = [CodeDom.Compiler.CompilerParameters]::new()
$parameters.GenerateInMemory = $true
foreach($reference in @($path, 'System.dll', 'System.Core.dll')) { [void]$parameters.ReferencedAssemblies.Add($reference) }
$compiled = ([Microsoft.CSharp.CSharpCodeProvider]::new()).CompileAssemblyFromSource($parameters, $source)
Assert-True (-not $compiled.Errors.HasErrors) ($compiled.Errors | Out-String)
$checks = $compiled.CompiledAssembly.GetType('KakkaraReachabilityChecks', $true)
[void]$checks.GetMethod('CheckSimulator').Invoke($null, @())
Write-Output 'PASS: physical versus startup ownership; closed Kakkara and Christmas starts reject remote drums and accept local escape/out-of-logic drums.'

$baseOptions = 'version=1.49 mode=open weaponUpgradeCosts=reduced playerMagicDamage=random crystalOrbWeaponBreaking=on spellShuffle=party cannonTravelRandomization=chaos freeCannonTravel=on showUpperLandOrbRequirement=on opStartingLocation=kakkara opCharacters=findbothCL opGoal=vlong opLogic=restrictive opFlammieDrumInLogic=yes'
$seed = '370385E350F7D294'
$results = @()
function Invoke-Case([string]$Name, [string]$Options) {
    $directory = [IO.Path]::GetFullPath((Join-Path $OutputRoot $Name))
    [void][IO.Directory]::CreateDirectory($directory)
    $romPath = Join-Path $directory ($Name + '.sfc')
    $start = [Diagnostics.ProcessStartInfo]::new($path)
    $start.WorkingDirectory=$directory; $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
    $start.Arguments='srcRom="'+(Resolve-Path $SourceRom).Path+'" dstRom="'+$romPath+'" seed="'+$seed+'" options="'+$Options+'"'
    $process = [Diagnostics.Process]::Start($start)
    Assert-True ($process.WaitForExit(60000)) 'Production CLI generation timed out; process was not killed.'
    $cli = $process.StandardOutput.ReadToEnd() + $process.StandardError.ReadToEnd()
    Assert-True ($process.ExitCode -eq 0) $cli
    Assert-True (Test-Path $romPath) ("No generated ROM: " + $Name)
    $log = Get-Content (Join-Path $directory ('log_' + $seed + '.txt')) -Raw
    Assert-True ($log -match 'Open world generation finished!' -and $log -match '\[general\] Done!') 'Simulation/generation failed.'
    Assert-True ($log -notmatch 'Short-circuiting|TEST_PROFILE|test bootstrap') 'Test bypass present.'
    $model = T 'processing.openworld.cannon.CannonTravelModel'
    $scriptType = T 'processing.common.structure.EventScript'
    $spoiler = Get-Content (Join-Path $directory ('log_' + $seed + '_SPOILER.txt')) -Raw
    $cannon = [regex]::Match($spoiler,'(?s)\[Cannon Travel\](.*?)\[Crystal Orb requirements\]').Groups[1].Value
    $cannon = ($cannon -replace '(?m)^.*\[spoiler\]\s*','').Trim()
    # Verify actual final ROM closed-office menu bytes, not merely abstract reachability.
    [byte[]]$rom = [IO.File]::ReadAllBytes($romPath)
    $table = ([int]$rom[0x1E7A3] + ([int]$rom[0x1E7A4] -shl 8) + ([int]$rom[0x1E7A5] -shl 16)) - 0xC00000
    $closedCount = 0
    foreach($office in $model.GetField('OFFICES').GetValue($null)) {
        $pointer = $table + 3*$office.MenuEvent
        $at = ([int]$rom[$pointer] + ([int]$rom[$pointer+1] -shl 8) + ([int]$rom[$pointer+2] -shl 16)) - 0xC00000
        if($cannon -match ('(?m)^'+[regex]::Escape($office.DisplayName)+': CLOSED - (.+)\r?$')) {
            $closedCount++
            $closed = [Activator]::CreateInstance($scriptType)
            $closed.AddDialogueBox($Matches[1].Trim()); $closed.End()
            [byte[]]$expected = $closed.ToArray()
            Assert-True ([Linq.Enumerable]::SequenceEqual($expected,[byte[]]$rom[$at..($at+$expected.Length-1)])) 'Actual closed office has a hidden route/flag/fare gate.'
        }
    }
    $cycle0 = [regex]::Match($spoiler,'(?s)Collection cycle:0(.*?)Collection cycle:1').Groups[1].Value
    if($Name -in @('reported','reported-repeat','paid')) {
        Assert-True ($closedCount -eq 7) 'Reproduction graph changed instead of correcting placement.'
        Assert-True ($cycle0 -notmatch 'girl ->|sword pedestal ->') 'Remote check still credited at Kakkara start.'
        Assert-True ($cycle0 -match 'fire palace chest 1 -> flammie drum') 'Reported seed lacks its proven local escape.'
        $rewardPointer = $table + 3*0x68A
        $rewardAt = ([int]$rom[$rewardPointer] + ([int]$rom[$rewardPointer+1] -shl 8) + ([int]$rom[$rewardPointer+2] -shl 16)) - 0xC00000
        $nextAt = $rom.Length
        for($id=0;$id -lt 0xA01;$id++) {
            $p=$table+3*$id
            $eventAt=([int]$rom[$p]+([int]$rom[$p+1] -shl 8)+([int]$rom[$p+2] -shl 16))-0xC00000
            if($eventAt -gt $rewardAt -and $eventAt -lt $nextAt) { $nextAt=$eventAt }
        }
        $hasDrum=$false
        for($i=$rewardAt;$i -lt $nextAt-1;$i++) { if($rom[$i] -eq 0x1E -and $rom[$i+1] -eq 0x47) { $hasDrum=$true; break } }
        Assert-True $hasDrum 'Final local reward event does not grant the Flammie Drum.'
        # Decode the actual map-128 sword object: it still dispatches event $532,
        # not event $103 or a startup grant moved to Kakkara.
        $objects = (T 'processing.common.VanillaMapUtil').GetMethod('getObjects').Invoke($null,@($rom,128))
        Assert-True ($objects[0].getEvent() -eq 0x532) 'Physical pedestal event was relocated.'
    }
    return [pscustomobject]@{Name=$Name;Seed=$seed;Options=$Options;Sha256=(Get-FileHash $romPath).Hash;Rom=$romPath;Cycle0=($cycle0 -replace '(?m)^.*\[spoiler\]\s*','');Cannon=$cannon}
}

# Exact reported configuration first; neighbors reuse its seed and alter one axis only.
$results += Invoke-Case 'reported' $baseOptions
$results += Invoke-Case 'reported-repeat' $baseOptions
$results += Invoke-Case 'paid' ($baseOptions.Replace('freeCannonTravel=on','freeCannonTravel=off'))
foreach($mode in @('off','open','shuffle')) {
    $results += Invoke-Case ('kakkara-'+$mode) ($baseOptions.Replace('cannonTravelRandomization=chaos','cannonTravelRandomization='+$mode))
}
$results += Invoke-Case 'short' ($baseOptions.Replace('opGoal=vlong','opGoal=vshort'))
$results += Invoke-Case 'potos' ($baseOptions.Replace('opStartingLocation=kakkara','opStartingLocation=default'))
$results += Invoke-Case 'drum-out' ($baseOptions.Replace('opFlammieDrumInLogic=yes','opFlammieDrumInLogic=no'))
Assert-True ($results[0].Sha256 -eq $results[1].Sha256) 'Exact repaired seed is not deterministic.'
Assert-True ($results[0].Cycle0 -eq $results[2].Cycle0) 'Fare toggle changed initial progression.'
Assert-True ($results[0].Cannon -eq $results[2].Cannon) 'Fare toggle changed the Cannon network.'
$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutputRoot 'results.json') -Encoding UTF8
$results | ForEach-Object { Write-Output ('PASS: '+$_.Name+'; '+$_.Sha256) }
Write-Output ('PASS: nine normal full generations, actual final closed-office events, local escape and deterministic repeat. Emulator verification remains required. Output: '+$OutputRoot)
