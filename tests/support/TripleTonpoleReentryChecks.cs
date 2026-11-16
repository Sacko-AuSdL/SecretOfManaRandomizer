using System;
using System.Collections.Generic;
using System.Linq;
using SoMRandomizer.config.settings;
using SoMRandomizer.processing.common;
using SoMRandomizer.processing.hacks.openworld;
using SoMRandomizer.processing.openworld;
using SoMRandomizer.processing.openworld.randomization;

// Focused event interpreter, not a SNES emulator. Executes emitted scripts and
// real prize payloads; native heal/orb/victory subroutines are counted boundaries.
public static class TripleTonpoleReentryChecks
{
    static int checks;
    static void Check(bool value, string message) { checks++; if (!value) throw new Exception(message); }

    sealed class Machine
    {
        readonly byte[] original;
        readonly RandoContext context;
        public byte[] Flags = new byte[256];
        public int[] Writes = new int[256];
        public List<int> Maps = new List<int>();
        public List<int> Doors = new List<int>();
        public List<int> Items = new List<int>();
        public int Gold, MagicWrites, Orbs, Victories, Dialogues;
        public Machine(byte[] rom, RandoContext ctx) { original = rom; context = ctx; }
        public void Door(int id)
        {
            Doors.Add(id);
            Maps.Add(context.replacementDoors.ContainsKey(id)
                ? context.replacementDoors[id].getTargetMap()
                : VanillaDoorUtil.getDoor(original, id).getTargetMap());
        }
        public void Enter()
        {
            ushort trigger = VanillaMapUtil.getTriggers(context.outputRom, 275)[1];
            if (trigger >= 0x800) Door(trigger - 0x800); else Run(trigger);
            int map = Maps.Last();
            if (map == 500) Run(0x6D3);
            else if (map == 277) Run(0x232);
            else throw new Exception("Unexpected entrance destination.");
        }
        public void Run(int id)
        {
            int pc = 0;
            var stack = new Stack<Tuple<int,int>>();
            for (int step = 0; step < 10000; step++)
            {
                if (id == 0) return;
                var bytes = context.replacementEvents.ContainsKey(id)
                    ? context.replacementEvents[id] : VanillaEventUtil.getVanillaEvent(original, id);
                int op = bytes[pc++];
                if (op == 0) return; // END terminates the whole event, including JSR callers.
                if (op == 2)
                {
                    if (stack.Count == 0) return;
                    var frame = stack.Pop(); id = frame.Item1; pc = frame.Item2;
                }
                else if (op == 0x42)
                {
                    int flag = bytes[pc++], range = bytes[pc++];
                    if (Flags[flag] < (range >> 4) || Flags[flag] > (range & 15)) pc += 2;
                }
                else if (op >= 0x10 && op <= 0x17) { id = ((op-0x10)<<8) | bytes[pc]; pc = 0; }
                else if (op >= 0x18 && op <= 0x1B) Door(((op-0x18)<<8) | bytes[pc++]);
                else if (op >= 0x20 && op <= 0x27)
                {
                    int target = ((op-0x20)<<8) | bytes[pc++];
                    if (target == 0x500) Orbs++;
                    else if (target == 0x784) Victories++;
                    else if (target != 0x41B) { stack.Push(Tuple.Create(id,pc)); id = target; pc = 0; }
                }
                else if (op == 0x29) { int f=bytes[pc++]; Flags[f]=(byte)((Flags[f]+1)&15); Writes[f]++; }
                else if (op == 0x30) { int f=bytes[pc++]; Flags[f]=bytes[pc++]; Writes[f]++; }
                else if (op == 0x1E) Items.Add(bytes[pc++]);
                else if (op == 0x36) { Gold += bytes[pc] | (bytes[pc+1]<<8); pc += 2; }
                else if (op == 0x39) { MagicWrites++; pc += 3; }
                else if (op == 0x40) pc += 4;
                else if (op == 0x28 || op == 0x2F || op == 0x1F) pc++;
                else if (op == 0x50 || op == 0x52) Dialogues++;
                else if (op == 0x06 || op == 0x0A || op == 0x51 || op >= 0x7F) { }
                else throw new Exception("Unsupported emitted opcode " + op.ToString("X2") + " in " + id.ToString("X3"));
            }
            throw new Exception("Event did not terminate.");
        }
        public Machine SaveReload()
        {
            // Native saves persist all 256 CFxx flag nibbles in 128 bytes.
            // SRAM/continue-door engine execution still needs a Mesen check.
            var packed = new byte[128];
            for(int i=0;i<128;i++) packed[i]=(byte)((Flags[i*2]&15)|((Flags[i*2+1]&15)<<4));
            var loaded = new Machine(original,context);
            for(int i=0;i<128;i++) { loaded.Flags[i*2]=(byte)(packed[i]&15); loaded.Flags[i*2+1]=(byte)(packed[i]>>4); }
            loaded.Items.AddRange(Items); loaded.Gold=Gold; loaded.MagicWrites=MagicWrites;
            loaded.Writes=(int[])Writes.Clone(); loaded.Orbs=Orbs; loaded.Victories=Victories;
            return loaded;
        }
    }

    static List<PrizeItem> Prizes(RandoSettings settings, RandoContext c)
    {
        foreach(string key in new[] {
            OpenWorldCharacterSelection.BOY_EXISTS, OpenWorldCharacterSelection.GIRL_EXISTS,
            OpenWorldCharacterSelection.SPRITE_EXISTS, OpenWorldCharacterSelection.START_WITH_BOY,
            OpenWorldCharacterSelection.START_WITH_GIRL, OpenWorldCharacterSelection.START_WITH_SPRITE,
            OpenWorldClassSelection.GIRL_MAGIC_EXISTS, OpenWorldClassSelection.SPRITE_MAGIC_EXISTS })
            c.workingData.setBool(key,true);
        foreach(string key in new[] {
            OpenWorldCharacterSelection.BOY_IN_LOGIC, OpenWorldCharacterSelection.GIRL_IN_LOGIC,
            OpenWorldCharacterSelection.SPRITE_IN_LOGIC, OpenWorldCharacterSelection.START_SOLO })
            c.workingData.setBool(key,false);
        c.workingData.set(OpenWorldCharacterSelection.STARTING_CHARACTER,"boy");
        c.workingData.setInt(StartingWeaponRandomizer.BOY_START_WEAPON_INDEX,0);
        c.workingData.setInt(StartingWeaponRandomizer.GIRL_START_WEAPON_INDEX,1);
        c.workingData.setInt(StartingWeaponRandomizer.SPRITE_START_WEAPON_INDEX,2);
        var locations = Enumerable.Range(0,200).Select(i=>new PrizeLocation("test "+i,0x581,0,new string[0],new string[0],1)).ToList();
        return OpenWorldPrizes.getForSelectedOptions(settings,c,locations);
    }

    static void Install(RandoContext c, RandoSettings settings, List<byte> template, PrizeItem a, PrizeItem b)
    {
        c.replacementEvents[0x581]=new List<byte>(template);
        var placements = new Dictionary<PrizeLocation,PrizeItem>();
        placements.Add(new PrizeLocation("undine item 1 (spells)",0x581,0,new string[0],new string[0],1),a);
        placements.Add(new PrizeLocation("undine item 2 (javelin)",0x581,1,new string[0],new string[0],1),b);
        OpenWorldResultInjector.injectRandomization(c.outputRom,placements,settings,c);
    }

    static void ClearedEntry(Machine m)
    {
        int orbs=m.Orbs, victories=m.Victories; byte[] flags=(byte[])m.Flags.Clone();
        m.Maps.Clear(); m.Doors.Clear(); m.Enter();
        Check(m.Maps.SequenceEqual(new[]{277}) && m.Doors.SequenceEqual(new[]{0x147}),"Completed source portal visited the Ice/private arena.");
        Check(m.Orbs==orbs && m.Victories==victories && m.Flags.SequenceEqual(flags),"Re-entry changed progression/repeated boss reward.");
    }

    public static string Run(byte[] original, RandoContext trio, RandoSettings settings, RandoContext normal, RandoSettings normalSettings)
    {
        var template=new List<byte>(trio.replacementEvents[0x581]);
        var normalTemplate=new List<byte>(normal.replacementEvents[0x581]);
        Check(template.SequenceEqual(normalTemplate),"Trio changed upstream Undine prize handling.");
        Check(VanillaMapUtil.getTriggers(normal.outputRom,275).SequenceEqual(VanillaMapUtil.getTriggers(original,275)),"Normal boss source portals changed.");
        var prizes=Prizes(settings,trio);
        Prizes(normalSettings,normal);
        var pairs = new[] {
            new[]{prizes.Single(p=>p.prizeName=="gold tower key"),prizes.Single(p=>p.prizeName=="midge mallet")},
            new[]{prizes.First(p=>p.prizeName.StartsWith("GP ")),prizes.Single(p=>p.prizeName=="undine spells")},
            new[]{prizes.First(p=>p.prizeName=="nothing"),prizes.First(p=>p.prizeName=="nothing")} };
        foreach(var pair in pairs)
        {
            Install(trio,settings,template,pair[0],pair[1]);
            Install(normal,normalSettings,normalTemplate,pair[0],pair[1]);
            Check(trio.replacementEvents[0x581].SequenceEqual(normal.replacementEvents[0x581]),"Boss choice changed injected rewards.");
            var m=new Machine(original,trio);
            m.Enter(); Check(m.Maps.SequenceEqual(new[]{500}) && m.Flags[0xE3]==0,"First entrance no longer starts the trio.");
            for(int death=1;death<=3;death++)
            {
                m.Run(0x6D2);
                Check(m.Flags[0xE3]==death && m.Orbs==(death==3?1:0),"Transformed deaths completed too soon or not once.");
            }
            Check(m.Flags[0xA0]==1 && m.Victories==1 && m.Maps.Last()==277,"First completion/return failed.");
            m.Run(0x6D2); Check(m.Orbs==1,"Duplicate death granted another fixed orb.");
            ClearedEntry(m);
            m=m.SaveReload(); ClearedEntry(m); // Completion saved before any NPC prize is taken.
            m.Run(0x581);
            int items=m.Items.Count, gold=m.Gold, magic=m.MagicWrites;
            var flagsAfter=(byte[])m.Flags.Clone(); var writesAfter=(int[])m.Writes.Clone();
            if(pair[0].gotItemEventFlag!=0)
            {
                Check(m.Flags[pair[0].gotItemEventFlag]==1 && m.Flags[pair[1].gotItemEventFlag]==1,"First rewards did not set both collected flags.");
                Check(m.Writes[pair[0].gotItemEventFlag]==1 && m.Writes[pair[1].gotItemEventFlag]==1,"First reward granted more than once.");
            }
            else Check(items==0 && gold==0 && magic==0,"Nothing payload granted a real reward.");
            for(int visit=0;visit<3;visit++)
            {
                ClearedEntry(m); m.Run(0x581);
                Check(m.Items.Count==items && m.Gold==gold && m.MagicWrites==magic,"Repeated interaction duplicated a reward.");
                Check(m.Flags.SequenceEqual(flagsAfter) && m.Writes.SequenceEqual(writesAfter),"Repeated dialogue changed a collection/progression flag.");
            }
            m=m.SaveReload(); ClearedEntry(m); m.Run(0x581);
            Check(m.Items.Count==items && m.Gold==gold && m.MagicWrites==magic && m.Flags.SequenceEqual(flagsAfter),"Saved rewards did not remain collected.");
            var n=new Machine(original,normal);
            n.Enter(); Check(n.Maps.SequenceEqual(new[]{277}),"Normal boss entrance redirected.");
            n.Run(0x233); n.Run(0x581);
            n.Enter(); n.Run(0x581); n=n.SaveReload(); n.Enter(); n.Run(0x581);
            Check(n.Items.Count==items && n.Gold==gold && n.MagicWrites==magic,"Normal-boss reward behavior differs.");
        }
        trio.replacementEvents[0x581]=template; normal.replacementEvents[0x581]=normalTemplate;
        return "PASS: "+checks+" focused re-entry/reward assertions; real injected prizes, nothing dialogue, completion/reward save-flag round-trips, and normal boss control (no emulator claims).";
    }
}
