using SoMRandomizer.config.settings;
using SoMRandomizer.processing.common;
using SoMRandomizer.processing.openworld;
using System.Collections.Generic;

namespace SoMRandomizer.processing.hacks.openworld
{
    public enum CrystalOrbRequirementType
    {
        Magic,
        SpecificWeapon,
    }

    public sealed class CrystalOrbRequirement
    {
        internal CrystalOrbRequirement(int mapNumber, int orbEvent, string routeName,
            CrystalOrbRequirementType type, byte value)
        {
            MapNumber = mapNumber;
            OrbEvent = orbEvent;
            RouteName = routeName;
            Type = type;
            Value = value;
        }

        public int MapNumber { get; private set; }
        public int OrbEvent { get; private set; }
        public string RouteName { get; private set; }
        public CrystalOrbRequirementType Type { get; private set; }
        // Magic: element-family byte $81-$88. SpecificWeapon: weapon ID 0-7.
        public byte Value { get; private set; }
    }

    /// <summary>
    /// Resolves the complete Crystal Orb requirement set once, after character roles and
    /// ElementSwaps are known and before Open World placement. Later systems reconstruct the
    /// immutable result from workingData; they never consume RNG or independently reroll it.
    /// </summary>
    public static class CrystalOrbRequirements
    {
        private const string RESOLVED_MARKER = "crystalOrbRequirementsResolved";
        private const string TYPE_PREFIX = "crystalOrbRequirementType";
        private const string VALUE_PREFIX = "crystalOrbRequirementValue";

        internal sealed class Route
        {
            internal Route(int mapNumber, int orbEvent, string routeName)
            {
                MapNumber = mapNumber;
                OrbEvent = orbEvent;
                RouteName = routeName;
            }

            internal int MapNumber { get; private set; }
            internal int OrbEvent { get; private set; }
            internal string RouteName { get; private set; }
        }

        internal static readonly Route[] ROUTES = new Route[]
        {
            new Route(ElementSwaps.ORBMAP_EARTHPALACE, 0x239, "Earth Palace"),
            new Route(ElementSwaps.ORBMAP_MATANGO, 0x27E, "Matango"),
            new Route(ElementSwaps.ORBMAP_FIREPALACE1, 0x2C8, "Fire Palace 1"),
            new Route(ElementSwaps.ORBMAP_FIREPALACE2, 0x6CB, "Fire Palace 2"),
            new Route(ElementSwaps.ORBMAP_FIREPALACE3, 0x6CE, "Fire Palace 3"),
            new Route(ElementSwaps.ORBMAP_UPPERLAND, 0x25A, "Upper Land"),
            new Route(ElementSwaps.ORBMAP_LUNAPALACE, 0x2C4, "Luna Palace"),
            new Route(ElementSwaps.ORBMAP_GRANDPALACE1, 0x570, "Grand Palace 1"),
            new Route(ElementSwaps.ORBMAP_GRANDPALACE2, 0x571, "Grand Palace 2"),
            new Route(ElementSwaps.ORBMAP_GRANDPALACE3, 0x572, "Grand Palace 3"),
            new Route(ElementSwaps.ORBMAP_GRANDPALACE4, 0x573, "Grand Palace 4"),
            new Route(ElementSwaps.ORBMAP_GRANDPALACE5, 0x574, "Grand Palace 5"),
            new Route(ElementSwaps.ORBMAP_GRANDPALACE6, 0x575, "Grand Palace 6"),
            new Route(ElementSwaps.ORBMAP_GRANDPALACE7, 0x576, "Grand Palace 7"),
        };

        public static bool isEnabled(RandoSettings settings)
        {
            string mode = settings.get(OpenWorldSettings.PROPERTYNAME_CRYSTAL_ORB_WEAPON_BREAKING);
            return mode == OpenWorldSettings.PROPERTYVALUE_CRYSTAL_ORB_WEAPON_BREAKING_ON ||
                mode == OpenWorldSettings.PROPERTYVALUE_CRYSTAL_ORB_WEAPON_BREAKING_WEAPON_ONLY;
        }

        public static bool isWeaponOnly(RandoSettings settings)
        {
            return settings.get(OpenWorldSettings.PROPERTYNAME_CRYSTAL_ORB_WEAPON_BREAKING) ==
                OpenWorldSettings.PROPERTYVALUE_CRYSTAL_ORB_WEAPON_BREAKING_WEAPON_ONLY;
        }

        /// <summary>
        /// Select each active Orb's one requirement. When its ElementSwaps family is usable by an
        /// actual generated role, Magic and SpecificWeapon are equally likely. Otherwise the Orb
        /// is SpecificWeapon. Weapon families are selected uniformly from IDs 0-7.
        /// </summary>
        public static Dictionary<int, CrystalOrbRequirement> resolveAndStore(
            RandoSettings settings, RandoContext context)
        {
            if(context.workingData.hasSetting(RESOLVED_MARKER))
            {
                return getResolvedRequirements(context);
            }

            if(!isEnabled(settings))
            {
                context.workingData.setInt(RESOLVED_MARKER, 0);
                return new Dictionary<int, CrystalOrbRequirement>();
            }

            bool girlMagicExists = context.workingData.getBool(OpenWorldClassSelection.GIRL_MAGIC_EXISTS);
            bool spriteMagicExists = context.workingData.getBool(OpenWorldClassSelection.SPRITE_MAGIC_EXISTS);
            bool weaponOnly = isWeaponOnly(settings);
            HashSet<byte> validOrbMagicFamilies = new HashSet<byte>(
                ElementSwaps.GetValidOrbElements(girlMagicExists, spriteMagicExists));
            Dictionary<int, byte> elementsByMap = ElementSwaps.getCrystalOrbElementMap(context);

            foreach(Route route in ROUTES)
            {
                if(!elementsByMap.ContainsKey(route.MapNumber) || elementsByMap[route.MapNumber] == 0xFF)
                {
                    continue;
                }

                byte element = elementsByMap[route.MapNumber];
                bool magicIsValid = validOrbMagicFamilies.Contains(element);
                CrystalOrbRequirementType type = !weaponOnly && magicIsValid && context.randomFunctional.Next() % 2 == 0
                    ? CrystalOrbRequirementType.Magic
                    : CrystalOrbRequirementType.SpecificWeapon;
                byte value = type == CrystalOrbRequirementType.Magic
                    ? element
                    : (byte)(context.randomFunctional.Next() % 8);

                context.workingData.setInt(TYPE_PREFIX + route.MapNumber, (int)type);
                context.workingData.setInt(VALUE_PREFIX + route.MapNumber, value);
            }
            context.workingData.setInt(RESOLVED_MARKER, 1);
            return getResolvedRequirements(context);
        }

        /// <summary>Return only the already-resolved requirements. This never consumes RNG.</summary>
        public static Dictionary<int, CrystalOrbRequirement> getResolvedRequirements(RandoContext context)
        {
            Dictionary<int, CrystalOrbRequirement> requirementsByMap =
                new Dictionary<int, CrystalOrbRequirement>();
            if(!hasResolvedRequirements(context))
            {
                return requirementsByMap;
            }

            foreach(Route route in ROUTES)
            {
                string typeKey = TYPE_PREFIX + route.MapNumber;
                string valueKey = VALUE_PREFIX + route.MapNumber;
                if(!context.workingData.hasSetting(typeKey) || !context.workingData.hasSetting(valueKey))
                {
                    continue;
                }
                requirementsByMap[route.MapNumber] = new CrystalOrbRequirement(
                    route.MapNumber, route.OrbEvent, route.RouteName,
                    (CrystalOrbRequirementType)context.workingData.getInt(typeKey),
                    (byte)context.workingData.getInt(valueKey));
            }
            return requirementsByMap;
        }

        /// <summary>
        /// True only when the feature resolver published its authoritative requirement set.
        /// This distinguishes feature On from the feature-Off marker without consuming RNG.
        /// </summary>
        public static bool hasResolvedRequirements(RandoContext context)
        {
            return context.workingData.hasSetting(RESOLVED_MARKER) &&
                context.workingData.getInt(RESOLVED_MARKER) == 1;
        }

        public static string getPrizeDependency(CrystalOrbRequirement requirement)
        {
            if(requirement.Type == CrystalOrbRequirementType.Magic)
            {
                return SomVanillaValues.elementOrbByteToName(requirement.Value, false) + " spells";
            }
            return SomVanillaValues.weaponByteToName(requirement.Value).ToLowerInvariant();
        }

        public static string getDisplayName(CrystalOrbRequirement requirement)
        {
            if(requirement.Type == CrystalOrbRequirementType.Magic)
            {
                return SomVanillaValues.elementOrbByteToName(requirement.Value, true);
            }
            return SomVanillaValues.weaponByteToName(requirement.Value);
        }
    }
}
