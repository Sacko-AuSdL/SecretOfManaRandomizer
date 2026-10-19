using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using static SoMRandomizer.processing.common.SomVanillaValues;
using Slot = SoMRandomizer.processing.common.VanillaBossMaps.VanillaBossMap;

namespace SoMRandomizer.processing.common
{
    public enum BossExecutionKind { Native, Direct, DonorCopy, Specialized }
    public enum BossCapabilityStatus { Unsupported, Implemented }

    /// <summary>Immutable description, NOT a replacement runtime death handler.</summary>
    public sealed class BossEncounterBinding
    {
        public string Destination { get; }
        public int DestinationMap { get; }
        public byte SelectedEncounter { get; }
        public BossExecutionKind Execution { get; }
        public BossCapabilityStatus Capability { get; }
        public string Adapter { get; }
        public int PhysicalMap { get; }
        public int TemplateMap { get; }
        public int DestinationCompletionEvent { get; }
        public int EncounterCompletionEvent { get; }
        public ReadOnlyCollection<int> EntryDoors { get; }
        public ReadOnlyCollection<int> EntryEvents { get; }
        public string CompletionCondition { get; }
        public string DestinationContinuation { get; }
        public string ReentryContract { get; }
        // Named ownership groups intentionally allow the two directions of an
        // existing adapter to SHARE its already-reserved block. These are not
        // free spans or a general-purpose allocation API.
        public ReadOnlyCollection<string> Resources { get; }

        internal BossEncounterBinding(Slot slot, byte boss, BossExecutionKind kind,
            BossCapabilityStatus status, string adapter, int physical, int template,
            int destinationEvent, int encounterEvent, IEnumerable<int> doors,
            IEnumerable<int> events, string condition, string continuation,
            string reentry, IEnumerable<string> resources)
        {
            Destination = slot.name; DestinationMap = slot.originalMapNum;
            SelectedEncounter = boss; Execution = kind; Capability = status;
            Adapter = adapter; PhysicalMap = physical; TemplateMap = template;
            DestinationCompletionEvent = destinationEvent; EncounterCompletionEvent = encounterEvent;
            EntryDoors = Array.AsReadOnly(doors.ToArray()); EntryEvents = Array.AsReadOnly(events.ToArray());
            CompletionCondition = condition; DestinationContinuation = continuation;
            ReentryContract = reentry; Resources = Array.AsReadOnly(resources.ToArray());
        }
    }

    /// <summary>
    /// One snapshot of the EXISTING selector's assignments per generation.
    /// Capability queries delegate in the original order, with no RNG/ROM writes.
    /// Existing adapters still own construction, event edits and collision checks.
    /// </summary>
    public sealed class BossEncounterRegistry
    {
        public ReadOnlyCollection<BossEncounterBinding> Bindings { get; }
        private BossEncounterRegistry(IEnumerable<BossEncounterBinding> bindings)
        { Bindings = Array.AsReadOnly(bindings.ToArray()); }

        public static Slot[] Destinations()
        {
            return VanillaBossMaps.BY_VANILLA_BOSS_ID.Values
                .Concat(new[] { VanillaBossMaps.DOPPELGANGERS }).ToArray();
        }

        public static byte[] GetRandomPool(Slot slot)
        { return DoppelgangerBossArenaRedirect.getOpenWorldRandomPool(slot); }

        public static bool CanSwap(Slot slot, byte boss)
        { return DoppelgangerBossArenaRedirect.canSwapInOpenWorld(slot, boss); }

        public static BossCapabilityStatus Capability(Slot slot, byte boss)
        {
            return GetRandomPool(slot).Contains(boss) || CanSwap(slot, boss)
                ? BossCapabilityStatus.Implemented : BossCapabilityStatus.Unsupported;
        }

        internal static void Capture(RandoContext context, byte[] originalRom, IDictionary<Slot, byte> assignments)
        {
            context.bossEncounters = new BossEncounterRegistry(Destinations().Select(slot =>
                Describe(originalRom, slot, assignments == null ? slot.getOriginalBossId(originalRom) : assignments[slot])));
        }

        private static BossEncounterBinding Describe(byte[] originalRom, Slot slot, byte boss)
        {
            byte native = slot.getOriginalBossId(originalRom);
            var kind = native == boss ? BossExecutionKind.Native : BossExecutionKind.Direct;
            int physical = slot.originalMapNum, template = physical;
            int destinationEvent = slot == VanillaBossMaps.DOPPELGANGERS ? 0x4E5
                : slot == VanillaBossMaps.TRIPLE_TONPOLE ? 0x66A
                : VanillaMapUtil.getObjects(originalRom, physical)[slot.originalObjNum].getEvent();
            int encounterEvent = destinationEvent;
            string adapter = "Native/direct", condition = "Native actor death callback; existing slot event guards";
            string continuation = "Original destination event/prize/progression/return (including NPC handoffs), never donor story";
            string reentry = "Existing destination visibility/completion flags and entry guards";
            var doors = new List<int>();
            for (int door = 0; door < 0x400; door++)
                if (VanillaDoorUtil.getDoor(originalRom, door).getTargetMap() == physical) doors.Add(door);
            var entries = VanillaMapUtil.getTriggers(originalRom, physical).Where(e => e < 0x800).Select(e => (int)e).Distinct().ToList();
            var resources = new List<string>();

            if (slot == VanillaBossMaps.DOPPELGANGERS || boss == DoppelgangerBossArenaRedirect.BOSS_ID)
            {
                adapter = "DoppelgangerBossArenaRedirect";
                bool reverse = slot == VanillaBossMaps.DOPPELGANGERS && boss != native;
                condition = "Native all-three actor $4A status gate";
                if (reverse)
                {
                    kind = BossExecutionKind.DonorCopy; physical = DoppelgangerBossArenaRedirect.MANTIS_MAP;
                    template = MAPNUM_MANTISANT_ARENA;
                    encounterEvent = DoppelgangerBossArenaRedirect.JEHK_DEATH_EVENT;
                    entries = new List<int> { 0x3DB }; doors = new List<int> { 0x304 };
                    condition = "Real bound actor death -> 6BB -> Jehk flag 3F=5 -> guarded 4E5";
                    continuation = "4E5 Jehk prize/3F=6 -> Door038 -> 41B HP/status -> 2F84 MP";
                    reentry = "3F>=6 -> 6BA Door038 only; no spawn/prize";
                }
                else if (boss != native)
                {
                    kind = BossExecutionKind.Specialized; physical = DoppelgangerBossArenaRedirect.SHADOW_MAP;
                    template = MAPNUM_DOPPEL_ARENA; encounterEvent = DoppelgangerBossArenaRedirect.COMPLETION_EVENT;
                    entries = new List<int> { DoppelgangerBossArenaRedirect.ENTRY_EVENT }; doors = new List<int> { 0x08D };
                    condition += " -> Potos=C -> 112"; reentry = "Potos>=C -> 6B9 Door08E only";
                }
                if (boss != native)
                    resources.Add("Doppelganger shared: maps1F1-1F3; ROM08FF50-08FFA3; events6D5/6D6/6B9/6BA/6BB; existing Potos/Jehk flags");
            }
            else if (slot == VanillaBossMaps.DOOMSWALL && DoomWallBossArenaRedirect.requiresRedirect(boss))
            {
                adapter = "DoomWallBossArenaRedirect"; kind = BossExecutionKind.DonorCopy;
                physical = DoomWallBossArenaRedirect.GENERATED_MAP_ID; template = VanillaBossMaps.BY_VANILLA_BOSS_ID[boss].originalMapNum;
                doors = new List<int> { 0x14F, 0x150 }; entries = new List<int> { 0x552 };
                resources.Add("Doom: maps1FE/1FF; ROM08E068-08E077/088FA8-088FB5; pieces3ED/3F5; destination events552/553, return314");
            }
            else if (slot == VanillaBossMaps.LIMESLIME && boss != native || boss == BOSSID_LIMESLIME && boss != native)
            {
                adapter = "LimeSlimeBossArenaRedirect";
                bool reverse = slot == VanillaBossMaps.LIMESLIME;
                kind = reverse ? BossExecutionKind.DonorCopy : BossExecutionKind.Specialized;
                physical = reverse ? LimeSlimeBossArenaRedirect.FOREIGN_IN_SHADE_SLOT_MAP_ID : LimeSlimeBossArenaRedirect.LIME_IN_FOREIGN_SLOT_MAP_ID;
                template = reverse ? VanillaBossMaps.BY_VANILLA_BOSS_ID[boss].originalMapNum : MAPNUM_LIMESLIME_ARENA;
                if (reverse) { doors = new List<int> { 0x03A }; entries = new List<int> { 0x543 }; }
                resources.Add("Lime shared: maps1FA-1FD; ROM08E080-08E0A7/088FCA-088FEE; pieces3E4/3E5/3E6/3DA/0E9; stage Door10B");
                condition = reverse ? condition : "Mode7 death0F -> death02/neutral1FB/dialogue reset -> destination callback";
                if (reverse) continuation = "544 Shade progression -> Door286/orb -> 542 -> Shade NPC586 prize";
            }
            else if (slot == VanillaBossMaps.DREADSLIME && boss != native || boss == BOSSID_DREADSLIME && boss != native)
            {
                adapter = "DreadSlimeBossArenaRedirect";
                bool reverse = slot == VanillaBossMaps.DREADSLIME;
                kind = reverse ? BossExecutionKind.DonorCopy : BossExecutionKind.Specialized;
                physical = reverse ? DreadSlimeBossArenaRedirect.FORTRESS_MAP_ID : DreadSlimeBossArenaRedirect.DREAD_MAP_ID;
                template = reverse ? VanillaBossMaps.BY_VANILLA_BOSS_ID[boss].originalMapNum : MAPNUM_DREADSLIME_ARENA;
                if (reverse) { doors = new List<int> { 0x152 }; entries = new List<int> { 0x424 }; }
                resources.Add("Dread: maps1F6-1F9; ROM08FEE0-08FF17; pieces1B7/3D3/3D4; shared Lime neutral stage");
                condition = reverse ? condition : "Mode7 death0F -> death02/neutral1FB/dialogue reset -> destination callback";
                if (reverse) continuation = "425 Fortress progression/731 -> Door0C0 -> prize -> Door0C0 -> 42C";
            }
            else if (boss == TripleTonpoleBossArenaRedirect.BOSS_ID || slot == VanillaBossMaps.TRIPLE_TONPOLE)
            {
                adapter = "TripleTonpoleBossArenaRedirect";
                if (boss == TripleTonpoleBossArenaRedirect.BOSS_ID && boss != native)
                {
                    kind = BossExecutionKind.Specialized; physical = TripleTonpoleBossArenaRedirect.MAP_ID;
                    template = MAPNUM_TRIPLETONPOLE_ARENA; encounterEvent = TripleTonpoleBossArenaRedirect.DEATH_EVENT;
                    entries = new List<int> { TripleTonpoleBossArenaRedirect.ENTRY_EVENT };
                    condition = "Three real Tonpole/transformed deaths; E3 exact-three guard -> destination callback";
                    resources.Add("Triple: maps1F4/1F5; ROM08FF20-08FF4D; pieces1D7/1D8; events6D2/6D3/6D4; flagE3");
                }
                else condition = boss == native ? "Native exact-three callback -> 66A" : "One bound actor -> 66A; extra Ice actors hidden";
            }
            var capability = Capability(slot, boss);
            // Legacy ordinary plando is not uniform admission. Describe it, but
            // never label an unsupported forced value as an approved capability.
            return new BossEncounterBinding(slot, boss, kind, capability, adapter, physical,
                template, destinationEvent, encounterEvent, doors, entries, condition, continuation, reentry, resources);
        }
    }
}
