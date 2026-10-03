# Contributing

Bug reports and compatibility updates are welcome.

Before reporting an installer problem:

1. Fully quit Garry's Mod.
2. Run Steam Verify.
3. Retry the latest Sticky Blood release.
4. Include your operating system, launch option, installer output, and the SHA-256 hashes of `bin/win64/studiorender.dll` and `bin/win64/engine.dll`.

Do not upload or attach Valve DLLs. Hashes and byte signatures are sufficient for compatibility work.

Changes should preserve the installer's fail-closed behavior: unknown hashes or unexpected bytes must be rejected rather than patched speculatively.
