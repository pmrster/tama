using Tama.Core;
using Tama.Core.Ui;

namespace Tama.Core.Tests;

/// <summary>
/// Covers <see cref="WindowFrameClamp"/> — the fix for the review finding that
/// <c>PinnedWindow.RestoreOrDefaultFrame</c> applied a persisted frame unchecked, so a monitor-
/// configuration change between app sessions (a display unplugged, a resolution change, ...)
/// could strand the restored window entirely off-screen (task-6-report.md fix wave). Screen
/// bounds mimic <c>SystemParameters.VirtualScreen{Left,Top,Width,Height}</c> — a plain
/// <see cref="WindowFrame"/> is reused for both the frame and the screen rectangle since the
/// shape (X, Y, Width, Height) is identical.
/// </summary>
[TestClass]
public sealed class WindowFrameClampTests
{
    private static readonly WindowFrame PrimaryScreen = new(0, 0, 1920, 1080);

    [TestMethod]
    public void Fully_visible_frame_is_returned_unchanged()
    {
        var frame = new WindowFrame(100, 100, 360, 480);
        Assert.AreEqual(frame, WindowFrameClamp.Clamp(frame, PrimaryScreen));
    }

    [TestMethod]
    public void Fully_off_screen_frame_falls_back_to_null()
    {
        // Saved on a monitor that no longer exists (or a wildly stale value) — none of the
        // 360x480 window would overlap the current 1920x1080 screen at all.
        var frame = new WindowFrame(5000, 5000, 360, 480);
        Assert.IsNull(WindowFrameClamp.Clamp(frame, PrimaryScreen));
    }

    [TestMethod]
    public void Partially_off_screen_frame_is_clamped_fully_into_view()
    {
        // Only the rightmost 60px of the 360-wide window is on-screen (x runs -300..60) — enough
        // overlap (>= 40 in both dimensions) to recover rather than discard, but it must be
        // translated fully into the visible screen area rather than left hanging off the edge.
        var frame = new WindowFrame(-300, 100, 360, 480);
        var clamped = WindowFrameClamp.Clamp(frame, PrimaryScreen);

        Assert.IsNotNull(clamped);
        Assert.AreNotEqual(frame, clamped, "should have moved, not merely accepted the persisted frame");
        Assert.AreEqual(new WindowFrame(0, 100, 360, 480), clamped);
        AssertFullyOnScreen(clamped.Value, PrimaryScreen);
    }

    [TestMethod]
    public void Just_barely_enough_corner_overlap_is_still_recovered()
    {
        // Exactly MinVisibleOverlap (40) of width on-screen — the boundary case, must clamp in
        // rather than reject.
        var frame = new WindowFrame(-320, 100, 360, 480); // right edge at x = 40
        var clamped = WindowFrameClamp.Clamp(frame, PrimaryScreen);
        Assert.IsNotNull(clamped);
        AssertFullyOnScreen(clamped.Value, PrimaryScreen);
    }

    [TestMethod]
    public void Just_under_minimum_overlap_falls_back_to_null()
    {
        var frame = new WindowFrame(-321, 100, 360, 480); // right edge at x = 39, < 40
        Assert.IsNull(WindowFrameClamp.Clamp(frame, PrimaryScreen));
    }

    [TestMethod]
    public void Frame_larger_than_the_screen_is_shrunk_to_fit()
    {
        // Persisted on a much larger (e.g. ultra-wide) monitor than is currently connected.
        var frame = new WindowFrame(100, 100, 3440, 1440);
        var clamped = WindowFrameClamp.Clamp(frame, PrimaryScreen);

        Assert.IsNotNull(clamped);
        Assert.AreEqual(PrimaryScreen.Width, clamped.Value.Width);
        Assert.AreEqual(PrimaryScreen.Height, clamped.Value.Height);
        AssertFullyOnScreen(clamped.Value, PrimaryScreen);
    }

    [TestMethod]
    public void Negative_origin_virtual_screen_secondary_monitor_frame_is_preserved()
    {
        // Windows virtual-desktop coordinates go negative when a secondary monitor sits to the
        // left of/above the primary — must not be mistaken for "off-screen".
        var virtualScreen = new WindowFrame(-1920, 0, 3840, 1080);
        var frame = new WindowFrame(-1800, 100, 360, 480);
        Assert.AreEqual(frame, WindowFrameClamp.Clamp(frame, virtualScreen));
    }

    [TestMethod]
    public void Non_positive_frame_dimensions_fall_back_to_null()
    {
        Assert.IsNull(WindowFrameClamp.Clamp(new WindowFrame(100, 100, 0, 480), PrimaryScreen));
        Assert.IsNull(WindowFrameClamp.Clamp(new WindowFrame(100, 100, 360, -10), PrimaryScreen));
    }

    private static void AssertFullyOnScreen(WindowFrame frame, WindowFrame screen)
    {
        Assert.IsTrue(frame.X >= screen.X, "left edge on-screen");
        Assert.IsTrue(frame.Y >= screen.Y, "top edge on-screen");
        Assert.IsTrue(frame.X + frame.Width <= screen.X + screen.Width, "right edge on-screen");
        Assert.IsTrue(frame.Y + frame.Height <= screen.Y + screen.Height, "bottom edge on-screen");
    }
}
