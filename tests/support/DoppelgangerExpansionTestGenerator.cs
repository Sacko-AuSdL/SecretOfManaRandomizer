using System;
using System.Collections.Generic;
using System.Reflection;
using SoMRandomizer.config.settings;
using SoMRandomizer.processing;
using SoMRandomizer.processing.common;
using SoMRandomizer.processing.openworld;

// Test assembly ONLY. No production test flags or boss rolls.
public sealed class DoppelgangerExpansionTestGenerator : OpenWorldGenerator
{
    public bool ManualSupplies;
    // Explicit opt-in for the one fast Pure Lands acceptance ROM. Ordinary
    // generation, including the other manual profiles, has no Sword teleport.
    public bool PureLandsShortcut;
    public RandoContext LastContext;
    public DoppelgangerExpansionTestGenerator()
    {
        var common = (List<RandoProcessor>)typeof(RomGenerator).GetField("commonHacks", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(this);
        common.RemoveAll(p => p.GetType().Name == "WeaponPowerCalculator");
    }
    protected override void generate(byte[] original, byte[] output, string seed, RandoSettings settings, RandoContext context)
    {
        base.generate(original, output, seed, settings, context);
        if (PureLandsShortcut && (!ManualSupplies || context.doppelgangerExpansion == null
            || context.doppelgangerExpansion.ForeignSlot != VanillaBossMaps.DRAGONWORM))
            throw new InvalidOperationException("Pure Lands shortcut requires the Dragon Worm shadow binding and manual supplies.");
        if (ManualSupplies)
        {
            var sword = context.replacementEvents[0x103];
            DoppelgangerManualProfile.AddSupplies(sword, false);
            // Remove the historical harness's LAST Door08D, retaining its valid
            // equipment/MP/healing supplies. Reach the actual randomized rooms.
            if (sword[sword.Count - 3] != 0x18 || sword[sword.Count - 2] != 0x8D)
                throw new InvalidOperationException("Manual supply helper changed its tail.");
            sword.RemoveRange(sword.Count - 3, 2);
            if (PureLandsShortcut)
            {
                // Use the actual redirected Dragon Worm entrance, NOT a
                // separate arena/return contract. Explicitly run its guarded
                // entry: door walk-ons are suppressed while event103 is busy.
                sword.InsertRange(sword.Count - 1, new byte[] { 0x42, 0x46, 0x1F, 0x10, 0, 0x1B, 0x75, 0x16, 0xD5 });
            }
            DoppelgangerManualProfile.ApplyEquipment(output);
        }
        LastContext = context;
    }
}
