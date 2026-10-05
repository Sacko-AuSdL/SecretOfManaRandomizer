using SoMRandomizer.config.settings;
using SoMRandomizer.logging;
using SoMRandomizer.processing.common;
using SoMRandomizer.util;
using System;
using System.Collections.Generic;
using static SoMRandomizer.processing.common.CustomRamOffsets;

namespace SoMRandomizer.processing.hacks.common.music
{
    /// <summary>
    /// Restore inherited gameplay music after the load menu's intentional $80,$20 fade.
    /// No map-song guesses, event replay, RNG calls, or SPC-memory modifications.
    /// </summary>
    public class SaveMusicRestoration : RandoProcessor
    {
        // Four $400-byte slots, primary $30:6000 and backup $30:7000.
        // Native data ends at +$2BB (version $3A). C7:5CDC sums +$003..$2BA;
        // C7:5C74 compares +$000..$2BA. Autosave uses slot 3 and $30:7FFF;
        // ConfuseFix owns a byte within +$295. No other supported-mode writer
        // owns this padding. Native save/load/checksum lengths stay unchanged.
        public const int METADATA_OFFSET = 0x2BC;
        public const int METADATA_LENGTH = 10;
        // +0..1 "SM", +2 version 1, +3..5 effective request, +6..7 world checksum,
        // +8 XOR guard, +9 inverted guard. Old/corrupt metadata is simply ignored.
        // The world checksum excludes +$2B7/$2B8: C7:5618 updates generation
        // counters/checksums in OTHER slots whenever a new save is made.

        protected override string getName() { return "Persist and restore inherited gameplay music"; }

        protected override bool process(byte[] origRom, byte[] outRom, string seed, RandoSettings settings, RandoContext context)
        {
            string mode = settings.get(CommonSettings.PROPERTYNAME_MODE);
            if ((mode != OpenWorldSettings.MODE_KEY && mode != VanillaRandoSettings.MODE_KEY) ||
                settings.getBool(CommonSettings.PROPERTYNAME_MUTE_MUSIC)) return false;

            // Validate hook ownership before changing any bytes. Autosave and RandomMusic
            // have already run; deliberately chain their load/reset trampolines.
            Require(outRom, 0x10010, 0x5C);
            Require(outRom, 0x755C7, 0x22);
            Require(outRom, 0x755D6, 0x20, 0xC6, 0x57, 0xDA);
            Require(outRom, 0x756C5, 0x9F, 0x01, 0x60, 0x30);
            Require(outRom, 0x1F109, 0x22, 0x04, 0x00, 0xC3);
            Require(outRom, 0x301E4, 0xA5, 0x03, 0x8D, 0x43, 0x21);
            Require(outRom, 0xB0BF, 0x22, 0xE0, 0xBF, 0x01);
            int previousReset = Address(outRom, 0x10011);
            int previousLoad = Address(outRom, 0x755C8);

            if (outRom[0x301AD] == 0x22)
            {
                // Chain RandomMusic only in these save/load modes. A tail JML keeps
                // its stack-sensitive duplicate-song return exactly intact. Replay
                // already has effective parameters: no original-song comparison/RNG.
                int previousRandom = Address(outRom, 0x301AE);
                var replay = new Routine();
                replay.Long(0xAF, SAVED_MUSIC_REPLAY);
                replay.Emit(0xC9, 1);
                replay.If(0xD0, "normal");
                replay.Emit(0xA5, 2, 0x29, 0xF0, 0x6B);
                replay.Label("normal");
                replay.Long(0x5C, previousRandom);
                Hook(outRom, context, 0x301AD, replay);
            }
            else Require(outRom, 0x301AD, 0xA5, 2, 0x29, 0xF0);

            var reset = new Routine();
            reset.Emit(0xE2, 0x20, 0xA9, 0);
            foreach (int address in new[] { SAVED_MUSIC_VALID, SAVED_MUSIC_EVENT_CAPTURE,
                SAVED_MUSIC_REPLAY, SAVED_MUSIC_PENDING }) reset.Long(0x8F, address);
            reset.Long(0x5C, previousReset); // retain the existing $042F invalidation
            Hook(outRom, context, 0x10010, reset, 0x5C);

            var entry = new Routine();
            // Exact C7:57C6 slot calculation, then the displaced PHX. JML adds
            // no stack frame: the native save routine retains its original stack.
            entry.Emit(0xC2, 0x20, 0xAD, 0x11, 0xA2, 0x29, 0xFF, 0, 0xEB, 0x0A, 0x0A, 0xAA);
            entry.Long(0x8F, SAVED_MUSIC_SLOT_16BIT);
            entry.Emit(0xE2, 0x20, 0xDA);
            entry.Long(0x5C, 0xC755DA);
            Hook(outRom, context, 0x755D6, entry, 0x5C);

            var save = new Routine();
            save.Long(0x9F, 0x306001); // displaced native checksum store, A16/X16
            save.Push();
            save.Emit(0x8A); // TXA: only this save's slot, not counter updates to other slots
            save.Long(0xCF, SAVED_MUSIC_SLOT_16BIT);
            save.If(0xD0, "done");
            save.Emit(0xE2, 0x20, 0xA9, 0);
            StoreBoth(save, 0); // invalidate first, commit marker last
            save.Long(0xAF, SAVED_MUSIC_VALID);
            save.Emit(0xC9, 1);
            save.If(0xD0, "done");
            for (int i = 0; i < 3; i++)
            {
                save.Long(0xAF, SAVED_MUSIC_REQUEST + i);
                StoreBoth(save, 3 + i);
            }
            Fingerprint(save, 0); // X = primary slot base
            StoreBoth(save, 6); // A16 writes +6 and +7
            save.Emit(0xE2, 0x20);
            Guard(save, 0);
            StoreBoth(save, 8);
            save.Emit(0x49, 0xFF);
            StoreBoth(save, 9);
            save.Emit(0xA9, 1);
            StoreBoth(save, 2);
            save.Emit(0xA9, 0x4D);
            StoreBoth(save, 1);
            save.Emit(0xA9, 0x53);
            StoreBoth(save, 0);
            save.Label("done");
            save.Pop();
            save.Emit(0x6B);
            Hook(outRom, context, 0x756C5, save);

            var load = new Routine();
            // Read metadata BEFORE C0:0021 initializes actors and clobbers X.
            // Only the native PLX at C7:55D1 restores the selected slot afterward.
            load.Push(); // X = selected primary OR backup slot base + 1
            load.Emit(0xE2, 0x20, 0xA9, 0);
            foreach (int address in new[] { SAVED_MUSIC_VALID, SAVED_MUSIC_PENDING,
                SAVED_MUSIC_EVENT_CAPTURE, SAVED_MUSIC_REPLAY }) load.Long(0x8F, address);
            load.Emit(0xC2, 0x20);
            load.Long(0xBF, 0x306000 + METADATA_OFFSET - 1);
            load.Emit(0xC9, 0x53, 0x4D);
            load.If(0xD0, "done");
            load.Emit(0xE2, 0x20);
            load.Long(0xBF, 0x306000 + METADATA_OFFSET + 1);
            load.Emit(0xC9, 1);
            load.If(0xD0, "done");
            Guard(load, -1);
            load.Long(0xDF, 0x306000 + METADATA_OFFSET + 7);
            load.If(0xD0, "done");
            load.Emit(0x49, 0xFF);
            load.Long(0xDF, 0x306000 + METADATA_OFFSET + 8);
            load.If(0xD0, "done");
            Fingerprint(load, -1);
            load.Long(0xDF, 0x306000 + METADATA_OFFSET + 5);
            load.If(0xD0, "done");
            load.Emit(0xE2, 0x20);
            for (int i = 0; i < 3; i++)
            {
                load.Long(0xBF, 0x306000 + METADATA_OFFSET + 2 + i);
                load.Long(0x8F, SAVED_MUSIC_REQUEST + i);
            }
            load.Emit(0xC2, 0x20);
            load.Long(0xAF, 0x7EA25A); // authoritative saved door, no map-song lookup
            load.Emit(0x29, 0xFF, 3, 0x0A, 0x0A, 0xAA);
            load.Long(0xBF, 0xC83000);
            load.Emit(0x29, 0xFF, 1);
            load.Long(0x8F, SAVED_MUSIC_MAP_16BIT);
            load.Emit(0xE2, 0x20, 0xA9, 1);
            load.Long(0x8F, SAVED_MUSIC_VALID);
            load.Long(0x8F, SAVED_MUSIC_PENDING);
            load.Label("done");
            load.Pop();
            load.Long(0x22, previousLoad); // preserve Autosave's DONT_AUTOSAVE handling
            load.Emit(0x6B);
            Hook(outRom, context, 0x755C7, load);

            var request = new Routine();
            request.Push(); // event command $40, DP=0; entry A16/X8
            request.Emit(0xE2, 0x20, 0xA9, 0);
            request.Long(0x8F, SAVED_MUSIC_EVENT_CAPTURE);
            request.Long(0xAF, 0x7E1E00);
            request.Emit(0xC9, 1);
            request.If(0xD0, "call");
            request.Long(0xAF, 0x7E1E01);
            request.Emit(0xC9, 7); // game-over music (events $7C7/$7C8), not gameplay
            request.If(0xF0, "call");
            request.Emit(0xC2, 0x20);
            request.Long(0xAF, 0x7E00DC);
            request.Emit(0xC9, 8, 0); // death map
            request.If(0xF0, "call");
            request.Emit(0xC9, 0, 1); // intro/title log map
            request.If(0xF0, "call");
            Alive(request, "accept", "call");
            request.Label("accept");
            request.Emit(0xE2, 0x20, 0xA9, 1);
            request.Long(0x8F, SAVED_MUSIC_EVENT_CAPTURE);
            request.Label("call");
            request.Pop();
            request.Long(0x22, 0xC30004);
            request.Push();
            request.Emit(0xE2, 0x20, 0xA9, 0);
            request.Long(0x8F, SAVED_MUSIC_EVENT_CAPTURE);
            request.Pop();
            request.Emit(0x6B);
            Hook(outRom, context, 0x1F109, request);

            var capture = new Routine();
            capture.Emit(0xA5, 3, 0x8D, 0x43, 0x21); // displaced actual parameter send, DP=$1E00
            capture.Push();
            capture.Emit(0xE2, 0x20);
            capture.Long(0xAF, SAVED_MUSIC_EVENT_CAPTURE);
            capture.Emit(0xC9, 1);
            capture.If(0xF0, "accept");
            capture.Long(0xAF, SAVED_MUSIC_REPLAY);
            capture.Emit(0xC9, 1);
            capture.If(0xD0, "done");
            capture.Label("accept");
            for (int i = 0; i < 3; i++)
            {
                capture.Emit(0xA5, 1 + i);
                capture.Long(0x8F, SAVED_MUSIC_REQUEST + i);
            }
            capture.Emit(0xA9, 1);
            capture.Long(0x8F, SAVED_MUSIC_VALID);
            capture.Emit(0xA9, 0);
            capture.Long(0x8F, SAVED_MUSIC_PENDING); // a real entry request wins
            capture.Label("done");
            capture.Pop();
            capture.Emit(0x6B);
            Hook(outRom, context, 0x301E4, capture, 0x22, 5);

            var deferred = new Routine();
            deferred.Long(0x22, 0x01BFE0); // original per-frame call, AFTER map/event processing
            deferred.Push();
            deferred.Emit(0xE2, 0x20);
            deferred.Long(0xAF, SAVED_MUSIC_PENDING);
            deferred.Emit(0xC9, 1);
            deferred.If(0xD0, "done");
            deferred.Emit(0xC2, 0x20);
            deferred.Long(0xAF, 0x7E00DC);
            deferred.Long(0xCF, SAVED_MUSIC_MAP_16BIT);
            deferred.If(0xD0, "cancel");
            deferred.Emit(0xE2, 0x20);
            deferred.Long(0xAF, 0x7E00D0); // active event: wait, don't replay its logic
            deferred.If(0xD0, "done");
            deferred.Long(0xAF, 0x7E00FF); // a door/transition is pending
            deferred.If(0xD0, "done");
            Alive(deferred, "replay", "cancel");
            deferred.Label("replay");
            deferred.Emit(0xE2, 0x20, 0xA9, 0);
            deferred.Long(0x8F, SAVED_MUSIC_PENDING); // consume BEFORE calling the driver
            deferred.Emit(0xA9, 1);
            deferred.Long(0x8F, SAVED_MUSIC_REPLAY);
            deferred.Long(0x8F, 0x7E1E00);
            for (int i = 0; i < 3; i++)
            {
                deferred.Long(0xAF, SAVED_MUSIC_REQUEST + i);
                deferred.Long(0x8F, 0x7E1E01 + i);
            }
            deferred.Emit(0xA9, 0xFF);
            deferred.Long(0x8F, MUSICRANDO_LASTSONG_BYTE);
            deferred.Emit(0xC2, 0x20, 0xA9, 0xFF, 0xFF);
            deferred.Long(0x8F, 0x7E1E05); // native song/echo cache: force this one full request
            deferred.Long(0x22, 0xC30004);
            deferred.Label("cancel");
            deferred.Emit(0xE2, 0x20, 0xA9, 0);
            deferred.Long(0x8F, SAVED_MUSIC_PENDING);
            deferred.Long(0x8F, SAVED_MUSIC_REPLAY);
            deferred.Label("done");
            deferred.Pop();
            deferred.Emit(0x6B);
            Hook(outRom, context, 0xB0BF, deferred);

            Logging.log("Save music metadata: slot +$2BC..$2C5, primary and backup; one-shot inherited-room restore.");
            return true;
        }

        private static void Alive(Routine r, string alive, string dead)
        {
            foreach (int actor in new[] { 0x7EE000, 0x7EE200, 0x7EE400 })
            {
                string next = "actor" + r.Position;
                r.Emit(0xE2, 0x20);
                r.Long(0xAF, actor); // same present-character predicate as Autosave
                r.If(0xF0, next);
                r.Emit(0xC2, 0x20);
                r.Long(0xAF, actor + 0x182);
                r.If(0xD0, alive);
                r.Label(next);
            }
            r.Jump(dead);
        }

        private static void StoreBoth(Routine r, int field)
        {
            r.Long(0x9F, 0x306000 + METADATA_OFFSET + field);
            r.Long(0x9F, 0x307000 + METADATA_OFFSET + field);
        }

        private static void Fingerprint(Routine r, int adjustment)
        {
            r.Emit(0xC2, 0x20);
            r.Long(0xBF, 0x3062B7 + adjustment);
            r.Emit(0x29, 0xFF, 0);
            r.Long(0x8F, SAVED_MUSIC_SCRATCH_16BIT);
            r.Long(0xBF, 0x3062B8 + adjustment);
            r.Emit(0x29, 0xFF, 0, 0x18);
            r.Long(0x6F, SAVED_MUSIC_SCRATCH_16BIT);
            r.Long(0x8F, SAVED_MUSIC_SCRATCH_16BIT);
            r.Long(0xBF, 0x306001 + adjustment);
            r.Emit(0x38);
            r.Long(0xEF, SAVED_MUSIC_SCRATCH_16BIT);
        }

        private static void Guard(Routine r, int adjustment)
        {
            r.Long(0xBF, 0x306000 + METADATA_OFFSET + 3 + adjustment);
            foreach (int field in new[] { 4, 5, 6, 7 })
                r.Long(0x5F, 0x306000 + METADATA_OFFSET + field + adjustment);
            r.Emit(0x49, 0xA4); // $A5 XOR format version 1
        }

        private static int Address(byte[] rom, int offset)
        {
            return rom[offset] | rom[offset + 1] << 8 | rom[offset + 2] << 16;
        }

        private static void Require(byte[] rom, int offset, params byte[] expected)
        {
            for (int i = 0; i < expected.Length; i++)
                if (rom[offset + i] != expected[i])
                    throw new InvalidOperationException("SaveMusicRestoration hook conflict at ROM $" + offset.ToString("X6"));
        }

        private static void Hook(byte[] rom, RandoContext context, int offset, Routine routine, byte opcode = 0x22, int length = 4)
        {
            byte[] bytes = routine.Finish();
            CodeGenerationUtils.ensureSpaceInBank(ref context.workingOffset, bytes.Length);
            int address = context.workingOffset + 0xC00000;
            rom[offset] = opcode;
            for (int i = 0; i < 3; i++) rom[offset + 1 + i] = (byte)(address >> (8 * i));
            for (int i = 4; i < length; i++) rom[offset + i] = 0xEA;
            Array.Copy(bytes, 0, rom, context.workingOffset, bytes.Length);
            context.workingOffset += bytes.Length;
        }

        // Labelled BRL fixups avoid hand-counted branch displacements. Conditional
        // branches invert their condition and skip a BRL; each routine stays in-bank.
        private sealed class Routine
        {
            private readonly List<byte> bytes = new List<byte>();
            private readonly Dictionary<string, int> labels = new Dictionary<string, int>();
            private readonly List<Tuple<int, string>> jumps = new List<Tuple<int, string>>();
            internal int Position { get { return bytes.Count; } }
            internal void Emit(params int[] values) { foreach (int value in values) bytes.Add((byte)value); }
            internal void Long(int opcode, int address) { Emit(opcode, address, address >> 8, address >> 16); }
            internal void Label(string name) { labels.Add(name, Position); }
            internal void Jump(string label) { Emit(0x82, 0, 0); jumps.Add(Tuple.Create(Position - 2, label)); }
            internal void If(int opcode, string label) { Emit(opcode ^ 0x20, 3); Jump(label); }
            internal void Push() { Emit(0x08, 0xC2, 0x30, 0x48, 0xDA, 0x5A); }
            internal void Pop() { Emit(0xC2, 0x30, 0x7A, 0xFA, 0x68, 0x28); }
            internal byte[] Finish()
            {
                foreach (var jump in jumps)
                {
                    int delta = labels[jump.Item2] - (jump.Item1 + 2);
                    if (delta < short.MinValue || delta > short.MaxValue) throw new InvalidOperationException("Music routine branch overflow");
                    bytes[jump.Item1] = (byte)delta;
                    bytes[jump.Item1 + 1] = (byte)(delta >> 8);
                }
                return bytes.ToArray();
            }
        }
    }
}
