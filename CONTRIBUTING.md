# Contributing

Bug reports and compatibility updates are welcome.

Before reporting an installer problem:

1. Fully quit Garry's Mod.
2. Run Steam Verify.
3. Retry the latest Sticky Blood release.
4. Include your operating system, launch option, installer output, and the SHA-256 hashes of `bin/win64/studiorender.dll` and `bin/win64/engine.dll`. If the installer says the build is unsupported, include the output of `install --dry-run` (Windows: `install.bat -DryRun`).

Do not upload or attach Valve DLLs. Hashes and byte signatures are sufficient for compatibility work.

Changes should preserve the installer's fail-closed behavior: a missing, ambiguous, or unexpected signature must be rejected rather than patched speculatively.
