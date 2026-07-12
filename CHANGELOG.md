# Changelog

## Unreleased

## 0.4.0 — 2026-07-12

- **Usage section, round 2:** a 7×24 weekday×hour **activity heatmap** (Claude-only — Codex logs
  carry no per-turn timestamps; last ~30 days, your local time, computed live and never persisted);
  a **token-mix bar** showing fresh vs cache-read vs cache-write, exposing that cache re-reads
  dominate the token count but cost ~0.1× input; **7d/30d spend delta** vs the prior equal window
  (↑/↓%, hidden until there's enough history); and **click a histogram bar** to drill into a single
  day's breakdown. All still read-only, local-only, no network.

## 0.3.0 — 2026-07-12

- New **Usage** section at the top of the dashboard: Today / 7d / 30d estimated cost + token
  tiles, expandable into a 30-day daily-cost histogram and per-model / per-provider /
  per-project breakdowns (Fable and every other priced tier appear per model). History is
  hybrid: a read-only back-scan of up to 30 days of Claude/Codex logs, merged with rollups the
  app persists in its own `~/Library/Application Support/Tama/history.json` so days that age
  out of the agents' log retention survive. Cost is never persisted — always re-priced from
  tokens at current rates. Plan-quota ("% left") is deliberately absent: it would require the
  network.
- Optional local notifications, **both off by default** (the permission prompt only appears on
  first opt-in in Settings): an alert when a streaming agent goes quiet for 3+ minutes (likely
  waiting for input), and a warning when a session's context window passes 85% (re-arms below
  75%). Local `UserNotifications` only — no network.
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
