# Alpha 0.1 release readiness

The proposed public Alpha is the RC3 build and its exact source on
`release/alpha-0.1`, based on `1fabbb3`. It is an unofficial experimental fork,
not a stable or upstream release.

## Technical scope

Approved Open World functionality is retained: Sandship, conservative special
boss adapters, Mantis/Jehk Doppelgangers, independent Triple Tonpole/Ice Palace,
Crystal Orb Off/Mixed/Weapon Only, Per Character/Party Spell Shuffle, destination
spirit affinity, Cannon Off/Open/Shuffle/Chaos, travel QoL/Kakkara, reduced
forging, player magic scaling, cosmetic Manabite and persistent music restoration.

Weapon Power, direct-arena prototypes and the Frost/Jehk pilot are excluded from
both source and compiled production code. Public Random/Swap/plando eligibility
is not expanded. Native map/data ownership protections remain intact.

RC2's package is archived unchanged but superseded due to its known Kakkara
progression softlock. RC3 changes only the geographic ownership of physical
Potos/Pandora checks; Luna remains Flammie-gated. The isolated source check uses
38 production suites, adding Kakkara and Luna regressions to the inherited 36.
Only the excluded manual-profile scaffolding test is omitted. Source hashes, registry pairings,
four fixtures, normal control worlds, starter worlds, serialization and dependency
checks are required before declaring the local release tip verified.

## Remaining gates

- Clean Windows GUI smoke: dependencies, ordinary-user startup, options
  save/load/paste, error handling and generation without SDK/repository access.
- Separate authorization for push, tag, GitHub pre-release and Discord posting.
- Volunteer full Open World runs and wider emulator/hardware/save/re-entry
  coverage remain important. Personal completion of every starter world is not
  a prerequisite for inviting Alpha volunteers.

Tomm (Discord) is credited for Manabite; creator permission for use and
redistribution is confirmed. Optional new credit details are not a blocker.
The occasional defeated-shadow ghost visual remains a known limitation.
