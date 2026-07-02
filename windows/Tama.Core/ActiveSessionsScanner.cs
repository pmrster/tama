namespace Tama.Core;

/// <summary>
/// Reads recently-active agent sessions and per-provider token totals from the agents'
/// local logs. Strictly read-only. Parsing cached per file by (mtime, size) — only files
/// being actively written are re-parsed. Mirror of the Swift ActiveSessionsReader.
/// </summary>
public sealed class ActiveSessionsScanner : IActivityScanning
{
    private readonly string _claudeProjectsDir;
    private readonly string _codexSessionsDir;
    private readonly string? _geminiTmpDir;
    private readonly string? _antigravityHistoryFile;
    private readonly Func<DateTimeOffset> _now;
    private readonly TimeZoneInfo _tz;
    private readonly int _limit;
    private const int CodexLookbackDays = 14;

    /// <summary>One file's parsed contribution. Buckets: hourKey → that hour's tokens —
    /// content-only, so entries stay valid in the (mtime,size) cache as windows move.</summary>
    private sealed record Entry(
        DateTimeOffset Mtime, long Size, Provider Provider, string Folder,
        IReadOnlyDictionary<long, TokenBreakdown> Buckets, int ContextTokens, int ContextWindow,
        DateTimeOffset Last, string? Model, string? SessionId, string? Title, int Messages);

    private Dictionary<string, Entry> _cache = new();

    public ActiveSessionsScanner(string claudeProjectsDir, string codexSessionsDir,
        string? geminiTmpDir, string? antigravityHistoryFile,
        Func<DateTimeOffset> now, TimeZoneInfo tz, int limit = 16)
    {
        _claudeProjectsDir = claudeProjectsDir;
        _codexSessionsDir = codexSessionsDir;
        _geminiTmpDir = geminiTmpDir;
        _antigravityHistoryFile = antigravityHistoryFile;
        _now = now;
        _tz = tz;
        _limit = limit;
    }

    /// <summary>The shipped scanner: real Windows agent-log locations, local time zone.</summary>
    public static ActiveSessionsScanner CreateDefault(Func<DateTimeOffset> now)
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return new ActiveSessionsScanner(
            Path.Combine(home, ".claude", "projects"),
            Path.Combine(home, ".codex", "sessions"),
            Path.Combine(home, ".gemini", "tmp"),
            Path.Combine(home, ".gemini", "antigravity-cli", "history.jsonl"),
            now, TimeZoneInfo.Local);
    }

    public Activity Scan(TokenWindow window)
    {
        var now = _now();
        var entries = new List<Entry>();
        var fresh = new Dictionary<string, Entry>();

        ScanClaude(window, now, entries, fresh);
        ScanCodex(window, now, entries, fresh);
        _cache = fresh;                                  // drop entries no longer in window
        entries.AddRange(FolderEntries(window, now));    // gemini + antigravity, small, uncached

        var cutoff = CutoffHour(window, now);
        var breakdowns = new Dictionary<Provider, TokenBreakdown>();
        var modelBreakdowns = new Dictionary<Provider, Dictionary<string, TokenBreakdown>>();
        var sessions = new List<SessionInfo>(entries.Count);
        foreach (var e in entries)
        {
            var bd = e.Buckets.Where(kv => kv.Key >= cutoff)
                .Aggregate(new TokenBreakdown(), (acc, kv) => acc + kv.Value);
            breakdowns[e.Provider] = breakdowns.GetValueOrDefault(e.Provider) + bd;
            var modelKey = e.Model ?? "";   // "" = unknown model → priced at the provider default
            var perModel = modelBreakdowns.TryGetValue(e.Provider, out var pm)
                ? pm : modelBreakdowns[e.Provider] = new Dictionary<string, TokenBreakdown>();
            perModel[modelKey] = perModel.GetValueOrDefault(modelKey) + bd;
            sessions.Add(new SessionInfo(e.Provider,
                Project: Path.GetFileName(e.Folder.TrimEnd('/', '\\')) is { Length: > 0 } p ? p : e.Folder,
                Folder: e.Folder, LastActivity: e.Last, Tokens: bd.Total,
                CacheTokens: bd.CacheRead + bd.CacheWrite, ContextTokens: e.ContextTokens,
                ContextWindow: e.ContextWindow, Model: e.Model, SessionId: e.SessionId,
                Title: e.Title, Breakdown: bd, Messages: e.Messages));
        }
        sessions.Sort((a, b) => b.LastActivity.CompareTo(a.LastActivity));
        return new Activity(
            sessions.Take(_limit).ToList(),
            breakdowns.ToDictionary(kv => kv.Key, kv => kv.Value.Total),
            breakdowns,
            modelBreakdowns.ToDictionary(kv => kv.Key,
                kv => (IReadOnlyDictionary<string, TokenBreakdown>)kv.Value));
    }

    // MARK: window math (tz-aware, mirrors Calendar.startOfDay / isDate(inSameDayAs:))

    private long CutoffHour(TokenWindow window, DateTimeOffset now) => window switch
    {
        TokenWindow.Today => ClaudeSessionReader.HourKey(StartOfDay(now)),
        _ => ClaudeSessionReader.HourKey(now.AddHours(-24)),
    };

    private bool InWindow(DateTimeOffset mtime, TokenWindow window, DateTimeOffset now) => window switch
    {
        TokenWindow.Today => IsSameLocalDay(mtime, now),
        _ => mtime >= now.AddHours(-24),
    };

    private DateTimeOffset StartOfDay(DateTimeOffset d)
    {
        var local = TimeZoneInfo.ConvertTime(d, _tz);
        var midnight = local.Date;
        return new DateTimeOffset(midnight, _tz.GetUtcOffset(midnight));
    }

    private bool IsSameLocalDay(DateTimeOffset a, DateTimeOffset b) =>
        TimeZoneInfo.ConvertTime(a, _tz).Date == TimeZoneInfo.ConvertTime(b, _tz).Date;

    // MARK: cached parsing

    private Entry? Cached(string file, Dictionary<string, Entry> fresh, Func<string, Entry?> parse)
    {
        DateTimeOffset mtime;
        long size;
        try
        {
            var info = new FileInfo(file);
            if (!info.Exists) return null;
            mtime = new DateTimeOffset(info.LastWriteTimeUtc, TimeSpan.Zero);
            size = info.Length;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
        { return null; }
        if (_cache.TryGetValue(file, out var hit) && hit.Mtime == mtime && hit.Size == size)
        {
            fresh[file] = hit;
            return hit;
        }
        var parsed = parse(file);
        if (parsed is null) return null;
        var entry = parsed with { Mtime = mtime, Size = size };
        fresh[file] = entry;
        return entry;
    }

    private void ScanClaude(TokenWindow window, DateTimeOffset now, List<Entry> entries, Dictionary<string, Entry> fresh)
    {
        string[] dirs;
        try { dirs = Directory.GetDirectories(_claudeProjectsDir); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
        { return; }
        foreach (var dir in dirs)
        {
            if (!SafeFileReader.IsSafeDirectory(dir)) continue;
            string[] files;
            try { files = Directory.GetFiles(dir, "*.jsonl"); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { continue; }
            foreach (var file in files)
            {
                if (Mtime(file) is not { } mod || !InWindow(mod, window, now)) continue;
                if (Cached(file, fresh, ParseClaudeEntry) is { } e) entries.Add(e);
            }
        }
    }

    private Entry? ParseClaudeEntry(string file)
    {
        if (ClaudeSessionReader.ParseFile(file) is not { } p) return null;
        return new Entry(DateTimeOffset.MinValue, 0, Provider.ClaudeCode, p.Folder,
            p.Buckets, p.ContextTokens, p.ContextWindow, p.Last, p.Model, p.SessionId,
            p.Title, p.Messages);
    }

    private void ScanCodex(TokenWindow window, DateTimeOffset now, List<Entry> entries, Dictionary<string, Entry> fresh)
    {
        // Codex files each rollout under its session-START date, but a long-lived session keeps
        // appending to that older file — look back N day-folders and keep files whose mtime is
        // in-window, matching the Claude scan. Unchanged files are cache hits, so this is cheap.
        var localNow = TimeZoneInfo.ConvertTime(now, _tz);
        for (var offset = 0; offset < CodexLookbackDays; offset++)
        {
            var day = localNow.Date.AddDays(-offset);
            var dayDir = Path.Combine(_codexSessionsDir,
                day.Year.ToString("D4"), day.Month.ToString("D2"), day.Day.ToString("D2"));
            if (!SafeFileReader.IsSafeDirectory(dayDir)) continue;
            string[] files;
            try { files = Directory.GetFiles(dayDir, "rollout-*.jsonl"); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { continue; }
            foreach (var file in files)
            {
                if (Mtime(file) is not { } mod || !InWindow(mod, window, now)) continue;
                if (Cached(file, fresh, ParseCodexEntry) is { } e) entries.Add(e);
            }
        }
    }

    private Entry? ParseCodexEntry(string file)
    {
        if (CodexReader.ParseFile(file) is not { } p) return null;
        // Session-cumulative: whole breakdown in ONE bucket at the last-activity hour —
        // all-or-nothing per window, matching the file's mtime-gated inclusion.
        var buckets = p.Cumulative.Total > 0
            ? new Dictionary<long, TokenBreakdown> { [ClaudeSessionReader.HourKey(p.Last)] = p.Cumulative }
            : new Dictionary<long, TokenBreakdown>();
        return new Entry(DateTimeOffset.MinValue, 0, Provider.Codex, p.Folder,
            buckets, p.ContextTokens, p.ContextWindow, p.Last, p.Model, p.SessionId,
            p.Title, p.Messages);
    }

    private IEnumerable<Entry> FolderEntries(TokenWindow window, DateTimeOffset now)
    {
        var empty = new Dictionary<long, TokenBreakdown>();
        if (_geminiTmpDir is { } tmp)
            foreach (var s in GeminiReader.Read(tmp))
                if (InWindow(s.LastActivity, window, now))
                    yield return new Entry(DateTimeOffset.MinValue, 0, Provider.Gemini, s.Folder,
                        empty, 0, 0, s.LastActivity, null, null, null, 0);
        if (_antigravityHistoryFile is { } hist)
            foreach (var s in AntigravityReader.Read(hist))
                if (InWindow(s.LastActivity, window, now))
                    yield return new Entry(DateTimeOffset.MinValue, 0, Provider.Antigravity, s.Folder,
                        empty, 0, 0, s.LastActivity, null, null, null, 0);
    }

    private static DateTimeOffset? Mtime(string file)
    {
        try { return new DateTimeOffset(File.GetLastWriteTimeUtc(file), TimeSpan.Zero); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
        { return null; }
    }
}
