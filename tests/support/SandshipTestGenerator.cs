using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using SoMRandomizer.config.settings;
using SoMRandomizer.processing;
using SoMRandomizer.processing.common;
using SoMRandomizer.processing.openworld;
using SoMRandomizer.processing.openworld.events;
using SoMRandomizer.processing.openworld.randomization;

// Test-only capture, never a production/bootstrap path.
public sealed class SandshipTestGenerator : OpenWorldGenerator
{
    public static RandoContext LastContext;
    public static List<PrizeLocation> LastLocations;
    public SandshipTestGenerator()
    {
        var hacks = (List<RandoProcessor>)typeof(RomGenerator).GetField("commonHacks",
            BindingFlags.Instance | BindingFlags.NonPublic).GetValue(this);
        hacks.RemoveAll(p => p.GetType().Name == "WeaponPowerCalculator");
    }
    protected override void generate(byte[] original, byte[] output, string seed,
        RandoSettings settings, RandoContext context)
    {
        LastContext = context;
        base.generate(original, output, seed, settings, context);
        LastLocations = OpenWorldLocations.getForSelectedOptions(settings,context);
    }
    private static void Check(bool yes, string message)
    {
        if (!yes) throw new Exception(message);
    }
    private static bool Same(byte[] a, byte[] b) { return a.SequenceEqual(b); }
    public static void CheckNative(byte[] original)
    {
        byte[] output = new byte[0x400000]; Array.Copy(original,output,original.Length);
        var settings = new OpenWorldSettings(new CommonSettings());
        var context = new RandoContext(); context.randomFunctional = new Random(12345);
        context.replacementEvents[0x112] = new List<byte> {0};
        int edited = VanillaMapUtil.getTriggerOffset(output,143); output[edited] = 0x37;
        byte[] before = (byte[])output.Clone();
        typeof(SandshipEvents).GetMethod("process",BindingFlags.Instance | BindingFlags.NonPublic)
            .Invoke(new SandshipEvents(),new object[] {original,output,"sandship",settings,context});
        Check(VanillaMapUtil.getTriggers(original,89).Contains(0xA3F),"Kakkara south door missing.");
        Check(VanillaMapUtil.getTriggers(original,69).Contains(0x9EA),"First desert south door missing.");
        var old = VanillaMapUtil.getTriggers(before,92); var changed = VanillaMapUtil.getTriggers(output,92);
        Check(changed.Count==old.Count+3 && old.SequenceEqual(changed.Take(old.Count))
            && changed.Skip(old.Count).All(v => v==SandshipEvents.ENTRANCE_EVENT),"South trigger order incorrect.");
        for (int map=0; map<512; map++)
        {
            // 298 is the terminal first-pool boundary. Its unused FF tail runs into
            // unrelated tables before pool 2; no walk-on/special/tile triggers use it.
            if (map!=92 && map!=298)
                Check(VanillaMapUtil.getTriggers(before,map).SequenceEqual(VanillaMapUtil.getTriggers(output,map)),
                    "Another live trigger sequence changed: "+map);
            var refs = VanillaMapUtil.getMapPieceReference(original,map);
            Check(!refs.bgPieces.Concat(refs.fgPieces).Any(p => p.pieceIndex==SandshipEvents.DESERT_BG_PIECE
                || p.pieceIndex==SandshipEvents.DESERT_FG_PIECE),"Allocated piece used by native map.");
        }
        Check(!VanillaMapUtil.getHeader(original,298).getWalkonEventEnabled()
            && !VanillaMapUtil.getHeader(original,298).getSpecialEventEnabled(),"Terminal span has special triggers.");
        var bg = SomMapCompressor.DecodeMap(context.replacementMapPieces[SandshipEvents.DESERT_BG_PIECE].ToArray());
        var fg = SomMapCompressor.DecodeMap(context.replacementMapPieces[SandshipEvents.DESERT_FG_PIECE].ToArray());
        var nativeBg = VanillaMapUtil.loadVanillaMapPiece(original,0x15B);
        var nativeFg = VanillaMapUtil.loadVanillaMapPiece(original,0x15C);
        var passage = VanillaMapUtil.loadVanillaMapPiece(original,0x151);
        Check(bg.GetLength(0)==48 && bg.GetLength(1)==48,"Desert dimensions changed.");
        for (int y=0; y<48; y++) for (int x=0; x<48; x++)
        {
            bool south = x>=18 && x<25 && y>=37;
            Check(bg[x,y]==(south ? passage[x-18,y-37] : nativeBg[x,y]),"Unrelated BG terrain changed.");
            Check(fg[x,y]==(south ? 1 : nativeFg[x,y]),"Unrelated FG terrain changed.");
        }
        Check(bg[20,41]==0xB6 && bg[21,41]==0xB6 && bg[22,41]==0xB6,"Native doorway tile lost.");
        Check(Same(original.Skip(0x8364C).Take(4).ToArray(),output.Skip(0x8364C).Take(4).ToArray()),"Boss door changed.");
        Check(Same(output.Skip(0x83650).Take(4).ToArray(),new byte[] {0x5C,0x2A,0x4E,0x80}),"Return door incorrect.");
        Check(Same(original.Skip(0x88FBE).Take(0x25).ToArray(),output.Skip(0x88FBE).Take(0x25).ToArray()),"Private refs changed.");
        Check(Same(original.Skip(0x8E0B5).Take(0x1E21).ToArray(),output.Skip(0x8E0B5).Take(0x1E21).ToArray()),"C8 code changed.");
        Check(context.replacementEvents[0x112].SequenceEqual(new byte[] {0}),"Mantis event changed.");
        foreach (int evt in new[] {0x66A,0x543,0x42D,0x553})
            Check(!context.replacementEvents.ContainsKey(evt),"Special boss event touched.");
        Check(context.replacementMapPieces.Keys.Count==2,"Unexpected piece allocation.");
        CheckEvents(output,context);
    }
    private static void CheckEvents(byte[] output,RandoContext context)
    {
        Check(context.replacementEvents[0x28A].SequenceEqual(new byte[] {0x42,0x28,0xFF,0x12,0xA8,0x19,0x93,0x27,4,0}),"Entry order changed.");
        Check(context.replacementEvents[0x2A1].SequenceEqual(new byte[] {0x42,0x28,0xFF,0x10,0,0x25,4,0x30,0x28,15,0x19,0xFF,0x27,0xC2,0}),"Death sequence changed.");
        var actors = VanillaMapUtil.getObjects(output,91);
        Check(actors[0].getSpecies()==0xB9 && actors[0].getEvent()==0x2A2,"Morie identity changed.");
        Check(actors[1].getSpecies()==0xB8 && actors[1].getEvent()==0x2A3,"Meria identity changed.");
        foreach (int i in new[] {0,1,5})
            Check(actors[i].getEventVisFlag()==0x28 && actors[i].getEventVisMinimum()==15
                && actors[i].getEventVisMaximum()==15,"Crew available before victory.");
        var boss = VanillaMapUtil.getObjects(output,340)[0];
        Check(boss.getEvent()==0x2A1 && boss.getEventVisMinimum()==14 && boss.getEventVisMaximum()==14,"Respawn guard missing.");
        Check(context.replacementEvents[0x2A2].Take(5).SequenceEqual(new byte[] {0x42,0x28,14,0x10,0}),"Hint clear guard missing.");
        Check(!context.replacementEvents[0x2A2].Contains((byte)0x30),"Hint changes state.");
        var pool = VanillaBossMaps.MECHRIDER1.allSupportedBosses;
        Check(TripleTonpoleBossArenaRedirect.getOpenWorldRandomPool(VanillaBossMaps.MECHRIDER1).SequenceEqual(pool),
            "Sandship redirect wrapper changed the existing pool.");
        Check(pool.Length==23 && pool.Distinct().Count()==23 && pool.Contains((byte)0x57),"Boss pool changed/duplicated.");
        foreach (byte id in new byte[] {0x58,0x61,0x6D,0x6E,0x7F,0x80})
            Check(!pool.Contains(id),"Unsupported special boss admitted.");
    }

    // Exercise generated item-check control flow, not a separate hand-written reward system.
    // Text bytes and existing commands are skipped by their actual widths. Jump $396 ends an already-owned check.
    public static int RunCaptain(byte[] ev,int clear,byte[] flags)
    {
        flags[0x28]=(byte)clear; int gold=0;
        for (int pc=0; pc<ev.Length;)
        {
            byte op=ev[pc++];
            if (op==0) break;
            if (op==0x42)
            {
                byte flag=ev[pc++],range=ev[pc++],jump=ev[pc++],target=ev[pc++];
                if (flags[flag]>=range/16 && flags[flag]<=(range&15))
                {
                    Check(jump==0x10 && target==0 || jump==0x13 && target==0x96,"Unexpected check branch.");
                    break;
                }
            }
            else if (op==0x36) { gold+=ev[pc]+256*ev[pc+1]; pc+=2; }
            else if (op==0x1E) { gold++; pc++; }
            else if (op==0x30) { flags[ev[pc]]=ev[pc+1]; gold++; pc+=2; }
            else if (op==0x29) flags[ev[pc++]]++;
            else if (op==0x28) pc++;
            else if (op==0x40) pc+=3; // Standard reward sound.
            else Check(op>=0x7F || op==0x50 || op==0x51 || op==0x52,"Unexpected prize opcode: "+op.ToString("X2"));
        }
        return gold;
    }
}
