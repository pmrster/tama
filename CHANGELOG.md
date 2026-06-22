# Changelog

## Unreleased

- Detect a locally-running **Ollama** server and show it as its own collapsible group —
  **Ollama → each model used this session** — separate from the project-grouped agent sessions,
  marked `local · free` (local inference has no cost). Presence comes from a read-only,
  comm-filtered process query (argv is read only for `ollama` processes, not all ~900). Per-model
  activity is parsed from a read-only tail of `~/.ollama/logs/server.log`, segmented between runner
  load/unload events: per model we show last-used, request count, last-request latency, and
  chat-vs-embed — plus a context gauge, throughput (tok/s), and live busy state **when the backend
  reports them**. Note: the **MLX** runner (Apple-Silicon `-mlx` models) logs none of context /
  throughput / busy markers, so those stay blank for MLX models; `.gguf` (llama.cpp) runners
  populate them fully. No network call is made (the Ollama HTTP API is never opened) and
  `~/.ollama/history` is never read; the group is hidden when no server is running.
  `SafetyNoWriteTests` covers the new reader.

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
