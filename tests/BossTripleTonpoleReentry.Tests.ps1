param(
    [string]$AssemblyPath=(Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe'),
    [string]$SourceRom='D:\views\tools\bots\Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc'
)
$ErrorActionPreference='Stop'
# Reuse the existing in-memory boss/processor fixtures and their full assertions.
. (Join-Path $PSScriptRoot 'BossTripleTonpoleCompatibility.Tests.ps1') -AssemblyPath $AssemblyPath -SourceRom $SourceRom
$cp=[CodeDom.Compiler.CompilerParameters]::new(); $cp.GenerateInMemory=$true
foreach($ref in @($assembly.Location,'System.dll','System.Core.dll')) { [void]$cp.ReferencedAssemblies.Add($ref) }
$compiled=([Microsoft.CSharp.CSharpCodeProvider]::new()).CompileAssemblyFromFile($cp,[string[]]@((Join-Path $PSScriptRoot 'support\TripleTonpoleReentryChecks.cs')))
if($compiled.Errors.HasErrors) { throw ($compiled.Errors|Out-String) }
$checks=$compiled.CompiledAssembly.GetType('TripleTonpoleReentryChecks',$true)
$checks.GetMethod('Run').Invoke($null,@($original,$cave[1],$cave[2],$normal[1],$normal[2]))
