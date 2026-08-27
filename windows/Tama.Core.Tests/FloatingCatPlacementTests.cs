using Tama.Core;
using Tama.Core.Ui;

namespace Tama.Core.Tests;

/// <summary>
/// Covers <see cref="FloatingCatPlacement"/> — the pure geometry behind the floating desktop cat
/// (<c>Tama.Tray.FloatingCatWindow</c>): where it lands on a fresh install, how a persisted
/// position is restored onto whatever monitors are connected NOW (through
/// <see cref="WindowFrameClamp"/>, like the pinned window), and the click-vs-drag threshold.
/// All values are logical (96-DPI) units; the WPF window converts device px before calling in.
/// </summary>
[TestClass]
public sealed class FloatingCatPlacementTests
{
    private static readonly WindowFrame PrimaryWork = new(0, 0, 1920, 1040);   // taskbar at bottom
    private static readonly WindowFrame Virtual = new(0, 0, 1920, 1080);
    private const double W = FloatingCatPlacement.WidgetWidth;
    private const double H = FloatingCatPlacement.WidgetHeight;
    private const double M = FloatingCatPlacement.DefaultMargin;

    [TestMethod]
    public void Widget_size_is_the_2x_pet_strip()
    {
        Assert.AreEqual(120, FloatingCatPlacement.WidgetWidth);
        Assert.AreEqual(68, FloatingCatPlacement.WidgetHeight);
    }

    [TestMethod]
    public void Default_frame_sits_bottom_right_of_the_work_area_inset_by_margin()
    {
        var f = FloatingCatPlacement.DefaultFrame(PrimaryWork);
        Assert.AreEqual(new WindowFrame(1920 - W - M, 1040 - H - M, W, H), f);
    }

    [TestMethod]
    public void Default_frame_honors_a_non_zero_work_area_origin()
    {
        // Left-docked taskbar: the work area starts at x=64.
        var f = FloatingCatPlacement.DefaultFrame(new WindowFrame(64, 0, 1856, 1080));
        Assert.AreEqual(new WindowFrame(64 + 1856 - W - M, 1080 - H - M, W, H), f);
    }

    [TestMethod]
    public void Default_frame_never_goes_left_or_above_the_work_area_on_a_tiny_screen()
    {
        var f = FloatingCatPlacement.DefaultFrame(new WindowFrame(0, 0, 50, 40));
        Assert.AreEqual(0, f.X);
        Assert.AreEqual(0, f.Y);
    }

    [TestMethod]
    public void Restore_returns_the_default_when_nothing_was_saved()
    {
        var f = FloatingCatPlacement.Restore(null, Virtual, PrimaryWork);
        Assert.AreEqual(FloatingCatPlacement.DefaultFrame(PrimaryWork), f);
    }

    [TestMethod]
    public void Restore_keeps_an_on_screen_saved_position()
    {
        var f = FloatingCatPlacement.Restore(new WindowFrame(300, 400, W, H), Virtual, PrimaryWork);
        Assert.AreEqual(new WindowFrame(300, 400, W, H), f);
    }

    [TestMethod]
    public void Restore_ignores_the_saved_size_and_uses_the_current_widget_size()
    {
        // A future build may change the widget size; the persisted one must not win.
        var f = FloatingCatPlacement.Restore(new WindowFrame(10, 10, 999, 999), Virtual, PrimaryWork);
        Assert.AreEqual(new WindowFrame(10, 10, W, H), f);
    }

    [TestMethod]
    public void Restore_clamps_a_partially_off_screen_saved_frame_into_view()
    {
        // 60 of 120 px still on-screen (>= WindowFrameClamp.MinVisibleOverlap) → pulled to x=0.
        var f = FloatingCatPlacement.Restore(new WindowFrame(-60, 500, W, H), Virtual, PrimaryWork);
        Assert.AreEqual(new WindowFrame(0, 500, W, H), f);
    }

    [TestMethod]
    public void Restore_falls_back_to_the_default_when_the_saved_frame_is_entirely_off_screen()
    {
        var f = FloatingCatPlacement.Restore(new WindowFrame(5000, 5000, W, H), Virtual, PrimaryWork);
        Assert.AreEqual(FloatingCatPlacement.DefaultFrame(PrimaryWork), f);
    }

    [TestMethod]
    public void Restore_preserves_a_negative_coordinate_secondary_monitor_position()
    {
        // Secondary monitor to the LEFT of the primary: virtual screen starts at x=-1920.
        var virtualScreen = new WindowFrame(-1920, 0, 3840, 1080);
        var f = FloatingCatPlacement.Restore(new WindowFrame(-1800, 900, W, H), virtualScreen, PrimaryWork);
        Assert.AreEqual(new WindowFrame(-1800, 900, W, H), f);
    }

    [TestMethod]
    public void IsDrag_is_false_below_the_threshold_on_both_axes()
    {
        Assert.IsFalse(FloatingCatPlacement.IsDrag(3.9, -3.9));
        Assert.IsFalse(FloatingCatPlacement.IsDrag(0, 0));
    }

    [TestMethod]
    public void IsDrag_is_true_at_the_threshold_on_either_axis()
    {
        Assert.IsTrue(FloatingCatPlacement.IsDrag(FloatingCatPlacement.DragThreshold, 0));
        Assert.IsTrue(FloatingCatPlacement.IsDrag(0, -FloatingCatPlacement.DragThreshold));
    }
}
