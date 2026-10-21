# Shared reflection fixtures; no production bootstrap, settings, or ROM writes.
$ErrorActionPreference='Stop'
$assembly=[Reflection.Assembly]::LoadFrom((Resolve-Path $AssemblyPath).Path)
function T([string]$Name) { return $assembly.GetType('SoMRandomizer.'+$Name,$true) }
function Assert-True([bool]$Value,[string]$Message) { if(-not $Value) { throw $Message } }
function Same($A,$B) { return [Linq.Enumerable]::SequenceEqual([byte[]]$A,[byte[]]$B) }
[byte[]]$original=[IO.File]::ReadAllBytes((Resolve-Path $SourceRom).Path)
$binding=[Reflection.BindingFlags]'Instance,NonPublic'
$maps=T 'processing.common.VanillaBossMaps'; $mapUtil=T 'processing.common.VanillaMapUtil'
function Apply([string]$Name,$Case) {
    $type=T $Name
    [void]$type.GetMethod('process',$binding).Invoke([Activator]::CreateInstance($type),@($original,$Case.Rom,'arena-stage1',$Case.Settings,$Case.Context))
}
function Native-Pins {
    return @{
        mantisAnt='Mantis-Ant';doppelgangers='Doppelgangers';wallFace='Wall-Face';tropicallo='Tropicallo';minotaur='Minotaur';
        spikeyTiger='Spikey-Tiger';jabberwocky='Jabberwocky';springBeak='Spring-Beak';frostGigas='Frost-Gigas';snapDragon='Snap-Dragon';
        mechRider1='Mech-Rider-1';doomsWall="Doom's-Wall";vampire='Vampire';metalMantis='Metal-Mantis';mechRider2='Mech-Rider-2';
        kilroy='Kilroy';gorgonBull='Gorgon-Bull';borealFace='Boreal-Face';greatViper='Great-Viper';limeSlime='Lime-Slime';
        blueSpike='Blue-Spike';hydra='Hydra';watermelon='Watermelon';hexas='Hexas';kettleKin='Kettle-Kin';tonpole='Tonpole';
        mechRider3='Mech-Rider-3';snowDragon='Snow-Dragon';fireGigas='Fire-Gigas';redDragon='Red-Dragon';axeBeak='Axe-Beak';
        blueDragon='Blue-Dragon';buffy='Buffy';darkLich='Dark-Lich';dragonWorm='Dragon-Worm';dreadSlime='Dread-Slime';
        thunderGigas='Thunder-Gigas';tripleTonpole='Triple-Tonpole'
    }
}
function New-Case([string]$Mode='random',$Pins=@{},[bool]$Pilot=$false) {
    $settings=[Activator]::CreateInstance((T 'config.settings.OpenWorldSettings'),[object[]]@([Activator]::CreateInstance((T 'config.settings.CommonSettings'))))
    $settings.set('opBosses',$Mode); $settings.set('crystalOrbWeaponBreaking','off')
    $context=[Activator]::CreateInstance((T 'processing.common.RandoContext'))
    $context.randomFunctional=[Random]::new(21377)
    $context.namesOfThings=[Activator]::CreateInstance((T 'processing.hacks.common.util.NamesOfThings'),[object[]]@(,$original))
    foreach($key in $Pins.Keys) { $context.plandoSettings['P_'+$key]=[Collections.Generic.List[string]]::new([string[]]@($Pins[$key])) }
    if($Pilot) { throw 'Historical manual pilot is not part of the release.' }
    [byte[]]$rom=[byte[]]::new(0x400000); [Array]::Copy($original,$rom,$original.Length)
    $context.originalRom=$original; $context.outputRom=$rom
    return [pscustomobject]@{Rom=$rom;Context=$context;Settings=$settings}
}
function Events($Case) {
    $wd=$Case.Context.workingData
    $wd.set('openWorldGoalShortName','manabeast'); $wd.setBool('fastManaFort',$true)
    $wd.setBool('anyMagicExists',$true); $wd.setInt('manaSeedsRequired',8)
    $wd.set('boyClass','OGboy'); $wd.set('girlClass','OGgirl'); $wd.set('spriteClass','OGsprite')
    $wd.setInt((T 'processing.ElementSwaps').GetField('ORBELEMENT_PREFIX').GetValue($null)+35,0x81)
    Apply 'processing.openworld.events.PrizeEvents' $Case
    Apply 'processing.openworld.events.OpenWorldSupportingEvents' $Case
}
function Read-Map($Rom,[string]$Method,[int]$Id) { return ,($mapUtil.GetMethod($Method).Invoke($null,@($Rom,$Id))) }
function Hash([byte[]]$Bytes) { return [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($Bytes)) }
