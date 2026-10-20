# Alpha 0.1 publication plan

Local release branch: `release/alpha-0.1`.
Base: `1fabbb3741a4b6843d25ef933a6a0985c5fe2f1f`.
Proposed first public Alpha tag: `v0.1.0-alpha.1`.
The intended artifact is RC3; candidate numbering and public tag numbering are
separate. No tag, push, publication or Discord posting is authorized yet.

The source manifest, package hashes, eligibility and exclusions are documented
in AlphaReleaseCandidate.md. Commit scope: approved boss/registry integration
and regressions; dependency/lock update; public docs/credits/provenance and
portable maintenance scripts. No experiments or generated artifacts are added.

## After separate publication approval

Verify that the branch tip equals the hash in the final local verification
handoff. From the isolated release checkout, run these as individual commands:

```powershell
git push -u origin release/alpha-0.1
git tag -a v0.1.0-alpha.1 release/alpha-0.1 -m "Alpha 0.1 — unofficial RC3"
git push origin refs/tags/v0.1.0-alpha.1
```

Do not use force, push the development branch, or push to upstream.
The branch currently has no tracking target; `push -u` will establish its own
origin tracking without changing the development branch's upstream.

In https://github.com/Sacko-AuSdL/SecretOfManaRandomizer open Releases and draft
a new release using the EXISTING approved tag. Title:
**Alpha 0.1 — unofficial Open World playtest (RC3)**.
Paste `release/GitHubReleaseNotes.md`, mark **Pre-release**, and do not mark it
the latest stable release. Upload the new RC3 ZIP and its SHA-256 sidecar,
not the rebuilt verification executable or any ROM/log. Check the expected ZIP
hash before upload:

Use the exact RC3 hash in the final handoff and ZIP sidecar. Do not upload RC2;
it retains the known Kakkara progression softlock and is archived only.

Publish only after the clean Windows GUI smoke check and explicit approval.
Copy the actual resulting release/download link into
`release/DiscordAnnouncement.md`; no live URL is claimed in this repository.
Post the reviewed announcement only after authorization.

## Credits and tester policy

This is an unofficial fork of Moppleton's randomizer, not an upstream release.
Manabite credit: Tomm (Discord), with creator use/redistribution permission
confirmed by the maintainer. No further name, URL or license is invented.
No additional attribution condition is known or made into a new blocker.

We seek volunteers for full normal Open World runs. Personal completion of all
starter worlds is not required before inviting them after technical checks.
Moppleton's recommendation to distribute experimental fork builds is reported
by the maintainer. No new author/community contact or weekly is claimed.
