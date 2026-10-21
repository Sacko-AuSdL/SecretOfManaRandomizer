using System;
using System.Collections.Generic;
using System.Linq;
using SoMRandomizer.processing.common.structure;
using SoMRandomizer.util;
using static SoMRandomizer.processing.common.SomVanillaValues;
using Slot = SoMRandomizer.processing.common.VanillaBossMaps.VanillaBossMap;

namespace SoMRandomizer.processing.common
{
    /// <summary>
    /// Immutable per-seed construction contract for the two independently owned
    /// trial resources. No functional RNG, runtime kill counter or global death
    /// interception. The selector admits only the contracts listed here.
    /// </summary>
    public sealed class DoppelgangerEncounterExpansion
    {
        public const int Start = 0x8FF50, End = 0x8FFB9; // exclusive (four native Jehk exit triggers included)
        public const int ReverseObjects = Start, ShadowObjects = 0x8FF60;
        public const int ReverseRefs = 0x8FF90, ShadowRefs = 0x8FF9C;
        public const int ReverseTriggers = 0x8FFAD, ShadowTriggers = 0x8FFAF;
        // Native-map reference audit: neither piece is referenced by any of the
        // 512 original maps; no other Open World writer owns either ID. Sandship
        // owns 3CC/3CD, slimes 3D3/3D4/3DA/3E4-6 and Doom 3ED/3F5.
        public const int DonorBg = 0x3E2, DonorFg = 0x3B8;
        public const int IdleHook = 0xB6A4;
        public Slot ForeignSlot { get; }
        public byte JehkBoss { get; }
        public bool DirectJehk { get { return IsDirectJehk(JehkBoss); } }
        public bool HasReverse { get { return JehkBoss != DoppelgangerBossArenaRedirect.BOSS_ID; } }
        public int Flag { get; }
        public int Completed { get; }
        public int Completion { get; }
        public int EntryDoor { get; }
        public int ReturnDoor { get; }
        public int ReturnMusic { get; }
        public IReadOnlyList<DirectBossSpawn> Spawns { get; }
        public ShadowDestination Destination { get; }
        public bool UsesDonor { get { return ForeignSlot != null && !UsesDestinationGeometry(ForeignSlot); } }
        // Native map204 has only one object slot. Reuse the existing three-actor
        // destination-copy allocation rather than expanding a shared object bank.
        // Unlike a donor cave, this copy remains the traversable clearing after
        // victory: both original entrances, exit tiles and progression survive.
        public bool PreservesDestinationTraversal { get { return ForeignSlot == VanillaBossMaps.DRAGONWORM; } }
        public static bool UsesDestinationGeometry(Slot slot)
        { return slot == VanillaBossMaps.TROPICALLO || slot == VanillaBossMaps.FROSTGIGAS || slot == VanillaBossMaps.DRAGONWORM; }

        // Destination-owned contracts, not per-species combat hacks. The donor
        // fallback is the native three-shadow room (including its four exits).
        // Donor callbacks must leave that room; destination copies can retain
        // their own traversal instead, under an explicit trigger contract.
        public sealed class ShadowDestination
        {
            public int Map { get; } public int Flag { get; } public int Completed { get; }
            public int Death { get; } public int Return { get; } public int Music { get; }
            public int EntryEvent { get; } public IReadOnlyList<int> Doors { get; }
            public ShadowDestination(int map, int flag, int completed, int death, int back, int music, int entry, params int[] doors)
            { Map=map; Flag=flag; Completed=completed; Death=death; Return=back; Music=music; EntryEvent=entry; Doors=Array.AsReadOnly(doors); }
        }
        public static readonly IReadOnlyList<ShadowDestination> ShadowDestinations = Array.AsReadOnly(new[] {
            new ShadowDestination(MAPNUM_MANTISANT_ARENA,0x10,12,0x112,0x8E,-1,-1,0x8D),
            new ShadowDestination(MAPNUM_TROPICALLO_ARENA,0x15,8,0x1B9,0x52,0x7CF,0x1BE,0x51),
            new ShadowDestination(MAPNUM_FROSTGIGAS_ARENA,0x26,4,0x66D,0x2CB,0x7C3,0x66B,0x2CA),
            new ShadowDestination(MAPNUM_WALLFACE_ARENA,0x1A,7,0x16E,0x25,0x7C3,0x16D,0x32),
            new ShadowDestination(MAPNUM_JABBERWOCKY_ARENA,0x19,1,0x20C,0xA1,0x7C3,0x84,0xA0,0xA2),
            new ShadowDestination(MAPNUM_MECHRIDER2_ARENA,0x35,6,0x52F,-1,-1,0x52E,0x35D),
            new ShadowDestination(MAPNUM_WATERMELON_ARENA,0x45,2,0x4B4,0x348,0x7D9,0x4B3,0x358),
            new ShadowDestination(MAPNUM_MECHRIDER3_ARENA,0x75,2,0x4A4,0x3F7,-1,0x4A3,0x3F6),
            new ShadowDestination(MAPNUM_FIREGIGAS_ARENA,0x18,6,0x237,0xDE,0x7D2,0x236,0x14B),
            // Pure Lands $62A plays music/checks MTR but DOES NOT leave the
            // original arena. Dragon Worm keeps its own destination geometry;
            // the remaining donors return via audited unused Door0CB first.
            new ShadowDestination(MAPNUM_DRAGONWORM_ARENA,0x46,1,0x5ED,-1,0x727,-1,0x375,0x378),
            new ShadowDestination(MAPNUM_SNOWDRAGON_ARENA,0x46,2,0x5EF,0xCB,0x727,-1,0x37F),
            new ShadowDestination(MAPNUM_AXEBEAK_ARENA,0x46,3,0x5F1,0xCB,0x727,-1,0x38B,0x38E),
            new ShadowDestination(MAPNUM_REDDRAGON_ARENA,0x46,4,0x5F3,0xCB,0x727,-1,0x395),
            new ShadowDestination(MAPNUM_THUNDERGIGAS_ARENA,0x46,5,0x5F5,0xCB,0x727,-1,0x3A5,0x3A8),
            new ShadowDestination(MAPNUM_BLUEDRAGON_ARENA,0x46,6,0x5F7,0xCB,0x727,-1,0x3AD),
            new ShadowDestination(MAPNUM_LIMESLIME_ARENA,0x38,6,0x544,0x286,0x7C0,0x543,0x3A),
            new ShadowDestination(MAPNUM_DREADSLIME_ARENA,0x4E,4,0x425,0xC0,0x731,0x424,0x152),
        });

        // Gigas-family movement is target-relative (no global position table).
        // Frost's actual Jehk placement was runtime accepted. The other family
        // members use the same floor/spawn contract, with native species AI.
        public static bool IsDirectJehk(byte boss)
        { return boss == BOSSID_FROSTGIGAS || boss == BOSSID_FIREGIGAS || boss == BOSSID_THUNDERGIGAS; }

        // Imported single-actor native geometry uses the SAME importer already
        // used by the Doom/Shade adapters, not guessed Jehk collision compatibility.
        // No global jump-position operands, transformations or Mode-7 bosses.
        public static readonly byte[] JehkBosses = {
            DoppelgangerBossArenaRedirect.BOSS_ID, BOSSID_MANTISANT,
            BOSSID_FROSTGIGAS, BOSSID_FIREGIGAS, BOSSID_THUNDERGIGAS,
            BOSSID_MINOTAUR, BOSSID_JABBER, BOSSID_SNAPDRAGON,
            BOSSID_METALMANTIS, BOSSID_GORGON, BOSSID_VAMPIRE,
            BOSSID_MECHRIDER1, BOSSID_MECHRIDER2, BOSSID_MECHRIDER3,
            BOSSID_KILROY, BOSSID_HEXAS, BOSSID_BUFFY
        };

        public static bool SupportsShadows(Slot slot)
        { return ShadowDestinations.Any(d => d.Map == slot.originalMapNum); }

        private DoppelgangerEncounterExpansion(Slot foreign, byte jehk)
        {
            ForeignSlot = foreign; JehkBoss = jehk;
            if (foreign == null) { Spawns = Array.AsReadOnly(new DirectBossSpawn[0]); return; }
            Destination = ShadowDestinations.Single(d => d.Map == foreign.originalMapNum);
            Flag=Destination.Flag; Completed=Destination.Completed; Completion=Destination.Death;
            EntryDoor=Destination.Doors[0]; ReturnDoor=Destination.Return; ReturnMusic=Destination.Music;
            if (foreign == VanillaBossMaps.TROPICALLO)
            {
                Flag = 0x15; Completed = 8; Completion = 0x1B9;
                EntryDoor = 0x51; ReturnDoor = 0x52; ReturnMusic = 0x7CF;
                Spawns = Array.AsReadOnly(new[] { new DirectBossSpawn(15, 36), new DirectBossSpawn(23, 37), new DirectBossSpawn(28, 36) });
            }
            else if (foreign == VanillaBossMaps.FROSTGIGAS)
            {
                Flag = 0x26; Completed = 4; Completion = 0x66D;
                EntryDoor = 0x2CA; ReturnDoor = 0x2CB; ReturnMusic = 0x7C3;
                // Upper corners at y12 have obstructed neighbours. The side
                // actors use the connected lower floor with full 3x3 clearance.
                Spawns = Array.AsReadOnly(new[] { new DirectBossSpawn(7, 14), new DirectBossSpawn(10, 12), new DirectBossSpawn(13, 14) });
            }
            else if (PreservesDestinationTraversal)
            {
                Spawns = Array.AsReadOnly(new[] { new DirectBossSpawn(21, 11), new DirectBossSpawn(23, 14), new DirectBossSpawn(14, 17) });
            }
            else
            {
                Spawns = Array.AsReadOnly(new[] { new DirectBossSpawn(15, 13), new DirectBossSpawn(13, 13), new DirectBossSpawn(17, 13) });
            }
        }

        /// <summary>Reserve both halves ONCE after selection, before publishing pointers.</summary>
        public static void Configure(byte[] rom, RandoContext context, IDictionary<Slot, byte> assignments)
        {
            var foreign = assignments.Where(p => p.Key != VanillaBossMaps.DOPPELGANGERS && p.Value == 0x81).Select(p => p.Key).ToArray();
            int count = assignments.Count(p => p.Value == 0x81);
            if (count > 1) throw new InvalidOperationException("Doppelgangers are a unique encounter: only one native or foreign assignment is supported.");
            byte boss = assignments[VanillaBossMaps.DOPPELGANGERS];
            // Preserve byte-identical accepted Phase-1 Mantis-only paths and the
            // separate historical Frost donor harness when explicitly selected.
            if ((foreign.Length == 0 || foreign[0] == VanillaBossMaps.MANTISANT)
                && (boss == 0x81 || boss == BOSSID_MANTISANT)) return;
            if (!JehkBosses.Contains(boss) || (foreign.Length != 0 && !SupportsShadows(foreign[0])))
                throw new InvalidOperationException("No audited Doppelganger encounter contract for selection.");
            var binding = new DoppelgangerEncounterExpansion(foreign.FirstOrDefault(), boss);
            binding.Construct(rom, context);
            context.doppelgangerExpansion = binding;
            context.workingData.setBool(DoppelgangerBossArenaRedirect.PROPERTY_FOREIGN, foreign.Length != 0);
            context.workingData.setBool(DoppelgangerBossArenaRedirect.PROPERTY_REVERSE, binding.HasReverse);
        }

        private void Construct(byte[] rom, RandoContext c)
        {
            for (int at = Start; at < End; at++)
                if (rom[at] != 255 || c.originalRom[at] != 255)
                    throw new InvalidOperationException("Trial allocation already owned at " + at.ToString("X6"));
            BossArenaGeometry.RequireNativeBoundaries(c.originalRom, rom, 496, 499);
            // The upstream Tropicallo adapter opens the room's interior floor
            // for every randomized boss. Its eight native compressed-piece
            // edits are also part of the accepted shadow prototype contract.
            // Run it once BEFORE composing/validating that destination floor.
            if (ForeignSlot != null && !UsesDonor && !PreservesDestinationTraversal) ForeignSlot.process(rom, DoppelgangerBossArenaRedirect.BOSS_ID);
            for (int map = 496; map <= 499; map++)
            {
                var refs = VanillaMapUtil.getMapPieceReference(c.originalRom, map);
                if (c.generatedMaps.ContainsKey(map) || VanillaMapUtil.getObjects(c.originalRom, map).Count != 0
                    || VanillaMapUtil.getTriggers(c.originalRom, map).Count != 0 || refs.bgPieces.Count + refs.fgPieces.Count != 0)
                    throw new InvalidOperationException("Trial map reservation changed.");
            }
            // A valid unused reverse half. Direct Jehk has no objects in map497.
            var header = VanillaMapUtil.getHeader(c.originalRom, MAPNUM_MANTISANT_ARENA);
            var reverse = VanillaMapUtil.getObjects(c.originalRom, MAPNUM_MANTISANT_ARENA)[0];
            reverse.setNeverVisible();
            var reversePieces = VanillaMapUtil.getMapPieceReference(c.originalRom, MAPNUM_MANTISANT_ARENA);
            if (HasReverse && !DirectJehk)
            {
                foreach (int piece in new[] { DonorBg, DonorFg })
                {
                    if (c.replacementMapPieces.ContainsKey(piece)) throw new InvalidOperationException("Jehk donor piece already owned.");
                    for (int m = 0; m < 512; m++)
                    {
                        var p = VanillaMapUtil.getMapPieceReference(c.originalRom, m);
                        if (p.bgPieces.Concat(p.fgPieces).Any(r => r.pieceIndex == piece))
                            throw new InvalidOperationException("Jehk donor piece has a native user.");
                    }
                }
                var imported = GeneratedMapUtil.importVanillaBossArena(c, JehkBoss);
                if (imported.mapData.mapObjects.Count != 1 || imported.mapData.mapHeader.getMode7Enabled())
                    throw new InvalidOperationException("Jehk requires a regular single-actor donor.");
                header = imported.mapData.mapHeader; reverse = imported.mapData.mapObjects[0];
                reverse.setEventVisFlag(0x3F); reverse.setEventVisMinimum(0); reverse.setEventVisMaximum(4); reverse.setEvent(0x6BB);
                reversePieces = new FullMapMapPieces();
                reversePieces.bgPieces.Add(Piece(DonorBg, false)); reversePieces.fgPieces.Add(Piece(DonorFg, true));
                c.replacementMapPieces[DonorBg] = SomMapCompressor.EncodeMap(imported.layer1Data).ToList();
                c.replacementMapPieces[DonorFg] = SomMapCompressor.EncodeMap(imported.layer2Data).ToList();
                var door = new Door(); door.setTargetMap(497); door.setXpos((byte)imported.entryPos.xpos);
                door.setYpos((byte)imported.entryPos.ypos); door.setLayer2Collision(imported.layer2Collision); door.setTransitionType(0);
                SetDoor(c, 0x304, door);
            }
            SetHeader(header); header.put(rom, ReverseObjects); reverse.put(rom, ReverseObjects + 8);
            CopyRefs(rom, reversePieces, ReverseRefs, 12);
            Word(rom, ReverseTriggers, 0x3DB);
            // Native Jehk geometry, native entry/facing and accepted lower floor
            // pocket. Never change the global/native Gigas AI or its own arena.
            if (HasReverse)
            {
                var native = VanillaMapUtil.getObjects(c.originalRom, MAPNUM_DOPPEL_ARENA);
                for (int i = 0; i < native.Count; i++)
                { native[i].setNeverVisible(); VanillaMapUtil.putObject(rom, native[i], MAPNUM_DOPPEL_ARENA, i); }
                if (DirectJehk)
                {
                    new DirectBossFloor(rom, MAPNUM_DOPPEL_ARENA).RequirePocket(14, 16, 1, 0x4A, 0);
                    var actor = VanillaMapUtil.getObjects(c.originalRom, MAPNUM_FROSTGIGAS_ARENA)[0];
                    actor.setSpecies(JehkBoss); actor.setXpos(14); actor.setYpos(16);
                    actor.setEventVisFlag(0x3F); actor.setEventVisMinimum(0); actor.setEventVisMaximum(4); actor.setEvent(0x6BB);
                    VanillaMapUtil.putObject(rom, actor, MAPNUM_DOPPEL_ARENA, 0);
                    SetDoor(c, 0x304, VanillaDoorUtil.getDoor(c.originalRom, 0x304));
                }
            }
            var shadows = VanillaMapUtil.getObjects(c.originalRom, MAPNUM_DOPPEL_ARENA);
            int source = ForeignSlot == null || UsesDonor ? MAPNUM_DOPPEL_ARENA : ForeignSlot.originalMapNum;
            header = VanillaMapUtil.getHeader(c.originalRom, source); SetHeader(header); header.put(rom, ShadowObjects);
            int objectEnd = ShadowObjects + 32;
            for (int i = 0; i < 3; i++)
            {
                if (shadows[i].getSpecies() != DoppelgangerBossArenaRedirect.SHADOW_SPECIES[i] || shadows[i].getEvent() != 0)
                    throw new InvalidOperationException("Native shadow identity changed.");
                if (ForeignSlot == null) shadows[i].setNeverVisible();
                else
                {
                    shadows[i].setEventVisFlag((byte)Flag); shadows[i].setEventVisMinimum(0); shadows[i].setEventVisMaximum((byte)(Completed - 1));
                    shadows[i].setXpos(Spawns[i].X); shadows[i].setYpos(Spawns[i].Y);
                }
                shadows[i].put(rom, ShadowObjects + 8 + 8 * i);
            }
            if (ForeignSlot == VanillaBossMaps.TROPICALLO)
            {
                var objects = VanillaMapUtil.getObjects(rom, source);
                if (objects.Count != 3 || objects[1].getSpecies() != 0x8C || objects[2].getSpecies() != 0x9B)
                    throw new InvalidOperationException("Tropicallo NPC contract changed.");
                objects[1].put(rom, objectEnd); objects[2].put(rom, objectEnd + 8); objectEnd += 16;
                var floor = new DirectBossFloor(rom, source);
                foreach (var p in Spawns) floor.RequirePocket(p.X, p.Y, 1, 0x4B, 0xA9);
                floor.RequireConnected(29, 41, Spawns, 0x4B, 0xA9);
            }
            if (ForeignSlot == VanillaBossMaps.FROSTGIGAS)
            {
                var floor = new DirectBossFloor(rom, source);
                foreach (var p in Spawns) floor.RequirePocket(p.X, p.Y, 1, 0, 0);
                floor.RequireConnected(9, 16, Spawns, 0, 0);
            }
            if (PreservesDestinationTraversal)
            {
                // Tileset30: walkable ground Collision[0]=00, passive canopy
                // Collision[0]=17. Keep canopy tiles, collision and both entry
                // coordinates; validate 3x3 actor pockets and both approaches.
                var floor = new DirectBossFloor(rom, source, null, 0x17);
                foreach (var p in Spawns) floor.RequirePocket(p.X, p.Y, 1, 0, 255);
                foreach (int id in Destination.Doors)
                {
                    var door = VanillaDoorUtil.getDoor(c.originalRom, id);
                    floor.RequireConnected(door.getXpos(), door.getYpos(), Spawns, 0, 255);
                }
            }
            CopyRefs(rom, VanillaMapUtil.getMapPieceReference(c.originalRom, source), ShadowRefs, 17);
            int refsEnd = ShadowRefs + VanillaMapUtil.makeMapPieceReference(VanillaMapUtil.getMapPieceReference(c.originalRom, source)).Length;
            // Native Jehk exit tiles remain mapped to the guarded completion.
            // Pure Lands instead retains its four native exit triggers below.
            int triggerEnd = ShadowTriggers + 2;
            Word(rom, ShadowTriggers, 0x6D5);
            if (source == MAPNUM_DOPPEL_ARENA)
            {
                // Requires a longer tail only for legacy Mantis + new reverse.
                for (int i = 1; i <= 4; i++) Word(rom, ShadowTriggers + i * 2, 0x6D6);
                triggerEnd += 8;
            }
            else if (PreservesDestinationTraversal)
            {
                var triggers = VanillaMapUtil.getTriggers(c.originalRom, source);
                if (!triggers.SequenceEqual(new ushort[] { 0x5EC, 0x5DF, 0x5DF, 0x5DE, 0x5DE }))
                    throw new InvalidOperationException("Pure Lands traversal trigger contract changed.");
                for (int i = 1; i < triggers.Count; i++) Word(rom, ShadowTriggers + i * 2, triggers[i]);
                triggerEnd += 8;
            }
            else if (VanillaMapUtil.getTriggers(c.originalRom, source).Count != 0)
                throw new InvalidOperationException("Destination needs a tile-trigger adapter.");
            foreach (int table in new[] { 0x87000, 0x85000, 0x84000 })
            {
                Word(rom, table + 497 * 2, table == 0x87000 ? ReverseObjects : table == 0x85000 ? ReverseRefs : ReverseTriggers);
                Word(rom, table + 498 * 2, table == 0x87000 ? ShadowObjects : table == 0x85000 ? ShadowRefs : ShadowTriggers);
                Word(rom, table + 499 * 2, table == 0x87000 ? objectEnd : table == 0x85000 ? refsEnd : triggerEnd);
            }
            if (ForeignSlot != null)
            {
                if (ReturnDoor == 0xCB)
                {
                    // Native Door0CB's only target is unused496. Reconfirm both
                    // event and tile-trigger callers before claiming this ID.
                    for(int e=0;e<0x800;e++) {
                        var bytes=c.replacementEvents.ContainsKey(e) ? c.replacementEvents[e] : VanillaEventUtil.getVanillaEvent(c.originalRom,e);
                        for(int i=0;i+1<bytes.Count;i++)
                            if(bytes[i]==0x18 && bytes[i+1]==0xCB) throw new InvalidOperationException("Trial return door has an event owner.");
                    }
                    for(int map=0;map<512;map++)
                        if(VanillaMapUtil.getTriggers(c.originalRom,map).Contains((ushort)0x8CB))
                            throw new InvalidOperationException("Trial return door has a tile-trigger owner.");
                    SetDoor(c,ReturnDoor,VanillaDoorUtil.getDoor(c.originalRom,EntryDoor));
                }
                foreach (int id in Destination.Doors)
                {
                    if (VanillaDoorUtil.getDoor(c.originalRom,id).getTargetMap() != ForeignSlot.originalMapNum)
                        throw new InvalidOperationException("Shadow destination entry contract changed.");
                    var door = VanillaDoorUtil.getDoor(c.originalRom, UsesDonor ? 0x304 : id);
                    door.setTargetMap(498); SetDoor(c, id, door);
                }
                InstallDispatcher(rom, c);
            }
        }

        public void PatchEvents(RandoContext c)
        {
            if (ForeignSlot != null)
            {
                BossArenaGeometry.RequireUnusedEvents(c.originalRom, c, 0x6D5, 0x6D6, 0x6B9);
                var back = new EventScript();
                if (ForeignSlot == VanillaBossMaps.MECHRIDER2)
                    back.Add(EventCommandEnum.FLAMMIE_FROM_POS.Value,0x64); // native $52F's 1C64, NOT Door464
                else if (ReturnDoor >= 0) back.Door(ReturnDoor);
                if (ReturnMusic >= 0) back.Jsr(ReturnMusic); back.End();
                c.replacementEvents[0x6B9] = back;
                if (ReturnDoor == 0xCB)
                {
                    var reward=c.replacementEvents[Completion];
                    if(!reward.Skip(reward.Count-3).SequenceEqual(new byte[]{0x16,0x2A,0}))
                        throw new InvalidOperationException("Pure Lands reward continuation changed.");
                    // Keep every reward/flag/refresh and $62A/MTR/music tail,
                    // inserting only the destination-owned regular-map return.
                    reward.InsertRange(reward.Count-3,new byte[]{0x18,0xCB});
                }
                // Completed Dragon Worm entry stays on the recognizable clearing
                // and selects its area music. Never bounce to a second arena or
                // force every approach back through the lower entrance.
                var entry = new EventScript(); entry.Logic((byte)Flag, (byte)Completed, 15,
                    EventScript.GetJumpCmd(PreservesDestinationTraversal ? ReturnMusic : 0x6B9));
                if (ForeignSlot == VanillaBossMaps.LIMESLIME || ForeignSlot == VanillaBossMaps.DREADSLIME)
                    entry.SetFlag(EventFlags.DEATH_TYPE_FLAG,2);
                entry.Jsr(PreservesDestinationTraversal ? 0x7C4 : 0x704); entry.End(); c.replacementEvents[0x6D5] = entry;
                var complete = new EventScript(); complete.Logic((byte)Flag, (byte)Completed, 15, EventScript.GetJumpCmd(0));
                for (byte i = 4; i <= 6; i++) complete.AddRange(new byte[] { 0x4A, i, 0x91, 0x7F, 0x10, 0 });
                if (ForeignSlot == VanillaBossMaps.MANTISANT) complete.SetFlag(0x10, 12);
                complete.Jump(Completion); complete.End(); c.replacementEvents[0x6D6] = complete;
                // Post-door walk-ons are suppressed while their calling event is
                // busy. Explicitly execute the destination-bound guarded entry.
                int access = Destination.EntryEvent;
                if (access >= 0)
                {
                    if (!UsesDonor)
                    {
                        var accepted = new EventScript(); accepted.Door(EntryDoor); accepted.Jump(0x6D5); accepted.End();
                        c.replacementEvents[access] = accepted;
                    }
                    else
                    {
                    // Preserve entry-side flags/guards/music. Insert the shared
                    // entry call at the real door opcode boundary, not in text.
                    var script = c.replacementEvents.ContainsKey(access) ? c.replacementEvents[access]
                        : VanillaEventUtil.getVanillaEvent(c.originalRom, access);
                    int at = FindEntryDoor(script, EntryDoor);
                    script.InsertRange(at+2, new byte[] { 0x26, 0xD5 });
                    if (ForeignSlot == VanillaBossMaps.WALLFACE)
                    {
                        // The original post-door F7 positioning assumes Wall's
                        // room, not the three-shadow donor. Its surrounding FF
                        // increments/decrements cancel; preserve the pre-door
                        // Thanatos/story flags, then use our normal entry.
                        script.RemoveRange(at+4,script.Count-at-4);script.Add(0);
                    }
                    // Native Mode-7 entrances set 0F after the door. This is a
                    // regular native-Jehk donor, so preserve all other commands
                    // but select ordinary death handling for these two entries.
                    if (ForeignSlot == VanillaBossMaps.LIMESLIME || ForeignSlot == VanillaBossMaps.DREADSLIME)
                        for (int i=0;i+2<script.Count;i++)
                            if(script[i]==0x30 && script[i+1]==EventFlags.DEATH_TYPE_FLAG && script[i+2]==15) script[i+2]=2;
                    // Completed re-entry must not repeat a native pre-door
                    // increment (Watermelon45, Dread4E, Wall1A, Fire18).
                    var guard = new EventScript(); guard.Logic((byte)Flag,(byte)Completed,15,EventScript.GetJumpCmd(0x6B9));
                    script.InsertRange(0,guard);
                    c.replacementEvents[access] = script;
                    }
                }
                // Destination prize events 1B9 / 66D are deliberately untouched.
            }
            if (HasReverse)
            {
                // Reuse the established guarded death -> flag5 -> 4E5 path. The
                // original post-prefix reward/healing sequence stays authoritative.
                DoppelgangerBossArenaRedirect.PatchReverseEvents(c);
                var completion = c.replacementEvents[0x4E5];
                byte[] tail = { 0x18, 0x38, 6, 0x24, 0x1B, 0x2F, 0x84, 0 };
                if (!completion.Skip(completion.Count - tail.Length).SequenceEqual(tail))
                    throw new InvalidOperationException("Jehk return/restoration contract changed.");
                // Destination-owned music must be requested explicitly after the
                // return door; its walk-on cannot run during the active prize.
                completion.InsertRange(completion.Count - tail.Length + 2, new byte[] { 0x26, 0x26 });
                c.replacementEvents[0x6BA].InsertRange(2, new byte[] { 0x26, 0x26 });
            }
        }

        public int InstallDispatcher(byte[] rom, RandoContext c)
        {
            byte[] previous = rom.Skip(IdleHook).Take(4).ToArray();
            if (!previous.SequenceEqual(new byte[] { 0xA5, 0xFF, 0x05, 0x52 }) && previous[0] != 0x22)
                throw new InvalidOperationException("Unknown idle-hook owner; cannot safely chain.");
            // Chain ONLY the known Crystal Orb dispatcher, not arbitrary code.
            if (previous[0] == 0x22 && (!c.workingData.hasSetting("crystalOrbWeaponBreakingDeferredRoutineOffsetHirom")
                || (previous[1] | previous[2] << 8 | previous[3] << 16) != c.workingData.getInt("crystalOrbWeaponBreakingDeferredRoutineOffsetHirom")))
                throw new InvalidOperationException("Idle hook is not the declared Crystal Orb dispatcher.");
            var a = new Asm();
            a.Emit(0x08, 0xC2, 0x20, 0x48, 0xDA, 0x5A, 0x8B, 0x0B, 0xC2, 0x30);
            a.Long(0xAF, 0x7E00DC); a.Word(0xC9, 498); a.If(0xD0, "done");
            foreach (int at in new[] { 0x7E00D0, 0x7E00FF, 0x7E0052 })
            { a.Long(0xAF, at); a.Word(0x29, 255); a.If(0xD0, "done"); }
            a.Long(0xAF, 0x7E00E2); a.Word(0x29, 1); a.If(0xD0, "done");
            a.Long(0xAF, 0x7E00E8); a.Word(0x29, 4); a.If(0xD0, "done");
            a.Long(0xAF, 0x7ECF00 + Flag); a.Word(0x29, 255); a.Word(0xC9, Completed); a.If(0xB0, "done");
            for (int i = 0; i < 3; i++)
            {
                int actor = 0x600 + i * 0x200;
                a.Long(0xAF, 0x7EE1E7 + actor); a.Word(0x29, 255); a.Word(0xC9, DoppelgangerBossArenaRedirect.SHADOW_SPECIES[i]); a.If(0xD0, "done");
                a.Long(0xAF, 0x7EE191 + actor); a.Word(0x29, 128); a.If(0xF0, "done");
                // Native $4A at Jehk is STATUS-only. Do not require HP zero or
                // a cleared graphics pointer in addition: native AI can mark a
                // shadow defeated independently of ordinary damage (the
                // counterpart-death tactic). Its three $4A checks below remain
                // authoritative. A residual visual is not a living actor.
                // Removed/unrecruited party slots can retain animation bytes;
                // just like the native wipe check, only active players gate us.
                a.Long(0xAF, 0x7EE000 + i * 0x200); a.Word(0x29, 255); a.If(0xF0, "quiet" + i);
                a.Word(0xC9, 128); a.If(0xB0, "quiet" + i);
                a.Long(0xAF, 0x7EE060 + i * 0x200); a.Word(0x29, 255); a.If(0xD0, "done");
                a.Long(0xAF, 0x7EE01C + i * 0x200); a.Word(0x29, 255); a.If(0xD0, "done");
                a.Label("quiet" + i);
            }
            for (int i = 0; i < 3; i++)
            {
                string next = "player" + i;
                a.Long(0xAF, 0x7EE000 + i * 0x200); a.Word(0x29, 255); a.If(0xF0, next);
                a.Word(0xC9, 128); a.If(0xB0, next);
                a.Long(0xAF, 0x7EE191 + i * 0x200); a.Word(0x29, 128); a.If(0xD0, next);
                a.Long(0xAF, 0x7EE182 + i * 0x200); a.If(0xF0, next);
                a.Word(0xA9, i * 0x200); a.Long(0x8F, 0x7E00D4);
                a.Word(0xA9, 0x6D6); a.Long(0x22, 0xC1E76D); a.Go("done"); a.Label(next);
            }
            a.Label("done"); a.Emit(0x2B, 0xAB, 0xE2, 0x10, 0x7A, 0xFA, 0xC2, 0x20, 0x68, 0x28);
            // Previous dispatcher replays the same four displaced instructions.
            // Call it exactly once; it sees any newly busy event state and keeps
            // its own queued Orb hit lifecycle. Native BNE stays untouched.
            a.Emit(previous); a.Emit(0x6B);
            byte[] code = a.Bytes(); CodeGenerationUtils.ensureSpaceInBank(ref c.workingOffset, code.Length);
            int atCode = c.workingOffset; Array.Copy(code, 0, rom, atCode, code.Length); c.workingOffset += code.Length;
            rom[IdleHook] = 0x22; rom[IdleHook + 1] = (byte)atCode; rom[IdleHook + 2] = (byte)(atCode >> 8); rom[IdleHook + 3] = (byte)((atCode >> 16) + 0xC0);
            c.workingData.setInt("DoppelgangerDispatcher", atCode); c.workingData.setInt("DoppelgangerDispatcherLength", code.Length);
            return atCode;
        }

        static void SetHeader(MapHeader h) { h.setWalkonEventEnabled(true); h.setSpecialEventEnabled(false); h.setMagicRopeEnabled(false); h.setFlammieEnabled(false); }
        static int FindEntryDoor(IList<byte> script, int door)
        {
            // Only pre-audited entry scripts: stop rather than inspect dialogue
            // as opcodes. All admitted entries put their door before any text.
            for(int i=0;i<script.Count;)
            {
                int op=script[i];
                if(op==0x18+(door>>8) && i+1<script.Count && script[i+1]==(byte)door) return i;
                if(op==0 || op==0x50 || op>=0x7F) break;
                int size=op==0x42 || op==0x40 ? 5 : op==0x39 ? 4
                    : op==0x30 || op==0x31 || op==0x32 || op==0x34 || op==0x36 || op==0x37 ? 3
                    : op>=0x10 && op<=0x2F ? 2 : 1;
                i+=size;
            }
            throw new InvalidOperationException("Audited shadow entry door " + door.ToString("X3") + " not found in " + BitConverter.ToString(script.ToArray()));
        }
        static FullMapMapPieceReference Piece(int id, bool fg) { return new FullMapMapPieceReference { pieceIndex = id, isForegroundPiece = fg, eventVisibilityValueHigh = 15 }; }
        static void CopyRefs(byte[] r, FullMapMapPieces p, int at, int capacity) { byte[] b = VanillaMapUtil.makeMapPieceReference(p); if (b.Length > capacity) throw new InvalidOperationException("Trial refs exceed capacity."); Array.Copy(b, 0, r, at, b.Length); }
        static void SetDoor(RandoContext c, int id, Door door) { if (c.replacementDoors.ContainsKey(id)) throw new InvalidOperationException("Trial door already owned."); c.replacementDoors[id] = door; }
        static void Word(byte[] r, int at, int v) { r[at] = (byte)v; r[at + 1] = (byte)(v >> 8); }
        sealed class Asm
        {
            readonly List<byte> code = new List<byte>(); readonly Dictionary<string, int> labels = new Dictionary<string, int>();
            readonly List<KeyValuePair<int, string>> fixups = new List<KeyValuePair<int, string>>();
            public void Emit(params byte[] b) { code.AddRange(b); }
            public void Word(byte op, int v) { Emit(op, (byte)v, (byte)(v >> 8)); }
            public void Long(byte op, int v) { Emit(op, (byte)v, (byte)(v >> 8), (byte)(v >> 16)); }
            public void Label(string name) { labels.Add(name, code.Count); }
            public void Go(string name) { Emit(0x82, 0, 0); fixups.Add(new KeyValuePair<int, string>(code.Count - 2, name)); }
            public void If(byte op, string name) { Emit((byte)(op ^ 0x20), 3); Go(name); }
            public byte[] Bytes() { foreach (var f in fixups) { int d = labels[f.Value] - f.Key - 2; code[f.Key] = (byte)d; code[f.Key + 1] = (byte)(d >> 8); } return code.ToArray(); }
        }
    }
}

