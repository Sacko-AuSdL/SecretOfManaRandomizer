# Alpha 0.1 RC4 clean Windows acceptance

**Status: NOT RUN.** Relocated command-line checks on a developer machine do not
count as a clean environment. No clean Windows VM/profile was supplied.

Use a fresh Windows VM or a genuinely separate clean machine, with no Visual
Studio, SDK, repository, developer NuGet cache or previous randomizer config.
.NET Framework 4.6.2 is the minimum target; a supported later 4.x installation
(such as the Windows-provided 4.8 runtime) is recommended. Record the exact
Windows/runtime version. Take a VM snapshot before installing anything.

1. Copy only the RC ZIP; record/verify its SHA-256. Extract the entire ZIP to a
   writable folder with a space and, if possible, a non-ASCII character in its
   name. Verify the file hashes against `SHA256SUMS.txt` before running.
2. Launch `SoMRandomizer.exe` without administrator privileges. Confirm no DLL,
   resource, framework or developer-path error. Record any security prompt;
   this private build is not claimed to be code-signed.
3. Select your own unmodified US Secret of Mana v1.0 ROM (2 MiB, optionally a
   512-byte copier header). The package must not supply a game image.
4. Select Open World and paste a supplied starter options string. Confirm visible
   labels and values, especially Orb mode, Spell Shuffle, Cannon mode, location,
   Free Cannon and fixed magic percentage. Change options, copy them, restart
   the app and paste them back; verify exact restoration. Exercise preset
   save/load if using presets. Record display scaling and keyboard behavior.
5. Generate the supplied Short seed to a new output folder/filename. Require a
   4 MiB output and successful generation log. Repeat into a DIFFERENT folder;
   hashes must match. Confirm no repository access or extra downloads are needed
   for generation. Optional update-check network failure must not block it.
6. Try a missing/invalid base ROM and a non-writable output location. Confirm the
   app gives an understandable failure rather than silently reporting success.
   Preserve the actual message if it does not.
7. Load the generated game in your chosen emulator. Start NEW gameplay, obtain
   the Sword normally, and verify no manual teleport or debug gear. Continue the
   acceptance run to its actual goal using the supplied checklist.
8. Test ordinary saves, fourth-slot autosave, alive/death/boss-music soft reset
   and reload. Verify music, sound effects, party defeat and completed-boss
   re-entry. Use separate saves per configuration and package version.

Return package/EXE/ROM hashes, seed/options, Windows/.NET/emulator versions,
pass/fail for every step, screenshots and reproducible failures to the maintainer.
Do not share the base or generated ROM. Steps 1-6 are the distribution/GUI smoke
check; steps 7-8 and complete runs are further gameplay coverage. Full personal
completion of all three configurations is not required before inviting Alpha
volunteers after technical checks and explicit release approval.
