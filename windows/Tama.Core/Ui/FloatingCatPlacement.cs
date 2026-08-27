namespace Tama.Core.Ui;

/// <summary>
/// Pure geometry for the floating desktop cat (<c>Tama.Tray.FloatingCatWindow</c>): its size,
/// where it lands on a fresh install, how a persisted position is restored onto the monitors
/// connected NOW, and the click-vs-drag threshold. Framework-free and in logical (96-DPI) units
/// — the WPF window converts device px before calling in — so it is unit-testable here, the same
/// split as <see cref="WindowFrameClamp"/> / <c>PinnedWindow</c>.
/// </summary>
public static class FloatingCatPlacement
{
    /// <summary>LayoutTransform applied over PetControl's already-2× raster (4 logical px per sprite cell).</summary>
    public const double DisplayScale = 2;

    /// <summary>PetControl strip geometry: its own pacing-range floor is spriteW + 12
    /// (<c>PetControl.Tick</c>), and PetControl.xaml fixes the strip height at 34.</summary>
    public const double StripWidth = CatSprite.GridCols * CatSprite.RasterScale + 12;   // 60
    public const double StripHeight = 34;

    public const double WidgetWidth = StripWidth * DisplayScale;    // 120
    public const double WidgetHeight = StripHeight * DisplayScale;  // 68

    /// <summary>Inset from the work-area corner on first show.</summary>
    public const double DefaultMargin = 16;

    /// <summary>Pointer travel (per axis, logical px) that turns a press into a drag instead of
    /// a click — mirrors the system's SM_CXDRAG/SM_CYDRAG default of 4.</summary>
    public const double DragThreshold = 4;

    /// <summary>Bottom-right corner of <paramref name="workArea"/>, inset by
    /// <paramref name="margin"/>; never left of / above the work-area origin on a tiny screen.</summary>
    public static WindowFrame DefaultFrame(WindowFrame workArea,
        double width = WidgetWidth, double height = WidgetHeight, double margin = DefaultMargin)
    {
        var x = Math.Max(workArea.X, workArea.X + workArea.Width - width - margin);
        var y = Math.Max(workArea.Y, workArea.Y + workArea.Height - height - margin);
        return new WindowFrame(x, y, width, height);
    }

    /// <summary>The persisted position (its saved SIZE is ignored — the widget is always the
    /// current build's size) clamped onto <paramref name="virtualScreen"/> via
    /// <see cref="WindowFrameClamp"/>; null or unrecoverable (entirely off every connected
    /// monitor) → <see cref="DefaultFrame"/> on <paramref name="primaryWorkArea"/>.</summary>
    public static WindowFrame Restore(WindowFrame? saved, WindowFrame virtualScreen, WindowFrame primaryWorkArea,
        double width = WidgetWidth, double height = WidgetHeight)
    {
        if (saved is { } s
            && WindowFrameClamp.Clamp(new WindowFrame(s.X, s.Y, width, height), virtualScreen) is { } clamped)
            return clamped;
        return DefaultFrame(primaryWorkArea, width, height);
    }

    /// <summary>True once the pointer has moved at least <paramref name="threshold"/> on either axis
    /// since the press.</summary>
    public static bool IsDrag(double dx, double dy, double threshold = DragThreshold) =>
        Math.Abs(dx) >= threshold || Math.Abs(dy) >= threshold;
}
