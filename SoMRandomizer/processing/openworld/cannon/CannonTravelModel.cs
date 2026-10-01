using SoMRandomizer.config.settings;
using SoMRandomizer.processing.common;
using System;
using System.Collections.Generic;
using System.Linq;

namespace SoMRandomizer.processing.openworld.cannon
{
    public enum CannonTravelRegion
    {
        Unrestricted,
        PotosArea,
        UpperLand,
        Matango,
        Kakkara,
        IceCountry,
        SouthtownEmpire,
        FlammieOnly,
    }

    public sealed class CannonDestination
    {
        internal CannonDestination(string id, string displayName, byte worldX, byte worldY,
            CannonTravelRegion logicalRegion, int postArrivalEvent)
        {
            Id = id;
            DisplayName = displayName;
            WorldX = worldX;
            WorldY = worldY;
            LogicalRegion = logicalRegion;
            PostArrivalEvent = postArrivalEvent;
        }

        public string Id { get; private set; }
        public string DisplayName { get; private set; }
        public byte WorldX { get; private set; }
        public byte WorldY { get; private set; }
        public CannonTravelRegion LogicalRegion { get; private set; }
        public int PostArrivalEvent { get; private set; }
    }

    public sealed class CannonOffice
    {
        internal CannonOffice(string id, string displayName, int mapNumber, int objectIndex,
            int menuEvent, byte sourceWorldX, byte sourceWorldY,
            CannonTravelRegion logicalRegion, string homeDestinationId,
            params int[] existingRouteEvents)
        {
            Id = id;
            DisplayName = displayName;
            MapNumber = mapNumber;
            ObjectIndex = objectIndex;
            MenuEvent = menuEvent;
            SourceWorldX = sourceWorldX;
            SourceWorldY = sourceWorldY;
            LogicalRegion = logicalRegion;
            HomeDestinationId = homeDestinationId;
            ExistingRouteEvents = existingRouteEvents;
        }

        public string Id { get; private set; }
        public string DisplayName { get; private set; }
        public int MapNumber { get; private set; }
        public int ObjectIndex { get; private set; }
        public int MenuEvent { get; private set; }
        public byte SourceWorldX { get; private set; }
        public byte SourceWorldY { get; private set; }
        public CannonTravelRegion LogicalRegion { get; private set; }
        public string HomeDestinationId { get; private set; }
        public int[] ExistingRouteEvents { get; private set; }
    }

    public sealed class ResolvedCannonRoute
    {
        internal ResolvedCannonRoute(CannonOffice office, CannonDestination destination)
        {
            Office = office;
            Destination = destination;
        }

        public CannonOffice Office { get; private set; }
        public CannonDestination Destination { get; private set; }
    }

    public sealed class ResolvedCannonOffice
    {
        internal ResolvedCannonOffice(CannonOffice office, IEnumerable<CannonDestination> destinations,
            string closedMessage)
        {
            Office = office;
            Routes = destinations.Select(destination =>
                new ResolvedCannonRoute(office, destination)).ToList();
            ClosedMessage = closedMessage;
        }

        public CannonOffice Office { get; private set; }
        public List<ResolvedCannonRoute> Routes { get; private set; }
        public string ClosedMessage { get; private set; }
        public bool IsClosed { get { return Routes.Count == 0; } }
    }

    public sealed class ResolvedCannonNetwork
    {
        internal ResolvedCannonNetwork(string mode, IEnumerable<ResolvedCannonOffice> offices)
        {
            Mode = mode;
            Offices = offices.ToList();
        }

        public string Mode { get; private set; }
        public List<ResolvedCannonOffice> Offices { get; private set; }
    }

    /// <summary>
    /// Canonical Cannon offices, reusable vanilla landing endpoints, and the one-shot
    /// deterministic network resolver. The resolved network is serialized into workingData;
    /// all later readers reconstruct it without consuming RNG.
    /// </summary>
    public static class CannonTravelModel
    {
        private const string RESOLVED_MARKER = "cannonTravelResolved";
        private const string MODE_KEY = "cannonTravelResolvedMode";
        private const string ROUTE_COUNT_PREFIX = "cannonTravelRouteCount_";
        private const string ROUTE_PREFIX = "cannonTravelRoute_";
        private const string CLOSED_MESSAGE_PREFIX = "cannonTravelClosedMessage_";

        public const string CLOSED_OFFICE_MESSAGE = "Sorry! I'm on vacation!";

        public static readonly CannonDestination[] DESTINATIONS = new CannonDestination[]
        {
            new CannonDestination("potos", "Potos", 0x9B, 0xBF,
                CannonTravelRegion.PotosArea, 0x610),
            new CannonDestination("gaiasNavel", "Gaia's Navel", 0x85, 0xCA,
                CannonTravelRegion.PotosArea, 0x705),
            new CannonDestination("waterPalace", "Water Palace", 0x84, 0xB7,
                CannonTravelRegion.PotosArea, 0x70E),
            new CannonDestination("upperLand", "Upper Land", 0x88, 0x98,
                CannonTravelRegion.UpperLand, 0x619),
            new CannonDestination("pandora", "Pandora", 0x95, 0xD8,
                CannonTravelRegion.PotosArea, 0x613),
            // $28,$5D is the existing Kakkara endpoint proven reusable by the
            // Potos -> Kakkara runtime diagnostic.
            new CannonDestination("kakkara", "Kakkara", 0x28, 0x5D,
                CannonTravelRegion.Kakkara, 0x61F),
            new CannonDestination("matango", "Matango", 0x68, 0x97,
                CannonTravelRegion.Matango, 0x61C),
            new CannonDestination("iceCountry", "Ice Country", 0xA7, 0x0B,
                CannonTravelRegion.IceCountry, 0x61D),
            new CannonDestination("southtown", "Southtown", 0xE4, 0x65,
                CannonTravelRegion.SouthtownEmpire, 0x620),
        };

        public static readonly CannonOffice[] OFFICES = new CannonOffice[]
        {
            new CannonOffice("upperLand", "Upper Land", 57, 8, 0x0CF, 0x9F, 0xAA,
                CannonTravelRegion.UpperLand, "upperLand", 0x0EF, 0x0F0),
            new CannonOffice("southtown", "Southtown", 155, 8, 0x0E2, 0xE4, 0x65,
                CannonTravelRegion.SouthtownEmpire, "southtown", 0x0E6),
            new CannonOffice("iceCountry", "Ice Country", 156, 8, 0x0E0, 0xB1, 0x26,
                CannonTravelRegion.IceCountry, "iceCountry", 0x0EA, 0x0EB),
            new CannonOffice("kakkara", "Kakkara", 157, 8, 0x0E1, 0x2B, 0x5D,
                CannonTravelRegion.Kakkara, "kakkara", 0x0E7, 0x0E8, 0x0E9),
            new CannonOffice("matango", "Matango", 158, 8, 0x0D0, 0x7A, 0x8B,
                CannonTravelRegion.Matango, "matango", 0x0EC, 0x0ED),
            new CannonOffice("potos", "Potos", 159, 8, 0x0D1, 0x9B, 0xBF,
                CannonTravelRegion.PotosArea, "potos", 0x0FD, 0x0CD),
            new CannonOffice("gaiasNavel", "Gaia's Navel", 171, 8, 0x0DF, 0x7F, 0xC2,
                CannonTravelRegion.PotosArea, "gaiasNavel", 0x0F4, 0x0F5),
        };

        private static readonly CannonTravelRegion[] CANNON_REGIONS = new CannonTravelRegion[]
        {
            CannonTravelRegion.PotosArea,
            CannonTravelRegion.UpperLand,
            CannonTravelRegion.Matango,
            CannonTravelRegion.Kakkara,
            CannonTravelRegion.IceCountry,
            CannonTravelRegion.SouthtownEmpire,
        };

        /// <summary>
        /// Region-level representation of the untouched Open World Cannon routes. This is
        /// used only by placement simulation when an alternate physical start makes the
        /// original Potos-centric coarse reachability model insufficient. It emits no ROM
        /// data and consumes no RNG.
        /// </summary>
        public static ResolvedCannonNetwork getVanillaRegionNetwork()
        {
            Dictionary<string, CannonDestination> destinations = DESTINATIONS.ToDictionary(
                destination => destination.Id);
            Dictionary<string, string[]> routeIds = new Dictionary<string, string[]>
            {
                { "upperLand", new string[] { "potos", "gaiasNavel" } },
                { "southtown", new string[] { "kakkara" } },
                { "iceCountry", new string[] { "matango", "kakkara" } },
                { "kakkara", new string[] { "matango", "iceCountry", "southtown" } },
                // Vanilla event $EC says it goes to the desert and lands at $40,$70,
                // another Kakkara-region endpoint. Event $ED goes to Ice Country.
                { "matango", new string[] { "kakkara", "iceCountry" } },
                { "potos", new string[] { "waterPalace", "upperLand" } },
                { "gaiasNavel", new string[] { "waterPalace", "pandora" } },
            };
            return new ResolvedCannonNetwork(OpenWorldSettings.PROPERTYVALUE_CANNON_TRAVEL_OFF,
                OFFICES.Select(office => new ResolvedCannonOffice(office,
                    routeIds[office.Id].Select(id => destinations[id]), null)));
        }

        public static ResolvedCannonNetwork resolveAndStore(RandoSettings settings, RandoContext context)
        {
            if(context.workingData.hasSetting(RESOLVED_MARKER))
            {
                return getResolvedNetwork(context);
            }

            string mode = settings.get(OpenWorldSettings.PROPERTYNAME_CANNON_TRAVEL_RANDOMIZATION);
            context.workingData.set(MODE_KEY, mode);
            if(mode == OpenWorldSettings.PROPERTYVALUE_CANNON_TRAVEL_OFF)
            {
                // Off consumes no Cannon RNG and publishes no custom routes.
                context.workingData.setInt(RESOLVED_MARKER, 0);
                return new ResolvedCannonNetwork(mode, new ResolvedCannonOffice[] { });
            }

            Dictionary<string, List<CannonDestination>> routes;
            if(mode == OpenWorldSettings.PROPERTYVALUE_CANNON_TRAVEL_OPEN)
            {
                routes = OFFICES.ToDictionary(office => office.Id,
                    office => DESTINATIONS.Where(destination =>
                        destination.Id != office.HomeDestinationId).ToList());
            }
            else if(mode == OpenWorldSettings.PROPERTYVALUE_CANNON_TRAVEL_SHUFFLE)
            {
                routes = buildShuffle(context.randomFunctional);
            }
            else if(mode == OpenWorldSettings.PROPERTYVALUE_CANNON_TRAVEL_CHAOS)
            {
                routes = buildChaos(context.randomFunctional);
            }
            else
            {
                throw new InvalidOperationException("Unsupported Cannon Travel mode: " + mode);
            }

            foreach(CannonOffice office in OFFICES)
            {
                List<CannonDestination> officeRoutes = orderForCompactMenu(routes[office.Id]);
                routes[office.Id] = officeRoutes;
                context.workingData.setInt(ROUTE_COUNT_PREFIX + office.Id, officeRoutes.Count);
                for(int i = 0; i < officeRoutes.Count; i++)
                {
                    context.workingData.set(ROUTE_PREFIX + office.Id + "_" + i,
                        officeRoutes[i].Id);
                }
                if(officeRoutes.Count == 0)
                {
                    context.workingData.set(CLOSED_MESSAGE_PREFIX + office.Id,
                        CLOSED_OFFICE_MESSAGE);
                }
            }
            context.workingData.setInt(RESOLVED_MARKER, 1);
            return getResolvedNetwork(context);
        }

        public static ResolvedCannonNetwork getResolvedNetwork(RandoContext context)
        {
            string mode = context.workingData.hasSetting(MODE_KEY)
                ? context.workingData.get(MODE_KEY)
                : OpenWorldSettings.PROPERTYVALUE_CANNON_TRAVEL_OFF;
            if(!context.workingData.hasSetting(RESOLVED_MARKER) ||
                context.workingData.getInt(RESOLVED_MARKER) != 1)
            {
                return new ResolvedCannonNetwork(mode, new ResolvedCannonOffice[] { });
            }

            Dictionary<string, CannonDestination> destinationsById =
                DESTINATIONS.ToDictionary(destination => destination.Id);
            List<ResolvedCannonOffice> offices = new List<ResolvedCannonOffice>();
            foreach(CannonOffice office in OFFICES)
            {
                int routeCount = context.workingData.getInt(ROUTE_COUNT_PREFIX + office.Id);
                List<CannonDestination> destinations = new List<CannonDestination>();
                for(int i = 0; i < routeCount; i++)
                {
                    destinations.Add(destinationsById[
                        context.workingData.get(ROUTE_PREFIX + office.Id + "_" + i)]);
                }
                string closedMessage = routeCount == 0
                    ? context.workingData.get(CLOSED_MESSAGE_PREFIX + office.Id)
                    : "";
                offices.Add(new ResolvedCannonOffice(office, destinations, closedMessage));
            }
            return new ResolvedCannonNetwork(mode, offices);
        }

        private static Dictionary<string, List<CannonDestination>> buildShuffle(Random random)
        {
            // Bounded retries cover only harmless tie-breaking conflicts. Every attempt begins
            // with a directed region cycle, so successful output is strongly connected by
            // construction rather than by lucky rerolling.
            for(int attempt = 0; attempt < 64; attempt++)
            {
                Dictionary<string, List<CannonDestination>> routes = emptyRoutes();
                Dictionary<string, int> destinationUse = DESTINATIONS.ToDictionary(
                    destination => destination.Id, destination => 0);
                List<CannonTravelRegion> cycle = CANNON_REGIONS.ToList();
                shuffle(cycle, random);

                bool failed = false;
                for(int i = 0; i < cycle.Count; i++)
                {
                    CannonTravelRegion source = cycle[i];
                    CannonTravelRegion target = cycle[(i + 1) % cycle.Count];
                    List<CannonOffice> sourceOffices = OFFICES.Where(candidateOffice =>
                        candidateOffice.LogicalRegion == source &&
                        routes[candidateOffice.Id].Count < candidateOffice.ExistingRouteEvents.Length).ToList();
                    shuffle(sourceOffices, random);
                    CannonOffice office = sourceOffices.OrderBy(candidate =>
                        routes[candidate.Id].Count).First();
                    CannonDestination destination = chooseBalancedDestination(
                        target, routes[office.Id], destinationUse, random);
                    if(destination == null)
                    {
                        failed = true;
                        break;
                    }
                    routes[office.Id].Add(destination);
                    destinationUse[destination.Id]++;
                }
                if(failed)
                {
                    continue;
                }

                List<CannonOffice> fillOrder = OFFICES.ToList();
                shuffle(fillOrder, random);
                foreach(CannonOffice office in fillOrder)
                {
                    while(routes[office.Id].Count < office.ExistingRouteEvents.Length)
                    {
                        List<CannonDestination> candidates = DESTINATIONS.Where(candidateDestination =>
                            candidateDestination.LogicalRegion != office.LogicalRegion &&
                            !routes[office.Id].Any(existing => existing.Id == candidateDestination.Id)).ToList();
                        shuffle(candidates, random);
                        CannonDestination destination = candidates
                            .OrderBy(candidate => destinationUse[candidate.Id])
                            .FirstOrDefault();
                        if(destination == null)
                        {
                            failed = true;
                            break;
                        }
                        routes[office.Id].Add(destination);
                        destinationUse[destination.Id]++;
                    }
                    if(failed)
                    {
                        break;
                    }
                }

                if(!failed && destinationUse.Values.All(count => count > 0) &&
                    isStronglyConnected(routes))
                {
                    return routes;
                }
            }
            throw new InvalidOperationException(
                "Unable to construct a bounded, strongly connected Cannon shuffle.");
        }

        private static Dictionary<string, List<CannonDestination>> buildChaos(Random random)
        {
            Dictionary<string, List<CannonDestination>> routes = emptyRoutes();
            List<CannonTravelRegion> shuffledRegions = CANNON_REGIONS.ToList();
            shuffle(shuffledRegions, random);
            int componentCount = 1 + random.Next(shuffledRegions.Count);
            List<List<CannonTravelRegion>> components = new List<List<CannonTravelRegion>>();
            for(int i = 0; i < componentCount; i++)
            {
                components.Add(new List<CannonTravelRegion> { shuffledRegions[i] });
            }
            for(int i = componentCount; i < shuffledRegions.Count; i++)
            {
                components[random.Next(componentCount)].Add(shuffledRegions[i]);
            }

            foreach(List<CannonTravelRegion> component in components)
            {
                if(component.Count > 1)
                {
                    shuffle(component, random);
                    for(int i = 0; i < component.Count; i++)
                    {
                        CannonTravelRegion source = component[i];
                        CannonTravelRegion target = component[(i + 1) % component.Count];
                        List<CannonOffice> offices = OFFICES.Where(candidateOffice =>
                            candidateOffice.LogicalRegion == source).ToList();
                        shuffle(offices, random);
                        CannonOffice office = offices.First(candidate =>
                            routes[candidate.Id].Count < candidate.ExistingRouteEvents.Length);
                        List<CannonDestination> targets = DESTINATIONS.Where(destination =>
                            destination.LogicalRegion == target).ToList();
                        routes[office.Id].Add(targets[random.Next(targets.Count)]);
                    }
                }

                foreach(CannonOffice office in OFFICES.Where(candidate =>
                    component.Contains(candidate.LogicalRegion)))
                {
                    int desiredCount = random.Next(office.ExistingRouteEvents.Length + 1);
                    desiredCount = Math.Max(desiredCount, routes[office.Id].Count);
                    while(routes[office.Id].Count < desiredCount)
                    {
                        List<CannonDestination> candidates = DESTINATIONS.Where(destination =>
                            component.Contains(destination.LogicalRegion) &&
                            destination.LogicalRegion != office.LogicalRegion &&
                            !routes[office.Id].Any(existing => existing.Id == destination.Id)).ToList();
                        if(candidates.Count == 0)
                        {
                            break;
                        }
                        shuffle(candidates, random);
                        routes[office.Id].Add(candidates[0]);
                    }
                }
            }

            return routes;
        }

        private static CannonDestination chooseBalancedDestination(CannonTravelRegion region,
            List<CannonDestination> officeRoutes, Dictionary<string, int> destinationUse,
            Random random)
        {
            List<CannonDestination> candidates = DESTINATIONS.Where(destination =>
                destination.LogicalRegion == region &&
                !officeRoutes.Any(existing => existing.Id == destination.Id)).ToList();
            shuffle(candidates, random);
            return candidates.OrderBy(candidate => destinationUse[candidate.Id]).FirstOrDefault();
        }

        private static Dictionary<string, List<CannonDestination>> emptyRoutes()
        {
            return OFFICES.ToDictionary(office => office.Id,
                office => new List<CannonDestination>());
        }

        private static List<CannonDestination> orderForCompactMenu(
            List<CannonDestination> destinations)
        {
            if(destinations.Count != 3)
            {
                return destinations;
            }
            for(int first = 0; first < 3; first++)
            {
                List<CannonDestination> pair = destinations.Where((value, index) =>
                    index != first).ToList();
                for(int swap = 0; swap < 2; swap++)
                {
                    CannonDestination second = pair[swap];
                    CannonDestination third = pair[1 - swap];
                    if(("50 GP! 1:" + destinations[first].DisplayName).Length <= 28 &&
                        ("2:" + second.DisplayName + " 3:" + third.DisplayName).Length <= 28)
                    {
                        return new List<CannonDestination>
                        {
                            destinations[first], second, third,
                        };
                    }
                }
            }
            throw new InvalidOperationException(
                "No safe 28-character Cannon menu ordering exists.");
        }

        private static void shuffle<T>(List<T> values, Random random)
        {
            for(int i = values.Count - 1; i > 0; i--)
            {
                int other = random.Next(i + 1);
                T temp = values[i];
                values[i] = values[other];
                values[other] = temp;
            }
        }

        public static bool isStronglyConnected(
            Dictionary<string, List<CannonDestination>> routes)
        {
            Dictionary<CannonTravelRegion, HashSet<CannonTravelRegion>> edges =
                CANNON_REGIONS.ToDictionary(region => region,
                    region => new HashSet<CannonTravelRegion>());
            foreach(CannonOffice office in OFFICES)
            {
                foreach(CannonDestination destination in routes[office.Id])
                {
                    edges[office.LogicalRegion].Add(destination.LogicalRegion);
                }
            }
            return allReachable(edges, CANNON_REGIONS[0], false) &&
                allReachable(edges, CANNON_REGIONS[0], true);
        }

        private static bool allReachable(
            Dictionary<CannonTravelRegion, HashSet<CannonTravelRegion>> edges,
            CannonTravelRegion start, bool reverse)
        {
            HashSet<CannonTravelRegion> visited = new HashSet<CannonTravelRegion> { start };
            Queue<CannonTravelRegion> pending = new Queue<CannonTravelRegion>();
            pending.Enqueue(start);
            while(pending.Count > 0)
            {
                CannonTravelRegion current = pending.Dequeue();
                IEnumerable<CannonTravelRegion> next = reverse
                    ? edges.Where(pair => pair.Value.Contains(current)).Select(pair => pair.Key)
                    : edges[current];
                foreach(CannonTravelRegion region in next)
                {
                    if(visited.Add(region))
                    {
                        pending.Enqueue(region);
                    }
                }
            }
            return CANNON_REGIONS.All(visited.Contains);
        }
    }
}
