using System;
using System.Linq;
using SoMRandomizer.config.settings;
using SoMRandomizer.processing.common;
using SoMRandomizer.processing.common.structure;

namespace SoMRandomizer.processing.openworld.events
{
    /// <summary>Open World access to the existing Mech Rider 1 slot, without the capture story.</summary>
    public class SandshipEvents : RandoProcessor
    {
        public const int ENTRANCE_EVENT = 0x28A;
        public const int CAPTAIN_EVENT = 0x2A3;
        public const int HINT_EVENT = 0x2A2;
        public const int DESERT_BG_PIECE = 0x3CC;
        public const int DESERT_FG_PIECE = 0x3CD;
        public const int TRIGGER_POOL_END = 0x84F7E;
        public const byte CLEARED = 0xF;

        protected override string getName() { return "Open World Sandship access"; }

        protected override bool process(byte[] origRom, byte[] outRom, string seed, RandoSettings settings, RandoContext context)
        {
            // Only called by OpenWorldEvents. Native starts at $E to skip capture; $F is our clear state.
            openSouthernDesert(origRom, outRom, context);

            EventScript entry = new EventScript();
            entry.Logic(EventFlags.DESERT_SHIP_FLAG, CLEARED, CLEARED, EventScript.GetJumpCmd(0x2A8));
            entry.Door(0x193); // Native stable boss entry: map 340, (16,20), regular display.
            entry.Jsr(0x704); // Standard boss music; no capture, party removal, or story waits.
            entry.End();
            context.replacementEvents[ENTRANCE_EVENT] = entry;

            EventScript death = new EventScript();
            death.Logic(EventFlags.DESERT_SHIP_FLAG, CLEARED, CLEARED, EventScript.GetJumpCmd(0));
            death.Jsr(0x504); // Preserve the native fixed weapon-orb reward.
            death.SetFlag(EventFlags.DESERT_SHIP_FLAG, CLEARED);
            death.Door(0x1FF); // Native post-boss crew map 91, (24,24).
            death.Jsr(0x7C2); // Native desert music.
            death.End();
            context.replacementEvents[0x2A1] = death;

            EventScript clearedEntry = new EventScript();
            clearedEntry.Door(0x1FF);
            clearedEntry.End();
            context.replacementEvents[0x2A8] = clearedEntry;

            EventScript captain = afterVictory();
            PrizeEvents.injectReplacementPattern(captain, 0);
            captain.End();
            context.replacementEvents[CAPTAIN_EVENT] = captain;
            EventScript hint = afterVictory();
            HintEvents.injectHintPattern(hint);
            hint.End();
            context.replacementEvents[HINT_EVENT] = hint;

            // Crew member 5 was the native Yes/No departure NPC. Keep a framed, repeatable departure.
            EventScript leave = afterVictory();
            leave.AddDialogueBox("The desert is this way.");
            leave.Door(0x194);
            leave.End();
            context.replacementEvents[0x2A7] = leave;
            // Hide the other three story NPCs; no native capture/dialogue chain remains reachable here.
            for (int i = 0; i < 6; i++)
            {
                MapObject npc = VanillaMapUtil.getObjects(origRom, 91)[i];
                if (i == 0 || i == 1 || i == 5)
                {
                    npc.setEventVisFlag(EventFlags.DESERT_SHIP_FLAG);
                    npc.setEventVisMinimum(CLEARED);
                    npc.setEventVisMaximum(CLEARED);
                }
                else npc.setNeverVisible();
                VanillaMapUtil.putObject(outRom, npc, 91, i);
            }
            MapObject boss = VanillaMapUtil.getObjects(outRom, 340)[0];
            boss.setEventVisFlag(EventFlags.DESERT_SHIP_FLAG);
            boss.setEventVisMinimum(0xE);
            boss.setEventVisMaximum(0xE);
            VanillaMapUtil.putObject(outRom, boss, 340, 0);

            // This native door is used by the replaced $2A8 only. Return immediately north of the new exit.
            Door returnDoor = new Door();
            returnDoor.setTargetMap(92);
            returnDoor.setXpos(21);
            returnDoor.setYpos(39);
            returnDoor.setTransitionType(0x80);
            returnDoor.put(outRom, 0x83000 + 4 * 0x194);
            return true;
        }

        private static EventScript afterVictory()
        {
            EventScript e = new EventScript();
            e.Logic(EventFlags.DESERT_SHIP_FLAG, 0, CLEARED - 1, EventScript.GetJumpCmd(0));
            return e;
        }

        private static void openSouthernDesert(byte[] original, byte[] output, RandoContext context)
        {
            // Unreferenced native piece IDs, also disjoint from Doom/Nesoberi/Lime/Dread/Triple allocations.
            if (context.replacementMapPieces.ContainsKey(DESERT_BG_PIECE)
                || context.replacementMapPieces.ContainsKey(DESERT_FG_PIECE))
                throw new InvalidOperationException("Sandship desert piece allocation already owned.");
            byte[,] bg = VanillaMapUtil.loadVanillaMapPiece(original, 0x15B);
            byte[,] fg = VanillaMapUtil.loadVanillaMapPiece(original, 0x15C);
            byte[,] south = VanillaMapUtil.loadVanillaMapPiece(original, 0x151);
            // Reuse the native desert south passage, including its three trigger tiles at (20..22,41).
            for (int y = 0; y < south.GetLength(1); y++)
                for (int x = 0; x < south.GetLength(0); x++)
                {
                    bg[18 + x, 37 + y] = south[x, y];
                    fg[18 + x, 37 + y] = 0x01; // Native empty foreground tile, not a new global tile/collision.
                }
            context.replacementMapPieces[DESERT_BG_PIECE] = SomMapCompressor.EncodeMap(bg).ToList();
            context.replacementMapPieces[DESERT_FG_PIECE] = SomMapCompressor.EncodeMap(fg).ToList();
            FullMapMapPieces refs = VanillaMapUtil.getMapPieceReference(output, 92);
            refs.bgPieces.Single(p => p.pieceIndex == 0x15B).pieceIndex = DESERT_BG_PIECE;
            refs.fgPieces.Single(p => p.pieceIndex == 0x15C).pieceIndex = DESERT_FG_PIECE;
            byte[] refBytes = VanillaMapUtil.makeMapPieceReference(refs);
            int start = VanillaMapUtil.getPiecePlacementOffset(output, 92);
            if (refBytes.Length != VanillaMapUtil.getPiecePlacementOffset(output, 93) - start)
                throw new InvalidOperationException("Sandship must not expand native piece-reference spans.");
            Array.Copy(refBytes, 0, output, start, refBytes.Length);

            // Insert three triggers at the end of map 92. Preserve every other live trigger sequence,
            // including edits made by earlier processors. First native pool ends at $084F7E; the six
            // bytes through $084F83 are audited FF padding before the $085000 reference table.
            // Map 298 is the empty terminal span between this pool and the second trigger pool.
            int insertion = VanillaMapUtil.getTriggerOffset(output, 93);
            if (VanillaMapUtil.getTriggerOffset(output, 298) != TRIGGER_POOL_END
                || insertion != VanillaMapUtil.getTriggerOffset(original, 93))
                throw new InvalidOperationException("Unexpected native desert trigger layout.");
            for (int i = TRIGGER_POOL_END; i < TRIGGER_POOL_END + 6; i++)
                if (output[i] != 0xFF) throw new InvalidOperationException("Sandship trigger padding already owned.");
            Array.Copy(output, insertion, output, insertion + 6, TRIGGER_POOL_END - insertion);
            for (int map = 0; map < 512; map++)
            {
                int at = VanillaMapUtil.getTriggerOffset(output, map);
                if (at >= insertion && at <= TRIGGER_POOL_END)
                {
                    at += 6;
                    output[0x84000 + map * 2] = (byte)at;
                    output[0x84001 + map * 2] = (byte)(at >> 8);
                }
            }
            for (int i = 0; i < 3; i++)
            {
                output[insertion + i * 2] = (byte)(ENTRANCE_EVENT & 0xFF);
                output[insertion + i * 2 + 1] = (byte)(ENTRANCE_EVENT >> 8);
            }
        }
    }
}
