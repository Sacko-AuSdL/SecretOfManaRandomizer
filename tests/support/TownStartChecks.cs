using System;using System.Linq;using System.Collections.Generic;using System.Reflection;
using SoMRandomizer.processing;using SoMRandomizer.processing.common;using SoMRandomizer.processing.openworld;using SoMRandomizer.processing.openworld.cannon;using SoMRandomizer.processing.openworld.randomization;using SoMRandomizer.config.settings;
public sealed class TownStartTestGenerator:OpenWorldGenerator
{
 public static RandoContext Context;
 public TownStartTestGenerator(){var f=BindingFlags.Instance|BindingFlags.NonPublic;((List<RandoProcessor>)typeof(RomGenerator).GetField("commonHacks",f).GetValue(this)).RemoveAll(p=>p.GetType().Name=="WeaponPowerCalculator");}
 protected override void generate(byte[] o,byte[] r,string seed,RandoSettings s,RandoContext c){base.generate(o,r,seed,s,c);Context=c;}
}
public static class TownStartChecks
{
 static void Check(bool b,string s){if(!b)throw new Exception(s);}
 public static string Run(byte[] o,byte[] r,OpenWorldSettings s,RandoContext c)
 {
  var town=OpenWorldStartingLocation.getTown(s,c);Check(town!=null,"No selected town.");
  var d=VanillaDoorUtil.getDoor(r,0x82);Check(d.getTargetMap()==town.Map&&d.getXpos()==town.X&&d.getYpos()==town.Y&&!d.getLayer2Collision()&&d.getTransitionType()==0,"Cold startup door differs from selected town.");
  var h=VanillaMapUtil.getHeader(o,town.Map);int ts=o[VanillaMapUtil.getObjectOffset(o,town.Map)+2]&63;
  var bg=new byte[128,128];var fg=new byte[128,128];var refs=VanillaMapUtil.getMapPieceReference(o,town.Map);
  foreach(var p in refs.bgPieces)VanillaMapUtil.copyMapPieceData(VanillaMapUtil.loadVanillaMapPiece(o,p.pieceIndex),bg,p.xPos,p.yPos);
  foreach(var p in refs.fgPieces)VanillaMapUtil.copyMapPieceData(VanillaMapUtil.loadVanillaMapPiece(o,p.pieceIndex),fg,p.xPos,p.yPos);
  for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++){
   int x=town.X+dx,y=town.Y+dy,t=o[0xB0400+ts*384+bg[x,y]],f=o[0xB0400+ts*384+192+fg[x,y]];
   Check(o.Skip(0xB0000+t*4).Take(4).SequenceEqual(new byte[]{0x12,6,0,0})||o.Skip(0xB0000+t*4).Take(4).SequenceEqual(new byte[]{0x12,7,0,0}),"Spawn pocket not natural full floor.");
   Check(f==0||f==4,"Spawn pocket has foreground obstruction.");
  }
  foreach(var a in VanillaMapUtil.getObjects(o,town.Map))Check(Math.Abs(a.getXpos()-town.X)+Math.Abs(a.getYpos()-town.Y)>=5,"Spawn intersects native NPC.");
  // Trigger data is repacked globally by existing adapters; compare resolved
  // trigger contents below, while native piece-reference boundaries stay fixed.
  foreach(int table in new[]{0x85000})Check(r.Skip(table+town.Map*2).Take(4).SequenceEqual(o.Skip(table+town.Map*2).Take(4)),"Town geometry/exit pointers changed.");
  Check(VanillaMapUtil.getTriggers(r,town.Map).SequenceEqual(VanillaMapUtil.getTriggers(o,town.Map)),"Town entry/exit events changed.");
  foreach(int door in Enumerable.Range(0,1024).Where(i=>VanillaDoorUtil.getDoor(o,i).getTargetMap()==town.Map))Check(r.Skip(0x83000+door*4).Take(4).SequenceEqual(o.Skip(0x83000+door*4).Take(4)),"Native town door changed.");
  var intro=c.replacementEvents[0x106];Check(intro.Skip(intro.Count-5).SequenceEqual(new byte[]{0x21,7,0x11,3,0}),"Town music terminated initialization/Sword flow.");
  var sound=VanillaEventUtil.getVanillaEvent(o,town.MusicEvent).Take(5).ToArray();Check(Enumerable.Range(0,intro.Count-4).Any(i=>intro.Skip(i).Take(5).SequenceEqual(sound)),"Native town music missing.");
  var startup=c.replacementEvents[0x400];Check(Enumerable.Range(0,startup.Count-1).Any(i=>startup[i]==0x18&&startup[i+1]==0x82),"Second start/teleport mechanism introduced.");
  var sword=c.replacementEvents[0x103];Check(sword.Last()==0&&!sword.Skip(Math.Max(0,sword.Count-3)).SequenceEqual(new byte[]{0x18,0x83,0}),"Manual Sword teleport leaked into normal start.");
  int savedDoor=town.Map==228?0x191:0xB9;int[] save=DoppelgangerAutosaveChecks.Probe(r,savedDoor,100);Check(save[0]==1&&save[1]==savedDoor,"Ordinary town entry cannot autosave.");Check(DoppelgangerAutosaveChecks.LoadDoor(r,savedDoor,0x82)==savedDoor,"Town save continuation changed.");
  Check(OpenWorldStartingLocation.getStartingRegion(s,c)==town.Region,"Physical/logical starting regions differ.");
  return "PASS "+town.Id+" native map"+town.Map+" ("+town.X+","+town.Y+"): 3x3 natural floor/NPC clearance, existing start82/music/init/Sword, native doors/geometry and native autosave continuation. Movement/exit runtime still requires Mesen.";
 }
 public static string Logic(OpenWorldSettings s,RandoContext generated)
 {
  var c=new RandoContext();foreach(var key in generated.workingData.keysStartingWith(""))c.workingData.set(key,generated.workingData.get(key));
  s.set(OpenWorldSettings.PROPERTYNAME_ALLOW_MISSED_ITEMS,"no");s.set("cannonTravelRandomization","chaos");c.workingData.setInt("cannonTravelResolved",1);c.workingData.set("cannonTravelResolvedMode","chaos");
  foreach(var office in CannonTravelModel.OFFICES){c.workingData.setInt("cannonTravelRouteCount_"+office.Id,0);c.workingData.set("cannonTravelClosedMessage_"+office.Id,CannonTravelModel.CLOSED_OFFICE_MESSAGE);}
  var town=OpenWorldStartingLocation.getTown(s,c);var loc=OpenWorldLocations.getForSelectedOptions(s,c);var local=loc.Single(l=>l.locationName==(town.Map==228?"salamando":"mara (tower key)"));var remote=loc.Single(l=>l.locationName=="girl");
  var drum=new PrizeItem("flammie drum","test",new byte[0],"",0,1);var none=new PrizeItem("nothing","test",new byte[0],"",0,1);
  var p=new Dictionary<PrizeLocation,PrizeItem>{{local,none},{remote,drum}};var blocked=OpenWorldSimulator.runSimulation(p,s,c);Check(blocked.score<0&&!blocked.collectionCycles[0].Contains(remote.locationName),"Closed-network town start incorrectly credits Potos Drum.");
  p[local]=drum;p[remote]=none;var ok=OpenWorldSimulator.runSimulation(p,s,c);Check(ok.score>=0&&ok.collectionCycles[0].Contains(local.locationName),"Reachable local Drum does not rescue closed-network start.");
  return "PASS "+town.Id+" real simulator: all cannon offices closed, unreachable Potos Drum rejected and local Drum accepted; no free progression flags/items.";
 }
}
