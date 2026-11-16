using System;
using System.Linq;
using System.Collections.Generic;
using SoMRandomizer.config.settings;
using SoMRandomizer.processing.common;
using SoMRandomizer.processing.openworld;
using SoMRandomizer.processing.openworld.events;
using SoMRandomizer.processing.openworld.randomization;
// Native event commands, dialogue closure and packed SRAM flags; PPU DMA and
// the completed UI callback are explicit boundaries, not an emulator claim.
public static class MaraEmptyPrizeChecks
{
 static void Check(bool b,string s){if(!b)throw new Exception(s);}
 static int Long(byte[] r,int a){return r[a]|r[a+1]<<8|r[a+2]<<16;}
 static byte[] Template(PrizeItem p){return new byte[]{0x50}.Concat(p.eventData).Concat(new byte[]{0x28,0,0x51,0}).ToArray();}
 static byte[] Inject(PrizeItem p,string goal,int ev=0x399){
  var c=new RandoContext();c.workingData.set(OpenWorldGoalProcessor.GOAL_SHORT_NAME,goal);
  c.workingData.setInt(StartingWeaponRandomizer.BOY_START_WEAPON_INDEX,0);c.workingData.setInt(StartingWeaponRandomizer.GIRL_START_WEAPON_INDEX,1);c.workingData.setInt(StartingWeaponRandomizer.SPRITE_START_WEAPON_INDEX,2);
  var e=new List<byte>();PrizeEvents.injectReplacementPattern(e,0);e.Add(0);c.replacementEvents[ev]=e;
  c.replacementEvents[0x586]=new List<byte>{0x11,0,0};
  var settings=new OpenWorldSettings(new CommonSettings());if(goal==OpenWorldGoalProcessor.GOAL_GIFTMODE){settings.set(OpenWorldSettings.PROPERTYNAME_NUM_XMAS_GIFTS,"0");c.replacementEvents[0x106]=new List<byte>();c.workingData.set(OpenWorldLocationPrizeMatcher.GIFT_SELECTION_PREFIX+"0","candy");}
  OpenWorldResultInjector.injectRandomization(new byte[0x400000],new Dictionary<PrizeLocation,PrizeItem>{{new PrizeLocation("mara (tower key)",ev,0,new string[0],new string[0],1),p}},settings,c);
  Check(c.replacementEvents[0x586].SequenceEqual(new byte[]{0x11,0,0}),"Mara changed Nocturne.");return c.replacementEvents[ev].ToArray();
 }
 static byte[] Fixture(byte[] native,byte[] body){
  var r=(byte[])native.Clone();int table=Long(r,0x1E7A3)-0xC00000,at=table+0x399*3;
  r[at]=0;r[at+1]=0xFF;r[at+2]=0xFF;Array.Copy(body,0,r,0x3FFF00,body.Length);return r;
 }
 static bool LastAlready;
 static SpellShuffleMachine Play(byte[] r,int slot,byte[] flags){
  var m=new SpellShuffleMachine(r){P=0,DB=0x7E,A=0x399,ExecuteSpecialEventDispatch=true};
  if(flags!=null)Array.Copy(flags,0,m.Memory,0x7ECF00,256);
  m.Write(0x7E00D4,slot*512,2);m.Write(0x7E00D9,1<<slot,1);
  for(int i=0;i<3;i++){m.Write(0x7EE000+i*512,1,1);m.Write(0x7EE182+i*512,100,2);m.Write(0x7EE02C+i*512,i==slot?1:0,1);}
  LastAlready=false;int already=Long(r,Long(r,0x1E7A3)-0xC00000+0x396*3);
  m.Run(0xC1E76D);m.Write(0x7E1D14,0x48,2);m.Writes.Clear();
  for(int frame=0;frame<260;frame++){
   m.S=0x1FF;m.P=0x20;m.DB=0x7E;m.DP=0;m.Run(0xC1E8C7);
   if(m.Read(0x7E00D0,1)==0){int cursor=m.Read(0x7E00D1,2)|m.Read(0x7E00D3,1)<<16;LastAlready=cursor>=already&&cursor<already+40;Check(m.Read(0x7E0048,1)==0&&m.Read(0x7E1D00,1)==0&&m.Read(0x7EA170,1)==0&&m.Read(0x7E00F1,1)==0&&(m.Read(0x7E00D9,1)&128)==0,"Mara left event/menu/control locks.");return m;}
   m.S=0x1FF;m.P=0x20;m.Write(0x7E00CC,0x80,1);m.Write(0x7E1D04,m.Read(0x7E1D04,1)&~2,1);m.Run(0xC0012C);
   if((m.Read(0x7E1D04,1)&1)==0)m.Write(0x7E0048,0,1);
  }throw new Exception("Mara dialogue did not end: D0="+m.Read(0x7E00D0,1).ToString("X2"));
 }
 static byte[] Flags(SpellShuffleMachine m){return m.Memory.Skip(0x7ECF00).Take(256).ToArray();}
 static byte[] Saved(byte[] r,byte[] flags){
  var save=new SpellShuffleMachine(r){P=0x20,DB=0x7E,X=0,Y=0xCF00};Array.Copy(flags,0,save.Memory,0x7ECF00,256);save.Run(0xC756F6,true);
  var load=new SpellShuffleMachine(r){P=0x20,DB=0x7E,X=0,Y=0xCF00};for(int i=0;i<128;i++)load.Write(0x306000+i,save.Read(0x306000+i,1),1);load.Run(0xC7588B,true);return Flags(load);
 }
 public static string Run(byte[] generated){
  var empty=new PrizeItem("nothing","",VanillaEventUtil.getBytes("Oops no item").ToArray(),"nothing",0,0.1);
  var guarded=Inject(empty,"manabeast");Check(guarded.SequenceEqual(new byte[]{0x50,0x42,0x31,0x1F,0x13,0x96,0x30,0x31,1}.Concat(empty.eventData).Concat(new byte[]{0x28,0,0x51,0})),"Wrong empty-event guard.");
  var original=Fixture(generated,Template(empty));var fixedRom=Fixture(generated,guarded);var zero=new byte[256];zero[0x30]=7;
  // Negative control: repeated original empty events never set a collection flag.
  var old=Play(original,1,zero);var oldAgain=Play(original,1,Flags(old));Check(!old.Writes.Contains(0x7ECF31)&&!oldAgain.Writes.Contains(0x7ECF31),"Original failure not reproduced.");
  for(int slot=0;slot<3;slot++){
   var first=Play(fixedRom,slot,zero);Check(first.Read(0x7ECF31,1)==1&&first.Read(0x7ECF30,1)==7&&first.Read(0x7ECF37,1)==0,"Empty check invented or lost progression.");
   var loaded=Saved(fixedRom,Flags(first));Check(loaded[0x31]==1&&loaded[0x30]==7,"Native save lost Mara flag.");
   var again=Play(fixedRom,slot,loaded);Check(LastAlready&&!again.Writes.Contains(0x7ECF31),"Collected empty prize ran twice.");
   int table=Long(fixedRom,0x1E7A3)-0xC00000;Check(again.Visits.Contains(0xC1E8F1),"Native repeat event not executed.");
   Check(again.Read(0x7ECF31,1)==1&&again.Read(0x7ECF37,1)==0,"Repeat awarded a real item.");
  }
  var real=new PrizeItem("gold key","",new byte[]{0x42,0x37,0x1F,0x13,0x96,0x30,0x37,1}.Concat(VanillaEventUtil.getBytes("Got the Gold Key")).ToArray(),"gold key",0x37,1);
  Check(Inject(real,"manabeast").SequenceEqual(Template(real)),"Genuine Mara reward changed.");
  var realRom=Fixture(generated,Inject(real,"manabeast"));var got=Play(realRom,1,null);Check(got.Read(0x7ECF37,1)==1&&got.Read(0x7ECF31,1)==0,"Real prize lost or used empty flag.");var repeat=Play(realRom,1,Saved(realRom,Flags(got)));Check(!repeat.Writes.Contains(0x7ECF37),"Real prize repeated after load.");
  Check(Inject(empty,"manabeast",0x398).SequenceEqual(Template(empty)),"Other empty location changed.");
  foreach(string goal in new[]{OpenWorldGoalProcessor.GOAL_GIFTMODE,OpenWorldGoalProcessor.GOAL_REINDEER})Check(Inject(empty,goal).SequenceEqual(Template(empty)),"Christmas flag ownership changed.");
  var objects=VanillaMapUtil.getObjects(generated,114);Check(objects[1].getEventVisFlag()!=0x31&&objects[2].getEventVisFlag()!=0x31,"Retired flag still controls Southtown NPC visibility.");
  Check(!EventFlags.OPENWORLD_ORB_FLAGS.Contains((byte)0x31)&&!EventFlags.OPENWORLD_GOLD_FLAGS.Contains((byte)0x31),"Mara flag overlaps prize pool.");
  return "PASS actual injector empty-only guard; native first/repeat dialogue END and controls for all physical slots; native packed save/load; genuine reward exactly once; Mara30/GoldKey37/Nocturne/other locations/Christmas unchanged; retired Southtown visibility ownership verified. PPU DMA/callback remain explicit boundaries.";
 }
}
