using System;
using System.Linq;
using SoMRandomizer.config.settings;
using SoMRandomizer.logging;
using SoMRandomizer.processing.common;

namespace SoMRandomizer.processing.hacks.openworld
{
    /// <summary>Opt out of exactly the native shadow counterpart-HP checks.</summary>
    public sealed class DoppelgangerDeathLink : RandoProcessor
    {
        public static readonly int[] Gates = { 0x10A735, 0x10A74A, 0x10A75F };
        public static readonly int[] StatusGates = { 0x10A70B, 0x10A719, 0x10A727 };
        protected override string getName() { return "Doppelganger Death Link"; }
        protected override bool process(byte[] original, byte[] output, string seed, RandoSettings settings, RandoContext context)
        {
            if (settings.get(CommonSettings.PROPERTYNAME_MODE) != OpenWorldSettings.MODE_KEY) return false;
            bool enabled = settings.get(OpenWorldSettings.PROPERTYNAME_DOPPELGANGER_DEATH_LINK) != "off";
            Logging.log("Doppelganger Death Link: " + (enabled ? "On (Vanilla)" : "Off (Challenge)"), "spoiler");
            if (enabled) return false;
            // Native species metadata at D0:0009 contains VM offsets, NOT ROM
            // addresses. C1:2521 fetches D0:4F15 + PC; 5605 starts D0:A51A.
            // FF 58 20 / FF 58 12 call these shared native script branches.
            // $30 = unsigned byte <= (C1:208A); $80 = self, $67 = E1E7.
            // Each matched branch tests counterpart HP with $BD, then $DC sets
            // self E191 bit80; $E3/$EE start native death animation. Slots are
            // physical 2/0/1, independent of selected gameplay roles.
            // Lowering ONLY the species upper bounds to zero makes each live
            // shadow skip its counterpart-death branch. Its own HP-zero check
            // at D0:A6FC, normal AI, and all player handlers are untouched.
            byte[] species = { 0x20, 0x2E, 0x3F }, players = { 2, 0, 1 };
            for (int i = 0; i < Gates.Length; i++)
            {
                byte[] expected = { 0x30, 0x80, 0x67, species[i], (byte)(i == 2 ? 0x8E : 0x90),
                    0xBD, players[i], 2, 0, 0, 0x88, 0xDC, 0x80, 0x11, 0x80, 0xE3, 0x31, 0, 0xEE };
                if (!original.Skip(Gates[i]).Take(expected.Length).SequenceEqual(expected)
                    || !output.Skip(Gates[i]).Take(expected.Length).SequenceEqual(expected))
                    throw new InvalidOperationException("Native shadow death-link script changed.");
                output[Gates[i] + 3] = 0;
            }
            // The physical attack branches also call 57F6/5804/5812: $2E
            // tests physical player E191 bit80. Null the tested mask, not the
            // death animation or the shadow's own HP-zero handling at A6FC.
            for (int i = 0; i < StatusGates.Length; i++)
            {
                byte[] expected = { 0x2E, (byte)i, 0x11, 0x80, 0x88, 0xDC, 0x80, 0x11, 0x80, 0xE3, 0x31, 0, 0xEE, 0 };
                if (!original.Skip(StatusGates[i]).Take(expected.Length).SequenceEqual(expected)
                    || !output.Skip(StatusGates[i]).Take(expected.Length).SequenceEqual(expected))
                    throw new InvalidOperationException("Native shadow status death-link script changed.");
                output[StatusGates[i] + 3] = 0;
            }
            return true;
        }
    }
}
