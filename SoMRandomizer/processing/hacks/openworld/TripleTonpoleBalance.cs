using SoMRandomizer.config.settings;
using SoMRandomizer.processing.common;
using SoMRandomizer.util;
using System;
using System.Collections.Generic;
using System.Linq;

namespace SoMRandomizer.processing.hacks.openworld
{
    /// <summary>Half HP per form in actual Triple encounters, never global species stats.</summary>
    public class TripleTonpoleBalance : RandoProcessor
    {
        public const int HOOK_OFFSET = 0x5697;
        public const int HP_DIVISOR = 2;
        protected override string getName() { return "Encounter-local Triple Tonpole HP"; }

        protected override bool process(byte[] origRom, byte[] outRom, string seed, RandoSettings settings, RandoContext context)
        {
            bool native = TripleTonpoleBossArenaRedirect.isNativeTriple(context);
            bool foreign = TripleTonpoleBossArenaRedirect.hasForeignTriple(context);
            if (!native && !foreign) return false;
            byte[] displaced = { 0xBF, 0x19, 0x1C, 0xD0, 0x99, 0xCA, 0xE1 };
            if (!outRom.Skip(HOOK_OFFSET).Take(displaced.Length).SequenceEqual(displaced))
                throw new InvalidOperationException("Triple HP hook already owned at $C0:5697.");
            // Full enemy initialization ends up here AFTER both the original
            // and EnemiesAtYourLevel HP loaders. Transformation at $C2:6294
            // calls $C0:003F -> $C0:55EC again, so BOTH forms get half HP.
            // Status recalculation does not reload HP, avoiding repeated nerfs.
            List<byte> code = new List<byte> { 0x08, 0xC2, 0x20, 0x48, 0xAF, 0xDC, 0, 0x7E };
            List<int> mapBranches = new List<int>();
            foreach (int map in new[] { native ? SomVanillaValues.MAPNUM_TRIPLETONPOLE_ARENA : -1,
                foreign ? TripleTonpoleBossArenaRedirect.MAP_ID : -1 }.Where(m => m >= 0))
            {
                code.AddRange(new byte[] { 0xC9, (byte)map, (byte)(map >> 8), 0xF0, 0 });
                mapBranches.Add(code.Count - 1);
            }
            code.AddRange(new byte[] { 0x80, 0 });
            int wrongMap = code.Count - 1;
            int species = code.Count;
            foreach (int branch in mapBranches) code[branch] = (byte)(species - branch - 1);
            code.AddRange(new byte[] { 0xB9, 0xE7, 0xE1, 0x29, 0xFF, 0,
                0xC9, 0x71, 0, 0xF0, 5, 0xC9, 0x7A, 0, 0xD0, 0 });
            int wrongSpecies = code.Count - 1;
            code.AddRange(new byte[] { 0xB9, 0x84, 0xE1, 0x4A, 0xD0, 3, 0xA9, 1, 0,
                0x99, 0x84, 0xE1, 0x99, 0x82, 0xE1 });
            int exit = code.Count;
            code[wrongMap] = (byte)(exit - wrongMap - 1);
            code[wrongSpecies] = (byte)(exit - wrongSpecies - 1);
            code.AddRange(new byte[] { 0x68, 0x28 });
            code.AddRange(displaced);
            code.Add(0x6B);
            CodeGenerationUtils.ensureSpaceInBank(ref context.workingOffset, code.Count);
            int address = context.workingOffset + 0xC00000;
            outRom[HOOK_OFFSET] = 0x22;
            outRom[HOOK_OFFSET + 1] = (byte)address;
            outRom[HOOK_OFFSET + 2] = (byte)(address >> 8);
            outRom[HOOK_OFFSET + 3] = (byte)(address >> 16);
            for (int i = 4; i < displaced.Length; i++) outRom[HOOK_OFFSET + i] = 0xEA;
            Array.Copy(code.ToArray(), 0, outRom, context.workingOffset, code.Count);
            context.workingData.setInt("tripleTonpoleHpRoutine", context.workingOffset);
            context.workingOffset += code.Count;
            return true;
        }
    }
}
