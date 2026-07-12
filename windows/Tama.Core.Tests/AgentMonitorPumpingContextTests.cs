using System.Collections.Concurrent;
using Tama.Core;

namespace Tama.Core.Tests;

/// <summary>
/// Proves the ordering claim in AgentMonitor.Refresh's own doc comment: the `inFlight` guard
/// clears only once the marshalled <c>Apply</c> call actually RUNS on the injected
/// SynchronizationContext — not merely when the background scan work finishes. A real WPF app
/// installs a DispatcherSynchronizationContext that only runs posted callbacks when the UI
/// thread's message loop pumps them; this test stands in for that pump with a small queueing
/// SynchronizationContext under direct, deterministic control (no timers, no real UI thread).
/// </summary>
[TestClass]
public sealed class AgentMonitorPumpingContextTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-06-19T12:00:00Z");

    /// <summary>Queues posted callbacks instead of running them — the test calls <see cref="Pump"/>
    /// to run them on its own schedule, simulating a UI thread's message loop being pumped (or not
    /// yet pumped).</summary>
    private sealed class PumpingSynchronizationContext : SynchronizationContext
    {
        private readonly ConcurrentQueue<(SendOrPostCallback Callback, object? State)> _queue = new();
        public readonly ManualResetEventSlim Posted = new(false);

        public override void Post(SendOrPostCallback d, object? state)
        {
            _queue.Enqueue((d, state));
            Posted.Set();
        }

        /// <summary>Runs every callback queued so far, then resets the signal for the next round.</summary>
        public void Pump()
        {
            while (_queue.TryDequeue(out var item)) item.Callback(item.State);
            Posted.Reset();
        }
    }

    private sealed class StubScanner : IActivityScanning
    {
        public Activity Result = Activity.Empty;
        public int Calls;
        public Activity Scan(TokenWindow window) { Interlocked.Increment(ref Calls); return Result; }
    }

    private sealed class StubPresence : IOllamaPresence { public bool IsRunning() => false; }
    private sealed class StubOllama : IOllamaReading { public OllamaStatus? Read() => null; }

    private string _stateDir = null!;

    [TestInitialize]
    public void SetUp() => _stateDir = Path.Combine(Path.GetTempPath(), "mon-pump-" + Guid.NewGuid());

    [TestCleanup]
    public void TearDown() { if (Directory.Exists(_stateDir)) Directory.Delete(_stateDir, recursive: true); }

    [TestMethod]
    public void InFlight_stays_set_until_the_pumped_apply_actually_runs()
    {
        var scanner = new StubScanner();
        var ctx = new PumpingSynchronizationContext();
        var monitor = new AgentMonitor(
            scanner, new StubPresence(), new StubOllama(), new CostEstimator(),
            new MoodEngine(TimeSpan.FromSeconds(900), TimeSpan.FromSeconds(3600), TimeZoneInfo.Utc),
            new CatStateStore(_stateDir), () => Now, runsInBackground: true, syncContext: ctx);

        // 1st Refresh: the inFlight guard is set synchronously on THIS thread before Task.Run even
        // starts (AgentMonitor.Refresh), so there is no race in asserting this immediately after.
        monitor.Refresh();

        // Wait for the background scan to finish and post its "apply" callback to our queue —
        // this can take a moment since it genuinely runs on a ThreadPool thread.
        Assert.IsTrue(ctx.Posted.Wait(TimeSpan.FromSeconds(5)),
            "background scan should complete and post its apply callback");

        // The posted callback has NOT been pumped yet, so inFlight must still read as set: a
        // second Refresh() right now must be a no-op (proves inFlight isn't cleared merely because
        // the background scan work itself is done).
        monitor.Refresh();
        Assert.AreEqual(1, scanner.Calls, "second Refresh before pumping must be skipped (still in-flight)");

        // Now actually run the queued apply — this is what clears inFlight.
        ctx.Pump();

        // Only now should a new scan be allowed. The scan itself still runs on a background
        // Task.Run, so wait for it to post again before checking the call count.
        monitor.Refresh();
        Assert.IsTrue(ctx.Posted.Wait(TimeSpan.FromSeconds(5)), "third Refresh should scan and post again");
        Assert.AreEqual(2, scanner.Calls, "Refresh after pumping the apply must be allowed to scan again");
    }

    [TestMethod]
    public void State_and_StateChanged_are_only_ever_updated_on_the_pumped_context_not_the_background_thread()
    {
        var scanner = new StubScanner();
        var ctx = new PumpingSynchronizationContext();
        var monitor = new AgentMonitor(
            scanner, new StubPresence(), new StubOllama(), new CostEstimator(),
            new MoodEngine(TimeSpan.FromSeconds(900), TimeSpan.FromSeconds(3600), TimeZoneInfo.Utc),
            new CatStateStore(_stateDir), () => Now, runsInBackground: true, syncContext: ctx);

        var fired = 0;
        monitor.StateChanged += _ => fired++;

        monitor.Refresh();
        Assert.IsTrue(ctx.Posted.Wait(TimeSpan.FromSeconds(5)));

        // Before pumping, the background thread has finished scanning but StateChanged must not
        // have fired yet — publishing only happens once the context runs the posted callback.
        Assert.AreEqual(0, fired);
        Assert.AreEqual(AppState.Empty, monitor.State);

        ctx.Pump();

        Assert.AreEqual(1, fired);
        Assert.AreEqual(Now, monitor.State.LastUpdated);
    }
}
