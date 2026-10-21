using System;
using System.Collections.Generic;
using System.Linq;
using SoMRandomizer.processing.common;

// Decode the ACTUAL emitted native-stat loader blocks, then execute those
// instructions against their ROM class/value tables. Not a high-level formula.
public static class DoppelgangerScalingChecks
{
    public static void RevivalControl(byte[] rom)
    {
        // Native target selector shared by item05 (Cup) / spell21 (Revivify):
        // D0:DB2A loads target death status, BPL skips the accepted-target path.
        foreach (int status in new[] { 0, 128 })
        {
            var menu = new SpellShuffleMachine(rom); menu.X = 0xE200; menu.P = 0x20;
            menu.Write(0x7EE391, status, 1);
            menu.Stops.Add(0xD0DB44); menu.Stops.Add(0xD0DB4D); menu.Run(0xD0DB2A);
            if (menu.PC != (status == 0 ? 0xD0DB4D : 0xD0DB44)) throw new Exception("Native revival target control changed.");
        }
        // Native shadow classification at C0:4802-4818 sets bit01, not the
        // regular-boss40/player80 flags. Revivify's C8:ED04 type guard returns
        // without HP/status changes for that living shadow classification.
        var effect = new SpellShuffleMachine(rom); effect.DP = 0x300; effect.X = 0x600; effect.P = 0x20;
        effect.Write(0x7E0385, 0x600, 2); effect.Write(0x7EE7FB, 1, 1);
        effect.Write(0x7EE782, 800, 2); effect.Write(0x7EE791, 0, 1);
        effect.Run(0xC8ED04, true);
        if (effect.Read(0x7EE782, 2) != 800 || effect.Read(0x7EE791, 1) != 0 || effect.Visits.Contains(0xC8ED0D))
            throw new Exception("Revival became a shadow damage/kill effect.");
    }
    public static Dictionary<int, int[]> Loaders(byte[] rom, int start, int end)
    {
        byte[] prefix = { 0xC2, 0x20, 0xBD, 0xE7, 0xE1, 0x29, 0xFF, 0, 0xAA, 0xE2, 0x20, 0xBF };
        var found = new Dictionary<int, int[]>();
        for (int at = start; at + 60 < end; at++)
        {
            bool matches = true;
            for (int i = 0; i < prefix.Length; i++) if (rom[at + i] != prefix[i]) { matches = false; break; }
            if (!matches) continue;
            // The separately emitted boss weapon-attack helper shares this
            // prefix but restores X and stores indexed by X instead of Y.
            // Only the regular native-stat loaders have the widening AND.
            if (rom[at + 15] != 0xC2 || rom[at + 16] != 0x20 || rom[at + 17] != 0x29) continue;
            if (rom[at + 20] == 0xDA) continue; // status-recalculation loader (no HP)
            int classes = rom[at + 12] | rom[at + 13] << 8 | (rom[at + 14] - 0xC0) << 16;
            int store = at + 20;
            if (rom[store] == 0x0A) store++; // word-table class stride
            if (rom[store++] != 0x18 || rom[store++] != 0x6F) throw new Exception("Unexpected loader level index at " + at.ToString("X6") + ": " + BitConverter.ToString(rom, at, 45));
            store += 3;
            if (rom[store++] != 0xAA) throw new Exception("Unexpected loader index transfer.");
            if (rom[store] == 0xE2) store += 2;
            if (rom[store++] != 0xBF) throw new Exception("Unexpected loader value read.");
            store += 3;
            if (rom[store] != 0x99) throw new Exception("Missing native stat store at " + at.ToString("X6"));
            int address = rom[store + 1] | rom[store + 2] << 8;
            int tail = store + 3;
            while (rom[tail] == 0x99) tail += 3;
            if (!found.ContainsKey(address)) found.Add(address, new[] { at, tail, classes });
        }
        if (!found.ContainsKey(0xE182) || !found.ContainsKey(0xE188) || !found.ContainsKey(0xE1A5))
            throw new Exception("Missing HP/STR/DEF loaders.");
        return found;
    }

    public static int Value(byte[] rom, int[] loader, int species, int level)
    {
        var m = new SpellShuffleMachine(rom);
        m.A = 0xFFFF; m.X = 0x600; m.Y = 0x600; m.P = 0x20;
        m.Write(0x7EE7E7, species, 2);
        // Six classes per level: table indices at (level-1)*6, *12 words.
        m.Write(CustomRamOffsets.LEVELMATCH_CURRENT_MAX_LEVEL_OFFSET_A_16BIT, (level - 1) * 6, 2);
        m.Write(CustomRamOffsets.LEVELMATCH_CURRENT_MAX_LEVEL_OFFSET_B_16BIT, (level - 1) * 12, 2);
        m.Stops.Add(loader[1] + 0xC00000); m.Run(loader[0] + 0xC00000);
        int store = loader[1] - 3;
        int address = rom[store + 1] | rom[store + 2] << 8;
        bool wide = address == 0xE184 || address == 0xE182 || address == 0xE1A5 || address == 0xE1A8 || address == 0xE18D;
        return m.Read(0x7E0000 + 0x600 + address, wide ? 2 : 1);
    }
}
