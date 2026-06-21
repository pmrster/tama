# Changelog

## Unreleased

## 0.2.2 — 2026-06-21

- Read the bundled `prices.json` through `SafeFileReader` (size cap + symlink/regular-file
  check), so every disk read is on the one hardened path.
- Add optional code-signing + notarization to the packaging script
  (`SIGN_IDENTITY` / `NOTARY_PROFILE`); unsigned builds still work and warn.
- Hardened log readers against symlinked, non-regular, and oversized files.
- Clarified publish docs around local-only behavior and manual packaging.
- Removed release automation until the project needs it.
