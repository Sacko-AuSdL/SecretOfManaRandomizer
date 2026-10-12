using System;
using System.Linq;
using System.Reflection;
using SoMRandomizer.config.settings;
using SoMRandomizer.processing.common;
using SoMRandomizer.processing.hacks.common.util;
using SoMRandomizer.processing.hacks.openworld;
using SoMRandomizer.util.rng;

public static class CrystalOrbDialogTests
{
    private static int assertions;
    private static void Check(bool value,string text) { assertions++; if(!value) throw new Exception(text); }
    private static byte[] Copy(byte[] native) { var rom=new byte[0x400000]; Array.Copy(native,rom,native.Length); return rom; }
    private static void Dispatch(SpellShuffleMachine m,int id)
    {
        m.Write(0x7E1000,0x57|(id<<8),2); m.Write(0x7E00D1,0x1000,2); m.Write(0x7E00D3,0x7E,1);
        m.P=0x10; m.DB=0x7E; m.DP=0; m.X=0xAB; m.Y=0xCD;
        m.Stops.Add(0xC1F27A); m.Stops.Add(0xC1E8D3); m.Writes.Clear(); m.Run(0xC1E8F1);
    }
    public static string Run(byte[] native)
    {
        assertions=0;
        // Reproduce the OLD producer from the real interpreter, not a presumed
        // generic message queue: native $57 routes directly to OPEN_DIALOGUE.
        var old=new SpellShuffleMachine(Copy(native)); Dispatch(old,3);
        Check(old.PC==0xC1F27A,"Native custom opcode no longer enters dialogue as expected.");
        var untouched=Copy(native); var baseline=(byte[])untouched.Clone(); int offset=0x200000;
        new CustomEventManager().process(untouched,ref offset);
        Check(untouched.SequenceEqual(baseline) && offset==0x200000,"No-command mode modified interpreter.");

        foreach(string mode in new[] {"on","weaponOnly"})
        {
            var common=new CommonSettings(); common.set("mode","open");
            var settings=new OpenWorldSettings(common); settings.set("crystalOrbWeaponBreaking",mode);
            settings.set("spellShuffle","off");
            var c=new RandoContext(); c.randomFunctional=new DotNet110Random(123);
            // One controlled cached weapon requirement; production resolver is not changed.
            c.workingData.setInt("orbElement291",0x81);
            c.workingData.setInt("crystalOrbRequirementsResolved",1);
            c.workingData.setInt("crystalOrbRequirementType291",1);
            c.workingData.setInt("crystalOrbRequirementValue291",4);
            c.replacementEvents[0x239]=new System.Collections.Generic.List<byte> {0x23,0x50,0x42,0x98,0x13,0x10,0x38,0};
            var rom=Copy(native);
            typeof(CrystalOrbWeaponBreaking).GetMethod("process",BindingFlags.Instance|BindingFlags.NonPublic)
                .Invoke(new CrystalOrbWeaponBreaking(),new object[] {native,rom,"dialog-test",settings,c});
            var ev=c.replacementEvents[0x239];
            Check(ev.SequenceEqual(new byte[] {0x30,0x98,0,0x57,ev[4],0x42,0x98,0x13,0x10,0x38,0}),"Weapon wrapper damaged event boundaries/tail.");
            offset=c.workingOffset; c.eventHackMgr.process(rom,ref offset);
            foreach(string[] names in new[] {new[] {"A","AA","AAA"},new[] {"Randi","Primm","Popoi"}})
            {
                foreach(bool armed in new[] {false,true})
                {
                    var m=new SpellShuffleMachine(rom);
                    for(int slot=0;slot<3;slot++) {
                        var text=VanillaEventUtil.getBytes(names[slot]);
                        for(int i=0;i<12;i++) m.Write(0x7ECC00+slot*12+i,i<text.Count?text[i]:0,1);
                    }
                    // Stale player-name/text content is deliberately present and
                    // unterminated. The fixed path must NEVER ask the renderer to use it.
                    for(int i=0;i<64;i++) m.Write(0x7EA22F+i,0x81,1);
                    m.Write(0x7E00DC,291,2); m.Write(0x7E00D4,0x600,2);
                    m.Write(0x7EE000+0x600,1,1); m.Write(0x7EE1E7+0x600,0x55,1);
                    m.Write(CustomRamOffsets.CRYSTAL_ORB_PENDING_STATE,armed?2:0,1);
                    m.Write(CustomRamOffsets.CRYSTAL_ORB_PENDING_TARGET_16BIT,0x600,2);
                    m.Write(CustomRamOffsets.CRYSTAL_ORB_PENDING_MAP_16BIT,291,2);
                    Dispatch(m,ev[4]);
                    Check(m.PC==0xC1E8D3 && m.Read(0x7E00D1,2)==0x1002,"Weapon command opened text or wrong continuation.");
                    Check(m.Read(0x7ECF98,1)==(armed?2:0),"Weapon pass behavior changed.");
                    Check(m.Read(CustomRamOffsets.CRYSTAL_ORB_PENDING_STATE,1)==0,"Physical pass was not cleared.");
                    Check(!m.Writes.Any(a=>a>=0x7EA000 && a<0x7EA300 || a>=0x7E1D00 && a<0x7E1D06),"State-only command touched text/window buffers.");
                    Check(m.S==0x1FC && m.X==0xAB && m.Y==0xCD && m.DB==0x7E && m.DP==0,"Dispatch stack/register contract damaged.");
                }
                // Built-in 57 00/01/02 STILL dispatch to dialogue, and the original
                // player-name copy remains byte-exact for short and ordinary names.
                for(int slot=0;slot<3;slot++)
                {
                    var m=new SpellShuffleMachine(rom); Dispatch(m,slot);
                    Check(m.PC==0xC1F27A,"Player-name insertion no longer takes text path.");
                    m=new SpellShuffleMachine(rom); m.Write(0x7E1000,slot,1);
                    var text=VanillaEventUtil.getBytes(names[slot]);
                    for(int i=0;i<12;i++) m.Write(0x7ECC00+slot*12+i,i<text.Count?text[i]:0,1);
                    m.P=0x20; m.Y=0x1000; m.Run(0xC0182B,true);
                    Check(Enumerable.Range(0,12).All(i=>m.Read(0x7EA22F+i,1)==(i<text.Count?text[i]:0)) && m.Read(0x7EA23B,1)==0,"Player-name copy changed.");
                    Check(m.S==0x1FF,"Name insertion stack unbalanced.");
                }
            }
        }
        // Existing printing custom commands are opt-IN to the old text path
        // by default, not swallowed by the non-text event extension.
        var printing=Copy(native); var mgr=new CustomEventManager();
        int printingId=mgr.registerNewEvent("printing",0x200000);
        mgr.registerNewEvent("state only",0x200000,false); offset=0x200100;
        mgr.process(printing,ref offset);
        var p=new SpellShuffleMachine(printing); Dispatch(p,printingId);
        Check(p.PC==0xC1F27A,"Printing custom command lost original dialogue dispatch.");
        // Exhaustively replay every ordinary opcode's dispatch up to its native
        // handler boundary. The hook must change ONLY opted-in state commands.
        for(int opcode=0;opcode<256;opcode++)
        {
            int handler=native[0x1E922+Math.Min(opcode,0x50)*2] |
                native[0x1E923+Math.Min(opcode,0x50)*2]<<8;
            var a=new SpellShuffleMachine(Copy(native)); var b=new SpellShuffleMachine(printing);
            foreach(var m in new[] {a,b}) {
                m.Write(0x7E1000,opcode|0x0200,2); // 57 02 remains player-name text
                m.Write(0x7E00D1,0x1000,2); m.Write(0x7E00D3,0x7E,1);
                m.P=0x10; m.X=0x67; m.Y=0x89; m.DP=0; m.DB=0x7E;
                m.Stops.Add(0xC10000+handler); m.Run(0xC1E8F1);
            }
            Check(a.PC==b.PC && a.A==b.A && a.X==b.X && a.Y==b.Y && a.P==b.P &&
                a.S==b.S && a.DB==b.DB && a.DP==b.DP && a.Read(0x7E00D1,2)==b.Read(0x7E00D1,2),
                "Non-Orb event dispatch changed at opcode "+opcode.ToString("X2"));
        }
        return "PASS: "+assertions+" Crystal Orb native-interpreter/name-buffer assertions (Shuffle Off, Mixed, Weapon Only).";
    }
}
