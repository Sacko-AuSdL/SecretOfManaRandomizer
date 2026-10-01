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

        public static bool useKakkara(RandoSettings settings, RandoContext context)
        {
            if(!settings.getBool(OpenWorldSettings.PROPERTYNAME_FLAMMIE_DRUM_IN_LOGIC) ||
                settings.get(OpenWorldSettings.PROPERTYNAME_STARTING_LOCATION) !=
                    OpenWorldSettings.PROPERTYVALUE_STARTING_LOCATION_KAKKARA)
            {
                return false;
            }

            string goal = context.workingData.get(OpenWorldGoalProcessor.GOAL_SHORT_NAME);
            return goal != OpenWorldGoalProcessor.GOAL_GIFTMODE &&
                goal != OpenWorldGoalProcessor.GOAL_REINDEER;
        }

        public static CannonTravelRegion getStartingRegion(RandoSettings settings, RandoContext context)
        {
            string goal = context.workingData.get(OpenWorldGoalProcessor.GOAL_SHORT_NAME);
            if(goal == OpenWorldGoalProcessor.GOAL_GIFTMODE ||
                goal == OpenWorldGoalProcessor.GOAL_REINDEER)
            {
                return CannonTravelRegion.IceCountry;
            }
            return useKakkara(settings, context)
                ? CannonTravelRegion.Kakkara
                : CannonTravelRegion.PotosArea;
        }
    }
}
