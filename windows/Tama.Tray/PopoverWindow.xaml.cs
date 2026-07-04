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

    public PopoverWindow(DashboardViewModel vm, Action onAbout, Action onQuit)
    {
        InitializeComponent();

        // Retint chrome + DashboardView's Palette-bound brushes for the current OS theme before
        // first paint (spec §2-Palette; Task 5 will call this again on a live theme-change signal).
        Palette.Apply(Palette.IsSystemDark());
        Dashboard.Initialize(vm, onAbout, onQuit);

        Deactivated += (_, _) => { if (!_closing) Close(); };
        Loaded += (_, _) => PositionNearTray();
    }

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        _closing = true;
        base.OnClosing(e);
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
        // NOTE: Screen.WorkingArea is physical pixels (WinForms); Left/Top/ActualHeight are
        // 96-DPI device-independent units (WPF). Left unconverted for Task 2 (compiles and is
        // directionally correct on the common 100% scale factor); a DPI-aware conversion via
        // this window's WindowsPresentationSource/CompositionTarget.TransformFromDevice belongs
        // with the real visual polish pass, not this shell task.
        var workArea = System.Windows.Forms.Screen.PrimaryScreen!.WorkingArea;
        const double margin = 8;
        Left = workArea.Right - Width - margin;
        Top = workArea.Bottom - ActualHeight - margin;
    }
}
