using Tama.Core;

namespace Tama.Core.Tests;

[TestClass]
public sealed class MoodEngineTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-06-19T12:00:00Z");
    private static readonly MoodEngine Engine = new(
        TimeSpan.FromSeconds(900), TimeSpan.FromSeconds(3600), TimeZoneInfo.Utc);

    private static Activity WithSessions(params DateTimeOffset[] lastActivities) => new(
        lastActivities.Select(d => new SessionInfo(Provider.ClaudeCode, "p", "/p", d)).ToList(),
        new Dictionary<Provider, int>(), new Dictionary<Provider, TokenBreakdown>(),
        new Dictionary<Provider, IReadOnlyDictionary<string, TokenBreakdown>>());

    // Pre-seeded "already saw today" state, so tests target working/resting/napping not greeting.
    private static readonly CatState SeenToday = new(Now.AddHours(-2));

    [TestMethod]
    public void Active_session_within_window_is_working_with_intensity()
    {
        var (mood, _) = Engine.Evaluate(WithSessions(Now.AddSeconds(-100), Now.AddSeconds(-200)), Now, SeenToday);
        Assert.AreEqual(Mood.Working(2), mood);
    }

    [TestMethod]
    public void Recent_but_paused_activity_is_resting()
    {
        var (mood, _) = Engine.Evaluate(WithSessions(Now.AddSeconds(-1800)), Now, SeenToday);
        Assert.AreEqual(Mood.Resting, mood);
    }

    [TestMethod]
    public void Stale_activity_is_napping()
    {
        var (mood, _) = Engine.Evaluate(WithSessions(Now.AddHours(-5)), Now, SeenToday);
        Assert.AreEqual(Mood.Napping, mood);
    }

    [TestMethod]
    public void No_sessions_is_napping()
    {
        var (mood, _) = Engine.Evaluate(WithSessions(), Now, SeenToday);
        Assert.AreEqual(Mood.Napping, mood);
    }

    [TestMethod]
    public void First_activity_of_a_new_day_greets_once_then_works()
    {
        var activity = WithSessions(Now.AddSeconds(-100));
        var (mood1, state1) = Engine.Evaluate(activity, Now, new CatState(Now.AddDays(-1)));
        Assert.AreEqual(Mood.Greeting, mood1);
        Assert.AreEqual(Now, state1.LastSeenDay);
        var (mood2, _) = Engine.Evaluate(activity, Now, state1);   // same day → no re-greet
        Assert.AreEqual(Mood.Working(1), mood2);
    }

    [TestMethod]
    public void Initial_state_with_activity_today_greets()
    {
        var (mood, _) = Engine.Evaluate(WithSessions(Now.AddHours(-2)), Now, CatState.Initial);
        Assert.AreEqual(Mood.Greeting, mood);
    }

    [TestMethod]
    public void New_day_with_no_activity_does_not_greet()
    {
        var (mood, state) = Engine.Evaluate(WithSessions(), Now, new CatState(Now.AddDays(-1)));
        Assert.AreEqual(Mood.Napping, mood);
        Assert.AreEqual(Now.AddDays(-1), state.LastSeenDay);   // state unchanged
    }

    [TestMethod]
    public void Exact_window_boundary_falls_to_the_lower_mood()
    {
        var (mood, _) = Engine.Evaluate(WithSessions(Now.AddSeconds(-900)), Now, SeenToday);
        Assert.AreEqual(Mood.Resting, mood);                    // strict <, matches Swift
    }
}
