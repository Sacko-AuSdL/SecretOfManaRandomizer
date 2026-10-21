using System;
// Execute the ROM's actual C1:251A VM dispatcher, $30/$BD/$2E/$DC
// handlers, relative branches and status store; animation is an explicit boundary.
public static class DoppelgangerDeathLinkChecks
{
    public static int[] Changes(byte[] a,byte[] b) { var c=new System.Collections.Generic.List<int>();for(int i=0;i<a.Length;i++)if(a[i]!=b[i])c.Add(i);return c.ToArray(); }
    public static bool Check(byte[] rom,int script,int species,int slot,int hp,int status)
    {
        var m=new SpellShuffleMachine(rom);m.Y=0xE600;m.DB=0x7E;m.P=0x20;
        m.Write(0x7EE7E7,species,1);m.Write(0x7EE782,800,2);
        for(int i=0;i<3;i++){m.Write(0x7EE182+i*512,100,2);m.Write(0x7EE191+i*512,0,1);}
        m.Write(0x7EE182+slot*512,hp,2);m.Write(0x7EE191+slot*512,status,1);
        m.Write(0x7EE744,script-0x104F15,2);
        for(int i=0;i<20;i++) {
            int pc=m.Read(0x7EE744,2)+0x104F15;
            if(rom[pc]==0 || pc>=0x10A773) return (m.Read(0x7EE791,1)&128)!=0;
            // Stop after a real $DC sets the death bit; do not emulate frames.
            m.Run(0xC1251A,true);
            if((m.Read(0x7EE791,1)&128)!=0)return true;
        }
        throw new Exception("Native shadow VM did not reach its return.");
    }
    public static bool OwnDeath(byte[] rom) {
        var m=new SpellShuffleMachine(rom);m.Y=0xE600;m.DB=0x7E;m.P=0x20;
        m.Write(0x7EE782,0,2);m.Write(0x7EE744,0x57E7,2);
        m.Run(0xC1251A,true);m.Run(0xC1251A,true);
        return (m.Read(0x7EE791,1)&128)!=0;
    }
}
