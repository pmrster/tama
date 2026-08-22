import AppKit
import ImageIO
import SwiftUI
import TamaCore
import UniformTypeIdentifiers

// Opt-in dev tooling: the demo / mock-data code (`--demo`, `--snapshot`, `--readme-shots`,
// `--cat-gif`) exists ONLY when built with `-Xswiftc -DTAMA_DEMO`. It is absent from normal
// debug builds and from release builds, so a plain clone (`swift run Tama --demo`) and the
// shipped DMG both ignore it and always read the real logs. See TamaApp's `#if TAMA_DEMO` wiring.
#if TAMA_DEMO

/// Dev-only: `Tama --snapshot [width]` renders the dashboard with mock data to
/// /tmp/dash.png and exits. Not used by the shipping app.
enum Snapshot {
    nonisolated(unsafe) static var sleepMode = false
    struct MockReader: ActivityScanning {
        func scan() -> Activity {
            let now = Date()
            // --sleep: age every session past the 15-min active window so the cat naps.
            let extra: TimeInterval = Snapshot.sleepMode ? 3600 : 0
            // Synthesize a plausible per-type split from a total + its cache part, so the
            // mock preview shows realistic cost (fresh ≈ 70% input / 30% output; cache = reads).
            func bd(_ total: Int, _ cache: Int) -> TokenBreakdown {
                let fresh = max(0, total - cache)
                let input = fresh * 7 / 10
                return TokenBreakdown(input: input, output: fresh - input, cacheRead: cache, cacheWrite: 0)
            }
            func ses(_ p: Provider, _ proj: String, _ folder: String, _ idx: Int,
                     _ tok: Int, _ cache: Int = 0, _ model: String? = nil, title: String? = nil,
                     ctx: Int = 0, window: Int = 0, ago: TimeInterval) -> SessionInfo {
                SessionInfo(provider: p, project: proj, folder: folder,
                            lastActivity: now.addingTimeInterval(-(ago + extra)),
                            tokens: tok, cacheTokens: cache, contextTokens: ctx, contextWindow: window,
                            model: model, sessionId: String(format: "%08x", 0x019eddab &+ idx), title: title,
                            breakdown: bd(tok, cache), messages: 6 + idx * 13)
            }
            let review = "Review this change for security vulnerabilities. Changed files (you may Read the…"
            let titles = ["adjust cat character to look like this", nil, "i want to build a macbook app helper",
                          "rename it all to tama", "how to run it"]
            var mb: [SessionInfo] = []
            for i in 0..<14 {
                let title = i < titles.count ? titles[i] : review   // rows 5..13 are repeated reviews
                mb.append(ses(.claudeCode, "tama-widget",
                              "/Example/Projects/tama-widget", i,
                              i == 0 ? 328_300_000 : 380_000, i == 0 ? 300_000_000 : 50_000,
                              "claude-opus-4-7", title: title,
                              ctx: i == 0 ? 189_000 : 40_000 + i * 9_000, window: 200_000,
                              ago: Double(i) * 60))
            }
            let site = ses(.claudeCode, "tama-site",
                         "/Example/Projects/tama-site", 99,
                         930_800, 870_000, "claude-sonnet-4-6",
                         ctx: 96_000, window: 200_000, ago: 120)
            let cx = ses(.codex, "tama-widget",
                         "/Example/Projects/tama-widget", 42,
                         1_713_407, 1_514_496, "gpt-5-codex",
                         title: "github. scan for security, risk, technical debt",
                         ctx: 98_221, window: 258_400, ago: 90)
            let cli = ses(.antigravity, "tama-cli",
                              "/Example/Projects/tama-cli", 7,
                              0, 0, nil, ago: 300)
            return Activity(sessions: mb + [site, cx, cli],
                            breakdowns: [.claudeCode: bd(389_900_000, 380_000_000),
                                         .codex: bd(900_100_000, 880_000_000)])
        }
    }

    /// Mock Ollama enrichment for demo/screenshot builds — several models used this session, the
    /// current one busy (idle + aged when `--sleep`).
    struct MockOllama: OllamaReading {
        func read() -> OllamaStatus? {
            let asleep = Snapshot.sleepMode
            let now = Date()
            func used(_ ago: TimeInterval) -> Date { now.addingTimeInterval(-(ago + (asleep ? 3600 : 0))) }
            return OllamaStatus(running: true, lastActivity: used(asleep ? 0 : 5), models: [
                OllamaModelActivity(model: "gemma4:12b-mlx", current: true, busy: !asleep,
                                    lastActivity: used(5), contextWindow: 32768, contextTokens: 12_480,
                                    tokensPerSecond: 64, lastLatency: 30.3, kind: .chat, requestCount: 7),
                OllamaModelActivity(model: "gemma4:26b-mlx", lastActivity: used(620),
                                    contextWindow: 32768, contextTokens: 8_100, lastLatency: 41.4,
                                    kind: .chat, requestCount: 3),
                OllamaModelActivity(model: "qwen3.6:27b-mlx", lastActivity: used(3500),
                                    contextWindow: 32768, contextTokens: 2_300, lastLatency: 5.0,
                                    kind: .chat, requestCount: 2),
                OllamaModelActivity(model: "bge-m3", lastActivity: used(4200), lastLatency: 0.12,
                                    kind: .embed, requestCount: 11),
            ])
        }
    }
    struct MockOllamaPresence: OllamaPresenceScanning {
        func ollamaProcesses() -> [ProcInfo] {
            [ProcInfo(pid: 1, ppid: 0, execPath: "/Applications/Ollama.app/Contents/Resources/ollama",
                      argv: ["ollama", "serve"], cwd: nil, hasTTY: false, commName: "ollama")]
        }
    }

    /// Mock plan limits for demo/screenshot builds: two Claude accounts (one fresh, one via the
    /// stale config cache) and a Codex Plus account — exercises every gauge state.
    struct MockQuotas: QuotaScanning {
        func scanQuotas() -> [AccountQuota] {
            let now = Date()
            return [
                AccountQuota(provider: .claudeCode, label: nil, accountKey: "a", identity: "dev@example.com", plan: "Max 5x",
                             windows: [QuotaWindow(kind: .session, usedPercent: 37, resetsAt: now.addingTimeInterval(2 * 3600 + 600)),
                                       QuotaWindow(kind: .weekly, usedPercent: 72, resetsAt: now.addingTimeInterval(3 * 86400 + 4 * 3600))],
                             fetchedAt: now.addingTimeInterval(-40), source: .claudeStatusline),
                AccountQuota(provider: .claudeCode, label: "work", accountKey: "b", identity: "me@work.example", plan: "Team",
                             windows: [QuotaWindow(kind: .session, usedPercent: 0, resetsAt: nil),
                                       QuotaWindow(kind: .weekly, usedPercent: 12, resetsAt: now.addingTimeInterval(5 * 86400))],
                             fetchedAt: now.addingTimeInterval(-26 * 3600), source: .claudeConfigCache),
                AccountQuota(provider: .codex, label: nil, accountKey: "default", identity: nil, plan: "Plus",
                             windows: [QuotaWindow(kind: .weekly, usedPercent: 46, resetsAt: now.addingTimeInterval(5 * 86400 + 15 * 3600))],
                             fetchedAt: now.addingTimeInterval(-300), source: .codexLog),
            ]
        }
    }

    /// Demo monitor: mock sessions plus a mock running Ollama server, so the local-model tile shows.
    @MainActor static func demoMonitor() -> AgentMonitor {
        AgentMonitor(reader: MockReader(), runsInBackground: false,
                     presenceScanner: MockOllamaPresence(), ollamaReader: MockOllama(),
                     quotaReader: MockQuotas())
    }

    @MainActor
    static func renderIfRequested() {
        let args = CommandLine.arguments
        if args.contains("--dump") {
            let act = ActiveSessionsReader(now: { Date() }).scan()
            for s in act.sessions {
                let kind = s.title == nil ? "id  " : "name"
                print("[\(s.provider.shortName)] \(kind) \(s.displayName)  ·  id=\(s.sessionId ?? "—")  proj=\(s.project)")
            }
            exit(0)
        }
        if let i = args.firstIndex(of: "--readme-shots") {
            let outDir = (i + 1 < args.count && !args[i + 1].hasPrefix("-")) ? args[i + 1] : "assets"
            renderReadmeShots(to: outDir)
            exit(0)
        }
        if let i = args.firstIndex(of: "--cat-gif") {
            let outDir = (i + 1 < args.count && !args[i + 1].hasPrefix("-")) ? args[i + 1] : "assets"
            renderCatGIFs(to: outDir)
            exit(0)
        }
        guard let i = args.firstIndex(of: "--snapshot") else { return }
        let width = (i + 1 < args.count ? Double(args[i + 1]) : nil).map { CGFloat($0) } ?? 340
        sleepMode = args.contains("--sleep")
        let monitor = demoMonitor()
        monitor.refresh()
        if args.contains("--expand") {
            let folder = "/Example/Projects/tama-widget"
            UIState.shared.expandedFolders = ["claudeCode:\(folder)"]
            UIState.shared.expandedGroups = ["claudeCode:\(folder):Review this change for security vulnerabilities. Changed files (you may Read the…"]
        }
        if let m = args.firstIndex(of: "--metric"), m + 1 < args.count, let n = Int(args[m + 1]) {
            UIState.shared.defaultMetric = n   // 0 ctx · 1 today · 2 fresh · 3 in · 4 out · 5 cache rd · 6 cache wr
        }
        if args.contains("--active-only") { UIState.shared.activeOnly = true }

        let view = NSHostingView(rootView: DashboardView(monitor: monitor, fixedWidth: width))
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        try? png.write(to: URL(fileURLWithPath: "/tmp/dash.png"))
        print("snapshot \(Int(view.bounds.width))x\(Int(view.bounds.height)) -> /tmp/dash.png")
        exit(0)
    }

    // MARK: README image generator (`--readme-shots [outdir]`, default ./assets)

    /// Render every README image — dashboard (active + sleeping) and the mascot closeup, each
    /// in light and dark — from synthetic `MockReader` data. Dev-only; ships nothing.
    @MainActor
    static func renderReadmeShots(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let appearances: [(String, NSAppearance)] = [
            ("light", NSAppearance(named: .aqua)!),
            ("dark", NSAppearance(named: .darkAqua)!),
        ]

        func write(_ data: Data?, _ name: String) {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            guard let data, (try? data.write(to: url)) != nil else { print("FAILED \(name)"); return }
            print("wrote \(url.path) (\(data.count / 1024) kB)")
        }

        func dashboards(_ prefix: String) {
            for (tag, ap) in appearances {
                let monitor = demoMonitor()
                monitor.refresh()
                write(renderPNG(DashboardView(monitor: monitor, fixedWidth: 300), appearance: ap),
                      "\(prefix)-\(tag).png")
            }
        }

        // Hero: active sessions, one folder expanded so session rows show.
        sleepMode = false
        UIState.shared.expandedFolders = ["claudeCode:/Example/Projects/tama-widget"]
        dashboards("dashboard")

        // Pinned window: the same tree at the resizable width (fixedWidth nil), which adds
        // full session names + inline message counts the narrow popover hides.
        for (tag, ap) in appearances {
            let monitor = demoMonitor()
            monitor.refresh()
            let view = DashboardView(monitor: monitor, fixedWidth: nil, managesRefresh: false)
                .frame(width: 380, height: 540)
            write(renderPNG(view, appearance: ap), "pinned-\(tag).png")
        }

        // Settings window. Set the stored appearance too so the segmented picker highlights
        // the matching option (Light/Dark) rather than always showing "System".
        for (tag, ap) in appearances {
            AppSettings.shared.appearance = (tag == "dark") ? .dark : .light
            write(renderPNG(SettingsView().frame(width: 320, height: 380), appearance: ap),
                  "settings-\(tag).png")
        }
        AppSettings.shared.appearance = .system

        // About window.
        for (tag, ap) in appearances {
            write(renderPNG(AboutView().frame(width: 320, height: 360), appearance: ap),
                  "about-\(tag).png")
        }

        // Sleeping: same data aged past the active window → the cat naps.
        sleepMode = true
        dashboards("dashboard-sleep")

        // Mascot closeup, frozen on a frame where "meow~" is showing.
        for (tag, ap) in appearances {
            write(renderPNG(CatCard(), appearance: ap, scale: 3), "cat-\(tag).png")
        }

        // Animated walking-cat GIFs (light + dark).
        renderCatGIFs(to: dir)
    }

    /// Write one seamless walking-cat GIF per appearance (`cat-walk-light.gif` / `-dark`). The
    /// cat's horizontal motion is a triangle wave, so sampling exactly one period loops cleanly.
    @MainActor
    static func renderCatGIFs(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        // These mirror PetView.motion for energy 4 at the 200pt strip width, so `period` is the
        // exact loop length: range = width − sprite(48) − 2·margin(6); speed = 28 + 10·energy.
        let frames = 44
        let range = 200.0 - 48.0 - 12.0
        let speed = 28.0 + 4.0 * 10.0
        let period = 2.0 * range / speed
        let t0 = 1.0                          // start past t<1s so the periodic "meow~" stays hidden
        let delay = period / Double(frames)
        let appearances: [(String, NSAppearance)] = [
            ("light", NSAppearance(named: .aqua)!), ("dark", NSAppearance(named: .darkAqua)!),
        ]
        for (tag, ap) in appearances {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("cat-walk-\(tag).gif")
            guard let dest = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.gif.identifier as CFString, frames, nil) else { print("FAILED \(url.lastPathComponent)"); continue }
            CGImageDestinationSetProperties(dest,
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            let frameProps = [kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delay,
                kCGImagePropertyGIFUnclampedDelayTime: delay,
            ]] as CFDictionary
            var written = 0
            for i in 0..<frames {
                let t = t0 + period * Double(i) / Double(frames)
                guard let cg = renderRep(CatStrip(t: t), appearance: ap, scale: 2)?.cgImage else { continue }
                CGImageDestinationAddImage(dest, cg, frameProps)
                written += 1
            }
            if CGImageDestinationFinalize(dest) {
                print("wrote \(url.path) (\(written) frames, \(String(format: "%.2f", period))s loop)")
            } else { print("FAILED \(url.lastPathComponent)") }
        }
    }

    /// Render a SwiftUI view to a bitmap at `scale`× in the given appearance. Sets the hosting
    /// view's appearance (and `NSApp`'s) so the adaptive `Palette` dynamic `NSColor`s resolve to
    /// the right light/dark variant during `cacheDisplay`.
    @MainActor
    private static func renderRep(_ root: some View, appearance: NSAppearance, scale: CGFloat = 2) -> NSBitmapImageRep? {
        NSApp.appearance = appearance
        let host = NSHostingView(rootView: root)
        host.appearance = appearance
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let bounds = host.bounds
        guard bounds.width > 0, bounds.height > 0,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(bounds.width * scale),
                pixelsHigh: Int(bounds.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = bounds.size   // points; larger pixel dims → cacheDisplay draws at `scale`×
        host.cacheDisplay(in: bounds, to: rep)
        return rep
    }

    @MainActor
    private static func renderPNG(_ root: some View, appearance: NSAppearance, scale: CGFloat = 2) -> Data? {
        renderRep(root, appearance: appearance, scale: scale)?.representation(using: .png, properties: [:])
    }
}

/// The mascot on its own little card, for the README closeup. A fixed `snapshotTime` freezes
/// the walk on a frame where "meow~" shows so the PNG is deterministic.
private struct CatCard: View {
    var body: some View {
        PetView(mood: .working(intensity: 3), snapshotTime: 0.35)
            .frame(width: 168)
            .padding(.horizontal, 18)
            .padding(.top, 16).padding(.bottom, 12)
            .background(Palette.panel)
    }
}

/// One GIF frame of the mascot pacing, at the clock time `t`. Width 200 matches the loop math
/// in `renderCatGIFs`; energy 4 = a brisk-but-cute walk.
private struct CatStrip: View {
    let t: Double
    var body: some View {
        PetView(mood: .working(intensity: 4), snapshotTime: t)
            .frame(width: 200)
            .padding(.vertical, 4)
            .background(Palette.panel)
    }
}

#endif
