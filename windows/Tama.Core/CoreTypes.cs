namespace Tama.Core;

public enum Provider
{
    ClaudeCode,
    Codex,
    Gemini,
    Antigravity,
}

/// <summary>Display metadata for each <see cref="Provider"/> — mirror of the Swift Provider
/// extension (CoreTypes.swift:9-33). <c>Provider.allCases</c>/enum declaration order (ClaudeCode,
/// Codex, Gemini, Antigravity) IS the dashboard's provider display order (planc-ui-spec.md §2b).</summary>
public static class ProviderInfo
{
    public static string DisplayName(this Provider p) => p switch
    {
        Provider.ClaudeCode => "Claude Code",
        Provider.Codex => "Codex",
        Provider.Gemini => "Gemini CLI",
        Provider.Antigravity => "Antigravity",
        _ => p.ToString(),
    };

    public static string ShortName(this Provider p) => p switch
    {
        Provider.ClaudeCode => "CC",
        Provider.Codex => "CX",
        Provider.Gemini => "GE",
        Provider.Antigravity => "AG",
        _ => p.ToString(),
    };

    /// <summary>Whether per-session token/model data is available from local logs for this
    /// provider (Gemini/Antigravity are presence-only — their token/cost fields are always 0).</summary>
    public static bool HasUsageData(this Provider p) => p is Provider.ClaudeCode or Provider.Codex;
}

/// <summary>
/// Token counts split by type — the basis for cost, since the four types are priced very
/// differently. CacheWrite1h is the 1-hour-TTL subset of CacheWrite (billed 2x input vs
/// 1.25x for 5-minute cache); it is NOT part of Total. See spec/log-formats.md.
/// </summary>
public readonly record struct TokenBreakdown(
    int Input = 0, int Output = 0, int CacheRead = 0, int CacheWrite = 0, int CacheWrite1h = 0)
{
    public int Total => Input + Output + CacheRead + CacheWrite;

    public static TokenBreakdown operator +(TokenBreakdown a, TokenBreakdown b) => new(
        a.Input + b.Input, a.Output + b.Output, a.CacheRead + b.CacheRead,
        a.CacheWrite + b.CacheWrite, a.CacheWrite1h + b.CacheWrite1h);
}
