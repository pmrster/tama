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
/// to 30s only once NEITHER is (spec §6's poll-interval table / beginInteractiveRefresh-
/// endInteractiveRefresh pair). This is reference-counted via <see cref="InteractivePolling"/>
/// (Begin() on popover-open and on pinned-window-shown, End() on popover-Closed and on
/// pinned-window-hidden) rather than a plain per-surface Start() call — a naive "just call
/// Start() on this surface's own open/close" approach regresses to 30s the instant ONE surface
/// closes even while the other is still open (e.g. pin, then open the popover, then let the
/// popover auto-close on focus loss: the pinned window is still visible but polling would wrongly
/// drop to 30s without the reference count — review finding, task-6-report.md fix wave).
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
        FloatingCatWindow? floatingCat = null;

        // Captured only once WPF's Run() has installed a DispatcherSynchronizationContext on
        // this (UI) thread (System.Windows.Application.Run sets it before raising Startup), so
        // AgentMonitor's background-thread scan results marshal back here — mirrors the Swift
        // AgentMonitor's @MainActor publish contract (spec §7 note 12).
        app.Startup += (_, _) =>
        {
            var syncContext = SynchronizationContext.Current;
            (monitor, trayIcon, settingsWindow, pinnedWindow, floatingCat) = Bootstrap(app, syncContext);
        };
        app.Exit += (_, _) =>
        {
            monitor?.Dispose();
            trayIcon?.Dispose();
            settingsWindow?.CloseForReal();
            pinnedWindow?.CloseForReal();
            floatingCat?.CloseForReal();
        };

        app.Run();
    }

    private static (AgentMonitor Monitor, TrayIcon TrayIcon, SettingsWindow SettingsWindow, PinnedWindow PinnedWindow,
        FloatingCatWindow FloatingCat) Bootstrap(
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

        // Reference-counted poll cadence (see this class's own doc comment) — Begin() from the
        // popover's open and the pinned window's shown transition, End() from the popover's
        // Closed and the pinned window's hidden transition; only drops to the background interval
        // once BOTH have called End().
        var interactivePolling = new InteractivePolling(
            monitor.Start, TimeSpan.FromSeconds(InteractiveIntervalSeconds), TimeSpan.FromSeconds(BackgroundIntervalSeconds));

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

        // anchor: null = summoned from the tray (opens at the tray corner); the floating cat passes
        // its own frame so the popover opens beside it instead.
        void TogglePopover(WindowFrame? anchor = null)
        {
            if (popover is not null)
            {
                popover.CloseSafely();   // triggers popover.Closed below (Deactivated also routes here)
                return;
            }
            // Reapply resolved appearance on popover open (macOS/Windows spec §1a).
            appSettingsVm.ReapplyIfSystem();
            popover = new PopoverWindow(dashboardVm, ShowAbout, app.Shutdown, TogglePinned, appSettingsVm.FontScale,
                anchor: anchor);
            popover.Closed += (_, _) =>
            {
                popover = null;
                interactivePolling.End();
            };
            popover.Show();
            popover.Activate();
            interactivePolling.Begin();
        }

        // Reused across pin/unpin (isReleasedWhenClosed = false, spec §1b) — same pattern as
        // settingsWindow above. Its own Toggle() handles show/hide + frame restore/persist; its
        // OWN pin button is wired directly to that Toggle() inside its constructor (no circular
        // "onPin" callback needed here, unlike the popover below which genuinely needs an external
        // reference to this instance).
        var pinnedWindow = new PinnedWindow(dashboardVm, appSettingsVm, ShowAbout, app.Shutdown);

        // Poll interval while the pinned window is open (spec §6: a visible dashboard runs the
        // interactive 7s cadence). Begin()/End() (not a plain per-surface Start() call) so this
        // correctly composes with the popover's own Begin()/End() above — the shared
        // interactivePolling only reverts to the background interval once NEITHER surface holds
        // it open (fix for the finding described in this class's doc comment).
        pinnedWindow.IsVisibleChanged += (_, _) =>
        {
            if (pinnedWindow.IsVisible) interactivePolling.Begin();
            else interactivePolling.End();
        };

        void TogglePinned() => pinnedWindow.Toggle();

        var trayIcon = new TrayIcon(
            onToggle: () => TogglePopover(),
            onPinToggle: TogglePinned,
            onFloatingCatToggle: () => appSettingsVm.FloatingCatVisible = !appSettingsVm.FloatingCatVisible,
            onSettings: ShowSettings,
            onAbout: ShowAbout,
            onQuit: app.Shutdown);

        // The floating desktop cat — constructed AFTER trayIcon so its right-click can reuse the
        // very same ContextMenuStrip. It shows/hides itself by observing FloatingCatVisible (the
        // tray item above and the Settings checkbox both just flip that one property), and the
        // tray item's check mark tracks the same property here. Deliberately NOT an
        // InteractivePolling consumer: it is a permanent surface, so counting it would pin the 7s
        // log-scan cadence for the app's whole life; it only needs Mood, where a 30s lag is
        // invisible — and it still gets the faster updates via StateChanged whenever the popover
        // or pinned window hold the interactive cadence.
        var floatingCat = new FloatingCatWindow(appSettingsVm,
            onClick: anchor => TogglePopover(anchor),
            onRightClick: trayIcon.ShowMenuAt);
        trayIcon.FloatingCatChecked = appSettingsVm.FloatingCatVisible;
        appSettingsVm.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(AppSettingsViewModel.FloatingCatVisible))
                trayIcon.FloatingCatChecked = appSettingsVm.FloatingCatVisible;
        };

        monitor.StateChanged += state =>
        {
            trayIcon.SetMood(state.Mood);
            floatingCat.SetMood(state.Mood);
        };
        floatingCat.SetMood(monitor.State.Mood);
        floatingCat.ApplyVisibility();   // shown by default on a fresh install (setting defaults to true)
        monitor.Start(TimeSpan.FromSeconds(BackgroundIntervalSeconds));

        return (monitor, trayIcon, settingsWindow, pinnedWindow, floatingCat);
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
