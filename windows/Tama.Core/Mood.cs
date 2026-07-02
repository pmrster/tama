namespace Tama.Core;

public enum MoodKind
{
    Greeting,   // transient: first activity of a new local day
    Working,    // a session is active right now (Intensity = active-session count)
    Resting,    // recent activity, but paused
    Napping,    // idle / away / nothing today
}

/// <summary>The companion cat's current feeling. Positive-only (no sad/sick states).</summary>
public readonly record struct Mood(MoodKind Kind, int Intensity = 0)
{
    public static readonly Mood Greeting = new(MoodKind.Greeting);
    public static readonly Mood Resting = new(MoodKind.Resting);
    public static readonly Mood Napping = new(MoodKind.Napping);
    public static Mood Working(int intensity) => new(MoodKind.Working, intensity);
}

/// <summary>The cat's own persisted state (NOT agent data): the last day it "saw" activity,
/// which gates the once-per-day greeting.</summary>
public sealed record CatState(DateTimeOffset? LastSeenDay)
{
    public static readonly CatState Initial = new((DateTimeOffset?)null);
}
