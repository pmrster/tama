namespace Tama.Core;

public sealed record UsageStats(int TodayTokens, double TodayCost)
{
    public static readonly UsageStats Empty = new(0, 0);
}

/// <summary>The monitor's published snapshot. Mirror of the Swift AppState (minus the
/// process-table session list, which the Windows UI does not use).</summary>
public sealed record AppState(
    IReadOnlyDictionary<Provider, UsageStats> Usage,
    DateTimeOffset LastUpdated,
    IReadOnlyList<SessionInfo> ActiveSessions,
    Mood Mood,
    OllamaStatus? Ollama)
{
    public static readonly AppState Empty = new(
        new Dictionary<Provider, UsageStats>(), DateTimeOffset.MinValue,
        Array.Empty<SessionInfo>(), Mood.Napping, null);
}
