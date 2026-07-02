using Tama.Core;

namespace Tama.Core.Tests;

[TestClass]
public sealed class OllamaReaderTests
{
    private string _root = null!;

    [TestInitialize]
    public void SetUp()
    {
        _root = Path.Combine(Path.GetTempPath(), "ollama-" + Guid.NewGuid());
        Directory.CreateDirectory(_root);
    }

    [TestCleanup]
    public void TearDown() => Directory.Delete(_root, recursive: true);

    private string Fixture(params string[] lines)
    {
        var p = Path.Combine(_root, "server.log");
        File.WriteAllText(p, string.Join("\n", lines));
        return p;
    }

    private static string Start(string tag) =>
        $"time=2026-06-22T18:36:56.556+07:00 level=INFO source=client.go:367 msg=\"starting mlx runner subprocess\" model={tag} port=100";
    private const string Stop =
        "time=2026-06-22T19:29:32.938+07:00 level=INFO source=client.go:126 msg=\"stopping mlx runner subprocess\" pid=999";
    private static string Prompt(int win, int tok) =>
        $"slot update_slots: id  0 | task 5 | new prompt, n_ctx_slot = {win}, n_keep = 4, task.n_tokens = {tok}";
    private const string Processing = "slot launch_slot_: id  0 | task 5 | processing task, is_child = 0";
    private const string Idle = "srv  update_slots: all slots are idle";
    private static string Timing(double tps) =>
        $"slot print_timing: id  0 | task 5 | n_decoded =    100, tg =  {tps} t/s";
    private static string Gin(string time, string dur, string endpoint) =>
        $"[GIN] 2026/06/22 - {time} | 200 |   {dur} |       127.0.0.1 | POST     \"{endpoint}\"";

    private static OllamaReader Reader(string path) => new(path, TimeZoneInfo.Utc);

    [TestMethod]
    public void Lists_models_current_first_with_attribution()
    {
        var p = Fixture(
            Start("qwen3.6:27b-mlx"), Prompt(32768, 2000), Processing, Timing(50.0),
            Gin("19:00:00", "5.0s", "/api/generate"), Idle, Stop,
            Start("gemma4:12b-mlx"), Prompt(8192, 500), Processing, Timing(80.0),
            Gin("19:30:00", "2.0s", "/api/chat"), Gin("19:30:05", "200ms", "/api/chat"));
        var models = Reader(p).Read()!.Models;
        Assert.AreEqual(2, models.Count);

        var g = models[0];
        Assert.AreEqual("gemma4:12b-mlx", g.Model);
        Assert.IsTrue(g.Current);
        Assert.IsTrue(g.Busy);                        // processing, no idle after
        Assert.AreEqual(8192, g.ContextWindow);
        Assert.AreEqual(500, g.ContextTokens);
        Assert.AreEqual(80.0, g.TokensPerSecond);
        Assert.AreEqual(0.2, g.LastLatencySeconds!.Value, 0.001);   // 200ms
        Assert.AreEqual(OllamaRequestKind.Chat, g.Kind);
        Assert.AreEqual(2, g.RequestCount);
        Assert.AreEqual(new DateTimeOffset(2026, 6, 22, 19, 30, 5, TimeSpan.Zero), g.LastActivity);

        var q = models[1];
        Assert.AreEqual("qwen3.6:27b-mlx", q.Model);
        Assert.IsFalse(q.Current);
        Assert.IsFalse(q.Busy);                       // idle after
        Assert.AreEqual(32768, q.ContextWindow);
    }

    [TestMethod]
    public void Non_inference_endpoints_do_not_count()
    {
        var p = Fixture(Start("m:1"),
            Gin("19:00:00", "1ms", "/api/tags"), Gin("19:00:01", "1ms", "/api/ps"));
        var m = Reader(p).Read()!.Models[0];
        Assert.AreEqual(0, m.RequestCount);
        Assert.AreEqual(OllamaRequestKind.Unknown, m.Kind);
    }

    [TestMethod]
    public void Embed_majority_flips_kind()
    {
        var p = Fixture(Start("m:1"),
            Gin("19:00:00", "1ms", "/api/embed"), Gin("19:00:01", "1ms", "/api/embed"),
            Gin("19:00:02", "1ms", "/api/chat"));
        Assert.AreEqual(OllamaRequestKind.Embed, Reader(p).Read()!.Models[0].Kind);
    }

    [TestMethod]
    public void Lines_before_any_start_are_unattributed()
    {
        var p = Fixture(Prompt(1000, 10), Gin("19:00:00", "1s", "/api/chat"), Start("m:1"));
        var m = Reader(p).Read()!.Models[0];
        Assert.AreEqual(0, m.RequestCount);
        Assert.IsNull(m.ContextWindow);
    }

    [TestMethod]
    public void Reload_of_same_model_merges_into_one_entry()
    {
        var p = Fixture(
            Start("m:1"), Gin("19:00:00", "1s", "/api/chat"), Stop,
            Start("m:1"), Gin("19:10:00", "1s", "/api/chat"));
        var models = Reader(p).Read()!.Models;
        Assert.AreEqual(1, models.Count);
        Assert.AreEqual(2, models[0].RequestCount);
    }

    [TestMethod]
    public void Go_durations_parse_all_suffixes()
    {
        var p = Fixture(Start("m:1"),
            Gin("19:00:00", "23.917µs", "/api/chat"));
        Assert.AreEqual(23.917e-6, Reader(p).Read()!.Models[0].LastLatencySeconds!.Value, 1e-9);
    }

    [TestMethod]
    public void Missing_or_empty_log_returns_null()
    {
        Assert.IsNull(Reader(Path.Combine(_root, "nope.log")).Read());
        Assert.IsNull(Reader(Fixture()).Read());
    }
}
