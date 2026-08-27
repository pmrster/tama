using System.Windows;
using Tama.Core;
using Tama.Core.Ui;
using Tama.Tray.Views;

namespace Tama.Tray;

/// <summary>
/// The transient, focus-loss-closing popover shell (spec §1a: borderless, AllowsTransparency,
/// Topmost while open, Deactivated closes it — the WPF analog of NSPopover's
/// `.behavior = .transient`). Hosts the real dashboard content (spec §2/§3/§4) via
/// <see cref="Views.DashboardView"/>; this window itself owns only the popover chrome/geometry
/// (border, transparency, tray-corner / beside-the-cat positioning, focus-loss dismissal).
/// </summary>
public partial class PopoverWindow : Window
{
    private bool _closing;
    private readonly WindowFrame? _anchor;

    /// <param name="anchor">When summoned from the floating cat: its logical frame, so the popover
    /// opens beside it (<see cref="PopoverAnchor"/>) instead of at the tray corner.</param>
    public PopoverWindow(DashboardViewModel vm, Action onAbout, Action onQuit, Action onPin, double fontScale = 1.0,
        WindowFrame? anchor = null)
    {
        InitializeComponent();
        _anchor = anchor;

        // No retint call here on purpose: Palette's brushes are process-wide statics, already
        // set to the correct color by AppSettingsViewModel (once at startup, again live on every
        // Settings change, spec §5) — re-deriving from the OS here would silently discard an
        // explicit Light/Dark override every time the popover reopens (see Palette.cs's own
        // doc comment on Apply/IsSystemDark). fontScale is re-read fresh here since the popover is
        // rebuilt on every open (spec §5/Task 5 carry: "next open" picks up the latest setting).
        Dashboard.Initialize(vm, onAbout, onQuit, onPin, fontScale: fontScale);

        Deactivated += (_, _) => { if (!_closing) Close(); };
        Loaded += (_, _) => { if (_anchor is { } a) PositionBesideAnchor(a); else PositionNearTray(); };
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

    /// <summary>Positions the popover beside the floating cat (<see cref="PopoverAnchor.Beside"/>:
    /// above it when there's room, else below/left/right), inside the work area of the monitor
    /// the cat is on. Same physical→logical conversion as <see cref="PositionNearTray"/>; the
    /// anchor itself is already logical (WPF Left/Top of the cat window). Runs on Loaded so
    /// SizeToContent="Height" has measured ActualHeight.</summary>
    private void PositionBesideAnchor(WindowFrame anchor)
    {
        var target = PresentationSource.FromVisual(this)?.CompositionTarget;
        var toDevice = target?.TransformToDevice ?? System.Windows.Media.Matrix.Identity;
        var toLogical = target?.TransformFromDevice ?? System.Windows.Media.Matrix.Identity;

        var center = toDevice.Transform(new System.Windows.Point(anchor.X + anchor.Width / 2, anchor.Y + anchor.Height / 2));
        var workArea = System.Windows.Forms.Screen
            .FromPoint(new System.Drawing.Point((int)center.X, (int)center.Y)).WorkingArea;
        var origin = toLogical.Transform(new System.Windows.Point(workArea.Left, workArea.Top));
        var corner = toLogical.Transform(new System.Windows.Point(workArea.Right, workArea.Bottom));

        var placement = PopoverAnchor.Beside(anchor, Width, ActualHeight,
            new WindowFrame(origin.X, origin.Y, corner.X - origin.X, corner.Y - origin.Y));
        Left = placement.Frame.X;
        Top = placement.Frame.Y;
    }
}
