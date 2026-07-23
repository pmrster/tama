using System.Windows;
using Tama.Core.Ui;
using Tama.Tray.Views;

namespace Tama.Tray;

/// <summary>
/// The transient, focus-loss-closing popover shell (spec §1a: borderless, AllowsTransparency,
/// Topmost while open, Deactivated closes it — the WPF analog of NSPopover's
/// `.behavior = .transient`). Hosts the real dashboard content (spec §2/§3/§4) via
/// <see cref="Views.DashboardView"/>; this window itself owns only the popover chrome/geometry
/// (border, transparency, tray-corner positioning, focus-loss dismissal).
/// </summary>
public partial class PopoverWindow : Window
{
    private bool _closing;

    public PopoverWindow(DashboardViewModel vm, Action onAbout, Action onQuit, Action onPin, double fontScale = 1.0)
    {
        InitializeComponent();

        // No retint call here on purpose: Palette's brushes are process-wide statics, already
        // set to the correct color by AppSettingsViewModel (once at startup, again live on every
        // Settings change, spec §5) — re-deriving from the OS here would silently discard an
        // explicit Light/Dark override every time the popover reopens (see Palette.cs's own
        // doc comment on Apply/IsSystemDark). fontScale is re-read fresh here since the popover is
        // rebuilt on every open (spec §5/Task 5 carry: "next open" picks up the latest setting).
        Dashboard.Initialize(vm, onAbout, onQuit, onPin, fontScale: fontScale);

        Deactivated += (_, _) => { if (!_closing) Close(); };
        Loaded += (_, _) => PositionNearTray();
    }

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        _closing = true;
        base.OnClosing(e);
    }

    /// <summary>Releases the DashboardView's VM subscription (lifecycle-leak fix, task-6 carry) —
    /// safe to call unconditionally since the popover is fully discarded and rebuilt fresh on every
    /// open (Program.cs's TogglePopover), unlike the reused PinnedWindow.</summary>
    protected override void OnClosed(EventArgs e)
    {
        Dashboard.Teardown();
        base.OnClosed(e);
    }

    public void CloseSafely()
    {
        if (!_closing)
            Close();
    }

    /// <summary>Positions the popover's bottom-right corner just above the taskbar tray corner
    /// (spec §1a: mac opens the popover below/near the status-item button; WPF has no handle to
    /// the tray icon's own screen rect, so this uses the primary screen's working-area corner —
    /// correct for the default bottom-right taskbar, per task-2-brief.md). Runs on Loaded so
    /// SizeToContent="Height" has already measured ActualHeight.</summary>
    private void PositionNearTray()
    {
        // Screen.WorkingArea is PHYSICAL pixels (WinForms); Left/Top/Width/ActualHeight are
        // 96-DPI device-independent units (WPF). On any display scaled above 100% (125%/150% is
        // the Windows-laptop default) the two spaces diverge, so assigning physical coords straight
        // to Left/Top shoves the popover off the bottom-right edge — open and activated but
        // invisible. Convert the physical work-area corner into this window's logical units via its
        // DPI transform (available once Loaded has created the HWND) before subtracting the popover
        // size, then clamp so a tiny/oddly-scaled screen can't still push it off-screen.
        var workArea = System.Windows.Forms.Screen.PrimaryScreen!.WorkingArea;
        const double margin = 8;
        var toLogical = PresentationSource.FromVisual(this)?.CompositionTarget?.TransformFromDevice
            ?? System.Windows.Media.Matrix.Identity;
        var corner = toLogical.Transform(new System.Windows.Point(workArea.Right, workArea.Bottom));
        var origin = toLogical.Transform(new System.Windows.Point(workArea.Left, workArea.Top));
        Left = Math.Max(origin.X, corner.X - Width - margin);
        Top = Math.Max(origin.Y, corner.Y - ActualHeight - margin);
    }
}
