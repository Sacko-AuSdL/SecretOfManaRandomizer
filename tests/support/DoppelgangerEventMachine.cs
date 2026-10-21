using System;
using System.Collections.Generic;

// Focused event runner, not a game/PPU emulator. The actor comparison executes
// the ACTUAL vanilla C1:F1F1 handler through its branch to C1:E8D3, including
// accumulator/index widths and the native explicit-actor address calculation.
public sealed class DoppelgangerEventMachine
{
    readonly byte[] rom;
    readonly IDictionary<int, List<byte>> events;
    public readonly byte[] Flags = new byte[256];
    public readonly byte[] ActorStatus = new byte[3];
    public int Prizes, FixedSwordOrbs, JehkRestorations, PartyMpRestorations, LastDoor = -1;
    public bool TraceMusicCallees;
    public readonly List<string> Sequence = new List<string>();
    public DoppelgangerEventMachine(byte[] rom, IDictionary<int, List<byte>> events)
    { this.rom = rom; this.events = events; }

    public void Run(int eventId)
    {
        int pc = 0;
        for (int steps = 0; steps < 1000; steps++)
        {
            if (eventId == 0 || !events.ContainsKey(eventId)) return;
            List<byte> script = events[eventId];
            // Repository prize injection marker; treat it as one test award,
            // leaving the surrounding REAL generated event sequence intact.
            if (pc + 5 <= script.Count && script[pc] == 0x12 && script[pc + 1] == 0x34
                && script[pc + 2] == 0x56 && script[pc + 3] == 0x78 && script[pc + 4] == 0)
            { Prizes++; Sequence.Add("prize"); pc += 5; continue; }
            int op = script[pc];
            if (op == 0) return;
            if (op == 0x42)
            {
                int flag = Flags[script[pc + 1]], range = script[pc + 2];
                if (flag >= (range >> 4) && flag <= (range & 15)) pc += 3;
                else pc += 5;
            }
            else if (op == 0x4A)
            {
                byte[] cmd = script.GetRange(pc, 6).ToArray();
                pc += NativeActorAdvance(rom, cmd, ActorStatus);
            }
            else if (op >= 0x10 && op <= 0x17)
            { eventId = ((op - 0x10) << 8) | script[pc + 1]; Sequence.Add("jump:" + eventId.ToString("X3")); pc = 0; }
            else if (op >= 0x18 && op <= 0x1B)
            { LastDoor = ((op - 0x18) << 8) | script[pc + 1]; Sequence.Add("door:" + LastDoor.ToString("X3")); pc += 2; }
            else if (op >= 0x20 && op <= 0x27)
            {
                int call = ((op - 0x20) << 8) | script[pc + 1];
                Sequence.Add("call:" + call.ToString("X3"));
                if (call == 0x501) FixedSwordOrbs++;
                if (call == 0x41B) JehkRestorations++;
                if (TraceMusicCallees && (call == 0x626 || call == 0x704)) Run(call);
                // Music/healing/fixed-orb callees themselves are unchanged.
                pc += 2;
            }
            else if (op == 0x30) { Flags[script[pc + 1]] = script[pc + 2]; pc += 3; }
            else if (op == 0x29 || op == 0x2A)
            { int flag = script[pc + 1]; Flags[flag] = (byte)((Flags[flag] + (op == 0x29 ? 1 : 15)) & 15); pc += 2; }
            else if (op == 0x2F || op == 0x28)
            {
                if (op == 0x2F && script[pc + 1] == 0x84) PartyMpRestorations++;
                if (op == 0x2F) Sequence.Add("heal:" + script[pc + 1].ToString("X2"));
                pc += 2; // heal / dialogue wait
            }
            else if (op == 0x50 || op == 0x51 || op == 0x52) pc++; // dialogue frame
            else if (op == 0x40) { Sequence.Add("sound:" + BitConverter.ToString(script.GetRange(pc, 5).ToArray())); pc += 5; }
            else if (op == 6) pc++; // existing party control
            else throw new Exception("Unsupported event opcode " + op.ToString("X2"));
        }
        throw new Exception("Event loop did not terminate.");
    }

    public static int NativeActorAdvance(byte[] rom, byte[] command, byte[] statuses)
    {
        byte[] ram = new byte[65536];
        Array.Copy(command, 0, ram, 0xC000, 6);
        ram[0xD1] = 0; ram[0xD2] = 0xC0; ram[0xD3] = 0x7E;
        ram[4] = command[0]; ram[5] = command[1];
        for (int i = 0; i < 3; i++) ram[0xE791 + i * 0x200] = statuses[i];
        var cpu = new ActorCpu(rom, ram);
        cpu.Run();
        return (ram[0xD1] | (ram[0xD2] << 8)) - 0xC000;
    }

    // Execute the emitted boss-kill classification prefix, stopping BEFORE its
    // unchanged scaling update/message code. Exactly one shadow is classified
    // as the logical boss; the two other shadows and ordinary enemies are not.
    public static bool CountsAsBoss(byte[] rom, byte species)
    {
        if (rom[0x4205] != 0x22) throw new Exception("Expected scaling hook missing.");
        int pc = rom[0x4206] | (rom[0x4207] << 8) | ((rom[0x4208] - 0xC0) << 16);
        int a = 0, x = 0x600, p = 0;
        for (int steps = 0; steps < 100; steps++)
        {
            int op = rom[pc++], value;
            switch (op)
            {
                case 0xE0: value = rom[pc] | (rom[pc + 1] << 8); pc += 2; p = (x >= value ? 1 : 0) | (x == value ? 2 : 0); break;
                case 0xBD:
                    value = rom[pc] | (rom[pc + 1] << 8); pc += 2;
                    if (value != 0xE180) throw new Exception("Unexpected classifier load.");
                    a = species; p = (p & ~2) | (a == 0 ? 2 : 0); break;
                case 0xC9: value = rom[pc++]; p = (a >= value ? 1 : 0) | (a == value ? 2 : 0); break;
                case 0xB0: value = (sbyte)rom[pc++]; if ((p & 1) != 0) pc += value; break;
                case 0x90: value = (sbyte)rom[pc++]; if ((p & 1) == 0) pc += value; break;
                case 0xF0: value = (sbyte)rom[pc++]; if ((p & 2) != 0) pc += value; break;
                case 0xD0: value = (sbyte)rom[pc++]; if ((p & 2) == 0) pc += value; break;
                case 0x9E: pc += 2; break; // replayed vanilla cleanup
                case 0x6B: return false;
                case 0xAF: return true; // first load of the boss scaling counter
                default: throw new Exception("Unexpected classifier opcode " + op.ToString("X2"));
            }
        }
        throw new Exception("Boss classifier did not terminate.");
    }

    sealed class ActorCpu
    {
        readonly byte[] rom, ram;
        int a, x, y, p = 0x30, pc = 0x1F1F1;
        int M { get { return (p & 0x20) != 0 ? 1 : 2; } }
        int I { get { return (p & 0x10) != 0 ? 1 : 2; } }
        public ActorCpu(byte[] rom, byte[] ram) { this.rom = rom; this.ram = ram; }
        int Fetch(int count) { int v = 0; for (int i = 0; i < count; i++) v |= rom[pc++] << (8 * i); return v; }
        int Read(int at, int count) { int v = 0; for (int i = 0; i < count; i++) v |= ram[(at + i) & 65535] << (8 * i); return v; }
        void Write(int at, int value, int count) { for (int i = 0; i < count; i++) ram[(at + i) & 65535] = (byte)(value >> (8 * i)); }
        void NZ(int v, int size) { int mask = size == 1 ? 255 : 65535; p = (p & ~0x82) | ((v & mask) == 0 ? 2 : 0) | ((v & (size == 1 ? 128 : 32768)) != 0 ? 128 : 0); }
        void Load(int v) { int mask = M == 1 ? 255 : 65535; a = (a & ~mask) | (v & mask); NZ(a, M); }
        void Compare(int v) { int mask = M == 1 ? 255 : 65535; p = (p & ~1) | ((a & mask) >= v ? 1 : 0); NZ(a - v, M); }
        void Branch(bool take) { int d = (sbyte)Fetch(1); if (take) pc += d; }
        public void Run()
        {
            for (int steps = 0; steps < 200; steps++)
            {
                if (pc == 0x1E8D3) return;
                int op = Fetch(1), at, v, mask;
                switch (op)
                {
                    case 0xA0: y = Fetch(I); NZ(y, I); break;
                    case 0xC2: p &= ~Fetch(1); break;
                    case 0xE2: p |= Fetch(1); if (I == 1) { x &= 255; y &= 255; } break;
                    case 0xB7: at = Read(Fetch(1), 3); Load(Read(at + y, M)); break;
                    case 0x85: Write(Fetch(1), a, M); break;
                    case 0xA6: x = Read(Fetch(1), I); NZ(x, I); break;
                    case 0xA5: Load(Read(Fetch(1), M)); break;
                    case 0x29: Load(a & Fetch(M)); break;
                    case 0x09: Load(a | Fetch(M)); break;
                    case 0xC9: Compare(Fetch(M)); break;
                    case 0xC5: Compare(Read(Fetch(1), M)); break;
                    case 0x3A: Load(a - 1); break;
                    case 0x0A: mask = M == 1 ? 255 : 65535; p = (p & ~1) | ((a & (M == 1 ? 128 : 32768)) != 0 ? 1 : 0); Load((a & mask) << 1); break;
                    case 0xEB: a = ((a & 255) << 8) | (a >> 8); NZ(a & 255, 1); break;
                    case 0xAA: x = a & (I == 1 ? 255 : 65535); NZ(x, I); break;
                    case 0x8A: Load(x); break;
                    case 0xBD: Load(Read(Fetch(2) + x, M)); break;
                    case 0x18: p &= ~1; break;
                    case 0x69: v = (a & (M == 1 ? 255 : 65535)) + Fetch(M) + (p & 1); p = (p & ~1) | (v > (M == 1 ? 255 : 65535) ? 1 : 0); Load(v); break;
                    case 0xF0: Branch((p & 2) != 0); break;
                    case 0xD0: Branch((p & 2) == 0); break;
                    case 0xB0: Branch((p & 1) != 0); break;
                    case 0x90: Branch((p & 1) == 0); break;
                    case 0x80: Branch(true); break;
                    case 0x82: at = (short)Fetch(2); pc += at; break;
                    default: throw new Exception("Unsupported native actor-check opcode " + op.ToString("X2"));
                }
            }
            throw new Exception("Native actor check did not reach interpreter continuation.");
        }
    }
}
