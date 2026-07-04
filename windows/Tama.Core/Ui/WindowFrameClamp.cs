namespace Tama.Core.Ui;

/// <summary>
/// Clamps a persisted <see cref="WindowFrame"/> (Task 6's <c>PinnedWindow.RestoreOrDefaultFrame</c>,
/// backed by <see cref="AppSettingsViewModel.PinnedFrame"/>) onto the current virtual-screen
/// bounds before it is applied to a real window. A monitor-configuration change between app
/// sessions (an external display unplugged, a resolution change, ...) can otherwise strand the
/// restored frame entirely off every currently-connected display, making the pinned window
/// impossible to find or interact with (review finding — task-6-report.md fix wave).
///
/// Framework-free: both the frame and the screen bounds are passed as plain <see cref="WindowFrame"/>
/// records (doubles), not WPF's <c>Rect</c>/<c>SystemParameters</c>, so this is unit-testable here;
/// <c>Tama.Tray.PinnedWindow</c> supplies the live <c>SystemParameters.VirtualScreenLeft/Top/Width/
/// Height</c> values as the "screen" rectangle.
/// </summary>
public static class WindowFrameClamp
{
    /// <summary>Minimum width/height of on-screen overlap required to accept the restored frame
    /// (after shrinking, before repositioning) rather than treating it as effectively off-screen.</summary>
    public const double MinVisibleOverlap = 40;

    /// <summary>
    /// Fits <paramref name="frame"/> onto <paramref name="screen"/>: shrinks width/height to at
    /// most the screen's own (a frame saved on a larger monitor than is currently connected), then
    /// translates its position so the (possibly shrunk) rectangle lies entirely within the screen.
    /// Returns <c>null</c> — signaling the caller should use its own default frame instead — if the
    /// ORIGINAL frame overlaps the screen by less than <see cref="MinVisibleOverlap"/> in either
    /// dimension (i.e. essentially none of it would be visible/reachable), or if any width/height
    /// involved is non-positive.
    /// </summary>
    public static WindowFrame? Clamp(WindowFrame frame, WindowFrame screen)
    {
        if (frame.Width <= 0 || frame.Height <= 0 || screen.Width <= 0 || screen.Height <= 0)
            return null;

        var width = Math.Min(frame.Width, screen.Width);
        var height = Math.Min(frame.Height, screen.Height);

        var overlapWidth = Math.Min(frame.X + width, screen.X + screen.Width) - Math.Max(frame.X, screen.X);
        var overlapHeight = Math.Min(frame.Y + height, screen.Y + screen.Height) - Math.Max(frame.Y, screen.Y);
        if (overlapWidth < MinVisibleOverlap || overlapHeight < MinVisibleOverlap)
            return null;

        var x = Math.Clamp(frame.X, screen.X, screen.X + screen.Width - width);
        var y = Math.Clamp(frame.Y, screen.Y, screen.Y + screen.Height - height);
        return new WindowFrame(x, y, width, height);
    }
}
