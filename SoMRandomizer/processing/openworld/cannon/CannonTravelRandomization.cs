using SoMRandomizer.config.settings;
using SoMRandomizer.processing.common;
using SoMRandomizer.processing.common.structure;
using SoMRandomizer.util;
using System;
using System.Collections.Generic;
using System.Linq;

namespace SoMRandomizer.processing.openworld.cannon
{
    /// <summary>
    /// Emits the cached Cannon network through the vanilla event/payment/flight machinery.
    /// $C1:E849 and $C1:E863 are the runtime-confirmed descriptor reads. Non-Off modes
    /// redirect their long-address operands to a generated 64-entry descriptor table.
    /// Event command $1D masks its operand with $003F at $C1:EB47; bit $40 has separate
    /// engine semantics and is never used by generated route IDs.
    /// </summary>
    public class CannonTravelRandomization : RandoProcessor
    {
        internal const int ROUTE_LOOKUP_SOURCE_OFFSET = 0x1E849;
        internal const int ROUTE_LOOKUP_TARGET_OFFSET = 0x1E863;
        internal const int VANILLA_ROUTE_TABLE_OFFSET = 0x67C80;
        internal const int GENERATED_ROUTE_TABLE_SIZE = 0x100;
        internal const byte FIRST_GENERATED_ROUTE_ID = 0x20;
        internal const byte FIRST_OPEN_ROUTE_ID = 0x00;
        internal const byte MAX_ROUTE_ID = 0x3F;
        private const int DIALOGUE_LINE_WIDTH = 28;
        internal const string ROUTE_TABLE_WORKING_DATA_KEY = "cannonTravelRouteTableOffset";

        private static readonly Dictionary<string, string> OPEN_OVERVIEW_NAMES =
            new Dictionary<string, string>
            {
                { "potos", "Potos" },
                { "gaiasNavel", "Gaia" },
                { "waterPalace", "Water" },
                { "upperLand", "Upper" },
                { "pandora", "Pandora" },
                { "kakkara", "Kakkara" },
                { "matango", "Matango" },
                { "iceCountry", "Ice" },
                { "southtown", "Southtown" },
            };

        // These two vanilla ranges are contiguous END-only events in US 1.0. Open needs
        // 21 framed three-choice page events, 56 route events, and seven standalone root
        // selectors: eight non-self destinations for each of seven offices. We validate
        // every used slot before replacing it and reject generator conflicts.
        private static readonly int[] OPEN_EVENT_POOL =
            Enumerable.Range(0x74B, 0x77F - 0x74B + 1)
                .Concat(Enumerable.Range(0x7A1, 0x7BF - 0x7A1 + 1)).ToArray();
        private static readonly int[] OPEN_PAGE_EVENTS = OPEN_EVENT_POOL.Take(
            CannonTravelModel.OFFICES.Length * 3).ToArray();
        private static readonly int[] OPEN_ROUTE_EVENTS = OPEN_EVENT_POOL.Skip(
            OPEN_PAGE_EVENTS.Length).Take(CannonTravelModel.OFFICES.Length *
            (CannonTravelModel.DESTINATIONS.Length - 1)).ToArray();
        private static readonly int[] OPEN_SELECTOR_EVENTS = OPEN_EVENT_POOL.Skip(
            OPEN_PAGE_EVENTS.Length + OPEN_ROUTE_EVENTS.Length).Take(
                CannonTravelModel.OFFICES.Length).ToArray();

        protected override string getName()
        {
            return "Open World Cannon Travel network";
        }

        protected override bool process(byte[] origRom, byte[] outRom, string seed,
            RandoSettings settings, RandoContext context)
        {
            string mode = settings.get(OpenWorldSettings.PROPERTYNAME_CANNON_TRAVEL_RANDOMIZATION);
            if(mode == OpenWorldSettings.PROPERTYVALUE_CANNON_TRAVEL_OFF)
            {
                // Deliberately do not even call the resolver: Off writes no Cannon data,
                // replaces no events, and consumes no RNG.
                return false;
            }

            ResolvedCannonNetwork network = CannonTravelModel.resolveAndStore(settings, context);
            int routeTableOffset = createExpandedRouteTable(outRom, context);
            context.workingData.setInt(ROUTE_TABLE_WORKING_DATA_KEY, routeTableOffset);

            if(mode == OpenWorldSettings.PROPERTYVALUE_CANNON_TRAVEL_OPEN)
            {
                emitOpenEvents(origRom, outRom, context, network, routeTableOffset);
            }
            else
            {
                emitSlotPreservingEvents(outRom, context, network, routeTableOffset);
            }
            return true;
        }

        private static int createExpandedRouteTable(byte[] outRom, RandoContext context)
        {
            if(outRom[ROUTE_LOOKUP_SOURCE_OFFSET] != 0xBF ||
                outRom[ROUTE_LOOKUP_TARGET_OFFSET] != 0xBF)
            {
                throw new InvalidOperationException(
                    "Cannon descriptor lookup opcodes no longer match $C1:E849/$C1:E863.");
            }

            CodeGenerationUtils.ensureSpaceInBank(ref context.workingOffset,
                GENERATED_ROUTE_TABLE_SIZE);
            int tableOffset = context.workingOffset;
            // Preserve all 64 current-output descriptors before overlaying generated routes.
            // This retains unused vanilla slots and any earlier Open World landing fixes.
            Array.Copy(outRom, VANILLA_ROUTE_TABLE_OFFSET, outRom, tableOffset,
                GENERATED_ROUTE_TABLE_SIZE);
            context.workingOffset += GENERATED_ROUTE_TABLE_SIZE;

            int tableCpuAddress = tableOffset + 0xC00000;
            writeLongOperand(outRom, ROUTE_LOOKUP_SOURCE_OFFSET + 1, tableCpuAddress);
            writeLongOperand(outRom, ROUTE_LOOKUP_TARGET_OFFSET + 1, tableCpuAddress + 2);
            return tableOffset;
        }

        private static void writeLongOperand(byte[] outRom, int operandOffset, int cpuAddress)
        {
            outRom[operandOffset] = (byte)cpuAddress;
            outRom[operandOffset + 1] = (byte)(cpuAddress >> 8);
            outRom[operandOffset + 2] = (byte)(cpuAddress >> 16);
        }

        private static void emitSlotPreservingEvents(byte[] outRom, RandoContext context,
            ResolvedCannonNetwork network, int tableOffset)
        {
            byte routeId = FIRST_GENERATED_ROUTE_ID;
            foreach(ResolvedCannonOffice resolvedOffice in network.Offices)
            {
                CannonOffice office = resolvedOffice.Office;
                if(resolvedOffice.IsClosed)
                {
                    EventScript closed = new EventScript();
                    closed.AddDialogueBox(resolvedOffice.ClosedMessage);
                    closed.End();
                    context.replacementEvents[office.MenuEvent] = closed;
                    continue;
                }

                if(resolvedOffice.Routes.Count > office.ExistingRouteEvents.Length)
                {
                    throw new InvalidOperationException(office.DisplayName +
                        " resolved more routes than its existing menu slots.");
                }

                List<int> routeEvents = new List<int>();
                foreach(ResolvedCannonRoute route in resolvedOffice.Routes)
                {
                    if(routeId > MAX_ROUTE_ID)
                    {
                        throw new InvalidOperationException(
                            "Generated Cannon route ID exceeds the event command's $003F mask.");
                    }
                    int routeEvent = office.ExistingRouteEvents[routeEvents.Count];
                    writeDescriptor(outRom, tableOffset, routeId, office, route.Destination);
                    context.replacementEvents[routeEvent] = makeRouteEvent(
                        route.Destination, routeId);
                    routeEvents.Add(routeEvent);
                    routeId++;
                }
                context.replacementEvents[office.MenuEvent] = makeDestinationMenu(
                    resolvedOffice.Routes.Select(route => route.Destination).ToList(),
                    routeEvents);
            }
        }

        private static void emitOpenEvents(byte[] origRom, byte[] outRom,
            RandoContext context, ResolvedCannonNetwork network, int tableOffset)
        {
            int destinationsPerOffice = CannonTravelModel.DESTINATIONS.Length - 1;
            if(OPEN_PAGE_EVENTS.Length != CannonTravelModel.OFFICES.Length * 3 ||
                OPEN_ROUTE_EVENTS.Length != CannonTravelModel.OFFICES.Length *
                    destinationsPerOffice ||
                OPEN_SELECTOR_EVENTS.Length != CannonTravelModel.OFFICES.Length)
            {
                throw new InvalidOperationException("Open Cannon event-pool sizing is invalid.");
            }
            foreach(int eventId in OPEN_PAGE_EVENTS.Concat(OPEN_ROUTE_EVENTS).Concat(
                OPEN_SELECTOR_EVENTS))
            {
                EventScript vanilla = VanillaEventUtil.getVanillaEvent(origRom, eventId);
                if(vanilla.Count != 1 || vanilla[0] != EventCommandEnum.END.Value ||
                    context.replacementEvents.ContainsKey(eventId))
                {
                    throw new InvalidOperationException("Open Cannon event slot 0x" +
                        eventId.ToString("X3") + " is no longer safely unused.");
                }
            }

            for(int officeIndex = 0; officeIndex < network.Offices.Count; officeIndex++)
            {
                ResolvedCannonOffice resolvedOffice = network.Offices[officeIndex];
                if(resolvedOffice.Routes.Count != destinationsPerOffice ||
                    resolvedOffice.Routes.Any(route =>
                        route.Destination.Id == resolvedOffice.Office.HomeDestinationId))
                {
                    throw new InvalidOperationException(
                        "Open Cannon office must contain exactly eight non-self destinations.");
                }

                List<int> routeEvents = new List<int>();
                for(int destinationIndex = 0;
                    destinationIndex < resolvedOffice.Routes.Count; destinationIndex++)
                {
                    int routeEventIndex = officeIndex * destinationsPerOffice + destinationIndex;
                    int routeEvent = OPEN_ROUTE_EVENTS[routeEventIndex];
                    int routeIdValue = FIRST_OPEN_ROUTE_ID + routeEventIndex;
                    if(routeIdValue > MAX_ROUTE_ID)
                    {
                        throw new InvalidOperationException(
                            "Generated Cannon route ID exceeds the event command's $003F mask.");
                    }
                    byte routeId = (byte)routeIdValue;
                    CannonDestination destination =
                        resolvedOffice.Routes[destinationIndex].Destination;
                    writeDescriptor(outRom, tableOffset, routeId,
                        resolvedOffice.Office, destination);
                    context.replacementEvents[routeEvent] = makeRouteEvent(
                        destination, routeId);
                    routeEvents.Add(routeEvent);
                }

                int selectorEvent = OPEN_SELECTOR_EVENTS[officeIndex];
                int[] pageEvents = new int[3];
                for(int page = 0; page < pageEvents.Length; page++)
                {
                    int pageEvent = OPEN_PAGE_EVENTS[officeIndex * 3 + page];
                    pageEvents[page] = pageEvent;
                    int firstDestination = page * 3;
                    List<CannonDestination> pageDestinations = resolvedOffice.Routes
                        .Skip(firstDestination).Take(3).Select(route =>
                            route.Destination).ToList();
                    List<int> pageRouteEvents = routeEvents.Skip(firstDestination)
                        .Take(3).ToList();
                    context.replacementEvents[pageEvent] = makeOpenRoutePage(
                        firstDestination, pageDestinations, pageRouteEvents,
                        selectorEvent);
                }
                context.replacementEvents[selectorEvent] = makeOpenPageSelector(pageEvents);
                context.replacementEvents[resolvedOffice.Office.MenuEvent] =
                    makeOpenMenu(resolvedOffice.Routes.Select(route =>
                        route.Destination).ToList(), selectorEvent);
            }
        }

        private static void writeDescriptor(byte[] outRom, int tableOffset, byte routeId,
            CannonOffice office, CannonDestination destination)
        {
            int offset = tableOffset + routeId * 4;
            outRom[offset] = office.SourceWorldX;
            outRom[offset + 1] = office.SourceWorldY;
            outRom[offset + 2] = destination.WorldX;
            outRom[offset + 3] = destination.WorldY;
        }

        private static EventScript makeDestinationMenu(List<CannonDestination> destinations,
            List<int> routeEvents)
        {
            EventScript menu = makePaidMenuPrefix();
            string prompt = makeCompactDestinationPrompt(destinations);
            byte[] positions = Enumerable.Range(0, destinations.Count)
                .Select(index => (byte)(2 + index * 5)).ToArray();
            string[] choices = Enumerable.Range(1, destinations.Count)
                .Select(index => index.ToString()).ToArray();
            byte[][] commands = routeEvents.Select(EventScript.GetJumpCmd).ToArray();
            menu.AddDialogueBoxWithChoices(prompt, positions, choices, commands,
                EventScript.GetJumpCmd(0x0FF));
            menu.End();
            return menu;
        }

        private static EventScript makeOpenMenu(List<CannonDestination> destinations,
            int selectorEvent)
        {
            if(destinations.Count != 8)
            {
                throw new InvalidOperationException(
                    "Open Cannon menu requires exactly eight destinations.");
            }

            EventScript menu = makePaidMenuPrefix();
            // The runtime dialogue window reliably exposes only three lines. Show one compact,
            // fully framed overview with one line per page, then open the proven three-choice
            // page selector in a separate frame. No CLEAR_DIALOGUE continuation is used.
            menu.AddDialogueBox(makeOpenPageOverview(destinations));
            // Do not append the selector as $51 $50 in this event. Runtime testing showed
            // that the newly opened frame appeared but its choices did not. Jump to a fresh
            // event whose first command is the proven vanilla-style $50/$58 choice pattern.
            menu.Jump(selectorEvent);
            menu.End();
            return menu;
        }

        private static EventScript makeOpenPageSelector(int[] pageEvents)
        {
            if(pageEvents.Length != 3)
            {
                throw new InvalidOperationException(
                    "Open Cannon page selector requires exactly three pages.");
            }

            EventScript selector = new EventScript();
            // Emit the known-good three-choice ordering explicitly:
            // OPEN_DIALOGUE, prompt, OPTION_SELECTION, three OPTION_AT entries,
            // OPTION_SELECTION_END, cancel jump, page jumps, END.
            selector.Add(EventCommandEnum.OPEN_DIALOGUE.Value);
            foreach(byte value in VanillaEventUtil.getBytes("50 GP! Choose page:\n"))
            {
                selector.Add(value);
            }
            selector.Add(EventCommandEnum.OPTION_SELECTION.Value);
            byte[] positions = new byte[] { 2, 7, 12 };
            for(int page = 0; page < pageEvents.Length; page++)
            {
                selector.Add(EventCommandEnum.OPTION_AT.Value, positions[page]);
                foreach(byte value in VanillaEventUtil.getBytes((page + 1).ToString()))
                {
                    selector.Add(value);
                }
            }
            selector.Add(EventCommandEnum.OPTION_SELECTION_END.Value);
            selector.Add(EventScript.GetJumpCmd(0x0FF));
            foreach(int pageEvent in pageEvents)
            {
                selector.Add(EventScript.GetJumpCmd(pageEvent));
            }
            selector.End();
            return selector;
        }

        private static EventScript makeOpenRoutePage(int firstDestination,
            List<CannonDestination> destinations, List<int> routeEvents, int rootMenuEvent)
        {
            if(destinations.Count != routeEvents.Count ||
                (destinations.Count != 2 && destinations.Count != 3))
            {
                throw new InvalidOperationException(
                    "Open Cannon route page requires two or three destinations.");
            }

            List<string> choices = Enumerable.Range(firstDestination + 1,
                destinations.Count).Select(number => number.ToString()).ToList();
            List<byte[]> commands = routeEvents.Select(EventScript.GetJumpCmd).ToList();
            if(destinations.Count == 2)
            {
                choices.Add("Back");
                commands.Add(EventScript.GetJumpCmd(rootMenuEvent));
            }

            EventScript page = new EventScript();
            // Full destination names occupy at most two prompt lines. The proven numeric
            // three-choice row is therefore always within the third visible line.
            page.AddDialogueBoxWithChoices(makeOpenRoutePagePrompt(firstDestination,
                destinations),
                new byte[] { 2, 7, 12 }, choices.ToArray(), commands.ToArray(),
                EventScript.GetJumpCmd(rootMenuEvent));
            page.End();
            return page;
        }

        private static EventScript makePaidMenuPrefix()
        {
            EventScript menu = new EventScript();
            menu.SetFlag(EventFlags.NOT_ENOUGH_GOLD_FLAG, 0);
            menu.Jsr(0x408);
            menu.Add(EventCommandEnum.OPEN_GP.Value);
            menu.Add(0x5F);
            return menu;
        }

        private static EventScript makeRouteEvent(CannonDestination destination, byte routeId)
        {
            if(routeId > MAX_ROUTE_ID)
            {
                throw new InvalidOperationException(
                    "Cannon event operand exceeds the six-bit route namespace.");
            }
            EventScript route = new EventScript();
            // Exact common wrapper used by the existing paid Cannon route events:
            // remove 50 GP, reject via $0F/$F8 if payment failed, launch, fly, then
            // continue through the destination's existing post-arrival event.
            route.Add(EventCommandEnum.REMOVE_GOLD.Value, 0x32, 0x00, 0x5F);
            route.Logic(EventFlags.NOT_ENOUGH_GOLD_FLAG, 1, 0xF,
                EventScript.GetJumpCmd(0x0F8));
            route.Jsr(0x797);
            route.Jsr(0x410);
            route.OpenDialogueBox();
            route.AddDialogue("Next stop: " + destination.DisplayName + "!\n", null);
            route.Jsr(0x0FC);
            route.Add(EventCommandEnum.CANNON_FROM_POS.Value, routeId);
            route.Jsr(0x0F7);
            route.Jump(destination.PostArrivalEvent);
            route.End();
            return route;
        }

        private static string makeCompactDestinationPrompt(List<CannonDestination> destinations)
        {
            if(destinations.Count == 1)
            {
                return "50 GP! 1:" + destinations[0].DisplayName + "\n";
            }
            if(destinations.Count == 2)
            {
                return "50 GP! 1:" + destinations[0].DisplayName + "\n" +
                    "2:" + destinations[1].DisplayName + "\n";
            }
            if(destinations.Count == 3)
            {
                string first = "50 GP! 1:" + destinations[0].DisplayName;
                string second = "2:" + destinations[1].DisplayName + " 3:" +
                    destinations[2].DisplayName;
                if(first.Length > DIALOGUE_LINE_WIDTH ||
                    second.Length > DIALOGUE_LINE_WIDTH)
                {
                    throw new InvalidOperationException(
                        "Resolved Cannon menu does not fit the 28-character dialogue width.");
                }
                return first + "\n" + second + "\n";
            }
            throw new InvalidOperationException("Cannon menu must contain one to three routes.");
        }

        private static string makeOpenPageOverview(List<CannonDestination> destinations)
        {
            if(destinations.Count != 8)
            {
                throw new InvalidOperationException(
                    "Open Cannon overview requires exactly eight destinations.");
            }

            List<string> lines = new List<string>();
            for(int page = 0; page < 3; page++)
            {
                int first = page * 3;
                List<string> names = destinations.Skip(first).Take(3).Select(destination =>
                {
                    string compactName;
                    if(!OPEN_OVERVIEW_NAMES.TryGetValue(destination.Id, out compactName))
                    {
                        throw new InvalidOperationException(
                            "Open Cannon destination has no compact overview name: " +
                            destination.Id);
                    }
                    return compactName;
                }).ToList();
                string line = (page + 1) + ":" + string.Join("/", names);
                if(line.Length > DIALOGUE_LINE_WIDTH)
                {
                    throw new InvalidOperationException(
                        "Open Cannon overview exceeds the 28-character dialogue width.");
                }
                lines.Add(line);
            }
            return string.Join("\n", lines);
        }

        private static string makeOpenRoutePagePrompt(int firstDestination,
            List<CannonDestination> destinations)
        {
            List<string> entries = destinations.Select((destination, index) =>
                (firstDestination + index + 1) + ":" + destination.DisplayName).ToList();
            for(int split = 1; split < entries.Count; split++)
            {
                string first = string.Join(" ", entries.Take(split));
                string second = string.Join(" ", entries.Skip(split));
                if(first.Length <= DIALOGUE_LINE_WIDTH &&
                    second.Length <= DIALOGUE_LINE_WIDTH)
                {
                    return first + "\n" + second + "\n";
                }
            }

            if(entries.Count == 2)
            {
                string singleLine = string.Join(" ", entries);
                if(singleLine.Length <= DIALOGUE_LINE_WIDTH)
                {
                    return singleLine + "\n";
                }
            }
            throw new InvalidOperationException(
                "Open Cannon route page does not fit in two dialogue lines.");
        }
    }
}
