using System.Globalization;

namespace Tama.Core.Ui;

/// <summary>
/// Pure display-string formatters, framework-free ports of the small format helpers scattered
/// through <c>Sources/Tama/MenuBarView.swift</c> (planc-ui-spec.md §2/§3/§4). Every rule here is a
/// line-for-line port of the Swift original — see each method's doc comment for the source lines.
/// </summary>
public static class Formatters
{
    /// <summary>"12.4k" / "2.5M" token abbreviation (MenuBarView.swift:76-80, formatTokens).</summary>
    public static string FormatTokens(int n)
    {
        if (n >= 1_000_000) return (n / 1_000_000.0).ToString("F1", CultureInfo.InvariantCulture) + "M";
        if (n >= 1_000) return (n / 1_000.0).ToString("F1", CultureInfo.InvariantCulture) + "k";
        return n.ToString(CultureInfo.InvariantCulture);
    }

    /// <summary>Estimated cost, prefixed "~" to read as an estimate; "" for zero/negative
    /// (MenuBarView.swift:83-89, formatCost).</summary>
    public static string FormatCost(double d)
    {
        if (d <= 0) return "";
        if (d < 0.01) return "~<$0.01";
        if (d >= 1_000) return "~$" + (d / 1_000.0).ToString("F1", CultureInfo.InvariantCulture) + "k";
        if (d >= 100) return "~$" + d.ToString("F0", CultureInfo.InvariantCulture);
        return "~$" + d.ToString("F2", CultureInfo.InvariantCulture);
    }

    /// <summary>Human wall-time duration: "2.0s" / "120ms" / "45µs"
    /// (MenuBarView.swift:323-327, formatDuration).</summary>
    public static string FormatDuration(double seconds)
    {
        if (seconds >= 1) return seconds.ToString("F1", CultureInfo.InvariantCulture) + "s";
        if (seconds >= 0.001) return ((int)Math.Round(seconds * 1000, MidpointRounding.AwayFromZero)) + "ms";
        return ((int)Math.Round(seconds * 1_000_000, MidpointRounding.AwayFromZero)) + "µs";
    }

    /// <summary>"now" / "Xm" / "Xh" relative to <paramref name="now"/>
    /// (MenuBarView.swift:926-931, relativeTime — the Swift version reads
    /// <c>monitor.state.lastUpdated</c> as its implicit "now").</summary>
    public static string RelativeTime(DateTimeOffset now, DateTimeOffset date)
    {
        var secs = (int)(now - date).TotalSeconds;
        if (secs < 60) return "now";
        if (secs < 3600) return $"{secs / 60}m";
        return $"{secs / 3600}h";
    }

    /// <summary>Strips a leading "claude-" prefix only (MenuBarView.swift:917-919, prettyModel).</summary>
    public static string PrettyModel(string model) =>
        model.StartsWith("claude-", StringComparison.Ordinal) ? model["claude-".Length..] : model;

    /// <summary>Swaps a home-directory prefix for "~" (MenuBarView.swift:921-924, prettyFolder).</summary>
    public static string PrettyFolder(string path, string homeDirectory) =>
        homeDirectory.Length > 0 && path.StartsWith(homeDirectory, StringComparison.Ordinal)
            ? "~" + path[homeDirectory.Length..] : path;
}
