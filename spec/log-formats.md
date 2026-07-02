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

- `{"type":"summary","summary":"<title>"}` → session title (highest priority).
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
- **Cumulative tokens:** sum `input + output + cache_read + cache_creation` per hour bucket
  (`hourKey = floor(unixSeconds/3600)`). Sidechain lines DO count here.
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
  runs to single spaces; if > 80 chars, cut to 80, trim trailing spaces, append `…`.

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
