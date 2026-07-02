namespace Tama.Core;

public enum Provider
{
    ClaudeCode,
    Codex,
    Gemini,
    Antigravity,
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
