using Tama.Core.Ui;

namespace Tama.Core.Tests;

/// <summary>
/// Covers <see cref="InteractivePolling"/>'s reference-counting contract — the fix for the review
/// finding that <c>Tama.Tray.Program</c>'s old per-surface <c>monitor.Start(...)</c> calls let the
/// poll interval regress to background while a SECOND surface (popover vs pinned window) was still
/// open (task-6-report.md fix wave). Mirrors Sources/TamaCore/Monitor/AgentMonitor.swift's
/// <c>interactiveConsumers</c> semantics exactly (max(0, ...) clamp included), so these cases are
/// deliberately the C# analogs of what that Swift type would need if it had its own dedicated
/// tests for begin/end pairing.
/// </summary>
[TestClass]
public sealed class InteractivePollingTests
{
    private static readonly TimeSpan Interactive = TimeSpan.FromSeconds(7);
    private static readonly TimeSpan Background = TimeSpan.FromSeconds(30);

    private static (InteractivePolling Polling, List<TimeSpan> Calls) Make()
    {
        var calls = new List<TimeSpan>();
        var polling = new InteractivePolling(calls.Add, Interactive, Background);
        return (polling, calls);
    }

    [TestMethod]
    public void Begin_starts_the_interactive_interval()
    {
        var (polling, calls) = Make();
        polling.Begin();
        CollectionAssert.AreEqual(new[] { Interactive }, calls);
        Assert.AreEqual(1, polling.Consumers);
    }

    [TestMethod]
    public void Single_begin_then_end_reverts_to_background()
    {
        var (polling, calls) = Make();
        polling.Begin();
        polling.End();
        CollectionAssert.AreEqual(new[] { Interactive, Background }, calls);
        Assert.AreEqual(0, polling.Consumers);
    }

    /// <summary>The exact bug this class fixes: two consumers (e.g. popover open while pinned is
    /// already open) — ending just ONE of them must NOT drop back to background yet.</summary>
    [TestMethod]
    public void Two_begins_then_one_end_stays_interactive()
    {
        var (polling, calls) = Make();
        polling.Begin();   // e.g. pinned window shown
        polling.Begin();   // e.g. popover opened while pinned is still visible
        polling.End();     // e.g. popover auto-closes
        Assert.AreEqual(1, polling.Consumers, "one consumer (the pinned window) is still open");
        CollectionAssert.AreEqual(new[] { Interactive, Interactive }, calls,
            "ending one of two consumers must not restart the background interval");
    }

    [TestMethod]
    public void Final_end_after_multiple_begins_reverts_to_background()
    {
        var (polling, calls) = Make();
        polling.Begin();
        polling.Begin();
        polling.End();
        polling.End();
        Assert.AreEqual(0, polling.Consumers);
        CollectionAssert.AreEqual(new[] { Interactive, Interactive, Background }, calls);
    }

    /// <summary>Clamps at zero — a stray extra End() (e.g. a duplicated close event) must not go
    /// negative, which would otherwise require an extra Begin() before the count could ever reach
    /// zero again and re-arm background polling (mirrors Swift's <c>max(0, ...)</c>).</summary>
    [TestMethod]
    public void End_below_zero_clamps_at_zero_and_still_starts_background()
    {
        var (polling, calls) = Make();
        polling.End();
        Assert.AreEqual(0, polling.Consumers);
        CollectionAssert.AreEqual(new[] { Background }, calls);

        polling.End();
        Assert.AreEqual(0, polling.Consumers, "consumer count must never go negative");
        CollectionAssert.AreEqual(new[] { Background, Background }, calls);

        // A single Begin() after two stray Ends() must be enough to go interactive again — proves
        // the count didn't drift negative and require multiple Begins to recover.
        polling.Begin();
        Assert.AreEqual(1, polling.Consumers);
        CollectionAssert.AreEqual(new[] { Background, Background, Interactive }, calls);
    }
}
