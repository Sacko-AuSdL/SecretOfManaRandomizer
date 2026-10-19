using SoMRandomizer.config.settings;
using SoMRandomizer.processing.common;

namespace SoMRandomizer.processing.hacks.common.qol
{
    /// <summary>
    /// Optionally replaces Watts's ordinary weapon-upgrade price table.
    /// </summary>
    public class WeaponUpgradeCosts : RandoProcessor
    {
        // Ordinary Watts transactions enter through the shop-menu dispatcher at $C0/7AC3-$C0/7ACA.
        // The forge handler obtains its price through the pointer at $D8/FB82, which points here in vanilla.
        // That price is used by the menu display/affordability path and remains on the stack for the common
        // confirmation subtraction at $C0/7C8C-$C0/7C92 (LDA $7ECC6A; SEC; SBC $01,s).
        // Replacing this one source therefore changes all three consumers together. Event $1B2's special
        // first Sword forge does not use this ordinary price table and remains unchanged.
        //
        // Headerless ROM offset 0x18FCFB = SNES $D8/FCFB.
        // The eight 16-bit little-endian entries are indexed by the weapon's current forge level.
        internal const int WEAPON_UPGRADE_PRICE_TABLE_OFFSET = 0x18FCFB;

        internal static readonly ushort[] REDUCED_WEAPON_UPGRADE_COSTS =
        {
            100,
            100,
            200,
            400,
            750,
            1650,
            3150,
            6250,
        };

        protected override string getName()
        {
            return "Reduced weapon upgrade costs";
        }

        protected override bool process(byte[] origRom, byte[] outRom, string seed, RandoSettings settings, RandoContext context)
        {
            if(settings.get(CommonSettings.PROPERTYNAME_WEAPON_UPGRADE_COSTS) != "reduced")
            {
                return false;
            }

            for(int i = 0; i < REDUCED_WEAPON_UPGRADE_COSTS.Length; i++)
            {
                ushort cost = REDUCED_WEAPON_UPGRADE_COSTS[i];
                int offset = WEAPON_UPGRADE_PRICE_TABLE_OFFSET + i * 2;
                outRom[offset] = (byte)cost;
                outRom[offset + 1] = (byte)(cost >> 8);
            }

            return true;
        }
    }
}
