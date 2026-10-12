using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using SoMRandomizer.config.settings;
using SoMRandomizer.processing;
using SoMRandomizer.processing.common;
using SoMRandomizer.processing.hacks.openworld;
using SoMRandomizer.processing.openworld;
using SoMRandomizer.processing.openworld.randomization;

// In-memory normal generation capture. Removes only unrelated local experimental
// Weapon Power from the test instance, never from production source/registration.
public class SpellShuffleTestGenerator : OpenWorldGenerator
{
    public RandoContext LastContext;
    public SpellShuffleTestGenerator() : this(false) { }
    public SpellShuffleTestGenerator(bool omitShuffleProcessors)
    {
        var common=(List<RandoProcessor>)typeof(RomGenerator).GetField("commonHacks",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(this);
        common.RemoveAll(p=>p.GetType().Name=="WeaponPowerCalculator");
        if(omitShuffleProcessors)
        {
            var modes=(List<RandoProcessor>)typeof(RomGenerator).GetField("modeSpecificHacks",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(this);
            modes.RemoveAll(p=>p is SpellShuffleAssignments || p is SpellShuffle);
        }
    }
    protected override void generate(byte[] original,byte[] output,string seed,RandoSettings settings,RandoContext context)
    { LastContext=context; base.generate(original,output,seed,settings,context); }
    public static string Validate(OpenWorldSettings settings,RandoContext context)
    {
        if(context.workingData.hasSetting(SpellShuffle.TABLE_OFFSET))
        {
            byte[] rom=context.outputRom;
            var hooks=new Dictionary<int,string> {
                {0x10CEB2,SpellShuffle.SELECT_ROUTINE}, {0x10D074,SpellShuffle.ICON_ROUTINE},
                {0x10D080,SpellShuffle.ICON_ROUTINE}, {0x10D089,SpellShuffle.METADATA_ROUTINE},
                {0x3FAA,SpellShuffle.CAPTURE_ROUTINE}, {0xBC14,SpellShuffle.CLEAR_ROUTINE},
                {0x8E8A0,SpellShuffle.AFFINITY_ROUTINE} };
            foreach(var hook in hooks)
                if(rom[hook.Key]!=0x22 || (rom[hook.Key+1]|rom[hook.Key+2]<<8|rom[hook.Key+3]<<16)!=context.workingData.getInt(hook.Value))
                    throw new Exception("Final-ROM hook overwritten: "+hook.Key.ToString("X6"));
            if(!rom.Skip(0x8E77E).Take(5).SequenceEqual(context.originalRom.Skip(0x8E77E).Take(5)))
                throw new Exception("Obsolete damage-target capture hook remains.");
            if(rom[0x1E8F7]!=0x5C) throw new Exception("Final-ROM non-text event dispatch missing.");
            int eventTable=(rom[0x1E7A3]|rom[0x1E7A4]<<8|rom[0x1E7A5]<<16)-0xC00000;
            for(int id=0x350;id<=0x357;id++)
            {
                int pointer=eventTable+id*3;
                int at=(rom[pointer]|rom[pointer+1]<<8|rom[pointer+2]<<16)-0xC00000;
                if(!rom.Skip(at).Take(context.replacementEvents[id].Count).SequenceEqual(context.replacementEvents[id]))
                    throw new Exception("Final-ROM checker event data overwritten.");
            }
            int table=context.workingData.getInt(SpellShuffle.TABLE_OFFSET);
            for(int slot=0;slot<3;slot++)
            {
                int[] row=SpellShuffleAssignments.getRow(context,slot);
                if(row==null) continue;
                string role=context.workingData.get(new[] {"boyClass","girlClass","spriteClass"}[slot]);
                foreach(int dest in SpellShuffleAssignments.getRoleSpellIds(role))
                    if(rom[table+slot*64+dest]!=row[dest]) throw new Exception("Final-ROM assignment table overwritten.");
            }
        }
        var elements=ElementSwaps.getCrystalOrbElementMap(context);
        if(SpellShuffleAssignments.hasAssignments(context) && !CrystalOrbRequirements.isWeaponOnly(settings))
        {
            var valid=SpellShuffleAssignments.getValidOrbElements(context);
            bool caster=Enumerable.Range(0,3).Any(i=>SpellShuffleAssignments.getRow(context,i)!=null);
            if(caster && elements.Values.Any(f=>f!=255 && !valid.Contains(f))) throw new Exception("Uncastable generated Orb.");
        }
        // The final-game unlock must grant the reserved third Dryad slot to
        // EVERY physical caster, including duplicate Girl/Sprite roles.
        if(context.replacementEvents.ContainsKey(0x42D))
        {
            var unlock=context.replacementEvents[0x42D];
            for(int slot=0;slot<3;slot++)
            {
                string role=context.workingData.get(new[] {"boyClass","girlClass","spriteClass"}[slot]);
                if(role=="OGboy") continue;
                byte mask=(byte)(role=="OGgirl"?0x38:0x07);
                byte[] grant={0x39,(byte)(slot+1),0xCD,mask};
                if(!Enumerable.Range(0,Math.Max(0,unlock.Count-3)).Any(i=>unlock.Skip(i).Take(4).SequenceEqual(grant)))
                    throw new Exception("Mana Magic unlock lost physical caster "+slot);
                int[] row=SpellShuffleAssignments.getRow(context,slot);
                if(row!=null && (row[0x20]!=0x20 || row[0x23]!=0x23)) throw new Exception("Reserved Mana Magic moved.");
            }
        }
        foreach(var requirement in CrystalOrbRequirements.getResolvedRequirements(context).Values)
            if(requirement.Type==CrystalOrbRequirementType.Magic && SpellShuffleAssignments.hasAssignments(context) &&
                SpellShuffleAssignments.getOrbCasters(context,requirement.Value).Count==0) throw new Exception("Impossible Mixed Magic requirement.");
        var grand=new List<string>(); var fortress=new List<string>();
        OpenWorldLocations.populateDependencies(settings,context,grand,fortress);
        if(SpellShuffleAssignments.hasAssignments(context) && !CrystalOrbRequirements.isEnabled(settings) &&
            Enumerable.Range(0,3).Any(i=>SpellShuffleAssignments.getRow(context,i)!=null))
            foreach(int map in Enumerable.Range(420,7))
                if(elements[map]!=255 && !grand.Contains(SomVanillaValues.elementOrbByteToName(elements[map],false)+" spells"))
                    throw new Exception("Missing Grand Palace gate in simulation.");
        return string.Join(" | ",Enumerable.Range(0,3).Where(i=>SpellShuffleAssignments.getRow(context,i)!=null)
            .Select(i=>new[] {"boy","girl","sprite"}[i]+":"+string.Join(",",SpellShuffleAssignments.getRow(context,i))));
    }
}
