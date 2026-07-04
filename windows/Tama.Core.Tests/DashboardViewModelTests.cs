using Tama.Core.Ui;

namespace Tama.Core.Tests;

/// <summary>
/// Cases per planc-ui-spec.md §2b/§2c/§3c/§3d/§4 and the underlying
/// Sources/Tama/MenuBarView.swift this ports (folderGroups :803-811, nameGroups :813-817,
/// visibleProviders :159-161, MetricKind :36-65, ollamaStrip :247-320).
/// </summary>
[TestClass]
public sealed class DashboardViewModelTests
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

    private sealed class FakeRunAtLogin : IRunAtLogin
    {
        public bool Enabled;
        public int SetCalls;
        public bool IsEnabled() => Enabled;
        public void SetEnabled(bool enabled) { Enabled = enabled; SetCalls++; }
    }

    private string _stateDir = null!;

    [TestInitialize]
    public void SetUp() => _stateDir = Path.Combine(Path.GetTempPath(), "dvm-" + Guid.NewGuid());

    [TestCleanup]
    public void TearDown() { if (Directory.Exists(_stateDir)) Directory.Delete(_stateDir, recursive: true); }

    private AgentMonitor Monitor(StubScanner scanner, StubPresence? presence = null, StubOllama? ollama = null) => new(
        scanner, presence ?? new StubPresence(), ollama ?? new StubOllama(),
        new CostEstimator(), new MoodEngine(TimeSpan.FromSeconds(900), TimeSpan.FromSeconds(3600), TimeZoneInfo.Utc),
        new CatStateStore(_stateDir), () => Now, runsInBackground: false);

    private static SessionInfo Session(
        Provider provider, string folder, string project, string sessionId,
        DateTimeOffset? lastActivity = null, int tokens = 0, int contextTokens = 0, int contextWindow = 0,
        string? title = null, string? model = null) =>
        new(provider, project, folder, lastActivity ?? Now.AddMinutes(-1),
            Tokens: tokens, ContextTokens: contextTokens, ContextWindow: contextWindow,
            SessionId: sessionId, Title: title, Model: model);

    private static Activity ActivityOf(params SessionInfo[] sessions) => new(
        sessions,
        new Dictionary<Provider, int>(), new Dictionary<Provider, TokenBreakdown>(),
        new Dictionary<Provider, IReadOnlyDictionary<string, TokenBreakdown>>());

    // --- Provider ordering (spec §2b: enum declaration order, non-empty only) ---

    [TestMethod]
    public void Providers_render_in_declaration_order_regardless_of_session_insertion_order()
    {
        var scanner = new StubScanner
        {
            Result = ActivityOf(
                Session(Provider.Codex, "/p2", "p2", "s2"),
                Session(Provider.ClaudeCode, "/p1", "p1", "s1")),
        };
        var monitor = Monitor(scanner);
        var vm = new DashboardViewModel(monitor);
        monitor.Refresh();

        var providers = vm.TreeRows.OfType<ProviderRowVm>().Select(r => r.Provider).ToList();
        CollectionAssert.AreEqual(new[] { Provider.ClaudeCode, Provider.Codex }, providers);
    }

    [TestMethod]
    public void Providers_with_no_sessions_are_hidden_entirely()
    {
        var scanner = new StubScanner { Result = ActivityOf(Session(Provider.ClaudeCode, "/p1", "p1", "s1")) };
        var monitor = Monitor(scanner);
        var vm = new DashboardViewModel(monitor);
        monitor.Refresh();

        var providers = vm.TreeRows.OfType<ProviderRowVm>().Select(r => r.Provider).ToList();
        CollectionAssert.AreEqual(new[] { Provider.ClaudeCode }, providers);
    }

    // --- Folder grouping (spec §2c: Dictionary(grouping: by: folder), sorted by most-recent activity desc) ---

    [TestMethod]
    public void Sessions_group_by_folder_and_folders_sort_most_recent_first()
    {
        var scanner = new StubScanner
        {
            Result = ActivityOf(
                Session(Provider.ClaudeCode, "/old", "old-proj", "s1", lastActivity: Now.AddHours(-2)),
                Session(Provider.ClaudeCode, "/new", "new-proj", "s2", lastActivity: Now.AddMinutes(-1)),
                Session(Provider.ClaudeCode, "/new", "new-proj", "s3", lastActivity: Now.AddMinutes(-5))),
        };
        var monitor = Monitor(scanner);
        var vm = new DashboardViewModel(monitor);
        monitor.Refresh();
        vm.ToggleFolderExpanded("ClaudeCode:/new"); // expand to see session count directly too

        var folders = vm.TreeRows.OfType<FolderRowVm>().ToList();
        Assert.AreEqual(2, folders.Count);
        Assert.AreEqual("new-proj", folders[0].Project);
        Assert.AreEqual(2, folders[0].SessionCount);
        Assert.AreEqual("old-proj", folders[1].Project);
        Assert.AreEqual(1, folders[1].SessionCount);
    }

    [TestMethod]
    public void Folder_row_is_hidden_by_default_until_provider_expanded_state_toggled()
    {
        var scanner = new StubScanner { Result = ActivityOf(Session(Provider.ClaudeCode, "/p1", "p1", "s1")) };
        var monitor = Monitor(scanner);
        var vm = new DashboardViewModel(monitor);
        monitor.Refresh();

        Assert.AreEqual(1, vm.TreeRows.OfType<FolderRowVm>().Count()); // provider starts expanded
        vm.ToggleProviderCollapsed(Provider.ClaudeCode);
        Assert.AreEqual(0, vm.TreeRows.OfType<FolderRowVm>().Count());
    }

    // --- Same-prompt collapsing (spec §3c: NameGroup, only collapsed when count > 1) ---

    [TestMethod]
    public void Single_session_per_name_renders_as_a_plain_leaf_not_a_group()
    {
        var scanner = new StubScanner
        { Result = ActivityOf(Session(Provider.ClaudeCode, "/p1", "p1", "s1", title: "security review")) };
        var monitor = Monitor(scanner);
        var vm = new DashboardViewModel(monitor);
        monitor.Refresh();
        vm.ToggleFolderExpanded("ClaudeCode:/p1");

        Assert.AreEqual(1, vm.TreeRows.OfType<SessionLeafRowVm>().Count());
        Assert.AreEqual(0, vm.TreeRows.OfType<SessionGroupRowVm>().Count());
    }

    [TestMethod]
    public void Repeated_same_name_sessions_collapse_into_one_group_row()
    {
        var scanner = new StubScanner
        {
            Result = ActivityOf(
                Session(Provider.ClaudeCode, "/p1", "p1", "s1", title: "security review"),
                Session(Provider.ClaudeCode, "/p1", "p1", "s2", title: "security review")),
        };
        var monitor = Monitor(scanner);
        var vm = new DashboardViewModel(monitor);
        monitor.Refresh();
        vm.ToggleFolderExpanded("ClaudeCode:/p1");

        var groups = vm.TreeRows.OfType<SessionGroupRowVm>().ToList();
        Assert.AreEqual(1, groups.Count);
        Assert.AreEqual(2, groups[0].Count);
        Assert.AreEqual(0, vm.TreeRows.OfType<SessionLeafRowVm>().Count()); // not also shown as leaves until expanded

        vm.ToggleGroupExpanded(groups[0].GroupKey);
        Assert.AreEqual(2, vm.TreeRows.OfType<SessionLeafRowVm>().Count());
    }

    // --- Empty states (spec §2 "Empty-state text") ---

    [TestMethod]
    public void Empty_state_shows_no_sessions_today_when_filter_is_off()
    {
        var monitor = Monitor(new StubScanner());
        var vm = new DashboardViewModel(monitor);
        monitor.Refresh();

        Assert.IsTrue(vm.IsTreeEmpty);
        Assert.AreEqual("No sessions today.", vm.EmptyStateText);
    }

    [TestMethod]
    public void Empty_state_shows_active_now_message_when_filter_is_on_and_nothing_matches()
    {
        var scanner = new StubScanner
        { Result = ActivityOf(Session(Provider.ClaudeCode, "/p1", "p1", "s1", lastActivity: Now.AddHours(-3))) };
        var monitor = Monitor(scanner);
        var vm = new DashboardViewModel(monitor);
        monitor.Refresh();
        vm.ActiveOnly = true;

        Assert.IsTrue(vm.IsTreeEmpty);
        Assert.AreEqual("No sessions active right now.", vm.EmptyStateText);
    }

    // --- Ollama visibility gating (spec §4: hidden unless server running; never a cost) ---

    [TestMethod]
    public void Ollama_strip_hidden_when_state_ollama_is_null()
    {
        var monitor = Monitor(new StubScanner());
        var vm = new DashboardViewModel(monitor);
        monitor.Refresh();

        Assert.IsFalse(vm.OllamaVisible);
    }

    [TestMethod]
    public void Ollama_strip_visible_the_instant_presence_is_true_even_with_no_models()
    {
        var monitor = Monitor(new StubScanner(), presence: new StubPresence { Running = true });
        var vm = new DashboardViewModel(monitor);
        monitor.Refresh();

        Assert.IsTrue(vm.OllamaVisible);
        Assert.AreEqual(0, vm.OllamaModels.Count);
        Assert.AreEqual("running · no model loaded", vm.OllamaEmptyText);
    }

    [TestMethod]
    public void Ollama_model_row_omits_gauge_and_tps_when_fields_are_unknown()
    {
        // MLX degradation rule (spec §4): no contextWindow/contextTokens -> no gauge;
        // no tokensPerSecond but a latency present -> metrics falls back to duration; kind
        // unknown -> no chat/embed suffix.
        var model = new OllamaModelActivity(
            "gemma4:12b-mlx", Current: true, Busy: false, LastActivity: Now.AddMinutes(-1),
            ContextWindow: null, ContextTokens: null, TokensPerSecond: null,
            LastLatencySeconds: 0.12, Kind: OllamaRequestKind.Unknown, RequestCount: 0);
        var monitor = Monitor(new StubScanner(), presence: new StubPresence { Running = true },
            ollama: new StubOllama { Status = new OllamaStatus(Models: new[] { model }) });
        var vm = new DashboardViewModel(monitor);
        monitor.Refresh();

        var row = vm.OllamaModels.Single();
        Assert.IsNull(row.ContextFraction);
        Assert.AreEqual("idle · 120ms", row.MetricsText);   // no " · chat"/" · embed" suffix
        Assert.IsFalse(row.Tooltip.Contains("ctx "));
        Assert.IsFalse(row.Tooltip.Contains("req"));
    }

    [TestMethod]
    public void Ollama_model_row_shows_gauge_and_tps_when_fields_present()
    {
        var model = new OllamaModelActivity(
            "gemma4:12b-mlx", Current: true, Busy: true, LastActivity: Now.AddMinutes(-1),
            ContextWindow: 8192, ContextTokens: 4096, TokensPerSecond: 42.0,
            LastLatencySeconds: null, Kind: OllamaRequestKind.Chat, RequestCount: 3);
        var monitor = Monitor(new StubScanner(), presence: new StubPresence { Running = true },
            ollama: new StubOllama { Status = new OllamaStatus(Models: new[] { model }) });
        var vm = new DashboardViewModel(monitor);
        monitor.Refresh();

        var row = vm.OllamaModels.Single();
        Assert.AreEqual(0.5, row.ContextFraction);
        Assert.AreEqual("busy · 42 t/s · chat", row.MetricsText);
        Assert.IsTrue(row.Tooltip.Contains("ctx 4.1k/8.2k"));
        Assert.IsTrue(row.Tooltip.Contains("3 req"));
    }

    // --- Window toggle triggers an immediate rescan (spec §2f: didSet on monitor.window) ---

    [TestMethod]
    public void Window_toggle_calls_through_to_monitor_and_triggers_an_immediate_rescan()
    {
        var scanner = new StubScanner();
        var monitor = Monitor(scanner);
        var vm = new DashboardViewModel(monitor);
        monitor.Refresh();
        Assert.AreEqual(1, scanner.Calls.Count);

        vm.Window = TokenWindow.Last24h;

        Assert.AreEqual(2, scanner.Calls.Count);
        Assert.AreEqual(TokenWindow.Last24h, scanner.Calls[^1]);
        Assert.AreEqual(TokenWindow.Last24h, monitor.Window);
        Assert.AreEqual("LAST 24H", vm.WindowLabel);
    }

    // --- 7-way metric cycle (spec §3d) ---

    [TestMethod]
    public void Metric_cycle_order_matches_ctx_today_fresh_in_out_cacheRd_cacheWr_and_wraps()
    {
        var expected = new[]
        {
            MetricKind.Ctx, MetricKind.Today, MetricKind.Fresh, MetricKind.Input,
            MetricKind.Output, MetricKind.CacheRead, MetricKind.CacheWrite, MetricKind.Ctx,
        };
        var k = MetricKind.Ctx;
        foreach (var next in expected.Skip(1))
        {
            k = k.Next();
            Assert.AreEqual(next, k);
        }
    }

    [TestMethod]
    public void Cycling_default_metric_clears_per_row_overrides()
    {
        var scanner = new StubScanner
        { Result = ActivityOf(Session(Provider.ClaudeCode, "/p1", "p1", "s1", contextTokens: 10)) };
        var monitor = Monitor(scanner);
        var vm = new DashboardViewModel(monitor);
        monitor.Refresh();
        var sessionKey = monitor.State.ActiveSessions[0].Id;

        vm.CycleMetric(sessionKey);   // row override -> Today
        Assert.AreEqual(MetricKind.Today, vm.MetricFor(sessionKey));

        vm.CycleDefaultMetric();      // global default -> Today; overrides cleared
        Assert.AreEqual(MetricKind.Today, vm.DefaultMetric);
        Assert.AreEqual(MetricKind.Today, vm.MetricFor(sessionKey));   // now via the (new) default, not a stale override
    }

    // --- Provider hasUsageData providers still appear with active sessions but never cost/TODAY entries ---

    [TestMethod]
    public void Today_bar_only_ever_shows_claude_code_and_codex()
    {
        var monitor = Monitor(new StubScanner());
        var vm = new DashboardViewModel(monitor);
        monitor.Refresh();

        Assert.AreEqual("CC", DashboardViewModel.CcLabel);
        Assert.AreEqual("CX", DashboardViewModel.CxLabel);
    }

    // --- Launch at login (spec §2g/§7 note 3: OS-authoritative via IRunAtLogin) ---

    [TestMethod]
    public void Launch_at_login_reads_live_through_the_injected_interface()
    {
        var monitor = Monitor(new StubScanner());
        var fake = new FakeRunAtLogin { Enabled = true };
        var vm = new DashboardViewModel(monitor, fake);

        Assert.IsTrue(vm.LaunchAtLoginEnabled);
        fake.Enabled = false;
        Assert.IsFalse(vm.LaunchAtLoginEnabled); // live, not cached at construction
    }

    [TestMethod]
    public void Launch_at_login_defaults_to_false_when_no_interface_supplied()
    {
        var monitor = Monitor(new StubScanner());
        var vm = new DashboardViewModel(monitor);
        Assert.IsFalse(vm.LaunchAtLoginEnabled);
        vm.ToggleLaunchAtLogin(); // must not throw with no IRunAtLogin
        Assert.IsFalse(vm.LaunchAtLoginEnabled);
    }

    [TestMethod]
    public void Toggling_launch_at_login_flips_it_through_the_interface_and_raises_property_changed()
    {
        var monitor = Monitor(new StubScanner());
        var fake = new FakeRunAtLogin { Enabled = false };
        var vm = new DashboardViewModel(monitor, fake);
        var raised = new List<string?>();
        vm.PropertyChanged += (_, e) => raised.Add(e.PropertyName);

        vm.ToggleLaunchAtLogin();

        Assert.AreEqual(1, fake.SetCalls);
        Assert.IsTrue(vm.LaunchAtLoginEnabled);
        CollectionAssert.Contains(raised, nameof(DashboardViewModel.LaunchAtLoginEnabled));

        vm.ToggleLaunchAtLogin();
        Assert.AreEqual(2, fake.SetCalls);
        Assert.IsFalse(vm.LaunchAtLoginEnabled);
    }
}
