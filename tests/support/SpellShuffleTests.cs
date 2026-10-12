using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using SoMRandomizer.config.settings;
using SoMRandomizer.processing;
using SoMRandomizer.processing.common;
using SoMRandomizer.processing.hacks.openworld;
using SoMRandomizer.processing.openworld;
using SoMRandomizer.processing.openworld.randomization;
using SoMRandomizer.util.rng;

public static class SpellShuffleTests
{
    private static int assertions;
    private static void Check(bool value,string message)
    { assertions++; if(!value) throw new Exception(message); }
    private static bool Apply(RandoProcessor processor,byte[] native,byte[] output,OpenWorldSettings settings,RandoContext context)
    {
        return (bool)processor.GetType().GetMethod("process",BindingFlags.Instance|BindingFlags.NonPublic)
            .Invoke(processor,new object[] {native,output,"spell-test",settings,context});
    }
    private static OpenWorldSettings Settings(string mode="perCharacter")
    {
        var common=new CommonSettings(); common.set("mode","open");
        var settings=new OpenWorldSettings(common); settings.set("spellShuffle",mode); return settings;
    }
    private static RandoContext Context(int seed,string[] roles,bool[] exists=null)
    {
        var c=new RandoContext(); c.randomFunctional=new DotNet110Random(seed);
        for(int i=0;i<3;i++)
        {
            string slot=new[] {"boy","girl","sprite"}[i];
            c.workingData.set(slot+"Class",roles[i]);
            c.workingData.setBool(slot+"Exists",exists==null || exists[i]);
        }
        c.workingData.setBool("girlMagicExists",Enumerable.Range(0,3).Any(i=>roles[i]=="OGgirl" && (exists==null || exists[i])));
        c.workingData.setBool("spriteMagicExists",Enumerable.Range(0,3).Any(i=>roles[i]=="OGsprite" && (exists==null || exists[i])));
        return c;
    }
    private static byte[] Copy(byte[] native) { var r=new byte[0x400000]; Array.Copy(native,r,native.Length); return r; }
    private static int Address(byte[] rom,int at) { return rom[at+1]|rom[at+2]<<8|rom[at+3]<<16; }
    private static void Force(RandoContext c,int slot,int destination,int actual)
    {
        int[] row=SpellShuffleAssignments.getRow(c,slot); int other=Array.IndexOf(row,actual);
        int old=row[destination]; row[destination]=actual; row[other]=old;
        c.workingData.setIntArray(SpellShuffleAssignments.ROW_PREFIX+slot,row);
    }
    public static string Run(byte[] native)
    {
        assertions=0; var settings=Settings();
        Check(settings.getDefault("spellShuffle")=="off","Default must be off.");
        Check(settings.getOptionsValues("spellShuffle").SequenceEqual(new[] {"off","perCharacter","party"}),"Unexpected setting values/compatibility.");
        var off=Settings("off"); var offCtx=Context(123,new[] {"OGboy","OGgirl","OGsprite"});
        var offRom=Copy(native); var before=(byte[])offRom.Clone();
        Check(!Apply(new SpellShuffleAssignments(),native,offRom,off,offCtx),"Off assignments active.");
        Check(!Apply(new SpellShuffle(),native,offRom,off,offCtx),"Off runtime active.");
        Check(offRom.SequenceEqual(before) && offCtx.workingOffset==0x200000,"Off changes ROM/allocation.");
        Check(offCtx.randomFunctional.Next()==new DotNet110Random(123).Next(),"Off consumes RNG.");
        off.set("mode","rando"); off.set("spellShuffle","perCharacter");
        Check(!Apply(new SpellShuffleAssignments(),native,offRom,off,offCtx),"Vanilla Rando modified.");

        foreach(string[] roles in new[] {
            new[] {"OGsprite","OGsprite","OGsprite"}, new[] {"OGgirl","OGgirl","OGgirl"},
            new[] {"OGboy","OGgirl","OGsprite"}, new[] {"OGgirl","OGgirl","OGsprite"} })
        {
            var a=Context(445566,roles); var b=Context(445566,roles);
            SpellShuffleAssignments.resolveAndStore(settings,a,native); SpellShuffleAssignments.resolveAndStore(settings,b,native);
            for(int slot=0;slot<3;slot++)
            {
                int[] row=SpellShuffleAssignments.getRow(a,slot), other=SpellShuffleAssignments.getRow(b,slot);
                if(roles[slot]=="OGboy") { Check(row==null,"Boy acquired spells."); continue; }
                Check(row.SequenceEqual(other),"Determinism failed.");
                int[] pool=SpellShuffleAssignments.getRoleSpellIds(roles[slot]);
                Check(pool.OrderBy(v=>v).SequenceEqual(pool.Select(id=>row[id]).OrderBy(v=>v)),"Spell instances lost/duplicated/cross-role.");
                Check(row[roles[slot]=="OGgirl"?0x23:0x20]==(roles[slot]=="OGgirl"?0x23:0x20),"Mana Magic moved.");
                Check(Enumerable.Range(0,42).Where(i=>!pool.Contains(i)).All(i=>row[i]==i),"Other role's slots modified.");
            }
            if(roles.Distinct().Count()==1)
                Check(!SpellShuffleAssignments.getRow(a,0).SequenceEqual(SpellShuffleAssignments.getRow(a,1)) &&
                    !SpellShuffleAssignments.getRow(a,1).SequenceEqual(SpellShuffleAssignments.getRow(a,2)),"Duplicate roles share a layout.");
            SpellShuffleAssignments.resolveAndStore(settings,a,native);
            Check(a.randomFunctional.Next()==b.randomFunctional.Next(),"Cached resolver reshuffles/consumes RNG.");
        }
        var absent=Context(33,new[] {"OGboy","OGgirl","OGsprite"},new[] {true,false,true});
        SpellShuffleAssignments.resolveAndStore(settings,absent,native);
        Check(SpellShuffleAssignments.getRow(absent,1)==null && SpellShuffleAssignments.getRow(absent,2)!=null,"Absent/findable handling wrong.");

        // Three independent Sprite rows, plus a controlled Gnome Fireball permutation.
        var c=Context(445566,new[] {"OGsprite","OGsprite","OGsprite"}); var rom=Copy(native);
        Apply(new SpellShuffleAssignments(),native,rom,settings,c); Force(c,2,0,12);
        Apply(new CharacterClasses(),native,rom,settings,c);
        before=(byte[])rom.Clone(); int start=c.workingOffset;
        Check(Apply(new SpellShuffle(),native,rom,settings,c),"Runtime not installed.");
        Check(c.workingOffset<start+8192 && start>>16==(c.workingOffset-1)>>16,"Allocation crosses code bank.");
        var spans=new[] {new[] {0x10CEB2,6},new[] {0x10D074,4},new[] {0x10D080,4},new[] {0x10D089,7},new[] {0x3FAA,6},new[] {0xBC14,4},new[] {0x8E8A0,7}};
        for(int i=0;i<rom.Length;i++) if(rom[i]!=before[i])
            Check(i>=start && i<c.workingOffset || spans.Any(p=>i>=p[0] && i<p[0]+p[1]),"Unrelated ROM write at "+i.ToString("X6"));
        Check(Enumerable.Range(0x8E7EE,0x900).Where(i=>i<0x8E8A0 || i>=0x8E8A7).All(i=>native[i]==rom[i]),"Enemy effects/PlayerMagicDamage code touched outside affinity hook.");
        Check(native.Skip(0x102AD8).Take(42*64).SequenceEqual(rom.Skip(0x102AD8).Take(42*64)),"Global spell metadata changed.");
        Check(!c.replacementEvents.ContainsKey(0x42D),"Late Mana Magic unlock changed.");
        foreach(FieldInfo field in typeof(CustomRamOffsets).GetFields(BindingFlags.Public|BindingFlags.Static))
        {
            if(field.FieldType!=typeof(int) || field.Name.StartsWith("SPELL_SHUFFLE_")) continue;
            int value=(int)field.GetValue(null);
            if(value>=0x7E0400 && value<0x7E0600)
            {
                int length=field.Name=="SAVED_MUSIC_REQUEST" ? 3 : field.Name.Contains("16BIT") ? 2 : 1;
                Check(value+length<=CustomRamOffsets.SPELL_SHUFFLE_ORB_CONTEXT,"Spell context overlaps "+field.Name);
            }
        }
        Runtime(c,rom);
        Interpreter(c,rom);
        TargetLifecycle(c,rom);
        GirlMenus(native,settings);
        SupportAndLogic(native,settings);
        SelfLocks(native,settings);
        // Hook ownership rejection cannot silently replace another installed patch.
        var bad=Copy(native); bad[0x10CEB2]=0xEA;
        bool rejected=false; try { Apply(new SpellShuffle(),native,bad,settings,c); } catch(TargetInvocationException e) { rejected=e.InnerException is InvalidOperationException; }
        Check(rejected,"Conflicting hook silently overwritten.");
        return "PASS: "+assertions+" spell shuffle assignment/runtime/logic assertions.";
    }
    private static SpellShuffleMachine NewMachine(byte[] rom)
    {
        var m=new SpellShuffleMachine(rom);
        for(int slot=0;slot<3;slot++) for(int spirit=0;spirit<8;spirit++) m.Write(0x7EE1C8+slot*512+spirit,0x3F,1);
        return m;
    }
    private static void Runtime(RandoContext c,byte[] rom)
    {
        foreach(int slot in Enumerable.Range(0,3)) foreach(int destination in SpellShuffleAssignments.getRoleSpellIds("OGsprite"))
        {
            int actual=SpellShuffleAssignments.getRow(c,slot)[destination]; var m=NewMachine(rom);
            m.A=destination; m.X=SpellShuffleAssignments.getSpiritIndex(destination); m.Y=0x1234; m.P=0x21;
            m.Write(0x7E1808,slot,1); int savedX=m.X;
            m.Run(c.workingData.getInt(SpellShuffle.SELECT_ROUTINE));
            Check(m.Read(0x7E1839,1)==actual && m.Read(0x7E19F1,1)==actual,"Selected/executed IDs disagree.");
            Check(m.X==savedX && m.Y==0x1234 && m.P==0x21 && m.S==0x1FF,"Select corrupts native register/stack contract.");
            m.Write(0x7E184F,destination,1); m.P=0; m.Run(c.workingData.getInt(SpellShuffle.ICON_ROUTINE));
            Check(m.A==m.Read(0xD8FD7E+actual*2,2),"Icon not mapped.");
            m.P=0x20; m.Run(c.workingData.getInt(SpellShuffle.METADATA_ROUTINE));
            Check(m.Read(0x7E1843,1)==rom[0x102ADF+actual*64],"MP metadata not mapped.");
            Check(m.Read(0x7E1842,1)==rom[0x102AD8+actual*64],"Targeting metadata not mapped.");
            m.Write(0x7EE186+slot*512,m.Read(0x7E1843,1),1);
            m.Write(0x7E1844,0x1A00,2); m.Run(0xC073AC);
            Check((m.P&1)!=0,"Actual MP cost not affordable at exact caster MP.");
            int cost=m.Read(0x7E1843,1);
            if(cost>0) {
                m.Write(0x7EE186+slot*512,cost-1,1); m.Run(0xC073AC);
                Check((m.P&1)==0,"Actual MP cost ignored/another player's MP used.");
            }
            // Native queue keeps selected actual ID AND the distinct destination spirit index.
            m.Write(0x7E1846,SpellShuffleAssignments.getSpiritIndex(destination),1);
            m.Write(0x7E1844,0x1A00,2); m.Write(0x7E1822,0x200,2); m.Write(0x7E0201,0,1);
            m.Run(0xC0731F,true);
            Check(m.Read(0x7E19F0,1)==actual && m.Read(0x7E19F7,1)==SpellShuffleAssignments.getSpiritIndex(destination),"Queue loses source spirit/effect.");
        }
        // Full native role -> spirit -> menu-position calculation, not just the helper.
        for(int slot=0;slot<3;slot++)
        {
            var m=NewMachine(rom); m.Write(0x7E1808,slot,1); m.Write(0x7E1875,0,1); m.Write(0x7E1878,0,1);
            m.Run(0xD0CE5D);
            Check(m.Read(0x7E1839,1)==SpellShuffleAssignments.getRow(c,slot)[0],"Native menu layout leaks across physical slots.");
            Check(m.Read(0x7E1846,1)==0,"Destination level/EXP index changed.");
            m.Write(0x7E1803,0x80,2); m.Run(0xD0D4DF,true);
            Check(m.Read(0x7E19D2,1)==0x56 && m.Read(0x7E19D3,1)==SpellShuffleAssignments.getRow(c,slot)[0],
                "Battle menu spell-name lookup uses original destination name.");
        }
        var level=NewMachine(rom); level.P=0x20; level.DP=0x300; level.Y=0x400;
        level.Write(0x7E0383,0x400,2); level.Write(0x7EE1FB+0x400,0x80,1);
        level.Write(0x7EE170+0x400,12,1); level.Write(0x7EE177+0x400,0,1);
        level.Write(0x7EE1C4+0x400,0x60,1); level.Write(0x7EE1C5+0x400,0x10,1);
        level.Write(0x7EE1D8+0x400,20,1); level.Write(0x7EE1DC+0x400,70,1);
        level.Write(0x7ECFFC,8,1); level.Write(0x7E00ED,0x80,1);
        level.Run(0xD04E6E,true);
        Check(level.Read(0x7E039D,1)==6 && level.Read(0x7E039E,1)==20,"Fireball reads Salamando rather than queued Gnome level/EXP.");
        level.Run(0xD04DCD);
        Check(level.Read(0x7EE1D8+0x400,1)==23 && level.Read(0x7EE1DC+0x400,1)==70,
            "Native magic EXP advances wrong destination spirit.");
        var hit=NewMachine(rom); Hit(hit,c,0x600,2,12,291);
        CheckOrb(hit,c,0x600,0x81,true);
        CheckOrb(hit,c,0x600,0x81,false); // exactly once
        Hit(hit,c,0x600,2,12,291); CheckOrb(hit,c,0x600,0x83,false);
        Hit(hit,c,0x600,2,12,291); hit.Write(0x7E00DC,307,2); CheckOrb(hit,c,0x600,0x81,false);
        Hit(hit,c,0x600,2,12,291); hit.Write(0x7EE1E7+0x600,0x54,1); CheckOrb(hit,c,0x600,0x81,false);
        Hit(hit,c,0x600,2,12,291); hit.Write(CustomRamOffsets.SPELL_SHUFFLE_ORB_CONTEXT+24+3,3,1); CheckOrb(hit,c,0x600,0x81,false);
        Hit(hit,c,0x600,2,12,291); hit.Write(0x7EE181+0x600,13,1); CheckOrb(hit,c,0x600,0x81,false);
        hit.Write(0x7EE1C8+0x400,0,1); Hit(hit,c,0x600,2,12,291); CheckOrb(hit,c,0x600,0x81,false);
        hit.Write(0x7EE1C8+0x400,7,1);
        // No hit/interrupted selection cannot arm; enemy/script/reflected caster rejected.
        CheckOrb(NewMachine(rom),c,0x600,0x81,false);
        Hit(hit,c,0x600,3,12,291); CheckOrb(hit,c,0x600,0x81,false);
        Hit(hit,c,0x600,2,32,291); CheckOrb(hit,c,0x600,0x88,false);
        // Overlapping real effects retain distinct per-target, per-caster inverse identities.
        var overlap=NewMachine(rom);
        int otherActual=SpellShuffleAssignments.getRow(c,0)[6];
        Hit(overlap,c,0x600,2,12,291); Hit(overlap,c,0x800,0,otherActual,291);
        CheckOrb(overlap,c,0x600,0x81,true); CheckOrb(overlap,c,0x800,0x82,
            (rom[0x102AD8+otherActual*64]&128)!=0);
        Hit(hit,c,0x600,2,12,291); hit.P=0xA1; hit.A=0x1234; hit.X=0x7788; hit.Y=0x99AA;
        hit.Run(c.workingData.getInt(SpellShuffle.CLEAR_ROUTINE));
        Check(hit.MapLoads==1 && hit.A==0x1234 && hit.X==0x7788 && hit.Y==0x99AA && hit.P==0xA1 && hit.S==0x1FF,"Map-clear fails native call/register contract.");
        Check(Enumerable.Range(0,96).All(i=>hit.Read(CustomRamOffsets.SPELL_SHUFFLE_ORB_CONTEXT+i,1)==0),"Save/load/map transition leaves stale context.");
        CheckOrb(hit,c,0x600,0x81,false);
    }
    private static void Hit(SpellShuffleMachine m,RandoContext c,int target,int caster,int actual,int map)
    {
        m.P=0x20; m.DB=0x7E; m.DP=0x300; m.X=caster*512; m.Y=target; m.A=0xAB01;
        m.Write(0x7E0382,caster,1); m.Write(0x7EE000+target,1,1);
        m.Write(0x7EE1E7+target,0x55,1); m.Write(0x7EE170+caster*512,actual,1); m.Write(0x7E00DC,map,2);
        m.Run(c.workingData.getInt(SpellShuffle.CAPTURE_ROUTINE));
        Check(m.A==(0xAB00|actual) && m.X==caster*512 && m.Y==target && m.S==0x1FF && m.DB==0x7E && m.DP==0x300,"Capture corrupts native replay/register/stack state.");
        Check(m.Read(0x7EE181+target,1)==actual,"Capture loses real spell.");
    }
    private static void Interpreter(RandoContext c,byte[] rom)
    {
        // Enter the REAL native special-object routine, including $395E's swap.
        // The old $C8:E77E hook was absent from this path; a helper-only fixture
        // incorrectly assumed the damage-target pipeline always preceded the checker.
        var m=NativeNotificationFixture(rom);
        Check(m.Read(0x7E00D4,2)==0,"Regression must start with the observed zero event owner.");
        m.Run(0xC03F94);
        Check(m.SpecialEvents==1 && m.LastSpecialEvent==0x239 && m.LastSpecialTarget==0x600,"Native magic special-object notification not reached.");
        Check(m.EventStarts==1 && m.LastEventOwner==0x600 && m.Read(0x7E00D4,2)==0x600,
            "Real native dispatcher lost notification target while starting event $239.");
        Check(m.Visits.Contains(0xC1E783) && m.Read(0x7E00D0,1)==1,
            "Regression must execute actual event acceptance, not a target-synthesizing dispatch stub.");
        Check(m.Read(CustomRamOffsets.SPELL_SHUFFLE_ORB_CONTEXT+24,1)==1,"Native notification failed to capture Gnome Fireball before event dispatch.");
        Check(!m.Visits.Contains(0xC8E77E),"Special-object path unexpectedly requires damage-target hook.");
        Check(m.S==0x1FF && m.DP==0x120 && m.DB==0xC8 && m.P==0x21,"Native special-target caller state damaged.");

        int offset=c.workingOffset; c.eventHackMgr.process(rom,ref offset);
        // Negative control: remove ONLY the new event-owner store from emitted
        // machine code. This reproduces the Mesen failure without repairing D4
        // in either the fixture or the native dispatcher boundary.
        var broken=(byte[])rom.Clone(); int stores=0;
        for(int at=c.workingData.getInt(SpellShuffle.CAPTURE_ROUTINE)-0xC00000;
            at<c.workingData.getInt(SpellShuffle.CLEAR_ROUTINE)-0xC00000-3;at++)
            if(broken.Skip(at).Take(4).SequenceEqual(new byte[] {0x8F,0xD4,0,0x7E})) {
                stores++; for(int i=0;i<4;i++) broken[at+i]=0xEA;
            }
        Check(stores==1,"Regression control did not isolate the single event-owner store.");
        var failed=NativeNotificationFixture(broken); failed.Run(0xC03F94);
        Check(failed.EventStarts==1 && failed.LastEventOwner==0 &&
            failed.Read(CustomRamOffsets.SPELL_SHUFFLE_ORB_CONTEXT+24,1)==1,
            "Missing-binding control did not reproduce valid capture plus zero event owner.");
        RunCheckerCommand(failed,c.replacementEvents[0x350]);
        Check(failed.Read(0x7ECF98,1)==0 && failed.Read(CustomRamOffsets.SPELL_SHUFFLE_ORB_CONTEXT+24,1)==1 &&
            failed.Visits.Contains(c.workingData.getInt(SpellShuffle.CHECKER_PREFIX+0x81)+0x1E),
            "Missing-binding control did not take the proven target-range rejection before consumption.");
        foreach(int family in new[] {0x81,0x83})
        {
            // Gnome uses the SAME native notification/dispatch machine above:
            // no fixture repairs $00D4 before the real custom-command interpreter.
            var test=family==0x81 ? m : NewMachine(rom);
            if(family!=0x81) Hit(test,c,0x600,2,12,291);
            int checker=family==0x81?0x350:0x353;
            var ev=c.replacementEvents[checker];
            Check(ev.SequenceEqual(new byte[] {0x34,4,0x80,0x08,0x57,ev[5],2,0}),"Checker opcode/argument boundaries changed.");
            RunCheckerCommand(test,ev);
            Check(test.PC==0xC1E8D3 && test.Read(0x7E00D1,2)==0x1002,"Non-text checker entered dialogue or failed to advance two bytes.");
            Check(test.Read(0x7ECF00+(family==0x81?0x98:0x9B),1)==(family==0x81?1:0),"Actual event-interpreter checker result incorrect.");
            Check(!test.Writes.Contains(0x7E1D01) && !test.Writes.Contains(0x7EA22F),"Orb checker touched dialogue/name buffer.");
            Check(test.Read(CustomRamOffsets.SPELL_SHUFFLE_ORB_CONTEXT+24,1)==0,"Interpreter did not consume hit exactly once.");
            if(family==0x81) {
                // Earth $239's normal success tail is still authoritative. A result
                // of 1 is in its 1..3 success range, with no completed-map guard set.
                var elements=new Dictionary<int,byte>(); var events=new Dictionary<int,List<byte>>();
                var plando=new Dictionary<string,List<string>> {
                    {PlandoProperties.KEY_EARTH_PALACE_ORB_ELEMENT,new List<string> {"Gnome"}} };
                new ElementSwaps().processOpenWorld((byte[])rom.Clone(),new DotNet110Random(9),elements,events,
                    true,true,true,plando,true,false);
                Check(events[0x239].SequenceEqual(new byte[] {0x23,0x50,0x42,0x18,0x2F,0x10,0,0x42,0x98,0x13,0x10,0x38,0}),
                    "Earth normal guard/checker/success transfer to $038 changed.");
                Check(test.Read(0x7ECF18,1)<2 && test.Read(0x7ECF98,1)==1,
                    "Runtime checker result cannot proceed through Earth's normal success tail.");
            }
        }
    }
    private static SpellShuffleMachine NativeNotificationFixture(byte[] rom)
    {
        var m=NewMachine(rom); m.ExecuteSpecialEventDispatch=true;
        m.X=0x600; m.Y=0x400; m.P=0x21; m.DP=0x120; m.DB=0xC8;
        m.Write(0x7EE1FB+0x600,0x10,1); m.Write(0x7EE000+0x600,2,1);
        m.Write(0x7EE1E7+0x600,0x55,1); m.Write(0x7EE170+0x400,12,1);
        m.Write(0x7EE03E+0x600,0x239,2); m.Write(0x7E00DC,291,2);
        m.Write(0x7EE1EC+0x600,0xFF,1); // stale field is irrelevant on this path
        return m;
    }
    private static void RunCheckerCommand(SpellShuffleMachine m,List<byte> ev)
    {
        m.Write(0x7E1000,0x57|(ev[5]<<8),2);
        m.Write(0x7E00D1,0x1000,2); m.Write(0x7E00D3,0x7E,1);
        m.P=0x10; m.DP=0; m.DB=0x7E; m.X=0xAB; m.Y=0xCD;
        m.Stops.Add(0xC1E8D3); m.Stops.Add(0xC1F27A); m.Writes.Clear();
        m.Run(0xC1E8F1);
    }
    private static void TargetLifecycle(RandoContext c,byte[] rom)
    {
        // Every physical caster and valid enemy-record offset; never hardcode $0600.
        for(int slot=0;slot<3;slot++) for(int target=0x600;target<0x1800;target+=0x200)
        {
            int dest=SpellShuffleAssignments.getRoleSpellIds("OGsprite").First(d=>
                d!=32 && (rom[0x102AD8+SpellShuffleAssignments.getRow(c,slot)[d]*64]&128)!=0);
            int actual=SpellShuffleAssignments.getRow(c,slot)[dest];
            var test=NewMachine(rom); test.Write(0x7E00D4,0,2);
            Hit(test,c,target,slot,actual,291);
            Check(test.Read(0x7E00D4,2)==target,"Accepted Orb hit does not bind its own event target.");
            CheckOrb(test,c,target,SpellShuffleAssignments.getSpiritFamily(dest),true);
            CheckOrb(test,c,target,SpellShuffleAssignments.getSpiritFamily(dest),false);
        }
        // Mismatched owner cannot select a different target's valid saved cast.
        var isolated=NewMachine(rom); Hit(isolated,c,0x600,2,12,291);
        CheckOrb(isolated,c,0x800,0x81,false);
        Check(isolated.Read(CustomRamOffsets.SPELL_SHUFFLE_ORB_CONTEXT+24,1)==1,
            "Mismatched actor consumed another target's context.");
        CheckOrb(isolated,c,0x600,0x81,true);
        // A newly notified target with an invalid/unlearned cast must replace the
        // event owner, but cannot fall back to the older valid target's context.
        Hit(isolated,c,0x600,2,12,291); Hit(isolated,c,0x800,3,12,291);
        Check(isolated.Read(0x7E00D4,2)==0x800,"Invalid cast left previous Orb as event owner.");
        CheckOrb(isolated,c,0x800,0x81,false);
        Check(isolated.Read(CustomRamOffsets.SPELL_SHUFFLE_ORB_CONTEXT+24,1)==1,"Invalid caster inherited unrelated context.");
        // A busy interpreter rejects the notification, without stealing its owner
        // or replacing an already accepted cast while its checker waits for animation.
        var busy=NewMachine(rom); Hit(busy,c,0x600,2,12,291);
        byte[] accepted=busy.Memory.Skip(CustomRamOffsets.SPELL_SHUFFLE_ORB_CONTEXT).Take(96).ToArray();
        busy.Write(0x7E00D0,1,1); Hit(busy,c,0x800,2,12,291);
        Check(busy.Read(0x7E00D4,2)==0x600 && accepted.SequenceEqual(
            busy.Memory.Skip(CustomRamOffsets.SPELL_SHUFFLE_ORB_CONTEXT).Take(96)),"Busy hit stole event owner/context.");
        busy.Write(0x7E00D0,0xFF,1); Hit(busy,c,0xA00,2,12,291);
        Check(busy.Read(0x7E00D4,2)==0xA00,"Native FF event-entry state incorrectly rejected.");
        foreach(int target in new[] {0,0x400,0x601,0x1800}) {
            var invalid=NewMachine(rom); invalid.Write(0x7E00D4,0x200,2);
            Hit(invalid,c,target,2,12,291);
            Check(invalid.Read(0x7E00D4,2)==0x200,"Invalid actor changed event owner.");
        }
        var enemy=NewMachine(rom); enemy.Write(0x7E00D4,0x200,2);
        enemy.P=0x20; enemy.X=0x400; enemy.Y=0x600; enemy.Write(0x7EE1E7+0x600,0x54,1);
        enemy.Run(c.workingData.getInt(SpellShuffle.CAPTURE_ROUTINE));
        Check(enemy.Read(0x7E00D4,2)==0x200,"Non-Orb special target changed event owner.");
    }
    private static void CheckOrb(SpellShuffleMachine m,RandoContext c,int target,int family,bool success)
    {
        int flag=Array.IndexOf(new[] {0x81,0x82,0x85,0x83,0x84,0x86,0x87,0x88},family)+0x98;
        m.Write(0x7E00D4,target,2); m.Write(0x7ECF00+flag,15,1);
        m.P=0xA1; m.A=0x8765; m.X=0x4444; m.Y=0x2222; m.DB=0xC0;
        m.Run(c.workingData.getInt(SpellShuffle.CHECKER_PREFIX+family));
        Check(m.Read(0x7ECF00+flag,1)==(success?1:0),"Orb result wrong: "+family.ToString("X2"));
        Check(m.P==0xA1 && m.A==0x8765 && m.X==0x4444 && m.Y==0x2222 && m.DB==0xC0 && m.S==0x1FF,"Checker corrupts caller state.");
    }
    private static void SupportAndLogic(byte[] native,OpenWorldSettings settings)
    {
        // A Girl's vanilla Gnome support trio cannot target an Orb. Identity is a controlled
        // permutation used solely in this regression, not a production shuffle override.
        var c=Context(7,new[] {"OGboy","OGgirl","OGboy"});
        SpellShuffleAssignments.resolveAndStore(settings,c,native);
        c.workingData.setIntArray(SpellShuffleAssignments.ROW_PREFIX+1,Enumerable.Range(0,42).ToArray());
        Check(!SpellShuffleAssignments.getValidOrbElements(c).Contains((byte)0x81),"Support-only Gnome eligible.");
        Check(SpellShuffleAssignments.getValidOrbElements(c).Contains((byte)0x84),"Girl offensive Lumina ineligible.");
        var ev=new Dictionary<int,List<byte>>(); var elements=new Dictionary<int,byte>(); var rom=Copy(native);
        var plando=new Dictionary<string,List<string>>(); plando[PlandoProperties.KEY_EARTH_PALACE_ORB_ELEMENT]=new List<string> {"Gnome"};
        bool rejected=false;
        try { new ElementSwaps().processOpenWorld(rom,new DotNet110Random(9),elements,ev,true,false,false,plando,true,false,SpellShuffleAssignments.getValidOrbElements(c)); }
        catch(ArgumentException e) { rejected=e.Message.Contains("no obtainable"); }
        Check(rejected,"Impossible forced Orb not clearly rejected.");
        plando.Clear(); elements.Clear(); ev.Clear();
        new ElementSwaps().processOpenWorld(rom,new DotNet110Random(9),elements,ev,true,false,false,plando,true,false,SpellShuffleAssignments.getValidOrbElements(c));
        Check(elements.Values.All(v=>v==255 || SpellShuffleAssignments.getValidOrbElements(c).Contains(v)),"Impossible Orb/Grand Palace default.");
        Check(ev.ContainsKey(0x570) && ev[0x570].Contains((byte)0xE8),"Grand Palace inline mutation lost.");
        var noMagic=new Dictionary<int,byte>(); var noEvents=new Dictionary<int,List<byte>>();
        bool noCasterRejected=false;
        plando[PlandoProperties.KEY_EARTH_PALACE_ORB_ELEMENT]=new List<string> {"Gnome"};
        try { new ElementSwaps().processOpenWorld(Copy(native),new DotNet110Random(9),noMagic,noEvents,false,false,false,plando,true,true,new List<byte>()); }
        catch(ArgumentException) { noCasterRejected=true; }
        Check(noCasterRejected,"No-caster forced Magic silently falls back to weapon.");
        var have=typeof(OpenWorldSimulator).GetMethod("haveRequirementWithAssignments",BindingFlags.Static|BindingFlags.NonPublic);
        Check((bool)have.Invoke(null,new object[] {SpellShuffleAssignments.OWNED_SPIRIT_PREFIX+"gnome spells",new List<string> {"gnome spells"},new List<string>(),new List<string>(),new List<string>(),new List<string>(),c}),
            "A support-only spirit cannot be delivered as a Christmas gift.");
        foreach(string[] owned in new[] {new string[0],new[] {"lumina spells"},new[] {"girl"},new[] {"girl","lumina spells"}})
        {
            bool result=(bool)have.Invoke(null,new object[] {"lumina spells",owned.ToList(),new List<string>(),new List<string>(),new List<string>(),new List<string>(),c});
            Check(result==(owned.Contains("girl") && owned.Contains("lumina spells")),"Simulator ignores joined caster/owned spirit.");
        }
        // Shuffled Girl support/healing names, costs, targeting and true effects remain native.
        // Move Cure Water into Gnome (a real healing permutation) and verify the native
        // Girl menu, not just metadata loaded in isolation.
        Force(c,1,3,11);
        Apply(new CharacterClasses(),native,rom,settings,c); Apply(new SpellShuffle(),native,rom,settings,c);
        var m=NewMachine(rom); m.Write(0x7E1808,1,1); m.Write(0x7E184F,9,1);
        m.Run(c.workingData.getInt(SpellShuffle.METADATA_ROUTINE));
        Check(m.Read(0x7E1842,1)==native[0x102AD8+9*64] && (m.Read(0x7E1842,1)&128)==0,"Healing targeting changed.");
        m.Write(0x7E1874,0,1); m.Write(0x7E1878,0,1); m.Run(0xD0CE5D);
        Check(m.Read(0x7E1839,1)==11 && m.Read(0x7E1846,1)==0,"Girl Gnome Cure Water selection/level wrong.");
        Check(m.Read(0x7E1843,1)==native[0x102ADF+11*64],"Girl healing MP cost changed.");
    }
    private static void GirlMenus(byte[] native,OpenWorldSettings settings)
    {
        var c=Context(778899,new[] {"OGgirl","OGgirl","OGgirl"}); var rom=Copy(native);
        Apply(new SpellShuffleAssignments(),native,rom,settings,c);
        Apply(new CharacterClasses(),native,rom,settings,c); Apply(new SpellShuffle(),native,rom,settings,c);
        for(int slot=0;slot<3;slot++) foreach(int dest in SpellShuffleAssignments.getRoleSpellIds("OGgirl"))
        {
            var m=NewMachine(rom); int spirit=SpellShuffleAssignments.getSpiritIndex(dest);
            // Girl has no Shade slots; native menu counts only learned spirits.
            m.Write(0x7EE1CE+slot*512,0,1);
            m.Write(0x7E1808,slot,1); m.Write(0x7E1874,spirit==7?6:spirit,1);
            m.Write(0x7E1878+spirit,(dest%6-3)<<4,1); m.Run(0xD0CE5D);
            Check(m.Read(0x7E1839,1)==SpellShuffleAssignments.getRow(c,slot)[dest],"Three-Girl menu leaked slot/layout.");
            Check(m.Read(0x7E1846,1)==spirit,"Girl menu source spirit index incorrect: slot "+slot+" destination "+dest+" expected "+spirit+" got "+m.Read(0x7E1846,1));
        }
    }
    private static void SelfLocks(byte[] native,OpenWorldSettings settings)
    {
        var c=Context(4455,new[] {"OGboy","OGboy","OGsprite"});
        SpellShuffleAssignments.resolveAndStore(settings,c,native);
        c.workingData.setIntArray(SpellShuffleAssignments.ROW_PREFIX+2,Enumerable.Range(0,42).ToArray());
        c.workingData.setBool("startWithBoy",true); c.workingData.setBool("startWithGirl",false);
        c.workingData.setBool("startWithSprite",false); c.workingData.setBool("anyMagicExists",true);
        c.workingData.set("openWorldGoalShortName","manabeast"); c.workingData.setInt("manaSeedsRequired",0);
        c.workingData.setInt("boyStartWeapon",0); c.workingData.setInt("girlStartWeapon",1); c.workingData.setInt("spriteStartWeapon",2);
        settings.set(OpenWorldSettings.PROPERTYNAME_ALLOW_MISSED_ITEMS,"no");
        c.plandoSettings[PlandoProperties.KEY_LOCATION_START_WITH]=new List<string> {"Gnome"};
        var gate=new PrizeLocation("findable caster behind own Orb",0,0,new string[0],new string[0],new[] {"gnome spells"},1);
        var placements=new Dictionary<PrizeLocation,PrizeItem> {{gate,new PrizeItem("sprite","",new byte[0],"",0,1)}};
        Check(OpenWorldSimulator.runSimulation(placements,settings,c).score==-1,"Findable caster behind its own Orb considered reachable.");
        placements.Add(new PrizeLocation("free character",0,0,new string[0],new string[0],new string[0],1),new PrizeItem("sprite","",new byte[0],"",0,1));
        Check(OpenWorldSimulator.runSimulation(placements,settings,c).score>0,"Joining legitimate caster does not unlock shuffled Orb.");
        c.plandoSettings.Clear(); c.workingData.setBool("startWithSprite",true); placements.Clear();
        placements.Add(gate,new PrizeItem("gnome spells","",new byte[0],"",0,1));
        Check(OpenWorldSimulator.runSimulation(placements,settings,c).score==-1,"Spirit behind its own Orb considered reachable.");
    }
}
