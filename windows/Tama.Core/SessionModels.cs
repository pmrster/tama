namespace Tama.Core;

/// <summary>Which time window the displayed token/cost totals cover.</summary>
public enum TokenWindow
{
    Today,      // since tz-local midnight
    Last24h,    // trailing 24 hours
}

/// <summary>
/// A recently-active agent session, named by its project folder (from the log's cwd).
/// Tokens = the window's CUMULATIVE tokens (incl. cache); ContextTokens/ContextWindow =
/// live context occupancy — never conflate the two (spec/log-formats.md).
/// </summary>
public sealed record SessionInfo(
    Provider Provider,
    string Project,
    string Folder,
    DateTimeOffset LastActivity,
    int Tokens = 0,
    int CacheTokens = 0,
    int ContextTokens = 0,
    int ContextWindow = 0,
    string? Model = null,
    string? SessionId = null,
    string? Title = null,
    TokenBreakdown Breakdown = default,
    int Messages = 0)
{
    /// <summary>Fresh (non-cache) tokens = input + output.</summary>
    public int FreshTokens => Math.Max(0, Tokens - CacheTokens);

    /// <summary>Live window occupancy 0…1, or null if unknown. NOT the cumulative tokens.</summary>
    public double? ContextFraction =>
        ContextWindow > 0 && ContextTokens > 0
            ? Math.Min(1, (double)ContextTokens / ContextWindow) : null;

    /// <summary>The session's display name: title, else short id, else "session".</summary>
    public string DisplayName => Title ?? SessionId ?? "session";

    public string Id => $"{Provider}:{Folder}:{SessionId}";
}

/// <summary>
/// Result of one scan: the (capped) session list for display + full per-provider totals,
/// with per-model breakdowns for tier-accurate pricing. Mirror of the Swift Activity.
/// </summary>
public sealed record Activity(
    IReadOnlyList<SessionInfo> Sessions,
    IReadOnlyDictionary<Provider, int> Totals,
    IReadOnlyDictionary<Provider, TokenBreakdown> Breakdowns,
    IReadOnlyDictionary<Provider, IReadOnlyDictionary<string, TokenBreakdown>> ModelBreakdowns)
{
    public static readonly Activity Empty = new(
        Array.Empty<SessionInfo>(),
        new Dictionary<Provider, int>(),
        new Dictionary<Provider, TokenBreakdown>(),
        new Dictionary<Provider, IReadOnlyDictionary<string, TokenBreakdown>>());
}

/// <summary>Something that can produce an Activity snapshot (the scanner, or a test stub).</summary>
public interface IActivityScanning
{
    Activity Scan(TokenWindow window);
}
