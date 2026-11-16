using SoMRandomizer.config.settings;
using SoMRandomizer.processing.common;
using SoMRandomizer.processing.openworld.cannon;

namespace SoMRandomizer.processing.openworld
{
    /// <summary>
    /// Resolves the optional physical and logical Open World start without consuming RNG.
    /// Christmas goals retain their dedicated Ice Country start, and Flammie-out-of-logic
    /// games retain the existing sword-pedestal sequence regardless of this setting.
    /// </summary>
    public static class OpenWorldStartingLocation
    {
        public const int START_DOOR = 0x82;
        public const int KAKKARA_MAP = SomVanillaValues.MAPNUM_KAKKARA;
        public const int KAKKARA_X = 29;
        public const int KAKKARA_Y = 36;
        public const bool KAKKARA_LAYER2_COLLISION = false;
        public const byte STARTUP_SAFE_TRANSITION = 0x00;
        public const int KAKKARA_MUSIC_EVENT = 0x7C2;
        public const int ICE_COUNTRY_MAP = SomVanillaValues.MAPNUM_TODO;
        public const int ICE_COUNTRY_X = 33, ICE_COUNTRY_Y = 41;
        public const int SOUTHTOWN_MAP = SomVanillaValues.MAPNUM_SOUTHTOWN;
        public const int SOUTHTOWN_X = 39, SOUTHTOWN_Y = 30;

        public sealed class StartingTown
        {
            public readonly string Id;
            public readonly int Map, X, Y, MusicEvent;
            public readonly CannonTravelRegion Region;
            public StartingTown(string id, int map, int x, int y, int music, CannonTravelRegion region)
            { Id = id; Map = map; X = x; Y = y; MusicEvent = music; Region = region; }
        }

        public static StartingTown getTown(RandoSettings settings, RandoContext context)
        {
            if (!settings.getBool(OpenWorldSettings.PROPERTYNAME_FLAMMIE_DRUM_IN_LOGIC)) return null;
            string goal = context.workingData.get(OpenWorldGoalProcessor.GOAL_SHORT_NAME);
            if (goal == OpenWorldGoalProcessor.GOAL_GIFTMODE || goal == OpenWorldGoalProcessor.GOAL_REINDEER) return null;
            switch (settings.get(OpenWorldSettings.PROPERTYNAME_STARTING_LOCATION))
            {
                case OpenWorldSettings.PROPERTYVALUE_STARTING_LOCATION_KAKKARA:
                    return new StartingTown("kakkara", KAKKARA_MAP, KAKKARA_X, KAKKARA_Y, KAKKARA_MUSIC_EVENT, CannonTravelRegion.Kakkara);
                case OpenWorldSettings.PROPERTYVALUE_STARTING_LOCATION_ICE_COUNTRY:
                    return new StartingTown("iceCountry", ICE_COUNTRY_MAP, ICE_COUNTRY_X, ICE_COUNTRY_Y, 0x711, CannonTravelRegion.IceCountry);
                case OpenWorldSettings.PROPERTYVALUE_STARTING_LOCATION_SOUTHTOWN:
                    return new StartingTown("southtown", SOUTHTOWN_MAP, SOUTHTOWN_X, SOUTHTOWN_Y, 0x70D, CannonTravelRegion.SouthtownEmpire);
                default: return null;
            }
        }

        public static bool useAlternateStart(RandoSettings settings, RandoContext context)
        { return getTown(settings, context) != null; }

        public static bool useKakkara(RandoSettings settings, RandoContext context)
        {
            StartingTown town = getTown(settings, context);
            return town != null && town.Id == "kakkara";
        }

        public static CannonTravelRegion getStartingRegion(RandoSettings settings, RandoContext context)
        {
            string goal = context.workingData.get(OpenWorldGoalProcessor.GOAL_SHORT_NAME);
            if(goal == OpenWorldGoalProcessor.GOAL_GIFTMODE ||
                goal == OpenWorldGoalProcessor.GOAL_REINDEER)
            {
                return CannonTravelRegion.IceCountry;
            }
            StartingTown town = getTown(settings, context);
            return town == null ? CannonTravelRegion.PotosArea : town.Region;
        }
    }
}
