using SoMRandomizer.config.settings;
using SoMRandomizer.processing.common;
using SoMRandomizer.util;
using System;
using System.IO;

namespace SoMRandomizer.processing.hacks.common.other
{
    /// <summary>
    /// Optionally replaces only the Mana Beast's Mode-7 tiles and palette.
    /// </summary>
    public class ManaBeastAppearance : RandoProcessor
    {
        internal const int CLOSEUP_TILES_OFFSET = 0x1A1000;
        internal const int CLOSEUP_TILES_SIZE = 0x14F4;
        internal const int NORMAL_TILES_OFFSET = 0x1A37F8;
        internal const int NORMAL_TILES_SIZE = 0x210B;
        internal const int PALETTE_65_OFFSET = 0x02F9DE;
        internal const int PALETTE_65_SIZE = 0x1E;

        internal const string CLOSEUP_TILES_RESOURCE = "SoMRandomizer.Resources.manaBeast.manabeast_closeup-18.sombosstiles";
        internal const string NORMAL_TILES_RESOURCE = "SoMRandomizer.Resources.manaBeast.manabeast-19.sombosstiles";
        internal const string PALETTE_65_RESOURCE = "SoMRandomizer.Resources.manaBeast.BossPalette65.palette";

        protected override string getName()
        {
            return "Super Rabite Mana Beast appearance";
        }

        protected override bool process(byte[] origRom, byte[] outRom, string seed, RandoSettings settings, RandoContext context)
        {
            if(settings.get(CommonSettings.PROPERTYNAME_MANA_BEAST_APPEARANCE) != "superRabite")
            {
                return false;
            }

            writeExactResource(outRom, CLOSEUP_TILES_OFFSET, CLOSEUP_TILES_SIZE, CLOSEUP_TILES_RESOURCE);
            writeExactResource(outRom, NORMAL_TILES_OFFSET, NORMAL_TILES_SIZE, NORMAL_TILES_RESOURCE);
            writeExactResource(outRom, PALETTE_65_OFFSET, PALETTE_65_SIZE, PALETTE_65_RESOURCE);
            return true;
        }

        private static void writeExactResource(byte[] outRom, int offset, int expectedSize, string resourceName)
        {
            byte[] resourceData = DataUtil.readResource(resourceName);
            if(resourceData.Length != expectedSize)
            {
                throw new InvalidDataException(resourceName + " must be exactly 0x" + expectedSize.ToString("X") + " bytes, but was 0x" + resourceData.Length.ToString("X") + ".");
            }
            if(offset < 0 || offset + expectedSize > outRom.Length)
            {
                throw new ArgumentException("Output ROM is too small for " + resourceName + ".", "outRom");
            }

            Array.Copy(resourceData, 0, outRom, offset, expectedSize);
        }
    }
}
