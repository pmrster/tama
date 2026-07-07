import SwiftUI
import TamaCore

@main
struct TamaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // Menu-bar-only app (LSUIElement): no real window scene. The status item and its popover
    // are owned by the AppDelegate via StatusItemController so we can handle right-click
    // (MenuBarExtra cannot). An empty Settings scene satisfies the `App` requirement.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.shared.applyAppearance()
        // Surface hover tooltips quickly (AppKit's default initial delay is ~1–2s, which
        // makes the many `.help(...)` hints feel hidden). 200 ms reads as responsive.
        UserDefaults.standard.set(200, forKey: "NSInitialToolTipDelay")
        // Demo / mock-data tooling is opt-in behind the TAMA_DEMO compile flag, so it is absent
        // from normal debug builds AND release builds — it only exists when explicitly built with
        // `-Xswiftc -DTAMA_DEMO`. `--demo` then runs the full live app on synthetic data (safe to
        // screen-record); `--sleep` pairs with it for the napping state.
        #if TAMA_DEMO
        Snapshot.renderIfRequested()
        let demo = CommandLine.arguments.contains("--demo")
        if demo { Snapshot.sleepMode = CommandLine.arguments.contains("--sleep") }
        let reader: ActivityScanning = demo ? Snapshot.MockReader() : ActiveSessionsReader(now: { Date() })
        #else
        let reader: ActivityScanning = ActiveSessionsReader(now: { Date() })
        #endif
        let monitor = AgentMonitor(reader: reader,
                                   historyReader: HistoryReader(),
                                   historyStore: .applicationSupport())
        // The pinned panel shows the same dashboard, hosted in an AppKit window.
        let pinnedMonitor = monitor
        PinnedPanel.shared.configure { DashboardView(monitor: pinnedMonitor, fixedWidth: nil) }
        monitor.start(interval: 30)
        statusController = StatusItemController(monitor: monitor)
    }
}
