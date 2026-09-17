using SoMRandomizer.config.settings;
using SoMRandomizer.logging;
using SoMRandomizer.processing.common;
using SoMRandomizer.processing.common.structure;
using SoMRandomizer.processing.hacks.common.util;
using SoMRandomizer.util;
using System;
using System.Collections.Generic;

namespace SoMRandomizer.processing.hacks.openworld
{
    internal sealed class EnabledCrystalOrbPhysicalRoute
    {
        internal EnabledCrystalOrbPhysicalRoute(CrystalOrbRequirement requirement,
            byte checkerFlag, List<byte> originalEvent)
        {
            Requirement = requirement;
            CheckerFlag = checkerFlag;
            OriginalEvent = originalEvent;
        }

        internal CrystalOrbRequirement Requirement { get; private set; }
        internal byte CheckerFlag { get; private set; }
        internal List<byte> OriginalEvent { get; private set; }
    }

    /// <summary>
    /// Open World Crystal Orb specific-weapon interaction support.
    /// </summary>
    public class CrystalOrbWeaponBreaking : RandoProcessor
    {
        public const string ROUTINE_OFFSET_HIROM = "crystalOrbWeaponBreakingRoutineOffsetHirom";
        public const string RANGED_PROJECTILE_ROUTINE_OFFSET_HIROM = "crystalOrbWeaponBreakingRangedProjectileRoutineOffsetHirom";
        public const string DEFERRED_ROUTINE_OFFSET_HIROM = "crystalOrbWeaponBreakingDeferredRoutineOffsetHirom";
        public const string PHYSICAL_PASS_COMMAND_OFFSET_HIROM = "crystalOrbWeaponBreakingPhysicalPassCommandOffsetHirom";
        internal const string EVENT_COMMAND_NAME_PHYSICAL_PASS = "crystal orb physical pass";

        internal const int ORB_SPECIES = 0x55;
        internal const int DEFERRED_EVENT_HOOK_OFFSET = 0xB6A4;
        internal const int TILE_COLLISION_LOAD_HOOK_OFFSET = 0x1D376;
        internal const int RANGED_PROJECTILE_HOOK_OFFSET = 0x2C529;
        internal const int PHYSICAL_PASS_COMMAND_MAX_LENGTH = 512;
        internal const int DEFERRED_EVENT_ROUTINE_MAX_LENGTH = 512;
        internal const int TILE_COLLISION_FALLBACK_ROUTINE_MAX_LENGTH = 448;
        internal const int RANGED_PROJECTILE_ROUTINE_MAX_LENGTH = 384;
        internal const int PENDING_STATE_NONE = 0;
        internal const int PENDING_STATE_QUEUED = 1;
        internal const int PENDING_STATE_ARMED = 2;
        internal const int PHYSICAL_CHECKER_SUCCESS_VALUE = 2;
        internal const int FIRST_ELEMENT_CHECKER_EVENT = 0x350;
        internal const int LAST_ELEMENT_CHECKER_EVENT = 0x357;
        internal const int FIRST_ELEMENT_CHECKER_FLAG = 0x98;
        internal const int EVENT_FLAGS_RAM_BASE = 0x7ECF00;
        internal const int WEAPON_HORIZONTAL_RADIUS_PIXELS = 40;
        internal const int WEAPON_VERTICAL_RADIUS_PIXELS = 40;
        // $D002/$D004 and $E002/$E004 are map-pixel actor/projectile anchors. Vanilla's ranged
        // overlap path uses a 16-pixel base extent for Bow/Boomerang, so keep this detector to a
        // one-tile rectangle instead of inheriting the deliberately forgiving melee fallback.
        internal const int PROJECTILE_HORIZONTAL_RADIUS_PIXELS = 16;
        internal const int PROJECTILE_VERTICAL_RADIUS_PIXELS = 16;
        internal const int FIRST_NONPLAYER_ACTOR_OFFSET = 0x0600;
        internal const int ACTOR_RECORD_STRIDE = 0x0200;
        internal const int ACTOR_TABLE_END_OFFSET = 0x1800;
        protected override string getName()
        {
            return "Crystal Orb weapon breaking";
        }

        protected override bool process(byte[] origRom, byte[] outRom, string seed, RandoSettings settings, RandoContext context)
        {
            if(!CrystalOrbRequirements.isEnabled(settings))
            {
                return false;
            }

            CrystalOrbRequirements.resolveAndStore(settings, context);
            List<EnabledCrystalOrbPhysicalRoute> enabledRoutes = getEnabledRoutes(origRom, context);
            if(enabledRoutes.Count == 0)
            {
                return false;
            }

            context.initialValues[CustomRamOffsets.CRYSTAL_ORB_PENDING_STATE] = PENDING_STATE_NONE;

            CodeGenerationUtils.ensureSpaceInBank(ref context.workingOffset, PHYSICAL_PASS_COMMAND_MAX_LENGTH);
            int physicalPassCommandOffset = context.workingOffset;
            int physicalPassCommandAddress = physicalPassCommandOffset + 0xC00000;
            emitPhysicalPassEventCommand(outRom, context, enabledRoutes);
            context.workingData.setInt(PHYSICAL_PASS_COMMAND_OFFSET_HIROM, physicalPassCommandAddress);
            int physicalPassCommandIndex = context.eventHackMgr.registerNewEvent(
                EVENT_COMMAND_NAME_PHYSICAL_PASS, physicalPassCommandOffset);
            wrapAuthoritativeOrbEvents(context, enabledRoutes, (byte)physicalPassCommandIndex);

            CodeGenerationUtils.ensureSpaceInBank(ref context.workingOffset, DEFERRED_EVENT_ROUTINE_MAX_LENGTH);
            int deferredRoutineOffset = context.workingOffset;
            int deferredRoutineAddress = deferredRoutineOffset + 0xC00000;
            emitDeferredDispatcher(outRom, context, enabledRoutes);
            context.workingData.setInt(DEFERRED_ROUTINE_OFFSET_HIROM, deferredRoutineAddress);

            List<EnabledCrystalOrbPhysicalRoute> meleeRoutes = new List<EnabledCrystalOrbPhysicalRoute>();
            List<EnabledCrystalOrbPhysicalRoute> rangedRoutes = new List<EnabledCrystalOrbPhysicalRoute>();
            foreach(EnabledCrystalOrbPhysicalRoute enabledRoute in enabledRoutes)
            {
                if(enabledRoute.Requirement.Value >= 5 && enabledRoute.Requirement.Value <= 7)
                {
                    rangedRoutes.Add(enabledRoute);
                }
                else
                {
                    meleeRoutes.Add(enabledRoute);
                }
            }

            CodeGenerationUtils.ensureSpaceInBank(ref context.workingOffset, TILE_COLLISION_FALLBACK_ROUTINE_MAX_LENGTH);
            int proximityRoutineOffset = context.workingOffset;
            int proximityRoutineAddress = proximityRoutineOffset + 0xC00000;
            emitActorCenteredProximityCheck(outRom, context, meleeRoutes);
            context.workingData.setInt(ROUTINE_OFFSET_HIROM, proximityRoutineAddress);

            int rangedRoutineAddress = 0;
            if(rangedRoutes.Count > 0)
            {
                CodeGenerationUtils.ensureSpaceInBank(ref context.workingOffset, RANGED_PROJECTILE_ROUTINE_MAX_LENGTH);
                int rangedRoutineOffset = context.workingOffset;
                rangedRoutineAddress = rangedRoutineOffset + 0xC00000;
                emitRangedProjectileCheck(outRom, context, rangedRoutes);
                context.workingData.setInt(RANGED_PROJECTILE_ROUTINE_OFFSET_HIROM, rangedRoutineAddress);

                // $C2/C529 is shared by Bow, Javelin, and both Boomerang projectile types after
                // $C2/C4C9 has prepared the projectile collision coordinates, but before vanilla
                // branches into type-specific collision handling. X is the owning player and Y is
                // the active $7E:D000 projectile record. Replace SEP #$20; LDA $D000,Y with a JSL
                // and NOP; the generated routine replays both instructions before returning.
                outRom[RANGED_PROJECTILE_HOOK_OFFSET] = 0x22;
                outRom[RANGED_PROJECTILE_HOOK_OFFSET + 1] = (byte)rangedRoutineAddress;
                outRom[RANGED_PROJECTILE_HOOK_OFFSET + 2] = (byte)(rangedRoutineAddress >> 8);
                outRom[RANGED_PROJECTILE_HOOK_OFFSET + 3] = (byte)(rangedRoutineAddress >> 16);
                outRom[RANGED_PROJECTILE_HOOK_OFFSET + 4] = 0xEA;
            }

            outRom[DEFERRED_EVENT_HOOK_OFFSET] = 0x22; // JSL deferred event routine
            outRom[DEFERRED_EVENT_HOOK_OFFSET + 1] = (byte)deferredRoutineAddress;
            outRom[DEFERRED_EVENT_HOOK_OFFSET + 2] = (byte)(deferredRoutineAddress >> 8);
            outRom[DEFERRED_EVENT_HOOK_OFFSET + 3] = (byte)(deferredRoutineAddress >> 16);

            // Replace exactly $01/D376 LDA [$06],Y; $01/D378 SEP #$20. The wrapper replays both
            // instructions before applying the actor-centered specific-weapon fallback.
            outRom[TILE_COLLISION_LOAD_HOOK_OFFSET] = 0x22; // JSL proximity routine
            outRom[TILE_COLLISION_LOAD_HOOK_OFFSET + 1] = (byte)proximityRoutineAddress;
            outRom[TILE_COLLISION_LOAD_HOOK_OFFSET + 2] = (byte)(proximityRoutineAddress >> 8);
            outRom[TILE_COLLISION_LOAD_HOOK_OFFSET + 3] = (byte)(proximityRoutineAddress >> 16);

            Logging.log("Specific-weapon Crystal Orb proximity hook: $C1/D376 -> $" +
                ((proximityRoutineAddress >> 16) & 0xFF).ToString("X2") + "/" +
                (proximityRoutineAddress & 0xFFFF).ToString("X4") + "; radius " +
                WEAPON_HORIZONTAL_RADIUS_PIXELS + "x" +
                WEAPON_VERTICAL_RADIUS_PIXELS + " pixels; ranged projectile hook: " +
                (rangedRoutineAddress == 0 ? "inactive" : "$C2/C529 -> $" +
                ((rangedRoutineAddress >> 16) & 0xFF).ToString("X2") + "/" +
                (rangedRoutineAddress & 0xFFFF).ToString("X4") + "; radius " +
                PROJECTILE_HORIZONTAL_RADIUS_PIXELS + "x" +
                PROJECTILE_VERTICAL_RADIUS_PIXELS + " pixels") +
                "; deferred event hook: $C0/B6A4 -> $" +
                ((deferredRoutineAddress >> 16) & 0xFF).ToString("X2") + "/" +
                (deferredRoutineAddress & 0xFFFF).ToString("X4") + "; physical-pass command: 57 " +
                physicalPassCommandIndex.ToString("X2") + ".");
            return true;
        }

        private static List<EnabledCrystalOrbPhysicalRoute> getEnabledRoutes(byte[] origRom, RandoContext context)
        {
            Dictionary<int, CrystalOrbRequirement> requirementsByMap =
                CrystalOrbRequirements.getResolvedRequirements(context);
            List<EnabledCrystalOrbPhysicalRoute> enabledRoutes = new List<EnabledCrystalOrbPhysicalRoute>();
            foreach(CrystalOrbRequirement requirement in requirementsByMap.Values)
            {
                if(requirement.Type != CrystalOrbRequirementType.SpecificWeapon)
                {
                    continue;
                }

                List<byte> originalEvent;
                if(context.replacementEvents.ContainsKey(requirement.OrbEvent))
                {
                    originalEvent = new List<byte>(context.replacementEvents[requirement.OrbEvent]);
                }
                else
                {
                    // Grand Palace events are deliberately left vanilla in some Open World
                    // character/element configurations. Wrap that authoritative vanilla event
                    // rather than recreating its inline flag and success logic here.
                    originalEvent = new List<byte>(VanillaEventUtil.getVanillaEvent(origRom, requirement.OrbEvent));
                }

                if(originalEvent.Count < 2 || originalEvent[0] < 0x20 || originalEvent[0] > 0x27)
                {
                    throw new InvalidOperationException("Crystal Orb event $" + requirement.OrbEvent.ToString("X3") +
                        " does not begin with an elemental checker JSR.");
                }
                int checkerEvent = ((originalEvent[0] - 0x20) << 8) | originalEvent[1];
                if(checkerEvent < FIRST_ELEMENT_CHECKER_EVENT || checkerEvent > LAST_ELEMENT_CHECKER_EVENT)
                {
                    throw new InvalidOperationException("Crystal Orb event $" + requirement.OrbEvent.ToString("X3") +
                        " calls unexpected checker event $" + checkerEvent.ToString("X3") + ".");
                }
                byte checkerFlag = (byte)(FIRST_ELEMENT_CHECKER_FLAG + checkerEvent - FIRST_ELEMENT_CHECKER_EVENT);
                enabledRoutes.Add(new EnabledCrystalOrbPhysicalRoute(
                    requirement, checkerFlag, originalEvent));
            }
            return enabledRoutes;
        }

        private static void wrapAuthoritativeOrbEvents(RandoContext context,
            List<EnabledCrystalOrbPhysicalRoute> enabledRoutes, byte physicalPassCommandIndex)
        {
            foreach(EnabledCrystalOrbPhysicalRoute enabledRoute in enabledRoutes)
            {
                // A SpecificWeapon Orb must not retain its old magic route. Clear this checker's
                // transient result, then let the custom command set it to an accepted value only
                // for a validated armed physical pass. Every byte following the original checker
                // JSR is retained, including guards and inline mutations. Magic requirements are
                // not wrapped at all, so they continue to call their original checker normally.
                EventScript wrappedEvent = new EventScript();
                wrappedEvent.SetFlag(enabledRoute.CheckerFlag, 0);
                wrappedEvent.Add(EventCommandEnum.CUSTOM_EVENT_COMMANDS.Value, physicalPassCommandIndex);
                for(int i = 2; i < enabledRoute.OriginalEvent.Count; i++)
                {
                    wrappedEvent.Add(enabledRoute.OriginalEvent[i]);
                }
                context.replacementEvents[enabledRoute.Requirement.OrbEvent] = wrappedEvent;
            }
        }

        private static void emitPhysicalPassEventCommand(byte[] outRom, RandoContext context,
            List<EnabledCrystalOrbPhysicalRoute> enabledRoutes)
        {
            int routineOffset = context.workingOffset;
            RoutineWriter w = new RoutineWriter(outRom, routineOffset);
            List<int> clearStateBranches = new List<int>();

            // The injected event command is the only consumer of the armed state. It revalidates
            // the saved map, event target, actor slot, active byte, and species before supplying
            // the checker's normal accepted value. Every exit clears the state, making the pass
            // one-shot even if dispatch or event execution is interrupted.
            w.Bytes(0x08, 0xC2, 0x30, 0x48, 0xDA, 0x5A); // PHP; REP #$30; PHA; PHX; PHY
            w.Bytes(0xE2, 0x20); // SEP #$20
            w.Long(0xAF, CustomRamOffsets.CRYSTAL_ORB_PENDING_STATE);
            w.Bytes(0xC9, PENDING_STATE_ARMED);
            int armedBranch = w.Branch(0xF0);

            clearStateBranches.Add(w.BranchLong());
            w.PatchRelative(armedBranch, w.Position);

            w.Bytes(0xC2, 0x20); // REP #$20
            w.Long(0xAF, CustomRamOffsets.CRYSTAL_ORB_PENDING_MAP_16BIT);
            w.Bytes(0xCF, 0xDC, 0x00, 0x7E); // CMP.l current map
            int mapMatchesBranch = w.Branch(0xF0);
            clearStateBranches.Add(w.BranchLong());
            w.PatchRelative(mapMatchesBranch, w.Position);

            w.Long(0xAF, CustomRamOffsets.CRYSTAL_ORB_PENDING_TARGET_16BIT);
            w.Bytes(0xCF, 0xD4, 0x00, 0x7E); // CMP.l current event target
            int targetMatchesBranch = w.Branch(0xF0);
            clearStateBranches.Add(w.BranchLong());
            w.PatchRelative(targetMatchesBranch, w.Position);

            w.Word(0xC9, FIRST_NONPLAYER_ACTOR_OFFSET);
            int targetMinimumBranch = w.Branch(0xB0); // BCS target >= first actor
            clearStateBranches.Add(w.BranchLong());
            w.PatchRelative(targetMinimumBranch, w.Position);
            w.Word(0xC9, ACTOR_TABLE_END_OFFSET);
            int targetMaximumBranch = w.Branch(0x90); // BCC target < table end
            clearStateBranches.Add(w.BranchLong());
            w.PatchRelative(targetMaximumBranch, w.Position);
            w.Word(0x29, ACTOR_RECORD_STRIDE - 1); // AND #$01FF
            int alignedTargetBranch = w.Branch(0xF0);
            clearStateBranches.Add(w.BranchLong());
            w.PatchRelative(alignedTargetBranch, w.Position);

            w.Long(0xAF, CustomRamOffsets.CRYSTAL_ORB_PENDING_TARGET_16BIT);
            w.Bytes(0xAA, 0xE2, 0x20); // TAX; SEP #$20
            w.Bytes(0xBF, 0x00, 0xE0, 0x7E); // active/existence byte
            int activeActorBranch = w.Branch(0xD0);
            clearStateBranches.Add(w.BranchLong());
            w.PatchRelative(activeActorBranch, w.Position);
            int positiveActorBranch = w.Branch(0x10); // BPL active actor
            clearStateBranches.Add(w.BranchLong());
            w.PatchRelative(positiveActorBranch, w.Position);
            w.Bytes(0xBF, 0xE7, 0xE1, 0x7E, 0xC9, ORB_SPECIES);
            int orbSpeciesBranch = w.Branch(0xF0);
            clearStateBranches.Add(w.BranchLong());
            w.PatchRelative(orbSpeciesBranch, w.Position);

            w.Bytes(0xC2, 0x20); // REP #$20
            w.Bytes(0xAF, 0xDC, 0x00, 0x7E); // current map
            Dictionary<byte, List<int>> routeBranchesByCheckerFlag =
                new Dictionary<byte, List<int>>();
            List<byte> checkerFlagOrder = new List<byte>();
            foreach(EnabledCrystalOrbPhysicalRoute enabledRoute in enabledRoutes)
            {
                w.Word(0xC9, enabledRoute.Requirement.MapNumber);
                int nextMapBranch = w.Branch(0xD0);
                if(!routeBranchesByCheckerFlag.ContainsKey(enabledRoute.CheckerFlag))
                {
                    routeBranchesByCheckerFlag[enabledRoute.CheckerFlag] = new List<int>();
                    checkerFlagOrder.Add(enabledRoute.CheckerFlag);
                }
                routeBranchesByCheckerFlag[enabledRoute.CheckerFlag].Add(w.BranchLong());
                w.PatchRelative(nextMapBranch, w.Position);
            }
            clearStateBranches.Add(w.BranchLong());

            foreach(byte checkerFlag in checkerFlagOrder)
            {
                foreach(int routeBranch in routeBranchesByCheckerFlag[checkerFlag])
                {
                    w.PatchRelativeLong(routeBranch, w.Position);
                }
                w.Bytes(0xE2, 0x20, 0xA9, PHYSICAL_CHECKER_SUCCESS_VALUE);
                w.Long(0x8F, EVENT_FLAGS_RAM_BASE + checkerFlag);
                clearStateBranches.Add(w.BranchLong());
            }

            int clearStateOffset = w.Position;
            foreach(int branch in clearStateBranches)
            {
                w.PatchRelativeLong(branch, clearStateOffset);
            }
            w.Bytes(0xE2, 0x20, 0xA9, PENDING_STATE_NONE);
            w.Long(0x8F, CustomRamOffsets.CRYSTAL_ORB_PENDING_STATE);
            w.Bytes(0xC2, 0x30, 0x7A, 0xFA, 0x68, 0x28, 0x6B); // restore Y, X, A, P; RTL

            context.workingOffset = w.Position;
            assertRoutineWithinMax("physical-pass command", routineOffset, context.workingOffset,
                PHYSICAL_PASS_COMMAND_MAX_LENGTH);
        }

        private static void emitDeferredDispatcher(byte[] outRom, RandoContext context,
            List<EnabledCrystalOrbPhysicalRoute> enabledRoutes)
        {
            int routineOffset = context.workingOffset;
            RoutineWriter w = new RoutineWriter(outRom, routineOffset);
            List<int> clearAndReplayBranches = new List<int>();
            List<int> replayBranches = new List<int>();

            // $C0/B6A4 is in the normal per-frame event/input dispatcher, after its F1 busy-state
            // checks. The collision hook only queues a target/map pair. Once it remains valid and
            // all vanilla busy conditions are clear, arm one physical pass and dispatch the
            // individual Orb event through $C1/E76D. Its injected command consumes the pass before
            // the event reaches its original elemental checker gate.
            w.Bytes(0x08, 0xC2, 0x30, 0x48, 0xDA, 0x5A); // preserve P, A, X, Y
            w.Bytes(0xE2, 0x20);
            w.Long(0xAF, CustomRamOffsets.CRYSTAL_ORB_PENDING_STATE);
            int hasPendingBranch = w.Branch(0xD0);
            replayBranches.Add(w.BranchLong());
            w.PatchRelative(hasPendingBranch, w.Position);
            w.Bytes(0xC9, PENDING_STATE_QUEUED);
            int queuedBranch = w.Branch(0xF0);
            w.Bytes(0xC9, PENDING_STATE_ARMED);
            int armedBranch = w.Branch(0xF0);
            clearAndReplayBranches.Add(w.BranchLong());
            w.PatchRelative(queuedBranch, w.Position);
            w.PatchRelative(armedBranch, w.Position);

            // Reject a queued hit immediately if its map or actor binding has gone stale.
            w.Bytes(0xC2, 0x20);
            w.Long(0xAF, CustomRamOffsets.CRYSTAL_ORB_PENDING_MAP_16BIT);
            w.Bytes(0xCF, 0xDC, 0x00, 0x7E);
            int savedMapMatchesBranch = w.Branch(0xF0);
            clearAndReplayBranches.Add(w.BranchLong());
            w.PatchRelative(savedMapMatchesBranch, w.Position);

            w.Long(0xAF, CustomRamOffsets.CRYSTAL_ORB_PENDING_TARGET_16BIT);
            w.Word(0xC9, FIRST_NONPLAYER_ACTOR_OFFSET);
            int queuedTargetMinimumBranch = w.Branch(0xB0);
            clearAndReplayBranches.Add(w.BranchLong());
            w.PatchRelative(queuedTargetMinimumBranch, w.Position);
            w.Word(0xC9, ACTOR_TABLE_END_OFFSET);
            int queuedTargetMaximumBranch = w.Branch(0x90);
            clearAndReplayBranches.Add(w.BranchLong());
            w.PatchRelative(queuedTargetMaximumBranch, w.Position);
            w.Word(0x29, ACTOR_RECORD_STRIDE - 1);
            int queuedTargetAlignedBranch = w.Branch(0xF0);
            clearAndReplayBranches.Add(w.BranchLong());
            w.PatchRelative(queuedTargetAlignedBranch, w.Position);
            w.Long(0xAF, CustomRamOffsets.CRYSTAL_ORB_PENDING_TARGET_16BIT);
            w.Bytes(0xAA, 0xE2, 0x20);
            w.Bytes(0xBF, 0x00, 0xE0, 0x7E);
            int queuedActorActiveBranch = w.Branch(0xD0);
            clearAndReplayBranches.Add(w.BranchLong());
            w.PatchRelative(queuedActorActiveBranch, w.Position);
            int queuedActorPositiveBranch = w.Branch(0x10);
            clearAndReplayBranches.Add(w.BranchLong());
            w.PatchRelative(queuedActorPositiveBranch, w.Position);
            w.Bytes(0xBF, 0xE7, 0xE1, 0x7E, 0xC9, ORB_SPECIES);
            int queuedOrbSpeciesBranch = w.Branch(0xF0);
            clearAndReplayBranches.Add(w.BranchLong());
            w.PatchRelative(queuedOrbSpeciesBranch, w.Position);

            // A successfully started event executes asynchronously. Retain ARMED only while
            // that event is still active and still owns the exact saved Orb target. This lets
            // the injected first event command consume it on the following interpreter pass,
            // but clears an aborted/replaced event before any normal magic can inherit it.
            w.Long(0xAF, CustomRamOffsets.CRYSTAL_ORB_PENDING_STATE);
            w.Bytes(0xC9, PENDING_STATE_ARMED);
            int processQueuedBranch = w.Branch(0xD0);
            w.Bytes(0xC2, 0x20);
            w.Long(0xAF, CustomRamOffsets.CRYSTAL_ORB_PENDING_TARGET_16BIT);
            w.Bytes(0xCF, 0xD4, 0x00, 0x7E);
            int armedTargetMatchesBranch = w.Branch(0xF0);
            clearAndReplayBranches.Add(w.BranchLong());
            w.PatchRelative(armedTargetMatchesBranch, w.Position);
            w.Bytes(0xE2, 0x20, 0xAF, 0xD0, 0x00, 0x7E);
            int armedEventActiveBranch = w.Branch(0xD0);
            clearAndReplayBranches.Add(w.BranchLong());
            w.PatchRelative(armedEventActiveBranch, w.Position);
            replayBranches.Add(w.BranchLong());

            w.PatchRelative(processQueuedBranch, w.Position);

            w.Bytes(0xAF, 0xD0, 0x00, 0x7E); // LDA.l $7E00D0 - event interpreter state
            int eventStateReadyBranch = w.Branch(0xF0);
            replayBranches.Add(w.BranchLong());
            w.PatchRelative(eventStateReadyBranch, w.Position);
            w.Bytes(0xAF, 0xFF, 0x00, 0x7E); // LDA.l $7E00FF
            w.Bytes(0x0F, 0x52, 0x00, 0x7E); // ORA.l $7E0052
            int globalReadyBranch = w.Branch(0xF0);
            replayBranches.Add(w.BranchLong());
            w.PatchRelative(globalReadyBranch, w.Position);
            w.Bytes(0xAF, 0xE2, 0x00, 0x7E, 0x29, 0x01); // LDA.l $7E00E2; AND #$01
            int transitionReadyBranch = w.Branch(0xF0);
            replayBranches.Add(w.BranchLong());
            w.PatchRelative(transitionReadyBranch, w.Position);
            w.Bytes(0xAF, 0xE8, 0x00, 0x7E, 0x29, 0x04); // LDA.l $7E00E8; AND #$04
            int mapStateReadyBranch = w.Branch(0xF0);
            replayBranches.Add(w.BranchLong());
            w.PatchRelative(mapStateReadyBranch, w.Position);

            w.Bytes(0xC2, 0x20);
            w.Bytes(0xAF, 0xDC, 0x00, 0x7E); // LDA.l $7E00DC - current map
            List<int> routeBranches = new List<int>();
            foreach(EnabledCrystalOrbPhysicalRoute enabledRoute in enabledRoutes)
            {
                w.Word(0xC9, enabledRoute.Requirement.MapNumber); // CMP #map
                routeBranches.Add(w.Branch(0xF0));
            }
            clearAndReplayBranches.Add(w.BranchLong());

            List<int> dispatchBranches = new List<int>();
            for(int i = 0; i < enabledRoutes.Count; i++)
            {
                w.PatchRelative(routeBranches[i], w.Position);
                w.Word(0xA9, enabledRoutes[i].Requirement.OrbEvent); // LDA #individual Orb event
                dispatchBranches.Add(w.BranchLong());
            }

            int dispatchOffset = w.Position;
            foreach(int branch in dispatchBranches)
            {
                w.PatchRelativeLong(branch, dispatchOffset);
            }
            w.Bytes(0x48); // PHA individual Orb event
            w.Long(0xAF, CustomRamOffsets.CRYSTAL_ORB_PENDING_TARGET_16BIT);
            w.Bytes(0x8F, 0xD4, 0x00, 0x7E); // install saved Orb as event target
            w.Bytes(0xE2, 0x20, 0xA9, PENDING_STATE_ARMED);
            w.Long(0x8F, CustomRamOffsets.CRYSTAL_ORB_PENDING_STATE);
            w.Bytes(0xC2, 0x20, 0x68); // restore individual Orb event
            w.Bytes(0x22, 0x6D, 0xE7, 0xC1); // JSL $C1E76D - normal event dispatcher

            // $C1/E76D starts the event interpreter; the event's first commands execute after
            // this call returns. Keep the pass armed only when startup moved $D0 out of idle.
            // If startup failed, clear immediately so no later normal-magic event can inherit it.
            w.Bytes(0xE2, 0x20);
            w.Bytes(0xAF, 0xD0, 0x00, 0x7E); // event interpreter state after startup
            int eventStartedBranch = w.Branch(0xD0);
            w.Bytes(0xA9, PENDING_STATE_NONE);
            w.Long(0x8F, CustomRamOffsets.CRYSTAL_ORB_PENDING_STATE);
            w.PatchRelative(eventStartedBranch, w.Position);
            replayBranches.Add(w.BranchLong());

            int clearAndReplayOffset = w.Position;
            foreach(int branch in clearAndReplayBranches)
            {
                w.PatchRelativeLong(branch, clearAndReplayOffset);
            }
            w.Bytes(0xE2, 0x20, 0xA9, PENDING_STATE_NONE);
            w.Long(0x8F, CustomRamOffsets.CRYSTAL_ORB_PENDING_STATE);

            int replayOffset = w.Position;
            foreach(int branch in replayBranches)
            {
                w.PatchRelativeLong(branch, replayOffset);
            }
            w.Bytes(0xC2, 0x30, 0x7A, 0xFA, 0x68, 0x28); // restore Y, X, A, P
            w.Bytes(0xA5, 0xFF, 0x05, 0x52, 0x6B); // displaced LDA $FF; ORA $52; RTL

            context.workingOffset = w.Position;
            assertRoutineWithinMax("deferred-event", routineOffset, context.workingOffset,
                DEFERRED_EVENT_ROUTINE_MAX_LENGTH);
        }

        private static void emitActorCenteredProximityCheck(byte[] outRom, RandoContext context,
            List<EnabledCrystalOrbPhysicalRoute> meleeRoutes)
        {
            int routineOffset = context.workingOffset;
            RoutineWriter w = new RoutineWriter(outRom, routineOffset);

            // $01/D293 calculates the vanilla directional 16x16-tile probe. Its $01/D29A
            // LDA #$1010 displacement remains unchanged; larger values move the probe.
            // $01/D376 loads Collision[2..3] through LDA [$06],Y. Replay that load and the
            // following SEP #$20 before any custom checks. An exact Collision[2] == $FF is an
            // authoritative directional tile contact for this player-record probe. Ranged weapon
            // requirements are deliberately absent from this routine and are handled from the
            // real projectile records at $C2/C529. Other
            // $F0/$C0 classes remain vanilla.
            // For probes that did not find $FF, retain the actor-centered 40x40 fallback that
            // makes short-range weapons usable without changing their global reach.
            w.Bytes(0xB7, 0x06, 0x48, 0xE2, 0x20); // LDA [$06],Y; PHA; SEP #$20
            w.Bytes(0xC9, 0xFF); // exact Crystal Orb interaction collision
            int exactContactBranch = w.Branch(0xF0);
            w.Bytes(0x29, 0xF0, 0xC9, 0xF0); // AND #$F0; CMP #$F0
            int f0Branch = w.Branch(0xF0);
            w.Bytes(0xC9, 0xC0); // CMP #$C0
            int normalCollisionBranch = w.Branch(0xD0);
            w.PatchRelative(f0Branch, w.Position);
            w.Bytes(0xC2, 0x20, 0x68, 0xE2, 0x20, 0x6B); // return original collision word

            w.PatchRelative(normalCollisionBranch, w.Position);
            w.Bytes(0xA9, 0x00); // actor-centered fallback; proximity is still required
            int contactMarkerReadyBranch = w.Branch(0x80);
            w.PatchRelative(exactContactBranch, w.Position);
            w.Bytes(0xA9, 0x01); // exact $FF contact; the probe already established geometry
            w.PatchRelative(contactMarkerReadyBranch, w.Position);
            w.Bytes(0x48); // one-byte exact-contact marker, above the saved collision word

            // $E1E3,X is the player's full equipped weapon ID: family * 9 + forge rank
            // (0..71), not a clean family ID. Range-decode it instead of masking low bits;
            // masking aliases unrelated weapon/rank combinations and makes Glove/0 appear
            // to act like a wildcard. X remains the owning player record at $01/D376 for
            // melee and ranged probes.
            w.Bytes(0xBD, 0xE3, 0xE1);

            // Group the resolved routes by required weapon. Runtime receives the profile's
            // already-resolved map/weapon pairs and owns no requirement-selection policy.
            Dictionary<int, List<EnabledCrystalOrbPhysicalRoute>> routesByWeapon =
                new Dictionary<int, List<EnabledCrystalOrbPhysicalRoute>>();
            foreach(EnabledCrystalOrbPhysicalRoute enabledRoute in meleeRoutes)
            {
                int weaponId = enabledRoute.Requirement.Value;
                if(!routesByWeapon.ContainsKey(weaponId))
                {
                    routesByWeapon[weaponId] = new List<EnabledCrystalOrbPhysicalRoute>();
                }
                routesByWeapon[weaponId].Add(enabledRoute);
            }

            Dictionary<int, int> weaponGroupBranches = new Dictionary<int, int>();
            for(int weaponId = 0; weaponId < 8; weaponId++)
            {
                if(routesByWeapon.ContainsKey(weaponId))
                {
                    int firstFullWeaponId = weaponId * 9;
                    int nextFullWeaponId = firstFullWeaponId + 9;
                    w.Bytes(0xC9, firstFullWeaponId);
                    int belowWeaponBranch = w.Branch(0x90); // BCC next family
                    w.Bytes(0xC9, nextFullWeaponId);
                    int aboveWeaponBranch = w.Branch(0xB0); // BCS next family
                    weaponGroupBranches[weaponId] = w.BranchLong();
                    w.PatchRelative(belowWeaponBranch, w.Position);
                    w.PatchRelative(aboveWeaponBranch, w.Position);
                }
            }
            List<int> returnOriginalBranches = new List<int>();
            returnOriginalBranches.Add(w.BranchLong());
            List<int> acceptedRouteBranches = new List<int>();

            for(int weaponId = 0; weaponId < 8; weaponId++)
            {
                if(!routesByWeapon.ContainsKey(weaponId))
                {
                    continue;
                }

                w.PatchRelativeLong(weaponGroupBranches[weaponId], w.Position);
                w.Bytes(0xC2, 0x20, 0xAF, 0xDC, 0x00, 0x7E); // REP #$20; current map
                foreach(EnabledCrystalOrbPhysicalRoute enabledRoute in routesByWeapon[weaponId])
                {
                    w.Word(0xC9, enabledRoute.Requirement.MapNumber);
                    int nextMapBranch = w.Branch(0xD0);
                    acceptedRouteBranches.Add(w.BranchLong());
                    w.PatchRelative(nextMapBranch, w.Position);
                }
                returnOriginalBranches.Add(w.BranchLong());
            }

            int acceptedRouteOffset = w.Position;
            foreach(int branch in acceptedRouteBranches)
            {
                w.PatchRelativeLong(branch, acceptedRouteOffset);
            }

            // Actor records $0600..$1600 use a $0200 stride. $E000,Y is active/existence,
            // $E1E7,Y is species, and $E002/$E004 are 16-bit map-pixel X/Y. X remains the
            // attacking player record from $01/D293. Exact $FF contacts can queue once
            // a live Orb actor is found; all other probes use the unchanged symmetric,
            // Orb-centered 40x40 fallback without changing global weapon reach.
            w.Bytes(0xC2, 0x20, 0xDA, 0x5A); // REP #$20; preserve X/Y
            w.Word(0xA0, FIRST_NONPLAYER_ACTOR_OFFSET); // LDY #first nonplayer actor
            int scanLoopOffset = w.Position;
            w.Bytes(0xE2, 0x20, 0xB9, 0x00, 0xE0); // active/existence byte
            int emptyActorBranch = w.Branch(0xF0);
            int inactiveActorBranch = w.Branch(0x30);
            w.Bytes(0xB9, 0xE7, 0xE1, 0xC9, ORB_SPECIES); // species $55
            int nonOrbBranch = w.Branch(0xD0);

            w.Bytes(0xA3, 0x05); // exact-contact marker below saved Y and X
            int exactContactQueueBranch = w.Branch(0xD0);
            w.Bytes(0xC2, 0x20, 0xBD, 0x02, 0xE0, 0x38, 0xF9, 0x02, 0xE0); // playerX - orbX
            w.Bytes(0x10, 0x04, 0x49, 0xFF, 0xFF, 0x1A); // absolute value
            w.Word(0xC9, WEAPON_HORIZONTAL_RADIUS_PIXELS + 1);
            int horizontalBranch = w.Branch(0xB0);
            w.Bytes(0xBD, 0x04, 0xE0, 0x38, 0xF9, 0x04, 0xE0); // playerY - orbY
            w.Bytes(0x10, 0x04, 0x49, 0xFF, 0xFF, 0x1A); // absolute value
            w.Word(0xC9, WEAPON_VERTICAL_RADIUS_PIXELS + 1);
            int verticalBranch = w.Branch(0xB0);
            w.PatchRelative(exactContactQueueBranch, w.Position);

            // Publish target and map before setting QUEUED so the deferred reader never observes
            // a partially written binding. Do not overwrite an already armed pass.
            w.Bytes(0xE2, 0x20);
            w.Long(0xAF, CustomRamOffsets.CRYSTAL_ORB_PENDING_STATE);
            w.Bytes(0xC9, PENDING_STATE_ARMED);
            int alreadyArmedBranch = w.Branch(0xF0);
            w.Bytes(0xC2, 0x20, 0x98); // REP #$20; TYA
            w.Long(0x8F, CustomRamOffsets.CRYSTAL_ORB_PENDING_TARGET_16BIT);
            w.Bytes(0xAF, 0xDC, 0x00, 0x7E);
            w.Long(0x8F, CustomRamOffsets.CRYSTAL_ORB_PENDING_MAP_16BIT);
            w.Bytes(0xE2, 0x20, 0xA9, PENDING_STATE_QUEUED);
            w.Long(0x8F, CustomRamOffsets.CRYSTAL_ORB_PENDING_STATE);
            w.PatchRelative(alreadyArmedBranch, w.Position);
            w.Bytes(0xC2, 0x20, 0x7A, 0xFA); // restore vanilla Y and attacking-player X
            w.Bytes(0xE2, 0x20, 0x68); // discard exact-contact marker
            w.Bytes(0xC2, 0x20, 0x68, 0xE2, 0x20, 0x6B); // return original collision word

            int nextActorOffset = w.Position;
            w.PatchRelative(emptyActorBranch, nextActorOffset);
            w.PatchRelative(inactiveActorBranch, nextActorOffset);
            w.PatchRelative(nonOrbBranch, nextActorOffset);
            w.PatchRelative(horizontalBranch, nextActorOffset);
            w.PatchRelative(verticalBranch, nextActorOffset);
            w.Bytes(0xC2, 0x20, 0x98, 0x18); // REP #$20; TYA; CLC
            w.Word(0x69, ACTOR_RECORD_STRIDE);
            w.Bytes(0xA8); // TAY
            w.Word(0xC0, ACTOR_TABLE_END_OFFSET);
            int loopBranch = w.Branch(0x90);
            w.PatchRelative(loopBranch, scanLoopOffset);
            w.Bytes(0x7A, 0xFA); // restore vanilla Y and attacking-player X

            int returnOriginalOffset = w.Position;
            foreach(int branch in returnOriginalBranches)
            {
                w.PatchRelativeLong(branch, returnOriginalOffset);
            }
            w.Bytes(0xE2, 0x20, 0x68); // discard exact-contact marker
            w.Bytes(0xC2, 0x20, 0x68, 0xE2, 0x20, 0x6B); // return original collision word

            context.workingOffset = w.Position;
            assertRoutineWithinMax("tile-collision fallback", routineOffset, context.workingOffset,
                TILE_COLLISION_FALLBACK_ROUTINE_MAX_LENGTH);
        }

        private static void emitRangedProjectileCheck(byte[] outRom, RandoContext context,
            List<EnabledCrystalOrbPhysicalRoute> rangedRoutes)
        {
            int routineOffset = context.workingOffset;
            RoutineWriter w = new RoutineWriter(outRom, routineOffset);

            // Projectile state is not an $E000 actor. Each player owns a $40-byte block in
            // $7E:D000, selected by player-record offset / 8; its live slots start at +00/+10/+20.
            // $D000,Y is the originating projectile type (Bow=1, Javelin=2, Boomerang=3 or 5),
            // while $D002/$D004 are its updated map-pixel coordinates. At $C2/C529 X is still the
            // owning player record and Y is the exact live projectile slot.
            w.Bytes(0x08, 0xC2, 0x30, 0x48, 0xDA, 0x5A); // PHP; REP #$30; PHA; PHX; PHY
            List<int> finishBranches = new List<int>();

            w.Word(0xE0, 0x0000); // player 1 owner
            int ownerOneBranch = w.Branch(0xF0);
            w.Word(0xE0, 0x0200); // player 2 owner
            int ownerTwoBranch = w.Branch(0xF0);
            w.Word(0xE0, 0x0400); // player 3 owner
            int ownerThreeBranch = w.Branch(0xF0);
            finishBranches.Add(w.BranchLong());
            int validOwnerOffset = w.Position;
            w.PatchRelative(ownerOneBranch, validOwnerOffset);
            w.PatchRelative(ownerTwoBranch, validOwnerOffset);
            w.PatchRelative(ownerThreeBranch, validOwnerOffset);

            w.Bytes(0xE2, 0x20, 0xB9, 0x00, 0xD0); // projectile type in current Y slot
            Dictionary<int, List<EnabledCrystalOrbPhysicalRoute>> routesByWeapon =
                new Dictionary<int, List<EnabledCrystalOrbPhysicalRoute>>();
            foreach(EnabledCrystalOrbPhysicalRoute rangedRoute in rangedRoutes)
            {
                int weaponId = rangedRoute.Requirement.Value;
                if(!routesByWeapon.ContainsKey(weaponId))
                {
                    routesByWeapon[weaponId] = new List<EnabledCrystalOrbPhysicalRoute>();
                }
                routesByWeapon[weaponId].Add(rangedRoute);
            }

            Dictionary<int, List<int>> weaponBranches = new Dictionary<int, List<int>>();
            weaponBranches[5] = new List<int>();
            weaponBranches[6] = new List<int>();
            weaponBranches[7] = new List<int>();
            if(routesByWeapon.ContainsKey(5))
            {
                w.Bytes(0xC9, 0x01); // Bow projectile
                weaponBranches[5].Add(w.Branch(0xF0));
            }
            if(routesByWeapon.ContainsKey(7))
            {
                w.Bytes(0xC9, 0x02); // Javelin projectile
                weaponBranches[7].Add(w.Branch(0xF0));
            }
            if(routesByWeapon.ContainsKey(6))
            {
                w.Bytes(0xC9, 0x03); // Boomerang projectile variant A
                weaponBranches[6].Add(w.Branch(0xF0));
                w.Bytes(0xC9, 0x05); // Boomerang projectile variant B
                weaponBranches[6].Add(w.Branch(0xF0));
            }
            finishBranches.Add(w.BranchLong());
            List<int> acceptedBranches = new List<int>();

            for(int weaponId = 5; weaponId <= 7; weaponId++)
            {
                if(!routesByWeapon.ContainsKey(weaponId))
                {
                    continue;
                }
                foreach(int weaponBranch in weaponBranches[weaponId])
                {
                    w.PatchRelative(weaponBranch, w.Position);
                }
                w.Bytes(0xC2, 0x20, 0xAF, 0xDC, 0x00, 0x7E); // current map
                foreach(EnabledCrystalOrbPhysicalRoute rangedRoute in routesByWeapon[weaponId])
                {
                    w.Word(0xC9, rangedRoute.Requirement.MapNumber);
                    int nextMapBranch = w.Branch(0xD0);
                    acceptedBranches.Add(w.BranchLong());
                    w.PatchRelative(nextMapBranch, w.Position);
                }
                finishBranches.Add(w.BranchLong());
            }

            int acceptedOffset = w.Position;
            foreach(int branch in acceptedBranches)
            {
                w.PatchRelativeLong(branch, acceptedOffset);
            }

            // Do not replace a queued or armed pass. The individual Orb event remains responsible
            // for removing the matched actor; projectile lifetime and return behavior stay vanilla.
            w.Bytes(0xE2, 0x20);
            w.Long(0xAF, CustomRamOffsets.CRYSTAL_ORB_PENDING_STATE);
            w.Bytes(0xC9, PENDING_STATE_NONE);
            int noPendingBranch = w.Branch(0xF0);
            finishBranches.Add(w.BranchLong());
            w.PatchRelative(noPendingBranch, w.Position);

            w.Word(0xA2, FIRST_NONPLAYER_ACTOR_OFFSET); // scan active world actors in X
            int scanLoopOffset = w.Position;
            w.Bytes(0xE2, 0x20, 0xBD, 0x00, 0xE0); // active/existence byte
            int emptyActorBranch = w.Branch(0xF0);
            int inactiveActorBranch = w.Branch(0x30);
            w.Bytes(0xBD, 0xE7, 0xE1, 0xC9, ORB_SPECIES);
            int nonOrbBranch = w.Branch(0xD0);

            w.Bytes(0xC2, 0x20, 0xB9, 0x02, 0xD0, 0x38, 0xFD, 0x02, 0xE0); // projectileX - orbX
            w.Bytes(0x10, 0x04, 0x49, 0xFF, 0xFF, 0x1A); // absolute value
            w.Word(0xC9, PROJECTILE_HORIZONTAL_RADIUS_PIXELS + 1);
            int horizontalBranch = w.Branch(0xB0);
            w.Bytes(0xB9, 0x04, 0xD0, 0x38, 0xFD, 0x04, 0xE0); // projectileY - orbY
            w.Bytes(0x10, 0x04, 0x49, 0xFF, 0xFF, 0x1A); // absolute value
            w.Word(0xC9, PROJECTILE_VERTICAL_RADIUS_PIXELS + 1);
            int verticalBranch = w.Branch(0xB0);

            // Publish the same actor/map binding consumed by the existing architecture-B
            // deferred dispatcher. The projectile hook adds no event-success path of its own.
            w.Bytes(0x8A); // TXA: matched Orb actor record
            w.Long(0x8F, CustomRamOffsets.CRYSTAL_ORB_PENDING_TARGET_16BIT);
            w.Bytes(0xAF, 0xDC, 0x00, 0x7E);
            w.Long(0x8F, CustomRamOffsets.CRYSTAL_ORB_PENDING_MAP_16BIT);
            w.Bytes(0xE2, 0x20, 0xA9, PENDING_STATE_QUEUED);
            w.Long(0x8F, CustomRamOffsets.CRYSTAL_ORB_PENDING_STATE);

            finishBranches.Add(w.BranchLong());

            int nextActorOffset = w.Position;
            w.PatchRelative(emptyActorBranch, nextActorOffset);
            w.PatchRelative(inactiveActorBranch, nextActorOffset);
            w.PatchRelative(nonOrbBranch, nextActorOffset);
            w.PatchRelative(horizontalBranch, nextActorOffset);
            w.PatchRelative(verticalBranch, nextActorOffset);
            w.Bytes(0xC2, 0x20, 0x8A, 0x18); // TXA; CLC
            w.Word(0x69, ACTOR_RECORD_STRIDE);
            w.Bytes(0xAA); // TAX
            w.Word(0xE0, ACTOR_TABLE_END_OFFSET);
            int loopBranch = w.Branch(0x90);
            w.PatchRelative(loopBranch, scanLoopOffset);

            int finishOffset = w.Position;
            foreach(int branch in finishBranches)
            {
                w.PatchRelativeLong(branch, finishOffset);
            }
            w.Bytes(0xC2, 0x30, 0x7A, 0xFA, 0x68, 0x28); // restore Y, X, A, P
            w.Bytes(0xE2, 0x20, 0xB9, 0x00, 0xD0, 0x6B); // displaced SEP #$20; LDA $D000,Y; RTL

            context.workingOffset = w.Position;
            assertRoutineWithinMax("ranged projectile", routineOffset, context.workingOffset,
                RANGED_PROJECTILE_ROUTINE_MAX_LENGTH);
        }

        private static void assertRoutineWithinMax(string name, int startOffset, int endOffset, int maximumLength)
        {
            int actualLength = endOffset - startOffset;
            if(actualLength > maximumLength)
            {
                throw new InvalidOperationException("Crystal Orb " + name + " routine length " + actualLength +
                    " exceeds reserved maximum " + maximumLength + ".");
            }
        }

        private sealed class RoutineWriter
        {
            private readonly byte[] rom;

            internal RoutineWriter(byte[] rom, int offset)
            {
                this.rom = rom;
                Position = offset;
            }

            internal int Position { get; private set; }

            internal void Bytes(params int[] bytes)
            {
                foreach(int value in bytes)
                {
                    rom[Position++] = (byte)value;
                }
            }

            internal void Word(int opcode, int value)
            {
                Bytes(opcode, value, value >> 8);
            }

            internal void Long(int opcode, int address)
            {
                Bytes(opcode, address, address >> 8, address >> 16);
            }

            internal int Branch(int opcode)
            {
                Bytes(opcode, 0);
                return Position - 1;
            }

            internal int BranchLong()
            {
                Bytes(0x82, 0, 0); // BRL
                return Position - 2;
            }

            internal void PatchRelative(int operandOffset, int targetOffset)
            {
                int displacement = targetOffset - (operandOffset + 1);
                if(displacement < sbyte.MinValue || displacement > sbyte.MaxValue)
                {
                    throw new InvalidOperationException("Crystal Orb generated branch is out of range.");
                }
                rom[operandOffset] = unchecked((byte)(sbyte)displacement);
            }

            internal void PatchRelativeLong(int operandOffset, int targetOffset)
            {
                int displacement = targetOffset - (operandOffset + 2);
                if(displacement < short.MinValue || displacement > short.MaxValue)
                {
                    throw new InvalidOperationException("Crystal Orb generated long branch is out of range.");
                }
                rom[operandOffset] = (byte)displacement;
                rom[operandOffset + 1] = (byte)(displacement >> 8);
            }
        }
    }
}
