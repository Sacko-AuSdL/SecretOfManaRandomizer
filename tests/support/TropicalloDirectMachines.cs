using System;
using System.Collections.Generic;
using SoMRandomizer.processing.common;

// Executes only the emitted binding-specific dispatcher. The native event
// interpreter is a boundary; its three $4A checks are executed separately via
// DoppelgangerEventMachine.NativeActorAdvance. Not a combat/PPU emulator.
public sealed class TropicalloDispatchMachine
{
    readonly byte[] rom;
    public readonly byte[] Ram = new byte[0x10000];
    public int A = 0xAB43, X = 0x56, Y = 0x78, P = 0x35, DB = 0x7E, DP, S = 0x1F0;
    public int Calls, EventId = -1, EventActor = -1;
    // Optional previous-dispatcher boundary used by the production coexistence
    // test. Its internal Orb logic has its own permanent machine tests; here
    // prove exactly-once chaining and the displaced result/status contract.
    public int ChainedAddress = -1, ChainedCalls;
    int pc;
    int M { get { return (P & 0x20) != 0 ? 1 : 2; } }
    int I { get { return (P & 0x10) != 0 ? 1 : 2; } }
    public TropicalloDispatchMachine(byte[] rom) { this.rom = rom; }
    public void Put(int at, int value) { Ram[at] = (byte)value; Ram[at + 1] = (byte)(value >> 8); }
    int Read(int at, int count) { return Ram[at & 65535] | (count == 2 ? Ram[(at + 1) & 65535] << 8 : 0); }
    int Fetch(int n) { int v = 0; for (int i = 0; i < n; i++) v |= rom[pc++] << (i * 8); return v; }
    void Push(int v, int n) { for (int i = n - 1; i >= 0; i--) Ram[S--] = (byte)(v >> (i * 8)); }
    int Pull(int n) { int v = 0; for (int i = 0; i < n; i++) v |= Ram[++S] << (i * 8); return v; }
    void NZ(int v, int n) { P = (P & ~0x82) | ((v & (n == 1 ? 255 : 65535)) == 0 ? 2 : 0) | ((v & (n == 1 ? 128 : 32768)) != 0 ? 128 : 0); }
    void Load(int v) { A = M == 1 ? (A & 0xFF00) | (v & 255) : v & 65535; NZ(A, M); }
    public void Run(int offset)
    {
        pc = offset;
        for (int steps = 0; steps < 1500; steps++)
        {
            int op = Fetch(1), at, v, n;
            switch (op)
            {
                case 0x08: Push(P, 1); break;
                case 0x28: P = Pull(1); break;
                case 0xC2: P &= ~Fetch(1); break;
                case 0xE2: P |= Fetch(1); if (I == 1) { X &= 255; Y &= 255; } break;
                case 0x48: Push(A, M); break;
                case 0x68: n = M; Load(Pull(n)); break;
                case 0xDA: Push(X, I); break;
                case 0xFA: X = Pull(I); NZ(X, I); break;
                case 0x5A: Push(Y, I); break;
                case 0x7A: Y = Pull(I); NZ(Y, I); break;
                case 0x8B: Push(DB, 1); break;
                case 0xAB: DB = Pull(1); NZ(DB, 1); break;
                case 0x0B: Push(DP, 2); break;
                case 0x2B: DP = Pull(2); NZ(DP, 2); break;
                case 0xAF: at = Fetch(3); if ((at >> 16) != 0x7E) throw new Exception("Unexpected read bank."); Load(Read(at, M)); break;
                case 0xA5: Load(Read(DP + Fetch(1), M)); break;
                case 0x05: Load(A | Read(DP + Fetch(1), M)); break;
                case 0xA9: Load(Fetch(M)); break;
                case 0x29: Load(A & Fetch(M)); break;
                case 0xC9: v = Fetch(M); n = A & (M == 1 ? 255 : 65535); P = (P & ~1) | (n >= v ? 1 : 0); NZ(n - v, M); break;
                case 0x8F: at = Fetch(3); if (at != 0x7E00D4) throw new Exception("Unexpected data write."); Put(at & 65535, A); break;
                case 0xD0: v = (sbyte)Fetch(1); if ((P & 2) == 0) pc += v; break;
                case 0xF0: v = (sbyte)Fetch(1); if ((P & 2) != 0) pc += v; break;
                case 0x90: v = (sbyte)Fetch(1); if ((P & 1) == 0) pc += v; break;
                case 0xB0: v = (sbyte)Fetch(1); if ((P & 1) != 0) pc += v; break;
                case 0x82: v = (short)Fetch(2); pc += v; break;
                case 0x22:
                    at = Fetch(3);
                    if (at == ChainedAddress) { ChainedCalls++; Load(Read(DP + 255, M)); Load(A | Read(DP + 0x52, M)); break; }
                    if (at != 0xC1E76D) throw new Exception("Unexpected runtime call.");
                    Calls++; EventId = A; EventActor = Read(0xD4, 2);
                    // Native dispatch boundary deliberately clobbers registers.
                    A = 0x1987; X = 0x9876; Y = 0x6543; P = 0; break;
                case 0x6B: return;
                default: throw new Exception("Unsupported dispatcher opcode " + op.ToString("X2"));
            }
        }
        throw new Exception("Dispatcher did not return.");
    }
}

public sealed class TropicalloEventMachine
{
    readonly byte[] rom;
    readonly IDictionary<int, List<byte>> events;
    public readonly byte[] Flags = new byte[256], Status = new byte[3];
    public readonly List<string> Trace = new List<string>();
    public int Prizes, Orbs, LastDoor = -1, Heals;
    public TropicalloEventMachine(byte[] rom, IDictionary<int, List<byte>> events) { this.rom = rom; this.events = events; }
    public void Run(int id)
    {
        if (id == 0) return;
        var script = events.ContainsKey(id) ? events[id] : VanillaEventUtil.getVanillaEvent(rom, id);
        for (int p = 0, steps = 0; p < script.Count && steps < 2000; steps++)
        {
            int op = script[p];
            if (p + 5 <= script.Count && op == 0x12 && script[p + 1] == 0x34 && script[p + 2] == 0x56 && script[p + 3] == 0x78)
            { Prizes++; Trace.Add("prize:" + script[p + 4]); p += 5; continue; }
            if (op == 0 || op == 2) return;
            if (op == 0x42)
            { int v = Flags[script[p + 1]], range = script[p + 2]; p += v >= (range >> 4) && v <= (range & 15) ? 3 : 5; }
            else if (op == 0x4A) p += DoppelgangerEventMachine.NativeActorAdvance(rom, script.GetRange(p, 6).ToArray(), Status);
            else if (op >= 0x10 && op <= 0x17) { Run(((op - 0x10) << 8) | script[p + 1]); return; }
            else if (op >= 0x18 && op <= 0x1B) { LastDoor = ((op - 0x18) << 8) | script[p + 1]; Trace.Add("door:" + LastDoor.ToString("X3")); p += 2; }
            else if (op >= 0x20 && op <= 0x27)
            {
                int call = ((op - 0x20) << 8) | script[p + 1]; Trace.Add("call:" + call.ToString("X3"));
                if (call == 0x503) Orbs++;
                else if (call == 0x41B) { Heals++; throw new Exception("Jehk healing leaked into Tropicallo."); }
                else Run(call);
                p += 2;
            }
            else if (op == 0x29) { Flags[script[p + 1]]++; p += 2; }
            else if (op == 0x30) { Flags[script[p + 1]] = script[p + 2]; p += 3; }
            else if (op == 0x2F) { Heals++; p += 2; }
            else if (op == 0x40) { Trace.Add("sound:" + BitConverter.ToString(script.GetRange(p, 5).ToArray())); p += 5; }
            else if (op == 0x28) p += 2;
            else if (op == 6 || op == 0x50 || op == 0x51 || op == 0x52 || op >= 0x7F) p++;
            else throw new Exception("Unhandled event opcode " + op.ToString("X2"));
        }
    }
}
