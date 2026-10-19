param([string]$AssemblyPath=(Join-Path $PSScriptRoot '..\.codex-build\alpha-audit\out\SoMRandomizer.exe'))
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
$assembly=[Reflection.Assembly]::LoadFrom((Resolve-Path $AssemblyPath).Path)
$commonType=$assembly.GetType('SoMRandomizer.config.settings.CommonSettings',$true)
$openType=$assembly.GetType('SoMRandomizer.config.settings.OpenWorldSettings',$true)
$managerType=$assembly.GetType('SoMRandomizer.config.ui.UiOptionsManager',$true)
function Assert-True([bool]$Value,[string]$Message) { if(-not $Value) { throw $Message } }
# Exercise the actual options-string UI binding without showing a window.
$options=@{
 spellShuffle=@('off','perCharacter','party')
 crystalOrbWeaponBreaking=@('off','on','weaponOnly')
 cannonTravelRandomization=@('off','open','shuffle','chaos')
 freeCannonTravel=@('off','on')
 showUpperLandOrbRequirement=@('off','on')
 opStartingLocation=@('default','kakkara')
 weaponUpgradeCosts=@('vanilla','reduced')
 playerMagicDamage=@('vanilla','fixed','random')
 manaBeastAppearance=@('vanilla','superRabite')
}
$count=0
foreach($key in $options.Keys) {
 foreach($value in $options[$key]) {
  $sourceCommon=[Activator]::CreateInstance($commonType)
  $targetCommon=[Activator]::CreateInstance($commonType)
  $source=[Activator]::CreateInstance($openType,[object[]]@($sourceCommon))
  $target=[Activator]::CreateInstance($openType,[object[]]@($targetCommon))
  $sourceOwner=if($sourceCommon.hasSetting($key)) { $sourceCommon } else { $source }
  $targetOwner=if($targetCommon.hasSetting($key)) { $targetCommon } else { $target }
  Assert-True ($sourceOwner.getDefault($key) -eq $options[$key][0]) ("Unexpected default: $key")
  Assert-True (($sourceOwner.getOptionsValues($key) -join ',') -eq ($options[$key] -join ',')) ("Unexpected values: $key")
  $managers=@([Activator]::CreateInstance($managerType),[Activator]::CreateInstance($managerType))
  $controls=@([Windows.Forms.ComboBox]::new(),[Windows.Forms.ComboBox]::new())
  try {
   for($i=0;$i -lt 2;$i++) {
    $owner=@($sourceOwner,$targetOwner)[$i]
    foreach($display in $owner.getDisplayValues($key)) { [void]$controls[$i].Items.Add($display) }
    $managers[$i].addComboBox($controls[$i],$key,$owner)
   }
   $controls[0].SelectedIndex=$sourceOwner.getIndex($key,$value)
   $serialized=$managers[0].getOptionsString()
   $managers[1].setOptions($serialized)
   Assert-True ($target.get($key) -eq $value) ("Options round trip failed: $key=$value")
   Assert-True ($source.ToString().Contains($key+' = '+$value)) ("Diagnostic settings omitted $key")
   $count++
  } finally { foreach($control in $controls) { $control.Dispose() } }
 }
}
$s=[Activator]::CreateInstance($openType,[object[]]@([Activator]::CreateInstance($commonType)))
Assert-True ($s.get('playerMagicDamagePercent') -eq '40') 'Fixed magic damage default changed.'
Assert-True ($s.get('opStartLevel') -eq '1' -and $s.get('opStartGold') -eq '0') 'Manual profile leaked into defaults.'
Assert-True ($s.get('opAllWeaponOrbs') -eq 'no') 'Manual orbs leaked into defaults.'
Assert-True ($s.get('opFlammieDrumInLogic') -eq 'no') 'Upstream Flammie default unexpectedly changed.'
$ui=Get-Content (Join-Path $PSScriptRoot '..\SoMRandomizer\forms\MainForm_UiOptionsInitialization.cs') -Raw
foreach($field in @('SPELL_SHUFFLE','CRYSTAL_ORB_WEAPON_BREAKING','CANNON_TRAVEL_RANDOMIZATION','FREE_CANNON_TRAVEL','SHOW_UPPER_LAND_ORB_REQUIREMENT','STARTING_LOCATION','MANA_BEAST_APPEARANCE','WEAPON_UPGRADE_COSTS','PLAYER_MAGIC_DAMAGE')) {
 Assert-True ($ui.Contains('PROPERTYNAME_'+$field)) ("Missing UI registration: $field")
}
'PASS: '+$count+' actual UI-binding options round trips; release defaults, labels registration, settings diagnostics; no window shown.'
