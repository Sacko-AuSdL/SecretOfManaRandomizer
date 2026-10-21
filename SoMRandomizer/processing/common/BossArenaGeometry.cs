using System;
using System.Collections.Generic;
using System.Linq;
using SoMRandomizer.processing.common.structure;

namespace SoMRandomizer.processing.common
{
    // Shared production geometry/ownership validation. No prototype catalogue,
    // admission switch, ROM mutation, test shortcut or random-number use.
    public static class BossArenaGeometry
    {
        public static void RequireUnusedEvents(byte[] original, RandoContext context, params int[] ids)
        {
            foreach (int id in ids)
                if (context.replacementEvents.ContainsKey(id) || !VanillaEventUtil.getVanillaEvent(original, id).SequenceEqual(new byte[] { 0 }))
                    throw new InvalidOperationException("Private event already owned: " + id.ToString("X3"));
        }
        public static void RequireNativeBoundaries(byte[] original, byte[] output, int firstMap, int lastBoundary, bool includeTriggers = true)
        {
            foreach (int table in includeTriggers ? new[] { 0x84000, 0x85000, 0x87000 } : new[] { 0x85000, 0x87000 })
                for (int map = firstMap; map <= lastBoundary; map++)
                    if (!output.Skip(table + 2 * map).Take(2).SequenceEqual(original.Skip(table + 2 * map).Take(2)))
                        throw new InvalidOperationException("Native map boundary already owned: " + map);
        }
    }

    public sealed class DirectBossSpawn
    {
        public byte X { get; }
        public byte Y { get; }
        public DirectBossSpawn(byte x, byte y)
        {
            if (x > 127 || y > 127) throw new ArgumentOutOfRangeException("spawn");
            X = x; Y = y;
        }
    }

    public sealed class DirectBossFloor
    {
        readonly byte[,] bg, fg;
        readonly bool[,] bgPresent, fgPresent;
        readonly byte[] rom;
        readonly int tileset;
        readonly byte foregroundCollision;
        public int Width { get { return bg.GetLength(0); } }
        public int Height { get { return bg.GetLength(1); } }
        public DirectBossFloor(byte[] rom, int map) : this(rom, map, null) { }
        public DirectBossFloor(byte[] rom, int map, IDictionary<byte, byte> flagState) : this(rom, map, flagState, 4) { }
        public DirectBossFloor(byte[] rom, int map, IDictionary<byte, byte> flagState, byte foregroundCollision)
        {
            this.rom = rom;
            this.foregroundCollision = foregroundCollision;
            if (VanillaMapUtil.getHeader(rom, map).getMode7Enabled()) throw new InvalidOperationException("Requires a special-display scene adapter.");
            var refs = VanillaMapUtil.getMapPieceReference(rom, map);
            var all = refs.bgPieces.Concat(refs.fgPieces).ToArray();
            if (refs.bgPieces.Count == 0) throw new InvalidOperationException("No background geometry.");
            foreach (var piece in all.Where(p => p.eventVisibilityValueLow != 0 || p.eventVisibilityValueHigh != 15))
                if (flagState == null || !flagState.ContainsKey(piece.eventVisibilityFlagId))
                    throw new InvalidOperationException("Conditional geometry requires an explicit flag-state adapter.");
            Func<FullMapMapPieceReference, bool> active = p => (p.eventVisibilityValueLow == 0 && p.eventVisibilityValueHigh == 15)
                || (flagState[p.eventVisibilityFlagId] >= p.eventVisibilityValueLow && flagState[p.eventVisibilityFlagId] <= p.eventVisibilityValueHigh);
            refs.bgPieces = refs.bgPieces.Where(active).ToList(); refs.fgPieces = refs.fgPieces.Where(active).ToList();
            all = refs.bgPieces.Concat(refs.fgPieces).ToArray();
            if (refs.bgPieces.Count == 0) throw new InvalidOperationException("No active background geometry.");
            var data = all.Select(p => VanillaMapUtil.loadVanillaMapPiece(rom, p.pieceIndex)).ToArray();
            int w = all.Select((p, i) => p.xPos + data[i].GetLength(0)).Max();
            int h = all.Select((p, i) => p.yPos + data[i].GetLength(1)).Max();
            bg = new byte[w, h]; fg = new byte[w, h]; bgPresent = new bool[w, h]; fgPresent = new bool[w, h];
            // Read byte2 directly: do not inherit MapHeader.getTileset16's byte0 bug.
            tileset = rom[VanillaMapUtil.getObjectOffset(rom, map) + 2] & 63;
            for (int i = 0; i < all.Length; i++)
            {
                bool foreground = i >= refs.bgPieces.Count;
                for (int y = 0; y < data[i].GetLength(1); y++)
                    for (int x = 0; x < data[i].GetLength(0); x++)
                    {
                        int px = x + all[i].xPos, py = y + all[i].yPos;
                        (foreground ? fg : bg)[px, py] = data[i][x, y];
                        (foreground ? fgPresent : bgPresent)[px, py] = true;
                    }
            }
        }
        public bool IsFloor(int x, int y, byte groundCollision, byte foregroundTile)
        {
            return x >= 0 && y >= 0 && x < Width && y < Height && bgPresent[x, y] && fgPresent[x, y]
                && bg[x, y] < 0xC0 && rom[0xB0400 + tileset * 0x180 + bg[x, y]] == groundCollision
                && (foregroundTile == 255 || fg[x, y] == foregroundTile) && fg[x, y] < 0xC0
                && rom[0xB0400 + tileset * 0x180 + 0xC0 + fg[x, y]] == foregroundCollision;
        }
        public void RequirePocket(int x, int y, int radius, byte groundCollision, byte foregroundTile)
        {
            if (radius < 0) throw new ArgumentOutOfRangeException("radius");
            for (int dy = -radius; dy <= radius; dy++)
                for (int dx = -radius; dx <= radius; dx++)
                    if (!IsFloor(x + dx, y + dy, groundCollision, foregroundTile))
                        throw new InvalidOperationException("Spawn/entry intersects collision, foreground or missing geometry.");
        }
        public int RequireConnected(int entryX, int entryY, IEnumerable<DirectBossSpawn> spawns, byte groundCollision, byte foregroundTile)
        {
            RequirePocket(entryX, entryY, 0, groundCollision, foregroundTile);
            var seen = new bool[Width, Height]; var queue = new Queue<int>(); queue.Enqueue(entryX + Width * entryY);
            int count = 0;
            while (queue.Count != 0)
            {
                int at = queue.Dequeue(), x = at % Width, y = at / Width;
                if (seen[x, y] || !IsFloor(x, y, groundCollision, foregroundTile)) continue;
                seen[x, y] = true; count++;
                if (x > 0) queue.Enqueue(at - 1); if (x + 1 < Width) queue.Enqueue(at + 1);
                if (y > 0) queue.Enqueue(at - Width); if (y + 1 < Height) queue.Enqueue(at + Width);
            }
            foreach (var spawn in spawns)
                if (spawn.X >= Width || spawn.Y >= Height || !seen[spawn.X, spawn.Y])
                    throw new InvalidOperationException("Spawn disconnected from entry.");
            return count;
        }
    }
}

