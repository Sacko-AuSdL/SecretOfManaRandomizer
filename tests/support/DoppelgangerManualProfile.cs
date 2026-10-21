using System;
using System.Collections.Generic;

// Manual-ROM scaffolding only; not compiled into the randomizer. Keep the
// profile shared with its permanent tests instead of unchecked local gear IDs.
public static class DoppelgangerManualProfile
{
    public const byte Head = 0x11; // Cockatrice Cap
    public const byte Body = 0x26; // Vestguard
    public const byte Accessory = 0x3D; // Amulet Ring
    public const byte WeaponRank = 6;
    public const byte Proficiency = 0x66; // two level-6 nibbles

    public static ushort Immunity(byte[] rom, byte head, byte body, byte accessory)
    {
        int result = 0x0800; // Native $C0:4AF6 mandatory immunity bit.
        foreach (byte id in new[] { head, body, accessory })
        {
            int at = 0x103ED0 + id * 10;
            result |= rom[at + 7] | (rom[at + 8] << 8);
        }
        return (ushort)result;
    }

    public static void Validate(byte[] rom, int slot, byte head, byte body, byte accessory)
    {
        if (slot < 0 || slot > 2 || head < 1 || head > 0x14
            || body < 0x16 || body > 0x29 || accessory < 0x2B || accessory > 0x3E)
            throw new ArgumentException("Invalid manual-profile equipment/category.");
        foreach (byte id in new[] { head, body, accessory })
            if ((rom[0x103ED0 + id * 10 + 5] & (0x80 >> slot)) == 0)
                throw new ArgumentException("Manual-profile gear is not wearable by this physical slot.");
        if ((Immunity(rom, head, body, accessory) & 0x8000) != 0)
            throw new ArgumentException("Manual-profile gear must not grant death immunity.");
    }

    public static void ApplyEquipment(byte[] rom)
    {
        for (int slot = 0; slot < 3; slot++)
        {
            // Validate FINAL ROM permissions, including randomized gameplay roles.
            Validate(rom, slot, Head, Body, Accessory);
            int at = 0x57BD + slot * 4;
            rom[at] = Head; rom[at + 1] = Body; rom[at + 2] = Accessory;
        }
    }

    public static void AddSupplies(List<byte> ready, bool reverse)
    {
        if (ready.Count == 0 || ready[ready.Count - 1] != 0)
            throw new ArgumentException("Unexpected startup event tail.");
        var supplies = new List<byte>();
        for (byte slot = 0; slot < 3; slot++)
        {
            // Native $39 selectors are 1/2/3 for Boy/Girl/Sprite. Zero means
            // the current event actor, not an independently addressed player.
            byte selector = (byte)(slot + 1);
            supplies.AddRange(new byte[] { 0x39, selector, 0x87, 99, 0x39, selector, 0x86, 99 });
            // Native per-player weapon/magic level nibbles; no HP, KO or
            // immunity writes and no invincibility. Equipment can be removed.
            for (byte attribute = 0xC0; attribute <= 0xC7; attribute++)
                supplies.AddRange(new byte[] { 0x39, selector, attribute, Proficiency });
        }
        // Native ADD_INVENTORY_ITEM weapon encoding: $80 + family*9 + rank.
        // $C0:655F-$6577 divides by nine and replaces that family's forged rank.
        for (int weapon = 0; weapon < 8; weapon++)
            supplies.AddRange(new byte[] { 0x1E, (byte)(0x80 + weapon * 9 + WeaponRank) });
        supplies.AddRange(new byte[] { 0x1F, 8, 0x2F, 0x44 }); // refresh weapons / heal
        foreach (byte item in new byte[] { 0x40, 0x41, 0x42, 0x43, 0x45 })
            for (int count = 0; count < 4; count++) supplies.AddRange(new byte[] { 0x1E, item });
        supplies.AddRange(reverse ? new byte[] { 0x1B, 0x04 } : new byte[] { 0x18, 0x8D });
        ready.InsertRange(ready.Count - 1, supplies);
    }
}
