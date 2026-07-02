using System.Globalization;
using System.Runtime.CompilerServices;
using System.Text.Json;

[assembly: InternalsVisibleTo("Tama.Core.Tests")]

namespace Tama.Core;

/// <summary>One parsed Claude session log. Buckets: hourKey → that hour's tokens.</summary>
public sealed record ClaudeParsed(
    string Folder,
    IReadOnlyDictionary<long, TokenBreakdown> Buckets,
    int ContextTokens,
    int ContextWindow,
    DateTimeOffset Last,
    string? Model,
    string? SessionId,
    string? Title,
    int Messages)
{
    public TokenBreakdown Cumulative =>
        Buckets.Values.Aggregate(new TokenBreakdown(), (a, b) => a + b);
}

/// <summary>
/// Parses one Claude Code session log (&lt;claude-root&gt;/projects/&lt;proj&gt;/&lt;session&gt;.jsonl).
/// Semantics are normative in spec/log-formats.md — mirror of the Swift parseClaude.
/// </summary>
public static class ClaudeSessionReader
{
    public static long HourKey(DateTimeOffset ts) => ts.ToUnixTimeSeconds() / 3600;

    /// <summary>Claude logs don't carry the window size: default 200K, 1M on marker/overflow.</summary>
    public static int ContextWindowFor(string? model, int occupancy)
    {
        var m = (model ?? "").ToLowerInvariant();
        if (m.Contains("[1m]") || m.Contains("-1m") || occupancy > 200_000) return 1_000_000;
        return 200_000;
    }

    public static ClaudeParsed? ParseFile(string path)
    {
        string? folder = null, model = null, session = null, title = null, firstPrompt = null;
        var buckets = new Dictionary<long, TokenBreakdown>();
        var last = DateTimeOffset.MinValue;
        var ctxLast = DateTimeOffset.MinValue;
        int contextTokens = 0, messages = 0;
        var seenIds = new HashSet<string>();

        SafeFileReader.ForEachLine(path, line =>
        {
            JsonDocument doc;
            try { doc = JsonDocument.Parse(line); }
            catch (JsonException) { return; }
            using var _ = doc;
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return;

            var type = StringOf(root, "type");
            if (type == "summary" && StringOf(root, "summary") is { Length: > 0 } s) title = s;

            var hasMessage = root.TryGetProperty("message", out var message)
                && message.ValueKind == JsonValueKind.Object;
            // Claude v2.x splits one reply across lines repeating the same usage;
            // a repeated message.id means the whole line was already counted.
            if (type == "assistant" && hasMessage && StringOf(message, "id") is { } id
                && !seenIds.Add(id)) return;

            var isMeta = BoolOf(root, "isMeta");
            if (type == "user" && !isMeta) messages++;
            else if (type == "assistant") messages++;

            if (firstPrompt is null && type == "user" && !isMeta && hasMessage)
                firstPrompt = UserPrompt(message);

            if (!hasMessage) return;
            if (StringOf(root, "timestamp") is not { } ts
                || !DateTimeOffset.TryParse(ts, CultureInfo.InvariantCulture,
                        DateTimeStyles.AdjustToUniversal, out var date)) return;
            if (StringOf(root, "cwd") is not { Length: > 0 } cwd) return;
            if (!message.TryGetProperty("usage", out var usage)
                || usage.ValueKind != JsonValueKind.Object) return;

            folder = cwd;
            if (session is null && StringOf(root, "sessionId") is { } sid) session = Prefix8(sid);

            int input = IntOf(usage, "input_tokens"), output = IntOf(usage, "output_tokens");
            int cacheRead = IntOf(usage, "cache_read_input_tokens");
            int cacheWrite = IntOf(usage, "cache_creation_input_tokens");
            var cacheWrite1h = usage.TryGetProperty("cache_creation", out var cc)
                && cc.ValueKind == JsonValueKind.Object ? IntOf(cc, "ephemeral_1h_input_tokens") : 0;

            var key = HourKey(date);
            buckets[key] = buckets.GetValueOrDefault(key)
                + new TokenBreakdown(input, output, cacheRead, cacheWrite, cacheWrite1h);

            if (date >= last)
            {
                last = date;
                if (StringOf(message, "model") is { Length: > 0 } m) model = m;
            }
            // Live context = latest non-sidechain turn's input side + its output.
            if (!BoolOf(root, "isSidechain") && date >= ctxLast)
            {
                ctxLast = date;
                contextTokens = input + cacheRead + cacheWrite + output;
            }
        });

        if (folder is null) return null;
        var sessionId = session ?? Prefix8(Path.GetFileNameWithoutExtension(path));
        return new ClaudeParsed(folder, buckets, contextTokens,
            ContextWindowFor(model, contextTokens), last, model, sessionId,
            title ?? firstPrompt, messages);
    }

    /// <summary>Human prompt from a user message, or null (tool result / system block / empty).</summary>
    public static string? UserPrompt(JsonElement message)
    {
        string? raw = null;
        if (message.TryGetProperty("content", out var content))
        {
            if (content.ValueKind == JsonValueKind.String) raw = content.GetString();
            else if (content.ValueKind == JsonValueKind.Array)
            {
                var parts = new List<string>();
                foreach (var item in content.EnumerateArray())
                {
                    if (item.ValueKind != JsonValueKind.Object) continue;
                    var kind = StringOf(item, "type");
                    if (kind == "tool_result") return null;
                    if (kind == "text" && StringOf(item, "text") is { } t) parts.Add(t);
                }
                raw = string.Join(" ", parts);
            }
        }
        return CleanPrompt(raw);
    }

    /// <summary>Trim, reject system/interrupted blocks, collapse whitespace, cap at 80 chars.</summary>
    internal static string? CleanPrompt(string? raw)
    {
        var t = raw?.Trim();
        if (string.IsNullOrEmpty(t)) return null;
        if (t.StartsWith('<') || t.StartsWith("[Request interrupted", StringComparison.Ordinal)) return null;
        t = string.Join(" ", t.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        return t.Length > 80 ? t[..80].TrimEnd() + "…" : t;
    }

    private static string? StringOf(JsonElement obj, string name) =>
        obj.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    private static bool BoolOf(JsonElement obj, string name) =>
        obj.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.True;

    private static int IntOf(JsonElement obj, string name) =>
        obj.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Number
            && v.TryGetInt32(out var i) ? i : 0;

    private static string Prefix8(string s) => s.Length <= 8 ? s : s[..8];
}
