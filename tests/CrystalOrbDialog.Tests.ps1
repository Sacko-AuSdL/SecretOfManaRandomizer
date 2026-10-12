param(
    [string]$AssemblyPath = (Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe'),
    [string]$SourceRom = 'D:\views\tools\bots\Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc'
)
$ErrorActionPreference = 'Stop'
$path = (Resolve-Path $AssemblyPath).Path
[void][Reflection.Assembly]::LoadFrom($path)
$compiler = [Microsoft.CSharp.CSharpCodeProvider]::new()
$parameters = [CodeDom.Compiler.CompilerParameters]::new()
$parameters.GenerateInMemory = $true
foreach($reference in @($path,'System.dll','System.Core.dll')) { [void]$parameters.ReferencedAssemblies.Add($reference) }
$compiled = $compiler.CompileAssemblyFromFile($parameters,[string[]]@(
    (Join-Path $PSScriptRoot 'support\SpellShuffleMachine.cs'),
    (Join-Path $PSScriptRoot 'support\CrystalOrbDialogTests.cs')))
if($compiled.Errors.HasErrors) { throw ($compiled.Errors | Out-String) }
$native = [IO.File]::ReadAllBytes((Resolve-Path $SourceRom).Path)
$compiled.CompiledAssembly.GetType('CrystalOrbDialogTests',$true).GetMethod('Run').Invoke($null,[object[]]@(,$native))
