namespace Tama.Core;

/// <summary>
/// Polls the scanners on a background thread and publishes AppState snapshots. UI-framework-free:
/// pass the UI thread's SynchronizationContext to marshal StateChanged onto it (WPF does this in
/// Tama.Tray); tests pass null and receive events on the worker thread. Mirror of the Swift
/// AgentMonitor (Combine/@MainActor replaced by event + SynchronizationContext).
/// </summary>
public sealed class AgentMonitor : IDisposable
{
    private readonly IActivityScanning _scanner;
    private readonly IOllamaPresence _presence;
    private readonly IOllamaReading _ollamaReader;
    private readonly CostEstimator _estimator;
    private readonly MoodEngine _moodEngine;
    private readonly CatStateStore _catStateStore;
    private readonly Func<DateTimeOffset> _now;
    private readonly bool _runsInBackground;
    private readonly SynchronizationContext? _syncContext;
    private Timer? _timer;
    private TimeSpan? _currentInterval;
    private int _inFlight;
    private CatState _catState;
    private TokenWindow _window = TokenWindow.Today;

    public AppState State { get; private set; } = AppState.Empty;
    public event Action<AppState>? StateChanged;

    /// <summary>"Active" = a session whose log was written within this of the last scan.</summary>
    public static readonly TimeSpan ActiveWindow = TimeSpan.FromSeconds(900);

    public AgentMonitor(IActivityScanning scanner, IOllamaPresence presence,
        IOllamaReading ollamaReader, CostEstimator estimator, MoodEngine moodEngine,
        CatStateStore catStateStore, Func<DateTimeOffset> now,
        bool runsInBackground = true, SynchronizationContext? syncContext = null)
    {
        _scanner = scanner;
        _presence = presence;
        _ollamaReader = ollamaReader;
        _estimator = estimator;
        _moodEngine = moodEngine;
        _catStateStore = catStateStore;
        _now = now;
        _runsInBackground = runsInBackground;
        _syncContext = syncContext;
        _catState = catStateStore.Load();
    }

    /// <summary>Window for displayed totals; changing it re-scans immediately (cache makes it cheap).</summary>
    public TokenWindow Window
    {
        get => _window;
        set { if (_window != value) { _window = value; Refresh(); } }
    }

    /// <summary>Estimated pay-as-you-go cost of this session's tokens (not a subscription bill).</summary>
    public double Cost(SessionInfo s) => _estimator.Cost(s.Breakdown, s.Provider, s.Model);

    /// <summary>Scans and publishes the new state. Background mode skips overlapping calls;
    /// runsInBackground: false (tests) scans synchronously on the caller's thread. With a real
    /// SynchronizationContext, the inFlight flag clears after the marshalled apply completes.</summary>
    public void Refresh()
    {
        var now = _now();
        var window = _window;
        if (!_runsInBackground)
        {
            Apply(_scanner.Scan(window), OllamaState(_presence.IsRunning(), _ollamaReader.Read()), now);
            return;
        }
        if (Interlocked.CompareExchange(ref _inFlight, 1, 0) != 0) return;
        Task.Run(() =>
        {
            try
            {
                var activity = _scanner.Scan(window);
                var ollama = OllamaState(_presence.IsRunning(), _ollamaReader.Read());
                Publish(() =>
                {
                    try { Apply(activity, ollama, now); }
                    finally { Interlocked.Exchange(ref _inFlight, 0); }
                });
            }
            catch
            {
                Interlocked.Exchange(ref _inFlight, 0);
                throw;
            }
        });
    }

    /// <summary>Gates the tile: hidden unless the server is running; else running + enrichment.</summary>
    public static OllamaStatus? OllamaState(bool presence, OllamaStatus? enrichment) =>
        presence ? (enrichment ?? new OllamaStatus()) with { Running = true } : null;

    private void Publish(Action apply)
    {
        if (_syncContext is { } ctx) ctx.Post(_ => apply(), null);
        else apply();
    }

    private void Apply(Activity activity, OllamaStatus? ollama, DateTimeOffset now)
    {
        var usage = new Dictionary<Provider, UsageStats>();
        foreach (var (provider, tokens) in activity.Totals)
        {
            // Price each model's tokens at its own tier, then sum; fall back to the rolled-up
            // breakdown at the default rate when no per-model split is available.
            double cost;
            if (activity.ModelBreakdowns.TryGetValue(provider, out var perModel) && perModel.Count > 0)
                cost = perModel.Sum(kv =>
                    _estimator.Cost(kv.Value, provider, kv.Key.Length == 0 ? null : kv.Key));
            else
                cost = activity.Breakdowns.TryGetValue(provider, out var bd)
                    ? _estimator.Cost(bd, provider) : 0;
            usage[provider] = new UsageStats(tokens, cost);
        }
        var (mood, newCatState) = _moodEngine.Evaluate(activity, now, _catState);
        if (newCatState != _catState)
        {
            _catState = newCatState;
            _catStateStore.Save(newCatState);
        }
        State = new AppState(usage, now, activity.Sessions, mood, ollama);
        StateChanged?.Invoke(State);
    }

    /// <summary>Starts (or re-arms) the poll timer. Idempotent for the same interval.</summary>
    public void Start(TimeSpan interval)
    {
        if (interval <= TimeSpan.Zero) { Stop(); return; }
        if (_timer is not null && _currentInterval == interval) return;
        _timer?.Dispose();
        _currentInterval = interval;
        Refresh();
        _timer = new Timer(_ => Refresh(), null, interval, interval);
    }

    public void Stop()
    {
        _timer?.Dispose();
        _timer = null;
        _currentInterval = null;
    }

    public bool IsActive(SessionInfo s) => State.LastUpdated - s.LastActivity < ActiveWindow;

    public int ActiveCount(Provider? provider = null) =>
        State.ActiveSessions.Count(s => (provider is null || s.Provider == provider) && IsActive(s));

    public void Dispose() => Stop();
}
