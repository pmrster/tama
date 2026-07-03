using System.Windows;
using System.Windows.Media;
using Tama.Core;

namespace Tama.Tray;

/// <summary>
/// The transient, focus-loss-closing popover shell (spec §1a: borderless, AllowsTransparency,
/// Topmost while open, Deactivated closes it — the WPF analog of NSPopover's
/// `.behavior = .transient`). Task 2 scope is the chrome, geometry, and monitor-driven summary
/// content below; the full provider/folder/session tree (spec §2) replaces the placeholder
/// StackPanel content in Task 4's DashboardView without needing to touch this window's shell.
/// </summary>
public partial class PopoverWindow : Window
{
    private readonly AgentMonitor _monitor;
    private bool _closing;

    public PopoverWindow(AgentMonitor monitor)
    {
        _monitor = monitor;
        InitializeComponent();

        Deactivated += (_, _) => { if (!_closing) Close(); };
        _monitor.StateChanged += OnStateChanged;
        Closed += (_, _) => _monitor.StateChanged -= OnStateChanged;
        Loaded += (_, _) => PositionNearTray();

        Render(_monitor.State);
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

    private void OnStateChanged(AppState state) => Dispatcher.Invoke(() => Render(state));

    private void Render(AppState state)
    {
        var activeNow = _monitor.ActiveCount();
        HeaderText.Text = activeNow == 1 ? "1 agent active" : $"{activeNow} agents active";
        // Color is ambiguous unqualified here (System.Drawing.Color is also in scope via
        // UseWindowsForms' implicit global using) — see TrayIcon.cs's BuildIcon for the same
        // System.Drawing-vs-WPF pattern.
        StatusDot.Fill = new SolidColorBrush(activeNow > 0
            ? System.Windows.Media.Color.FromRgb(0xF3, 0xBD, 0x4F)   // Palette.yellow
            : System.Windows.Media.Color.FromRgb(0x6E, 0x65, 0x5C)); // Palette.dim
        StatusText.Text = $"Mood: {state.Mood.Kind} — full dashboard lands in Task 4.";
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
