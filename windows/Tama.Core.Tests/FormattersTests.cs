using Tama.Core.Ui;

namespace Tama.Core.Tests;

/// <summary>
/// Cases copied verbatim from the Swift source these formatters port (Sources/Tama/MenuBarView.swift:
/// formatTokens :76-80, formatCost :83-89, formatDuration :323-327, relativeTime :926-931,
/// prettyModel :917-919, prettyFolder :921-924) — see planc-ui-spec.md §2/§3/§4.
/// </summary>
[TestClass]
public sealed class FormattersTests
{
    // formatTokens: "%.1fM" >= 1_000_000; "%.1fk" >= 1_000; else plain int (:76-80).
    [TestMethod]
    public void FormatTokens_plain_below_1000()
    {
        Assert.AreEqual("0", Formatters.FormatTokens(0));
        Assert.AreEqual("999", Formatters.FormatTokens(999));
    }

    [TestMethod]
    public void FormatTokens_k_suffix_from_1000()
    {
        Assert.AreEqual("1.0k", Formatters.FormatTokens(1_000));
        Assert.AreEqual("1.5k", Formatters.FormatTokens(1_500));
        Assert.AreEqual("12.4k", Formatters.FormatTokens(12_400));
    }

    [TestMethod]
    public void FormatTokens_M_suffix_from_1_000_000()
    {
        Assert.AreEqual("1.0M", Formatters.FormatTokens(1_000_000));
        Assert.AreEqual("2.5M", Formatters.FormatTokens(2_500_000));
    }

    // formatCost: <=0 -> "" ; <0.01 -> "~<$0.01" ; >=100 -> "~$%.0f" ; >=1000 -> "~$%.1fk" ; else "~$%.2f" (:83-89).
    [TestMethod]
    public void FormatCost_zero_or_negative_is_empty()
    {
        Assert.AreEqual("", Formatters.FormatCost(0));
        Assert.AreEqual("", Formatters.FormatCost(-1.5));
    }

    [TestMethod]
    public void FormatCost_below_a_cent_shows_placeholder()
    {
        Assert.AreEqual("~<$0.01", Formatters.FormatCost(0.005));
    }

    [TestMethod]
    public void FormatCost_normal_range_two_decimals()
    {
        Assert.AreEqual("~$0.01", Formatters.FormatCost(0.01));
        Assert.AreEqual("~$4.10", Formatters.FormatCost(4.1));
    }

    [TestMethod]
    public void FormatCost_hundreds_rounds_to_whole_dollars()
    {
        Assert.AreEqual("~$150", Formatters.FormatCost(150.4));
    }

    [TestMethod]
    public void FormatCost_thousands_uses_k_suffix()
    {
        Assert.AreEqual("~$1.5k", Formatters.FormatCost(1500));
        Assert.AreEqual("~$1.2k", Formatters.FormatCost(1234.5));
    }

    // formatDuration: >=1s -> "%.1fs" ; >=0.001s -> "<ms>ms" ; else "<µs>µs" (:323-327).
    [TestMethod]
    public void FormatDuration_seconds()
    {
        Assert.AreEqual("2.0s", Formatters.FormatDuration(2.0));
    }

    [TestMethod]
    public void FormatDuration_milliseconds()
    {
        Assert.AreEqual("120ms", Formatters.FormatDuration(0.12));
    }

    [TestMethod]
    public void FormatDuration_microseconds()
    {
        Assert.AreEqual("45µs", Formatters.FormatDuration(0.000045));
    }

    // relativeTime: secs<60 -> "now" ; secs<3600 -> "Xm" ; else "Xh" (:926-931).
    [TestMethod]
    public void RelativeTime_under_a_minute_is_now()
    {
        var now = DateTimeOffset.Parse("2026-06-19T12:00:00Z");
        Assert.AreEqual("now", Formatters.RelativeTime(now, now.AddSeconds(-30)));
    }

    [TestMethod]
    public void RelativeTime_under_an_hour_is_minutes()
    {
        var now = DateTimeOffset.Parse("2026-06-19T12:00:00Z");
        Assert.AreEqual("2m", Formatters.RelativeTime(now, now.AddSeconds(-125)));
    }

    [TestMethod]
    public void RelativeTime_an_hour_or_more_is_hours()
    {
        var now = DateTimeOffset.Parse("2026-06-19T12:00:00Z");
        Assert.AreEqual("2h", Formatters.RelativeTime(now, now.AddSeconds(-7200)));
    }

    // prettyModel: strips a leading "claude-" prefix only (:917-919).
    [TestMethod]
    public void PrettyModel_strips_claude_prefix()
    {
        Assert.AreEqual("sonnet-5", Formatters.PrettyModel("claude-sonnet-5"));
    }

    [TestMethod]
    public void PrettyModel_leaves_other_models_untouched()
    {
        Assert.AreEqual("gemma4:12b-mlx", Formatters.PrettyModel("gemma4:12b-mlx"));
    }

    // prettyFolder: home dir swapped for "~" (:921-924).
    [TestMethod]
    public void PrettyFolder_swaps_home_prefix_for_tilde()
    {
        Assert.AreEqual("~/projects/foo",
            Formatters.PrettyFolder("/Users/tama/projects/foo", "/Users/tama"));
    }

    [TestMethod]
    public void PrettyFolder_leaves_paths_outside_home_untouched()
    {
        Assert.AreEqual("/var/other/foo", Formatters.PrettyFolder("/var/other/foo", "/Users/tama"));
    }
}
