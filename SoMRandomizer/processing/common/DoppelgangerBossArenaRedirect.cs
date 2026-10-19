using SoMRandomizer.processing.common.structure;
using System;
using System.Linq;
using static SoMRandomizer.processing.common.SomVanillaValues;

namespace SoMRandomizer.processing.common
{
    /// <summary>
    /// Open World only: one logical three-shadow encounter, initially compatible
    /// with Mantis in both directions. $81 is a selection ID, NEVER a species.
    /// Native shadow metadata/AI and the $4A actor-status completion test remain
    /// authoritative; there is no global death hook or kill counter.
    /// </summary>
    public static class DoppelgangerBossArenaRedirect
    {
        public const byte BOSS_ID = 0x81;
        public const string PROPERTY_NATIVE_BOSS = "DoppelgangerSlotBoss";
        public const string PROPERTY_FOREIGN = "DoppelgangerInMantis";
        public const string PROPERTY_REVERSE = "MantisInDoppelgangerSlot";
        private const string PROPERTY_ALLOCATED = "DoppelgangerMapsAllocated";

        // Native maps 496-499 have no objects, pieces or triggers. Door $0CB is
        // the sole door targeting 496, with NO native event/tile-trigger callers.
        // Leave 496 and its pointers UNCHANGED: they terminate reachable map 495.
        // 497 and 498 are private arenas; 499 is an unreachable end sentinel.
        // All source/final-ROM ownership is covered by the allocation tests.
        public const int MANTIS_MAP = 0x1F1;
        public const int SHADOW_MAP = 0x1F2;
        public const int END_MAP = 0x1F3;
        // Audited FF padding after Triple ($08FF20-$08FF4D), outside native
        // C8 executable code and disjoint from Doom/Nesoberi/slime allocations.
        public const int MANTIS_OBJECTS = 0x8FF50; // header + one boss, 16 bytes
        public const int SHADOW_OBJECTS = 0x8FF60; // header + three shadows, 32 bytes
        public const int MANTIS_REFS = 0x8FF80; // native $14/$15, 12 bytes
        public const int SHADOW_REFS = 0x8FF8C; // native $2C8/$2C9, 12 bytes
        public const int MANTIS_TRIGGERS = 0x8FF98; // one walk-on, 2 bytes
        public const int SHADOW_TRIGGERS = 0x8FF9A; // walk-on + four exit tiles, 10 bytes
        public const int ALLOCATION_END = 0x8FFA4; // exclusive

        // END-only native events, not used by Cannon, prizes or other redirects.
        public const int ENTRY_EVENT = 0x6D5;
        public const int COMPLETION_EVENT = 0x6D6;
        public const int MANTIS_RETURN_EVENT = 0x6B9;
        public const int JEHK_RETURN_EVENT = 0x6BA;
        public const int JEHK_DEATH_EVENT = 0x6BB;
        public const int JEHK_PRIZE_EVENT = 0x4E5;
        public static readonly byte[] SHADOW_SPECIES = { 0x2E, 0x3F, 0x20 };

        public static void reset(RandoContext context)
        {
            context.workingData.setInt(PROPERTY_NATIVE_BOSS, BOSS_ID);
            context.workingData.setBool(PROPERTY_FOREIGN, false);
            context.workingData.setBool(PROPERTY_REVERSE, false);
            context.workingData.setBool(PROPERTY_ALLOCATED, false);
        }

        public static bool hasForeign(RandoContext context)
        {
            return context.workingData.hasSetting(PROPERTY_FOREIGN)
                && context.workingData.getBool(PROPERTY_FOREIGN);
        }

        public static bool hasReverse(RandoContext context)
        {
            return context.workingData.hasSetting(PROPERTY_REVERSE)
                && context.workingData.getBool(PROPERTY_REVERSE);
        }

        public static bool preserveNativeShadow(RandoContext context, int map, byte species)
        {
            // NoEnemies still traverses ORIGINAL bounds. Generated arenas live
            // in originally empty spans; this exception only protects the native
            // selected trial and never protects unrelated ordinary enemies.
            // Vanilla boss mode bypasses BossSwaps before reset/selection.
            // Absent selection metadata therefore means the untouched native
            // trial, not three removable ordinary enemies. A selected donor
            // still leaves the native shadows hidden as before.
            return map == MAPNUM_DOPPEL_ARENA && SHADOW_SPECIES.Contains(species)
                && (!context.workingData.hasSetting(PROPERTY_NATIVE_BOSS)
                    || context.workingData.getInt(PROPERTY_NATIVE_BOSS) == BOSS_ID);
        }

        public static byte[] getOpenWorldRandomPool(VanillaBossMaps.VanillaBossMap slot)
        {
            if (slot == VanillaBossMaps.DOPPELGANGERS) return new[] { BOSS_ID, BOSSID_MANTISANT };
            byte[] existing = TripleTonpoleBossArenaRedirect.getOpenWorldRandomPool(slot);
            return slot == VanillaBossMaps.MANTISANT ? existing.Concat(new[] { BOSS_ID }).ToArray() : existing;
        }

        public static bool canSwapInOpenWorld(VanillaBossMaps.VanillaBossMap slot, byte boss)
        {
            if (slot == VanillaBossMaps.DOPPELGANGERS) return boss == BOSS_ID || boss == BOSSID_MANTISANT;
            if (boss == BOSS_ID) return slot == VanillaBossMaps.MANTISANT;
            return TripleTonpoleBossArenaRedirect.canSwapInOpenWorld(slot, boss);
        }

        public static void createForeign(byte[] rom, RandoContext context)
        {
            if (hasForeign(context)) throw new InvalidOperationException("Duplicate Doppelganger redirect.");
            Allocate(rom, context);
            var objects = VanillaMapUtil.getObjects(context.originalRom, MAPNUM_DOPPEL_ARENA);
            for (int i = 0; i < 3; i++)
            {
                MapObject shadow = objects[i];
                if (shadow.getSpecies() != SHADOW_SPECIES[i] || shadow.getEvent() != 0)
                    throw new InvalidOperationException("Native Doppelganger actor contract changed.");
                shadow.setEventVisFlag(EventFlags.POTOS_FLAG);
                shadow.setEventVisMinimum(0);
                shadow.setEventVisMaximum(0xB);
                // Keep native coordinates, priority and event 0; enemy slots
                // 4/5/6 must belong ONLY to these three priority objects.
                shadow.put(rom, SHADOW_OBJECTS + 8 + i * 8);
            }
            Door entry = VanillaDoorUtil.getDoor(context.originalRom, 0x304);
            entry.setTargetMap(SHADOW_MAP);
            SetDoor(context, 0x08D, entry);
            context.workingData.setBool(PROPERTY_FOREIGN, true);
        }

        public static void createReverse(byte[] rom, RandoContext context)
        {
            createReverse(rom, context, BOSSID_MANTISANT);
        }

        internal static void createReverse(byte[] rom, RandoContext context, byte donor)
        {
            if (donor != BOSSID_MANTISANT)
                throw new InvalidOperationException("Unapproved Jehk donor.");
            if (hasReverse(context)) throw new InvalidOperationException("Duplicate Jehk redirect.");
            Allocate(rom, context);
            int sourceMap = MAPNUM_MANTISANT_ARENA;
            var donorObjects = VanillaMapUtil.getObjects(context.originalRom, sourceMap);
            if (donorObjects.Count != 1 || donorObjects[0].getSpecies() != donor)
                throw new InvalidOperationException("Jehk single-actor donor contract changed.");
            MapObject mantis = donorObjects[0];
            mantis.setEventVisFlag(EventFlags.JEHK_CAVE_FLAG);
            mantis.setEventVisMinimum(0);
            mantis.setEventVisMaximum(4);
            mantis.setEvent(JEHK_DEATH_EVENT);
            mantis.put(rom, MANTIS_OBJECTS + 8);
            Door entry = VanillaDoorUtil.getDoor(context.originalRom, 0x08D);
            entry.setTargetMap(MANTIS_MAP);
            SetDoor(context, 0x304, entry);
            // No native shadows remain active alongside the replacement, even
            // if an old/native map-72 path is inspected or revisited.
            var shadows = VanillaMapUtil.getObjects(context.originalRom, MAPNUM_DOPPEL_ARENA);
            int start = VanillaMapUtil.getObjectOffset(context.originalRom, MAPNUM_DOPPEL_ARENA) + 8;
            for (int i = 0; i < shadows.Count; i++)
            {
                shadows[i].setNeverVisible();
                shadows[i].put(rom, start + i * 8);
            }
            context.workingData.setBool(PROPERTY_REVERSE, true);
        }

        private static void Allocate(byte[] rom, RandoContext context)
        {
            if (context.workingData.hasSetting(PROPERTY_ALLOCATED)
                && context.workingData.getBool(PROPERTY_ALLOCATED)) return;
            for (int at = MANTIS_OBJECTS; at < ALLOCATION_END; at++)
                if (rom[at] != 0xFF) throw new InvalidOperationException("Doppelganger allocation already owned at " + at.ToString("X6"));
            for (int map = 496; map <= END_MAP; map++)
            {
                var pieces = VanillaMapUtil.getMapPieceReference(context.originalRom, map);
                if (VanillaMapUtil.getObjects(context.originalRom, map).Count != 0
                    || VanillaMapUtil.getTriggers(context.originalRom, map).Count != 0
                    || pieces.bgPieces.Count != 0 || pieces.fgPieces.Count != 0)
                    throw new InvalidOperationException("Doppelganger native map allocation is not empty.");
                if (context.generatedMaps.ContainsKey(map)) throw new InvalidOperationException("Doppelganger map already owned.");
                foreach (int table in new[] { 0x84000, 0x85000, 0x87000 })
                    for (int i = 0; i < 2; i++)
                        if (rom[table + map * 2 + i] != context.originalRom[table + map * 2 + i])
                            throw new InvalidOperationException("Doppelganger map pointer already owned.");
            }
            // Initialize even the unreachable reserved half as a valid map.
            // Enable its objects only when that direction is actually selected.
            WriteHeader(rom, context, MAPNUM_MANTISANT_ARENA, MANTIS_OBJECTS);
            WriteHeader(rom, context, MAPNUM_DOPPEL_ARENA, SHADOW_OBJECTS);
            MapObject inactive = VanillaMapUtil.getObjects(context.originalRom, MAPNUM_MANTISANT_ARENA)[0];
            inactive.setNeverVisible();
            inactive.put(rom, MANTIS_OBJECTS + 8);
            var shadows = VanillaMapUtil.getObjects(context.originalRom, MAPNUM_DOPPEL_ARENA);
            if (shadows.Count != 3) throw new InvalidOperationException("Native Doppelganger object count changed.");
            for (int i = 0; i < 3; i++)
            {
                shadows[i].setNeverVisible();
                shadows[i].put(rom, SHADOW_OBJECTS + 8 + i * 8);
            }
            WriteRefs(rom, context, MAPNUM_MANTISANT_ARENA, MANTIS_REFS);
            WriteRefs(rom, context, MAPNUM_DOPPEL_ARENA, SHADOW_REFS);
            Word(rom, MANTIS_TRIGGERS, 0x3DB);
            Word(rom, SHADOW_TRIGGERS, ENTRY_EVENT);
            for (int i = 1; i < 5; i++) Word(rom, SHADOW_TRIGGERS + 2 * i, COMPLETION_EVENT);
            Pointer(rom, 0x87000, MANTIS_MAP, MANTIS_OBJECTS);
            Pointer(rom, 0x87000, SHADOW_MAP, SHADOW_OBJECTS);
            Pointer(rom, 0x87000, END_MAP, SHADOW_OBJECTS + 32);
            Pointer(rom, 0x85000, MANTIS_MAP, MANTIS_REFS);
            Pointer(rom, 0x85000, SHADOW_MAP, SHADOW_REFS);
            Pointer(rom, 0x85000, END_MAP, SHADOW_REFS + 12);
            Pointer(rom, 0x84000, MANTIS_MAP, MANTIS_TRIGGERS);
            Pointer(rom, 0x84000, SHADOW_MAP, SHADOW_TRIGGERS);
            Pointer(rom, 0x84000, END_MAP, ALLOCATION_END);
            context.workingData.setBool(PROPERTY_ALLOCATED, true);
        }

        public static void patchEvents(RandoContext context)
        {
            if (hasForeign(context))
            {
                ReserveEvent(context, ENTRY_EVENT);
                ReserveEvent(context, COMPLETION_EVENT);
                ReserveEvent(context, MANTIS_RETURN_EVENT);
                EventScript back = new EventScript(); back.Door(0x08E); back.End();
                context.replacementEvents[MANTIS_RETURN_EVENT] = back;
                EventScript entry = new EventScript();
                entry.Logic(EventFlags.POTOS_FLAG, 0xC, 0xF, EventScript.GetJumpCmd(MANTIS_RETURN_EVENT));
                entry.Jsr(0x704); entry.End();
                context.replacementEvents[ENTRY_EVENT] = entry;
                EventScript completion = new EventScript();
                completion.Logic(EventFlags.POTOS_FLAG, 0xC, 0xF, EventScript.GetJumpCmd(MANTIS_RETURN_EVENT));
                // Exact native $4E5 test: $4A compares actor $91 against $7F.
                // At CPU $C1:F1F1/$F248 a live actor executes the failure jump;
                // a defeated actor skips it. All three must pass. No counter.
                for (byte actor = 4; actor <= 6; actor++)
                    completion.AddRange(new byte[] { 0x4A, actor, 0x91, 0x7F, 0x10, 0x00 });
                completion.SetFlag(EventFlags.POTOS_FLAG, 0xC);
                completion.Jump(0x112); completion.End();
                context.replacementEvents[COMPLETION_EVENT] = completion;
            }
            if (hasReverse(context))
            {
                ReserveEvent(context, JEHK_RETURN_EVENT);
                ReserveEvent(context, JEHK_DEATH_EVENT);
                EventScript back = new EventScript(); back.Door(0x038); back.End();
                context.replacementEvents[JEHK_RETURN_EVENT] = back;
                EventScript entry = new EventScript();
                entry.Logic(EventFlags.JEHK_CAVE_FLAG, 6, 15, EventScript.GetJumpCmd(JEHK_RETURN_EVENT));
                entry.Jsr(0x704); entry.End();
                context.replacementEvents[0x3DB] = entry;
                EventScript death = new EventScript();
                death.Logic(EventFlags.JEHK_CAVE_FLAG, 6, 15, EventScript.GetJumpCmd(0));
                // Arm only from the real bound boss death callback. Exit $3DF
                // must never satisfy the reward just by touching an exit tile.
                death.SetFlag(EventFlags.JEHK_CAVE_FLAG, 5);
                death.Jump(JEHK_PRIZE_EVENT); death.End();
                context.replacementEvents[JEHK_DEATH_EVENT] = death;
                var prize = context.replacementEvents[JEHK_PRIZE_EVENT];
                byte[] prefix = { 0x42, 0x3F, 0x6F, 0x14, 0x60,
                    0x4A, 4, 0x91, 0x7F, 0x13, 0xDE,
                    0x4A, 5, 0x91, 0x7F, 0x13, 0xDE,
                    0x4A, 6, 0x91, 0x7F, 0x13, 0xDE };
                if (!prize.Take(prefix.Length).SequenceEqual(prefix))
                    throw new InvalidOperationException("Jehk prize prefix changed.");
                EventScript guardedPrize = new EventScript();
                guardedPrize.Logic(EventFlags.JEHK_CAVE_FLAG, 6, 15, EventScript.GetJumpCmd(0x460));
                guardedPrize.Logic(EventFlags.JEHK_CAVE_FLAG, 0, 4, EventScript.GetJumpCmd(0));
                // Original flag=6, prize insertion, Door $038, healing and end.
                // Keep the same $4E5 logical check; only its defeat gate changes.
                guardedPrize.AddRange(prize.Skip(prefix.Length));
                context.replacementEvents[JEHK_PRIZE_EVENT] = guardedPrize;
            }
        }

        private static void ReserveEvent(RandoContext context, int id)
        {
            if (context.replacementEvents.ContainsKey(id)
                || !VanillaEventUtil.getVanillaEvent(context.originalRom, id).SequenceEqual(new byte[] { 0 }))
                throw new InvalidOperationException("Doppelganger event already owned: " + id.ToString("X3"));
        }

        private static void WriteHeader(byte[] rom, RandoContext context, int source, int offset)
        {
            MapHeader header = VanillaMapUtil.getHeader(context.originalRom, source);
            header.setWalkonEventEnabled(true);
            header.setSpecialEventEnabled(false);
            header.setMagicRopeEnabled(false);
            header.setFlammieEnabled(false);
            header.put(rom, offset);
        }

        private static void WriteRefs(byte[] rom, RandoContext context, int source, int offset)
        {
            byte[] refs = VanillaMapUtil.makeMapPieceReference(VanillaMapUtil.getMapPieceReference(context.originalRom, source));
            if (refs.Length != 12) throw new InvalidOperationException("Doppelganger reference contract changed.");
            Array.Copy(refs, 0, rom, offset, refs.Length);
        }

        private static void SetDoor(RandoContext context, int id, Door door)
        {
            if (context.replacementDoors.ContainsKey(id)) throw new InvalidOperationException("Doppelganger entry door already owned.");
            context.replacementDoors[id] = door;
        }

        private static void Pointer(byte[] rom, int table, int map, int offset) { Word(rom, table + map * 2, offset); }
        private static void Word(byte[] rom, int at, int value) { rom[at] = (byte)value; rom[at + 1] = (byte)(value >> 8); }
    }
}
