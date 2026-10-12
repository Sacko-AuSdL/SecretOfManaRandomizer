using System;
using System.Linq;
using System.Collections.Generic;
using System.Reflection;
using SoMRandomizer.config.settings;
using SoMRandomizer.processing;
using SoMRandomizer.processing.common;
using SoMRandomizer.processing.hacks.common.util;
using SoMRandomizer.processing.hacks.openworld;
using SoMRandomizer.processing.openworld;
using SoMRandomizer.processing.openworld.randomization;
using SoMRandomizer.util.rng;

public static class PartySpellShuffleTests
{
    private static int count;
    private static readonly string[] Slots={"boy","girl","sprite"};
    private static void Check(bool value,string message) { count++; if(!value) throw new Exception(message); }
    private static OpenWorldSettings Settings(string mode="party") {
        var common=new CommonSettings(); common.set("mode","open");
        var s=new OpenWorldSettings(common); s.set("spellShuffle",mode); return s;
    }
    private static RandoContext Context(int seed,string[] roles,bool[] exists=null) {
        var c=new RandoContext(); c.randomFunctional=new DotNet110Random(seed);
        for(int i=0;i<3;i++) { c.workingData.set(Slots[i]+"Class",roles[i]); c.workingData.setBool(Slots[i]+"Exists",exists==null || exists[i]); }
        return c;
    }
    private static byte[] Copy(byte[] native) { var rom=new byte[0x400000]; Array.Copy(native,rom,native.Length); return rom; }
    private static void Apply(RandoProcessor p,byte[] native,byte[] rom,OpenWorldSettings s,RandoContext c) {
        p.GetType().GetMethod("process",BindingFlags.Instance|BindingFlags.NonPublic).Invoke(p,new object[] {native,rom,"party-test",s,c});
    }
    private static int[] Pool(RandoContext c,bool assigned) {
        return Enumerable.Range(0,3).Where(i=>SpellShuffleAssignments.getRow(c,i)!=null)
            .SelectMany(i=>SpellShuffleAssignments.getShuffleableSpellIds(c.workingData.get(Slots[i]+"Class"))
                .Select(id=>assigned ? SpellShuffleAssignments.getRow(c,i)[id] : id)).OrderBy(id=>id).ToArray();
    }
    // Relocate existing INSTANCES while retaining every other position/multiplicity.
    public static void Place(RandoContext c,int slot,int destination,int actual) {
        int[][] rows=Enumerable.Range(0,3).Select(i=>SpellShuffleAssignments.getRow(c,i)).ToArray();
        if(rows[slot][destination]==actual) return;
        for(int owner=0;owner<3;owner++) if(rows[owner]!=null)
            foreach(int id in SpellShuffleAssignments.getShuffleableSpellIds(c.workingData.get(Slots[owner]+"Class")))
                if(rows[owner][id]==actual && !(owner==slot && id==destination)) {
                    // Already placed identical entries must not be pulled back out.
                    if(locked.Contains(owner*64+id)) continue;
                    rows[owner][id]=rows[slot][destination]; rows[slot][destination]=actual;
                    for(int i=0;i<3;i++) if(rows[i]!=null) c.workingData.setIntArray(SpellShuffleAssignments.ROW_PREFIX+i,rows[i]);
                    return;
                }
        throw new Exception("Missing spell instance "+actual);
    }
    private static readonly HashSet<int> locked=new HashSet<int>();
    private static void Force(RandoContext c,int slot,int dest,int actual) { Place(c,slot,dest,actual); locked.Add(slot*64+dest); }
    private static SpellShuffleMachine Machine(byte[] rom) {
        var m=new SpellShuffleMachine(rom);
        for(int slot=0;slot<3;slot++) for(int spirit=0;spirit<8;spirit++) m.Write(0x7EE1C8+slot*512+spirit,0x3F,1);
        return m;
    }
    public static string Run(byte[] native) {
        count=0; locked.Clear(); var s=Settings();
        Check(s.getDefault("spellShuffle")=="off" && s.getOptionsValues("spellShuffle").SequenceEqual(new[] {"off","perCharacter","party"}),"Setting compatibility changed.");
        foreach(string mode in new[] {"off","perCharacter","party"}) {
            var restored=Settings("off"); restored.processNewSettings(new SoMRandomizer.config.PropertyFileReader()
                .readByteArray(System.Text.Encoding.UTF8.GetBytes("spellShuffle="+mode+"\n")));
            Check(restored.get("spellShuffle")==mode,"Serialized spellShuffle value no longer loads: "+mode);
        }
        var names=new NamesOfThings(native);
        int freeze=Enumerable.Range(0,42).Single(id=>names.getOriginalName(id).Trim().Equals("FREEZE",StringComparison.OrdinalIgnoreCase));
        Check(freeze==6,"Authoritative Freeze/Frostwelle ID is not $06.");
        foreach(string[] roles in new[] {
            new[] {"OGboy","OGgirl","OGsprite"},new[] {"OGgirl","OGgirl","OGsprite"},
            new[] {"OGsprite","OGsprite","OGsprite"},new[] {"OGgirl","OGgirl","OGgirl"},
            new[] {"OGboy","OGsprite","OGsprite"},new[] {"OGboy","OGboy","OGgirl"},new[] {"OGboy","OGboy","OGboy"} }) {
            var a=Context(445566,roles); var b=Context(445566,roles);
            SpellShuffleAssignments.resolveAndStore(s,a,native); SpellShuffleAssignments.resolveAndStore(s,b,native);
            Check(Pool(a,false).SequenceEqual(Pool(a,true)),"Party multiset changed for "+string.Join(",",roles));
            Check(Pool(a,true).Length==20*roles.Count(role=>role!="OGboy"),"Wrong participant/pool count.");
            for(int slot=0;slot<3;slot++) {
                int[] row=SpellShuffleAssignments.getRow(a,slot), other=SpellShuffleAssignments.getRow(b,slot);
                if(roles[slot]=="OGboy") { Check(row==null && other==null,"Noncaster participated."); continue; }
                Check(row.SequenceEqual(other),"Party determinism failed.");
                Check(row[32]==32 && row[35]==35,"Mana Magic moved/lost.");
            }
            SpellShuffleAssignments.resolveAndStore(s,a,native);
            Check(a.randomFunctional.Next()==b.randomFunctional.Next(),"Cached Party resolver consumes RNG.");
            // Frozen legacy algorithm: adding Party must not change existing Per Character rolls.
            var legacy=Context(445566,roles); SpellShuffleAssignments.resolveAndStore(Settings("perCharacter"),legacy,native);
            var rng=new DotNet110Random(445566);
            for(int slot=0;slot<3;slot++) if(roles[slot]!="OGboy") {
                int[] dest=SpellShuffleAssignments.getShuffleableSpellIds(roles[slot]); int[] values=(int[])dest.Clone();
                for(int i=values.Length-1;i>0;i--) { int j=rng.Next()%(i+1); int temp=values[i]; values[i]=values[j]; values[j]=temp; }
                Check(dest.Select(id=>SpellShuffleAssignments.getRow(legacy,slot)[id]).SequenceEqual(values),"Per Character seed changed.");
            }
            Check(legacy.randomFunctional.Next()==rng.Next(),"Per Character RNG changed.");
        }
        var absent=Context(4,new[] {"OGgirl","OGsprite","OGsprite"},new[] {true,false,true});
        SpellShuffleAssignments.resolveAndStore(s,absent,native);
        Check(SpellShuffleAssignments.getRow(absent,1)==null && Pool(absent,true).Length==40,"Absent actor contributed spells.");

        var triple=Context(112233,new[] {"OGsprite","OGsprite","OGsprite"});
        SpellShuffleAssignments.resolveAndStore(s,triple,native);
        Force(triple,2,0,freeze); Force(triple,2,1,freeze); Force(triple,2,2,freeze);
        Check(Pool(triple,false).SequenceEqual(Pool(triple,true)),"Forced Triple Freeze created/lost instances.");
        Check(SpellShuffleAssignments.getShuffleableSpellIds("OGsprite").Count(id=>SpellShuffleAssignments.getRow(triple,2)[id]==freeze)==3,"Three Freeze copies not on one physical caster.");
        var rom=Copy(native); Apply(new CharacterClasses(),native,rom,s,triple);
        int start=triple.workingOffset; byte[] before=(byte[])rom.Clone(); Apply(new SpellShuffle(),native,rom,s,triple);
        Check(triple.workingOffset<start+8192,"Party allocation exceeds reserved bank space.");
        for(int i=0;i<rom.Length;i++) if(rom[i]!=before[i]) Check(i>=start && i<triple.workingOffset ||
            new[] {0x10CEB2,0x10D074,0x10D080,0x10D089,0x3FAA,0xBC14,0x8E8A0}.Any(at=>i>=at && i<at+(at==0x10D089 || at==0x8E8A0?7:at==0x3FAA || at==0x10CEB2?6:4)),"Party changed unrelated ROM "+i.ToString("X6"));
        foreach(int dest in new[] {0,1,2}) Menu(triple,rom,native,2,dest);
        // Only the third learned position is present: union masks retain independent slots.
        var sparse=Machine(rom); sparse.Write(0x7EE1C8+0x400,4,1);
        Hit(sparse,triple,2,0x600,freeze,0); CheckOrb(sparse,triple,0x81,true);
        Hit(sparse,triple,2,0x600,freeze,1); CheckOrb(sparse,triple,0x81,false); // Freeze not in Undine on this caster
        sparse.Write(0x7EE1C8+0x400,0,1); Hit(sparse,triple,2,0x600,freeze,0); CheckOrb(sparse,triple,0x81,false);
        sparse.Write(0x7EE1C8+0x400,7,1); Hit(sparse,triple,2,0x600,freeze,0); CheckOrb(sparse,triple,0x83,false);
        Check(sparse.Read(CustomRamOffsets.SPELL_SHUFFLE_ORB_CONTEXT+24,1)==0,"Wrong family did not consume one-shot record.");
        foreach(int source in new[] {8,255}) { Hit(sparse,triple,2,0x600,freeze,source); CheckOrb(sparse,triple,0x81,false); }
        Hit(sparse,triple,2,0x600,freeze,0); sparse.Write(0x7E00DC,35,2); CheckOrb(sparse,triple,0x81,false);
        SaveLoad(triple,rom,freeze);
        NativeOrbDispatch(triple,rom,freeze);
        locked.Clear(); var spirits=Context(112233,new[] {"OGsprite","OGsprite","OGsprite"});
        SpellShuffleAssignments.resolveAndStore(s,spirits,native);
        Force(spirits,2,0,freeze); Force(spirits,2,1,freeze); Force(spirits,2,6,freeze);
        var spiritRom=Copy(native); Apply(new CharacterClasses(),native,spiritRom,s,spirits); Apply(new SpellShuffle(),native,spiritRom,s,spirits);
        var overlap=Machine(spiritRom);
        Hit(overlap,spirits,2,0x600,freeze,0); Hit(overlap,spirits,2,0x800,freeze,1);
        Check(overlap.Read(CustomRamOffsets.SPELL_SHUFFLE_ORB_CONTEXT+25,1)==0x81 &&
            overlap.Read(CustomRamOffsets.SPELL_SHUFFLE_ORB_CONTEXT+33,1)==0x82,
            "Same actual spell in two spirits overwrote per-target source identity.");
        CheckOrb(overlap,spirits,0x82,true);
        overlap.Write(0x7E00D4,0x600,2); CheckOrb(overlap,spirits,0x81,true);
        Hit(overlap,spirits,2,0x600,freeze,1); CheckOrb(overlap,spirits,0x81,false);
        Hit(overlap,spirits,2,0x600,freeze,1); CheckOrb(overlap,spirits,0x82,true);
        Check(!spirits.replacementEvents.ContainsKey(0x42D),"Party changed Thanatos Mana Magic unlock.");

        locked.Clear(); var cross=Context(223344,new[] {"OGboy","OGgirl","OGsprite"});
        SpellShuffleAssignments.resolveAndStore(s,cross,native);
        Force(cross,1,3,12); // Girl Gnome Fireball (Sprite native)
        Force(cross,2,0,11); // Sprite Gnome Cure Water (Girl native)
        Force(cross,2,1,4);  // Sprite Gnome Speed Up (Girl native)
        Force(cross,2,2,5);  // Sprite Gnome Defender: entire Gnome menu is support-only
        Force(cross,1,9,6);  // Girl Undine Freeze
        Check(Pool(cross,false).SequenceEqual(Pool(cross,true)),"Cross-role redistribution changed multiset.");
        var mixed=Copy(native); Apply(new CharacterClasses(),native,mixed,s,cross); Apply(new SpellShuffle(),native,mixed,s,cross);
        foreach(int slot in new[] {1,2}) foreach(int dest in SpellShuffleAssignments.getRoleSpellIds(slot==1?"OGgirl":"OGsprite")) Menu(cross,mixed,native,slot,dest);
        NativeEffects(mixed);
        var offense=Machine(mixed); Hit(offense,cross,1,0x600,12,0); CheckOrb(offense,cross,0x81,true);
        var support=Machine(mixed); Hit(support,cross,2,0x600,11,0); CheckOrb(support,cross,0x81,false);
        Hit(support,cross,2,0x600,4,0); CheckOrb(support,cross,0x81,false);
        Check(SpellShuffleAssignments.getOrbCasters(cross,0x81).Contains("girl"),"Girl's crossed offensive spell ignored by logic.");
        // Every family follows real assigned targeting and actual physical caster ownership.
        foreach(int family in Enumerable.Range(0x81,8)) foreach(int slot in new[] {1,2}) {
            int[] row=SpellShuffleAssignments.getRow(cross,slot);
            bool eligible=SpellShuffleAssignments.getShuffleableSpellIds(slot==1?"OGgirl":"OGsprite").Any(dest=>
                SpellShuffleAssignments.getSpiritFamily(dest)==family && (native[0x102AD8+row[dest]*64]&128)!=0);
            Check(SpellShuffleAssignments.getOrbCasters(cross,(byte)family).Contains(Slots[slot])==eligible,"Party Orb caster availability wrong.");
        }
        var flags=typeof(OpenWorldSimulator).GetMethod("haveRequirementWithAssignments",BindingFlags.NonPublic|BindingFlags.Static);
        foreach(string[] owned in new[] {new[] {"gnome spells"},new[] {"sprite","gnome spells"},new[] {"girl","gnome spells"}})
            Check((bool)flags.Invoke(null,new object[] {"gnome spells",owned.ToList(),new List<string>(),new List<string>(),new List<string>(),new List<string>(),cross})==owned.Contains("girl"),"Logic ignores actual joined crossed caster.");
        return "PASS: "+count+" Party multiset/duplicate/cross-role/runtime/save-load assertions; Freeze ID $06.";
    }
    private static void NativeOrbDispatch(RandoContext c,byte[] rom,int freeze) {
        var m=Machine(rom); m.ExecuteSpecialEventDispatch=true;
        m.X=0x600; m.Y=0x400; m.P=0x21; m.DB=0xC8; m.DP=0x120;
        m.Write(0x7EE7FB,0x10,1); m.Write(0x7EE600,2,1); m.Write(0x7EE7E7,0x55,1);
        m.Write(0x7EE570,freeze,1); m.Write(0x7EE577,0,1); m.Write(0x7EE63E,0x239,2); m.Write(0x7E00DC,291,2);
        m.Run(0xC03F94);
        Check(m.LastSpecialEvent==0x239 && m.EventStarts==1 && m.LastEventOwner==0x600,"Party lost Fix2 native event-target binding.");
        int offset=c.workingOffset; c.eventHackMgr.process(rom,ref offset);
        var ev=c.replacementEvents[0x350];
        m.Write(0x7E1000,0x57|(ev[5]<<8),2); m.Write(0x7E00D1,0x1000,2); m.Write(0x7E00D3,0x7E,1);
        m.P=0x10; m.DP=0; m.DB=0x7E; m.Stops.Add(0xC1E8D3); m.Stops.Add(0xC1F27A);
        m.Run(0xC1E8F1);
        Check(m.PC==0xC1E8D3 && m.Read(0x7ECF98,1)==1 && m.Read(CustomRamOffsets.SPELL_SHUFFLE_ORB_CONTEXT+24,1)==0,
            "Party native custom command opened text, failed, or retained its one-shot context.");
    }
    private static void NativeEffects(byte[] rom) {
        foreach(int slot in new[] {0,1,2}) foreach(int actual in new[] {4,6,11,12}) {
            var m=Machine(rom); m.EmulateMathHardware=true; m.FixedRandom=0;
            int caster=slot*512, target=actual==4 || actual==11 ? (slot+1)%3*512 : 0x600;
            m.P=0x20; m.DP=0x300; m.Y=caster; m.X=target;
            m.Write(0x7E0383,caster,2); m.Write(0x7E0385,target,2);
            m.Write(0x7EE170+caster,actual,1); m.Write(0x7EE177+caster,0,1);
            m.Write(0x7EE176+caster,1,1); m.Write(0x7EE1FB+caster,0x80,1);
            m.Write(0x7EE18B+caster,40,1); m.Write(0x7EE18C+caster,60,1);
            m.Write(0x7EE1FD+caster,12,1); m.Write(0x7EE1FE+caster,24,1);
            m.Write(0x7E039D,6,1);
            m.Write(0x7E03DC,actual*64,2); m.Write(0x7E03DE,0xD0,1);
            m.Run(0xC8E855,true);
            Check(m.Read(0x7E0391,1)==(actual%6<3?40:60),"Native magic power chose another caster/archetype.");
            int handler=rom[0x8E801+actual*2]|rom[0x8E802+actual*2]<<8;
            Check(handler==(actual==11?0xEBB3:actual==4?0xEB04:0xEA8B),"Native effect ID dispatch changed.");
            if(actual==11 || actual==4) {
                m.Run(0xC80000+handler,true);
                Check(actual==11 ? m.Read(0x7EE1F3+target,2)>0 : (m.Read(0x7EE1B0+target,1)&0x3C)==0x14,
                    "Native crossed Cure Water/Speed Up effect failed.");
                Check(m.S==0x1FF,"Native support effect left an unbalanced stack.");
            }
        }
    }
    private static void Menu(RandoContext c,byte[] rom,byte[] native,int slot,int dest) {
        var m=Machine(rom); int actual=SpellShuffleAssignments.getRow(c,slot)[dest];
        int source=SpellShuffleAssignments.getSpiritIndex(dest); bool girl=c.workingData.get(Slots[slot]+"Class")=="OGgirl";
        if(girl) m.Write(0x7EE1CE+slot*512,0,1);
        m.Write(0x7E1808,slot,1); m.Write(girl?0x7E1874:0x7E1875,girl && source==7?6:source,1);
        m.Write(0x7E1878+source,girl ? (dest%6-3)<<4 : dest%6,1); m.Run(0xD0CE5D);
        Check(m.Read(0x7E1839,1)==actual && m.Read(0x7E1846,1)==source,"Menu lost duplicate/cross-role position/source: slot "+slot+" dest "+dest+" expected "+actual+"/"+source+" got "+m.Read(0x7E1839,1)+"/"+m.Read(0x7E1846,1));
        Check(m.Read(0x7E1843,1)==native[0x102ADF+actual*64] && m.Read(0x7E1842,1)==native[0x102AD8+actual*64],"Actual MP/targeting changed.");
        m.P=0; m.Write(0x7E184F,dest,1); m.Run(c.workingData.getInt(SpellShuffle.ICON_ROUTINE));
        Check(m.A==m.Read(0xD8FD7E+actual*2,2),"Actual icon changed.");
        m.Write(0x7E1803,0x80,2); m.Run(0xD0D4DF,true);
        Check(m.Read(0x7E19D2,1)==0x56 && m.Read(0x7E19D3,1)==actual,"Actual spell-name ID changed.");
        m.Write(0x7EE186+slot*512,m.Read(0x7E1843,1),1); m.Write(0x7E1844,0x1A00,2); m.Run(0xC073AC);
        Check((m.P&1)!=0,"Cross-role spell MP affordability uses wrong actor.");
        m.Write(0x7E1822,0x200,2); m.Write(0x7E0201,0,1); m.Run(0xC0731F,true);
        Check(m.Read(0x7E19F0,1)==actual && m.Read(0x7E19F7,1)==source,"Queue overwrote source with effect's native element.");
    }
    private static void Hit(SpellShuffleMachine m,RandoContext c,int slot,int target,int actual,int source) {
        m.P=0x20; m.DB=0x7E; m.DP=0x300; m.X=slot*512; m.Y=target; m.A=0x410;
        m.Write(0x7E00D0,0,1); m.Write(0x7E00DC,291,2); m.Write(0x7EE000+target,2,1);
        m.Write(0x7EE1E7+target,0x55,1); m.Write(0x7EE170+slot*512,actual,1); m.Write(0x7EE177+slot*512,source,1);
        // Unrelated menu owner/source may change while the original effect resolves.
        m.Write(0x7E1808,(slot+1)%3,1); m.Write(0x7E1846,7,1);
        m.Run(c.workingData.getInt(SpellShuffle.CAPTURE_ROUTINE));
        Check(m.X==slot*512 && m.Y==target && m.A==(0x400|actual) && m.S==0x1FF,"Party capture damaged registers/stack.");
    }
    private static void CheckOrb(SpellShuffleMachine m,RandoContext c,int family,bool success) {
        int flag=Array.IndexOf(new[] {0x81,0x82,0x85,0x83,0x84,0x86,0x87,0x88},family)+0x98;
        m.P=0xA1; m.DB=0xC8; m.X=0x1234; m.Y=0x5678; m.A=0x9876;
        m.Run(c.workingData.getInt(SpellShuffle.CHECKER_PREFIX+family));
        Check(m.Read(0x7ECF00+flag,1)==(success?1:0),"Party Orb source/result wrong.");
        Check(m.S==0x1FF && m.DB==0xC8 && m.P==0xA1 && m.A==0x9876 && m.X==0x1234 && m.Y==0x5678,"Party checker corrupted caller.");
    }
    private static void SaveLoad(RandoContext c,byte[] rom,int freeze) {
        var save=Machine(rom); save.Write(0x7EE5C8,4,1); save.Write(0x7EE5C4,0x60,1); save.Write(0x7EE5D8,42,1);
        Hit(save,c,2,0x600,freeze,0); // transient context must NOT persist in save data
        for(int slot=0;slot<3;slot++) { save.P=0x20; save.DB=0x7E; save.X=0x103+slot*128; save.Y=0xE180+slot*512; save.Run(0xC756E1,true); }
        var load=new SpellShuffleMachine(rom); Array.Copy(save.Memory,0x306000,load.Memory,0x306000,0x2000);
        for(int slot=0;slot<3;slot++) { load.P=0x20; load.DB=0x7E; load.X=0x103+slot*128; load.Y=0xE180+slot*512; load.Run(0xC7587A,true); }
        load.Run(c.workingData.getInt(SpellShuffle.CLEAR_ROUTINE));
        Check(load.Read(0x7EE5C8,1)==4 && load.Read(0x7EE5C4,1)==0x60 && load.Read(0x7EE5D8,1)==42,"Native SRAM copy lost learned/level/EXP fields.");
        Check(Enumerable.Range(0,96).All(i=>load.Read(CustomRamOffsets.SPELL_SHUFFLE_ORB_CONTEXT+i,1)==0),"Load/map transition retained transient Orb context.");
        Hit(load,c,2,0x600,freeze,0); CheckOrb(load,c,0x81,true);
        load.P=0x20; load.DB=0x7E; load.DP=0x300; load.Y=0x400; load.Write(0x7E0383,0x400,2); load.Write(0x7EE5FB,0x80,1);
        load.Run(0xD04E6E,true);
        Check(load.Read(0x7E039D,1)==6 && load.Read(0x7E039E,1)==42,"Duplicate Freeze lost source Gnome level after load.");
    }
}
