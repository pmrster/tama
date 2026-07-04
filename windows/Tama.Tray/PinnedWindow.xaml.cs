using System.ComponentModel;
using System.Windows;
using Tama.Core;
using Tama.Core.Ui;

namespace Tama.Tray;

/// <summary>
/// The resizable, always-on-top pinned dashboard window (planc-ui-spec.md §1b) — the WPF analog
/// of mac's <c>PinnedPanel</c>. Constructed once alongside the popover/settings windows
/// (Program.cs), reused across pin/unpin via a hide-not-destroy Closing handler (same pattern as
/// <see cref="Views.SettingsWindow"/>), remembering its frame (position + size) across toggles —
/// and across app relaunches — via <see cref="AppSettingsViewModel.PinnedFrame"/>. The restored
/// frame is clamped to the current virtual-screen bounds via <see cref="WindowFrameClamp"/> before
/// being applied, so a monitor-configuration change since the frame was saved can't strand the
/// window off-screen.
/// </summary>
public partial class PinnedWindow : Window
{
    private readonly AppSettingsViewModel _appSettingsVm;
    private bool _closeForReal;
    private bool _everShown;

    public PinnedWindow(DashboardViewModel vm, AppSettingsViewModel appSettingsVm, Action onAbout, Action onQuit)
    {
        InitializeComponent();
        _appSettingsVm = appSettingsVm;

        // The pin button rendered INSIDE this window is the "unpin" direction — wire it straight
        // to this instance's own Toggle() rather than threading an externally-constructed
        // callback through Program.cs (which would need this very instance before it exists).
        Dashboard.Initialize(vm, onAbout, onQuit, onPin: Toggle, fixedWidth: false, fontScale: appSettingsVm.FontScale);

        Closing += PinnedWindow_Closing;
    }

    /// <summary>Mirrors <c>PinnedPanel.toggle()</c> (spec §1b): if currently visible, hide it (the
    /// "unpin" direction — keeps the instance alive, isReleasedWhenClosed = false); else restore
    /// its last-known frame (or the spec's default 360x480, centered, on first presentation only)
    /// and show + activate it. Activating steals focus from a currently-open transient popover,
    /// which then closes itself via its own Deactivated handler — no explicit coordination needed
    /// here (spec: "pinning closes popover").</summary>
    public void Toggle()
    {
        // SaveFrame() here (not just in PinnedWindow_Closing) because Hide() does not raise the
        // Window's Closing event — only Close() (the X button / CloseForReal) does — so unpinning
        // via the pin button/tray menu would otherwise never persist the frame.
        if (IsVisible) { SaveFrame(); Hide(); return; }

        // Re-applies the current font scale so a Settings change made while this window was
        // hidden takes effect on this "next open" of the reused instance (spec §5/Task 5 carry).
        Dashboard.SetFontScale(_appSettingsVm.FontScale);
        RestoreOrDefaultFrame();
        Show();
        Activate();
    }

    private void RestoreOrDefaultFrame()
    {
        // Clamped against the CURRENT virtual-screen bounds (not whatever monitor config existed
        // when the frame was saved) — a display unplugged or a resolution change between app
        // sessions can otherwise strand the restored frame entirely off every connected monitor
        // (review finding — task-6-report.md fix wave). WindowFrameClamp.Clamp returns null when
        // the persisted frame is unrecoverable (essentially none of it would be on-screen), in
        // which case this falls through to the same default-frame path used when nothing was
        // persisted at all.
        var screen = new WindowFrame(
            SystemParameters.VirtualScreenLeft, SystemParameters.VirtualScreenTop,
            SystemParameters.VirtualScreenWidth, SystemParameters.VirtualScreenHeight);

        if (_appSettingsVm.PinnedFrame is { } f && WindowFrameClamp.Clamp(f, screen) is { } clamped)
        {
            Left = clamped.X;
            Top = clamped.Y;
            Width = clamped.Width;
            Height = clamped.Height;
        }
        else if (!_everShown)
        {
            // Spec §1b: default size 360x480, centered on first presentation only.
            Width = 360;
            Height = 480;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
        }
        _everShown = true;
    }

    private void PinnedWindow_Closing(object? sender, CancelEventArgs e)
    {
        SaveFrame();
        if (_closeForReal) return;
        e.Cancel = true;
        Hide();
    }

    private void SaveFrame() =>
        _appSettingsVm.PinnedFrame = new WindowFrame(Left, Top, Width, Height);

    /// <summary>Releases the DashboardView's VM subscription (lifecycle-leak fix, task-6 carry).
    /// Fires only on the real close driven by <see cref="CloseForReal"/> (app shutdown), since the
    /// ordinary unpin path hides rather than closes this reused instance.</summary>
    protected override void OnClosed(EventArgs e)
    {
        Dashboard.Teardown();
        base.OnClosed(e);
    }

    /// <summary>Lets Program.cs release the window for real on app shutdown instead of just
    /// hiding it (symmetry with SettingsWindow.CloseForReal).</summary>
    public void CloseForReal()
    {
        _closeForReal = true;
        Close();
    }
}
