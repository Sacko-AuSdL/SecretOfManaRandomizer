using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Reflection;
using SoMRandomizer.config.settings;
using SoMRandomizer.processing;
using SoMRandomizer.processing.common;
using SoMRandomizer.processing.openworld;
using SoMRandomizer.processing.openworld.events;
using SoMRandomizer.processing.hacks.openworld;

// Focused map/serialized-ROM and native pointer-loader checks, not a game emulator.
public static class UpperLandOrbAccessibilityChecks
{
    static void Check(bool ok, string why) { if (!ok) throw new Exception(why); }
    static void Apply(byte[] original, RandoContext c)
    {
        if (c.outputRom == null) { c.outputRom = new byte[0x400000]; Array.Copy(original, c.outputRom, original.Length); }
        typeof(OpenWorldSupportingMapChanges).GetMethod("makeUpperLandWeaponOrbAccessible",
            BindingFlags.Static | BindingFlags.NonPublic).Invoke(null, new object[] { original, c.outputRom, c });
    }
    static RandoContext Context(int type, int value)
    {
        var c = new RandoContext();
        c.randomFunctional = new Random(817);
        c.workingData.setInt("crystalOrbRequirementsResolved", 1);
        c.workingData.setInt("crystalOrbRequirementType41", type);
        c.workingData.setInt("crystalOrbRequirementValue41", value);
        return c;
    }
    static byte[,] Piece(byte[] original, RandoContext c, int id)
    {
        return c.replacementMapPieces.ContainsKey(id)
            ? SomMapCompressor.DecodeMap(c.replacementMapPieces[id].ToArray())
            : VanillaMapUtil.loadVanillaMapPiece(original, id);
    }
    public static void Geometry(byte[] original, RandoContext c)
    {
        int changed = 0;
        foreach (int id in new[] { 0x11A, 0x120 })
        {
            var before = VanillaMapUtil.loadVanillaMapPiece(original, id);
            var after = Piece(original, c, id);
            var floor = VanillaMapUtil.loadVanillaMapPiece(original, id == 0x11A ? 0x115 : 0x116);
            int ox = id == 0x11A ? 21 : 20, oy = id == 0x11A ? 57 : 56;
            for (int y = 0; y < before.GetLength(1); y++) for (int x = 0; x < before.GetLength(0); x++)
            {
                byte expected = id == 0x11A && x == 7 && y >= 4 ? (byte)0x8F
                    : id == 0x11A && y < 4 ? before[x,y] : floor[x + ox, y + oy];
                Check(after[x,y] == expected, "Gate graphics/collision layout differs from scoped native underlay plus hedge.");
                if (before[x,y] != after[x,y]) changed++;
            }
        }
        var closed = Layer(original, c, 3, false); var fg = Layer(original, c, 3, true);
        var open = Layer(original, c, 4, false);
        Check(open.Cast<byte>().SequenceEqual(Layer(original, null, 4, false).Cast<byte>()), "Cleared map changed.");
        var west = Connected(original, closed, 11, 41);
        var east = Connected(original, closed, 36, 51);
        Check(west.Contains(27 + 62 * 48) && east.Contains(29 + 62 * 48), "Independent closed approaches cannot reach Orb.");
        if (west.Contains(29 + 62 * 48))
        {
            for (int y=53;y<67;y++) Console.WriteLine(y+" "+String.Concat(Enumerable.Range(16,20).Select(x=>Free(original,closed,x,y)?".":"#")));
        }
        Check(!west.Contains(29 + 62 * 48) && !east.Contains(27 + 62 * 48), "Closed gate bypassed.");
        Check(Connected(original, open, 11, 41).Contains(36 + 51 * 48), "Activated gate does not open.");
        foreach (int x in new[] { 27, 29 }) foreach (int y in new[] { 62, 63 })
        {
            Check(original.Skip(0xB0000 + original[0xB0400 + 384 + closed[x,y]] * 4).Take(4)
                .SequenceEqual(new byte[] {0x12,6,0,0}), "Approach is not full ordinary floor; connectivity alone is insufficient.");
            Check(original.Skip(0xB0000 + original[0xB0400 + 384 + 192 + fg[x,y]] * 4).Take(4)
                .SequenceEqual(new byte[] {0x12,6,0,0}), "Foreground obstructs an attack approach.");
        }
        foreach (int y in new[] { 61, 62, 63, 64 }) Check(!Free(original, closed, 28, y), "Hedge endpoint/gate is not sealed.");
        Check(changed > 1, "Negative control failed to reject the one-tile Fix1 layout.");
    }
    static bool Free(byte[] r, byte[,] bg, int x, int y)
    {
        if (x < 0 || x >= 48 || y < 0 || y >= 72 || bg[x, y] >= 192) return false;
        int collision = r[0xB0400 + 384 + bg[x, y]];
        return (r[0xB0000 + collision * 4] & 1) == 0;
    }
    static HashSet<int> Connected(byte[] r, byte[,] bg, int x, int y)
    {
        var seen = new HashSet<int>(); var q = new Queue<int>(); q.Enqueue(x + y * 48);
        while (q.Count > 0)
        {
            int n = q.Dequeue(), xx = n % 48, yy = n / 48;
            if (!Free(r, bg, xx, yy) || !seen.Add(n)) continue;
            if (xx > 0) q.Enqueue(n - 1); if (xx < 47) q.Enqueue(n + 1);
            if (yy > 0) q.Enqueue(n - 48); if (yy < 71) q.Enqueue(n + 48);
        }
        return seen;
    }
    public static byte[,] Layer(byte[] r, RandoContext c, int flag, bool foreground)
    {
        var result = new byte[48, 72]; var refs = VanillaMapUtil.getMapPieceReference(r, 41);
        foreach (var p in foreground ? refs.fgPieces : refs.bgPieces)
        {
            if (p.eventVisibilityFlagId != 0 && (p.eventVisibilityFlagId != 0x20
                || flag < p.eventVisibilityValueLow || flag > p.eventVisibilityValueHigh)) continue;
            VanillaMapUtil.copyMapPieceData(c == null ? VanillaMapUtil.loadVanillaMapPiece(r, p.pieceIndex)
                : Piece(r, c, p.pieceIndex), result, p.xPos, p.yPos);
        }
        return result;
    }
    public static string Run(byte[] original)
    {
        var snapshot = (byte[])original.Clone();
        for (int weapon = 0; weapon < 8; weapon++)
        {
            var c = Context(1, weapon); Apply(original, c); Geometry(original, c);
            int at = VanillaMapUtil.getObjectOffset(original, 41) + 8;
            Check(c.outputRom.Skip(at).Take(2).SequenceEqual(original.Skip(at).Take(2))
                && c.outputRom[at + 2] == original[at + 2]
                && c.outputRom.Skip(at + 3).Take(5).SequenceEqual(original.Skip(at + 3).Take(5)),
                "Native Orb object changed.");
            Check(c.replacementMapPieces.Count == 2 && c.randomFunctional.Next() == new Random(817).Next(),
                "Unexpected map writer/RNG consumption.");
            Apply(original, c); Geometry(original, c); // idempotent, merges existing data
        }
        var magic = Context(0, 0x85); Apply(original, magic);
        var absent = new RandoContext(); Apply(original, absent);
        Check(magic.replacementMapPieces.Count == 0 && absent.replacementMapPieces.Count == 0,
            "Magic/inactive Orb geometry changed.");
        Check(magic.outputRom.Take(original.Length).SequenceEqual(original)
            && absent.outputRom.Take(original.Length).SequenceEqual(original), "Magic/inactive Orb object moved.");
        var merged = Context(1, 1); var a = VanillaMapUtil.loadVanillaMapPiece(original, 0x11A);
        a[0, 0] ^= 1; merged.replacementMapPieces[0x11A] = new List<byte>(SomMapCompressor.EncodeMap(a));
        merged.replacementMapPieces[0x34] = new List<byte> { 1, 2, 3 };
        Apply(original, merged);
        Check(Piece(original, merged, 0x11A)[0, 0] == a[0, 0]
            && merged.replacementMapPieces[0x34].SequenceEqual(new byte[] { 1, 2, 3 }),
            "Existing map edits were overwritten.");
        var conflict = Context(1, 1); a = VanillaMapUtil.loadVanillaMapPiece(original, 0x11A);
        a[7, 5] = 0; conflict.replacementMapPieces[0x11A] = new List<byte>(SomMapCompressor.EncodeMap(a));
        bool rejected = false; try { Apply(original, conflict); } catch (TargetInvocationException e)
        { rejected = e.InnerException is InvalidOperationException; }
        Check(rejected, "Conflicting ownership was overwritten.");
        for (int map = 0; map < 511; map++)
        {
            // Ignore non-map table entries: e.g. unused 243 starts in data,
            // not with the native FE/FF map-layer marker. Valid later maps
            // really do have reference blocks above $87000.
            int start = VanillaMapUtil.getPiecePlacementOffset(original, map);
            int end = VanillaMapUtil.getPiecePlacementOffset(original, map + 1);
            if (start >= end || start < 0x85400 || end > original.Length
                || (original[start] != 0xFE && original[start] != 0xFF)) continue;
            var refs = VanillaMapUtil.getMapPieceReference(original, map);
            Check(map == 41 || !refs.bgPieces.Concat(refs.fgPieces).Any(p => p.pieceIndex == 0x11A || p.pieceIndex == 0x120),
                "Edited piece shared with another map: " + map);
        }
        Javelin(original);
        Check(original.SequenceEqual(snapshot), "Base ROM mutated.");
        return "PASS: all eight weapon requirements; native Orb restored; two conditional pieces; BOTH native approaches reach full clear floor; closed/open gate preserved; Magic/inactive unchanged; ownership/merge/RNG guards.";
    }
    static void Javelin(byte[] original)
    {
        var c = Context(1, 7); Apply(original, c); Geometry(original, c);
        var settings = new OpenWorldSettings(new CommonSettings()); settings.set("crystalOrbWeaponBreaking", "weaponOnly");
        c.originalRom = original; c.workingOffset = 0x200000;
        c.replacementEvents[0x25A] = new List<byte> { 0x23,0x52,0x42,0x9A,0x13,0x12,0x5B,0 };
        new CrystalOrbWeaponBreaking().add(original, c.outputRom, "upperland-javelin", settings, c);
        foreach(bool west in new[]{false,true}) foreach(int player in new[]{0,0x200,0x400}) foreach(bool correct in new[]{false,true})
        {
            // Base-form weapon and an otherwise zeroed player record: no charge
            // levels or charged-attack setup. At the adjacent walkable tile the
            // ordinary projectile is within the native hook's 16px contact box.
            var m = new SpellShuffleMachine(c.outputRom){P=0,DB=0x7E,X=player,Y=player/8};
            int x=(west?27:29)*16+8,y=62*16+8,slot=player/8;
            m.Write(0x7E00DC,41,2);m.Write(0x7ECF10,0xA3,1);m.Write(0x7EE02C+player,1,1);
            m.Write(0x7EE1E8+player,(correct?7:5)*9,1);
            m.Write(0x7ED000+slot,correct?2:1,1);m.Write(0x7ED002+slot,x,2);m.Write(0x7ED004+slot,y,2);
            m.Write(0x7EE600,2,1);m.Write(0x7EE7E7,0x55,1);m.Write(0x7EE602,28*16+8,2);m.Write(0x7EE604,y,2);
            m.Stops.Add(0xC2C52E);m.Run(0xC2C526,true); // actual native coordinate preparation + projectile hook
            Check(m.Read(CustomRamOffsets.CRYSTAL_ORB_PENDING_STATE,1)==(correct?1:0),"Uncharged Javelin/wrong-projectile Upper Land contact failed.");
            Check(m.Read(0x7ECF10,1)==0xA3&&m.X==player&&m.Y==slot,"Projectile contact changed progression or native owner/slot.");
            if(correct)Check(m.Read(CustomRamOffsets.CRYSTAL_ORB_PENDING_MAP_16BIT,2)==41&&m.Read(CustomRamOffsets.CRYSTAL_ORB_PENDING_TARGET_16BIT,2)==0x600,"Projectile queued wrong Orb.");
        }
        Console.WriteLine("PASS both accepted walkable approaches: base-form uncharged Javelin native C2C526/C4C9/C529 contact; all physical slots; wrong Bow rejected; no premature progression writes. Live launch/animation remains Mesen verification.");
    }
    public static void VerifyClosedStartup(byte[] rom)
    {
        // Read the FINAL relocated initialization event, not a fabricated flag
        // state. All commands in this native Open World initializer set flags.
        Func<int,int> address = at => rom[at] | rom[at+1] << 8 | rom[at+2] << 16;
        int table = address(0x1E7A3) - 0xC00000;
        int pc = address(table + 0x107 * 3) - 0xC00000, gate = -1;
        for (int commands=0; commands<256; commands++)
        {
            int op=rom[pc++];
            if(op==2) { Check(gate==3,"Fresh diagnostic pre-clears the gate or hides the Orb."); return; }
            Check(op==0x30,"Initialization needs a real command parser for the new opcode.");
            int flag=rom[pc++], value=rom[pc++]; if(flag==0x20)gate=value;
        }
        throw new Exception("Initialization did not return.");
    }
    public static void Final(byte[] original, byte[] rom, RandoContext c, bool manual)
    {
        CrystalOrbRequirement req;
        Check(CrystalOrbRequirements.getResolvedRequirements(c).TryGetValue(41, out req)
            && req.Type == CrystalOrbRequirementType.SpecificWeapon, "No active weapon Orb.");
        VerifyClosedStartup(rom);
        Geometry(original, c);
        foreach (int id in new[] { 0x115, 0x116, 0x11A, 0x120, 0x34 })
        {
            var m = new SpellShuffleMachine(rom) { P = 0, DB = 0, A = id };
            m.Stops.Add(0xC0CCA1); m.Run(0xC0CC79);
            int offset = m.Read(0x7E001D, 3) - 0xC00000;
            var expected = Piece(original, c, id);
            var actual = SomMapCompressor.DecodeMap(rom.Skip(offset).Take(0x10000 - (offset & 65535)).ToArray());
            Check(expected.Cast<byte>().SequenceEqual(actual.Cast<byte>()), "Final native piece loader mismatch: " + id.ToString("X3"));
        }
        foreach (int table in new[] { 0x84000, 0x85000 })
            Check(rom.Skip(table + 82).Take(4).SequenceEqual(original.Skip(table + 82).Take(4)), "Map reference/trigger boundary changed.");
        Check(VanillaMapUtil.getObjects(rom, 41)[0].getXpos() == 28
            && VanillaMapUtil.getObjects(rom, 41)[0].getYpos() == 62, "Orb not at original position.");
        Check(VanillaMapUtil.getTriggers(rom, 41).SequenceEqual(VanillaMapUtil.getTriggers(original, 41)), "Native room transitions changed.");
        Check(rom.Skip(0x83000 + 0x86 * 4).Take(4).SequenceEqual(original.Skip(0x83000 + 0x86 * 4).Take(4)), "Matango-side native entry changed.");
        var gate = c.replacementEvents.ContainsKey(0x25B) ? c.replacementEvents[0x25B]
            : VanillaEventUtil.getVanillaEvent(original, 0x25B);
        Check(gate.SequenceEqual(VanillaEventUtil.getVanillaEvent(original, 0x25B)), "Orb success/progression changed.");
        var ready = c.replacementEvents[0x103];
        bool shortcut = ready.Skip(ready.Count - 3).SequenceEqual(new byte[] { 0x18, 0x83, 0 });
        Check(shortcut == manual, "Manual shortcut leaked into production or disappeared.");
        foreach (bool west in new[] { true, false }) foreach (bool correct in new[] { false, true })
            foreach (int player in new[] { 0, 0x200, 0x400 })
                NativeProbe(original, rom, c, req.Value, west, correct, player);
        var entry = VanillaDoorUtil.getDoor(rom, 0x83);
        Check(manual ? (entry.getXpos() == 26 || entry.getXpos() == 30) && entry.getYpos() == 62 && entry.getTransitionType() == 0
            : rom.Skip(0x83000 + 0x83 * 4).Take(4).SequenceEqual(original.Skip(0x83000 + 0x83 * 4).Take(4)),
            "Manual west-side entry adjustment leaked into production.");
        Console.WriteLine("PASS: final expanded piece loader, map/door boundaries, unchanged native Orb success, "
            + (manual ? "test-only west-side entry083" : "normal production startup") + "; requirement=" + CrystalOrbRequirements.getDisplayName(req));
    }
    static void NativeProbe(byte[] original, byte[] rom, RandoContext c, int weapon, bool west, bool correct, int player)
    {
        if (weapon >= 5) return; // Separate real projectile hooks are covered by the existing Orb suite.
        foreach (int direction in new[] { 0, 1, 2, 4 })
        {
            // A FRESH unopened state for EVERY direction/weapon/physical actor.
            var m = new SpellShuffleMachine(rom) {P=0,DB=0x7E,X=player};
            var bg=Layer(original,c,3,false);var fg=Layer(original,c,3,true);
            for(int y=0;y<72;y++)for(int x=0;x<48;x++){m.Write(0x7F0000+y*128+x,bg[x,y],1);m.Write(0x7F4000+y*128+x,fg[x,y],1);}
            for(int id=0;id<192;id++)for(int n=0;n<4;n++){
                m.Write(0x7FB800+id*4+n,original[0xB0000+original[0xB0400+384+id]*4+n],1);
                m.Write(0x7FBC00+id*4+n,original[0xB0000+original[0xB0400+384+192+id]*4+n],1);
            }
            m.Write(0x7E00DC,41,2);m.Write(0x7ECF10,0xA3,1);m.Write(0x7EE02C+player,1,1);
            m.Write(0x7EE1E8+player,(correct?weapon:(weapon+1)%5)*9+6,1);
            m.Write(0x7EE002+player,(west?27:29)*16+8,2);m.Write(0x7EE004+player,62*16+8,2);
            m.Write(0x7EE0C0+player,west?0x0010:0x00F0,2);m.Write(0x7E0056,direction,2);
            m.Write(0x7E00C0,2048,2);m.Write(0x7E00C2,2048,2);
            m.Write(0x7EE600,2,1);m.Write(0x7EE7E7,0x55,1);m.Write(0x7EE602,28*16+8,2);m.Write(0x7EE604,62*16+8,2);
            m.Stops.Add(0xC1D37A);m.Run(0xC1D293,true);
            Check(m.Read(CustomRamOffsets.CRYSTAL_ORB_PENDING_STATE,1)==(correct?1:0),"Real directional map probe did not respect weapon requirement from both closed approaches.");
            Check(m.Read(0x7ECF10,1)==0xA3,"Contact changed progression before native opening event.");
        }
    }

}

public sealed class UpperLandOrbAccessTestGenerator : OpenWorldGenerator
{
    public bool Manual;
    public bool EastStart;
    public int RequiredWeapon = 1;
    public static RandoContext Context;
    public UpperLandOrbAccessTestGenerator()
    {
        var flags = BindingFlags.Instance | BindingFlags.NonPublic;
        ((List<RandoProcessor>)typeof(RomGenerator).GetField("commonHacks", flags).GetValue(this))
            .RemoveAll(p => p.GetType().Name == "WeaponPowerCalculator");
        var modes = (List<RandoProcessor>)typeof(RomGenerator).GetField("modeSpecificHacks", flags).GetValue(this);
        modes.Insert(modes.FindIndex(p => p is CrystalOrbWeaponBreaking), new TestSwordOrb(this));
    }
    // Test-only forced requirement BEFORE hooks, colors, hints and placement;
    // production has no such override. No extra RNG or late event rewriting.
    sealed class TestSwordOrb : RandoProcessor
    {
        readonly UpperLandOrbAccessTestGenerator owner;
        public TestSwordOrb(UpperLandOrbAccessTestGenerator owner) { this.owner = owner; }
        protected override string getName() { return "Diagnostic Upper Land Sword requirement"; }
        protected override bool process(byte[] o, byte[] r, string seed, RandoSettings s, RandoContext c)
        {
            if (!owner.Manual) return false;
            CrystalOrbRequirements.resolveAndStore(s, c);
            c.workingData.setInt("crystalOrbRequirementValue41", owner.RequiredWeapon); return true;
        }
    }
    protected override void generate(byte[] original, byte[] output, string seed, RandoSettings s, RandoContext c)
    {
        base.generate(original, output, seed, s, c); Context = c;
        if (!Manual) return;
        var ready = c.replacementEvents[0x103];
        DoppelgangerManualProfile.AddSupplies(ready, false);
        ready.RemoveRange(ready.Count - 3, 2);
        ready.InsertRange(ready.Count - 1, new byte[] { 0x18, 0x83 });
        var entry = VanillaDoorUtil.getDoor(output, 0x83);
        entry.setXpos((byte)(EastStart ? 30 : 26)); entry.setYpos(62); entry.setTransitionType(0);
        VanillaDoorUtil.putDoor(output, entry, 0x83);
        DoppelgangerManualProfile.ApplyEquipment(output);
    }
}
