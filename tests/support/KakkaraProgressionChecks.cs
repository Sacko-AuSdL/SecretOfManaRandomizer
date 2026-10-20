using System;
using System.Collections.Generic;
using System.Linq;
using SoMRandomizer.config.settings;
using SoMRandomizer.processing.common;
using SoMRandomizer.processing.openworld.cannon;
using SoMRandomizer.processing.openworld.randomization;
using SoMRandomizer.processing.openworld;

// Fixtures use real location dependencies and the actual simulator, not a second solver.
public static class KakkaraProgressionChecks
{
    static void Check(bool condition, string message)
    { if(!condition) throw new Exception(message); }

    static RandoContext Copy(RandoContext source)
    {
        var copy = new RandoContext();
        foreach(string key in source.workingData.keysStartingWith(""))
            copy.workingData.set(key, source.workingData.get(key));
        return copy;
    }

    public static void Run(RandoContext generated)
    {
        // Item reachability abstracts winning an ordinary boss, but the actual ROM
        // must still require Sandship victory before granting the captain's prize.
        Check(generated.replacementEvents[0x2A3].Take(5).SequenceEqual(new byte[] {0x42,0x28,0x0E,0x10,0x00}),
            "Generated captain event lost its pre-victory guard.");
        var crew = VanillaMapUtil.getObjects(generated.outputRom,91);
        Check(crew[1].getEvent()==0x2A3 && crew[1].getEventVisFlag()==0x28
            && crew[1].getEventVisMinimum()==15 && crew[1].getEventVisMaximum()==15,
            "Captain actor became available before ship-boss completion.");
        Check(VanillaMapUtil.getTriggers(generated.outputRom,92).Contains(0x28A),
            "Kakkara's on-foot Sandship entrance disappeared.");
        foreach(int map in new[] {328,331,345})
            Check(VanillaMapUtil.getObjects(generated.outputRom,map)[map==345?1:0].getEvent()==
                (map==328?0x68A:map==331?0x678:0x68B), "Generated Fire Palace chest event mismatch.");
        var settings = new OpenWorldSettings(new CommonSettings());
        settings.set("opStartingLocation", "kakkara");
        settings.set("opFlammieDrumInLogic", "yes");
        settings.set("cannonTravelRandomization", "chaos");
        settings.set("crystalOrbWeaponBreaking", "weaponOnly");
        settings.set("opLogic", "restrictive");
        var context = Copy(generated);
        var w = context.workingData;
        w.set("openWorldGoalShortName", "manabeast");
        w.setBool("fastManaFort", false);
        w.setBool("startWithBoy", true);
        w.setBool("startWithGirl", false);
        w.setBool("startWithSprite", false);
        w.setInt("boyStartWeapon", 1); // Sword, deliberately not Whip or Axe.
        w.setInt("cannonTravelResolved", 1);
        w.set("cannonTravelResolvedMode", "chaos");
        foreach(var office in CannonTravelModel.OFFICES)
        {
            w.setInt("cannonTravelRouteCount_" + office.Id, 0);
            w.set("cannonTravelClosedMessage_" + office.Id, CannonTravelModel.CLOSED_OFFICE_MESSAGE);
        }
        // A real two-stage local progression chain, plus the third final Orb.
        w.setInt("crystalOrbRequirementsResolved", 1);
        foreach(int map in new[] {348,345,240}) w.setInt("crystalOrbRequirementType" + map, 1);
        w.setInt("crystalOrbRequirementValue348", 1); // Sword
        w.setInt("crystalOrbRequirementValue345", 4); // Whip
        w.setInt("crystalOrbRequirementValue240", 2); // Axe
        var locations = OpenWorldLocations.getForSelectedOptions(settings, context);
        var names = new[] {"fire palace chest 1", "fire palace chest 2", "fire palace axe orb chest", "fire seed", "sandship captain"};
        var expectedEvents = new[] {0x68A,0x68B,0x678,0x589,0x2A3};
        for(int i=0;i<names.Length;i++)
        {
            var location = locations.Single(l=>l.locationName==names[i]);
            Check(location.eventNum==expectedEvents[i] && location.cannonTravelRegion==CannonTravelRegion.Kakkara,
                "Local event/region mismatch: " + names[i]);
        }
        var first = locations.Single(l=>l.locationName==names[0]);
        var second = locations.Single(l=>l.locationName==names[1]);
        var orbChest = locations.Single(l=>l.locationName==names[2]);
        var seed = locations.Single(l=>l.locationName==names[3]);
        var captain = locations.Single(l=>l.locationName==names[4]);
        Check(first.lockedByPrizes.SequenceEqual(new[] {"sword"}), "First chest lost its own Orb dependency.");
        foreach(var chest in new[] {second,orbChest})
            Check(chest.lockedByPrizes.SequenceEqual(new[] {"sword","whip"}), "Later chest lost its second Orb dependency.");
        Check(new[] {"sword","whip","axe","fire seed"}.All(seed.lockedByPrizes.Contains),
            "Fire Seed omitted a restrictive seed/Orb/traversal dependency.");
        Check(captain.lockedByPrizes.Length==0, "Sandship acquired an invented item/Orb requirement.");
        var placements = new Dictionary<PrizeLocation,PrizeItem>();
        placements[first]=Prize("whip");
        placements[second]=Prize("axe");
        placements[orbChest]=Prize("fire seed");
        placements[seed]=Prize("flammie drum");
        placements[captain]=Prize("earth seed");
        var result = OpenWorldSimulator.runSimulation(placements, settings, context);
        Check(result.score>0, "Valid staged local progression was rejected.");
        Check(result.collectionCycles[0].Contains(first.locationName) && result.collectionCycles[0].Contains(captain.locationName),
            "Starting Sword/local boss check not reachable.");
        Check(!result.collectionCycles[0].Contains(second.locationName) && !result.collectionCycles[0].Contains(orbChest.locationName),
            "Second-Orb chests credited before obtaining Whip.");
        Check(result.collectionCycles[1].Contains(second.locationName) && result.collectionCycles[1].Contains(orbChest.locationName),
            "First chest's Whip did not open later checks in the next cycle.");
        Check(result.collectionCycles[2].Contains(seed.locationName), "Final Orb/seed reward became available at the wrong stage.");
        w.setInt("boyStartWeapon",0); // Glove cannot satisfy the first Sword Orb.
        var blocked = OpenWorldSimulator.runSimulation(placements,settings,context);
        Check(blocked.score<0 && !blocked.collectionCycles[0].Contains(first.locationName), "Blocked first Orb was bypassed.");
        // The captain can supply the missing first weapon after its boss; no Cannon required.
        placements[captain]=Prize("sword");
        var rescued = OpenWorldSimulator.runSimulation(placements,settings,context);
        Check(rescued.score>0 && rescued.collectionCycles[1].Contains(first.locationName), "Captain reward did not unlock the first Orb.");
        settings.set("opLogic","basic");
        var basicSeed=OpenWorldLocations.getForSelectedOptions(settings,context).Single(l=>l.locationName=="fire seed");
        Check(!basicSeed.lockedByPrizes.Contains("fire seed") && basicSeed.lockedByPrizes.Contains("axe"),
            "Basic logic lost physical Orb requirements or retained the restrictive own-seed gate.");
        CheckLuna(generated,settings,context);
    }

    static void CheckLuna(RandoContext generated, OpenWorldSettings settings, RandoContext context)
    {
        // Actual on-foot desert route to Karon ferry, then its existing unconditional
        // ride event. This is not a flight endpoint or a new travel connection.
        foreach(var pair in new[] {new[] {0x23F,69},new[] {0x1E8,94},new[] {0x229,97},
            new[] {0x22E,96},new[] {0x23D,32},new[] {0x278,32},new[] {0x23C,48},new[] {0x236,35}})
            Check(VanillaDoorUtil.getDoor(generated.outputRom,pair[0]).getTargetMap()==pair[1], "Desert/Luna door changed.");
        var ferry=generated.replacementEvents[0x2C1];
        Check(ferry.Take(2).SequenceEqual(new byte[] {0x1A,0x40})
            && ferry.Skip(ferry.Count-3).SequenceEqual(new byte[] {0x1A,0x78,0x00})
            && !ferry.Contains((byte)0x42), "Karon ferry acquired an unmodelled gate.");
        // Physical ferry traversal must not relax the intended progression rule.
        Check(CannonTravelRegions.getLocationRegion("luna item 1 (spells)")==CannonTravelRegion.FlammieOnly
            && CannonTravelRegions.getLocationRegion("luna item 2 (seed)")==CannonTravelRegion.FlammieOnly,
            "Luna rewards lost their intended Flammie requirement.");
        settings.set("opLogic","restrictive");
        var w=context.workingData;
        w.setInt("crystalOrbRequirementType35",1);w.setInt("crystalOrbRequirementValue35",0);
        var all=OpenWorldLocations.getForSelectedOptions(settings,context);
        var moon=all.Where(l=>l.locationName.StartsWith("luna item ")).ToList();
        var captain=all.Single(l=>l.locationName=="sandship captain");
        var prizes=new Dictionary<PrizeLocation,PrizeItem>{{captain,Prize("moon seed")},
            {moon[0],Prize("flammie drum")},{moon[1],Prize("wind seed")}};
        context.randomFunctional=new Random(100);
        context.plandoSettings[PlandoProperties.KEY_LOCATION_LUNA_1]=new List<string>{PlandoProperties.VALUE_PRIZE_FLAMMIE_DRUM};
        var placed=new Dictionary<PrizeLocation,PrizeItem>();
        var pool=new List<PrizeItem>{Prize("flammie drum"),Prize("moon seed"),Prize("wind seed")};
        foreach(string mode in new[] {"off","open","shuffle","chaos"})
        {
            settings.set("cannonTravelRandomization",mode);
            var result=OpenWorldSimulator.runSimulation(prizes,settings,context);
            Check(result.score<0 && !result.collectionCycles.SelectMany(c=>c).Contains(moon[0].locationName),
                "Luna allowed a circular Drum placement: "+mode);
            bool forbidden=false;
            try { forbidden=!OpenWorldLocationPrizeMatcher.placeItems(new List<PrizeLocation>{captain,moon[0],moon[1]},pool,
                settings,context,new Dictionary<PrizeLocation,PrizeItem>()); }
            catch(Exception ex) { if(!ex.Message.Contains("Plando specified impossible settings")) throw; forbidden=true; }
            Check(forbidden,"Luna accepted a plando Drum despite its flight gate: "+mode);
        }
        context.plandoSettings.Clear();
        settings.set("cannonTravelRandomization","chaos");
        prizes[captain]=Prize("flammie drum");prizes[moon[0]]=Prize("moon seed");
        var blocked=OpenWorldSimulator.runSimulation(prizes,settings,context);
        Check(blocked.score<0,"Flight bypassed Luna's restrictive Moon Seed requirement.");
        prizes[moon[0]]=Prize("wind seed");
        settings.set("opLogic","basic");
        var basic=OpenWorldLocations.getForSelectedOptions(settings,context).Where(l=>l.locationName.StartsWith("luna item ")).ToList();
        var basicPrizes=new Dictionary<PrizeLocation,PrizeItem>{{captain,Prize("flammie drum")},
            {basic[0],Prize("wind seed")},{basic[1],Prize("earth seed")}};
        var unlocked=OpenWorldSimulator.runSimulation(basicPrizes,settings,context);
        Check(unlocked.score>0 && !unlocked.collectionCycles[0].Contains(basic[0].locationName)
            && unlocked.collectionCycles[1].Contains(basic[0].locationName),"Local Drum did not unlock Luna in the next sphere.");
        w.setInt("crystalOrbRequirementValue35",1); // Wrong weapon: flight must not bypass the Orb.
        var wrong=OpenWorldLocations.getForSelectedOptions(settings,context).Where(l=>l.locationName.StartsWith("luna item ")).ToList();
        Check(OpenWorldSimulator.runSimulation(new Dictionary<PrizeLocation,PrizeItem>{{captain,Prize("flammie drum")},
            {wrong[0],Prize("wind seed")},{wrong[1],Prize("earth seed")}},settings,context).score<0,"Flight bypassed Luna's Orb.");
        w.setInt("crystalOrbRequirementValue35",0);
        settings.set("opFlammieDrumInLogic","no");
        basicPrizes[captain]=Prize("moon seed");
        var directFlight=OpenWorldSimulator.runSimulation(basicPrizes,settings,context);
        Check(directFlight.score>0 && directFlight.collectionCycles[0].Contains(basic[0].locationName),
            "Drum-out-of-logic no longer grants initial flight.");
        settings.set("opFlammieDrumInLogic","yes");
        settings.set("opStartingLocation","default");settings.set("cannonTravelRandomization","off");
        bool accepted=false;
        try { accepted=OpenWorldLocationPrizeMatcher.placeItems(new List<PrizeLocation>{captain,moon[0],moon[1]},pool,
            settings,context,new Dictionary<PrizeLocation,PrizeItem>()); }
        catch(Exception) { }
        Check(!accepted, "Potos/Off upstream Drum exclusion changed.");
    }

    static PrizeItem Prize(string name) { return new PrizeItem(name,"item",new byte[0],name,0,1); }
}
