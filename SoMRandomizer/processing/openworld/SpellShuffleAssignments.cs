using SoMRandomizer.config.settings;
using SoMRandomizer.logging;
using SoMRandomizer.processing.common;
using SoMRandomizer.processing.hacks.openworld;
using SoMRandomizer.processing.hacks.common.util;
using System;
using System.Collections.Generic;
using System.Linq;

namespace SoMRandomizer.processing.openworld
{
    /// <summary>
    /// Seed-owned assignments, resolved after existence/roles and before Orb/placement rolls.
    /// A row is indexed by the vanilla spell ID of the destination slot, NOT by effect element.
    /// Per Character rows are permutations; Party rows may contain repeated actual IDs.
    /// Both keep physical destination slots and their spirit unlock/level semantics.
    /// </summary>
    public sealed class SpellShuffleAssignments : RandoProcessor
    {
        public const string RESOLVED = "spellShuffleResolved";
        public const string ROW_PREFIX = "spellShuffleCharacter";
        public const string OWNED_SPIRIT_PREFIX = "ownedSpirit:";
        private const string COMPATIBLE = "spellShuffleOrbCompatible";
        public const int SPELL_COUNT = 42;
        public const int TABLE_STRIDE = 64;
        private static readonly string[] Slots = { "boy", "girl", "sprite" };
        // Native learned-byte order, distinct from Orb color/checker ordering.
        private static readonly byte[] Families = { 0x81, 0x82, 0x83, 0x85, 0x87, 0x88, 0x86, 0x84 };

        public static bool isEnabled(RandoSettings settings)
        {
            return settings.get(CommonSettings.PROPERTYNAME_MODE) == OpenWorldSettings.MODE_KEY &&
                (settings.get(OpenWorldSettings.PROPERTYNAME_SPELL_SHUFFLE) ==
                    OpenWorldSettings.PROPERTYVALUE_SPELL_SHUFFLE_PER_CHARACTER || isParty(settings));
        }

        public static bool isParty(RandoSettings settings)
        { return settings.get(OpenWorldSettings.PROPERTYNAME_SPELL_SHUFFLE) == OpenWorldSettings.PROPERTYVALUE_SPELL_SHUFFLE_PARTY; }

        public static bool hasAssignments(RandoContext context)
        {
            return context.workingData.hasSetting(RESOLVED) && context.workingData.getInt(RESOLVED) == 1;
        }

        protected override string getName() { return "Seeded spell assignments"; }
        protected override bool process(byte[] origRom, byte[] outRom, string seed, RandoSettings settings, RandoContext context)
        {
            if (!isEnabled(settings)) return false; // no cache, writes, allocations, or RNG when Off
            resolveAndStore(settings, context, outRom);
            return true;
        }

        public static void resolveAndStore(RandoSettings settings, RandoContext context, byte[] rom)
        {
            if (!isEnabled(settings) || hasAssignments(context)) return;
            // D0:DA75 chooses enemy records from bit 7. D0:DB32 explicitly admits species $55.
            // C0:3FAA notifies special targets before spell effects; damage is not required.
            // Ally-only spells and the pinned Mana Magic entries cannot select an Orb.
            context.workingData.setIntArray(COMPATIBLE, Enumerable.Range(0, SPELL_COUNT)
                .Where(id => (rom[0x102AD8 + id * 0x40] & 0x80) != 0).ToArray());
            if (isParty(settings)) resolveParty(context);
            else for (int slot = 0; slot < 3; slot++)
            {
                if (!context.workingData.getBool(Slots[slot] + "Exists")) continue;
                string role = context.workingData.get(Slots[slot] + "Class");
                int[] pool = getRoleSpellIds(role);
                if (pool.Length == 0) continue;
                int pinned = role == "OGgirl" ? 0x23 : 0x20;
                int[] destinations = pool.Where(id => id != pinned).ToArray();
                int[] shuffled = (int[])destinations.Clone();
                for (int i = shuffled.Length - 1; i > 0; i--)
                {
                    int j = context.randomFunctional.Next() % (i + 1);
                    int temp = shuffled[i]; shuffled[i] = shuffled[j]; shuffled[j] = temp;
                }
                int[] row = Enumerable.Range(0, SPELL_COUNT).ToArray();
                for (int i = 0; i < destinations.Length; i++) row[destinations[i]] = shuffled[i];
                context.workingData.setIntArray(ROW_PREFIX + slot, row);
            }
            context.workingData.setInt(RESOLVED, 1);
            Logging.log("Spell Shuffle: " + (isParty(settings) ? "Party Shuffle" : "Per Character") + " (Mana Magic pinned)", "spoiler");
            for (int slot = 0; slot < 3; slot++)
            {
                int[] row = getRow(context, slot);
                if (row == null) continue;
                string role = context.workingData.get(Slots[slot] + "Class");
                foreach (var group in getRoleSpellIds(role).GroupBy(getSpiritIndex))
                {
                    string family = SomVanillaValues.elementOrbByteToName(Families[group.Key], true);
                    string names = string.Join(", ", group.Select(id => context.namesOfThings == null
                        ? row[id].ToString("X2") : context.namesOfThings.getOriginalName(
                        NamesOfThings.INDEX_SPELLS_START + row[id])));
                    Logging.log("  " + Slots[slot] + " (" + role + ") / " + family + ": " + names, "spoiler");
                }
            }
        }

        private static void resolveParty(RandoContext context)
        {
            var positions = new List<KeyValuePair<int,int>>();
            var pool = new List<int>();
            for(int slot=0;slot<3;slot++)
            {
                if(!context.workingData.getBool(Slots[slot]+"Exists")) continue;
                int[] ids=getShuffleableSpellIds(context.workingData.get(Slots[slot]+"Class"));
                if(ids.Length==0) continue;
                context.workingData.setIntArray(ROW_PREFIX+slot,Enumerable.Range(0,SPELL_COUNT).ToArray());
                foreach(int id in ids) { positions.Add(new KeyValuePair<int,int>(slot,id)); pool.Add(id); }
            }
            // A single Fisher-Yates permutation of INSTANCES, not distinct spell IDs.
            // Equal IDs may land together, even three times within one spirit menu.
            for(int i=pool.Count-1;i>0;i--)
            {
                int j=context.randomFunctional.Next()%(i+1);
                int temp=pool[i]; pool[i]=pool[j]; pool[j]=temp;
            }
            int[][] rows=Enumerable.Range(0,3).Select(slot=>getRow(context,slot)).ToArray();
            for(int i=0;i<positions.Count;i++) rows[positions[i].Key][positions[i].Value]=pool[i];
            for(int slot=0;slot<3;slot++) if(rows[slot]!=null) context.workingData.setIntArray(ROW_PREFIX+slot,rows[slot]);
        }

        public static int[] getRow(RandoContext context, int slot)
        {
            string key = ROW_PREFIX + slot;
            return context.workingData.hasSetting(key) ? context.workingData.getIntArray(key) : null;
        }
        public static int[] getRoleSpellIds(string role)
        {
            if (role == "OGgirl") return Enumerable.Range(0, 6).SelectMany(i => new[] { i * 6 + 3, i * 6 + 4, i * 6 + 5 })
                .Concat(new[] { 39, 40, 41 }).ToArray();
            if (role == "OGsprite") return Enumerable.Range(0, 6).SelectMany(i => new[] { i * 6, i * 6 + 1, i * 6 + 2 })
                .Concat(new[] { 36, 37, 38 }).ToArray();
            return new int[0];
        }
        public static int getSpiritIndex(int destinationId)
        {
            return destinationId >= 39 ? 7 : destinationId / 6;
        }
        public static byte getSpiritFamily(int destinationId) { return Families[getSpiritIndex(destinationId)]; }
        public static byte getSpiritFamilyByIndex(int spiritIndex) { return Families[spiritIndex]; }
        public static int[] getShuffleableSpellIds(string role)
        { return getRoleSpellIds(role).Where(id=>id!=0x20 && id!=0x23).ToArray(); }
        public static int getLearnedMask(int destinationId) { return 1 << (destinationId % 6); }

        public static List<string> getOrbCasters(RandoContext context, byte family)
        {
            var result = new List<string>();
            if (!hasAssignments(context)) return result;
            var compatible = new HashSet<int>(context.workingData.getIntArray(COMPATIBLE));
            for (int slot = 0; slot < 3; slot++)
            {
                int[] row = getRow(context, slot);
                if (row == null) continue;
                string role = context.workingData.get(Slots[slot] + "Class");
                // Mana Magic is excluded both by targeting and by its late unlock.
                if (getRoleSpellIds(role).Any(id => id != 0x20 && id != 0x23 &&
                    getSpiritFamily(id) == family && compatible.Contains(row[id]))) result.Add(Slots[slot]);
            }
            return result;
        }
        public static List<byte> getValidOrbElements(RandoContext context)
        {
            return Enumerable.Range(0x81, 8).Select(v => (byte)v)
                .Where(family => getOrbCasters(context, family).Count != 0).ToList();
        }
        public static byte getDependencyFamily(string dependency)
        {
            if (!dependency.EndsWith(" spells", StringComparison.Ordinal)) return 0;
            return SomVanillaValues.elementOrbNameToByte(dependency.Substring(0, dependency.Length - 7));
        }
    }
}
