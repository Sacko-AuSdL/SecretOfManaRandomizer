param(
 [Parameter(Mandatory=$true)][string]$CandidateRoot,
 [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9-]*$')][string]$StageName='package'
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')); $root=[IO.Path]::GetFullPath($CandidateRoot)
$snapshot=Join-Path $root 'source'; $build=Join-Path $root 'build-release'; $stage=Join-Path $root $StageName
if(Test-Path $stage) { throw 'Package staging already exists; use a new candidate directory.' }
$manifest=Get-Content (Join-Path $snapshot 'RELEASE-SOURCE-MANIFEST.json') -Raw | ConvertFrom-Json
foreach($inputFile in $manifest.Files) { if((Get-FileHash (Join-Path $snapshot $inputFile.Path)).Hash -ne $inputFile.SnapshotSha256) { throw ('Source inventory mismatch: '+$inputFile.Path) } }
[void][IO.Directory]::CreateDirectory($stage)
$outputs=@(Get-ChildItem $build -File | Where-Object { $_.Name -eq 'SoMRandomizer.exe' -or $_.Name -eq 'SoMRandomizer.exe.config' -or $_.Extension -eq '.dll' })
if(-not ($outputs|Where-Object Name -eq 'SoMRandomizer.exe')) { throw 'Release executable missing.' }
foreach($file in $outputs) { Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $stage $file.Name) }
$documents=@{ 'AlphaTesterGuide.md'='PlayerGuide.md';'AlphaChangelog.md'='Changelog.md';'AlphaKnownIssues.md'='KnownIssues.md';'AlphaCleanWindowsChecklist.md'='CleanWindowsChecklist.md';'LICENSE'='LICENSE' }
foreach($key in $documents.Keys) { Copy-Item -LiteralPath (Join-Path $repo $key) -Destination (Join-Path $stage $documents[$key]) }
Copy-Item -LiteralPath (Join-Path $snapshot 'RELEASE-SOURCE-MANIFEST.json') -Destination (Join-Path $stage 'RELEASE-SCOPE.json')
# Archive only the explicit source inventory, never obj/bin, tests or local files.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$sourceDir=Join-Path $stage 'Source'; [void][IO.Directory]::CreateDirectory($sourceDir)
$archive=[IO.Compression.ZipFile]::Open((Join-Path $sourceDir 'Alpha-0.1-RC3-source.zip'),[IO.Compression.ZipArchiveMode]::Create)
try {
 foreach($inputFile in $manifest.Files) { [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,(Join-Path $snapshot $inputFile.Path),$inputFile.Path,[IO.Compression.CompressionLevel]::Optimal) }
 [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,(Join-Path $snapshot 'RELEASE-SOURCE-MANIFEST.json'),'RELEASE-SOURCE-MANIFEST.json',[IO.Compression.CompressionLevel]::Optimal)
} finally { $archive.Dispose() }
# Preserve real upstream package licenses/notices. Include the whole locked graph
# rather than assuming compile-only/transitive Microsoft packages need no notice.
$assets=Get-Content (Join-Path $snapshot 'SoMRandomizer/obj/project.assets.json') -Raw | ConvertFrom-Json
$cache=@($assets.packageFolders.PSObject.Properties)[0].Name
$licenseDir=Join-Path $stage 'ThirdPartyLicenses'; [void][IO.Directory]::CreateDirectory($licenseDir)
$notices=@('# Third party attribution','','Unofficial experimental fork of Moppleton''s Secret of Mana Randomizer: https://github.com/Moppu/SecretOfManaRandomizer','The application is LGPL-2.1-or-later; see LICENSE and the bundled buildable source.','Dependencies retain their own licenses. Exact versions and notices follow.','Manabite artwork/palette by Tomm (Discord). The maintainer confirms the original creator granted permission for use and redistribution (2026-10-18). Existing credits are retained. No additional license or attribution conditions were supplied; no creator URL or separate license terms are invented.','')
foreach($library in $assets.libraries.PSObject.Properties | Sort-Object Name) {
 if($library.Value.type -ne 'package') { continue }
 if($library.Name -match '^Microsoft.NETFramework.ReferenceAssemblies(\.net462)?/') {
  $notices+=('- '+$library.Name+': build-only targeting pack; no targeting-pack DLLs are redistributed. Restore separately when building source.')
  continue
 }
 $directory=Join-Path $cache $library.Value.path
 $nuspec=Get-ChildItem -LiteralPath $directory -Filter '*.nuspec' | Select-Object -First 1
 [xml]$metadata=Get-Content -LiteralPath $nuspec.FullName
 $m=$metadata.package.metadata; $label=$library.Name.Replace('/','-')
 $license=$m.license.InnerText; if(-not $license) { $license=[string]$m.licenseUrl }
 $notices+=('- '+$library.Name+'; authors: '+$m.authors+'; license: '+$license+'; '+$m.copyright)
 $files=@(Get-ChildItem -LiteralPath $directory -File | Where-Object { $_.Name -match '(?i)license|notice' })
 if($files.Count -eq 0) { throw ('No actual license/notice available for '+$library.Name) }
 $target=Join-Path $licenseDir $label; [void][IO.Directory]::CreateDirectory($target)
 foreach($file in $files) { Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $target $file.Name) }
}
$notices | Set-Content -LiteralPath (Join-Path $stage 'THIRD-PARTY-NOTICES.md') -Encoding UTF8
$profiles=Get-Content (Join-Path $PSScriptRoot 'StarterSettings.json') -Raw | ConvertFrom-Json
$settingsDir=Join-Path $stage 'StarterSettings'; [void][IO.Directory]::CreateDirectory($settingsDir)
$a=[Reflection.Assembly]::LoadFrom((Join-Path $stage 'SoMRandomizer.exe'))
$commonType=$a.GetType('SoMRandomizer.config.settings.CommonSettings',$true)
$openType=$a.GetType('SoMRandomizer.config.settings.OpenWorldSettings',$true)
$managerType=$a.GetType('SoMRandomizer.config.ui.UiOptionsManager',$true)
Add-Type -AssemblyName System.Windows.Forms
$uiSource=[IO.File]::ReadAllText((Join-Path $snapshot 'SoMRandomizer/forms/MainForm_UiOptionsInitialization.cs'))
function New-ProfileBindings([string[]]$Keys) {
 $common=[Activator]::CreateInstance($commonType); $settings=[Activator]::CreateInstance($openType,[object[]]@($common))
 $manager=[Activator]::CreateInstance($managerType); $controls=@{}
 foreach($key in $Keys) {
  $owner=if($common.hasSetting($key)) { $common } else { $settings }
  if($key -eq 'mode') {
   $control=[Windows.Forms.TabControl]::new()
   foreach($display in $common.getDisplayValues('mode')) { [void]$control.TabPages.Add($display) }
   $manager.addTabControl($control,$key,$owner)
  } else {
   $field=@($owner.GetType().GetFields()|Where-Object {$_.IsLiteral -and $_.Name.StartsWith('PROPERTYNAME_') -and $_.GetRawConstantValue() -eq $key})
   if($field.Count -eq 0 -or -not @($field|Where-Object {$uiSource.Contains($_.Name)}).Count) { throw ('Profile key is not registered in the real UI: '+$key) }
   try { $values=$owner.getOptionsValues($key) } catch { $values=$null }
   if($null -ne $values) {
    $control=[Windows.Forms.ComboBox]::new()
    foreach($display in $owner.getDisplayValues($key)) { [void]$control.Items.Add($display) }
    $manager.addComboBox($control,$key,$owner)
   } else {
    $control=[Windows.Forms.NumericUpDown]::new(); $manager.addNumericUpDown($control,$key,$owner)
   }
  }
  $controls[$key]=$control
 }
 return [pscustomobject]@{Common=$common;Settings=$settings;Manager=$manager;Controls=$controls}
}
$readme=@('# Unofficial Alpha 0.1 RC3 normal gameplay configurations','','Volunteer full-run coverage is pending; personal completion is not a prerequisite for joining the playtest. Paste the entire corresponding .options.txt line into the Open World options box.','Seed strings intentionally retain RC1 labels for exact comparison. These are RC3 package profiles, not RC1 binaries.','Files use the actual UI options serializer, with version=1.49 and mode=open; omitted options reset to this package''s defaults.','The exact source/build/hash fixes those default definitions; no plando, bootstrap or manual teleport is enabled.','All three options strings passed headless UI-binding save/load round trips, not a clean-machine visual UI test.','')
$resolved=@()
foreach($profile in $profiles) {
 $wanted=@{mode='open'}
 foreach($pair in $profile.Options.Split(' ')) { $at=$pair.IndexOf('='); $wanted[$pair.Substring(0,$at)]=$pair.Substring($at+1) }
 $keys=@($wanted.Keys|Sort-Object); $bindings=New-ProfileBindings $keys; $roundTrip=New-ProfileBindings $keys
 try {
  foreach($key in $keys) {
   $owner=if($bindings.Common.hasSetting($key)) { $bindings.Common } else { $bindings.Settings }
   $control=$bindings.Controls[$key]
   if($control -is [Windows.Forms.NumericUpDown]) { $control.Value=[decimal]::Parse($wanted[$key],[Globalization.CultureInfo]::InvariantCulture) }
   else { $control.SelectedIndex=$owner.getIndex($key,$wanted[$key]) }
  }
  $options=$bindings.Manager.getOptionsString()
  $roundTrip.Manager.setOptions($options)
  foreach($key in $keys) { if($roundTrip.Settings.get($key) -ne $wanted[$key]) { throw ('UI round trip mismatch: '+$profile.Name+'/'+$key) } }
  if($options -notmatch '^version=1\.49 ' -or $options -notmatch '(^| )mode=open( |$)' -or $options -match 'testOnly|debugLoggingEnabled|SourceROMName|TargetROMName') { throw 'Invalid UI starter serialization.' }
 } finally { foreach($binding in @($bindings,$roundTrip)) { foreach($control in $binding.Controls.Values) { $control.Dispose() } } }
 $options | Set-Content -LiteralPath (Join-Path $settingsDir ($profile.Name+'.options.txt')) -Encoding UTF8
 $readme+=@(('## '+$profile.Name),'',('Seed: `'+$profile.Seed+'`. Goal: '+$profile.Goal+'.'),'', $profile.Expectations,'',('Known limits: '+$profile.Limitations),'')
 $resolved += [pscustomobject]@{Name=$profile.Name;Seed=$profile.Seed;Goal=$profile.Goal;Options=$options;Expectations=$profile.Expectations;Limitations=$profile.Limitations}
 Write-Output ('PASS: real UI serializer and headless options round trip for '+$profile.Name)
}
$resolved | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $settingsDir 'Profiles.json') -Encoding UTF8
$readme | Set-Content -LiteralPath (Join-Path $settingsDir 'README.md') -Encoding UTF8
Write-Output ('Prepared package staging: '+$stage+'. Not zipped or approved until verification completes.')
