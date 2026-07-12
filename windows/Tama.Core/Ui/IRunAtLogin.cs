namespace Tama.Core.Ui;

/// <summary>
/// Abstraction over "start the app automatically when the user logs in" (planc-ui-spec.md §2g /
/// §7 note 3: mac reads <c>SMAppService.mainApp.status</c> live rather than a persisted flag —
/// OS-authoritative, not app-config-authoritative). The Windows implementation
/// (<c>Tama.Tray.RunAtLogin</c>) manipulates the HKCU
/// <c>Software\Microsoft\Windows\CurrentVersion\Run</c> key; it lives in Tama.Tray (registry
/// access is Windows-only), while this interface lives here so <see cref="DashboardViewModel"/>'s
/// wiring is unit-testable on mac with a fake, mirroring every other injected dependency in this
/// codebase (<c>AgentMonitor</c>'s clock, <c>SettingsStore</c>'s directory, etc.).
/// </summary>
public interface IRunAtLogin
{
    /// <summary>True if the app is currently registered to launch at login. Queried live —
    /// never cached — so it reflects reality even if changed outside the app.</summary>
    bool IsEnabled();

    /// <summary>Registers (true) or unregisters (false) the app for launch-at-login. Best-effort:
    /// implementations must never throw (mirrors every other persistence path in this codebase).</summary>
    void SetEnabled(bool enabled);
}
