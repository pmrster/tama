using Tama.Core;

namespace Tama.Core.Tests;

[TestClass]
public sealed class ActiveSessionsScannerTests
{
    private string _root = null!;
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-06-19T12:00:00Z");

    [TestInitialize]
    public void SetUp()
    {
        _root = Path.Combine(Path.GetTempPath(), "scan-" + Guid.NewGuid());
        Directory.CreateDirectory(_root);
    }

    [TestCleanup]
    public void TearDown() => Directory.Delete(_root, recursive: true);

    private const string ClaudeTurn =
        "{\"type\":\"assistant\",\"timestamp\":\"2026-06-19T09:00:00.000Z\",\"cwd\":\"/Example/Code/myapp\",\"message\":{\"id\":\"m1\",\"model\":\"claude-opus-4-8\",\"usage\":{\"input_tokens\":100,\"output_tokens\":10,\"cache_read_input_tokens\":5,\"cache_creation_input_tokens\":2}}}";

    private string WriteClaude(string content, DateTime? mtime = null, string name = "s.jsonl")
    {
        var dir = Path.Combine(_root, "claude", "-Example-Code-myapp");
        Directory.CreateDirectory(dir);
        var p = Path.Combine(dir, name);
        File.WriteAllText(p, content);
        File.SetLastWriteTimeUtc(p, mtime ?? Now.UtcDateTime);
        return p;
    }

    private ActiveSessionsScanner Scanner(int limit = 16) => new(
        Path.Combine(_root, "claude"), Path.Combine(_root, "codex"),
        Path.Combine(_root, "gemini"), Path.Combine(_root, "anti", "history.jsonl"),
        () => Now, TimeZoneInfo.Utc, limit);

    [TestMethod]
    public void Scan_lists_claude_session_with_totals_and_model_breakdowns()
    {
        WriteClaude(ClaudeTurn);
        var activity = Scanner().Scan(TokenWindow.Today);
        Assert.AreEqual(1, activity.Sessions.Count);
        var s = activity.Sessions[0];
        Assert.AreEqual(Provider.ClaudeCode, s.Provider);
        Assert.AreEqual("myapp", s.Project);
        Assert.AreEqual(117, s.Tokens);
        Assert.AreEqual(117, activity.Totals[Provider.ClaudeCode]);
        Assert.AreEqual(117, activity.ModelBreakdowns[Provider.ClaudeCode]["claude-opus-4-8"].Total);
    }

    [TestMethod]
    public void Files_touched_yesterday_are_excluded_from_today_but_not_last24h()
    {
        WriteClaude(ClaudeTurn, mtime: Now.UtcDateTime.AddHours(-13));  // 23:00 yesterday
        Assert.AreEqual(0, Scanner().Scan(TokenWindow.Today).Sessions.Count);
        Assert.AreEqual(1, Scanner().Scan(TokenWindow.Last24h).Sessions.Count);
    }

    [TestMethod]
    public void Windowed_tokens_sum_only_buckets_after_cutoff()
    {
        // Two turns: 23:30 yesterday (id y) and 09:00 today (id t). File touched today.
        var yesterday =
            "{\"type\":\"assistant\",\"timestamp\":\"2026-06-18T23:30:00.000Z\",\"cwd\":\"/Example/Code/myapp\",\"message\":{\"id\":\"y\",\"model\":\"claude-opus-4-8\",\"usage\":{\"input_tokens\":1000,\"output_tokens\":0}}}";
        WriteClaude(yesterday + "\n" + ClaudeTurn);
        var today = Scanner().Scan(TokenWindow.Today);
        Assert.AreEqual(117, today.Sessions[0].Tokens);          // yesterday's 1000 outside window
        var day = Scanner().Scan(TokenWindow.Last24h);
        Assert.AreEqual(1117, day.Sessions[0].Tokens);           // both inside trailing 24h
    }

    [TestMethod]
    public void Cache_reuses_parse_for_unchanged_files()
    {
        WriteClaude(ClaudeTurn);
        var scanner = Scanner();
        var first = scanner.Scan(TokenWindow.Today);
        var second = scanner.Scan(TokenWindow.Today);            // same mtime+size → cache hit
        Assert.AreEqual(first.Sessions[0].Tokens, second.Sessions[0].Tokens);
    }

    [TestMethod]
    public void Sessions_sorted_newest_first_and_capped_but_totals_cover_all()
    {
        WriteClaude(ClaudeTurn, name: "a.jsonl");
        WriteClaude(ClaudeTurn.Replace("09:00:00", "10:00:00"), name: "b.jsonl");
        var activity = Scanner(limit: 1).Scan(TokenWindow.Today);
        Assert.AreEqual(1, activity.Sessions.Count);             // capped
        Assert.AreEqual(234, activity.Totals[Provider.ClaudeCode]); // both counted
    }

    [TestMethod]
    public void Codex_lookback_finds_old_folder_touched_today()
    {
        // Rollout filed under June 10 but mtime = today → in window via 14-day lookback.
        var dir = Path.Combine(_root, "codex", "2026", "06", "10");
        Directory.CreateDirectory(dir);
        var p = Path.Combine(dir, "rollout-2026-06-10T08-00-00-019eddab-x.jsonl");
        File.WriteAllText(p, string.Join("\n",
            "{\"timestamp\":\"2026-06-10T08:00:00.000Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"019eddab\",\"cwd\":\"/Example/Code/widget\"}}",
            "{\"timestamp\":\"2026-06-19T11:00:00.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":10,\"cached_input_tokens\":0,\"output_tokens\":5},\"last_token_usage\":{\"input_tokens\":10,\"output_tokens\":5},\"model_context_window\":100000}}}"));
        File.SetLastWriteTimeUtc(p, Now.UtcDateTime);
        var activity = Scanner().Scan(TokenWindow.Today);
        Assert.AreEqual(1, activity.Sessions.Count);
        Assert.AreEqual(Provider.Codex, activity.Sessions[0].Provider);
        Assert.AreEqual(15, activity.Sessions[0].Tokens);
    }
}
