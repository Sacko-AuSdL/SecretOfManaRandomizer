using System;
using System.Collections.Generic;

// Focused 65816 instruction runner, not an animation/game emulator. It executes
// the emitted hooks, native spell-ID/metadata loaders and native spell queue.
// Map loading itself is an explicit boundary; its original call is counted.
public sealed class SpellShuffleMachine
{
    public readonly byte[] Memory = new byte[0x1000000];
    public readonly byte[] Rom;
    public readonly HashSet<int> Writes = new HashSet<int>();
    public readonly HashSet<int> Visits = new HashSet<int>();
    public readonly HashSet<int> Stops = new HashSet<int>();
    public int SpecialEvents, LastSpecialEvent, LastSpecialTarget;
    public bool ExecuteSpecialEventDispatch;
    public int EventStarts, LastEventOwner;
    public bool EmulateMathHardware;
    public int? FixedRandom;
    public int A, X, Y, P=0x20, S=0x1FF, DP, DB=0x7E, PC, MapLoads;
    private const int End=0xFFFFFF;
    private int W { get { return (P&0x20)!=0 ? 1 : 2; } }
    private int IW { get { return (P&0x10)!=0 ? 1 : 2; } }
    private int Mask { get { return W==1 ? 255 : 65535; } }
    public SpellShuffleMachine(byte[] rom) { Rom=rom; }
    private int Address(int a)
    {
        int bank=a>>16, low=a&65535;
        return ((bank<0x40 || bank>=0x80 && bank<0xC0) && low<0x2000) ? 0x7E0000+low : a&0xFFFFFF;
    }
    public int Read(int a,int n)
    {
        if((a>>16)>=0xC0) return Rom[a-0xC00000] | (n==2 ? Rom[a-0xC00000+1]<<8 : 0);
        int value=0; for(int i=0;i<n;i++) value |= Memory[Address(a+i)]<<(8*i); return value;
    }
    public void Write(int a,int v,int n)
    {
        for(int i=0;i<n;i++) { int at=Address(a+i); Memory[at]=(byte)(v>>(8*i)); Writes.Add(at); }
        if(EmulateMathHardware && a==0x004203) Write(0x004216,Read(0x004202,1)*Read(0x004203,1),2);
        if(EmulateMathHardware && a==0x004206) {
            int dividend=Read(0x004204,2), divisor=Read(0x004206,1);
            Write(0x004214,divisor==0 ? 65535 : dividend/divisor,2);
            Write(0x004216,divisor==0 ? dividend : dividend%divisor,2);
        }
    }
    private int Fetch() { return Rom[PC++-0xC00000]; }
    private int O(int n) { int v=0; for(int i=0;i<n;i++) v|=Fetch()<<(8*i); return v; }
    private int Abs() { return DB*65536+O(2); }
    private void NZ(int v,int n)
    {
        int mask=n==1?255:65535;
        P=(P&~0x82)|((v&mask)==0?2:0)|((v&(n==1?128:32768))!=0?128:0);
    }
    private void L(int v) { A=(A&~Mask)|(v&Mask); NZ(A,W); }
    private void C(int v,int left,int n)
    {
        int mask=n==1?255:65535; P=(P&~1)|((left&mask)>=(v&mask)?1:0); NZ(left-v,n);
    }
    private void Math(int v,bool subtract)
    {
        int left=A&Mask, right=v&Mask;
        int result=subtract ? left-right-((P&1)==0?1:0) : left+right+(P&1);
        P=(P&~0x41)|(subtract ? (result>=0?1:0) : (result>Mask?1:0)) |
            (((subtract ? (left^right)&(left^result) : ~(left^right)&(left^result))&(W==1?128:32768))!=0 ? 0x40 : 0);
        L(result);
    }
    private void Push(int v,int n) { for(int i=n-1;i>=0;i--) Write(S--,v>>(8*i),1); }
    private int Pull(int n) { int v=0; for(int i=0;i<n;i++) v|=Read(++S,1)<<(8*i); return v; }
    private void Call(int a) { Push(PC>>16,1); Push((PC-1)&65535,2); PC=a; }
    private void Return() { int low=Pull(2); PC=(Pull(1)<<16)|((low+1)&65535); }
    public void Run(int at,bool shortReturn=false)
    {
        PC=End;
        if(shortReturn) { Push(0xFFFE,2); PC=at; } else Call(at);
        for(int steps=0;PC!=End;steps++)
        {
            if(steps>30000) throw new Exception("Spell routine loop at "+PC.ToString("X6"));
            Visits.Add(PC);
            if(Stops.Contains(PC)) break;
            if(PC==0x02AA5C) { MapLoads++; Return(); continue; }
            // Optional bounded RNG primitive for native effect-formula tests only.
            if(PC==0xC03884 && FixedRandom.HasValue) { L(FixedRandom.Value); Return(); continue; }
            if(PC==0x018000) {
                SpecialEvents++; LastSpecialEvent=A&65535; LastSpecialTarget=Y;
                // Optional REAL native dispatcher, including its busy guard and
                // event-pointer setup. Never synthesize $00D4 from Y in the runner.
                if(ExecuteSpecialEventDispatch) PC=0xC18000; else Return();
                continue;
            }
            if(ExecuteSpecialEventDispatch && PC==0xC1E88D) {
                // Explicit animation boundary AFTER actual event acceptance.
                // Return from native JSR $E77B; no animation/frame emulation.
                EventStarts++; LastEventOwner=Read(0x7E00D4,2);
                // $E77B saved X below the JSR return address; the normal startup
                // tail restores it before RTS. Preserve that exact stack shape.
                X=Pull(2); NZ(X,2);
                PC=0xC10000|((Pull(2)+1)&65535); continue;
            }
            Step();
        }
    }
    private void Branch(bool take) { int delta=(sbyte)O(1); if(take) PC+=delta; }
    private void Step()
    {
        int at=PC, op=Fetch(), v;
        switch(op)
        {
            case 0x08: Push(P,1); break;
            case 0x28: P=Pull(1); if(IW==1) { X&=255; Y&=255; } break;
            case 0xC2: P&=~O(1); break;
            case 0xE2: P|=O(1); if(IW==1) { X&=255; Y&=255; } break;
            case 0x48: Push(A,W); break;
            case 0x68: L(Pull(W)); break;
            case 0xDA: Push(X,IW); break;
            case 0xFA: X=Pull(IW); NZ(X,IW); break;
            case 0x5A: Push(Y,IW); break;
            case 0x7A: Y=Pull(IW); NZ(Y,IW); break;
            case 0x8B: Push(DB,1); break;
            case 0x0B: Push(DP,2); break;
            case 0x2B: DP=Pull(2); NZ(DP,2); break;
            case 0x5B: DP=A&65535; NZ(DP,2); break;
            case 0x3B: L(S); break;
            case 0xAB: DB=Pull(1); NZ(DB,1); break;
            case 0xA9: L(O(W)); break;
            case 0xAD: L(Read(Abs(),W)); break;
            case 0xAF: L(Read(O(3),W)); break;
            case 0xBF: L(Read(O(3)+X,W)); break;
            case 0xBD: L(Read(Abs()+X,W)); break;
            case 0xB9: L(Read(Abs()+Y,W)); break;
            case 0xA5: L(Read(DP+O(1),W)); break;
            case 0xA7: L(Read(Read(DP+O(1),3),W)); break;
            case 0xB7: L(Read(Read(DP+O(1),3)+Y,W)); break;
            case 0xB5: L(Read(DP+O(1)+X,W)); break;
            case 0xA3: L(Read(S+O(1),W)); break;
            case 0x8D: Write(Abs(),A,W); break;
            case 0x8F: Write(O(3),A,W); break;
            case 0x9F: Write(O(3)+X,A,W); break;
            case 0x9D: Write(Abs()+X,A,W); break;
            case 0x99: Write(Abs()+Y,A,W); break;
            case 0x85: Write(DP+O(1),A,W); break;
            case 0x84: Write(DP+O(1),Y,IW); break;
            case 0x86: Write(DP+O(1),X,IW); break;
            case 0x64: Write(DP+O(1),0,W); break;
            case 0x83: Write(S+O(1),A,W); break;
            case 0x9C: Write(Abs(),0,W); break;
            case 0x9E: Write(Abs()+X,0,W); break;
            case 0xA2: X=O(IW); NZ(X,IW); break;
            case 0xA0: Y=O(IW); NZ(Y,IW); break;
            case 0xAE: X=Read(Abs(),IW); NZ(X,IW); break;
            case 0xBE: X=Read(Abs()+Y,IW); NZ(X,IW); break;
            case 0xAC: Y=Read(Abs(),IW); NZ(Y,IW); break;
            case 0xA6: X=Read(DP+O(1),IW); NZ(X,IW); break;
            case 0xA4: Y=Read(DP+O(1),IW); NZ(Y,IW); break;
            case 0x8A: L(X); break;
            case 0x98: L(Y); break;
            case 0xAA: X=A&(IW==1?255:65535); NZ(X,IW); break;
            case 0xA8: Y=A&(IW==1?255:65535); NZ(Y,IW); break;
            case 0xEB: A=((A&255)<<8)|(A>>8); NZ(A,1); break;
            case 0x0A: v=A&Mask; P=(P&~1)|((v&(W==1?128:32768))!=0?1:0); L(v<<1); break;
            case 0x4A: v=A&Mask; P=(P&~1)|(v&1); L(v>>1); break;
            case 0x46: v=DP+O(1); int shifted=Read(v,W); P=(P&~1)|(shifted&1); Write(v,shifted>>1,W); NZ(shifted>>1,W); break;
            case 0x89: v=O(W); P=(P&~2)|((A&v&Mask)==0?2:0); break;
            case 0x3C: v=Read(Abs()+X,W); P=(P&~0xC2)|(v&(W==1?0xC0:0xC000))>>(W==1?0:8)|((A&v&Mask)==0?2:0); break;
            case 0x29: L(A&O(W)); break;
            case 0x3F: L(A&Read(O(3)+X,W)); break;
            case 0x1F: L(A|Read(O(3)+X,W)); break;
            case 0x91: Write(DB*65536+Read(DP+O(1),2)+Y,A,W); break;
            case 0x23: L(A&Read(S+O(1),W)); break;
            case 0x09: L(A|O(W)); break;
            case 0x18: P&=~1; break;
            case 0x38: P|=1; break;
            case 0x69: Math(O(W),false); break;
            case 0x63: Math(Read(S+O(1),W),false); break;
            case 0x6D: Math(Read(Abs(),W),false); break;
            case 0x6F: Math(Read(O(3),W),false); break;
            case 0x7D: Math(Read(Abs()+X,W),false); break;
            case 0x79: Math(Read(Abs()+Y,W),false); break;
            case 0x65: Math(Read(DP+O(1),W),false); break;
            case 0xE9: Math(O(W),true); break;
            case 0xED: Math(Read(Abs(),W),true); break;
            case 0xE5: Math(Read(DP+O(1),W),true); break;
            case 0xFF: Math(Read(O(3)+X,W),true); break;
            case 0xC9: C(O(W),A,W); break;
            case 0xCF: C(Read(O(3),W),A,W); break;
            case 0xC5: C(Read(DP+O(1),W),A,W); break;
            case 0xDF: C(Read(O(3)+X,W),A,W); break;
            case 0xDD: C(Read(Abs()+X,W),A,W); break;
            case 0xD9: C(Read(Abs()+Y,W),A,W); break;
            case 0xE0: C(O(IW),X,IW); break;
            case 0xC0: C(O(IW),Y,IW); break;
            case 0x1A: L(A+1); break;
            case 0x3A: L(A-1); break;
            case 0xE8: X=(X+1)&(IW==1?255:65535); NZ(X,IW); break;
            case 0xCA: X=(X-1)&(IW==1?255:65535); NZ(X,IW); break;
            case 0xC8: Y=(Y+1)&(IW==1?255:65535); NZ(Y,IW); break;
            case 0x88: Y=(Y-1)&(IW==1?255:65535); NZ(Y,IW); break;
            case 0xEE: v=Abs(); int r=Read(v,W)+1; Write(v,r,W); NZ(r,W); break;
            case 0xC6: v=DP+O(1); int dec=Read(v,W)-1; Write(v,dec,W); NZ(dec,W); break;
            case 0xF0: Branch((P&2)!=0); break;
            case 0xD0: Branch((P&2)==0); break;
            case 0x90: Branch((P&1)==0); break;
            case 0xB0: Branch((P&1)!=0); break;
            case 0x10: Branch((P&128)==0); break;
            case 0x30: Branch((P&128)!=0); break;
            case 0x80: Branch(true); break;
            case 0x82: v=(short)O(2); PC+=v; break;
            case 0x22: v=O(3); Call(v); break;
            case 0x6B: Return(); break;
            case 0x20: v=O(2); Push((PC-1)&65535,2); PC=(PC&0xFF0000)|v; break;
            case 0xFC: v=O(2); v=Read((PC&0xFF0000)+v+X,2); Push((PC-1)&65535,2); PC=(PC&0xFF0000)|v; break;
            case 0x4C: v=O(2); PC=(PC&0xFF0000)|v; break;
            case 0x5C: PC=O(3); break;
            case 0x7C: v=O(2); PC=(PC&0xFF0000)|Read((PC&0xFF0000)+v+X,2); break;
            case 0x60: v=Pull(2); PC=v==0xFFFE ? End : (PC&0xFF0000)|((v+1)&65535); break;
            case 0xEA: break;
            default: throw new Exception("Unsupported spell instruction "+op.ToString("X2")+" at "+at.ToString("X6"));
        }
    }
}
