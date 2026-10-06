using SoMRandomizer.processing.common.structure;
using SoMRandomizer.util;
using System;
using System.Collections.Generic;
using System.Linq;
using static SoMRandomizer.processing.common.SomVanillaValues;

namespace SoMRandomizer.processing.common
{
    /// <summary>
    /// Separate Dread's physical Mode-7 fight from Mana Fortress event $425.
    /// Never overwrite either native arena or execute a donor's progression.
    /// </summary>
    public static class DreadSlimeBossArenaRedirect
    {
        public const string PROPERTY_DREAD_IN_FOREIGN_SLOT = "DreadSlimeInForeignSlot";
        public const string PROPERTY_FOREIGN_IN_DREAD_SLOT = "ForeignBossInDreadSlimeSlot";
        public const string PROPERTY_SLOT_MAP = "DreadSlimeRedirectSlotMap";
        private const string PROPERTY_ENTRY_EVENT = "DreadSlimeRedirectEntryEvent";
        private const string PROPERTY_ENTRY_DOOR = "DreadSlimeRedirectEntryDoor";
        private const string PROPERTY_DEATH_EVENT = "DreadSlimeRedirectDeathEvent";
        public const int DREAD_MAP_ID = 0x1F6;
        public const int FORTRESS_MAP_ID = 0x1F8;
        public const int FORTRESS_BG_PIECE_ID = 0x3D3;
        public const int FORTRESS_FG_PIECE_ID = 0x3D4;
        public const int NATIVE_DREAD_PIECE_ID = 0x1B7;
        public const int NATIVE_ENTRY_DOOR = 0x152;
        public const int NATIVE_ENTRY_EVENT = 0x424;
        public const int NATIVE_DEATH_EVENT = 0x425;

        // Bank 8's $FED6-$FFFF padding is outside the native map collections
        // and the preceding terminated combat data. Source writers and final
        // Open World ROMs were audited; do NOT append after $8E0A8 (code starts
        // at $8E0B0). Doom/Nesoberi/Lime/Shade own other disjoint spans.
        public const int DREAD_OBJECT_OFFSET = 0x8FEE0;
        public const int FORTRESS_OBJECT_OFFSET = 0x8FEF0;
        public const int DREAD_REFS_OFFSET = 0x8FF00;
        public const int FORTRESS_REFS_OFFSET = 0x8FF0C;
        public const int EMPTY_TRIGGER_OFFSET = 0x88FEE; // shared empty range, no writes

        // Only the already-audited entry + fixed-orb + explicit-return slots.
        // Exact individual entry event IDs avoid matching door-like text bytes.
        private static readonly Dictionary<int, int[]> ENTRIES = new Dictionary<int, int[]>
        {
            { MAPNUM_MANTISANT_ARENA, new[] { 0x10C, 0x08D } },
            { MAPNUM_WALLFACE_ARENA, new[] { 0x16D, 0x032 } },
            { MAPNUM_TROPICALLO_ARENA, new[] { 0x1BE, 0x051 } },
            { MAPNUM_JABBERWOCKY_ARENA, new[] { 0x084, 0x0A0 } },
            { MAPNUM_MECHRIDER2_ARENA, new[] { 0x52E, 0x35D } },
            { MAPNUM_WATERMELON_ARENA, new[] { 0x4B3, 0x358 } },
            { MAPNUM_MECHRIDER3_ARENA, new[] { 0x4A3, 0x3F6 } },
            { MAPNUM_FROSTGIGAS_ARENA, new[] { 0x66B, 0x2CA } },
            { MAPNUM_FIREGIGAS_ARENA, new[] { 0x236, 0x14B } },
        };

        public static readonly byte[] FORTRESS_BOSSES = DoomWallBossArenaRedirect.REDIRECTABLE_BOSSES
            .Where(b => b != BOSSID_KETTLEKIN && b != BOSSID_TONPOLE)
            .Concat(new[] { BOSSID_DREADSLIME }).ToArray();

        public static void reset(RandoContext context)
        {
            context.workingData.setInt(PROPERTY_DREAD_IN_FOREIGN_SLOT, 0);
            context.workingData.setInt(PROPERTY_FOREIGN_IN_DREAD_SLOT, 0);
        }

        public static bool isSafeTarget(VanillaBossMaps.VanillaBossMap slot)
        {
            return ENTRIES.ContainsKey(slot.originalMapNum);
        }

        public static byte[] getOpenWorldRandomPool(VanillaBossMaps.VanillaBossMap slot)
        {
            if (slot == VanillaBossMaps.DREADSLIME) return FORTRESS_BOSSES;
            byte[] pool = LimeSlimeBossArenaRedirect.getOpenWorldRandomPool(slot);
            return isSafeTarget(slot) ? pool.Concat(new[] { BOSSID_DREADSLIME }).ToArray() : pool;
        }

        public static bool canSwapInOpenWorld(VanillaBossMaps.VanillaBossMap slot, byte boss)
        {
            if (slot == VanillaBossMaps.DREADSLIME) return FORTRESS_BOSSES.Contains(boss);
            if (boss == BOSSID_DREADSLIME) return isSafeTarget(slot);
            return LimeSlimeBossArenaRedirect.canSwapInOpenWorld(slot, boss);
        }

        public static void createDreadInForeignSlot(byte[] rom, RandoContext context,
            VanillaBossMaps.VanillaBossMap slot, ushort deathEvent)
        {
            if (!isSafeTarget(slot)) throw new InvalidOperationException("Unsafe Dread target: " + slot.name);
            createArena(rom, context, BOSSID_DREADSLIME, deathEvent, DREAD_MAP_ID,
                DREAD_OBJECT_OFFSET, DREAD_REFS_OFFSET);
            // The shared stage is inert and slot-independent. No new door,
            // map, pieces, or Fortress/Shade flags are allocated for cleanup.
            LimeSlimeBossArenaRedirect.createNeutralRewardStagingMap(rom, context);
            int[] entry = ENTRIES[slot.originalMapNum];
            Door door = VanillaDoorUtil.getDoor(context.originalRom, NATIVE_ENTRY_DOOR);
            door.setTargetMap(DREAD_MAP_ID); // preserve 16,12/layer1/$80 exactly
            context.replacementDoors[entry[1]] = door;
            context.workingData.setInt(PROPERTY_DREAD_IN_FOREIGN_SLOT, 1);
            context.workingData.setInt(PROPERTY_SLOT_MAP, slot.originalMapNum);
            context.workingData.setInt(PROPERTY_ENTRY_EVENT, entry[0]);
            context.workingData.setInt(PROPERTY_ENTRY_DOOR, entry[1]);
            context.workingData.setInt(PROPERTY_DEATH_EVENT, deathEvent);
        }

        public static void createForeignBossInDreadSlot(byte[] rom, RandoContext context, byte boss)
        {
            if (boss == BOSSID_DREADSLIME || !FORTRESS_BOSSES.Contains(boss))
                throw new InvalidOperationException("Unsafe Fortress replacement: " + boss.ToString("X2"));
            createArena(rom, context, boss, NATIVE_DEATH_EVENT, FORTRESS_MAP_ID,
                FORTRESS_OBJECT_OFFSET, FORTRESS_REFS_OFFSET);
            var source = VanillaBossMaps.BY_VANILLA_BOSS_ID[boss];
            Door door = new Door();
            door.setTargetMap(FORTRESS_MAP_ID);
            door.setXpos((byte)source.entryPos.xpos);
            door.setYpos((byte)source.entryPos.ypos);
            door.setLayer2Collision(source.collideLayer2);
            door.setTransitionType(0);
            context.replacementDoors[NATIVE_ENTRY_DOOR] = door;
            context.workingData.setInt(PROPERTY_FOREIGN_IN_DREAD_SLOT, 1);
        }

        public static void patchEvents(RandoContext context)
        {
            if (context.workingData.hasSetting(PROPERTY_FOREIGN_IN_DREAD_SLOT)
                && context.workingData.getInt(PROPERTY_FOREIGN_IN_DREAD_SLOT) != 0)
            {
                // $424 is vanilla in Open World. Retain its entry increment,
                // door and boss music, changing ONLY the special death type.
                EventScript entry = VanillaEventUtil.getVanillaEvent(context.originalRom, NATIVE_ENTRY_EVENT);
                if (entry.Count != 10 || entry[2] != 0x30 || entry[3] != EventFlags.DEATH_TYPE_FLAG
                    || entry[4] != 0x0F || entry[5] != 0x19 || entry[6] != 0x52)
                    throw new InvalidOperationException("Dread native entry contract changed.");
                entry[4] = 0x02;
                context.replacementEvents[NATIVE_ENTRY_EVENT] = entry;
                // $425 stays byte-for-byte upstream: $4E++, $0B=2, JSR $731,
                // Door $C0, randomized prize, Door $C0 (autosave), JMP $42C.
            }
            if (!context.workingData.hasSetting(PROPERTY_DREAD_IN_FOREIGN_SLOT)
                || context.workingData.getInt(PROPERTY_DREAD_IN_FOREIGN_SLOT) == 0) return;
            int entryId = context.workingData.getInt(PROPERTY_ENTRY_EVENT);
            int doorId = context.workingData.getInt(PROPERTY_ENTRY_DOOR);
            List<byte> eventData = context.replacementEvents[entryId];
            byte doorOpcode = (byte)(0x18 + (doorId >> 8));
            int at = eventData.FindIndex(b => b == doorOpcode);
            // All admitted events have the single authoritative entry door.
            // Locate its full two-byte command rather than the opcode alone.
            while (at >= 0 && (at + 1 >= eventData.Count || eventData[at + 1] != (byte)doorId))
                at = eventData.FindIndex(at + 1, b => b == doorOpcode);
            if (at < 0) throw new InvalidOperationException("Dread entry door not found.");
            EventScript deathType = new EventScript();
            deathType.SetFlag(EventFlags.DEATH_TYPE_FLAG, 0x0F);
            eventData.InsertRange(at + 2, deathType);

            List<byte> death = context.replacementEvents[context.workingData.getInt(PROPERTY_DEATH_EVENT)];
            int boundary = -1;
            for (int i = 0; i + 1 < death.Count; i++)
                if (death[i] == 0x25 && death[i + 1] <= 7) { boundary = i; break; }
            if (boundary < 0) throw new InvalidOperationException("Dread slot has no fixed-orb cleanup boundary.");
            death.InsertRange(boundary, LimeSlimeBossArenaRedirect.getNeutralRewardStagingTransition());
        }

        private static void createArena(byte[] rom, RandoContext context, byte boss, ushort deathEvent,
            int mapId, int objectOffset, int refsOffset)
        {
            RequirePadding(rom, objectOffset, 16);
            RequirePadding(rom, refsOffset, 12);
            var source = VanillaBossMaps.BY_VANILLA_BOSS_ID[boss];
            var arena = GeneratedMapUtil.importVanillaBossArena(context, boss);
            arena.mapData.mapHeader.setWalkonEventEnabled(false);
            arena.mapData.mapHeader.setSpecialEventEnabled(false);
            arena.mapData.mapHeader.setMagicRopeEnabled(false);
            arena.mapData.mapHeader.setFlammieEnabled(false);
            MapObject obj = VanillaMapUtil.getObjects(context.originalRom, source.originalMapNum)[source.originalObjNum];
            obj.setAlwaysVisible();
            obj.setEvent(deathEvent); // preserve native high bits/direction/layer
            arena.mapData.mapObjects.Clear();
            arena.mapData.mapObjects.Add(obj);
            arena.mapData.mapTriggers.Clear();
            var pieces = new FullMapMapPieces();
            // Dread's native $1B7 is already a door-free 24x24 map on both
            // layers. Reuse it exactly; don't consume scarce unused piece IDs.
            int bg = boss == BOSSID_DREADSLIME ? NATIVE_DREAD_PIECE_ID : FORTRESS_BG_PIECE_ID;
            int fg = boss == BOSSID_DREADSLIME ? NATIVE_DREAD_PIECE_ID : FORTRESS_FG_PIECE_ID;
            pieces.bgPieces.Add(Reference(bg, false));
            pieces.fgPieces.Add(Reference(fg, true));
            if (boss != BOSSID_DREADSLIME)
            {
                if (context.replacementMapPieces.ContainsKey(bg) || context.replacementMapPieces.ContainsKey(fg))
                    throw new InvalidOperationException("Dread redirect piece allocation conflict.");
                context.replacementMapPieces[bg] = SomMapCompressor.EncodeMap(arena.layer1Data).ToList();
                context.replacementMapPieces[fg] = SomMapCompressor.EncodeMap(arena.layer2Data).ToList();
            }
            byte[] refs = VanillaMapUtil.makeMapPieceReference(pieces);
            if (refs.Length != 12) throw new InvalidOperationException("Dread references exceed allocation.");
            Pointer(rom, 0x87000, mapId, objectOffset);
            Pointer(rom, 0x87000, mapId + 1, objectOffset + 16);
            arena.mapData.mapHeader.put(rom, objectOffset);
            obj.put(rom, objectOffset + 8);
            Pointer(rom, 0x85000, mapId, refsOffset);
            Pointer(rom, 0x85000, mapId + 1, refsOffset + refs.Length);
            Array.Copy(refs, 0, rom, refsOffset, refs.Length);
            Pointer(rom, 0x84000, mapId, EMPTY_TRIGGER_OFFSET);
            Pointer(rom, 0x84000, mapId + 1, EMPTY_TRIGGER_OFFSET);
        }

        private static FullMapMapPieceReference Reference(int piece, bool foreground)
        {
            return new FullMapMapPieceReference { eventVisibilityFlagId = 0, eventVisibilityValueLow = 0,
                eventVisibilityValueHigh = 15, pieceIndex = piece, isForegroundPiece = foreground, xPos = 0, yPos = 0 };
        }

        private static void RequirePadding(byte[] rom, int start, int length)
        {
            for (int i = start; i < start + length; i++)
                if (rom[i] != 0xFF) throw new InvalidOperationException("Dread allocation already owned at " + i.ToString("X6"));
        }

        private static void Pointer(byte[] rom, int table, int map, int offset)
        {
            rom[table + map * 2] = (byte)offset;
            rom[table + map * 2 + 1] = (byte)(offset >> 8);
        }
    }
}
