using System.ComponentModel;

namespace Tama.Core.Ui;

/// <summary>
/// The 7-way per-row metric cycle (planc-ui-spec.md §3d; MenuBarView.swift:36-65, MetricKind).
/// Cycle order is exactly the declaration order below, wrapping via <see cref="Next"/>.
/// </summary>
public enum MetricKind { Ctx, Today, Fresh, Input, Output, CacheRead, CacheWrite }

public static class MetricKindExtensions
{
    private static readonly MetricKind[] All =
    {
        MetricKind.Ctx, MetricKind.Today, MetricKind.Fresh, MetricKind.Input,
        MetricKind.Output, MetricKind.CacheRead, MetricKind.CacheWrite,
    };

    public static string Label(this MetricKind k) => k switch
    {
        MetricKind.Ctx => "ctx",
        MetricKind.Today => "today",
        MetricKind.Fresh => "fresh",
        MetricKind.Input => "in",
        MetricKind.Output => "out",
        MetricKind.CacheRead => "cache rd",
        MetricKind.CacheWrite => "cache wr",
        _ => "",
    };

    /// <summary>Tooltip blurb (MenuBarView.swift:854-864, metricBlurb).</summary>
    public static string Blurb(this MetricKind k) => k switch
    {
        MetricKind.Ctx => "Live context-window usage right now",
        MetricKind.Today => "Today's cumulative tokens (incl. cache)",
        MetricKind.Fresh => "Today's fresh tokens (input + output, no cache)",
        MetricKind.Input => "Today's input tokens (fresh, non-cache)",
        MetricKind.Output => "Today's output tokens",
        MetricKind.CacheRead => "Today's cache-read tokens (re-read context)",
        MetricKind.CacheWrite => "Today's cache-write tokens (context cached)",
        _ => "",
    };

    public static MetricKind Next(this MetricKind k) => (MetricKind)(((int)k + 1) % All.Length);

    /// <summary>Values are pulled straight off SessionInfo/TokenBreakdown fields — never
    /// re-derived — so each is exact and additive (cache read is reads ONLY, not lumped with
    /// cache writes, MenuBarView.swift:52).</summary>
    public static int Value(this MetricKind k, SessionInfo s) => k switch
    {
        MetricKind.Ctx => s.ContextTokens,
        MetricKind.Today => s.Tokens,
        MetricKind.Fresh => s.FreshTokens,
        MetricKind.Input => s.Breakdown.Input,
        MetricKind.Output => s.Breakdown.Output,
        MetricKind.CacheRead => s.Breakdown.CacheRead,
        MetricKind.CacheWrite => s.Breakdown.CacheWrite,
        _ => 0,
    };

    public static int Value(this MetricKind k, IEnumerable<SessionInfo> sessions) => sessions.Sum(s => k.Value(s));
}

/// <summary>Base type for one flattened, already-visibility-resolved row of the popover's
/// provider/folder/session tree (planc-ui-spec.md §2). One list item == one visual row, mirroring
/// the <c>listHeight</c> row-counting formula (§2, "Popover scroll-area height formula").</summary>
public abstract record DashboardRow;

/// <summary>§2b provider header row.</summary>
public sealed record ProviderRowVm(
    Provider Provider, string DisplayName, bool Expanded, int ProjectCount, int ActiveCount,
    string ToggleTooltip) : DashboardRow
{
    /// <summary>§2b: provider name rendered uppercased ("displayName.uppercased()", :425).</summary>
    public string DisplayNameUpper => DisplayName.ToUpperInvariant();

    /// <summary>§2b: `"\(groups.count) proj · \(activeCount) active"` (:429).</summary>
    public string StatsText => $"{ProjectCount} proj · {ActiveCount} active";
}

/// <summary>§2c folder (project) row.</summary>
public sealed record FolderRowVm(
    Provider Provider, string FolderKey, string Folder, string Project, int SessionCount,
    bool Live, bool Expanded, bool PathRevealed, string PrettyPath, MetricKind Metric,
    string MetricText, string MetricTooltip, string? CostText, string CostTooltip,
    string ToggleTooltip, string RevealTooltip) : DashboardRow
{
    /// <summary>§2c: `"(\(g.sessions.count))"` session count (:458).</summary>
    public string CountText => $"({SessionCount})";
}

/// <summary>The extra row shown under a folder row when its full path is revealed (§2c).
/// Excluded from the <c>listHeight</c> row count — it is not part of the literal spec formula.</summary>
public sealed record FolderPathRowVm(string PrettyPath) : DashboardRow;

/// <summary>§3a a single session (leaf). <paramref name="Nested"/> is true when rendered inside
/// an expanded <see cref="SessionGroupRowVm"/> (always shown by id, extra indent, §3c:546-550).</summary>
public sealed record SessionLeafRowVm(
    Provider Provider, string SessionKey, string Name, bool AsId, bool Live, string? ModelBadge,
    MetricKind Metric, bool ShowGauge, double? ContextFraction, bool ContextWarn, string MetricText,
    string MetricTooltip, string? CostText, string CostTooltip, string RelativeTime, string Tooltip,
    bool Nested) : DashboardRow;

/// <summary>§3c repeated-same-prompt sessions collapsed into one row (only when count > 1).</summary>
public sealed record SessionGroupRowVm(
    Provider Provider, string GroupKey, string Name, int Count, bool Live, bool Expanded,
    string? ModelBadge, MetricKind Metric, string MetricText, string MetricTooltip, string? CostText,
    string RelativeTime, string Tooltip) : DashboardRow
{
    /// <summary>§3c: `"×\(ng.sessions.count)"` (:513).</summary>
    public string CountText => $"×{Count}";
}

/// <summary>§4 Ollama per-model status dot state: busy (yellow) > active-within-15min (green) >
/// idle (dim).</summary>
public enum OllamaDotState { Busy, Active, Idle }

/// <summary>§4 one Ollama model row. <see cref="ContextFraction"/> is null under the MLX
/// degradation rules (no gauge rendered, never a borrowed/zero value).</summary>
public sealed record OllamaModelRowVm(
    string Model, OllamaDotState Dot, double? ContextFraction, bool ContextWarn, string MetricsText,
    string Tooltip);

/// <summary>
/// Projects <see cref="AgentMonitor"/>'s published <see cref="AppState"/> into the popover's
/// display rows (planc-ui-spec.md §2/§3/§4). Framework-free — WPF's DashboardView binds directly
/// to this. Long-lived by design (constructed once alongside the AgentMonitor, not per popover
/// open/close): it owns exactly the state the Swift port keeps in its process-lifetime
/// <c>UIState.shared</c> singleton (collapse/expand sets, active-only filter, metric selections),
/// which persists across the transient popover being closed and reopened — see planc-ui-spec.md
/// §7 note 7. (Ollama's own collapse toggle is deliberately NOT here — the Swift source keeps it
/// as per-view @State that resets on every re-host, spec §4; that toggle belongs to the WPF view.)
/// </summary>
public sealed class DashboardViewModel : INotifyPropertyChanged
{
    private const string CostCaveat =
        "Estimated pay-as-you-go API cost from public per-token rates — not your actual bill (Max/Pro " +
        "subscriptions are billed differently). May read slightly under Claude's /cost, which also " +
        "counts interrupted/in-flight turns not yet saved to the logs Tama reads.";

    private readonly AgentMonitor _monitor;
    private readonly IRunAtLogin? _runAtLogin;
    private readonly HashSet<Provider> _collapsedProviders = new();
    private readonly HashSet<string> _expandedFolders = new();
    private readonly HashSet<string> _expandedGroups = new();
    private readonly HashSet<string> _revealedPaths = new();
    private readonly Dictionary<string, MetricKind> _rowMetric = new();
    private bool _activeOnly;
    private MetricKind _defaultMetric = MetricKind.Ctx;

    public event PropertyChangedEventHandler? PropertyChanged;

    /// <summary><paramref name="runAtLogin"/> is optional (null in most tests that don't care
    /// about the footer's launch-at-login checkbox) — mirrors every other optional collaborator
    /// pattern in this codebase (e.g. AppSettingsViewModel's systemIsDark/onAppearanceChanged).</summary>
    public DashboardViewModel(AgentMonitor monitor, IRunAtLogin? runAtLogin = null)
    {
        _monitor = monitor;
        _runAtLogin = runAtLogin;
        _monitor.StateChanged += _ => Recompute();
        Recompute();
    }

    /// <summary>Footer "Launch at login" checkbox (spec §2g/§7 note 3): OS-authoritative, queried
    /// live through the injected <see cref="IRunAtLogin"/> rather than a persisted flag (mirrors
    /// mac's <c>SMAppService.mainApp.status</c>). False when no <see cref="IRunAtLogin"/> was
    /// supplied.</summary>
    public bool LaunchAtLoginEnabled => _runAtLogin?.IsEnabled() ?? false;

    /// <summary>Toggles launch-at-login through the injected interface; a no-op if none was
    /// supplied. Raises PropertyChanged so the view refreshes its checkbox glyph immediately.</summary>
    public void ToggleLaunchAtLogin()
    {
        if (_runAtLogin is null) return;
        _runAtLogin.SetEnabled(!LaunchAtLoginEnabled);
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(LaunchAtLoginEnabled)));
    }

    // ---- user-facing toggles (mirror UIState.shared) ----

    public bool ActiveOnly
    {
        get => _activeOnly;
        set { if (_activeOnly == value) return; _activeOnly = value; Recompute(); }
    }

    /// <summary>Changing this calls through to AgentMonitor.Window, whose own setter triggers an
    /// immediate rescan (didSet semantics, spec §2f) — StateChanged then drives our Recompute.</summary>
    public TokenWindow Window
    {
        get => _monitor.Window;
        set => _monitor.Window = value;
    }

    public MetricKind DefaultMetric => _defaultMetric;

    /// <summary>Header metric-cycle button: advances the global default AND clears every
    /// per-row override, so all rows visibly snap to the new type (MenuBarView.swift:836-839).</summary>
    public void CycleDefaultMetric()
    {
        _defaultMetric = _defaultMetric.Next();
        _rowMetric.Clear();
        Recompute();
    }

    /// <summary>Tapping a single row's number cycles only that row (:830-831).</summary>
    public void CycleMetric(string key)
    {
        _rowMetric[key] = MetricFor(key).Next();
        Recompute();
    }

    public MetricKind MetricFor(string key) => _rowMetric.TryGetValue(key, out var m) ? m : _defaultMetric;

    public void ToggleProviderCollapsed(Provider p)
    {
        if (!_collapsedProviders.Remove(p)) _collapsedProviders.Add(p);
        Recompute();
    }

    public void ToggleFolderExpanded(string key) { Toggle(_expandedFolders, key); Recompute(); }
    public void ToggleGroupExpanded(string key) { Toggle(_expandedGroups, key); Recompute(); }
    public void ToggleRevealedPath(string key) { Toggle(_revealedPaths, key); Recompute(); }

    public bool AnyFolderExpanded => _expandedFolders.Count > 0;

    /// <summary>Header expand/collapse-all button (MenuBarView.swift:888-892).</summary>
    public void ExpandOrCollapseAll()
    {
        if (AnyFolderExpanded)
        {
            _expandedFolders.Clear();
        }
        else
        {
            foreach (var p in Enum.GetValues<Provider>())
            {
                var sessions = SessionsFor(p);
                if (sessions.Count == 0) continue;
                foreach (var g in FolderGroups(sessions)) _expandedFolders.Add(FolderKey(p, g.Folder));
            }
        }
        Recompute();
    }

    private static void Toggle(HashSet<string> set, string key) { if (!set.Remove(key)) set.Add(key); }

    /// <summary>Proxies AgentMonitor.Refresh() so the WPF view only ever needs this VM, never a
    /// direct AgentMonitor reference (header "Refresh now" icon, MenuBarView.swift:372).</summary>
    public void RefreshNow() => _monitor.Refresh();

    /// <summary>The pixel-cat strip's current mood (PetView(mood:), spec §2 layout tree).</summary>
    public Mood Mood => _monitor.State.Mood;

    public string DefaultMetricLabel => _defaultMetric.Label();

    /// <summary>listHeight + 22, exactly as the popover's `tree` applies on top of listHeight
    /// (MenuBarView.swift:239).</summary>
    public int PopoverListHeight => ListHeight + 22;

    // ---- derived display state, recomputed on every AgentMonitor.StateChanged ----

    public IReadOnlyList<DashboardRow> TreeRows { get; private set; } = Array.Empty<DashboardRow>();
    public bool IsTreeEmpty { get; private set; } = true;
    public string EmptyStateText { get; private set; } = "No sessions today.";

    /// <summary>Popover scroll-area height in points, per the exact §2 formula: <c>clamp(rows * 26
    /// + 16, min: 60, max: 340)</c> — ported literally, including its use of the raw (uncollapsed)
    /// session count for expanded folders rather than the name-group-collapsed row count actually
    /// rendered (MenuBarView.swift:171-182 does the same; not "fixed" here for parity).</summary>
    public int ListHeight { get; private set; } = 60;

    public bool OllamaVisible { get; private set; }
    public bool OllamaBusy { get; private set; }
    public string OllamaCountLabel { get; private set; } = "";
    public string? OllamaEmptyText { get; private set; }
    public IReadOnlyList<OllamaModelRowVm> OllamaModels { get; private set; } = Array.Empty<OllamaModelRowVm>();

    public int ActiveNow { get; private set; }
    public string AgentsWord { get; private set; } = "agents active";

    public string WindowLabel => Window == TokenWindow.Today ? "TODAY" : "LAST 24H";
    public string WindowPhrase => Window == TokenWindow.Today
        ? "Today (since local midnight)" : "Last 24 hours (rolling)";
    public string WindowNoun => Window == TokenWindow.Today ? "today" : "in the last 24h";

    public string WindowToggleTooltip => Window == TokenWindow.Today
        ? "Token/cost totals cover TODAY (since local midnight, matching the providers' daily usage reset). Click for a rolling LAST 24H window."
        : "Token/cost totals cover the rolling LAST 24H. Click to switch back to TODAY (since local midnight).";

    // TODAY bar: always exactly Claude Code then Codex, hardcoded — never looped over
    // visibleProviders (spec §2f).
    public const string CcLabel = "CC";
    public const string CxLabel = "CX";
    public string CcTokensText { get; private set; } = "0";
    public string CxTokensText { get; private set; } = "0";
    /// <summary>" ~$4.10" — leading space + formatCost, or "" when the cost is 0, exactly the
    /// `cost > 0 ? " " + formatCost(cost) : ""` concatenation of todayEntry (:663).</summary>
    public string CcCostText { get; private set; } = "";
    public string CxCostText { get; private set; } = "";
    public string TodayTooltip { get; private set; } = "";

    public string MetricCycleTooltip =>
        $"All rows show {_defaultMetric.Label()} ({_defaultMetric.Blurb()}). Click to switch all to " +
        $"{_defaultMetric.Next().Label()} — cycles ctx → today → fresh → in → out → cache rd → cache wr. " +
        "Or tap a single number to switch just that row.";

    public string ActiveOnlyTooltip => _activeOnly
        ? "Active-now filter is ON — showing only sessions with activity in the last 15 min. Click to show all of today."
        : "Active-now filter — show only sessions active in the last 15 min (hide idle ones). Click to turn on.";

    public string ExpandCollapseAllTooltip => AnyFolderExpanded ? "Collapse all folders" : "Expand all folders";

    public const string PinTooltip = "Keep on screen (pin/unpin)";
    public const string RefreshTooltip = "Refresh now";
    public const string LaunchAtLoginTooltip = "Start automatically when you log in.";
    public const string AboutTooltip = "About Tama — show the installed version";
    public const string QuitTooltip = "Quit Tama";
    public const string InfoButtonTooltip = "How these numbers are calculated";
    public const string InfoPopoverTitle = "How the numbers are calculated";

    /// <summary>§2e legend: dim prefix, then alternating yellow-name/dim-description pairs joined
    /// by " · ", no trailing separator on the last.</summary>
    public const string LegendPrefix = "tap any number · ";
    public static readonly IReadOnlyList<(string Name, string DescWithSeparator)> LegendPieces = new (string, string)[]
    {
        ("ctx", "live context · "),
        ("today", "total incl cache · "),
        ("fresh", "in+out · "),
        ("in", "input · "),
        ("out", "output · "),
        ("cache rd", "cache reads · "),
        ("cache wr", "cache writes"),
    };

    /// <summary>§2f the (?) info popover's 6 rows, verbatim.</summary>
    public static readonly IReadOnlyList<(string Name, string Desc)> InfoRows = new (string, string)[]
    {
        ("TODAY / 24H", "Window for the token + cost totals. TODAY = since local midnight (matches the providers' daily reset); 24H = rolling last 24 hours. Tap the label to switch. Includes cache reads."),
        ("ctx", "How full the context window is right now — the live conversation size, not a windowed total."),
        ("red row", "Idle: the session's last log write was over 15 min ago. A green dot means active within 15 min."),
        ("$ cost", "Estimated pay-as-you-go API price of the windowed tokens — an estimate, not your subscription bill."),
        ("source", "Read-only from ~/.claude and ~/.codex logs. Claude is summed per assistant reply, counted once per message id (the log repeats each reply's usage across its thinking/text lines); Codex reports its session-cumulative total."),
        ("vs claude /cost", "Tama reads the saved session logs; Claude's /cost reads its live billing. They match on completed turns and differ only by an interrupted or still-running turn — a call Claude billed but hasn't written to the log yet. Tama never touches the network, so reading a little under /cost is expected, not an error; it catches up once the turn is saved."),
    };

    // ---- recompute ----

    private void Recompute()
    {
        var state = _monitor.State;
        var rows = new List<DashboardRow>();
        var visibleProviderCount = 0;
        var listRows = 0;

        foreach (var p in Enum.GetValues<Provider>())
        {
            var sessions = SessionsFor(p, state);
            if (sessions.Count == 0) continue;
            visibleProviderCount++;
            listRows += 1;   // the provider header row itself

            var expanded = !_collapsedProviders.Contains(p);
            var groups = FolderGroups(sessions);
            rows.Add(new ProviderRowVm(p, p.DisplayName(), expanded, groups.Count, _monitor.ActiveCount(p),
                expanded ? "Collapse this provider" : "Expand this provider's projects"));
            if (!expanded) continue;

            listRows += groups.Count;   // one folder-group row each, once the provider is expanded

            foreach (var g in groups)
            {
                var fKey = FolderKey(p, g.Folder);
                var folderExpanded = _expandedFolders.Contains(fKey);
                var revealed = _revealedPaths.Contains(fKey);
                var live = g.Sessions.Any(_monitor.IsActive);
                var metric = MetricFor("F:" + fKey);
                var cost = Cost(g.Sessions);

                rows.Add(new FolderRowVm(
                    p, fKey, g.Folder, g.Project, g.Sessions.Count, live, folderExpanded, revealed,
                    PrettyFolder(g.Folder), metric, MetricText(metric.Value(g.Sessions)),
                    FolderMetricTooltip(metric, g.Sessions),
                    cost >= 0.01 ? Formatters.FormatCost(cost) : null,
                    $"{CostCaveat}\nThis project {WindowNoun}: {Formatters.FormatCost(cost)}.",
                    folderExpanded ? "Collapse this folder's sessions" : "Expand this folder's sessions",
                    revealed ? "Hide folder path" : "Show folder path"));

                if (revealed) rows.Add(new FolderPathRowVm(PrettyFolder(g.Folder)));
                if (!folderExpanded) continue;

                listRows += g.Sessions.Count;   // literal spec formula: raw sessions, not name-groups

                foreach (var ng in NameGroups(g.Sessions))
                {
                    if (ng.Sessions.Count == 1)
                    {
                        rows.Add(BuildLeaf(ng.Sessions[0], p, nested: false));
                        continue;
                    }
                    var gKey = GroupKey(p, g.Folder, ng.Name);
                    var groupExpanded = _expandedGroups.Contains(gKey);
                    rows.Add(BuildGroup(p, ng, gKey, groupExpanded));
                    if (groupExpanded)
                        foreach (var s in ng.Sessions) rows.Add(BuildLeaf(s, p, nested: true));
                }
            }
        }

        TreeRows = rows;
        IsTreeEmpty = visibleProviderCount == 0;
        EmptyStateText = _activeOnly ? "No sessions active right now." : "No sessions today.";
        ListHeight = Math.Min(Math.Max(listRows * 26 + 16, 60), 340);

        RecomputeOllama(state);
        RecomputeHeaderAndToday(state);

        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(string.Empty));
    }

    private void RecomputeOllama(AppState state)
    {
        var o = state.Ollama;
        OllamaVisible = o is not null;
        if (o is null)
        {
            OllamaBusy = false;
            OllamaCountLabel = "";
            OllamaEmptyText = null;
            OllamaModels = Array.Empty<OllamaModelRowVm>();
            return;
        }

        OllamaBusy = o.Busy;
        var n = o.Models.Count;
        OllamaCountLabel = (n == 1 ? "1 model" : $"{n} models") + " · local · free";
        OllamaEmptyText = n == 0 ? "running · no model loaded" : null;
        OllamaModels = o.Models.Select(m => BuildOllamaRow(m, state)).ToList();
    }

    private static OllamaModelRowVm BuildOllamaRow(OllamaModelActivity m, AppState state)
    {
        var active = m.Active(state.LastUpdated, AgentMonitor.ActiveWindow);
        var dot = m.Busy ? OllamaDotState.Busy : active ? OllamaDotState.Active : OllamaDotState.Idle;
        var frac = m.ContextFraction;
        var warn = frac is { } f && f >= 0.9;

        var parts = new List<string> { m.Busy ? "busy" : "idle" };
        if (m.Busy && m.TokensPerSecond is { } tps) parts.Add($"{RoundInt(tps)} t/s");
        else if (m.LastLatencySeconds is { } lat) parts.Add(Formatters.FormatDuration(lat));
        if (m.Kind != OllamaRequestKind.Unknown) parts.Add(m.Kind == OllamaRequestKind.Embed ? "embed" : "chat");

        var bits = new List<string> { m.Model, m.Current ? "loaded" : "used this session" };
        if (m.ContextWindow is { } w) bits.Add($"ctx {Formatters.FormatTokens(m.ContextTokens ?? 0)}/{Formatters.FormatTokens(w)}");
        if (m.RequestCount > 0) bits.Add($"{m.RequestCount} req");
        if (m.TokensPerSecond is { } tps2) bits.Add($"{RoundInt(tps2)} tok/s");

        return new OllamaModelRowVm(m.Model, dot, frac, warn, string.Join(" · ", parts), string.Join(" · ", bits));
    }

    private void RecomputeHeaderAndToday(AppState state)
    {
        ActiveNow = _monitor.ActiveCount();
        AgentsWord = ActiveNow == 1 ? "agent active" : "agents active";

        var cc = state.Usage.TryGetValue(Provider.ClaudeCode, out var ccUsage) ? ccUsage : UsageStats.Empty;
        var cx = state.Usage.TryGetValue(Provider.Codex, out var cxUsage) ? cxUsage : UsageStats.Empty;
        CcTokensText = Formatters.FormatTokens(cc.TodayTokens);
        CxTokensText = Formatters.FormatTokens(cx.TodayTokens);
        CcCostText = cc.TodayCost > 0 ? " " + Formatters.FormatCost(cc.TodayCost) : "";
        CxCostText = cx.TodayCost > 0 ? " " + Formatters.FormatCost(cx.TodayCost) : "";
        TodayTooltip = $"{CostCaveat}\n{WindowPhrase}: Claude {Formatters.FormatCost(cc.TodayCost)}, " +
            $"Codex {Formatters.FormatCost(cx.TodayCost)}.";
    }

    // ---- row builders ----

    private SessionLeafRowVm BuildLeaf(SessionInfo s, Provider provider, bool nested)
    {
        var asId = nested || s.Title is null;
        var name = nested ? s.SessionId ?? "session" : s.DisplayName;
        var metric = MetricFor(s.Id);
        var showGauge = metric == MetricKind.Ctx;
        double? frac = null;
        bool warn = false;
        string metricText;
        string metricTooltip;
        if (showGauge)
        {
            if (s.ContextTokens > 0)
            {
                frac = s.ContextFraction;
                warn = frac is { } f && f >= 0.9;
                metricText = Formatters.FormatTokens(s.ContextTokens);   // popover: no " ctx" suffix
                // The gauge's own inner .help(contextHelp(s)) (§3b, :647) sits deeper in the view
                // tree than sessionMetric's outer .help(sessionMetricHelp) (§3a, :622) and is what
                // AppKit actually surfaces on hover in ctx mode.
                metricTooltip = ContextHelp(s);
            }
            else
            {
                metricText = "—";   // the "—" Text has no .help override of its own (:649-651)
                metricTooltip = SessionMetricTooltip(metric, s);
            }
        }
        else
        {
            metricText = MetricText(metric.Value(s));
            metricTooltip = SessionMetricTooltip(metric, s);
        }

        var cost = _monitor.Cost(s);
        return new SessionLeafRowVm(
            provider, s.Id, name, asId, _monitor.IsActive(s),
            s.Model is { } m ? Formatters.PrettyModel(m) : null,
            metric, showGauge, frac, warn, metricText,
            metricTooltip,
            cost >= 0.01 ? Formatters.FormatCost(cost) : null,
            $"{CostCaveat}\nThis session {WindowNoun}: {Formatters.FormatCost(cost)}.",
            Formatters.RelativeTime(_monitor.State.LastUpdated, s.LastActivity),
            SessionTooltip(s),
            nested);
    }

    private SessionGroupRowVm BuildGroup(Provider p, NameGroup ng, string gKey, bool expanded)
    {
        var live = ng.Sessions.Any(_monitor.IsActive);
        var model = UniformModel(ng.Sessions);
        var metric = MetricFor("G:" + gKey);
        var cost = Cost(ng.Sessions);
        return new SessionGroupRowVm(
            p, gKey, ng.Name, ng.Sessions.Count, live, expanded,
            model is { } m ? Formatters.PrettyModel(m) : null,
            metric, MetricText(metric.Value(ng.Sessions)),
            GroupMetricTooltip(metric, ng.Sessions),
            cost >= 0.01 ? Formatters.FormatCost(cost) : null,
            Formatters.RelativeTime(_monitor.State.LastUpdated, ng.Last),
            $"{ng.Sessions.Count} sessions that each began with this prompt. Tokens are the sum; expand to see each session.");
    }

    // ---- grouping helpers ----

    private sealed record FolderGroup(string Folder, string Project, IReadOnlyList<SessionInfo> Sessions, DateTimeOffset Last);
    private sealed record NameGroup(string Name, IReadOnlyList<SessionInfo> Sessions)
    {
        public DateTimeOffset Last => Sessions.Count == 0 ? DateTimeOffset.MinValue : Sessions.Max(s => s.LastActivity);
    }

    private IReadOnlyList<SessionInfo> SessionsFor(Provider p) => SessionsFor(p, _monitor.State);

    private IReadOnlyList<SessionInfo> SessionsFor(Provider p, AppState state)
    {
        IEnumerable<SessionInfo> all = state.ActiveSessions.Where(s => s.Provider == p);
        if (_activeOnly) all = all.Where(_monitor.IsActive);
        return all.ToList();
    }

    private static IReadOnlyList<FolderGroup> FolderGroups(IReadOnlyList<SessionInfo> sessions) =>
        sessions.GroupBy(s => s.Folder)
            .Select(g =>
            {
                var ordered = g.OrderByDescending(s => s.LastActivity).ToList();
                return new FolderGroup(g.Key, ordered[0].Project, ordered, ordered.Max(s => s.LastActivity));
            })
            .OrderByDescending(fg => fg.Last)
            .ToList();

    private static IReadOnlyList<NameGroup> NameGroups(IReadOnlyList<SessionInfo> sessions) =>
        sessions.GroupBy(s => s.DisplayName)
            .Select(g => new NameGroup(g.Key, g.OrderByDescending(s => s.LastActivity).ToList()))
            .OrderByDescending(ng => ng.Last)
            .ToList();

    private static string? UniformModel(IReadOnlyList<SessionInfo> sessions)
    {
        var models = sessions.Select(s => s.Model).Where(m => m is not null).Distinct().ToList();
        return models.Count == 1 ? models[0] : null;
    }

    private double Cost(IReadOnlyList<SessionInfo> sessions) => sessions.Sum(_monitor.Cost);

    private static string FolderKey(Provider p, string folder) => $"{p}:{folder}";
    private static string GroupKey(Provider p, string folder, string name) => $"{p}:{folder}:{name}";

    /// <summary>"—" when the value is 0 (no data of this type for this row), else the formatted
    /// number — never a borrowed/wrong number (MenuBarView.swift:843-852). The popover drops the
    /// per-row type-label suffix the pinned window would append; Task 4 only hosts the popover.</summary>
    private static string MetricText(int value) => value <= 0 ? "—" : Formatters.FormatTokens(value);

    private static string PrettyFolder(string path) =>
        Formatters.PrettyFolder(path, Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));

    private string SessionMetricTooltip(MetricKind kind, SessionInfo s) =>
        $"Showing: {kind.Label()} — {kind.Blurb()}: {Formatters.FormatTokens(kind.Value(s))}.\n" +
        "Click to switch type (ctx → today → fresh → in → out → cache rd → cache wr). '—' means no data of this type.";

    private static string FolderMetricTooltip(MetricKind kind, IReadOnlyList<SessionInfo> sessions) =>
        $"{kind.Blurb()}, summed across this project's {sessions.Count} session(s): " +
        $"{Formatters.FormatTokens(kind.Value(sessions))}.\nClick to switch type.";

    private static string GroupMetricTooltip(MetricKind kind, IReadOnlyList<SessionInfo> sessions) =>
        $"{kind.Blurb()}, summed across these {sessions.Count} sessions: " +
        $"{Formatters.FormatTokens(kind.Value(sessions))}.\nClick to switch type.";

    private string SessionTooltip(SessionInfo s)
    {
        var lines = new List<string>
        {
            $"One {s.Provider.DisplayName()} session (a single conversation) — not a subagent.",
        };
        if (s.Title is { } t) lines.Add($"Title: {t}");
        if (s.SessionId is { } id) lines.Add($"Session id: {id}");
        if (s.Messages > 0) lines.Add($"Messages: {s.Messages} (conversation length — the count Claude /resume shows)");
        if (s.ContextTokens > 0)
        {
            var pct = s.ContextFraction is { } f ? $" ({RoundInt(f * 100)}% full)" : "";
            var win = s.ContextWindow > 0 ? $" / {Formatters.FormatTokens(s.ContextWindow)}" : "";
            lines.Add($"Context now: {Formatters.FormatTokens(s.ContextTokens)}{win}{pct}");
        }
        if (s.Tokens > 0)
        {
            lines.Add($"{WindowPhrase}: {Formatters.FormatTokens(s.Tokens)} total · " +
                $"{Formatters.FormatTokens(s.FreshTokens)} fresh · {Formatters.FormatTokens(s.CacheTokens)} cache");
            var cost = _monitor.Cost(s);
            if (cost > 0) lines.Add($"Est. API cost {WindowNoun}: {Formatters.FormatCost(cost)}  ({CostCaveat})");
        }
        return string.Join("\n", lines);
    }

    /// <summary>Context-window gauge tooltip (MenuBarView.swift:654-659, contextHelp).</summary>
    private static string ContextHelp(SessionInfo s)
    {
        var pct = s.ContextFraction is { } f ? $" ({RoundInt(f * 100)}%)" : "";
        var win = s.ContextWindow > 0 ? $" / {Formatters.FormatTokens(s.ContextWindow)}" : "";
        return $"Context window: {Formatters.FormatTokens(s.ContextTokens)}{win}{pct} in use right now.\n" +
            "Live conversation size — not today's cumulative tokens (see the session tooltip / TODAY).";
    }

    private static int RoundInt(double v) => (int)Math.Round(v, MidpointRounding.AwayFromZero);
}
