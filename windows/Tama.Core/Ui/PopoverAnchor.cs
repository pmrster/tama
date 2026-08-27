namespace Tama.Core.Ui;

/// <summary>Which side of the anchor the popover was placed on.</summary>
public enum PopoverSide { Above, Below, Left, Right }

/// <summary>The chosen popover frame plus the side it ended up on (for tests / future pointer art).</summary>
public readonly record struct PopoverPlacement(WindowFrame Frame, PopoverSide Side);

/// <summary>
/// Where the dashboard popover opens when summoned from the floating cat instead of the tray
/// corner (<c>PopoverWindow.PositionNearTray</c>): beside the anchor, preferring above it, and
/// always inside the work area of the monitor the anchor is on. Pure and in logical units, so
/// the WPF caller only has to convert that monitor's physical work area first (same DPI rule as
/// <c>PositionNearTray</c>).
/// </summary>
public static class PopoverAnchor
{
    /// <summary>Space between the anchor and the popover edge, logical px.</summary>
    public const double Gap = 8;

    /// <summary>Tries Above (horizontally centered on the anchor, x clamped), then Below, then
    /// Left (vertically centered, y clamped), then Right. If none fits, returns the Above
    /// candidate clamped on both axes — it may overlap the anchor, which beats being off-screen.</summary>
    public static PopoverPlacement Beside(WindowFrame anchor, double popoverWidth, double popoverHeight,
        WindowFrame workArea, double gap = Gap)
    {
        var centeredX = ClampX(anchor.X + anchor.Width / 2 - popoverWidth / 2, popoverWidth, workArea);
        var centeredY = ClampY(anchor.Y + anchor.Height / 2 - popoverHeight / 2, popoverHeight, workArea);

        var aboveY = anchor.Y - gap - popoverHeight;
        if (aboveY >= workArea.Y)
            return new(new WindowFrame(centeredX, aboveY, popoverWidth, popoverHeight), PopoverSide.Above);

        var belowY = anchor.Y + anchor.Height + gap;
        if (belowY + popoverHeight <= workArea.Y + workArea.Height)
            return new(new WindowFrame(centeredX, belowY, popoverWidth, popoverHeight), PopoverSide.Below);

        var leftX = anchor.X - gap - popoverWidth;
        if (leftX >= workArea.X)
            return new(new WindowFrame(leftX, centeredY, popoverWidth, popoverHeight), PopoverSide.Left);

        var rightX = anchor.X + anchor.Width + gap;
        if (rightX + popoverWidth <= workArea.X + workArea.Width)
            return new(new WindowFrame(rightX, centeredY, popoverWidth, popoverHeight), PopoverSide.Right);

        return new(new WindowFrame(centeredX, ClampY(aboveY, popoverHeight, workArea), popoverWidth, popoverHeight),
            PopoverSide.Above);
    }

    private static double ClampX(double x, double width, WindowFrame wa) =>
        Math.Clamp(x, wa.X, Math.Max(wa.X, wa.X + wa.Width - width));

    private static double ClampY(double y, double height, WindowFrame wa) =>
        Math.Clamp(y, wa.Y, Math.Max(wa.Y, wa.Y + wa.Height - height));
}
