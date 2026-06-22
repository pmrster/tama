import AppKit
import Combine
import SwiftUI
import TamaCore

/// A floating panel that hosts the dashboard so it can stay on screen ("Pin"). Implemented
/// in AppKit because a SwiftUI `Window` scene does not reliably open from a menu-bar-only
/// (agent) app.
@MainActor
final class PinnedPanel {
    static let shared = PinnedPanel()
    private var panel: NSPanel?
    private var builder: (() -> AnyView)?

    func configure(_ make: @escaping () -> some View) {
        builder = { AnyView(make()) }
    }

    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            present()
        }
    }

    private func present() {
        guard let builder else { return }
        let firstTime = panel == nil
        let p = panel ?? makePanel()
        p.contentViewController = NSHostingController(rootView: builder())
        if firstTime {
            p.setContentSize(NSSize(width: 360, height: 480))
            p.center()
        }
        panel = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 480),
                        styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.title = "Tama"
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.contentMinSize = NSSize(width: 300, height: 240)
        p.acceptsMouseMovedEvents = true   // so SwiftUI `.help` tooltips track inside the panel
        return p
    }
}

/// Owns the menu-bar status item and its dropdown. We manage `NSStatusItem` directly (instead
/// of SwiftUI's `MenuBarExtra`) so left-click opens the dashboard popover while **right-click**
/// shows a small menu (About / Quit) — MenuBarExtra offers no right-click hook.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let monitor: AgentMonitor
    private var cancellable: AnyCancellable?
    private var appearanceCancellable: AnyCancellable?

    init(monitor: AgentMonitor) {
        self.monitor = monitor
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = MenuBarIcon.image(for: monitor.state.mood)
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let hosting = NSHostingController(rootView: DashboardView(monitor: monitor, managesRefresh: false))
        hosting.sizingOptions = [.preferredContentSize]   // popover tracks the SwiftUI content size
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.delegate = self

        // NSPopover does NOT inherit `NSApp.appearance` like the panels do, so force it to
        // match the Light/Dark setting — otherwise the open popover keeps its launch colors
        // while About/Pinned recolor. Re-applied on every show (below) and on every change.
        popover.appearance = AppSettings.shared.nsAppearance
        appearanceCancellable = AppSettings.shared.$appearance
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.popover.appearance = AppSettings.shared.nsAppearance }

        // Keep the menu-bar count text in sync with the live state.
        cancellable = monitor.$state.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.statusItem.button?.image = MenuBarIcon.image(for: self?.monitor.state.mood ?? .napping)
            self?.updateTitle()
        }
        updateTitle()
    }

    private func updateTitle() {
        statusItem.button?.title = " \(monitor.activeCount())"
    }

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.appearance = AppSettings.shared.nsAppearance
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverWillShow(_ notification: Notification) {
        monitor.beginInteractiveRefresh(interval: 7)
    }

    func popoverDidClose(_ notification: Notification) {
        monitor.endInteractiveRefresh(backgroundInterval: 30)
    }

    private func showMenu() {
        let menu = NSMenu()
        let about = NSMenuItem(title: "About Tama", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Tama",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        }
    }

    @objc private func showAbout() {
        if popover.isShown { popover.performClose(nil) }
        AboutPanel.show()
    }

    @objc private func showSettings() {
        if popover.isShown { popover.performClose(nil) }
        SettingsPanel.show()
    }
}

/// Tama's Settings window — a small floating panel hosting `SettingsView`, in the same
/// AppKit-panel style as `AboutPanel` (a SwiftUI window scene does not reliably open from a
/// menu-bar-only / `LSUIElement` app).
@MainActor
enum SettingsPanel {
    private static var panel: NSPanel?

    static func show() {
        let p = panel ?? makePanel()
        panel = p
        p.contentViewController = NSHostingController(rootView: SettingsView())
        p.setContentSize(NSSize(width: 320, height: 380))
        p.center()
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    static func close() { panel?.orderOut(nil) }

    private static func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 380),
                        styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.title = "Tama Settings"
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        return p
    }
}

/// Tama's custom "About" window — a small floating panel hosting `AboutView`, in the app's
/// pixel-cat aesthetic. Implemented as an AppKit `NSPanel` (like `PinnedPanel`) because the
/// standard `orderFrontStandardAboutPanel` does not reliably surface from a menu-bar-only
/// (`LSUIElement` / accessory) app, so clicking "About" appeared to do nothing.
@MainActor
enum AboutPanel {
    private static var panel: NSPanel?

    static func show() {
        let p = panel ?? makePanel()
        panel = p
        // Re-host fresh each time so the version/animation start clean.
        p.contentViewController = NSHostingController(rootView: AboutView())
        p.setContentSize(NSSize(width: 320, height: 360))
        p.center()
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    static func close() { panel?.orderOut(nil) }

    private static func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 360),
                        styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.title = "About Tama"
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        return p
    }
}

/// The contents of the About window. Reads the version from the real Info.plist in the
/// packaged `.app`, falling back to "dev" when running unbundled (`swift run`).
struct AboutView: View {
    @ObservedObject private var settings = AppSettings.shared

    /// Latest-release page. `/latest` redirects to the newest tag, so this never goes stale.
    static let releasesURL = URL(string: "https://github.com/pmrster/tama/releases/latest")!
    static let repositoryURL = URL(string: "https://github.com/pmrster/tama")!

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
    private var year: Int { Calendar.current.component(.year, from: Date()) }

    var body: some View {
        VStack(spacing: 0) {
            // The mascot pacing across the top, on its own little stage.
            PetView(mood: .working(intensity: 2))
                .frame(height: 40)
                .padding(.horizontal, 18)
                .padding(.top, 18)

            VStack(spacing: 6) {
                Text("Tama")
                    .font(.system(size: scaled(22), weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.text)
                Text("v\(version) · build \(build)")
                    .font(.system(size: scaled(11), weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.dim)

                // Opens the releases page in the user's browser so they can compare versions.
                // The app itself makes no network call — `NSWorkspace.open` hands a URL to the
                // browser, which does the fetching. The "No network" invariant stays intact.
                Button {
                    NSWorkspace.shared.open(AboutView.releasesURL)
                } label: {
                    HStack(spacing: 3) {
                        Text("Check for updates")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.system(size: scaled(10), weight: .semibold))
                    .foregroundStyle(Palette.yellow)
                }
                .buttonStyle(.plain)
                .help("Open the releases page to see if a newer version is available")
            }
            .padding(.top, 10)

            Text("A menu-bar pixel cat that watches your local Claude Code, Codex, Gemini & Antigravity sessions — grouped by project folder — plus today's token usage.")
                .font(.system(size: scaled(11)))
                .foregroundStyle(Palette.dim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 14)

            // The hard design invariant, stated plainly.
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill").font(.system(size: scaled(10)))
                Text("Read-only · Local-only · No network")
                    .font(.system(size: scaled(10), weight: .semibold))
            }
            .foregroundStyle(Palette.green)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Palette.green.opacity(0.12), in: Capsule())
            .padding(.top, 14)

            Spacer(minLength: 12)

            Button { AboutPanel.close() } label: {
                Text("Close")
                    .font(.system(size: scaled(12), weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .padding(.horizontal, 22).padding(.vertical, 7)
                    .background(Palette.yellow.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 10)

            HStack(spacing: 8) {
                Text("© \(String(year)) pmrster")
                Text("·")
                Button {
                    NSWorkspace.shared.open(AboutView.repositoryURL)
                } label: {
                    Text("GitHub")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.yellow)
                .help("Open the Tama source repository")
            }
            .font(.system(size: scaled(10), weight: .medium, design: .monospaced))
            .foregroundStyle(Palette.dim)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.panel)
    }
}

/// The menu-bar icon: a tiny pixel-pet silhouette, drawn as a template image so it adapts to
/// light/dark menu bars. Gives the app a recognizable identity next to the counts. The glyph
/// changes with mood — awake cat for working/greeting/resting, curled cat for napping.
enum MenuBarIcon {
    // Awake silhouette (eyes open, tail up) — working / greeting / resting.
    private static let awake = [
        ".....XX...XX.",   // ears
        ".....XXXXXXX.",
        ".....XXXXXXXX",
        ".....XXXXXXXX",
        "XX...XXXXXXXX",   // tail stub
        ".XXXXXXXXXXXX",   // tail merges into body
        ".XXXXXXXXXXXX",
        "..XXXXXXXXXX.",
        "..X.XX.XX.X..",   // legs
    ]
    // Sleeping silhouette (curled, lower profile, tail tucked) — napping.
    private static let asleep = [
        "............",
        "............",
        "....XXXX....",   // tucked head
        "..XXXXXXXX..",
        ".XXXXXXXXXX.",
        ".XXXXXXXXXXX",
        ".XXXXXXXXXXX",
        "..XXXXXXXX..",
        "............",
    ]

    @MainActor static func image(for mood: Mood) -> NSImage {
        let napping: Bool = { if case .napping = mood { return true } else { return false } }()
        let grid = napping ? asleep : awake
        let px: CGFloat = 1.7
        let cols = grid[0].count, rows = grid.count
        let img = NSImage(size: NSSize(width: CGFloat(cols) * px, height: CGFloat(rows) * px))
        img.lockFocus()
        NSColor.black.setFill()
        for (r, row) in grid.enumerated() {
            for (c, ch) in row.enumerated() where ch == "X" {
                // NSImage origin is bottom-left, so flip the row index.
                let rect = NSRect(x: CGFloat(c) * px, y: CGFloat(rows - 1 - r) * px, width: px, height: px)
                rect.fill()
            }
        }
        img.unlockFocus()
        img.isTemplate = true
        return img
    }
}
