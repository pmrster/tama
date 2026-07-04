using Tama.Core;
using Tama.Core.Ui;
using Tama.Tray.Views;

namespace Tama.Tray;

/// <summary>
/// Composition root — the WPF analog of TamaApp.swift + AppDelegate.applicationDidFinishLaunching
/// (spec §6). Custom entry point (see Tama.Tray.csproj's StartupObject) so this bootstrap reads
/// top-to-bottom in one place instead of inside App.xaml.cs's OnStartup.
///
/// Wiring mirrors the Swift app: one shared AgentMonitor instance for the process lifetime,
/// constructed from the real (non-demo) readers, started at the 30s background interval, bumped
/// to the 7s interactive interval while the popover OR the pinned window is open and dropped back
/// to 30s once neither is (spec §6's poll-interval table / beginInteractiveRefresh-
/// endInteractiveRefresh pair). Since only one of {popover, pinned} is ever visible at a time in
/// this app (see PinnedWindow's own doc comment), a plain per-surface Start() call at each
/// show/close stands in for the Swift side's interactiveConsumers reference count.
/// </summary>
public static class Program
{
    private const double InteractiveIntervalSeconds = 7;
    private const double BackgroundIntervalSeconds = 30;

    [STAThread]
    public static void Main()
    {
        var app = new App();
        app.InitializeComponent();

        AgentMonitor? monitor = null;
        TrayIcon? trayIcon = null;
        SettingsWindow? settingsWindow = null;
        PinnedWindow? pinnedWindow = null;

        // Captured only once WPF's Run() has installed a DispatcherSynchronizationContext on
        // this (UI) thread (System.Windows.Application.Run sets it before raising Startup), so
        // AgentMonitor's background-thread scan results marshal back here — mirrors the Swift
        // AgentMonitor's @MainActor publish contract (spec §7 note 12).
        app.Startup += (_, _) =>
        {
            var syncContext = SynchronizationContext.Current;
            (monitor, trayIcon, settingsWindow, pinnedWindow) = Bootstrap(app, syncContext);
        };
        app.Exit += (_, _) =>
        {
            monitor?.Dispose();
            trayIcon?.Dispose();
            settingsWindow?.CloseForReal();
            pinnedWindow?.CloseForReal();
        };

        app.Run();
    }

    private static (AgentMonitor Monitor, TrayIcon TrayIcon, SettingsWindow SettingsWindow, PinnedWindow PinnedWindow) Bootstrap(
        System.Windows.Application app, SynchronizationContext? syncContext)
    {
        var monitor = new AgentMonitor(
            scanner: ActiveSessionsScanner.CreateDefault(() => DateTimeOffset.Now),
            presence: new ProcessOllamaPresence(),
            ollamaReader: new OllamaReader(OllamaReader.DefaultLogPath(), TimeZoneInfo.Local),
            estimator: new CostEstimator(),
            moodEngine: new MoodEngine(),
            catStateStore: CatStateStore.AppData(),
            now: () => DateTimeOffset.Now,
            runsInBackground: true,
            syncContext: syncContext);

        // Constructed once alongside AgentMonitor, NOT per popover open/close — DashboardViewModel's
        // own doc comment requires this: it owns collapse/expand sets, active-only filter, and
        // metric-cycle selections that must persist across the transient popover being closed and
        // reopened (mirrors the Swift port's process-lifetime UIState.shared, spec §7 note 7).
        // runAtLogin backs the footer's "Launch at login" checkbox (task-6-brief.md's IRunAtLogin).
        var runAtLogin = new RunAtLogin();
        var dashboardVm = new DashboardViewModel(monitor, runAtLogin);

        // Appearance/font-size settings (spec §5) — persisted to %APPDATA%\Tama\settings.json.
        // AppSettingsViewModel is now the single source of truth for Palette.Apply: applied once
        // here before any window is shown (mirrors AppDelegate.applicationDidFinishLaunching's
        // explicit AppSettings.shared.applyAppearance() call, spec §6 step 1), then again live on
        // every Settings change via the injected callback below. It also owns PinnedFrame (spec
        // §1b "remembers frame"), persisted through the same store.
        var appSettingsVm = new AppSettingsViewModel(
            SettingsStore.AppData(), systemIsDark: Palette.IsSystemDark, onAppearanceChanged: Palette.Apply);
        appSettingsVm.ApplyInitialAppearance();

        // Reused across opens (isReleasedWhenClosed = false, spec §1c) — Hide()s on close rather
        // than destroying, so its own Closing handler intercepts the close instead of this method.
        var settingsWindow = new SettingsWindow(appSettingsVm);

        void ShowSettings()
        {
            settingsWindow.Show();
            settingsWindow.Activate();
        }

        PopoverWindow? popover = null;

        void TogglePopover()
        {
            if (popover is not null)
            {
                popover.CloseSafely();   // triggers popover.Closed below (Deactivated also routes here)
                return;
            }
            // Reapply resolved appearance on popover open (macOS/Windows spec §1a).
            appSettingsVm.ReapplyIfSystem();
            popover = new PopoverWindow(dashboardVm, ShowAbout, app.Shutdown, TogglePinned, appSettingsVm.FontScale);
            popover.Closed += (_, _) =>
            {
                popover = null;
                monitor.Start(TimeSpan.FromSeconds(BackgroundIntervalSeconds));
            };
            popover.Show();
            popover.Activate();
            monitor.Start(TimeSpan.FromSeconds(InteractiveIntervalSeconds));
        }

        // Reused across pin/unpin (isReleasedWhenClosed = false, spec §1b) — same pattern as
        // settingsWindow above. Its own Toggle() handles show/hide + frame restore/persist; its
        // OWN pin button is wired directly to that Toggle() inside its constructor (no circular
        // "onPin" callback needed here, unlike the popover below which genuinely needs an external
        // reference to this instance).
        var pinnedWindow = new PinnedWindow(dashboardVm, appSettingsVm, ShowAbout, app.Shutdown);

        // Poll interval while the pinned window is open (spec §6: a visible dashboard runs the
        // interactive 7s cadence, reverting to 30s once neither surface is open). Since only one
        // of {popover, pinned} is ever visible at a time in this app (opening one focuses it,
        // which closes the transient popover via Deactivated), a plain IsVisible check is enough —
        // no need for the Swift side's interactiveConsumers reference count.
        pinnedWindow.IsVisibleChanged += (_, _) =>
            monitor.Start(TimeSpan.FromSeconds(
                pinnedWindow.IsVisible ? InteractiveIntervalSeconds : BackgroundIntervalSeconds));

        void TogglePinned() => pinnedWindow.Toggle();

        var trayIcon = new TrayIcon(
            onToggle: TogglePopover,
            onPinToggle: TogglePinned,
            onSettings: ShowSettings,
            onAbout: ShowAbout,
            onQuit: app.Shutdown);

        monitor.StateChanged += state => trayIcon.SetMood(state.Mood);
        monitor.Start(TimeSpan.FromSeconds(BackgroundIntervalSeconds));

        return (monitor, trayIcon, settingsWindow, pinnedWindow);
    }

    private static void ShowAbout() =>
        System.Windows.MessageBox.Show(
            "Tama for Windows\n\nShows how many Claude Code / Codex / Gemini / Antigravity agent "
            + "sessions are recently active, grouped by project folder, plus today's token usage. "
            + "Read-only, local-only, no network.",
            "About Tama",
            System.Windows.MessageBoxButton.OK,
            System.Windows.MessageBoxImage.None);
}
