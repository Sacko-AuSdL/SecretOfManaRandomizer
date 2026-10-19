using SoMRandomizer.config.settings;
using SoMRandomizer.processing;
using SoMRandomizer.processing.common;
using SoMRandomizer.processing.openworld;
using System.Collections.Generic;
using System.Reflection;

public sealed class DoppelgangerTestGenerator : OpenWorldGenerator
{
    public static RandoContext LastContext;
    public DoppelgangerTestGenerator()
    {
        // Keep the existing local experiment untouched, but out of this test.
        var common = (List<RandoProcessor>)typeof(RomGenerator).GetField("commonHacks",
            BindingFlags.Instance | BindingFlags.NonPublic).GetValue(this);
        common.RemoveAll(p => p.GetType().Name == "WeaponPowerCalculator");
    }
    protected override void generate(byte[] original, byte[] output, string seed,
        RandoSettings settings, RandoContext context)
    {
        base.generate(original, output, seed, settings, context);
        LastContext = context;
    }
}
