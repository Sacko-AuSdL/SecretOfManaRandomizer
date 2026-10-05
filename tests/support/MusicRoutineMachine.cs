using System;
using System.Collections.Generic;

// Focused 65816 instruction harness, NOT an SPC/audio or full-game emulator.
// Executes the emitted hooks and native C3 request prologue/parameter send.
// SPC handshakes/stream uploads and actor initialization are explicit boundaries.
public sealed class MusicRoutineMachine
{
    public readonly byte[] Memory = new byte[0x1000000];
    public readonly byte[] Rom;
    public readonly List<byte[]> Commands = new List<byte[]>();
    public readonly HashSet<int> Writes = new HashSet<int>();
    public int A, X, Y, P = 0x20, DP, DB = 0x7E, S = 0x1FF, PC;
    public int RngCalls, ActorInitializations, FrameCalls;
    private int steps;
    private readonly Queue<string> trace = new Queue<string>();
    private const int End = 0xFFFFFF;
    public MusicRoutineMachine(byte[] rom) { Rom = rom; }
    public int UnexpectedRomWrite(byte[] before, int limit, HashSet<int> allowed)
    {
        for (int i = 0; i < limit; i++)
            if (Rom[i] != before[i] && !allowed.Contains(i)) return i;
        return -1;
    }
    private int Width { get { return (P & 0x20) != 0 ? 1 : 2; } }
    private int IndexWidth { get { return (P & 0x10) != 0 ? 1 : 2; } }
    private int Mask { get { return Width == 1 ? 255 : 65535; } }
    private int Address(int address)
    {
        int bank = address >> 16, low = address & 65535;
        if ((bank < 0x40 || (bank >= 0x80 && bank < 0xC0)) && low < 0x2000)
            return 0x7E0000 + low;
        return address & 0xFFFFFF;
    }
    public int Read(int address, int width)
    {
        int value = 0;
        for (int i = 0; i < width; i++) value |= Memory[Address(address + i)] << (8 * i);
        return value;
    }
    public void Write(int address, int value, int width)
    {
        for (int i = 0; i < width; i++)
        {
            int at = Address(address + i);
            Memory[at] = (byte)(value >> (8 * i));
            Writes.Add(at);
        }
        if (Address(address) == 0x4206)
        {
            int divisor = Read(0x4206, 1);
            Write(0x4216, divisor == 0 ? 0 : Read(0x4204, 2) % divisor, 2);
        }
    }
    private int Data(int address, int width)
    {
        if ((address >> 16) >= 0xC0)
        {
            int at = address - 0xC00000;
            return Rom[at] | (width == 2 ? Rom[at + 1] << 8 : 0);
        }
        // The SPC acknowledges parameters; no claim about driver execution/DSP output.
        if (address == 0x2141) return 0;
        if (address == 0x2142) return 1;
        if (address == 0x2140 && (PC == 0xC301F4 || PC == 0xC305B5)) return 0;
        return Read(address, width);
    }
    private int Fetch()
    {
        int bank = PC >> 16;
        int offset = bank >= 0xC0 ? PC - 0xC00000 : PC;
        PC++;
        return Rom[offset];
    }
    private int Operand(int count)
    {
        int value = 0;
        for (int i = 0; i < count; i++) value |= Fetch() << (8 * i);
        return value;
    }
    private void NZ(int value, int width)
    {
        int mask = width == 1 ? 255 : 65535;
        P = (P & ~0x82) | ((value & mask) == 0 ? 2 : 0) |
            ((value & (width == 1 ? 128 : 32768)) != 0 ? 128 : 0);
    }
    private void Load(int value) { A = (A & ~Mask) | (value & Mask); NZ(A, Width); }
    private void Compare(int value)
    {
        int left = A & Mask;
        P = (P & ~1) | (left >= (value & Mask) ? 1 : 0);
        NZ(left - value, Width);
    }
    private void Arithmetic(int value, bool subtract)
    {
        int left = A & Mask;
        int result = subtract ? left - (value & Mask) - ((P & 1) != 0 ? 0 : 1) :
            left + (value & Mask) + (P & 1);
        P = (P & ~1) | (subtract ? (result >= 0 ? 1 : 0) : (result > Mask ? 1 : 0));
        Load(result);
    }
    private void Push(int value, int count)
    {
        for (int i = count - 1; i >= 0; i--) Memory[0x7E0000 + S--] = (byte)(value >> (8 * i));
    }
    private int Pull(int count)
    {
        int value = 0;
        for (int i = 0; i < count; i++) value |= Memory[0x7E0000 + ++S] << (8 * i);
        return value;
    }
    private void Return() { int low = Pull(2); PC = (Pull(1) << 16) | ((low + 1) & 65535); }
    private void Call(int target)
    {
        Push(PC >> 16, 1); Push((PC - 1) & 65535, 2); PC = target;
    }
    public void Run(int address)
    {
        steps = 0;
        PC = End;
        Call(address);
        while (PC != End)
        {
            if (++steps > 20000) throw new Exception("Music test routine loop at " + PC.ToString("X6"));
            Step();
        }
    }
    private void Step()
    {
        if (PC == 0xC14CE5) { PC = End; return; } // native reset continuation
        if (PC == 0xC755DA) { Pull(2); Return(); return; } // native save continuation: consume displaced PHX
        if (PC == 0xC00021)
        {
            ActorInitializations++;
            X = 0x400; // native C0:4C28 does NOT preserve X
            Return(); return;
        }
        if (PC == 0x01BFE0) { FrameCalls++; Return(); return; }
        if (PC == 0xC0389C) { RngCalls++; Load(7); Return(); return; }
        if (PC == 0xC301F6 || PC == 0xC305B7)
        {
            Commands.Add(new byte[] { (byte)A, (byte)Read(0x2141, 1), (byte)Read(0x2142, 1), (byte)Read(0x2143, 1) });
            Write(0x2140, A, 1);
            PC = 0xC3018D; // don't emulate SPC sample upload, retain native register unwind
            return;
        }
        int start = PC, op = Fetch(), value;
        trace.Enqueue(start.ToString("X6") + ":" + op.ToString("X2") + " S=" + S.ToString("X4") + " P=" + P.ToString("X2"));
        if (trace.Count > 24) trace.Dequeue();
        switch (op)
        {
            case 0x08: Push(P, 1); break;
            case 0x28: P = Pull(1); if (IndexWidth == 1) { X &= 255; Y &= 255; } break;
            case 0xC2: P &= ~Fetch(); break;
            case 0xE2: P |= Fetch(); if (IndexWidth == 1) { X &= 255; Y &= 255; } break;
            case 0x48: Push(A, Width); break;
            case 0x68: Load(Pull(Width)); break;
            case 0xDA: Push(X, IndexWidth); break;
            case 0xFA: X = Pull(IndexWidth); NZ(X, IndexWidth); break;
            case 0x5A: Push(Y, IndexWidth); break;
            case 0x7A: Y = Pull(IndexWidth); NZ(Y, IndexWidth); break;
            case 0x0B: Push(DP, 2); break;
            case 0x2B: DP = Pull(2); NZ(DP, 2); break;
            case 0x8B: Push(DB, 1); break;
            case 0xAB: DB = Pull(1); NZ(DB, 1); break;
            case 0xA9: Load(Operand(Width)); break;
            case 0xA2: X = Operand(IndexWidth); NZ(X, IndexWidth); break;
            case 0xA0: Y = Operand(IndexWidth); NZ(Y, IndexWidth); break;
            case 0xA5: Load(Data(DP + Fetch(), Width)); break;
            case 0xA6: X = Data(DP + Fetch(), IndexWidth); NZ(X, IndexWidth); break;
            case 0xAD: Load(Data((DB << 16) | Operand(2), Width)); break;
            case 0xAF: Load(Data(Operand(3), Width)); break;
            case 0xBF: Load(Data(Operand(3) + X, Width)); break;
            case 0x85: Write(DP + Fetch(), A, Width); break;
            case 0x86: Write(DP + Fetch(), X, IndexWidth); break;
            case 0x8D: Write((DB << 16) | Operand(2), A, Width); break;
            case 0x8F: Write(Operand(3), A, Width); break;
            case 0x9F: Write(Operand(3) + X, A, Width); break;
            case 0x64: Write(DP + Fetch(), 0, Width); break;
            case 0xC9: Compare(Operand(Width)); break;
            case 0xCD: Compare(Data((DB << 16) | Operand(2), Width)); break;
            case 0xCF: Compare(Data(Operand(3), Width)); break;
            case 0xDF: Compare(Data(Operand(3) + X, Width)); break;
            case 0xE4:
                value = Data(DP + Fetch(), IndexWidth);
                P = (P & ~1) | (X >= value ? 1 : 0); NZ(X - value, IndexWidth); break;
            case 0x29: Load(A & Operand(Width)); break;
            case 0x49: Load(A ^ Operand(Width)); break;
            case 0x5F: Load(A ^ Data(Operand(3) + X, Width)); break;
            case 0x18: P &= ~1; break;
            case 0x38: P |= 1; break;
            case 0x69: Arithmetic(Operand(Width), false); break;
            case 0x6F: Arithmetic(Data(Operand(3), Width), false); break;
            case 0xEF: Arithmetic(Data(Operand(3), Width), true); break;
            case 0x0A:
                value = A & Mask; P = (P & ~1) | ((value & (Width == 1 ? 128 : 32768)) != 0 ? 1 : 0);
                Load(value << 1); break;
            case 0x1A: Load(A + 1); break;
            case 0xEB: A = ((A & 255) << 8) | ((A >> 8) & 255); NZ(A & 255, 1); break;
            case 0x8A: Load(X); break;
            case 0xAA: X = A & (IndexWidth == 1 ? 255 : 65535); NZ(X, IndexWidth); break;
            case 0x22: Call(Operand(3)); break;
            case 0x5C: PC = Operand(3); break;
            case 0x4C: PC = (PC & 0xFF0000) | Operand(2); break;
            case 0x6B: Return(); break;
            case 0xEA: break;
            case 0x82: value = (short)Operand(2); PC += value; break;
            case 0x80: value = (sbyte)Fetch(); PC += value; break;
            case 0xD0: value = (sbyte)Fetch(); if ((P & 2) == 0) PC += value; break;
            case 0xF0: value = (sbyte)Fetch(); if ((P & 2) != 0) PC += value; break;
            case 0x30: value = (sbyte)Fetch(); if ((P & 128) != 0) PC += value; break;
            case 0xB0: value = (sbyte)Fetch(); if ((P & 1) != 0) PC += value; break;
            default: throw new Exception("Unsupported test opcode " + op.ToString("X2") + " at " + start.ToString("X6") + "\n" + String.Join("\n", trace.ToArray()));
        }
    }
}
