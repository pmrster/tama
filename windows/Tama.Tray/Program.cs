using Tama.Core;

namespace Tama.Tray;

/// <summary>
/// Composition root — the WPF analog of TamaApp.swift + AppDelegate.applicationDidFinishLaunching
/// (spec §6). Custom entry point (see Tama.Tray.csproj's StartupObject) so this bootstrap reads
/// top-to-bottom in one place instead of inside App.xaml.cs's OnStartup.
///
/// Wiring mirrors the Swift app: one shared AgentMonitor instance for the process lifetime,
/// constructed from the real (non-demo) readers, started at the 30s background interval, bumped
/// to the 7s interactive interval while the popover is open and dropped back to 30s when it
/// closes (spec §6's poll-interval table / beginInteractiveRefresh-endInteractiveRefresh pair —
/// this app only ever has the popover as an interactive consumer until Task 6 adds the pinned
/// window, so a plain Start() call stands in for the Swift side's consumer-counting).
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

        // Captured only once WPF's Run() has installed a DispatcherSynchronizationContext on
        // this (UI) thread (System.Windows.Application.Run sets it before raising Startup), so
        // AgentMonitor's background-thread scan results marshal back here — mirrors the Swift
        // AgentMonitor's @MainActor publish contract (spec §7 note 12).
        app.Startup += (_, _) =>
        {
            var syncContext = SynchronizationContext.Current;
            (monitor, trayIcon) = Bootstrap(app, syncContext);
        };
        app.Exit += (_, _) =>
        {
            monitor?.Dispose();
            trayIcon?.Dispose();
        };

        app.Run();
    }

    private static (AgentMonitor Monitor, TrayIcon TrayIcon) Bootstrap(
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

        PopoverWindow? popover = null;

        void TogglePopover()
        {
            if (popover is not null)
            {
                popover.CloseSafely();   // triggers popover.Closed below (Deactivated also routes here)
                return;
            }
            popover = new PopoverWindow(monitor);
            popover.Closed += (_, _) =>
            {
                popover = null;
                monitor.Start(TimeSpan.FromSeconds(BackgroundIntervalSeconds));
            };
            popover.Show();
            popover.Activate();
            monitor.Start(TimeSpan.FromSeconds(InteractiveIntervalSeconds));
        }

        var trayIcon = new TrayIcon(
            onToggle: TogglePopover,
            onAbout: ShowAbout,
            onQuit: app.Shutdown);

        monitor.StateChanged += state => trayIcon.SetMood(state.Mood);
        monitor.Start(TimeSpan.FromSeconds(BackgroundIntervalSeconds));

        return (monitor, trayIcon);
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
