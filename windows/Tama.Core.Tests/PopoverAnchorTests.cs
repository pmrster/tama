using Tama.Core;
using Tama.Core.Ui;

namespace Tama.Core.Tests;

/// <summary>
/// Covers <see cref="PopoverAnchor"/> — where the dashboard popover opens when summoned from the
/// floating cat rather than the tray corner: beside the cat, preferring above it, never off the
/// monitor the cat is on. Inputs/outputs are logical units on ONE monitor's work area.
/// </summary>
[TestClass]
public sealed class PopoverAnchorTests
{
    private static readonly WindowFrame Work = new(0, 0, 1920, 1040);
    private const double PopW = 300;
    private const double PopH = 500;
    private const double CatW = 120;
    private const double CatH = 68;
    private const double Gap = PopoverAnchor.Gap;

    private static PopoverPlacement Place(double catX, double catY, WindowFrame? work = null, double popH = PopH) =>
        PopoverAnchor.Beside(new WindowFrame(catX, catY, CatW, CatH), PopW, popH, work ?? Work);

    [TestMethod]
    public void Prefers_above_the_cat_centered_horizontally()
    {
        var p = Place(900, 956);   // bottom edge, mid-screen
        Assert.AreEqual(PopoverSide.Above, p.Side);
        Assert.AreEqual(900 + CatW / 2 - PopW / 2, p.Frame.X);
        Assert.AreEqual(956 - Gap - PopH, p.Frame.Y);
        Assert.AreEqual(new WindowFrame(p.Frame.X, p.Frame.Y, PopW, PopH), p.Frame);
    }

    [TestMethod]
    public void Clamps_x_when_the_cat_hugs_the_right_edge()
    {
        var p = Place(1800, 900);
        Assert.AreEqual(PopoverSide.Above, p.Side);
        Assert.AreEqual(1920 - PopW, p.Frame.X);
    }

    [TestMethod]
    public void Clamps_x_when_the_cat_hugs_the_left_edge()
    {
        var p = Place(0, 900);
        Assert.AreEqual(PopoverSide.Above, p.Side);
        Assert.AreEqual(0, p.Frame.X);
    }

    [TestMethod]
    public void Falls_to_below_when_there_is_no_room_above()
    {
        var p = Place(900, 0);
        Assert.AreEqual(PopoverSide.Below, p.Side);
        Assert.AreEqual(CatH + Gap, p.Frame.Y);
        Assert.AreEqual(900 + CatW / 2 - PopW / 2, p.Frame.X);
    }

    [TestMethod]
    public void Falls_to_left_when_neither_above_nor_below_fits()
    {
        var shortWork = new WindowFrame(0, 0, 1920, 400);
        var p = Place(900, 50, shortWork, popH: 300);
        Assert.AreEqual(PopoverSide.Left, p.Side);
        Assert.AreEqual(900 - Gap - PopW, p.Frame.X);
        Assert.AreEqual(0, p.Frame.Y);   // v-centered would be negative → clamped to the top
    }

    [TestMethod]
    public void Falls_to_right_when_left_has_no_room_either()
    {
        var shortWork = new WindowFrame(0, 0, 1920, 400);
        var p = Place(10, 50, shortWork, popH: 300);
        Assert.AreEqual(PopoverSide.Right, p.Side);
        Assert.AreEqual(10 + CatW + Gap, p.Frame.X);
    }

    [TestMethod]
    public void Falls_back_to_a_clamped_above_frame_when_nothing_fits()
    {
        var tiny = new WindowFrame(0, 0, 320, 200);
        var p = Place(100, 100, tiny, popH: 300);
        Assert.AreEqual(PopoverSide.Above, p.Side);
        Assert.AreEqual(0, p.Frame.Y);
        Assert.IsTrue(p.Frame.X >= 0 && p.Frame.X <= 320 - PopW, "x clamped inside the work area");
    }

    [TestMethod]
    public void Handles_a_negative_origin_work_area()
    {
        var secondary = new WindowFrame(-1920, 0, 1920, 1040);
        var p = Place(-1000, 956, secondary);
        Assert.AreEqual(PopoverSide.Above, p.Side);
        Assert.AreEqual(-1000 + CatW / 2 - PopW / 2, p.Frame.X);
        Assert.AreEqual(956 - Gap - PopH, p.Frame.Y);
    }

    [TestMethod]
    public void Every_placement_is_fully_inside_the_work_area_when_the_popover_fits()
    {
        var spots = new[]
        {
            (0.0, 0.0), (1800.0, 0.0), (0.0, 972.0), (1800.0, 972.0),   // corners
            (900.0, 0.0), (900.0, 972.0), (0.0, 500.0), (1800.0, 500.0), // edges
            (900.0, 500.0),                                             // middle
        };
        foreach (var (x, y) in spots)
        {
            var p = Place(x, y);
            Assert.IsTrue(p.Frame.X >= Work.X, $"left edge on-screen at ({x},{y})");
            Assert.IsTrue(p.Frame.Y >= Work.Y, $"top edge on-screen at ({x},{y})");
            Assert.IsTrue(p.Frame.X + p.Frame.Width <= Work.X + Work.Width, $"right edge on-screen at ({x},{y})");
            Assert.IsTrue(p.Frame.Y + p.Frame.Height <= Work.Y + Work.Height, $"bottom edge on-screen at ({x},{y})");
        }
    }
}
