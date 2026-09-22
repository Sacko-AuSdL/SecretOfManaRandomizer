using SoMRandomizer.processing.openworld.randomization;
using System.Collections.Generic;

namespace SoMRandomizer.processing.openworld.cannon
{
    /// <summary>
    /// Minimal Open World region ownership needed by Cannon reachability. Locations not
    /// listed here remain in the connected Potos/Gaia/Pandora/Water-Palace area unless the
    /// existing upstream Flammie-only list identifies them as remote.
    /// </summary>
    public static class CannonTravelRegions
    {
        private static readonly HashSet<string> UNRESTRICTED_LOCATIONS =
            new HashSet<string>
            {
                "girl",
                "starter weapon (alt)",
                "starter weapon (main)",
                "sword pedestal",
            };

        private static readonly Dictionary<string, CannonTravelRegion> REGION_OVERRIDES =
            new Dictionary<string, CannonTravelRegion>
            {
                { "sylphid item 1 (spells)", CannonTravelRegion.UpperLand },
                { "sylphid item 2 (seed)", CannonTravelRegion.UpperLand },
                { "moogle village glove orb chest", CannonTravelRegion.UpperLand },
                { "moogle village axe orb chest", CannonTravelRegion.UpperLand },

                { "matango flammie", CannonTravelRegion.Matango },
                { "matango inn javelin orb chest", CannonTravelRegion.Matango },
                { "jehk", CannonTravelRegion.Matango },

                { "fire seed", CannonTravelRegion.Kakkara },
                { "kakkara (moogle belt)", CannonTravelRegion.Kakkara },
                { "fire palace axe orb chest", CannonTravelRegion.Kakkara },
                { "fire palace chest 1", CannonTravelRegion.Kakkara },
                { "fire palace chest 2", CannonTravelRegion.Kakkara },

                { "salamando", CannonTravelRegion.IceCountry },
                { "santa (new item)", CannonTravelRegion.IceCountry },
                { "santa spear orb chest", CannonTravelRegion.IceCountry },
                { "ice castle glove orb chest", CannonTravelRegion.IceCountry },
                { "triple tonpole", CannonTravelRegion.IceCountry },

                { "mara (tower key)", CannonTravelRegion.SouthtownEmpire },
                { "northtown ruins sword orb chest", CannonTravelRegion.SouthtownEmpire },
                { "northtown castle axe orb chest", CannonTravelRegion.SouthtownEmpire },
                { "northtown ruins spear orb chest", CannonTravelRegion.SouthtownEmpire },
                { "northtown castle whip orb chest", CannonTravelRegion.SouthtownEmpire },
                { "northtown ruins bow orb chest", CannonTravelRegion.SouthtownEmpire },
                { "northtown castle chest", CannonTravelRegion.SouthtownEmpire },
                { "doom wall", CannonTravelRegion.SouthtownEmpire },
                { "vampire", CannonTravelRegion.SouthtownEmpire },
                { "mech rider 2", CannonTravelRegion.SouthtownEmpire },
                { "metal mantis (new item)", CannonTravelRegion.SouthtownEmpire },
            };

        public static CannonTravelRegion getLocationRegion(string locationName)
        {
            if(UNRESTRICTED_LOCATIONS.Contains(locationName))
            {
                return CannonTravelRegion.Unrestricted;
            }
            if(REGION_OVERRIDES.ContainsKey(locationName))
            {
                return REGION_OVERRIDES[locationName];
            }
            if(OpenWorldPrizes.flammieRequiredLocations.Contains(locationName))
            {
                return CannonTravelRegion.FlammieOnly;
            }
            return CannonTravelRegion.PotosArea;
        }

        public static HashSet<CannonTravelRegion> getReachableRegions(
            ResolvedCannonNetwork network, CannonTravelRegion startingRegion,
            bool hasFlammie, bool matangoUpperLandConnectionOpen)
        {
            HashSet<CannonTravelRegion> reachable = new HashSet<CannonTravelRegion>
            {
                CannonTravelRegion.Unrestricted,
                startingRegion,
            };
            if(hasFlammie)
            {
                foreach(CannonOffice office in CannonTravelModel.OFFICES)
                {
                    reachable.Add(office.LogicalRegion);
                }
                reachable.Add(CannonTravelRegion.FlammieOnly);
                return reachable;
            }

            bool changed;
            do
            {
                changed = false;
                if(matangoUpperLandConnectionOpen)
                {
                    if(reachable.Contains(CannonTravelRegion.Matango))
                    {
                        changed |= reachable.Add(CannonTravelRegion.UpperLand);
                    }
                    if(reachable.Contains(CannonTravelRegion.UpperLand))
                    {
                        changed |= reachable.Add(CannonTravelRegion.Matango);
                    }
                }

                foreach(ResolvedCannonOffice office in network.Offices)
                {
                    if(!reachable.Contains(office.Office.LogicalRegion))
                    {
                        continue;
                    }
                    foreach(ResolvedCannonRoute route in office.Routes)
                    {
                        changed |= reachable.Add(route.Destination.LogicalRegion);
                    }
                }
            }
            while(changed);
            return reachable;
        }
    }
}
