# Expanded Open World Alpha 0.1 RC4 — known limitations

This is an unofficial, unsigned community playtest build, not an upstream stable
release. Use a new game and separate ordinary saves/save states for each ROM.

- Boss compatibility is deliberately bounded. Some encounters use private arena
  copies while retaining the entered location's prize/progression/return.
  Dragon Worm's shadow encounter uses a recognizable copy of its own clearing.
  The other five Pure Lands shadow placements still use donor rooms and may
  include a brief completed-entry return transition. Report any wrong position,
  lost control, repeated fight or repeated reward; they were not converted in
  the Dragon Worm fix.
- A defeated shadow can occasionally leave a nonblocking ghost visual with
  three Sprite gameplay roles. Previously reported encounters still completed.
- The maintainer has accepted the focused Doppelganger/Death Link/scaling,
  Jehk, save/reset and Dragon Worm ArenaFix2 cases in Mesen. That does not mean
  every supported boss pairing, party configuration or full seed was played.
- Clean Windows GUI installation, unusual display scaling, other emulators and
  flash hardware still need human coverage. Packaged CLI checks on the development
  machine are not a clean-machine GUI test.
- The application/ROM retain upstream numeric version 1.49. Identify this build
  as Alpha 0.1 RC4 and include its EXE/ROM hashes in reports.
- Only Open World is qualified for this playtest. Cannon Chaos is not the
  separate legacy Chaos game mode.
- The CLI may exit successfully even when generation fails. Require a valid
  output and `Done!` plus successful simulation in its log.
- Weapon Power, generic direct-placement experiments, the historical Frost
  donor pilot, Weapon Master/Fortress weapon gates and harder Manabite combat
  are excluded. Approved production Jehk Gigas replacements ARE included.

Never share base/generated game ROMs. Preserve a pre-failure save, complete
settings, seed, emulator version and exact steps. Redact private paths from logs.
