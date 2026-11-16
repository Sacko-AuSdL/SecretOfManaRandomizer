param(
    [string]$AssemblyPath=(Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe'),
    [string]$SourceRom='D:\views\tools\bots\Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc',
    [string]$GeneratedRom=''
)
$ErrorActionPreference='Stop'
$assembly=[Reflection.Assembly]::LoadFrom((Resolve-Path $AssemblyPath).Path)
$cp=[CodeDom.Compiler.CompilerParameters]::new(); $cp.GenerateInMemory=$true
foreach($ref in @($assembly.Location,'System.dll','System.Core.dll')) { [void]$cp.ReferencedAssemblies.Add($ref) }
$compiled=([Microsoft.CSharp.CSharpCodeProvider]::new()).CompileAssemblyFromFile($cp,[string[]]@(
    (Join-Path $PSScriptRoot 'support\SpellShuffleMachine.cs'),
    (Join-Path $PSScriptRoot 'support\UndineCachedReturnChecks.cs')))
if($compiled.Errors.HasErrors) { throw ($compiled.Errors|Out-String) }
$checks=$compiled.CompiledAssembly.GetType('UndineCachedReturnChecks',$true)
[byte[]]$original=[IO.File]::ReadAllBytes((Resolve-Path $SourceRom).Path)
$checks.GetMethod('Run').Invoke($null,@(,$original))
if($GeneratedRom) {
    [byte[]]$rom=[IO.File]::ReadAllBytes((Resolve-Path $GeneratedRom).Path)
    $checks.GetMethod('FinalRom').Invoke($null,@($original,$rom))
}
