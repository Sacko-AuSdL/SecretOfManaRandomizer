using System;
using System.Linq;
using System.Reflection;
using SoMRandomizer.config.settings;
using SoMRandomizer.processing;
using SoMRandomizer.processing.common;
using SoMRandomizer.processing.hacks.openworld;
using SoMRandomizer.processing.hacks.common.qol;
using SoMRandomizer.processing.openworld;
using SoMRandomizer.util.rng;

public static class SpellShuffleAffinityTests
{
    private static int count;
    private static readonly int[] Bits={1,4,8,2,64,128,16,32}; // queued spirit order
    private static void Check(bool ok,string message) { count++; if(!ok) throw new Exception(message); }
    private static byte[] Copy(byte[] source) { var r=new byte[0x400000]; Array.Copy(source,r,source.Length); return r; }
    private static void Apply(RandoProcessor p,byte[] source,byte[] rom,OpenWorldSettings s,RandoContext c) {
        p.GetType().GetMethod("process",BindingFlags.NonPublic|BindingFlags.Instance).Invoke(p,new object[] {source,rom,"affinity-test",s,c});
    }
    private static RandoContext Context() {
        var c=new RandoContext(); c.randomFunctional=new DotNet110Random(556677);
        foreach(string slot in new[] {"boy","girl","sprite"}) { c.workingData.set(slot+"Class","OGsprite"); c.workingData.setBool(slot+"Exists",true); }
        return c;
    }
    private static SpellShuffleMachine Machine(byte[] rom,int caster,int spell,int spirit,int target=0x600) {
        var m=new SpellShuffleMachine(rom); m.EmulateMathHardware=true; m.FixedRandom=0;
        m.A=0xAB45; m.P=0x61; m.X=target; m.Y=0x2345; m.DP=0x300;
        m.Write(0x7E0383,caster,2); m.Write(0x7E0385,target,2);
        m.Write(0x7E03DC,spell*64,2); m.Write(0x7E03DE,0xD0,1);
        m.Write(0x7EE170+caster,spell,1); m.Write(0x7EE177+caster,spirit,1);
        m.Write(0x7EE176+caster,1,1);
        for(int slot=0;slot<3;slot++) for(int i=0;i<8;i++) m.Write(0x7EE1C8+slot*512+i,0x3F,1);
        // Deliberately unrelated menu and consumed/garbage Orb context.
        m.Write(0x7E1808,2,1); m.Write(0x7E1846,7,1);
        for(int i=0;i<96;i++) m.Write(CustomRamOffsets.SPELL_SHUFFLE_ORB_CONTEXT+i,0xCC,1);
        return m;
    }
    private static int Factor(SpellShuffleMachine m,int weak,int resist) {
        m.Write(0x7EE1A1+m.X,weak,1); m.Write(0x7EE1A3+m.X,resist,1);
        m.Run(0xC8E8A0,true);
        Check(m.S==0x1FF && m.DB==0x7E && m.DP==0x300,"Affinity unbalanced stack or changed DB/DP");
        Check(Enumerable.Range(0,96).All(i=>m.Read(CustomRamOffsets.SPELL_SHUFFLE_ORB_CONTEXT+i,1)==0xCC),"Damage touched Orb context");
        return m.Read(0x7E038F,1);
    }
    private static void SameNative(byte[] native,byte[] rom,int caster,int actual,int spirit) {
        var a=Machine(native,caster,actual,spirit); var b=Machine(rom,caster,actual,spirit);
        int nativeBit=native[0x102ADC+actual*64];
        Check(Factor(a,nativeBit,0)==Factor(b,nativeBit,0),"Native fallback affinity changed");
        Check(a.A==b.A && a.X==b.X && a.Y==b.Y && a.P==b.P && a.S==b.S,"Native fallback registers/flags changed");
        Check(a.Writes.Concat(b.Writes).Where(at=>at>=0x7E0300).Distinct().All(at=>a.Read(at,1)==b.Read(at,1)),"Native fallback WRAM changed");
    }
    private static int Damage(byte[] rom,int caster,int actual,int spirit,int weak,int resist,int targets=1) {
        var m=Machine(rom,caster,actual,spirit); m.Y=caster;
        m.Write(0x7EE176+caster,targets,1); m.Write(0x7EE1E7+0x600,0x10,1);
        m.Write(0x7EE1A1+0x600,weak,1); m.Write(0x7EE1A3+0x600,resist,1);
        m.Write(0x7E0391,20,1); m.Write(0x7E0396,20,2); m.Write(0x7E039D,2,1);
        m.Run(0xC8EA8B,true); // actual native affinity -> formula -> final HP damage
        Check(m.S==0x1FF,"Native HP calculation unbalanced stack");
        return m.Read(0x7EE7F1,2);
    }
    public static string Run(byte[] native) {
        count=0;
        foreach(string mode in new[] {"perCharacter","party"}) {
            var common=new CommonSettings(); common.set("mode","open");
            var s=new OpenWorldSettings(common); s.set("spellShuffle",mode);
            var c=Context(); SpellShuffleAssignments.resolveAndStore(s,c,native);
            string rows=string.Join("|",Enumerable.Range(0,3).Select(i=>string.Join(",",SpellShuffleAssignments.getRow(c,i))));
            var control=Context(); SpellShuffleAssignments.resolveAndStore(s,control,native);
            var rom=Copy(native); Apply(new CharacterClasses(),native,rom,s,c); Apply(new SpellShuffle(),native,rom,s,c);
            Check(c.randomFunctional.Next()==control.randomFunctional.Next(),"Runtime affinity consumed RNG");
            Check(rows==string.Join("|",Enumerable.Range(0,3).Select(i=>string.Join(",",SpellShuffleAssignments.getRow(c,i)))),"Runtime affinity changed assignments");
            Check(rom.Skip(0x102AD8).Take(42*64).SequenceEqual(native.Skip(0x102AD8).Take(42*64)),"Global spell definitions changed");
            for(int slot=0;slot<3;slot++) foreach(int dest in SpellShuffleAssignments.getShuffleableSpellIds("OGsprite")) {
                int id=SpellShuffleAssignments.getRow(c,slot)[dest], spirit=SpellShuffleAssignments.getSpiritIndex(dest);
                // Only ordinary HP-damaging and HP-absorb native handlers should remap.
                int handler=native[0x8E801+id*2]|native[0x8E802+id*2]<<8;
                bool hp=new[] {0xEA8B,0xEB39,0xEB54,0xEBCA,0xEBE5}.Contains(handler);
                if(!hp) { SameNative(native,rom,slot*512,id,spirit); continue; }
                foreach(int target in new[] {0x600,0x800,0xA00,0x200}) { // multi-target and reflected player target
                    var m=Machine(rom,slot*512,id,spirit,target);
                    int factor=Factor(m,Bits[spirit],0);
                    Check(factor==4,"Destination weakness not applied: "+mode+"/"+slot+"/"+dest+" actual "+id+" target "+target+" factor "+factor);
                    Check(m.X==target && m.Y==slot*512 && (m.A&0xFF00)==0xAB00,"Physical caster/target/B corrupted");
                }
                Check(Factor(Machine(rom,slot*512,id,spirit),0,Bits[spirit])==1,"Destination resistance not applied");
                Check(Factor(Machine(rom,slot*512,id,spirit),0,0)==2,"Neutral affinity wrong");
                Check(Factor(Machine(rom,slot*512,id,spirit),Bits[spirit],Bits[spirit])==1,"Native resistance priority changed");
                var unlearned=Machine(rom,slot*512,id,spirit); unlearned.Write(0x7EE1C8+slot*512+spirit,0,1);
                var n=Machine(native,slot*512,id,spirit);
                Check(Factor(unlearned,0xFF,0)==Factor(n,0xFF,0),"Unlearned cast did not retain native fallback");
            }
            // All native spell IDs on an enemy/boss source remain native, regardless of menu state.
            foreach(int caster in new[] {0x600,0xA00}) for(int actual=0;actual<42;actual++) SameNative(native,rom,caster,actual,0);
            SameNative(native,rom,0x201,12,0); // not an aligned player
            SameNative(native,rom,0x400,12,8); // invalid source
            SameNative(native,rom,0x400,12,255);
            Check(SpellShuffleAssignments.getRow(c,2)[32]==32 && SpellShuffleAssignments.getRow(c,2)[35]==35,"Dryad Mana Magic moved");
        }
        // Controlled valid permutations, including same effect in multiple spirits/players.
        var settings=new OpenWorldSettings(new CommonSettings()); settings.set("mode","open"); settings.set("spellShuffle","party");
        var forced=Context(); SpellShuffleAssignments.resolveAndStore(settings,forced,native);
        int[][] r=Enumerable.Range(0,3).Select(i=>Enumerable.Range(0,42).ToArray()).ToArray();
        // Three Freeze instances on physical Sprite slot 2's Gnome. Each swap retains the pool.
        for(int slot=0;slot<3;slot++) { int old=r[2][slot]; r[2][slot]=r[slot][6]; r[slot][6]=old; }
        // Same caster: Fireball under Undine vs Salamando, retaining two native copies.
        int displaced=r[2][7]; r[2][7]=r[0][12]; r[0][12]=displaced;
        for(int slot=0;slot<3;slot++) forced.workingData.setIntArray(SpellShuffleAssignments.ROW_PREFIX+slot,r[slot]);
        var f=Copy(native); Apply(new CharacterClasses(),native,f,settings,forced); Apply(new SpellShuffle(),native,f,settings,forced);
        Check(Factor(Machine(f,0x400,6,0),1,0)==4,"Triple Freeze is not Earth");
        Check(Factor(Machine(f,0x400,12,1),4,0)==4,"Undine Fireball is not Water");
        Check(Factor(Machine(f,0x400,12,2),4,0)==2,"Salamando Fireball incorrectly uses Water");
        Check(Factor(Machine(f,0,12,1),4,0)==2,"Another physical caster inherited Fireball membership");
        // Queue source, not mutable menu or actual-ID inverse. Actual native queue emission.
        var queue=Machine(f,0x400,12,1); queue.Write(0x7E1844,0x1A00,2); queue.Write(0x7E1839,12,1);
        queue.Write(0x7E1846,1,1); queue.Write(0x7E1822,0x200,2); queue.Write(0x7E0201,0,1);
        queue.P=0x20; queue.Run(0xC0731F,true);
        Check(queue.Read(0x7E19F0,1)==12 && queue.Read(0x7E19F7,1)==1,"Native queue lost actual/source");
        queue.Write(0x7EE577,queue.Read(0x7E19F7,1),1); queue.Write(0x7E1846,7,1); queue.X=0x600;
        Check(Factor(queue,4,0)==4,"Later menu change displaced queued Water affinity");
        int weak=Damage(f,0x400,6,0,1,0), neutral=Damage(f,0x400,6,0,0,0), resist=Damage(f,0x400,6,0,0,1);
        Check(weak>neutral && neutral>resist && resist>0,"Native HP damage does not reflect affinity ordering");
        Check(Damage(f,0x400,6,0,1,0,3)<weak,"Native multi-target splitting changed");
        // Scaling hook composes downstream with the native HP path, not affinity selection.
        var scaled=(byte[])f.Clone(); settings.set("playerMagicDamage","fixed"); settings.set("playerMagicDamagePercent","50");
        Apply(new PlayerMagicDamage(),native,scaled,settings,forced);
        Check(Damage(scaled,0x400,6,0,1,0)==Math.Max(1,weak/2),"PlayerMagicDamage does not compose with destination affinity");
        // A separate valid permutation for the specifically requested Fireball/
        // Freeze examples; the earlier Triple Freeze fixture retains all 3 copies.
        int t=r[1][0]; r[1][0]=r[1][12]; r[1][12]=t;
        t=r[2][2]; r[2][2]=r[2][12]; r[2][12]=t;
        for(int slot=0;slot<3;slot++) forced.workingData.setIntArray(SpellShuffleAssignments.ROW_PREFIX+slot,r[slot]);
        var examples=Copy(native); Apply(new CharacterClasses(),native,examples,settings,forced); Apply(new SpellShuffle(),native,examples,settings,forced);
        Check(Factor(Machine(examples,0x200,12,0),1,0)==4,"Gnome Fireball is not Earth");
        Check(Factor(Machine(examples,0x400,6,2),8,0)==4,"Salamando Freeze is not Fire");
        Check(Factor(Machine(examples,0x400,6,0),8,0)==2,"Gnome Freeze inherited other same-ID cast's Fire affinity");
        var pending=Machine(examples,0x200,12,0);
        pending.Write(0x7EE570,6,1); pending.Write(0x7EE577,2,1);
        Check(Factor(pending,1,0)==4,"Simultaneous Sprite cast replaced Girl source");
        pending.Write(0x7E0383,0x400,2); pending.Write(0x7E03DC,6*64,2); pending.X=0x800;
        Check(Factor(pending,8,0)==4,"Simultaneous Girl cast replaced Sprite source");
        return "PASS: "+count+" generated/native affinity, duplicate, caster, queue, enemy, support, RNG and damage-scaling assertions.";
    }
}
