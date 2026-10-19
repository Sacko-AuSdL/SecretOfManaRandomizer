using SoMRandomizer.config.settings;
using SoMRandomizer.processing.common;
using SoMRandomizer.processing.common.structure;
using System;
using static SoMRandomizer.processing.common.SomVanillaValues;

namespace SoMRandomizer.processing.hacks.openworld
{
    /// <summary>
    /// Remove all regular enemies.
    /// </summary>
    /// 
    /// <remarks>Author: Moppleton</remarks>
    public class NoEnemies : RandoProcessor
    {
        protected override bool process(byte[] origRom, byte[] outRom, string seed, RandoSettings settings, RandoContext context)
        {
            for (int mapNum = 16; mapNum < 500; mapNum++)
            {
                // skip tasnica miniboss, karon ferry
                if (mapNum != MAPNUM_TASNICA_THRONE_ROOM_NPC && mapNum != MAPNUM_KARONFERRY_ENDPOINTS && 
                    mapNum != MAPNUM_KARONFERRY_TRAVELING_UP && mapNum != MAPNUM_KARONFERRY_TRAVELING_DOWN)
                {
                    // Traverse native spans only. Generated pointers in outRom must not turn
                    // an empty native map (such as 499, before generated map 500) into code/data.
                    int start = VanillaMapUtil.getObjectOffset(origRom, mapNum) + 8;
                    int end = VanillaMapUtil.getObjectOffset(origRom, mapNum + 1);
                    for (int offset = start; offset < end; offset += 8)
                    {
                        // Keep prior output mutations; origRom supplies boundaries, not object state.
                        byte[] objectData = new byte[8];
                        Array.Copy(outRom, offset, objectData, 0, objectData.Length);
                        MapObject obj = new MapObject(objectData);
                        // object species in normal enemy range
                        if(obj.getSpecies() < 84
                            && !DoppelgangerBossArenaRedirect.preserveNativeShadow(context, mapNum, obj.getSpecies()))
                        {
                            obj.setNeverVisible();
                        }
                        // write it back
                        obj.put(outRom, offset);
                    }
                }
            }
            return true;
        }

        protected override string getName()
        {
            return "No enemies mode";
        }
    }
}
