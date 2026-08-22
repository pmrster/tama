# Tama log-format specification

Normative for BOTH implementations (Swift `Sources/TamaCore`, C# `windows/Tama.Core`).
Fixtures in `spec/fixtures/` are canonical: each implementation's conformance test must
produce the values in `spec/fixtures/expected.json` from them. Change behavior here first,
then fix both implementations against the fixtures.

## The two numbers (never conflate)

1. **Cumulative `tokens`** — total tokens processed in the window (incl. cache reads),
   summed from per-hour buckets. Feeds tooltips and the TODAY bar.
2. **Live `contextTokens` / `contextWindow`** — current context-window occupancy
   (last turn's input side + its output), clamped fraction = contextTokens/contextWindow.

## Claude Code — `<claude-root>/projects/<proj>/<session>.jsonl`

One JSON object per line. Relevant line shapes:

- `{"type":"summary","summary":"<title>"}` → session title (highest priority). Multiple
  `summary` lines can appear in one file; the LAST one wins (both implementations simply
  overwrite the title on each sighting, in file order).
- `{"type":"user","isMeta":<bool?>,"timestamp":ISO8601,"cwd":path,"sessionId":uuid,
   "message":{"role":"user","content":string | [{"type":"text","text":...} |
   {"type":"tool_result",...}]}}`
- `{"type":"assistant","isSidechain":<bool?>,"timestamp":ISO8601,"cwd":path,
   "sessionId":uuid,"message":{"id":"msg_x","model":str,"usage":{"input_tokens":n,
   "output_tokens":n,"cache_read_input_tokens":n,"cache_creation_input_tokens":n,
   "cache_creation":{"ephemeral_1h_input_tokens":n}}}}`

Rules:
- **Dedup by `message.id`:** Claude v2.x writes one reply as several lines (one per content
  block) repeating the same `usage`. Count usage AND the message ONCE per id; skip the whole
  line on a repeated id. Assistant lines without an id are counted every time.
- **Timestamps:** must be internet date-time WITH fractional seconds and an explicit timezone
  designator (e.g. `2026-06-19T09:00:00.000Z`); lines with other timestamp shapes (no
  fractional seconds, no offset) are not usage-bearing (Swift `ISO8601DateFormatter`
  `.withInternetDateTime + .withFractionalSeconds` semantics — both required, no lax fallback).
- **Cumulative tokens:** sum `input + output + cache_read + cache_creation` per hour bucket
  (`hourKey = trunc(unixSeconds/3600)`, i.e. truncation toward zero, not `floor` — the two
  differ only for timestamps before 1970). Sidechain lines DO count here.
- **`cacheWrite1h`:** `usage.cache_creation.ephemeral_1h_input_tokens`, tracked as a subset
  of cacheWrite for pricing (1h cache = 2× input rate vs 1.25× for 5m).
- **Context:** from the LATEST line where `isSidechain != true` (by timestamp, `>=` wins):
  `input + cache_read + cache_creation + output`.
- **Context window:** logs don't carry it. Default 200_000; promote to 1_000_000 when the
  lowercased model id contains `[1m]` or `-1m`, or occupancy > 200_000.
- **Messages** (the `/resume` count): +1 per `type=="user"` line with `isMeta != true`
  (tool_result user lines DO count); +1 per distinct assistant reply (id-deduped).
- **Model:** `message.model` of the latest usage-bearing line (`>=` wins).
- **Folder:** `cwd` of usage-bearing lines (last one wins). No usage-bearing line with a
  non-empty `cwd` → the file yields NO session.
- **Session id:** first `sessionId` seen on a usage-bearing line, first 8 chars; fallback:
  first 8 chars of the filename (without extension).
- **Title fallback:** first real user prompt — `message.content` as string, or joined
  `text` blocks; a content array containing any `tool_result` block is NOT a prompt.
  Clean: trim; reject if starts with `<` or `[Request interrupted`; collapse whitespace
  runs to single spaces; if > 80 chars, cut to 80, trim trailing spaces, append `…`. The
  80-char cap counts extended grapheme clusters (user-perceived characters, Swift
  `String.count`), NOT UTF-16 code units — a multi-unit character (e.g. most emoji) is one
  character toward the cap, and truncation must never split one mid-code-unit.

## Codex — `<codex-root>/sessions/YYYY/MM/DD/rollout-*.jsonl`

Line shapes (`payload` nested under each line's `type`):
- `{"type":"session_meta","payload":{"id":uuid,"cwd":path}}` → folder (first non-empty),
  session id (first 8 chars).
- `{"type":"turn_context","payload":{"model":str}}` → model (last wins).
- `{"type":"event_msg","payload":{"type":"user_message","message":str}}` → title source.
- `{"type":"response_item","payload":{"type":"message","role":"user"|"assistant",
   "content":[{"type":"input_text","text":str}]}}` → messages count (+1 for role
   user/assistant only); also title source for role=user via joined `input_text` blocks.
- `{"type":"event_msg","payload":{"type":"token_count","info":{
   "total_token_usage":{"input_tokens":n,"cached_input_tokens":n,"output_tokens":n},
   "last_token_usage":{"input_tokens":n,"output_tokens":n},
   "model_context_window":n}}}` → the LAST such line wins entirely.

Rules:
- **Cumulative:** from last `total_token_usage`: breakdown = input−cached / output / cached
  as cacheRead / 0 cacheWrite. Whole breakdown lands in ONE hour bucket at the file's mtime
  (session-cumulative, all-or-nothing).
- **Context:** `last_token_usage.input_tokens + output_tokens` (input already includes cached).
- **Window:** `model_context_window` when > 0.
- **Title:** first `user_message` (or role=user message item): strip everything through
  `## My request for Codex:` if present, then the same Clean rules as Claude.
- **Last activity:** the file's mtime. No `session_meta.cwd` → NO session.

## Gemini — `<gemini-root>/tmp/<hash>/`

Per subdirectory: folder = trimmed content of `.project_root` (≤ 8 KiB; empty → skip);
last activity = `logs.json` mtime, else the subdirectory's mtime. No tokens (all zero).

## Antigravity — `<gemini-root>/antigravity-cli/history.jsonl`

Lines `{"workspace":path,"timestamp":msEpoch}` (≤ 16 MiB read). One session per distinct
workspace, last activity = max timestamp (ms → seconds). No tokens.

## Ollama — server.log (tail ≤ 256 KiB)

No per-line model tag: attribute lines by SEGMENTING between runner events.
- Start: a line containing `runner subprocess` AND `starting`, with `model=<tag>`
  (tag = up to the next whitespace). Sets the active AND current model; same tag
  re-loaded merges into one entry (first-seen order preserved).
- Stop: a line containing the verbatim `stopping mlx runner subprocess` clears both.
  (llama.cpp runners that never emit this line simply hand over at the next start.)
- Unattributed lines (before any start / after a stop) are dropped.

Per-segment accumulation (last value wins unless noted):
- `n_ctx_slot = <int>` → contextWindow; `task.n_tokens = <int>` → contextTokens;
  `tg = <float>` → tokensPerSecond.
- `processing task` → busy=true; `all slots are idle` → busy=false.
- `[GIN] yyyy/MM/dd - HH:mm:ss | status | <duration> | ip | METHOD "<endpoint>"`:
  only `/embed*`, `/api/chat`, `/api/generate` count as inference (requestCount+1,
  chat/embed tally). Duration = Go format (`5.0s`/`200ms`/`µs`|`us`/`ns`) → lastLatency.
  Timestamp carries no zone: parse in the injected zone → lastActivity.
- kind = embed if embedCount > chatCount, else chat if chatCount > 0, else unknown.

Output: models sorted current-first, then lastActivity desc. Status lastActivity =
log file mtime. `running` comes from the process table, not the log.
Missing/empty log → no status.

## Scan behavior (window filtering — implemented by the scanner, Plan B for C#)

- A file contributes only if its mtime is in-window (`today` = same local day as `now`;
  `last24h` = within trailing 24h). Codex looks back 14 day-folders (a live session keeps
  appending to its start-date file).
- Windowed tokens = sum of hour buckets at/after the cutoff hour (today → start-of-day
  hour; last24h → now − 24h hour).
- Parse cache keyed by `(mtime, size)` per file path.
- Sessions sorted by last activity, newest first, capped at `limit` (default 16);
  totals/breakdowns are computed over ALL in-window entries, not just the displayed cap.

## Safety (both implementations)

Read-only opens that never block the writing agent; reject non-regular files and reparse
points/symlinks on files and directories; size caps above; malformed JSON lines skipped;
never build a filesystem read path from log content (`cwd` is display-only).

## Plan limits — session / weekly quota (macOS first; Windows port TODO)

Per-account subscription limits, read from what the CLIs already write. No network, no
credential files. There are no `spec/fixtures/` cases for this yet, so it is NOT part of the
cross-impl conformance test; the shapes below are still normative for any implementation.

Two numbers per account window: `usedPercent` (0…100, clamp) and `resetsAt` (a window is
"expired" — display-dimmed — once `resetsAt < now`). Window kinds: `session` (~5h),
`weekly` (7d), `scoped(<name>)` (provider extra, e.g. Claude per-model weekly).

### Codex — `<codex-home>/sessions/YYYY/MM/DD/rollout-*.jsonl`

The LAST `token_count` event carrying a `payload.rate_limits` block, in the most recently
modified rollout (look back 14 day-folders; try the newest few, skipping ones with no
`rate_limits` yet). Shape:

```
payload.rate_limits {
  plan_type: "plus" | "pro" | "team" | …,
  primary:   { used_percent: n, window_minutes: n, resets_at: <epoch seconds> },
  secondary: { … } | null
}
```

`window_minutes` → kind: `< 1440` → `session`; `10080` → `weekly`; else `scoped("<days>d")`.
`plan_type` → prettified ("plus" → "Plus"). Identity (email) is NOT taken — it lives only in
`auth.json`, which is never read.

### Claude Code — `<claude-config-dir>/.claude.json` (default: `~/.claude.json`)

Parse ONLY these two top-level keys; retain nothing else (the file also holds per-project
prompt history under `projects` — never read it):

```
oauthAccount { emailAddress, organizationType: "claude_max"|…, organizationRateLimitTier: "default_claude_max_5x"|… }
cachedUsageUtilization {
  fetchedAtMs: <ms>, accountUuid,
  utilization {
    five_hour  { utilization: <percent>, resets_at: <ISO8601, any fractional precision> },
    seven_day  { … },
    seven_day_opus | seven_day_sonnet { … } | null   // → scoped("Opus"/"Sonnet")
  }
}
```

This is Claude Code's own `/usage` cache; it refreshes on Claude's schedule, so `fetchedAtMs`
can be > a day old — display "as of …" and stale-dim. Plan name = org type minus the `claude_`
prefix, plus the tier's trailing `Nx` multiplier ("claude_max" + "…_5x" → "Max 5x").

### Statusline bridge (opt-in) — `<app-support>/Tama/statusline/<label>.json`

The documented Claude Code status-line JSON, mirrored to a file by the user's statusline
command (`default.json` for the default account; `<label>.json` per extra account). Read
`rate_limits.five_hour.used_percentage` + `.resets_at` (epoch s) and the `seven_day` equivalent;
`fetchedAt` = file mtime. Preferred over the `.claude.json` cache for an account when it is
newer; identity/plan still come from `.claude.json`.
