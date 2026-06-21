# Changelog

## Unreleased

## 0.2.2 — 2026-06-21

- The packaged `.app` now carries a valid signature: `prices.json` ships only in
  `Contents/Resources` (a stray copy at the bundle root made the app unsignable), and the
  build signs ad-hoc when no Developer ID is set. This stops macOS reporting a downloaded
  build as "damaged" and makes the app notarization-ready.
- The DMG now opens with **Tama** on the left and **Applications** on the right
  (deterministic, committed layout — no Finder automation needed at build time).
- Add optional code-signing + notarization to the packaging script
  (`SIGN_IDENTITY` / `NOTARY_PROFILE`, `REQUIRE_NOTARIZATION=1` for release builds);
  unsigned-but-ad-hoc-signed builds still work.
- Read the bundled `prices.json` through `SafeFileReader` (size cap + symlink/regular-file
  check), so every disk read is on the one hardened path.
- Hardened log readers against symlinked, non-regular, and oversized files.
- Add CI (tests, secret scan, dependency review, CodeQL), Dependabot, and a privacy policy.
- Clarified install + publish docs around local-only behavior and manual packaging.
