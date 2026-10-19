using SoMRandomizer.config.settings;
using SoMRandomizer.logging;
using SoMRandomizer.processing.common;
using SoMRandomizer.util;
using System;

namespace SoMRandomizer.processing.hacks.common.qol
{
    /// <summary>
    /// Applies one seed-resolved final multiplier to player offensive spell HP damage.
    /// </summary>
    public class PlayerMagicDamage : RandoProcessor
    {
        public const string ROUTINE_OFFSET_HIROM = "playerMagicDamageRoutineOffsetHirom";
        public const string RESOLVED_PERCENTAGE = "playerMagicDamageResolvedPercentage";

        internal const string MODE_VANILLA = "vanilla";
        internal const string MODE_FIXED = "fixed";
        internal const string MODE_RANDOM = "random";
        internal const int FIRST_FINAL_DAMAGE_STORE_OFFSET = 0x8EB90;
        internal const int SECOND_FINAL_DAMAGE_STORE_OFFSET = 0x8E9F6;
        internal const int MIN_RANDOM_PERCENT = 0;
        internal const int MAX_RANDOM_PERCENT = 100;
        internal const int PERCENT_STEP = 5;
        internal const int CRYSTAL_ORB_SPECIES = 0x55;

        protected override string getName()
        {
            return "Player magic damage multiplier";
        }

        protected override bool process(byte[] origRom, byte[] outRom, string seed, RandoSettings settings, RandoContext context)
        {
            string mode = settings.get(CommonSettings.PROPERTYNAME_PLAYER_MAGIC_DAMAGE);
            int fixedPercentage = settings.getInt(CommonSettings.PROPERTYNAME_PLAYER_MAGIC_DAMAGE_PERCENT);
            int percentage = resolvePercentage(mode, fixedPercentage, context.randomFunctional);
            context.workingData.setInt(RESOLVED_PERCENTAGE, percentage);
            Logging.log("Player magic damage: " + displayMode(mode) + " -> " + percentage + "%", "spoiler");

            // Vanilla is deliberately a strict no-write path. Fixed/Random resolving to 100%
            // also needs no runtime hook, but remains distinguishable in the spoiler log.
            if(mode == MODE_VANILLA || percentage == 100)
            {
                return false;
            }

            // Statistics.cs identifies these as the two final magic HP-damage stores. At both,
            // A is the completed 16-bit damage, X is the target pawn record, and Y is the caster.
            // Player records are $0000/$0200/$0400 and enemy records begin at $0600. Filtering on
            // both records excludes enemy-cast magic and player-target healing/support. MP drain
            // uses $E1F5/$E1F6 instead, so it never enters this path.
            CodeGenerationUtils.ensureSpaceInBank(ref context.workingOffset, 192);
            int scalerOffset = context.workingOffset;
            int scalerAddress = scalerOffset + 0xC00000;
            context.workingData.setInt(ROUTINE_OFFSET_HIROM, scalerAddress);

            outRom[context.workingOffset++] = 0xE0; // CPX #$0600 - target must be enemy
            outRom[context.workingOffset++] = 0x00;
            outRom[context.workingOffset++] = 0x06;
            outRom[context.workingOffset++] = 0x90; // BCC return unchanged
            int playerTargetBranchOffset = context.workingOffset++;
            outRom[context.workingOffset++] = 0xC0; // CPY #$0600 - caster must be player
            outRom[context.workingOffset++] = 0x00;
            outRom[context.workingOffset++] = 0x06;
            outRom[context.workingOffset++] = 0xB0; // BCS return unchanged
            int enemyCasterBranchOffset = context.workingOffset++;
            outRom[context.workingOffset++] = 0x48; // PHA - preserve completed damage
            outRom[context.workingOffset++] = 0xE2; // SEP #$20
            outRom[context.workingOffset++] = 0x20;
            outRom[context.workingOffset++] = 0xBF; // LDA.l $7EE1E7,X - target species
            outRom[context.workingOffset++] = 0xE7;
            outRom[context.workingOffset++] = 0xE1;
            outRom[context.workingOffset++] = 0x7E;
            outRom[context.workingOffset++] = 0xC9; // CMP #$55 - never alter Crystal Orb activation
            outRom[context.workingOffset++] = CRYSTAL_ORB_SPECIES;
            outRom[context.workingOffset++] = 0xC2; // REP #$20 (does not alter CMP flags)
            outRom[context.workingOffset++] = 0x20;
            outRom[context.workingOffset++] = 0xD0; // BNE nonOrbTarget
            int nonOrbBranchOffset = context.workingOffset++;
            outRom[context.workingOffset++] = 0x68; // PLA - original damage
            outRom[context.workingOffset++] = 0x6B; // RTL

            int nonOrbTargetOffset = context.workingOffset;
            outRom[nonOrbBranchOffset] = relativeBranch(nonOrbBranchOffset, nonOrbTargetOffset);
            outRom[context.workingOffset++] = 0x68; // PLA - original damage
            outRom[context.workingOffset++] = 0xC9; // CMP #$0000 - preserve zero
            outRom[context.workingOffset++] = 0x00;
            outRom[context.workingOffset++] = 0x00;
            outRom[context.workingOffset++] = 0xF0; // BEQ return unchanged
            int zeroDamageBranchOffset = context.workingOffset++;

            if(percentage == 0)
            {
                outRom[context.workingOffset++] = 0xA9; // LDA #$0000
                outRom[context.workingOffset++] = 0x00;
                outRom[context.workingOffset++] = 0x00;
            }
            else
            {
                // Percentages are multiples of five, so damage * percent / 100 is exactly
                // damage * (percent / 5) / 20. Vanilla caps final damage at 999; the largest
                // intermediate is therefore 999 * 19 = 18,981 and cannot overflow 16 bits.
                // Keep the original damage on the stack and unroll the small constant multiply.
                int multiplier = percentage / PERCENT_STEP;
                outRom[context.workingOffset++] = 0xDA; // PHX - preserve target record
                outRom[context.workingOffset++] = 0x48; // PHA - original damage
                outRom[context.workingOffset++] = 0xA9; // LDA #$0000 - product
                outRom[context.workingOffset++] = 0x00;
                outRom[context.workingOffset++] = 0x00;
                for(int i = 0; i < multiplier; i++)
                {
                    outRom[context.workingOffset++] = 0x18; // CLC
                    outRom[context.workingOffset++] = 0x63; // ADC $01,S - original damage
                    outRom[context.workingOffset++] = 0x01;
                }
                outRom[context.workingOffset++] = 0xAA; // TAX - temporarily retain product
                outRom[context.workingOffset++] = 0x68; // PLA - discard original damage
                outRom[context.workingOffset++] = 0x8A; // TXA - restore product
                outRom[context.workingOffset++] = 0xFA; // PLX - restore target record

                // Divide the 16-bit product by 20 through the SNES hardware divider. Long
                // addressing avoids assumptions about the caller's data-bank register.
                outRom[context.workingOffset++] = 0x8F; // STA.l $004204 - dividend
                outRom[context.workingOffset++] = 0x04;
                outRom[context.workingOffset++] = 0x42;
                outRom[context.workingOffset++] = 0x00;
                outRom[context.workingOffset++] = 0xE2; // SEP #$20
                outRom[context.workingOffset++] = 0x20;
                outRom[context.workingOffset++] = 0xA9; // LDA #$14 - divisor 20
                outRom[context.workingOffset++] = 0x14;
                outRom[context.workingOffset++] = 0x8F; // STA.l $004206
                outRom[context.workingOffset++] = 0x06;
                outRom[context.workingOffset++] = 0x42;
                outRom[context.workingOffset++] = 0x00;
                for(int i = 0; i < 8; i++)
                {
                    outRom[context.workingOffset++] = 0xEA; // wait at least 16 cycles
                }
                outRom[context.workingOffset++] = 0xC2; // REP #$20
                outRom[context.workingOffset++] = 0x20;
                outRom[context.workingOffset++] = 0xAF; // LDA.l $004214 - quotient
                outRom[context.workingOffset++] = 0x14;
                outRom[context.workingOffset++] = 0x42;
                outRom[context.workingOffset++] = 0x00;
                outRom[context.workingOffset++] = 0xD0; // BNE return
                int nonzeroResultBranchOffset = context.workingOffset++;
                outRom[context.workingOffset++] = 0x1A; // INC A - nonzero input/percent stays at least 1

                int returnOffset = context.workingOffset;
                outRom[nonzeroResultBranchOffset] = relativeBranch(nonzeroResultBranchOffset, returnOffset);
            }

            int scalerReturnOffset = context.workingOffset;
            outRom[playerTargetBranchOffset] = relativeBranch(playerTargetBranchOffset, scalerReturnOffset);
            outRom[enemyCasterBranchOffset] = relativeBranch(enemyCasterBranchOffset, scalerReturnOffset);
            outRom[zeroDamageBranchOffset] = relativeBranch(zeroDamageBranchOffset, scalerReturnOffset);
            outRom[context.workingOffset++] = 0x6B; // RTL

            int firstWrapperAddress = emitStoreWrapper(outRom, context, scalerAddress, true);
            int secondWrapperAddress = emitStoreWrapper(outRom, context, scalerAddress, false);
            patchStore(outRom, FIRST_FINAL_DAMAGE_STORE_OFFSET, firstWrapperAddress);
            patchStore(outRom, SECOND_FINAL_DAMAGE_STORE_OFFSET, secondWrapperAddress);

            Logging.log("Player magic damage final-store hooks: $C8/EB90 and $C8/E9F6; scaler at $" +
                ((scalerAddress >> 16) & 0xFF).ToString("X2") + "/" + (scalerAddress & 0xFFFF).ToString("X4") + ".");
            return true;
        }

        private static int emitStoreWrapper(byte[] outRom, RandoContext context, int scalerAddress, bool restoreA4Load)
        {
            int wrapperAddress = context.workingOffset + 0xC00000;
            outRom[context.workingOffset++] = 0x22; // JSL scaler
            outRom[context.workingOffset++] = (byte)scalerAddress;
            outRom[context.workingOffset++] = (byte)(scalerAddress >> 8);
            outRom[context.workingOffset++] = (byte)(scalerAddress >> 16);
            outRom[context.workingOffset++] = 0x9D; // displaced: STA $E1F1,X
            outRom[context.workingOffset++] = 0xF1;
            outRom[context.workingOffset++] = 0xE1;
            if(restoreA4Load)
            {
                outRom[context.workingOffset++] = 0xA5; // displaced: LDA $A4
                outRom[context.workingOffset++] = 0xA4;
            }
            else
            {
                outRom[context.workingOffset++] = 0xE2; // displaced: SEP #$20
                outRom[context.workingOffset++] = 0x20;
            }
            outRom[context.workingOffset++] = 0x6B; // RTL
            return wrapperAddress;
        }

        private static void patchStore(byte[] outRom, int offset, int wrapperAddress)
        {
            outRom[offset] = 0x22; // JSL wrapper
            outRom[offset + 1] = (byte)wrapperAddress;
            outRom[offset + 2] = (byte)(wrapperAddress >> 8);
            outRom[offset + 3] = (byte)(wrapperAddress >> 16);
            outRom[offset + 4] = 0xEA;
        }

        internal static int resolvePercentage(string mode, int fixedPercentage, Random random)
        {
            if(mode == MODE_VANILLA)
            {
                return 100;
            }
            if(mode == MODE_FIXED)
            {
                validatePercentage(fixedPercentage);
                return fixedPercentage;
            }
            if(mode == MODE_RANDOM)
            {
                if(random == null)
                {
                    throw new ArgumentNullException("random");
                }
                return MIN_RANDOM_PERCENT + random.Next(((MAX_RANDOM_PERCENT - MIN_RANDOM_PERCENT) / PERCENT_STEP) + 1) * PERCENT_STEP;
            }
            throw new ArgumentException("Unknown player magic damage mode: " + mode, "mode");
        }

        internal static int scaleDamage(int damage, int percentage)
        {
            if(damage < 0)
            {
                throw new ArgumentOutOfRangeException("damage");
            }
            validatePercentage(percentage);
            if(damage == 0 || percentage == 0)
            {
                return 0;
            }
            int scaled = (int)(((long)damage * percentage) / 100);
            return Math.Max(1, scaled);
        }

        private static void validatePercentage(int percentage)
        {
            if(percentage < 0 || percentage > 100 || percentage % PERCENT_STEP != 0)
            {
                throw new ArgumentOutOfRangeException("percentage", "Player magic damage must be from 0 through 100 in 5% steps.");
            }
        }

        private static string displayMode(string mode)
        {
            return Char.ToUpperInvariant(mode[0]) + mode.Substring(1);
        }

        private static byte relativeBranch(int operandOffset, int targetOffset)
        {
            int displacement = targetOffset - (operandOffset + 1);
            if(displacement < sbyte.MinValue || displacement > sbyte.MaxValue)
            {
                throw new InvalidOperationException("Player magic damage generated branch is out of range.");
            }
            return unchecked((byte)(sbyte)displacement);
        }
    }
}
