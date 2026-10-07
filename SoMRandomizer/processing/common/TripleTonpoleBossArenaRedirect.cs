using SoMRandomizer.processing.common.structure;
using SoMRandomizer.util;
using System;
using System.Collections.Generic;
using System.Linq;
using static SoMRandomizer.processing.common.SomVanillaValues;

namespace SoMRandomizer.processing.common
{
    /// <summary>
    /// Open World's independent Ice Palace encounter and private three-actor
    /// Tonpole arena. $80 is a selection sentinel, NEVER an actor species.
    /// Ordinary Ice bosses still use the native arena and upstream $66A tail.
    /// </summary>
    public static class TripleTonpoleBossArenaRedirect
    {
        public const byte BOSS_ID = VanillaBossMaps.VanillaBossMap.TRIPLE_TONPOLE_OBJECT_INDICATOR;
        public const string PROPERTY_ICE_BOSS = "IcePalaceBoss";
        public const string PROPERTY_SLOT_MAP = "TripleTonpoleForeignSlotMap";
        private const string PROPERTY_DEATH_EVENT = "TripleTonpoleForeignDeathEvent";
        public const int MAP_ID = 0x1F4; // $1F5 is the empty pointer sentinel
        public const int OBJECT_OFFSET = 0x8FF20; // header + three native objects (32 bytes)
        public const int REFS_OFFSET = 0x8FF40; // native $1D7 / $1D8 references (12 bytes)
        public const int TRIGGER_OFFSET = 0x8FF4C; // one private walk-on (2 bytes)
        public const int DEATH_EVENT = 0x6D2;
        public const int ENTRY_EVENT = 0x6D3;
        public const int UNDINE_RETURN_EVENT = 0x6D4;
        // Unused chest flag, outside the OW prize/orb and Christmas flag pools.
        // Do NOT use $25 here: it controls the independent native Ice boss.
        public const byte COUNT_FLAG = EventFlags.UNUSED_CHEST_VISIBILITY_FLAG_E3;

        private static readonly Dictionary<int, int> ENTRY_DOORS = new Dictionary<int, int>
        {
            { MAPNUM_MANTISANT_ARENA, 0x08D }, { MAPNUM_WALLFACE_ARENA, 0x032 },
            { MAPNUM_TROPICALLO_ARENA, 0x051 }, { MAPNUM_JABBERWOCKY_ARENA, 0x0A0 },
            { MAPNUM_MECHRIDER2_ARENA, 0x35D }, { MAPNUM_WATERMELON_ARENA, 0x358 },
            { MAPNUM_MECHRIDER3_ARENA, 0x3F6 }, { MAPNUM_FROSTGIGAS_ARENA, 0x2CA },
            { MAPNUM_FIREGIGAS_ARENA, 0x14B }, { MAPNUM_TONPOLE_ARENA, 0x144 },
        };

        // Exactly the ordinary bosses formerly copied from Undine Cave. No
        // unsupported jumping, wall, dragon, or Mode-7 species are added.
        public static readonly byte[] ICE_BOSSES = VanillaBossMaps.TONPOLE.allSupportedBosses
            .Concat(new[] { BOSS_ID }).ToArray();

        public static void reset(RandoContext context)
        {
            context.workingData.setInt(PROPERTY_SLOT_MAP, -1);
        }

        public static bool isSafeTarget(VanillaBossMaps.VanillaBossMap slot)
        {
            return ENTRY_DOORS.ContainsKey(slot.originalMapNum);
        }

        public static bool isNativeTriple(RandoContext context)
        {
            return context.workingData.hasSetting(PROPERTY_ICE_BOSS)
                && context.workingData.getInt(PROPERTY_ICE_BOSS) == BOSS_ID;
        }

        public static bool hasForeignTriple(RandoContext context)
        {
            return context.workingData.hasSetting(PROPERTY_SLOT_MAP)
                && context.workingData.getInt(PROPERTY_SLOT_MAP) >= 0;
        }

        public static byte[] getOpenWorldRandomPool(VanillaBossMaps.VanillaBossMap slot)
        {
            if (slot == VanillaBossMaps.TRIPLE_TONPOLE) return ICE_BOSSES;
            byte[] pool = DreadSlimeBossArenaRedirect.getOpenWorldRandomPool(slot);
            return isSafeTarget(slot) ? pool.Concat(new[] { BOSS_ID }).ToArray() : pool;
        }

        public static bool canSwapInOpenWorld(VanillaBossMaps.VanillaBossMap slot, byte boss)
        {
            if (slot == VanillaBossMaps.TRIPLE_TONPOLE) return ICE_BOSSES.Contains(boss);
            if (boss == BOSS_ID) return isSafeTarget(slot);
            return DreadSlimeBossArenaRedirect.canSwapInOpenWorld(slot, boss);
        }

        public static void create(byte[] rom, RandoContext context,
            VanillaBossMaps.VanillaBossMap slot, ushort deathEvent)
        {
            if (!isSafeTarget(slot) || hasForeignTriple(context))
                throw new InvalidOperationException("Unsafe or duplicate Triple Tonpole redirect.");
            // Audited against source writers AND final ROMs: Dread/Fortress end
            // at $8FF17; Doom/Nesoberi/Lime/Shade/staging are disjoint. Fail on
            // occupied padding, not merely on conflicting dictionary entries.
            RequirePadding(rom, OBJECT_OFFSET, 32);
            RequirePadding(rom, REFS_OFFSET, 12);
            RequirePadding(rom, TRIGGER_OFFSET, 2);
            for (int map = MAP_ID; map <= MAP_ID + 1; map++)
            {
                // Compare ownership of the pointer slots, not the apparent
                // length of unused sentinel map $1F5. An earlier Dread write
                // to $1F6 legitimately changes that unused map's end pointer.
                if (context.generatedMaps.ContainsKey(map))
                    throw new InvalidOperationException("Triple Tonpole map already owned.");
                foreach (int table in new[] { 0x84000, 0x85000, 0x87000 })
                    for (int i = 0; i < 2; i++)
                        if (rom[table + map * 2 + i] != context.originalRom[table + map * 2 + i])
                            throw new InvalidOperationException("Triple Tonpole map pointer already owned.");
            }
            MapHeader header = VanillaMapUtil.getHeader(context.originalRom, MAPNUM_TRIPLETONPOLE_ARENA);
            header.setWalkonEventEnabled(true);
            header.setSpecialEventEnabled(false);
            header.setMagicRopeEnabled(false);
            header.setFlammieEnabled(false);
            header.put(rom, OBJECT_OFFSET);
            var objects = VanillaMapUtil.getObjects(context.originalRom, MAPNUM_TRIPLETONPOLE_ARENA);
            if (objects.Count != 3) throw new InvalidOperationException("Native Triple object contract changed.");
            for (int i = 0; i < objects.Count; i++)
            {
                MapObject obj = objects[i];
                if (obj.getSpecies() != BOSSID_TONPOLE || obj.getEvent() != 0x66A)
                    throw new InvalidOperationException("Native Triple actor contract changed.");
                obj.setEventVisFlag(COUNT_FLAG);
                obj.setEventVisMinimum(0);
                obj.setEventVisMaximum(2);
                obj.setEvent(DEATH_EVENT); // preserve coordinates/priority/direction/high bits
                obj.put(rom, OBJECT_OFFSET + 8 + i * 8);
            }
            byte[] refs = VanillaMapUtil.makeMapPieceReference(
                VanillaMapUtil.getMapPieceReference(context.originalRom, MAPNUM_TRIPLETONPOLE_ARENA));
            if (refs.Length != 12) throw new InvalidOperationException("Native Triple reference contract changed.");
            Array.Copy(refs, 0, rom, REFS_OFFSET, refs.Length);
            rom[TRIGGER_OFFSET] = (byte)(ENTRY_EVENT & 0xFF);
            rom[TRIGGER_OFFSET + 1] = (byte)(ENTRY_EVENT >> 8);
            Pointer(rom, 0x87000, MAP_ID, OBJECT_OFFSET);
            Pointer(rom, 0x87000, MAP_ID + 1, OBJECT_OFFSET + 32);
            Pointer(rom, 0x85000, MAP_ID, REFS_OFFSET);
            Pointer(rom, 0x85000, MAP_ID + 1, REFS_OFFSET + 12);
            Pointer(rom, 0x84000, MAP_ID, TRIGGER_OFFSET);
            Pointer(rom, 0x84000, MAP_ID + 1, TRIGGER_OFFSET + 2);
            // Reuse the actual native Ice entrance: 11,19/layer1/$80. No
            // guessed coordinates, new door IDs, or Mode-7 state machinery.
            Door door = VanillaDoorUtil.getDoor(context.originalRom, 0x2C2);
            door.setTargetMap(MAP_ID);
            int entryDoor = ENTRY_DOORS[slot.originalMapNum];
            if (context.replacementDoors.ContainsKey(entryDoor))
                throw new InvalidOperationException("Triple Tonpole entry door already owned.");
            context.replacementDoors[entryDoor] = door;
            context.workingData.setInt(PROPERTY_SLOT_MAP, slot.originalMapNum);
            context.workingData.setInt(PROPERTY_DEATH_EVENT, deathEvent);
        }

        public static void patchEvents(RandoContext context)
        {
            if (isNativeTriple(context))
            {
                // Keep $66A's upstream flags/prize/door/music; replace ONLY
                // the artificial one-kill-counts-for-three prefix. Guard the
                // claimed state before another actor can repeat the reward.
                List<byte> original = context.replacementEvents[0x66A];
                byte[] prefix = { 0x29, 0x25, 0x29, 0x25, 0x29, 0x25 };
                if (!original.Take(6).SequenceEqual(prefix))
                    throw new InvalidOperationException("Ice prize prefix changed.");
                EventScript death = CountingDeath(EventFlags.MULTI_TONPOLE_FLAG);
                death.AddRange(original.Skip(6));
                context.replacementEvents[0x66A] = death;
            }
            if (!hasForeignTriple(context)) return;
            foreach (int id in new[] { DEATH_EVENT, ENTRY_EVENT })
                if (context.replacementEvents.ContainsKey(id)
                    || !VanillaEventUtil.getVanillaEvent(context.originalRom, id).SequenceEqual(new byte[] { 0 }))
                    throw new InvalidOperationException("Triple Tonpole event already owned: " + id.ToString("X3"));
            int slotMap = context.workingData.getInt(PROPERTY_SLOT_MAP);
            int slotDeath = context.workingData.getInt(PROPERTY_DEATH_EVENT);
            EventScript entry = new EventScript();
            // Undine's death event has no return door. Door $147 is its real
            // native return, unchanged; subsequent $144 entrances go straight
            // back to the now-completed cave instead of respawning the trio.
            if (slotMap == MAPNUM_TONPOLE_ARENA)
            {
                if (context.replacementEvents.ContainsKey(UNDINE_RETURN_EVENT)
                    || !VanillaEventUtil.getVanillaEvent(context.originalRom, UNDINE_RETURN_EVENT).SequenceEqual(new byte[] { 0 }))
                    throw new InvalidOperationException("Triple Undine return event already owned.");
                EventScript returnOnly = new EventScript();
                returnOnly.Door(0x147);
                returnOnly.End();
                context.replacementEvents[UNDINE_RETURN_EVENT] = returnOnly;
                entry.Logic(EventFlags.OPEN_WORLD_TONPOLE_FLAG, 1, 15, EventScript.GetJumpCmd(UNDINE_RETURN_EVENT));
                List<byte> tail = context.replacementEvents[slotDeath];
                if (!tail.Skip(tail.Count - 3).SequenceEqual(new byte[] { 0x17, 0x0B, 0 }))
                    throw new InvalidOperationException("Undine death tail changed.");
                tail[tail.Count - 3] = 0x27; // return from existing music before the native door
                tail.InsertRange(tail.Count - 1, new byte[] { 0x19, 0x47 });
            }
            entry.SetFlag(COUNT_FLAG, 0);
            entry.Jsr(0x704); // existing boss music
            entry.End();
            context.replacementEvents[ENTRY_EVENT] = entry;
            EventScript completion = CountingDeath(COUNT_FLAG);
            // Mark claimed before jumping into the authoritative slot event.
            completion.Jump(slotDeath);
            completion.End();
            context.replacementEvents[DEATH_EVENT] = completion;
        }

        private static EventScript CountingDeath(byte flag)
        {
            EventScript death = new EventScript();
            death.Logic(flag, 3, 15, EventScript.GetJumpCmd(0));
            death.IncrFlag(flag);
            death.Logic(flag, 0, 2, EventScript.GetJumpCmd(0));
            return death;
        }

        private static void RequirePadding(byte[] rom, int start, int length)
        {
            for (int i = start; i < start + length; i++)
                if (rom[i] != 0xFF) throw new InvalidOperationException("Triple allocation already owned at " + i.ToString("X6"));
        }

        private static void Pointer(byte[] rom, int table, int map, int offset)
        {
            rom[table + map * 2] = (byte)offset;
            rom[table + map * 2 + 1] = (byte)(offset >> 8);
        }
    }
}
