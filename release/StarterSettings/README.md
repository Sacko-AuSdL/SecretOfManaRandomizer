# Unofficial Alpha 0.1 RC2 normal gameplay configurations

Volunteer full-run coverage is pending; personal completion is not a prerequisite for joining the playtest. Paste the entire corresponding .options.txt line into the Open World options box.
Seed strings intentionally retain RC1 labels for exact RC1/RC2 comparison. These are RC2 package profiles, not RC1 binaries.
Files use the actual UI options serializer, with version=1.49 and mode=open; omitted options reset to this package's defaults.
The exact source/build/hash fixes those default definitions; no plando, bootstrap or manual teleport is enabled.
All three options strings passed headless UI-binding save/load round trips, not a clean-machine visual UI test.

## Short

Seed: `Alpha01-RC1-Short`. Goal: Vanilla Short.

Normal Sword acquisition; find the other characters and Flammie through checks; obey the cached Mixed Orb requirements and shuffled spirit slots; Short goal uses the shortened Fortress route to Mana Beast.

Known limits: Destination-owned boss returns must be checked; no newly generated full playthrough has been completed.

## Long

Seed: `Alpha01-RC1-Long`. Goal: Vanilla Long.

Normal Kakkara startup Door 082, no manual teleport; Upper Land information is informational, not necessarily mandatory. Cannon works at zero GP. Complete Long-goal Palace/Fortress progression and the final Mana Magic/Mana Beast sequence.

Known limits: Weapon-family Orb requirements do not use Weapon Power. Test both ordinary and autosave reloads before and after special bosses.

## ThreeSprites

Seed: `Alpha01-RC1-ThreeSprites`. Goal: Vanilla Short.

All three physical characters start with Sprite gameplay roles using the normal party setting, not debug grants. Spirit slots/layouts remain per physical caster. Follow the simulated Chaos Cannon/Flammie network; confirm reserved Dryad Mana Magic and normal party defeat.

Known limits: A defeated shadow may leave a nonblocking ghost visual. Three Sprite roles are not three Sprite appearance sprites. No new direct-arena prototype is enabled.

