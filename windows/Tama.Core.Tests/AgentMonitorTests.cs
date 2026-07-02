using Tama.Core;

namespace Tama.Core.Tests;

[TestClass]
public sealed class AgentMonitorTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-06-19T12:00:00Z");

    private sealed class StubScanner : IActivityScanning
    {
        public Activity Result = Activity.Empty;
        public List<TokenWindow> Calls = new();
        public Activity Scan(TokenWindow window) { Calls.Add(window); return Result; }
    }

    private sealed class StubPresence : IOllamaPresence
    {
        public bool Running;
        public bool IsRunning() => Running;
    }

    private sealed class StubOllama : IOllamaReading
    {
        public OllamaStatus? Status;
        public OllamaStatus? Read() => Status;
    }

    private string _stateDir = null!;

    [TestInitialize]
    public void SetUp() => _stateDir = Path.Combine(Path.GetTempPath(), "mon-" + Guid.NewGuid());

    [TestCleanup]
    public void TearDown() { if (Directory.Exists(_stateDir)) Directory.Delete(_stateDir, recursive: true); }

    private static Activity ActivityWith(params (string model, TokenBreakdown bd)[] models)
    {
        var perModel = models.ToDictionary(m => m.model, m => m.bd);
        var rolled = models.Aggregate(new TokenBreakdown(), (acc, m) => acc + m.bd);
        var session = new SessionInfo(Provider.ClaudeCode, "p", "/p", Now.AddSeconds(-100),
            Tokens: rolled.Total, Breakdown: rolled);
        return new Activity(new[] { session },
            new Dictionary<Provider, int> { [Provider.ClaudeCode] = rolled.Total },
            new Dictionary<Provider, TokenBreakdown> { [Provider.ClaudeCode] = rolled },
            new Dictionary<Provider, IReadOnlyDictionary<string, TokenBreakdown>>
            { [Provider.ClaudeCode] = perModel });
    }

    // runsInBackground: false → scans run synchronously on the test thread (the Swift
    // testing seam), so no waits or races anywhere in this suite.
    private AgentMonitor Monitor(StubScanner scanner, StubPresence? presence = null, StubOllama? ollama = null) => new(
        scanner, presence ?? new StubPresence(), ollama ?? new StubOllama(),
        new CostEstimator(), new MoodEngine(TimeSpan.FromSeconds(900), TimeSpan.FromSeconds(3600), TimeZoneInfo.Utc),
        new CatStateStore(_stateDir), () => Now, runsInBackground: false);

    [TestMethod]
    public void Refresh_publishes_sessions_usage_and_mood()
    {
        var scanner = new StubScanner
        { Result = ActivityWith(("claude-sonnet-5", new TokenBreakdown(Input: 1_000_000))) };
        var monitor = Monitor(scanner);
        AppState? published = null;
        monitor.StateChanged += s => published = s;

        monitor.Refresh();
        Assert.IsNotNull(published);
        Assert.AreEqual(1, published.ActiveSessions.Count);
        Assert.AreEqual(1_000_000, published.Usage[Provider.ClaudeCode].TodayTokens);
        Assert.AreEqual(3.0, published.Usage[Provider.ClaudeCode].TodayCost, 1e-9);   // sonnet tier
        Assert.AreEqual(MoodKind.Greeting, published.Mood.Kind);                       // first activity today
        Assert.AreEqual(Now, published.LastUpdated);
    }

    [TestMethod]
    public void Per_model_costs_sum_across_tiers()
    {
        var scanner = new StubScanner
        {
            Result = ActivityWith(
                ("claude-sonnet-5", new TokenBreakdown(Input: 1_000_000)),
                ("claude-haiku-4-5", new TokenBreakdown(Input: 1_000_000))),
        };
        var monitor = Monitor(scanner);
        monitor.Refresh();
        Assert.AreEqual(3.0 + 1.0, monitor.State.Usage[Provider.ClaudeCode].TodayCost, 1e-9);
    }

    [TestMethod]
    public void Ollama_tile_hidden_unless_process_running()
    {
        Assert.IsNull(AgentMonitor.OllamaState(presence: false,
            enrichment: new OllamaStatus(Models: new[] { new OllamaModelActivity("m", false, false, null, null, null, null, null, OllamaRequestKind.Unknown, 0) })));
        var shown = AgentMonitor.OllamaState(presence: true, enrichment: null);
        Assert.IsNotNull(shown);
        Assert.IsTrue(shown.Running);
    }

    [TestMethod]
    public void Window_change_triggers_rescan_with_new_window()
    {
        var scanner = new StubScanner();
        var monitor = Monitor(scanner);
        monitor.Refresh();
        Assert.AreEqual(1, scanner.Calls.Count);
        monitor.Window = TokenWindow.Last24h;
        Assert.AreEqual(2, scanner.Calls.Count);
        Assert.AreEqual(TokenWindow.Last24h, scanner.Calls[^1]);
        monitor.Window = TokenWindow.Last24h;   // no change → no extra scan
        Assert.AreEqual(2, scanner.Calls.Count);
    }

    [TestMethod]
    public void Cat_state_persisted_once_seen()
    {
        var scanner = new StubScanner
        { Result = ActivityWith(("claude-opus-4-8", new TokenBreakdown(Input: 10))) };
        Monitor(scanner).Refresh();
        Assert.AreEqual(Now, new CatStateStore(_stateDir).Load().LastSeenDay);
    }

    [TestMethod]
    public void IsActive_uses_the_15_minute_window_against_last_update()
    {
        var scanner = new StubScanner
        { Result = ActivityWith(("m", new TokenBreakdown(Input: 1))) };
        var monitor = Monitor(scanner);
        monitor.Refresh();
        Assert.IsTrue(monitor.IsActive(monitor.State.ActiveSessions[0]));   // 100 s ago
        Assert.AreEqual(1, monitor.ActiveCount());
        Assert.AreEqual(0, monitor.ActiveCount(Provider.Codex));
    }
}
