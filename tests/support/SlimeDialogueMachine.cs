using System;
using System.Collections.Generic;

// Executes the emitted stage guard and the real vanilla dialogue reset/size
// routines. Not a PPU, event-loop, or full-game emulator.
public sealed class SlimeDialogueMachine
{
    private readonly byte[] rom;
    public readonly byte[] Memory = new byte[0x1000000];
    private readonly List<byte> stack = new List<byte>();
    public int A, X, Y, P = 0x20, DB = 0x7E, PC;
    private int M { get { return (P & 0x20) != 0 ? 1 : 2; } }
    private int I { get { return (P & 0x10) != 0 ? 1 : 2; } }
    public SlimeDialogueMachine(byte[] rom) { this.rom = rom; }
    private int Address(int at) { return (at >> 16) < 0x40 && (at & 0xFFFF) < 0x2000 ? 0x7E0000 + (at & 0xFFFF) : at; }
    public int Read(int at, int size)
    {
        int value = 0;
        for (int i = 0; i < size; i++)
            value |= ((at >> 16) >= 0xC0 ? rom[at - 0xC00000 + i] : Memory[Address(at + i)]) << (8 * i);
        return value;
    }
    public void Write(int at, int value, int size) { for (int i = 0; i < size; i++) Memory[Address(at + i)] = (byte)(value >> (8 * i)); }
    private int Fetch(int size) { int value = Read(PC, size); PC += size; return value; }
    private void Push(int value, int size) { for (int i = size - 1; i >= 0; i--) stack.Add((byte)(value >> (8 * i))); }
    private int Pull(int size)
    {
        int value = 0;
        for (int i = 0; i < size; i++) { int at = stack.Count - 1; value |= stack[at] << (8 * i); stack.RemoveAt(at); }
        return value;
    }
    private void NZ(int value, int size) { int mask = size == 1 ? 255 : 65535; P = (P & ~0x82) | ((value & mask) == 0 ? 2 : 0) | ((value & (size == 1 ? 128 : 32768)) != 0 ? 128 : 0); }
    private void Load(int value) { int mask = M == 1 ? 255 : 65535; A = (A & ~mask) | (value & mask); NZ(A, M); }
    public void Run(int start, bool longReturn)
    {
        stack.Clear();
        if (longReturn) Push(0xFF, 1);
        Push(0xFFFE, 2);
        PC = start;
        for (int steps = 0; steps < 20000; steps++)
        {
            int at = PC, op = Fetch(1), operand, value, mask;
            switch (op)
            {
                case 0x08: Push(P, 1); break;
                case 0x28: P = Pull(1); break;
                case 0xC2: P &= ~Fetch(1); break;
                case 0xE2: P |= Fetch(1); if (I == 1) { X &= 255; Y &= 255; } break;
                case 0x48: Push(A, M); break;
                case 0x68: Load(Pull(M)); break;
                case 0xDA: Push(X, I); break;
                case 0xFA: X = Pull(I); NZ(X, I); break;
                case 0x5A: Push(Y, I); break;
                case 0x7A: Y = Pull(I); NZ(Y, I); break;
                case 0x8B: Push(DB, 1); break;
                case 0xAB: DB = Pull(1); NZ(DB, 1); break;
                case 0xA9: Load(Fetch(M)); break;
                case 0xA2: X = Fetch(I); NZ(X, I); break;
                case 0xA8: Y = A; NZ(Y, I); break;
                case 0xAA: X = A; NZ(X, I); break;
                case 0x98: Load(Y); break;
                case 0xAD: Load(Read((DB << 16) | Fetch(2), M)); break;
                case 0xBD: operand = Fetch(2); Load(Read((DB << 16) | ((operand + X) & 65535), M)); break;
                case 0xAF: Load(Read(Fetch(3), M)); break;
                case 0x8D: Write((DB << 16) | Fetch(2), A, M); break;
                case 0x8F: Write(Fetch(3), A, M); break;
                case 0x8E: Write((DB << 16) | Fetch(2), X, I); break;
                case 0x9C: Write((DB << 16) | Fetch(2), 0, M); break;
                case 0x9E: operand = Fetch(2); Write((DB << 16) | ((operand + X) & 65535), 0, M); break;
                case 0xCA: X = (X - 1) & (I == 1 ? 255 : 65535); NZ(X, I); break;
                case 0xEB: A = ((A & 255) << 8) | (A >> 8); NZ(A & 255, 1); break;
                case 0xC9: operand = Fetch(M); mask = M == 1 ? 255 : 65535; P = (P & ~1) | ((A & mask) >= operand ? 1 : 0); NZ(A - operand, M); break;
                case 0x29: Load(A & Fetch(M)); break;
                case 0x09: Load(A | Fetch(M)); break;
                case 0x1C: operand = (DB << 16) | Fetch(2); value = Read(operand, M); P = (P & ~2) | ((value & A) == 0 ? 2 : 0); Write(operand, value & ~A, M); break;
                case 0x0A: mask = M == 1 ? 255 : 65535; P = (P & ~1) | ((A & (M == 1 ? 128 : 32768)) != 0 ? 1 : 0); Load((A & mask) << 1); break;
                case 0xD0: operand = (sbyte)Fetch(1); if ((P & 2) == 0) PC += operand; break;
                case 0xF0: operand = (sbyte)Fetch(1); if ((P & 2) != 0) PC += operand; break;
                case 0x80: operand = (sbyte)Fetch(1); PC += operand; break;
                case 0x4C: operand = Fetch(2); PC = (PC & 0xFF0000) | operand; break;
                case 0x22: operand = Fetch(3); Push(PC >> 16, 1); Push(PC - 1, 2); PC = operand; break;
                case 0x20: operand = Fetch(2); Push(PC - 1, 2); PC = (PC & 0xFF0000) | operand; break;
                case 0x60: operand = Pull(2) + 1; if (stack.Count == 0) return; PC = (PC & 0xFF0000) | operand; break;
                case 0x6B: operand = Pull(2) + 1; value = Pull(1); if (value == 255 && operand == 65535) { if (stack.Count != 0) throw new Exception("Unbalanced stack."); return; } PC = (value << 16) | operand; break;
                default: throw new Exception("Unsupported dialogue opcode " + op.ToString("X2") + " at " + at.ToString("X6"));
            }
        }
        throw new Exception("Dialogue routine did not finish.");
    }
}
