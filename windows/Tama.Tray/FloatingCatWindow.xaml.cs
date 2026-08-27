using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using Tama.Core;
using Tama.Core.Ui;

namespace Tama.Tray;

/// <summary>
/// The floating, always-on-top desktop cat — the Windows stand-in for the mac menu-bar cat, so
/// the dashboard is one click away without hunting for the (often overflow-hidden) tray icon.
/// Left-click toggles the popover anchored beside the cat; right-click shows the tray's own
/// context menu; drag moves it (frame persisted via <see cref="AppSettingsViewModel.FloatingCatFrame"/>
/// and restored through <see cref="FloatingCatPlacement.Restore"/>, clamped to the monitors
/// connected NOW — same pattern as <see cref="PinnedWindow"/>). Shown/hidden by
/// <see cref="AppSettingsViewModel.FloatingCatVisible"/>, which the tray menu and the Settings
/// window both drive, so the three surfaces can never disagree.
///
/// Constructed once (Program.cs), hide-not-destroy like the other reused windows. Only pure
/// geometry lives in Tama.Core (<see cref="FloatingCatPlacement"/>); this class is the WPF/Win32
/// adapter: ex-styles, DPI conversion, mouse tracking.
///
/// Activation: the window carries WS_EX_NOACTIVATE (+ WS_EX_TOOLWINDOW so it never shows in
/// Alt-Tab) and ShowActivated=False, so clicking the cat never steals focus from the user's app —
/// and, critically, never deactivates <see cref="PopoverWindow"/>, which closes itself on
/// Deactivated. A cat click while the popover is open therefore reaches TogglePopover, which
/// closes it — toggle semantics for free.
///
/// Drag: once the pointer travels <see cref="FloatingCatPlacement.DragThreshold"/> the press is
/// handed to <see cref="Window.DragMove"/> (the OS move loop — the standard on-screen-keyboard
/// recipe for NOACTIVATE windows). WPF mouse capture is held only for the pre-threshold press,
/// so a press near the widget's edge that slides outward still routes its moves/up to Root
/// instead of being swallowed (review finding); the drag itself is never capture-driven, since
/// Win32 grants only partial capture to a window whose thread isn't in the foreground — this
/// window's normal state.
/// </summary>
public partial class FloatingCatWindow : Window
{
    private readonly AppSettingsViewModel _settings;
    private readonly Action<WindowFrame> _onClick;
    private readonly Action<System.Drawing.Point> _onRightClick;
    private bool _closeForReal;
    private bool _everShown;
    private bool _pressed;
    private bool _dragged;
    private System.Windows.Point _pressDevice;

    /// <param name="onClick">Left-click without a drag; receives this window's logical frame so the
    /// popover can anchor beside it.</param>
    /// <param name="onRightClick">Right-click; receives the cursor in PHYSICAL screen px (what
    /// WinForms' <c>ContextMenuStrip.Show</c> expects).</param>
    public FloatingCatWindow(AppSettingsViewModel settings, Action<WindowFrame> onClick,
        Action<System.Drawing.Point> onRightClick)
    {
        InitializeComponent();
        _settings = settings;
        _onClick = onClick;
        _onRightClick = onRightClick;

        Root.Width = FloatingCatPlacement.WidgetWidth;
        Root.Height = FloatingCatPlacement.WidgetHeight;
        Pet.SetMinimal(true);

        Closing += FloatingCatWindow_Closing;
        _settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(AppSettingsViewModel.FloatingCatVisible)) ApplyVisibility();
        };
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        var hwnd = new WindowInteropHelper(this).Handle;
        var exStyle = NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE);
        NativeMethods.SetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE,
            exStyle | NativeMethods.WS_EX_NOACTIVATE | NativeMethods.WS_EX_TOOLWINDOW);
    }

    /// <summary>Shows or hides per <see cref="AppSettingsViewModel.FloatingCatVisible"/>. On show,
    /// the persisted frame is restored onto the CURRENT virtual screen (or defaults to the
    /// bottom-right of the primary work area). <c>SystemParameters</c> values are already logical
    /// units, unlike WinForms' <c>Screen.WorkingArea</c> (see PopoverWindow.PositionNearTray).</summary>
    public void ApplyVisibility()
    {
        if (!_settings.FloatingCatVisible)
        {
            if (IsVisible) { SaveFrame(); Hide(); }
            return;
        }

        var virtualScreen = new WindowFrame(
            SystemParameters.VirtualScreenLeft, SystemParameters.VirtualScreenTop,
            SystemParameters.VirtualScreenWidth, SystemParameters.VirtualScreenHeight);
        var wa = SystemParameters.WorkArea;
        var frame = FloatingCatPlacement.Restore(
            _settings.FloatingCatFrame, virtualScreen, new WindowFrame(wa.X, wa.Y, wa.Width, wa.Height));
        Left = frame.X;
        Top = frame.Y;
        _everShown = true;
        Show();   // ShowActivated="False" → no activation
    }

    public void SetMood(Mood mood) => Pet.SetMood(mood);

    /// <summary>This window's frame in logical units — the popover anchor.</summary>
    public WindowFrame CurrentFrame => new(Left, Top, ActualWidth, ActualHeight);

    /// <summary>Lets Program.cs release the window for real on app shutdown instead of just
    /// hiding it (symmetry with PinnedWindow/SettingsWindow.CloseForReal).</summary>
    public void CloseForReal()
    {
        _closeForReal = true;
        Close();
    }

    private void FloatingCatWindow_Closing(object? sender, CancelEventArgs e)
    {
        SaveFrame();
        if (_closeForReal) return;
        e.Cancel = true;
        Hide();
    }

    /// <summary>Guarded by <see cref="_everShown"/>: Left/Top are NaN before the first show, and
    /// SettingsStore.Save would silently swallow the resulting serialization failure.</summary>
    private void SaveFrame()
    {
        if (_everShown) _settings.FloatingCatFrame = CurrentFrame;
    }

    // ---- click vs drag ----

    private void Root_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        _pressed = true;
        _dragged = false;
        // Screen-space (device px) so the delta isn't distorted by the window moving under the cursor.
        _pressDevice = PointToScreen(e.GetPosition(this));
        Root.CaptureMouse();   // keep Move/Up routed here even if the cursor slips past the edge
        e.Handled = true;
    }

    private void Root_MouseMove(object sender, System.Windows.Input.MouseEventArgs e)
    {
        if (!_pressed || _dragged || e.LeftButton != MouseButtonState.Pressed) return;
        var delta = ToLogical(PointToScreen(e.GetPosition(this)) - _pressDevice);
        if (!FloatingCatPlacement.IsDrag(delta.X, delta.Y)) return;

        _dragged = true;
        Root.ReleaseMouseCapture();   // the OS move loop takes its own capture
        try
        {
            DragMove();   // OS move loop; returns once the button is released
        }
        catch (InvalidOperationException)
        {
            // Button released between the check above and the call — nothing to move.
        }
        _pressed = false;
        SaveFrame();
    }

    private void Root_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (!_pressed) return;
        _pressed = false;
        Root.ReleaseMouseCapture();
        e.Handled = true;
        if (!_dragged) _onClick(CurrentFrame);
    }

    private void Root_LostMouseCapture(object sender, System.Windows.Input.MouseEventArgs e)
    {
        // Capture taken away mid-press (a modal, another app's capture) — not a click. The
        // explicit release before DragMove above also lands here, with _dragged already true.
        if (!_dragged) _pressed = false;
    }

    private void Root_MouseRightButtonUp(object sender, MouseButtonEventArgs e)
    {
        e.Handled = true;
        // The NotifyIcon KB trick: a ContextMenuStrip only auto-dismisses on an outside click if
        // its owner thread is in the foreground, so foreground this window first (programmatic
        // activation is allowed despite WS_EX_NOACTIVATE). That closes an open popover — fine on
        // a right-click, and the left-click path stays non-activating.
        NativeMethods.SetForegroundWindow(new WindowInteropHelper(this).Handle);
        _onRightClick(System.Windows.Forms.Control.MousePosition);
    }

    private System.Windows.Vector ToLogical(System.Windows.Vector deviceDelta)
    {
        var toLogical = PresentationSource.FromVisual(this)?.CompositionTarget?.TransformFromDevice
            ?? System.Windows.Media.Matrix.Identity;
        return toLogical.Transform(deviceDelta);
    }

    private static class NativeMethods
    {
        public const int GWL_EXSTYLE = -20;
        public const long WS_EX_TOOLWINDOW = 0x00000080;
        public const long WS_EX_NOACTIVATE = 0x08000000;

        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
        private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
        private static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

        [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
        private static extern int GetWindowLong32(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll", EntryPoint = "SetWindowLongW")]
        private static extern int SetWindowLong32(IntPtr hWnd, int nIndex, int dwNewLong);

        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        // The *Ptr entry points exist only in 64-bit user32; the shipped build is x64, but keep
        // the 32-bit fallback so a local x86 build doesn't throw EntryPointNotFoundException.
        public static long GetWindowLong(IntPtr hWnd, int index) =>
            IntPtr.Size == 8 ? GetWindowLongPtr64(hWnd, index).ToInt64() : GetWindowLong32(hWnd, index);

        public static void SetWindowLong(IntPtr hWnd, int index, long value)
        {
            if (IntPtr.Size == 8) SetWindowLongPtr64(hWnd, index, new IntPtr(value));
            else SetWindowLong32(hWnd, index, unchecked((int)value));
        }
    }
}
