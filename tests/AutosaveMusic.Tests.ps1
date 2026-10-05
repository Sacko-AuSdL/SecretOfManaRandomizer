param(
    [string]$AssemblyPath = (Join-Path $PSScriptRoot '..\SoMRandomizer\bin\Debug\net462\SoMRandomizer.exe'),
    [string]$SourceRom = 'D:\views\tools\bots\Secret of Mana (US) (1993) (Action Role Playing Game) (Super Nes).sfc'
)
# Separate process entry point: real Autosave processor + chained load hook, both music modes.
& (Join-Path $PSScriptRoot 'SaveMusicRestoration.Tests.ps1') -AssemblyPath $AssemblyPath -SourceRom $SourceRom -AutosaveOnly
if(-not $?) { throw 'Autosave music integration failed.' }
