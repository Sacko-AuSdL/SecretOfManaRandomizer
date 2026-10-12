using SoMRandomizer.config.settings;
using SoMRandomizer.logging;
using SoMRandomizer.processing.common;
using SoMRandomizer.processing.common.structure;
using SoMRandomizer.processing.openworld;
using SoMRandomizer.util;
using System;
using System.Collections.Generic;
using System.Linq;

namespace SoMRandomizer.processing.hacks.openworld
{
    /// <summary>
    /// Player-menu ID remapping, installed AFTER CharacterClasses. All enemy/effect tables stay
    /// native. A confirmed special-target hit snapshots its source family: Per Character
    /// uses the unique inverse; Party uses the caster's queued spirit and learned membership.
    /// Neither uses another player's menu or a mutable spell-power field. HP-damage
    /// affinity independently reads the executing caster's queued destination spirit.
    /// </summary>
    public sealed class SpellShuffle : RandoProcessor
    {
        public const string TABLE_OFFSET = "spellShuffleTableOffset";
        public const string INVERSE_OFFSET = "spellShuffleInverseOffset";
        public const string SELECT_ROUTINE = "spellShuffleSelectRoutine";
        public const string ICON_ROUTINE = "spellShuffleIconRoutine";
        public const string METADATA_ROUTINE = "spellShuffleMetadataRoutine";
        public const string CAPTURE_ROUTINE = "spellShuffleCaptureRoutine";
        public const string CLEAR_ROUTINE = "spellShuffleClearRoutine";
        public const string CHECKER_PREFIX = "spellShuffleCheckerRoutine";
        public const string PARTY_MASK_OFFSET = "spellShufflePartyMaskOffset";
        public const string AFFINITY_ROUTINE = "spellShuffleAffinityRoutine";
        private const int ContextBase = CustomRamOffsets.SPELL_SHUFFLE_ORB_CONTEXT;
        private static readonly byte[] CheckerFamilies = { 0x81, 0x82, 0x85, 0x83, 0x84, 0x86, 0x87, 0x88 };

        protected override string getName() { return "Spell shuffle runtime"; }
        protected override bool process(byte[] origRom, byte[] outRom, string seed, RandoSettings settings, RandoContext context)
        {
            if(!SpellShuffleAssignments.isEnabled(settings) || !SpellShuffleAssignments.hasAssignments(context)) return false;
            if(!Enumerable.Range(0,3).Any(slot => SpellShuffleAssignments.getRow(context,slot) != null)) return false;
            // These sites are deliberately downstream of CharacterClasses' arithmetic/role hooks.
            Require(outRom,0x10CEB2,0x8D,0x39,0x18,0x8D,0xF1,0x19);
            Require(outRom,0x10D074,0xBF,0x00,0x00,0xD8);
            Require(outRom,0x10D080,0xBF,0x00,0x00,0xD8);
            Require(outRom,0x10D089,0xAD,0x4F,0x18,0x22,0xBF,0xCE,0xD0);
            Require(outRom,0x3FAA,0xBD,0x70,0xE1,0x99,0x81,0xE1);
            Require(outRom,0xBC14,0x22,0x5C,0xAA,0x02);
            Require(outRom,0x8E8A0,0xA0,0xDC,0x2A,0xB7,0xDC,0xA4,0x83);
            CodeGenerationUtils.ensureSpaceInBank(ref context.workingOffset, 8192);
            int table = context.workingOffset;
            byte[] mapped = Enumerable.Range(0,192).Select(i => (byte)(i % 64)).ToArray();
            byte[] inverse = new byte[192], indices = new byte[192], masks = new byte[192];
            for(int slot=0; slot<3; slot++)
            {
                int[] row = SpellShuffleAssignments.getRow(context,slot);
                if(row == null) continue;
                string role = context.workingData.get(new[] {"boyClass","girlClass","spriteClass"}[slot]);
                foreach(int dest in SpellShuffleAssignments.getRoleSpellIds(role))
                {
                    mapped[slot*64+dest]=(byte)row[dest];
                    int actual=row[dest], at=slot*64+actual;
                    if(actual == 0x20 || actual == 0x23 || (outRom[0x102AD8+actual*64]&0x80)==0) continue;
                    inverse[at]=SpellShuffleAssignments.getSpiritFamily(dest);
                    indices[at]=(byte)SpellShuffleAssignments.getSpiritIndex(dest);
                    masks[at]=(byte)SpellShuffleAssignments.getLearnedMask(dest);
                }
            }
            foreach(byte[] data in new[] {mapped,inverse,indices,masks})
            {
                Array.Copy(data,0,outRom,context.workingOffset,data.Length);
                context.workingOffset+=data.Length;
            }
            context.workingData.setInt(TABLE_OFFSET,table);
            context.workingData.setInt(INVERSE_OFFSET,table+192);

            int partyMasks=0;
            if(SpellShuffleAssignments.isParty(settings))
            {
                // (physical caster * 64 + actual ID) * 8 + queued destination spirit.
                // OR the learned-position bits, not a single inverse ID: repeated
                // spells within/across spirits must not overwrite each other's source.
                partyMasks=context.workingOffset;
                byte[] membership=new byte[3*64*8];
                for(int slot=0;slot<3;slot++)
                {
                    int[] row=SpellShuffleAssignments.getRow(context,slot);
                    if(row==null) continue;
                    string role=context.workingData.get(new[] {"boyClass","girlClass","spriteClass"}[slot]);
                    foreach(int dest in SpellShuffleAssignments.getShuffleableSpellIds(role))
                    {
                        int actual=row[dest];
                        if((outRom[0x102AD8+actual*64]&0x80)==0) continue;
                        membership[(slot*64+actual)*8+SpellShuffleAssignments.getSpiritIndex(dest)] |=
                            (byte)SpellShuffleAssignments.getLearnedMask(dest);
                    }
                }
                Array.Copy(membership,0,outRom,context.workingOffset,membership.Length);
                context.workingOffset+=membership.Length;
                foreach(int spirit in Enumerable.Range(0,8))
                    outRom[context.workingOffset++]=SpellShuffleAssignments.getSpiritFamilyByIndex(spirit);
                context.workingData.setInt(PARTY_MASK_OFFSET,partyMasks);
            }

            // Damage has no dependency on the target-bound, consumed Orb context.
            // Both modes validate the executing caster's queued $E177 spirit against
            // the ROM assignment and its learned-position mask. No new WRAM state.
            int affinityMasks=partyMasks;
            if(affinityMasks==0)
            {
                affinityMasks=context.workingOffset;
                byte[] membership=new byte[3*64*8];
                for(int slot=0;slot<3;slot++)
                {
                    int[] row=SpellShuffleAssignments.getRow(context,slot);
                    if(row==null) continue;
                    string role=context.workingData.get(new[] {"boyClass","girlClass","spriteClass"}[slot]);
                    foreach(int dest in SpellShuffleAssignments.getShuffleableSpellIds(role))
                        membership[(slot*64+row[dest])*8+SpellShuffleAssignments.getSpiritIndex(dest)] |=
                            (byte)SpellShuffleAssignments.getLearnedMask(dest);
                }
                Array.Copy(membership,0,outRom,context.workingOffset,membership.Length);
                context.workingOffset+=membership.Length;
                foreach(int spirit in Enumerable.Range(0,8))
                    outRom[context.workingOffset++]=SpellShuffleAssignments.getSpiritFamilyByIndex(spirit);
            }
            int damageIds=context.workingOffset;
            // Native HP handlers: EA8B, EB39 (damage+slow), EB54 (HP absorb),
            // EBCA (damage+confuse), EBE5 (damage+status). Status-only EA97/EBF4,
            // MP absorb EC3B, random Lunar Magic EEF5 and percentage Evil Gate
            // ED82 retain their native special mechanics. Mana Magic never enters.
            var hpSpells=new HashSet<int> {0,1,6,7,8,12,13,14,16,17,18,19,31,37,40};
            for(int id=0;id<42;id++) outRom[context.workingOffset++]=(byte)(hpSpells.Contains(id)?1:0);
            int affinityBits=context.workingOffset;
            // Orb-family order $81-$88 is NOT the native damage-bit order.
            foreach(byte bit in new byte[] {1,4,8,32,2,16,64,128}) outRom[context.workingOffset++]=bit;
            int damageLookup=Emit(context,outRom,w => EmitPartyActorLookup(w,affinityMasks));
            int affinity=Emit(context,outRom,w =>
            {
                // $C8:E8A0: A8/X16, DB=$7E, DP=$0300, X=target; $83=caster.
                // Replay native metadata read and caster restoration first. Replace
                // only A's low affinity byte; preserve B/X/P/DB/DP and native Y/NZ.
                w.B(0xA0,0xDC,0x2A,0xB7,0xDC,0xA4,0x83,0x08,0xC2,0x30,0x48,0xDA);
                w.B(0xB9,0x70,0xE1); w.W(0x29,0xFF); w.W(0xC9,42); w.If(0xB0,"native");
                w.B(0xAA); w.L(0xBF,damageIds+0xC00000); w.W(0x29,0xFF); w.If(0xF0,"native");
                w.B(0xB9,0x70,0xE1); w.L(0x22,damageLookup); w.W(0x29,0xFF); w.If(0xF0,"native");
                w.B(0x38); w.W(0xE9,0x81); w.B(0xAA); w.L(0xBF,affinityBits+0xC00000);
                w.B(0xE2,0x20,0x83,0x03); // replace only saved A.low, not its native B
                w.Label("native"); w.B(0xC2,0x30,0xFA,0x68,0x28,0xA4,0x83,0x6B);
            });
            Hook(outRom,0x8E8A0,7,affinity);
            context.workingData.setInt(AFFINITY_ROUTINE,affinity);

            int lookup = Emit(context,outRom,w =>
            {
                // A: native spell ID, $1808: physical menu owner. Preserve index registers/P.
                w.B(0x08,0xC2,0x30,0x29,0xFF,0x00,0x48,0xDA);
                w.L(0xAF,0x7E1808); w.W(0x29,0x00FF); w.W(0xC9,3); w.If(0xB0,"identity");
                for(int i=0;i<6;i++) w.B(0x0A);
                w.B(0x18,0x63,0x03,0xAA); // ADC native ID saved beneath PHX
                w.L(0xBF,table+0xC00000); w.W(0x29,0xFF); w.B(0x83,0x03);
                w.Label("identity"); w.B(0xFA,0x68,0x28,0x6B);
            });
            int select = Emit(context,outRom,w =>
            {
                w.L(0x22,lookup); // native CEB2 entry A8/X16; preserve X spirit index
                w.B(0x8D,0x39,0x18,0x8D,0xF1,0x19,0x6B);
            });
            int icon = Emit(context,outRom,w =>
            {
                // $184F is the native destination ID, incremented even for unlearned entries.
                w.B(0x08,0xC2,0x30,0xDA); w.L(0xAF,0x7E184F);
                w.W(0x29,0xFF); w.L(0x22,lookup); w.W(0x29,0xFF); w.B(0x0A,0xAA);
                w.L(0xBF,0xD8FD7E); w.B(0xFA,0x28,0x6B);
            });
            int metadata = Emit(context,outRom,w =>
            {
                w.B(0xAD,0x4F,0x18); w.L(0x22,lookup); w.L(0x22,0xD0CEBF); w.B(0x6B);
            });
            // Actor inverse lookup: A actual ID, Y caster offset, X preserved. A zero result
            // rejects enemy/script/reflected casts without a legitimately learned player slot.
            int actorLookup = partyMasks!=0 ? Emit(context,outRom,w => EmitPartyActorLookup(w,partyMasks)) : Emit(context,outRom,w =>
            {
                w.B(0x08,0xC2,0x30); w.W(0x29,0xFF); w.B(0x48,0xDA);
                w.W(0xC9,42); w.If(0xB0,"invalid");
                w.B(0x98); w.W(0xC9,0x600); w.If(0xB0,"invalid");
                w.W(0x29,0x1FF); w.If(0xD0,"invalid");
                w.B(0x98,0x4A,0x4A,0x4A,0x18,0x63,0x03,0xAA);
                w.L(0xBF,table+576+0xC00000); w.W(0x29,0xFF); w.B(0x83,0x03); // learned mask
                w.L(0xBF,table+384+0xC00000); w.W(0x29,0xFF); w.B(0xDA,0x48);
                w.B(0x98,0x18,0x63,0x01,0xAA,0x68);
                w.L(0xBF,0x7EE1C8); w.B(0x23,0x05); w.If(0xF0,"unlearned");
                w.B(0xFA); w.L(0xBF,table+192+0xC00000); w.W(0x29,0xFF); w.Jump("result");
                w.Label("unlearned"); w.B(0xFA);
                w.Label("invalid"); w.W(0xA9,0);
                w.Label("result"); w.B(0x83,0x03,0xFA,0x68,0x28,0x6B);
            });
            int capture = Emit(context,outRom,w => EmitCapture(w,actorLookup));
            int clear = Emit(context,outRom,w =>
            {
                w.B(0x08,0xC2,0x30,0x48,0xDA); w.W(0xA2,95); w.B(0xE2,0x20,0xA9,0);
                w.Label("loop"); w.L(0x9F,ContextBase); w.B(0xCA); w.If(0x10,"loop");
                w.B(0xC2,0x30,0xFA,0x68,0x28); w.L(0x22,0x02AA5C); w.B(0x6B);
            });
            for(int i=0;i<8;i++)
            {
                byte family=CheckerFamilies[i], flag=(byte)(0x98+i);
                int check = Emit(context,outRom,w => EmitChecker(w,family,flag));
                int command=context.eventHackMgr.registerNewEvent("spell shuffle Orb "+family.ToString("X2"),check-0xC00000,false);
                var ev = new EventScript();
                ev.Add(EventCommandEnum.CHARACTER_ANIM.Value,0x04,0x80);
                ev.Add(EventCommandEnum.WAIT_FOR_ANIM.Value);
                ev.Add(EventCommandEnum.CUSTOM_EVENT_COMMANDS.Value,(byte)command);
                ev.Return(); ev.End();
                context.replacementEvents[0x350+i]=ev;
                context.workingData.setInt(CHECKER_PREFIX+family,check);
            }
            Hook(outRom,0x10CEB2,6,select); Hook(outRom,0x10D074,4,icon); Hook(outRom,0x10D080,4,icon);
            Hook(outRom,0x10D089,7,metadata); Hook(outRom,0x3FAA,6,capture); Hook(outRom,0xBC14,4,clear);
            context.workingData.setInt(SELECT_ROUTINE,select); context.workingData.setInt(ICON_ROUTINE,icon);
            context.workingData.setInt(METADATA_ROUTINE,metadata); context.workingData.setInt(CAPTURE_ROUTINE,capture);
            context.workingData.setInt(CLEAR_ROUTINE,clear);
            // InitialValues runs among common hacks, before this processor. Initialization
            // therefore belongs to the map-load hook, including the first startup map and
            // save/load restoration, rather than late additions to initialValues.
            Logging.log("Spell Shuffle hooks: $D0:CEB2, $D0:D074/D080/D089, $C0:3FAA, $C0:BC14, $C8:E8A0 (player HP affinity); tables ROM $"+table.ToString("X6"));
            return true;
        }

        private static void EmitPartyActorLookup(Writer w,int masks)
        {
            // Native C0:731F stores destination spirit $1846 in queue byte +7.
            // The executing physical caster owns this source in $E177; native
            // C1:8748 uses it for the summon, and D0:4E82 uses it for level/EXP.
            // It is NOT $E171 (mutable spell power), nor the global last menu.
            // Party Orb capture and both modes' damage-affinity lookup use this.
            // The contract is DB=$7E, A8 or A16/X16, Y=caster, X/Y/P preserved.
            w.B(0x08,0xC2,0x30); w.W(0x29,0xFF); w.B(0x48,0xDA,0x5A);
            w.W(0xC9,42); w.If(0xB0,"invalid");
            w.B(0x98); w.W(0xC9,0x600); w.If(0xB0,"invalid");
            w.W(0x29,0x1FF); w.If(0xD0,"invalid");
            w.B(0x98,0x4A,0x4A,0x4A,0x18,0x63,0x05,0x0A,0x0A,0x0A,0xAA);
            w.B(0xB9,0x77,0xE1); w.W(0x29,0xFF); w.W(0xC9,8); w.If(0xB0,"invalid");
            w.B(0x48,0x8A,0x18,0x63,0x01,0xAA); // membership index + saved spirit
            w.L(0xBF,masks+0xC00000); w.W(0x29,0xFF); w.If(0xF0,"invalidSpirit");
            w.B(0x83,0x07); // replace saved actual ID with learned-position mask
            w.B(0x98,0x18,0x63,0x01,0xAA); w.L(0xBF,0x7EE1C8);
            w.B(0x23,0x07); w.If(0xF0,"invalidSpirit");
            w.B(0x68,0xAA); w.L(0xBF,masks+3*64*8+0xC00000); w.W(0x29,0xFF); w.Jump("result");
            w.Label("invalidSpirit"); w.B(0x68);
            w.Label("invalid"); w.W(0xA9,0);
            w.Label("result"); w.B(0x83,0x05,0x7A,0xFA,0x68,0x28,0x6B);
        }

        private static void EmitCapture(Writer w,int actorLookup)
        {
            // $C0:3FAA: X caster, Y special target, DP=$0300, DB=$7E, after
            // $C0:395E swaps the input actor indices. This path dispatches the
            // object's event at $3FB8 WITHOUT reaching $C8:E77E first.
            w.B(0xBD,0x70,0xE1,0x99,0x81,0xE1); // native real spell-ID write/flags
            w.B(0x08,0xC2,0x30,0x48,0xDA,0x5A);
            w.B(0x8A,0x48,0x98,0xAA,0x68,0xA8); // internal X target, Y caster
            w.B(0x8A); w.W(0xC9,0x600); w.If(0x90,"end"); w.W(0xC9,0x1800); w.If(0xB0,"end");
            w.W(0x29,0x1FF); w.If(0xD0,"end");
            w.B(0xE2,0x20); w.L(0xBF,0x7EE1E7); w.B(0xC9,0x55); w.If(0xD0,"end");
            // $C1:E783 accepts a new event only when $00D0 is 00 or FF. Unlike
            // ordinary actor-event callers ($C0:B695/$C0:BF0F), $C0:3FB8 does
            // NOT install its target in $00D4. Mesen confirmed Y=$0600 but
            // $00D4=$0000 throughout event $239 -> $350 -> custom $57 $03.
            // Bind this validated Orb (not a global last-target fallback) before
            // dispatch, even if its spell later fails the learned-family lookup.
            // Busy notifications must not steal the running event's owner/context.
            w.L(0xAF,0x7E00D0); w.B(0xC9,0); w.If(0xF0,"bindTarget");
            w.B(0xC9,0xFF); w.If(0xD0,"end");
            w.Label("bindTarget"); w.B(0xC2,0x20,0x8A); w.L(0x8F,0x7E00D4);
            // Snapshot before event startup; $00D4 remains the event's actor
            // through its animation/wait and checker subevent. No checker or
            // physical-pass semantics are changed here.
            w.B(0xC2,0x20,0x8A);
            for(int i=0;i<6;i++) w.B(0x4A);
            w.B(0xAA,0xE2,0x20,0xA9,0); w.L(0x9F,ContextBase); // invalidate before overwrite
            w.B(0xB9,0x70,0xE1); w.L(0x9F,ContextBase+2); w.L(0x22,actorLookup);
            w.L(0x9F,ContextBase+1); w.B(0xC9,0); w.If(0xF0,"end");
            w.B(0xC2,0x20,0x98); for(int i=0;i<9;i++) w.B(0x4A);
            w.B(0xE2,0x20); w.L(0x9F,ContextBase+3);
            w.B(0xC2,0x20); w.L(0xAF,0x7E00DC); w.L(0x9F,ContextBase+4);
            w.B(0xE2,0x20,0xA9,1); w.L(0x9F,ContextBase);
            w.Label("end"); w.B(0xC2,0x30,0x7A,0xFA,0x68,0x28,0x6B);
        }

        private static void EmitChecker(Writer w,byte family,byte flag)
        {
            // Custom commands do not promise the incoming DB. Bind actor absolute reads
            // explicitly and restore it on all exits (also useful for machine tests).
            w.B(0x08,0xC2,0x30,0x48,0xDA,0x5A,0x8B,0xE2,0x20,0xA9,0x7E,0x48,0xAB,0xA9,0);
            w.L(0x8F,0x7ECF00+flag); // fail closed, independent of physical-pass state
            w.B(0xC2,0x20); w.L(0xAF,0x7E00D4);
            w.W(0xC9,0x600); w.If(0x90,"end"); w.W(0xC9,0x1800); w.If(0xB0,"end");
            w.W(0x29,0x1FF); w.If(0xD0,"end");
            w.L(0xAF,0x7E00D4); for(int i=0;i<6;i++) w.B(0x4A); w.B(0xAA,0xE2,0x20);
            w.L(0xBF,ContextBase); w.B(0x48,0xA9,0); w.L(0x9F,ContextBase); w.B(0x68,0xC9,1); w.If(0xD0,"end");
            // The marker is consumed before validation on EVERY valid-target exit.
            w.L(0xBF,ContextBase+1); w.B(0xC9,family); w.If(0xD0,"end");
            w.B(0xC2,0x20); w.L(0xBF,ContextBase+4); w.L(0xCF,0x7E00DC); w.If(0xD0,"end");
            w.L(0xAF,0x7E00D4); w.B(0xA8,0xE2,0x20);
            w.B(0xB9,0x00,0xE0); w.If(0xF0,"end"); w.If(0x30,"end");
            w.B(0xB9,0xE7,0xE1,0xC9,0x55); w.If(0xD0,"end");
            w.B(0xB9,0x81,0xE1); w.L(0xDF,ContextBase+2); w.If(0xD0,"end");
            // $E1EC is NOT written by the native special-object notification;
            // the captured player slot was validated at hit time instead.
            w.L(0xBF,ContextBase+3); w.B(0xC9,3); w.If(0xB0,"end");
            w.B(0xA9,1); w.L(0x8F,0x7ECF00+flag);
            w.Label("end"); w.B(0xAB,0xC2,0x30,0x7A,0xFA,0x68,0x28,0x6B);
        }

        private static void Require(byte[] rom,int at,params byte[] bytes)
        {
            if(!rom.Skip(at).Take(bytes.Length).SequenceEqual(bytes))
                throw new InvalidOperationException("Spell Shuffle hook already owned/changed at ROM $"+at.ToString("X6"));
        }
        private static void Hook(byte[] rom,int at,int length,int target)
        {
            rom[at]=0x22; rom[at+1]=(byte)target; rom[at+2]=(byte)(target>>8); rom[at+3]=(byte)(target>>16);
            for(int i=4;i<length;i++) rom[at+i]=0xEA;
        }
        private static int Emit(RandoContext context,byte[] rom,Action<Writer> emit)
        {
            int start=context.workingOffset; var w=new Writer(rom,start); emit(w); w.Finish();
            context.workingOffset=w.Position; return start+0xC00000;
        }
        private sealed class Writer
        {
            private readonly byte[] rom;
            private readonly Dictionary<string,int> labels=new Dictionary<string,int>();
            private readonly List<KeyValuePair<int,string>> branches=new List<KeyValuePair<int,string>>();
            internal int Position;
            internal Writer(byte[] rom,int position) { this.rom=rom; Position=position; }
            internal void B(params byte[] bytes) { foreach(byte b in bytes) rom[Position++]=b; }
            internal void W(byte op,int value) { B(op,(byte)value,(byte)(value>>8)); }
            internal void L(byte op,int value) { B(op,(byte)value,(byte)(value>>8),(byte)(value>>16)); }
            internal void Label(string name) { labels.Add(name,Position); }
            internal void Jump(string name) { B(0x82,0,0); branches.Add(new KeyValuePair<int,string>(Position-2,name)); }
            internal void If(byte opcode,string name) { B((byte)(opcode^0x20),3); Jump(name); }
            internal void Finish()
            {
                foreach(var b in branches) { int delta=labels[b.Value]-b.Key-2; rom[b.Key]=(byte)delta; rom[b.Key+1]=(byte)(delta>>8); }
            }
        }
    }
}
