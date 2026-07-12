namespace Tama.Core.Ui;

/// <summary>
/// Reference-counted interactive/background poll-cadence switch — the Windows analog of the
/// Swift <c>AgentMonitor</c>'s <c>interactiveConsumers</c> field plus its
/// <c>beginInteractiveRefresh</c>/<c>endInteractiveRefresh</c> pair
/// (Sources/TamaCore/Monitor/AgentMonitor.swift). Framework-free: takes a start callback (in the
/// shipped app, <see cref="AgentMonitor"/>'s <c>Start</c> method group) rather than a concrete
/// monitor reference, so it is unit-testable with a fake and reusable by any number of
/// independent "interactive surface" consumers (popover, pinned window, ...) without any one of
/// them needing to know whether some OTHER surface is still open.
///
/// This replaces Task 6's per-surface <c>monitor.Start(...)</c> calls in <c>Program.cs</c>, which
/// had a bug: the popover's <c>Closed</c> handler unconditionally reverted to the background
/// interval even while the pinned window was still visible (review finding — task-6-report.md
/// fix wave). <see cref="Begin"/>/<see cref="End"/> must be called in pairs, one pair per surface
/// (open/close, show/hide); the background interval is only (re-)armed once every surface has
/// called <see cref="End"/> — i.e. the consumer count returns to zero — exactly mirroring the
/// Swift side's <c>interactiveConsumers == 0</c> check.
/// </summary>
public sealed class InteractivePolling
{
    private readonly Action<TimeSpan> _start;
    private readonly TimeSpan _interactiveInterval;
    private readonly TimeSpan _backgroundInterval;
    private int _consumers;

    /// <summary>Current consumer count. Never negative (see <see cref="End"/>). Exposed for tests;
    /// not otherwise meaningful to callers.</summary>
    public int Consumers => _consumers;

    public InteractivePolling(Action<TimeSpan> start, TimeSpan interactiveInterval, TimeSpan backgroundInterval)
    {
        _start = start;
        _interactiveInterval = interactiveInterval;
        _backgroundInterval = backgroundInterval;
    }

    /// <summary>One more surface now wants the interactive cadence. Always (re-)arms the
    /// interactive interval, regardless of the current count — mirrors Swift's
    /// <c>beginInteractiveRefresh</c>, which calls <c>start(interval:)</c> unconditionally.</summary>
    public void Begin()
    {
        _consumers++;
        _start(_interactiveInterval);
    }

    /// <summary>One surface no longer wants the interactive cadence. Clamps at zero — like
    /// Swift's <c>max(0, interactiveConsumers - 1)</c> — so a stray extra <see cref="End"/> call
    /// (e.g. a duplicated close event) can never go negative or require an extra
    /// <see cref="Begin"/> to re-arm background polling. Only drops to the background interval
    /// once the count actually reaches zero, i.e. every other surface has also called
    /// <see cref="End"/>.</summary>
    public void End()
    {
        _consumers = Math.Max(0, _consumers - 1);
        if (_consumers == 0)
            _start(_backgroundInterval);
    }
}
