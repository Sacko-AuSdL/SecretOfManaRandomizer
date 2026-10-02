using SoMRandomizer.logging;
using SoMRandomizer.processing.common.structure;
using System.Linq;
using static SoMRandomizer.processing.common.GeneratedMapUtil;
using static SoMRandomizer.processing.common.SomVanillaValues;

namespace SoMRandomizer.processing.common
{
    /// <summary>
    /// Builds a native-geometry boss arena for an ordinary boss selected for the
    /// Open World Doom's Wall slot.  The generated map intentionally keeps only
    /// the selected boss's visual/physical arena requirements; Northtown owns the
    /// entry, death, prize, progression, and return events.
    /// </summary>
    public static class DoomWallBossArenaRedirect
    {
        public const string PROPERTY_ENABLED = "DoomWallBossArenaRedirectEnabled";

        // Map 510 is an empty final map slot.  Using the last real slot also lets
        // FullMapReplacer update its 511 sentinel without disturbing another map.
        public const int GENERATED_MAP_ID = 0x1FE;

        // These two map-piece IDs are unreferenced by all 512 vanilla full maps.
        public const int GENERATED_BG_PIECE_ID = 0x3ED;
        public const int GENERATED_FG_PIECE_ID = 0x3F5;

        // Vanilla map 511's sentinel pointers show the end of each bank-8 data
        // set.  Piece/trigger data can share the gap before object data begins at
        // $089000; object data can append after its own $08E068 sentinel.
        public const int GENERATED_PIECE_DATA_OFFSET = 0x88FA8;
        public const int GENERATED_TRIGGER_DATA_OFFSET = 0x88FB4;
        public const int GENERATED_OBJECT_DATA_OFFSET = 0x8E068;

        public const int DOOM_SLOT_ENTRY_EVENT = 0x552;
        public const int DOOM_SLOT_DEATH_EVENT = 0x553;
        public const int DOOM_SLOT_LEFT_ENTRY_DOOR = 0x14F;
        public const int DOOM_SLOT_RIGHT_ENTRY_DOOR = 0x150;
        public const int DOOM_SLOT_RETURN_DOOR = 0x314;

        // Every ordinary species already supported by Open World BossSwaps.
        // Walls retain map 407; Mode-7 slimes, Triple Tonpole, Mana Beast, and
        // child species remain deliberately excluded.
        public static readonly byte[] REDIRECTABLE_BOSSES = new byte[]
        {
            BOSSID_MANTISANT, BOSSID_TROPICALLO, BOSSID_MINOTAUR, BOSSID_SPIKEY,
            BOSSID_JABBER, BOSSID_SPRINGBEAK, BOSSID_FROSTGIGAS, BOSSID_SNAPDRAGON,
            BOSSID_MECHRIDER1, BOSSID_VAMPIRE, BOSSID_METALMANTIS, BOSSID_MECHRIDER2,
            BOSSID_KILROY, BOSSID_GORGON, BOSSID_BOREAL, BOSSID_GREATVIPER,
            BOSSID_BLUESPIKE, BOSSID_HYDRA, BOSSID_WATERMELON, BOSSID_HEXAS,
            BOSSID_KETTLEKIN, BOSSID_TONPOLE, BOSSID_MECHRIDER3, BOSSID_SNOWDRAGON,
            BOSSID_FIREGIGAS, BOSSID_REDDRAGON, BOSSID_AXEBEAK, BOSSID_BLUEDRAGON,
            BOSSID_BUFFY, BOSSID_DARKLICH, BOSSID_DRAGONWORM, BOSSID_THUNDERGIGAS,
        };

        public static readonly byte[] DOOM_SLOT_RANDOM_BOSSES = new byte[]
        {
            BOSSID_MANTISANT, BOSSID_WALLFACE, BOSSID_TROPICALLO, BOSSID_MINOTAUR,
            BOSSID_SPIKEY, BOSSID_JABBER, BOSSID_SPRINGBEAK, BOSSID_FROSTGIGAS,
            BOSSID_SNAPDRAGON, BOSSID_MECHRIDER1, BOSSID_DOOMSWALL, BOSSID_VAMPIRE,
            BOSSID_METALMANTIS, BOSSID_MECHRIDER2, BOSSID_KILROY, BOSSID_GORGON,
            BOSSID_BOREAL, BOSSID_GREATVIPER, BOSSID_BLUESPIKE, BOSSID_HYDRA,
            BOSSID_WATERMELON, BOSSID_HEXAS, BOSSID_KETTLEKIN, BOSSID_TONPOLE,
            BOSSID_MECHRIDER3, BOSSID_SNOWDRAGON, BOSSID_FIREGIGAS, BOSSID_REDDRAGON,
            BOSSID_AXEBEAK, BOSSID_BLUEDRAGON, BOSSID_BUFFY, BOSSID_DARKLICH,
            BOSSID_DRAGONWORM, BOSSID_THUNDERGIGAS,
        };

        public static bool requiresRedirect(byte bossId)
        {
            return REDIRECTABLE_BOSSES.Contains(bossId);
        }

        public static VanillaBossMaps.VanillaBossMap getPhysicalArena(byte bossId)
        {
            return VanillaBossMaps.BY_VANILLA_BOSS_ID[bossId];
        }

        public static void create(byte[] outRom, RandoContext context, byte bossId)
        {
            VanillaBossMaps.VanillaBossMap sourceArena = getPhysicalArena(bossId);
            GeneratedMap generatedArena = GeneratedMapUtil.importVanillaBossArena(context, bossId);

            // Never execute the selected boss's native walk-on/progression.  The
            // one retained trigger is Doom slot event $552 (boss music).
            generatedArena.mapData.mapHeader.setWalkonEventEnabled(true);
            generatedArena.mapData.mapHeader.setSpecialEventEnabled(false);
            generatedArena.mapData.mapHeader.setMagicRopeEnabled(false);
            generatedArena.mapData.mapHeader.setFlammieEnabled(false);
            generatedArena.mapData.mapTriggers.Clear();
            generatedArena.mapData.mapTriggers.Add(DOOM_SLOT_ENTRY_EVENT);

            foreach (MapObject bossObject in generatedArena.mapData.mapObjects)
            {
                bossObject.setEvent(DOOM_SLOT_DEATH_EVENT);
            }

            generatedArena.mapData.mapPieces = new FullMapMapPieces();
            generatedArena.mapData.mapPieces.bgPieces.Add(makePieceReference(GENERATED_BG_PIECE_ID, false));
            generatedArena.mapData.mapPieces.fgPieces.Add(makePieceReference(GENERATED_FG_PIECE_ID, true));
            context.replacementMapPieces[GENERATED_BG_PIECE_ID] = SomMapCompressor.EncodeMap(generatedArena.layer1Data).ToList();
            context.replacementMapPieces[GENERATED_FG_PIECE_ID] = SomMapCompressor.EncodeMap(generatedArena.layer2Data).ToList();
            writeGeneratedMap(outRom, generatedArena.mapData);

            // Both native Doom entry sides now enter the same generated arena.
            // Transition 0 is the proven generic generated-arena transition; the
            // native $87/$88 wall-side transitions assume map 407 geometry.
            context.replacementDoors[DOOM_SLOT_LEFT_ENTRY_DOOR] = makeEntryDoor(sourceArena, generatedArena.layer2Collision);
            context.replacementDoors[DOOM_SLOT_RIGHT_ENTRY_DOOR] = makeEntryDoor(sourceArena, generatedArena.layer2Collision);

            context.workingData.setInt(PROPERTY_ENABLED, 1);
            Logging.log("Doom's Wall slot uses generated map " + GENERATED_MAP_ID.ToString("X3")
                + " imported from " + sourceArena.name + " for boss " + bossId.ToString("X2"), "debug");
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

        private static Door makeEntryDoor(VanillaBossMaps.VanillaBossMap sourceArena, bool layer2Collision)
        {
            Door door = new Door();
            door.setTargetMap(GENERATED_MAP_ID);
            door.setXpos((byte)sourceArena.entryPos.xpos);
            door.setYpos((byte)sourceArena.entryPos.ypos);
            door.setLayer2Collision(layer2Collision);
            door.setTransitionType(0);
            return door;
        }

        private static void writeGeneratedMap(byte[] outRom, FullMap map)
        {
            byte[] pieceData = VanillaMapUtil.makeMapPieceReference(map.mapPieces);
            int objectDataSize = 8 + map.mapObjects.Count * 8;
            int triggerDataSize = map.mapTriggers.Count * 2;
            if (pieceData.Length > GENERATED_TRIGGER_DATA_OFFSET - GENERATED_PIECE_DATA_OFFSET
                || GENERATED_TRIGGER_DATA_OFFSET + triggerDataSize > 0x89000
                || GENERATED_OBJECT_DATA_OFFSET + objectDataSize > 0x90000)
            {
                throw new System.InvalidOperationException("Generated Doom-slot arena exceeds its reserved bank-8 spans.");
            }

            writeMapPointer(outRom, 0x87000, GENERATED_MAP_ID, GENERATED_OBJECT_DATA_OFFSET);
            writeMapPointer(outRom, 0x87000, GENERATED_MAP_ID + 1, GENERATED_OBJECT_DATA_OFFSET + objectDataSize);
            map.mapHeader.put(outRom, GENERATED_OBJECT_DATA_OFFSET);
            for (int i = 0; i < map.mapObjects.Count; i++)
            {
                map.mapObjects[i].put(outRom, GENERATED_OBJECT_DATA_OFFSET + 8 + i * 8);
            }

            writeMapPointer(outRom, 0x85000, GENERATED_MAP_ID, GENERATED_PIECE_DATA_OFFSET);
            writeMapPointer(outRom, 0x85000, GENERATED_MAP_ID + 1, GENERATED_PIECE_DATA_OFFSET + pieceData.Length);
            System.Array.Copy(pieceData, 0, outRom, GENERATED_PIECE_DATA_OFFSET, pieceData.Length);

            writeMapPointer(outRom, 0x84000, GENERATED_MAP_ID, GENERATED_TRIGGER_DATA_OFFSET);
            writeMapPointer(outRom, 0x84000, GENERATED_MAP_ID + 1, GENERATED_TRIGGER_DATA_OFFSET + triggerDataSize);
            for (int i = 0; i < map.mapTriggers.Count; i++)
            {
                ushort trigger = map.mapTriggers[i];
                outRom[GENERATED_TRIGGER_DATA_OFFSET + i * 2] = (byte)trigger;
                outRom[GENERATED_TRIGGER_DATA_OFFSET + i * 2 + 1] = (byte)(trigger >> 8);
            }
        }

        private static void writeMapPointer(byte[] outRom, int tableOffset, int mapId, int dataOffset)
        {
            int pointerOffset = tableOffset + mapId * 2;
            outRom[pointerOffset] = (byte)dataOffset;
            outRom[pointerOffset + 1] = (byte)(dataOffset >> 8);
        }
    }
}
