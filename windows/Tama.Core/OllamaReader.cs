using System.Globalization;
using System.Text;

namespace Tama.Core;

/// <summary>
/// Reads per-model activity for a local Ollama server from its llama.cpp server.log.
/// Read-only and local-only: never opens the Ollama HTTP API, never reads history files.
/// Only the log tail is inspected. Activity is attributed by segmenting the log between
/// runner start/stop events. Mirror of the Swift OllamaReader (spec/log-formats.md, Ollama).
/// </summary>
public sealed class OllamaReader
{
    private const int TailBytes = 256 * 1024;
    private readonly string _logPath;
    private readonly TimeZoneInfo _tz;

    /// <summary>tz parses the [GIN] request timestamps, which carry no zone of their own.</summary>
    public OllamaReader(string logPath, TimeZoneInfo tz)
    {
        _logPath = logPath;
        _tz = tz;
    }

    /// <summary>Default Windows location of the Ollama server log.</summary>
    public static string DefaultLogPath() => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Ollama", "server.log");

    private sealed class Segment
    {
        public bool Busy;
        public DateTimeOffset? LastActivity;
        public int? ContextWindow;
        public int? ContextTokens;
        public double? TokensPerSecond;
        public double? LastLatencySeconds;
        public int RequestCount;
        public int ChatCount;
        public int EmbedCount;
        public OllamaRequestKind Kind =>
            EmbedCount > ChatCount ? OllamaRequestKind.Embed
            : ChatCount > 0 ? OllamaRequestKind.Chat : OllamaRequestKind.Unknown;
    }

    public OllamaStatus? Read()
    {
        var data = SafeFileReader.Tail(_logPath, TailBytes);
        if (data is not { Length: > 0 }) return null;
        var text = Encoding.UTF8.GetString(data);

        var segments = new Dictionary<string, Segment>();   // keyed by model tag (dedupes reloads)
        var order = new List<string>();                     // first-seen order
        string? active = null;                              // model owning the lines being read
        string? current = null;                             // model whose runner is still loaded

        foreach (var line in text.Split('\n', StringSplitOptions.RemoveEmptyEntries))
        {
            if (StartedModel(line) is { } tag)
            {
                active = tag; current = tag;
                if (!segments.ContainsKey(tag)) { segments[tag] = new Segment(); order.Add(tag); }
                continue;
            }
            if (line.Contains("stopping mlx runner subprocess", StringComparison.Ordinal))
            {
                active = null; current = null;
                continue;
            }
            if (active is null || !segments.TryGetValue(active, out var seg)) continue;
            Apply(line, seg);
        }

        var models = order
            .Select(tag =>
            {
                var s = segments[tag];
                return new OllamaModelActivity(tag, Current: tag == current, Busy: s.Busy,
                    LastActivity: s.LastActivity, ContextWindow: s.ContextWindow,
                    ContextTokens: s.ContextTokens, TokensPerSecond: s.TokensPerSecond,
                    LastLatencySeconds: s.LastLatencySeconds, Kind: s.Kind,
                    RequestCount: s.RequestCount);
            })
            .OrderByDescending(m => m.Current)                                   // loaded model first
            .ThenByDescending(m => m.LastActivity ?? DateTimeOffset.MinValue)
            .ToList();
        return new OllamaStatus(Running: false, LastActivity: ModificationDate(), Models: models);
    }

    private void Apply(string line, Segment seg)
    {
        if (IntAfter("n_ctx_slot = ", line) is { } w) seg.ContextWindow = w;
        if (IntAfter("task.n_tokens = ", line) is { } t) seg.ContextTokens = t;
        if (DoubleAfter("tg = ", line) is { } tps) seg.TokensPerSecond = tps;
        if (line.Contains("all slots are idle", StringComparison.Ordinal)) seg.Busy = false;
        if (line.Contains("processing task", StringComparison.Ordinal)) seg.Busy = true;
        if (line.StartsWith("[GIN]", StringComparison.Ordinal)) ApplyGin(line, seg);
    }

    private void ApplyGin(string line, Segment seg)
    {
        if (GinEndpoint(line) is not { } endpoint) return;
        OllamaRequestKind kind;
        if (endpoint.Contains("/embed", StringComparison.Ordinal)) kind = OllamaRequestKind.Embed;
        else if (endpoint.EndsWith("/api/chat", StringComparison.Ordinal)
              || endpoint.EndsWith("/api/generate", StringComparison.Ordinal)) kind = OllamaRequestKind.Chat;
        else return;   // /api/tags, /show, /ps, /version, /pull, /delete — not inference
        seg.RequestCount++;
        if (kind == OllamaRequestKind.Embed) seg.EmbedCount++; else seg.ChatCount++;
        var fields = line.Split('|');
        if (fields.Length > 2 && ParseDuration(fields[2].Trim()) is { } dur) seg.LastLatencySeconds = dur;
        var stamp = fields[0].Replace("[GIN]", "", StringComparison.Ordinal).Trim();
        if (DateTime.TryParseExact(stamp, "yyyy/MM/dd - HH:mm:ss", CultureInfo.InvariantCulture,
                DateTimeStyles.None, out var local))
            seg.LastActivity = new DateTimeOffset(local, _tz.GetUtcOffset(local));
    }

    /// <summary>model=&lt;tag&gt; on a runner-subprocess start line (ignores pull-manifest noise).</summary>
    private static string? StartedModel(string line)
    {
        if (!line.Contains("runner subprocess", StringComparison.Ordinal)
            || !line.Contains("starting", StringComparison.Ordinal)) return null;
        var i = line.IndexOf("model=", StringComparison.Ordinal);
        if (i < 0) return null;
        var rest = line[(i + "model=".Length)..];
        var end = rest.AsSpan().IndexOfAny(' ', '\t');
        var tag = end < 0 ? rest : rest[..end];
        return tag.Length == 0 ? null : tag;
    }

    private static int? IntAfter(string needle, string line)
    {
        var i = line.IndexOf(needle, StringComparison.Ordinal);
        if (i < 0) return null;
        var rest = line.AsSpan(i + needle.Length);
        var len = 0;
        while (len < rest.Length && char.IsAsciiDigit(rest[len])) len++;
        return len > 0 && int.TryParse(rest[..len], out var v) ? v : null;
    }

    private static double? DoubleAfter(string needle, string line)
    {
        var i = line.IndexOf(needle, StringComparison.Ordinal);
        if (i < 0) return null;
        var rest = line.AsSpan(i + needle.Length).TrimStart(' ');
        var len = 0;
        while (len < rest.Length && (char.IsAsciiDigit(rest[len]) || rest[len] == '.')) len++;
        return len > 0 && double.TryParse(rest[..len], CultureInfo.InvariantCulture, out var v) ? v : null;
    }

    /// <summary>The quoted route on a [GIN] line, e.g. /api/chat.</summary>
    private static string? GinEndpoint(string line)
    {
        var close = line.LastIndexOf('"');
        if (close < 0) return null;
        var open = line.LastIndexOf('"', close - 1);
        if (open < 0) return null;
        return line[(open + 1)..close];
    }

    /// <summary>llama.cpp's Go-duration strings: 5.0s, 200ms, 23.917µs, 41ns.</summary>
    private static double? ParseDuration(string s)
    {
        double? Value(int drop, double scale) =>
            double.TryParse(s[..^drop], CultureInfo.InvariantCulture, out var v) ? v * scale : null;
        if (s.EndsWith("ms", StringComparison.Ordinal)) return Value(2, 1e-3);
        if (s.EndsWith("µs", StringComparison.Ordinal) || s.EndsWith("us", StringComparison.Ordinal)) return Value(2, 1e-6);
        if (s.EndsWith("ns", StringComparison.Ordinal)) return Value(2, 1e-9);
        if (s.EndsWith("s", StringComparison.Ordinal)) return Value(1, 1);
        return null;
    }

    private DateTimeOffset? ModificationDate()
    {
        try
        {
            return File.Exists(_logPath)
                ? new DateTimeOffset(File.GetLastWriteTimeUtc(_logPath), TimeSpan.Zero) : null;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
        { return null; }
    }
}
