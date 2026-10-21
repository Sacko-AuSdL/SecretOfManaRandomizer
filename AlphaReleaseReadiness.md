# Alpha 0.1 RC4 release readiness

The candidate is an unofficial experimental Expanded Open World playtest.
It integrates the accepted Doppelganger expansion into the existing RC3 release
checkout; no branch, checkout, commit or tag was created for preparation.

Included: 18 Doppelganger locations, 17 Jehk choices, optional Death Link,
corrected scaling and save/return safety, plus the accepted RC3 travel, magic,
Orb, party, Sandship, special boss, cosmetic and music features.
Weapon Power and direct-placement prototype catalogues/pilots are excluded.

Release build, locked restore, live dependency audit and all 45 final production
suites passed. Package/source/runtime hashes, normal CLI starter worlds and
extracted execution must pass before the package is handed off. The final
handoff records their actual outcomes and RC4 ZIP checksum.

Remaining review/publication steps:

- Manual review of the new ZIP and release/Discord drafts.
- Clean Windows GUI smoke (not replaced by headless UI/CLI verification).
- Separate explicit authorization for any commit, push, new tag or publication.
- Broader volunteer full runs and emulator/hardware coverage; not every boss
  pairing or party combination has an exhaustive completion claim.

Preserve the existing RC3 artifact and alpha.1 tag. Remote tag status is
unverified in this preparation; the blocked lookup was not retried.
The known ghost visual and remaining Pure Lands donor-return limitations are
documented honestly in AlphaKnownIssues.md.
