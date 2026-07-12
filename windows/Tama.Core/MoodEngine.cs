namespace Tama.Core;

/// <summary>Pure mapping from a scan to a Mood. No I/O, no clock of its own — fully injected,
/// mirror of the Swift MoodEngine.</summary>
public sealed class MoodEngine
{
    private readonly TimeSpan _activeWindow;   // active session: lastActivity within this of now
    private readonly TimeSpan _restWindow;     // beyond active but within this → resting
    private readonly TimeZoneInfo _tz;

    public MoodEngine(TimeSpan? activeWindow = null, TimeSpan? restWindow = null, TimeZoneInfo? tz = null)
    {
        _activeWindow = activeWindow ?? TimeSpan.FromSeconds(900);
        _restWindow = restWindow ?? TimeSpan.FromSeconds(3600);
        _tz = tz ?? TimeZoneInfo.Local;
    }

    public (Mood Mood, CatState State) Evaluate(Activity activity, DateTimeOffset now, CatState state)
    {
        var mostRecent = activity.Sessions.Count > 0
            ? activity.Sessions.Max(s => s.LastActivity) : (DateTimeOffset?)null;
        var activeCount = activity.Sessions.Count(s => now - s.LastActivity < _activeWindow);
        var hasActivityToday = mostRecent is { } mr && IsSameLocalDay(mr, now);

        // Greeting: a new local day AND there is activity to greet. Fires once — stamping
        // LastSeenDay makes the next scan fall through to working/resting.
        var isNewDay = state.LastSeenDay is not { } seen || !IsSameLocalDay(seen, now);
        if (hasActivityToday && isNewDay) return (Mood.Greeting, new CatState(now));

        var mood = activeCount > 0 ? Mood.Working(activeCount)
            : mostRecent is { } last && now - last < _restWindow ? Mood.Resting
            : Mood.Napping;

        // Keep LastSeenDay current whenever there's activity today, so greeting won't refire.
        return (mood, hasActivityToday ? new CatState(now) : state);
    }

    private bool IsSameLocalDay(DateTimeOffset a, DateTimeOffset b) =>
        TimeZoneInfo.ConvertTime(a, _tz).Date == TimeZoneInfo.ConvertTime(b, _tz).Date;
}
