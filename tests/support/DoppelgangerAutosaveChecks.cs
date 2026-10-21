using System;
public static class DoppelgangerAutosaveChecks
{
    public static int[] Probe(byte[] rom,int door,int hp) {
        var m=new SpellShuffleMachine(rom);m.A=door;m.P=0;m.DB=0x7E;
        m.Write(0x7EA25A,0x2D0,2);
        for(int i=0;i<3;i++){m.Write(0x7EE000+512*i,1,1);m.Write(0x7EE182+512*i,hp,2);}
        m.Stops.Add(0xC755D6);
        int at=rom[0x1E7D7]|rom[0x1E7D8]<<8|rom[0x1E7D9]<<16;
        m.Run(at);
        return new[]{m.Visits.Contains(0xC755D6)?1:0,m.Read(0x7EA25A,2),m.Read(0x7E010E,2)};
    }
    public static int LoadDoor(byte[] rom,int saved,int current) {
        var m=new SpellShuffleMachine(rom);m.P=0;m.Write(0x7EA25A,saved,2);m.Write(0x7E010E,current,2);
        m.Stops.Add(0xC00109);m.Run(0xC00105);return m.A;
    }
}
