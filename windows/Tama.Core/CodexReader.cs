using System.Text.Json;

namespace Tama.Core;

/// <summary>
/// One parsed Codex rollout. Codex reports a session-cumulative total (not per-turn), so
/// there are no hour buckets here: the scanner drops <c>Cumulative</c> into a single bucket
/// at <c>Last</c> (the file's mtime) — all-or-nothing per window, matching the reference.
/// </summary>
public sealed record CodexParsed(
    string Folder,
    TokenBreakdown Cumulative,
    int ContextTokens,
    int ContextWindow,
    DateTimeOffset Last,
    string? Model,
    string? SessionId,
    string? Title,
    int Messages);

/// <summary>
/// Parses one Codex rollout (&lt;codex-root&gt;/sessions/YYYY/MM/DD/rollout-*.jsonl).
/// Semantics normative in spec/log-formats.md — mirror of the Swift parseCodex.
/// </summary>
public static class CodexReader
{
    public static CodexParsed? ParseFile(string path)
    {
        string? cwd = null, model = null, session = null, firstPrompt = null;
        int lastInput = 0, lastOutput = 0, lastCache = 0, contextTokens = 0, contextWindow = 0, messages = 0;

        SafeFileReader.ForEachLine(path, line =>
        {
            JsonDocument doc;
            try { doc = JsonDocument.Parse(line); }
            catch (JsonException) { return; }
            using var _ = doc;
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return;

            var type = StringOf(root, "type");
            var hasPayload = root.TryGetProperty("payload", out var payload)
                && payload.ValueKind == JsonValueKind.Object;
            if (!hasPayload) return;
            var payloadType = StringOf(payload, "type");

            if (type == "session_meta")
            {
                if (cwd is null && StringOf(payload, "cwd") is { Length: > 0 } c) cwd = c;
                if (session is null && StringOf(payload, "id") is { } sid) session = Prefix8(sid);
            }
            if (type == "turn_context" && StringOf(payload, "model") is { Length: > 0 } m) model = m;

            // Conversation length = transcript `message` items with role user/assistant (the
            // duplicated user_message/agent_message events and developer/system roles don't count).
            if (payloadType == "message" && StringOf(payload, "role") is "user" or "assistant") messages++;

            // Conversation name: the first real user prompt — a `user_message` event, or a
            // `message` item with role=user (joined `input_text` blocks).
            if (firstPrompt is null)
            {
                if (payloadType == "user_message" && StringOf(payload, "message") is { } msg)
                    firstPrompt = CodexPrompt(msg);
                else if (payloadType == "message" && StringOf(payload, "role") == "user"
                    && payload.TryGetProperty("content", out var content)
                    && content.ValueKind == JsonValueKind.Array)
                {
                    var texts = new List<string>();
                    foreach (var item in content.EnumerateArray())
                        if (item.ValueKind == JsonValueKind.Object
                            && StringOf(item, "type") == "input_text"
                            && StringOf(item, "text") is { } t) texts.Add(t);
                    if (texts.Count > 0) firstPrompt = CodexPrompt(string.Join(" ", texts));
                }
            }

            if (payloadType == "token_count"
                && payload.TryGetProperty("info", out var info) && info.ValueKind == JsonValueKind.Object)
            {
                if (info.TryGetProperty("total_token_usage", out var total)
                    && total.ValueKind == JsonValueKind.Object)
                {
                    lastInput = IntOf(total, "input_tokens");     // includes the cached subset
                    lastOutput = IntOf(total, "output_tokens");
                    lastCache = IntOf(total, "cached_input_tokens");
                }
                // Context occupancy = last turn's input side (already includes cached) + its output.
                if (info.TryGetProperty("last_token_usage", out var lastTurn)
                    && lastTurn.ValueKind == JsonValueKind.Object)
                    contextTokens = IntOf(lastTurn, "input_tokens") + IntOf(lastTurn, "output_tokens");
                if (IntOf(info, "model_context_window") is > 0 and var w) contextWindow = w;
            }
        });

        if (cwd is null) return null;
        DateTimeOffset mtime;
        try { mtime = new DateTimeOffset(File.GetLastWriteTimeUtc(path), TimeSpan.Zero); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
        { mtime = DateTimeOffset.MinValue; }
        // `input_tokens` includes `cached_input_tokens`; split the cached part out for pricing.
        var breakdown = new TokenBreakdown(
            Input: Math.Max(0, lastInput - lastCache), Output: lastOutput,
            CacheRead: lastCache, CacheWrite: 0);
        return new CodexParsed(cwd, breakdown, contextTokens, contextWindow, mtime,
            model, session, firstPrompt, messages);
    }

    /// <summary>Strip the IDE-context wrapper Codex prepends, then apply the shared cleaning rules.</summary>
    internal static string? CodexPrompt(string raw)
    {
        var t = raw;
        const string marker = "## My request for Codex:";
        var i = t.IndexOf(marker, StringComparison.Ordinal);
        if (i >= 0) t = t[(i + marker.Length)..];
        return ClaudeSessionReader.CleanPrompt(t);
    }

    private static string? StringOf(JsonElement obj, string name) =>
        obj.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    private static int IntOf(JsonElement obj, string name) =>
        obj.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Number
            && v.TryGetInt32(out var i) ? i : 0;

    private static string Prefix8(string s) => s.Length <= 8 ? s : s[..8];
}
