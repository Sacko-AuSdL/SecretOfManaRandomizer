using SoMRandomizer.processing.common.structure;
using SoMRandomizer.util;
using System;
using System.Collections.Generic;
using System.Linq;
using static SoMRandomizer.processing.common.GeneratedMapUtil;
using static SoMRandomizer.processing.common.SomVanillaValues;

namespace SoMRandomizer.processing.common
{
    /// <summary>
    /// Keeps Lime Slime and its native Shade Palace slot independently
    /// randomizable.  Either direction receives a private, native-geometry arena;
    /// the boss object's event remains owned by the randomized slot.
    /// </summary>
    public static class LimeSlimeBossArenaRedirect
    {
        public const string PROPERTY_LIME_IN_FOREIGN_SLOT = "LimeSlimeInForeignSlot";
        public const string PROPERTY_FOREIGN_IN_SHADE_SLOT = "ForeignBossInLimeSlimeSlot";
        public const string PROPERTY_LIME_SLOT_MAP = "LimeSlimeRedirectSlotMap";
        public const string PROPERTY_LIME_SLOT_DEATH_EVENT = "LimeSlimeRedirectSlotDeathEvent";
        public const string PROPERTY_LIME_ENTRY_DOORS = "LimeSlimeRedirectEntryDoors";

        // Both vanilla Mode-7 slime arenas use this exact entry contract:
        // player (16,12), layer 1, transition $80.  The camera initializer at
        // $00:CA10/$00:CA3F derives its initial scroll from the decoded door X/Y;
        // the generic VanillaBossMaps entry (12,13) leaves the Mode-7 body and
        // the actor-owned core in different coordinate frames.
        private const int NATIVE_LIME_ENTRY_DOOR = 0x03A;

        // Empty map/sentinel pairs immediately below the validated Doom redirect
        // map pair ($1FE/$1FF).  Vanilla has no objects, triggers, pieces, or doors
        // for any of $1FA-$1FD.
        public const int LIME_IN_FOREIGN_SLOT_MAP_ID = 0x1FA;
        public const int LIME_REWARD_STAGING_MAP_ID = 0x1FB;
        public const int FOREIGN_IN_SHADE_SLOT_MAP_ID = 0x1FC;
        public const int FOREIGN_IN_SHADE_SLOT_SENTINEL_MAP_ID = 0x1FD;

        // Vanilla Door $10B points at empty map $110 and is not referenced by
        // any vanilla event or composite-map trigger.  Reuse that dead slot
        // only while a foreign-slot Lime fight needs its neutral reward stage.
        public const int LIME_REWARD_STAGING_DOOR = 0x10B;

        // These IDs are unreferenced by all 512 vanilla full maps.  Doom's
        // redirect separately owns $3ED/$3F5.
        public const int LIME_BG_PIECE_ID = 0x3E4;
        public const int LIME_FG_PIECE_ID = 0x3E5;
        public const int SHADE_BG_PIECE_ID = 0x3E6;
        public const int SHADE_FG_PIECE_ID = 0x3DA;
        // Vanilla $0E9 is a real 120x120 all-zero tile map, used on both
        // layers elsewhere.  With map $0FA's tileset, tile zero on each
        // layer selects the transparent $35F tile, not dungeon geometry.
        public const int LIME_REWARD_STAGING_BLANK_PIECE_ID = 0x0E9;

        // Fixed, non-overlapping spans in the proven-unused tails of the vanilla
        // bank-8 object/piece/trigger collections.  Doom currently ends at
        // $08E078 / $088FB6, while the Open World Nesoberi trigger relocation
        // owns $088FBE-$088FC9.  Keep both generated piece-reference blocks
        // immediately after that range so later Open World processors cannot
        // reinterpret trigger data as map-piece metadata.
        public const int LIME_OBJECT_DATA_OFFSET = 0x8E080;
        public const int LIME_REWARD_STAGING_OBJECT_DATA_OFFSET = 0x8E090;
        public const int SHADE_OBJECT_DATA_OFFSET = 0x8E098;
        public const int LIME_PIECE_DATA_OFFSET = 0x88FCA;
        public const int LIME_REWARD_STAGING_PIECE_DATA_OFFSET = 0x88FD6;
        public const int SHADE_PIECE_DATA_OFFSET = 0x88FE2;
        public const int LIME_TRIGGER_DATA_OFFSET = 0x88FEE;
        public const int SHADE_TRIGGER_DATA_OFFSET = 0x88FEE;

        // Only slots with an Open World entry event and a death event that
        // explicitly leaves the isolated arena are admitted.  This is narrower
        // than ordinary direct arena compatibility by design.
        private static readonly Dictionary<int, int[]> SAFE_LIME_TARGET_ENTRY_DOORS =
            new Dictionary<int, int[]>
            {
                { MAPNUM_MANTISANT_ARENA, new int[] { 0x08D } },
                { MAPNUM_WALLFACE_ARENA, new int[] { 0x032 } },
                { MAPNUM_TROPICALLO_ARENA, new int[] { 0x051 } },
                { MAPNUM_JABBERWOCKY_ARENA, new int[] { 0x0A0 } },
                { MAPNUM_MECHRIDER2_ARENA, new int[] { 0x35D } },
                { MAPNUM_WATERMELON_ARENA, new int[] { 0x358 } },
                { MAPNUM_MECHRIDER3_ARENA, new int[] { 0x3F6 } },
                { MAPNUM_FROSTGIGAS_ARENA, new int[] { 0x2CA } },
                { MAPNUM_FIREGIGAS_ARENA, new int[] { 0x14B } },
            };

        // Native-geometry imports already proven by the Doom redirect.  Keep
        // Kettle Kin and Triple Tonpole out of this pass because their separate
        // graphics/spawn behavior has not been validated for the Shade slot.
        public static readonly byte[] SHADE_SLOT_RANDOM_BOSSES =
            DoomWallBossArenaRedirect.REDIRECTABLE_BOSSES
                .Where(bossId => bossId != BOSSID_KETTLEKIN && bossId != BOSSID_TONPOLE)
                .Concat(new byte[] { BOSSID_LIMESLIME })
                .ToArray();

        public static void reset(RandoContext context)
        {
            context.workingData.setInt(PROPERTY_LIME_IN_FOREIGN_SLOT, 0);
            context.workingData.setInt(PROPERTY_FOREIGN_IN_SHADE_SLOT, 0);
            context.workingData.setInt(PROPERTY_LIME_SLOT_MAP, -1);
            context.workingData.setInt(PROPERTY_LIME_SLOT_DEATH_EVENT, -1);
            context.workingData.set(PROPERTY_LIME_ENTRY_DOORS, "");
        }

        public static bool isSafeLimeTargetSlot(VanillaBossMaps.VanillaBossMap slot)
        {
            return slot != VanillaBossMaps.LIMESLIME
                && SAFE_LIME_TARGET_ENTRY_DOORS.ContainsKey(slot.originalMapNum);
        }

        public static bool isSafeShadeReplacement(byte bossId)
        {
            return SHADE_SLOT_RANDOM_BOSSES.Contains(bossId);
        }

        public static bool canPlaceInOpenWorld(VanillaBossMaps.VanillaBossMap slot, byte bossId)
        {
            if (slot == VanillaBossMaps.LIMESLIME)
            {
                return isSafeShadeReplacement(bossId);
            }
            if (bossId == BOSSID_LIMESLIME)
            {
                return isSafeLimeTargetSlot(slot);
            }
            return slot.allSupportedBosses.Contains(bossId);
        }

        public static byte[] getOpenWorldRandomPool(VanillaBossMaps.VanillaBossMap slot)
        {
            if (slot == VanillaBossMaps.LIMESLIME)
            {
                return SHADE_SLOT_RANDOM_BOSSES;
            }
            if (isSafeLimeTargetSlot(slot))
            {
                return slot.allSupportedBosses.Concat(new byte[] { BOSSID_LIMESLIME }).ToArray();
            }
            return slot.allSupportedBosses;
        }

        public static bool canSwapInOpenWorld(VanillaBossMaps.VanillaBossMap slot, byte bossId)
        {
            if (slot == VanillaBossMaps.LIMESLIME || bossId == BOSSID_LIMESLIME)
            {
                return canPlaceInOpenWorld(slot, bossId);
            }
            return slot.supportedSwapBosses.Contains(bossId);
        }

        public static void createLimeInForeignSlot(byte[] outRom, RandoContext context,
            VanillaBossMaps.VanillaBossMap slot, ushort slotDeathEvent)
        {
            if (!isSafeLimeTargetSlot(slot))
            {
                throw new InvalidOperationException("Lime Slime redirect is not safe for slot " + slot.name + ".");
            }

            createArena(outRom, context, BOSSID_LIMESLIME, slotDeathEvent,
                LIME_IN_FOREIGN_SLOT_MAP_ID, LIME_BG_PIECE_ID, LIME_FG_PIECE_ID,
                LIME_OBJECT_DATA_OFFSET, LIME_PIECE_DATA_OFFSET, LIME_TRIGGER_DATA_OFFSET);
            createNeutralRewardStagingMap(outRom, context);

            int[] entryDoors = SAFE_LIME_TARGET_ENTRY_DOORS[slot.originalMapNum];
            redirectLimeDoors(context, entryDoors);
            context.workingData.setInt(PROPERTY_LIME_IN_FOREIGN_SLOT, 1);
            context.workingData.setInt(PROPERTY_LIME_SLOT_MAP, slot.originalMapNum);
            context.workingData.setInt(PROPERTY_LIME_SLOT_DEATH_EVENT, slotDeathEvent);
            context.workingData.set(PROPERTY_LIME_ENTRY_DOORS, string.Join(",", entryDoors));
        }

        public static void createForeignBossInShadeSlot(byte[] outRom, RandoContext context, byte bossId)
        {
            if (!isSafeShadeReplacement(bossId) || bossId == BOSSID_LIMESLIME)
            {
                throw new InvalidOperationException("Boss " + bossId.ToString("X2")
                    + " is not a safe Lime Slime slot replacement.");
            }

            VanillaBossMaps.VanillaBossMap sourceArena = VanillaBossMaps.BY_VANILLA_BOSS_ID[bossId];
            createArena(outRom, context, bossId, 0x544,
                FOREIGN_IN_SHADE_SLOT_MAP_ID, SHADE_BG_PIECE_ID, SHADE_FG_PIECE_ID,
                SHADE_OBJECT_DATA_OFFSET, SHADE_PIECE_DATA_OFFSET, SHADE_TRIGGER_DATA_OFFSET);
            redirectDoors(context, new int[] { 0x03A }, FOREIGN_IN_SHADE_SLOT_MAP_ID,
                sourceArena.entryPos, sourceArena.collideLayer2);
            context.workingData.setInt(PROPERTY_FOREIGN_IN_SHADE_SLOT, 1);
        }

        /// <summary>
        /// Lime's native entry sets death type $0F after its door.  When Lime is
        /// redirected elsewhere, add the same command immediately after that
        /// slot's proven Open World entry-door command.
        /// </summary>
        public static void patchLimeEntryEvent(RandoContext context)
        {
            if (!context.workingData.hasSetting(PROPERTY_LIME_IN_FOREIGN_SLOT)
                || context.workingData.getInt(PROPERTY_LIME_IN_FOREIGN_SLOT) == 0)
            {
                return;
            }

            string doorSetting = context.workingData.get(PROPERTY_LIME_ENTRY_DOORS);
            int patchedCount = 0;
            foreach (string doorText in doorSetting.Split(new char[] { ',' }, StringSplitOptions.RemoveEmptyEntries))
            {
                int doorId = int.Parse(doorText);
                byte doorCommand = (byte)(EventCommandEnum.DOOR_BASE.Value + (doorId >> 8));
                byte doorLow = (byte)doorId;
                foreach (List<byte> eventData in context.replacementEvents.Values)
                {
                    for (int i = 0; i + 1 < eventData.Count; i++)
                    {
                        if (eventData[i] == doorCommand && eventData[i + 1] == doorLow)
                        {
                            EventScript deathType = new EventScript();
                            deathType.SetFlag(EventFlags.DEATH_TYPE_FLAG, 0x0F);
                            eventData.InsertRange(i + 2, deathType);
                            patchedCount++;
                            i += deathType.Count;
                        }
                    }
                }
            }

            if (patchedCount == 0)
            {
                throw new InvalidOperationException("Unable to find the redirected Lime Slime entry event.");
            }
        }

        /// <summary>
        /// Dread Slime's Open World death event restores ordinary death handling
        /// and takes a door off its Mode-7 map before displaying its prize.  A
        /// redirected Lime uses the same presentation boundary but enters its
        /// private, empty, ordinary-display map instead of showing Dread's map.
        /// Leading progression flags and the remainder of the slot event stay in
        /// their original order, including its authoritative exit door.
        /// </summary>
        public static void patchLimeDeathEvent(RandoContext context)
        {
            if (!context.workingData.hasSetting(PROPERTY_LIME_IN_FOREIGN_SLOT)
                || context.workingData.getInt(PROPERTY_LIME_IN_FOREIGN_SLOT) == 0)
            {
                return;
            }

            int deathEventId = context.workingData.getInt(PROPERTY_LIME_SLOT_DEATH_EVENT);
            if (!context.replacementEvents.ContainsKey(deathEventId))
            {
                throw new InvalidOperationException("Unable to find the redirected Lime Slime death event.");
            }

            List<byte> deathEvent = context.replacementEvents[deathEventId];
            int firstOrbMessage = -1;
            for (int i = 0; i + 1 < deathEvent.Count; i++)
            {
                // Fixed weapon-orb messages are JSR $500-$507.
                if (deathEvent[i] == EventCommandEnum.JUMP_SUBR_BASE.Value + 0x05
                    && deathEvent[i + 1] <= 0x07)
                {
                    firstOrbMessage = i;
                    break;
                }
            }

            if (firstOrbMessage == -1)
            {
                throw new InvalidOperationException(
                    "Redirected Lime Slime death event has no fixed weapon-orb message boundary.");
            }

            EventScript mode7Cleanup = new EventScript();
            mode7Cleanup.SetFlag(EventFlags.DEATH_TYPE_FLAG, 0x02);
            mode7Cleanup.Door(LIME_REWARD_STAGING_DOOR);
            deathEvent.InsertRange(firstOrbMessage, mode7Cleanup);
        }

        private static void createNeutralRewardStagingMap(byte[] outRom, RandoContext context)
        {
            FullMap stagingMap = new FullMap();
            // Reuse only the valid regular-display/tileset setup, never the
            // recognizable Mana Fortress background piece ($2F0).
            stagingMap.mapHeader = VanillaMapUtil.getHeader(context.originalRom, 0x0FA);
            stagingMap.mapHeader.setAnimatedTiles(false);
            stagingMap.mapHeader.setUnknownTileFlag(false);
            stagingMap.mapHeader.setPaletteAnimated(false);
            stagingMap.mapHeader.setLayer1UsesForegroundTiles(false);
            stagingMap.mapHeader.setLayer2UsesForegroundTiles(true);
            stagingMap.mapHeader.setMode7Enabled(false);
            stagingMap.mapHeader.setWalkonEventEnabled(false);
            stagingMap.mapHeader.setSpecialEventEnabled(false);
            stagingMap.mapHeader.setFlammieEnabled(false);
            stagingMap.mapHeader.setMagicRopeEnabled(false);
            stagingMap.mapHeader.setBgScrolling(0);
            stagingMap.mapHeader.setDisplaySettings(0);
            stagingMap.mapHeader.setNpcPalette(0xFF);
            stagingMap.mapPieces = new FullMapMapPieces();
            stagingMap.mapPieces.bgPieces.Add(makePieceReference(LIME_REWARD_STAGING_BLANK_PIECE_ID, false));
            stagingMap.mapPieces.fgPieces.Add(makePieceReference(LIME_REWARD_STAGING_BLANK_PIECE_ID, true));

            // $00:CB90 calls the piece parser ($00:CBD1) before checking the
            // range end.  An empty composite therefore cannot safely clear the
            // former Mode-7 background.  Load blank pieces on BOTH layers.
            // Adjacent maps share start/end pointers, so inserting this block
            // requires moving Shade's unchanged references forward 12 bytes;
            // Lime's references and both arenas' geometry remain unchanged.
            writeGeneratedMap(outRom, stagingMap, LIME_REWARD_STAGING_MAP_ID,
                LIME_REWARD_STAGING_OBJECT_DATA_OFFSET,
                LIME_REWARD_STAGING_PIECE_DATA_OFFSET, LIME_TRIGGER_DATA_OFFSET);

            if (context.replacementDoors.ContainsKey(LIME_REWARD_STAGING_DOOR))
            {
                throw new InvalidOperationException(
                    "Lime reward staging door is already owned by another processor.");
            }
            Door stagingDoor = new Door();
            stagingDoor.setTargetMap(LIME_REWARD_STAGING_MAP_ID);
            stagingDoor.setXpos(16);
            stagingDoor.setYpos(16);
            stagingDoor.setLayer2Collision(false);
            stagingDoor.setTransitionType(0x80);
            context.replacementDoors[LIME_REWARD_STAGING_DOOR] = stagingDoor;
        }

        private static void createArena(byte[] outRom, RandoContext context, byte physicalBossId,
            ushort slotDeathEvent, int generatedMapId, int bgPieceId, int fgPieceId,
            int objectOffset, int pieceOffset, int triggerOffset)
        {
            VanillaBossMaps.VanillaBossMap sourceArena = VanillaBossMaps.BY_VANILLA_BOSS_ID[physicalBossId];
            GeneratedMap generatedArena = GeneratedMapUtil.importVanillaBossArena(context, physicalBossId);

            generatedArena.mapData.mapHeader.setWalkonEventEnabled(false);
            generatedArena.mapData.mapHeader.setSpecialEventEnabled(false);
            generatedArena.mapData.mapHeader.setMagicRopeEnabled(false);
            generatedArena.mapData.mapHeader.setFlammieEnabled(false);
            generatedArena.mapData.mapTriggers.Clear();

            // Preserve native object direction/layer/unknown bits.  Lime Slime's
            // native object carries nonzero high event bits not reproduced by the
            // generic arena importer.
            MapObject nativeBossObject = VanillaMapUtil.getObjects(
                context.originalRom, sourceArena.originalMapNum)[sourceArena.originalObjNum];
            nativeBossObject.setAlwaysVisible();
            nativeBossObject.setEvent(slotDeathEvent);
            generatedArena.mapData.mapObjects.Clear();
            generatedArena.mapData.mapObjects.Add(nativeBossObject);

            generatedArena.mapData.mapPieces = new FullMapMapPieces();
            generatedArena.mapData.mapPieces.bgPieces.Add(makePieceReference(bgPieceId, false));
            generatedArena.mapData.mapPieces.fgPieces.Add(makePieceReference(fgPieceId, true));
            context.replacementMapPieces[bgPieceId] = SomMapCompressor.EncodeMap(generatedArena.layer1Data).ToList();
            context.replacementMapPieces[fgPieceId] = SomMapCompressor.EncodeMap(generatedArena.layer2Data).ToList();
            writeGeneratedMap(outRom, generatedArena.mapData, generatedMapId,
                objectOffset, pieceOffset, triggerOffset);
        }

        private static FullMapMapPieceReference makePieceReference(int pieceId, bool foreground)
        {
            return new FullMapMapPieceReference
            {
                eventVisibilityFlagId = 0,
                eventVisibilityValueLow = 0,
                eventVisibilityValueHigh = 0x0F,
                pieceIndex = pieceId,
                isForegroundPiece = foreground,
                xPos = 0,
                yPos = 0,
            };
        }

        private static void redirectDoors(RandoContext context, IEnumerable<int> doorIds,
            int generatedMapId, XyPos entryPos, bool layer2Collision)
        {
            foreach (int doorId in doorIds)
            {
                Door door = new Door();
                door.setTargetMap((ushort)generatedMapId);
                door.setXpos((byte)entryPos.xpos);
                door.setYpos((byte)entryPos.ypos);
                door.setLayer2Collision(layer2Collision);
                door.setTransitionType(0);
                context.replacementDoors[doorId] = door;
            }
        }

        private static void redirectLimeDoors(RandoContext context, IEnumerable<int> doorIds)
        {
            foreach (int doorId in doorIds)
            {
                // Clone the authoritative native Lime entry rather than the
                // stale generic boss-map coordinates.  Change only its target
                // map; X/Y, collision layer, and transition remain byte-exact.
                Door door = VanillaDoorUtil.getDoor(context.originalRom, NATIVE_LIME_ENTRY_DOOR);
                door.setTargetMap(LIME_IN_FOREIGN_SLOT_MAP_ID);
                context.replacementDoors[doorId] = door;
            }
        }

        private static void writeGeneratedMap(byte[] outRom, FullMap map, int mapId,
            int objectOffset, int pieceOffset, int triggerOffset)
        {
            byte[] pieceData = VanillaMapUtil.makeMapPieceReference(map.mapPieces);
            int objectDataSize = 8 + map.mapObjects.Count * 8;
            int triggerDataSize = map.mapTriggers.Count * 2;
            if (objectDataSize > 0x20 || pieceData.Length > 0x0C || triggerDataSize != 0
                || objectOffset + objectDataSize > 0x90000
                || pieceOffset + pieceData.Length > triggerOffset
                || triggerOffset + triggerDataSize > 0x89000)
            {
                throw new InvalidOperationException("Generated Lime redirect arena exceeds its reserved bank-8 spans.");
            }

            writeMapPointer(outRom, 0x87000, mapId, objectOffset);
            writeMapPointer(outRom, 0x87000, mapId + 1, objectOffset + objectDataSize);
            map.mapHeader.put(outRom, objectOffset);
            for (int i = 0; i < map.mapObjects.Count; i++)
            {
                map.mapObjects[i].put(outRom, objectOffset + 8 + i * 8);
            }

            writeMapPointer(outRom, 0x85000, mapId, pieceOffset);
            writeMapPointer(outRom, 0x85000, mapId + 1, pieceOffset + pieceData.Length);
            Array.Copy(pieceData, 0, outRom, pieceOffset, pieceData.Length);

            writeMapPointer(outRom, 0x84000, mapId, triggerOffset);
            writeMapPointer(outRom, 0x84000, mapId + 1, triggerOffset + triggerDataSize);
        }

        private static void writeMapPointer(byte[] outRom, int tableOffset, int mapId, int dataOffset)
        {
            int pointerOffset = tableOffset + mapId * 2;
            outRom[pointerOffset] = (byte)dataOffset;
            outRom[pointerOffset + 1] = (byte)(dataOffset >> 8);
        }
    }
}
