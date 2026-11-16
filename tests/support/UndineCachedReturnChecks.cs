using System;
using System.Linq;
using System.Reflection;
using SoMRandomizer.config.settings;
using SoMRandomizer.processing.common;
using SoMRandomizer.processing.hacks.common.qol;
using SoMRandomizer.processing.openworld.events;
using SoMRandomizer.util;

// Executes native cache, SRAM continuation, collision-request and door decoder
// instructions. Frame scheduling, rendering and SRAM checksums are not emulated.
public static class UndineCachedReturnChecks
{
    static int checks;
    static void Check(bool ok, string why) { checks++; if (!ok) throw new Exception(why); }
    static void Until(SpellShuffleMachine m, int start, int stop)
    {
        m.Stops.Add(stop); m.Run(start); m.Stops.Clear();
    }
    static void DecodeDoor(SpellShuffleMachine m, int door)
    {
        m.P=0; m.X=door*4;
        Until(m,0xC1E7DF,0xC1E800);
    }
    static void CachePriorMap(SpellShuffleMachine m, int map)
    {
        m.P=0; m.Write(0x7E00DC,map,2);
        Until(m,0xC1CC81,0xC1CC86); // native current map -> CD08
        m.Run(0xC1CBD2); // native CD00..CDFF -> CE00..CEFF
        Check(m.Read(0x7ECE08,2)==map,"Native room cache was not captured.");
    }
    static void CheckLookup(SpellShuffleMachine m, int current, int next)
    {
        Until(m,0xC0C481,0xC0C491);
        Check(m.Read(0x7E001D,2)==current && (m.A&65535)==next,
            "Unexpected native object pointers.");
    }
    static void NativeLifecycle(byte[] rom, bool reload, int actor)
    {
        var m=new SpellShuffleMachine(rom);
        CachePriorMap(m,0x115); DecodeDoor(m,0x146);
        Check(m.Read(0x7E00DC,2)==0x116,"Wrong NPC room entry.");
        if(reload)
        {
            // Real vanilla SRAM continuation writer/reader, including old saves.
            m.Write(0x7EA25A,0x146,2); m.X=0;
            m.Run(0xC7579F,true);
            int saved=m.Read(0x306000,2);
            Check(saved==0x146,"Native save did not retain the NPC room door.");
            m=new SpellShuffleMachine(rom); // volatile cache is NOT in the save
            m.Write(0x306000,saved,2); m.X=0;
            m.Run(0xC7592E,true);
            Until(m,0xC00105,0xC00109);
            Check(m.A==0x146,"Native load did not request the saved door.");
            CachePriorMap(m,0); DecodeDoor(m,saved);
            Check(m.Read(0x7E00DC,2)==0x116,"Reload did not reach Undine.");
        }
        // Actual old tile collision requests the cached return for every actor.
        m.P=0x20; m.X=actor;
        m.Write(0x7E0001,rom[0xB0001+4*rom[0xB0400+10*384+0xB4]],1);
        Until(m,0xC0D688,0xC0D695);
        Check(m.Read(0x7EE04A+actor,1)==0x80,"Original cached-exit request did not reproduce.");
        // This reproduces the former native failure, without entering its hang.
        m.Run(0xC1CCF5);
        Check(m.Read(0x7E00DC,2)==(reload?0:0x115),"Wrong cached-return result.");
        CheckLookup(m,reload?0x9000:0xC738,reload?0x9000:0xC748);

        // Fixed exit collision has no cached-return request, for any party actor.
        m.P=0x20; m.X=actor;
        m.Write(0x7E0001,rom[0xB0001+4*rom[0xB0400+10*384+0x77]],1);
        m.Write(0x7EE04A+actor,0,1);
        Until(m,0xC0D688,0xC0D695);
        Check(m.Read(0x7EE04A+actor,1)==0,"Fixed exit still requests cached return.");
        m.Write(0x7E00DC,0x116,2);
        m.Write(0x7ECF50,0x31,1); // A0/A1 packed progression flags, sentinel
        m.Write(0x7ECF1B,0x10,1); // item flags, sentinel
        // Both existing map-trigger entries are Door $147, not a new event.
        int door=VanillaMapUtil.getTriggers(rom,0x116)[actor==0?0:1]-0x800;
        DecodeDoor(m,door);
        Check(m.Read(0x7E00DC,2)==0x115 && m.Read(0x7E00DE,1)==23,
            "Fixed exit did not decode native Door 147.");
        Check(m.Read(0x7E00DF,2)==0xA012 && m.Read(0x7E00E8,1)==0,
            "Fixed exit retained cached-camera semantics.");
        CheckLookup(m,0xC738,0xC748);
        Check(m.Read(0x7ECF50,1)==0x31 && m.Read(0x7ECF1B,1)==0x10,
            "Room return changed persistent rewards/progression.");
        CachePriorMap(m,0x115); DecodeDoor(m,0x146);
        Check(m.Read(0x7E00DC,2)==0x116,"NPC room re-entry failed.");
        DecodeDoor(m,0x147);
        Check(m.Read(0x7E00DC,2)==0x115,"Repeated exit failed.");
    }
    static void Geometry(byte[] original, byte[,] fixedPiece)
    {
        var before=VanillaMapUtil.loadVanillaMapPiece(original,0x34);
        Check(fixedPiece.GetLength(0)==40 && fixedPiece.GetLength(1)==50,"Room size changed.");
        for(int y=0;y<50;y++) for(int x=0;x<40;x++)
            Check(fixedPiece[x,y]==((y==34 && (x==14 || x==15))?0x77:before[x,y]),
                "Unrelated NPC-room tile changed.");
        Check(before[14,34]==0xB4 && before[15,34]==0xB4,"Reproduction lost its cached exit.");
        var tiles=VanillaTilesetUtil.DecodeTileset16(VanillaTilesetUtil.getCompressedVanillaTileset16(original,10));
        Check(tiles.Tiles[0x77].Tiles.Select(t=>t.ToBinary()).SequenceEqual(
            tiles.Tiles[0xB4].Tiles.Select(t=>t.ToBinary())),"Exit graphics changed.");
        Check(original[0xB0001+4*original[0xB0400+10*384+0xB4]]==0x10,
            "Original exit is not a cached return.");
        Check(original[0xB0001+4*original[0xB0400+10*384+0x77]]==0x80,
            "Replacement is not a native door tile.");
        int cached=0xB0000+4*original[0xB0400+10*384+0xB4];
        int direct=0xB0000+4*original[0xB0400+10*384+0x77];
        Check(original[cached]==original[direct] && original[cached+2]==original[direct+2]
            && original[cached+3]==original[direct+3],"Exit collision changed beyond return/door semantics.");
    }
    public static void Run(byte[] original)
    {
        byte[] snapshot=(byte[])original.Clone(), rom=new byte[0x400000];
        Array.Copy(original,rom,original.Length);
        var common=new CommonSettings(); common.set("mode","open");
        var settings=new OpenWorldSettings(common);
        var context=new RandoContext(); context.randomFunctional=new Random(41);
        context.originalRom=original; context.outputRom=rom;
        context.workingData.set("openWorldGoalShortName","manabeast");
        typeof(OpenWorldSupportingMapChanges).GetMethod("process",BindingFlags.Instance|BindingFlags.NonPublic)
            .Invoke(new OpenWorldSupportingMapChanges(),new object[]{original,rom,"cached-return",settings,context});
        Check(context.replacementMapPieces.Count==1 && context.replacementMapPieces.ContainsKey(0x34),
            "Unrelated map piece replacement.");
        Geometry(original,SomMapCompressor.DecodeMap(context.replacementMapPieces[0x34].ToArray()));
        Check(context.randomFunctional.Next()==new Random(41).Next(),"Correction consumed RNG.");
        for(int map=0;map<500;map++)
        {
            var refs=VanillaMapUtil.getMapPieceReference(original,map);
            Check(!refs.bgPieces.Concat(refs.fgPieces).Any(p=>p.pieceIndex==0x34) || map==278,
                "Piece 34 is shared by another native map.");
        }
        Check(VanillaMapUtil.getTriggers(rom,278).SequenceEqual(new ushort[]{0x947,0x947}),"Exit triggers changed.");
        Check(original.SequenceEqual(snapshot),"Base ROM mutated.");
        foreach(int door in new[]{0x146,0x147})
            Check(rom.Skip(0x83000+door*4).Take(4).SequenceEqual(original.Skip(0x83000+door*4).Take(4)),"Native door changed.");
        // Autosave really accepts Door146. Save/load is not a manual teleport artifact.
        context.workingOffset=0x300000;
        typeof(Autosave).GetMethod("process",BindingFlags.Instance|BindingFlags.NonPublic)
            .Invoke(new Autosave(),new object[]{original,rom,"cached-return",settings,context});
        var save=new SpellShuffleMachine(rom); save.A=0x146; save.P=0;
        save.Write(0x7EE000,1,1); save.Write(0x7EE182,100,2);
        save.Stops.Add(0xC755D6);
        save.Run(rom[0x1E7D7]|rom[0x1E7D8]<<8|rom[0x1E7D9]<<16);
        Check(save.Visits.Contains(0xC755D6) && save.Read(0x7EA25A,2)==0x146,"NPC-room autosave no longer reproduced.");
        foreach(bool reload in new[]{false,true}) foreach(int actor in new[]{0,0x200,0x400})
            NativeLifecycle(rom,reload,actor);
        Console.WriteLine("PASS: Undine cached-return checks ("+checks+" assertions; native instructions, old-save continuation and geometry).");
    }
    public static void FinalRom(byte[] original, byte[] rom)
    {
        // The expanded piece table installed at native CC79, not the old pointer table.
        Check(rom[0xCC82]==0xBF,"Expanded map-piece table loader missing.");
        int table=rom[0xCC83]|rom[0xCC84]<<8|rom[0xCC85]<<16;
        int at=table-0xC00000+0x34*3;
        int piece=(rom[at]|rom[at+1]<<8|rom[at+2]<<16)-0xC00000;
        var compressed=rom.Skip(piece).Take(0x10000-(piece&65535)).ToArray();
        Geometry(original,SomMapCompressor.DecodeMap(compressed));
        Check(VanillaMapUtil.getTriggers(rom,278).SequenceEqual(new ushort[]{0x947,0x947}),"Final exit trigger mismatch.");
        foreach(int door in new[]{0x146,0x147})
            Check(rom.Skip(0x83000+door*4).Take(4).SequenceEqual(original.Skip(0x83000+door*4).Take(4)),"Final native door changed.");
        foreach(bool reload in new[]{false,true}) NativeLifecycle(rom,reload,0x200);
        Console.WriteLine("PASS: final ROM piece, door, object-pointer and reload/return verification.");
    }
}
