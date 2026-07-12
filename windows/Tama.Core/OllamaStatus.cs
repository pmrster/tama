namespace Tama.Core;

/// <summary>What a model's recent requests were for — inferred from request endpoints.</summary>
public enum OllamaRequestKind
{
    Chat,     // /api/chat or /api/generate
    Embed,    // /api/embeddings or /api/embed
    Unknown,
}

/// <summary>
/// Activity attributed to one model in the current Ollama server session, built by segmenting
/// server.log between runner load/unload events. Exact for serial use; approximate if models
/// run concurrently. Mirror of the Swift OllamaModelActivity.
/// </summary>
public sealed record OllamaModelActivity(
    string Model,
    bool Current,
    bool Busy,
    DateTimeOffset? LastActivity,
    int? ContextWindow,
    int? ContextTokens,
    double? TokensPerSecond,
    double? LastLatencySeconds,
    OllamaRequestKind Kind,
    int RequestCount)
{
    /// <summary>Context-window occupancy 0…1, or null when either side is unknown.</summary>
    public double? ContextFraction =>
        ContextWindow is > 0 && ContextTokens is { } t
            ? Math.Min(1, Math.Max(0, (double)t / ContextWindow.Value)) : null;

    /// <summary>True when this model logged activity within <paramref name="window"/> of now.</summary>
    public bool Active(DateTimeOffset now, TimeSpan window) =>
        LastActivity is { } last && now - last < window;
}

/// <summary>
/// Presence + per-model activity of a local Ollama server. Not a coding-agent session —
/// surfaced as its own group, never priced. Running is filled by the caller from the
/// process table; the rest comes from a read-only parse of server.log.
/// </summary>
public sealed record OllamaStatus(
    bool Running = false,
    DateTimeOffset? LastActivity = null,
    IReadOnlyList<OllamaModelActivity>? Models = null)
{
    public IReadOnlyList<OllamaModelActivity> Models { get; init; } = Models ?? Array.Empty<OllamaModelActivity>();

    /// <summary>The currently-loaded model (best effort), else the most recently used.</summary>
    public OllamaModelActivity? CurrentModel =>
        Models.FirstOrDefault(m => m.Current) ?? Models.FirstOrDefault();

    /// <summary>True when any model is processing a request right now.</summary>
    public bool Busy => Models.Any(m => m.Busy);
}
