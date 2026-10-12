using System.Collections.Generic;

namespace SoMRandomizer.processing.hacks.common.util
{
    /// <summary>
    /// Add custom event commands as 0x57 xx starting at 03
    /// </summary>
    /// 
    /// <remarks>Author: Moppleton</remarks>
    public class CustomEventManager
    {
        // 57 xx event type -> offset to jump to process event
        private Dictionary<int, int> eventJumpOffsets = new Dictionary<int, int>();
        private HashSet<int> nonTextCommands = new HashSet<int>();
        // type of next event to add (x57 xx)
        private int index = 3;
        // event type name to x57 xx command type to run
        private Dictionary<string, int> indexesByName = new Dictionary<string, int>();

        public int registerNewEvent(string commandName, int offset, bool producesText = true)
        {
            int id = index;
            eventJumpOffsets[index] = offset;
            indexesByName[commandName] = index;
            if(!producesText) nonTextCommands.Add(index);
            index++;
            return id;
        }

        // use 57 xx to run the event
        public byte getCommandIndex(string commandName)
        {
            return (byte)indexesByName[commandName];
        }

        // must be done after everything else that registers ^
        public void process(byte[] outRom, ref int newCodeOffset)
        {
            if(nonTextCommands.Count > 0) emitNonTextDispatch(outRom, ref newCodeOffset);
            // added anything?
            if(index > 3)
            {
                outRom[0x185F] = 0x22;
                outRom[0x1860] = (byte)newCodeOffset;
                outRom[0x1861] = (byte)(newCodeOffset >> 8);
                outRom[0x1862] = (byte)((newCodeOffset >> 16) + 0xC0);
                outRom[0x1863] = 0xEA;
                outRom[0x1864] = 0xEA;
                outRom[0x1865] = 0xEA;
                outRom[0x1866] = 0xEA;
                outRom[0x1867] = 0xEA;
                outRom[0x1868] = 0xEA;
                outRom[0x1869] = 0xEA;
                outRom[0x186A] = 0xEA;
                outRom[0x186B] = 0xEA;
                outRom[0x186C] = 0xEA;
                outRom[0x186D] = 0xEA;
                outRom[0x186E] = 0xEA;
                outRom[0x186F] = 0xEA;
                outRom[0x1870] = 0xEA;
                outRom[0x1871] = 0xEA;
                outRom[0x1872] = 0xEA;
                outRom[0x1873] = 0xEA;
                outRom[0x1874] = 0xEA;
                outRom[0x1875] = 0xEA;

                // new subroutine: copy of 185F - 1876, but we special case for X == 24 (param == 3)
                // note 8bit A, 16bit X
                // PHY
                // CPX #24
                // BEQ xx
                // 1860 - 1876 from above, except RTL instead of RTS; original code nop nop nop nop RTS
                // xx:
                //    note 7ECF18, 19, 1A, 1B - hours, minutes, seconds, frames
                //    also note dialogue chars = 0->B5, 1->B6.. 9->BE
                //    so we need to write to 7EA22F, 0-terminated i think? and the code we return to handles displaying it
                //    this is going to be similar code to how we dump it to layer 3 but with different final value offsets
                // phy
                outRom[newCodeOffset++] = 0x5A;

                // cpx 0x24
                outRom[newCodeOffset++] = 0xE0;
                outRom[newCodeOffset++] = 0x24;
                outRom[newCodeOffset++] = 0x00;
                // bcs over this shit
                outRom[newCodeOffset++] = 0xB0;
                outRom[newCodeOffset++] = 0x17;

                // original code from above - run for case where id < 3 (print player names)
                outRom[newCodeOffset++] = 0xA9;
                outRom[newCodeOffset++] = 0x0C;

                outRom[newCodeOffset++] = 0xA0;
                outRom[newCodeOffset++] = 0x00;
                outRom[newCodeOffset++] = 0x00;

                outRom[newCodeOffset++] = 0xEB;

                outRom[newCodeOffset++] = 0xBD;
                outRom[newCodeOffset++] = 0x00;
                outRom[newCodeOffset++] = 0xCC;

                outRom[newCodeOffset++] = 0x99;
                outRom[newCodeOffset++] = 0x2F;
                outRom[newCodeOffset++] = 0xA2;

                outRom[newCodeOffset++] = 0xE8;

                outRom[newCodeOffset++] = 0xC8;

                outRom[newCodeOffset++] = 0xEB;

                outRom[newCodeOffset++] = 0x3A;

                outRom[newCodeOffset++] = 0xD0;
                outRom[newCodeOffset++] = 0xF3;

                outRom[newCodeOffset++] = 0x99;
                outRom[newCodeOffset++] = 0x2F;
                outRom[newCodeOffset++] = 0xA2;

                // ply
                outRom[newCodeOffset++] = 0x7A;
                // rtl
                outRom[newCodeOffset++] = 0x6B;

                for (int i = 3; i < index; i++)
                {
                    int compareValue = i * 12;
                    int jumpOffset = eventJumpOffsets[i];
                    // CPX #0030
                    outRom[newCodeOffset++] = 0xE0;
                    outRom[newCodeOffset++] = (byte)compareValue;
                    outRom[newCodeOffset++] = (byte)(compareValue >> 8);
                    // BNE over
                    outRom[newCodeOffset++] = 0xD0;
                    outRom[newCodeOffset++] = 0x0A;
                    // JSL 16bitprint
                    outRom[newCodeOffset++] = 0x22;
                    outRom[newCodeOffset++] = (byte)jumpOffset;
                    outRom[newCodeOffset++] = (byte)(jumpOffset >> 8);
                    outRom[newCodeOffset++] = (byte)((jumpOffset >> 16) + 0xC0);
                    // PLY
                    outRom[newCodeOffset++] = 0x7A;
                    // LDA #7E
                    outRom[newCodeOffset++] = 0xA9;
                    outRom[newCodeOffset++] = 0x7E;
                    // PHA
                    outRom[newCodeOffset++] = 0x48;
                    // PLB
                    outRom[newCodeOffset++] = 0xAB;
                    // RTL
                    outRom[newCodeOffset++] = 0x6B;
                }

                // default: just clean up, don't call anything

                // PLY
                outRom[newCodeOffset++] = 0x7A;
                // LDA #7E
                outRom[newCodeOffset++] = 0xA9;
                outRom[newCodeOffset++] = 0x7E;
                // PHA
                outRom[newCodeOffset++] = 0x48;
                // PLB
                outRom[newCodeOffset++] = 0xAB;
                // RTL
                outRom[newCodeOffset++] = 0x6B;

            }
        }

        private void emitNonTextDispatch(byte[] rom, ref int offset)
        {
            // C1:E8F7 clamps ALL opcodes >= $50 (including $57) to dialogue.
            // C0:182B then substitutes $A22F as text; $185F only customizes its
            // contents, not that continuation. Orb state-only commands must instead
            // advance the event cursor directly, without opening/rendering stale text.
            if(rom[0x1E8F7] != 0xC9 || rom[0x1E8F8] != 0x50 ||
                rom[0x1E8F9] != 0x90 || rom[0x1E8FA] != 0x02)
                throw new System.InvalidOperationException("Custom event dispatch hook already owned.");
            SoMRandomizer.util.CodeGenerationUtils.ensureSpaceInBank(ref offset, 96 + nonTextCommands.Count * 14);
            int start = offset;
            var code = new List<byte>();
            var successBranches = new List<int>();
            System.Action<byte[]> emit = bytes => code.AddRange(bytes);
            System.Action<int, int> fix = (at, target) => {
                int delta = target - at - 2;
                code[at] = (byte)delta; code[at + 1] = (byte)(delta >> 8);
            };
            // Interpreter entry A8/X8, DP=0, DB=$7E. Preserve caller state and
            // provide the existing custom-handler A8/X16 contract only for $57.
            emit(new byte[] { 0x08,0xC2,0x30,0x48,0xDA,0x5A,0x8B,0xE2,0x20,
                0xC9,0x57,0xF0,0x03,0x82,0,0 });
            int not57 = code.Count - 2;
            emit(new byte[] { 0xAF,0x05,0x00,0x7E }); // argument read by C1:E8F1
            for(int id = 3; id < index; id++)
            {
                if(!nonTextCommands.Contains(id)) continue;
                int target = eventJumpOffsets[id] + 0xC00000;
                emit(new byte[] { 0xC9,(byte)id,0xD0,0x0A,0xA2,(byte)(id*12),(byte)(id*12>>8),
                    0x22,(byte)target,(byte)(target>>8),(byte)(target>>16),0x82,0,0 });
                successBranches.Add(code.Count - 2);
            }
            int fallback = code.Count;
            fix(not57, fallback);
            // Replay original CMP/BCC. Printing custom commands and player-name
            // insertion still take their original dialogue path byte-for-byte.
            emit(new byte[] { 0xAB,0xC2,0x30,0x7A,0xFA,0x68,0x28,
                0xC9,0x50,0xB0,0x04,0x5C,0xFD,0xE8,0xC1,0x5C,0xFB,0xE8,0xC1 });
            foreach(int at in successBranches) fix(at, code.Count);
            emit(new byte[] { 0xAB,0xC2,0x30,0x7A,0xFA,0x68,0x28,
                0x08,0xC2,0x20,0xAF,0xD1,0x00,0x7E,0x1A,0x1A,0x8F,0xD1,0x00,0x7E,
                0x28,0x5C,0xD3,0xE8,0xC1 });
            code.CopyTo(rom, offset); offset += code.Count;
            rom[0x1E8F7] = 0x5C;
            rom[0x1E8F8] = (byte)start; rom[0x1E8F9] = (byte)(start >> 8);
            rom[0x1E8FA] = (byte)((start >> 16) + 0xC0);
        }
    }
}
