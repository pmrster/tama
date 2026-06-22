import Foundation
import Combine

@MainActor
public final class AgentMonitor: ObservableObject {
    @Published public private(set) var state: AppState = .empty

    /// Time window for the displayed token/cost totals. Changing it re-scans immediately so the UI
    /// updates without waiting for the next poll. The reader's per-hour cache makes this cheap (no re-read).
    @Published public var window: TokenWindow = .today {
        didSet { if window != oldValue { refresh() } }
    }

    private let reader: ActivityScanning
    private let presenceScanner: OllamaPresenceScanning
    private let ollamaReader: OllamaReading
    private let estimator: CostEstimator
    private let nowProvider: () -> Date
    private let runsInBackground: Bool
    private let ioQueue = DispatchQueue(label: "tama.widget.io", qos: .utility)
    private var timer: Timer?
    private var currentInterval: TimeInterval?
    private var interactiveConsumers = 0
    private var inFlight = false
    private let moodEngine: MoodEngine
    private let catStateStore: CatStateStore
    private var catState: CatState

    public init(reader: ActivityScanning, now: @escaping () -> Date = { Date() },
                runsInBackground: Bool = true, estimator: CostEstimator = CostEstimator(),
                moodEngine: MoodEngine = MoodEngine(),
                catStateStore: CatStateStore = .applicationSupport(),
                presenceScanner: OllamaPresenceScanning = SysctlProcessScanner(),
                ollamaReader: OllamaReading = OllamaReader()) {
        self.reader = reader
        self.presenceScanner = presenceScanner
        self.ollamaReader = ollamaReader
        self.estimator = estimator
        self.nowProvider = now
        self.runsInBackground = runsInBackground
        self.moodEngine = moodEngine
        self.catStateStore = catStateStore
        self.catState = catStateStore.load()
    }

    /// Estimated pay-as-you-go API cost of this session's tokens today (not a subscription bill).
    public func cost(_ s: SessionInfo) -> Double { s.cost(using: estimator) }

    /// Reads the logs off the main thread (cached) and publishes the new state on main.
    public func refresh() {
        let now = nowProvider()
        let window = self.window
        guard runsInBackground else {
            apply(reader.scan(window: window), ollama: scanOllama(), now: now); return
        }
        if inFlight { return }                          // skip overlapping scans
        inFlight = true
        let reader = self.reader
        let scanOllama = self.scanOllama   // captured closures touch no main-actor state
        ioQueue.async { [weak self] in
            let activity = reader.scan(window: window)
            let ollama = scanOllama()
            DispatchQueue.main.async {
                self?.apply(activity, ollama: ollama, now: now)
                self?.inFlight = false
            }
        }
    }

    /// Detects the local Ollama server (process table) and enriches it from `server.log`.
    /// Captured as a value so it can run off the main actor; reads no `@MainActor` state.
    private nonisolated var scanOllama: @Sendable () -> OllamaStatus? {
        let scanner = presenceScanner, reader = ollamaReader
        return { Self.ollamaState(presence: OllamaPresence.isRunning(in: scanner.ollamaProcesses()),
                                  enrichment: reader.read()) }
    }

    /// Gates the tile: hidden unless the server is running; otherwise running + log enrichment.
    public nonisolated static func ollamaState(presence: Bool, enrichment: OllamaStatus?) -> OllamaStatus? {
        guard presence else { return nil }
        var status = enrichment ?? OllamaStatus()
        status.running = true
        return status
    }

    private func apply(_ activity: Activity, ollama: OllamaStatus?, now: Date) {
        var usage: [Provider: UsageStats] = [:]
        for (provider, tokens) in activity.totals {
            // Price each model's tokens at its own tier rate, then sum. Falls back to the rolled-up
            // breakdown (priced at the default rate) when no per-model split is available.
            let cost: Double
            if let perModel = activity.modelBreakdowns[provider], !perModel.isEmpty {
                cost = perModel.reduce(0.0) { acc, entry in
                    acc + estimator.cost(entry.value, provider: provider,
                                         model: entry.key.isEmpty ? nil : entry.key)
                }
            } else {
                cost = activity.breakdowns[provider].map { estimator.cost($0, provider: provider) } ?? 0
            }
            usage[provider] = UsageStats(todayTokens: tokens, todayCost: cost, byProject: [])
        }
        let (mood, newCatState) = moodEngine.evaluate(activity: activity, now: now, state: catState)
        if newCatState != catState {
            catState = newCatState
            catStateStore.save(newCatState)
        }
        state = AppState(sessions: [], usage: usage, lastUpdated: now,
                         activeSessions: activity.sessions, mood: mood, ollama: ollama)
    }

    public func start(interval: TimeInterval = 7) {
        guard interval > 0 else { stop(); return }
        if timer != nil, currentInterval == interval { return }
        timer?.invalidate()
        currentInterval = interval
        refresh()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = min(max(1, interval * 0.15), interval * 0.5)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        currentInterval = nil
    }

    public func beginInteractiveRefresh(interval: TimeInterval = 7) {
        interactiveConsumers += 1
        start(interval: interval)
    }

    public func endInteractiveRefresh(backgroundInterval: TimeInterval = 30) {
        interactiveConsumers = max(0, interactiveConsumers - 1)
        if interactiveConsumers == 0 {
            start(interval: backgroundInterval)
        }
    }

    /// Active sessions (project + folder) for one provider, most recent first.
    public func activeSessions(for provider: Provider) -> [SessionInfo] {
        state.activeSessions.filter { $0.provider == provider }
    }

    /// "Active" = a session whose log was written within `activeWindow` of the last scan.
    /// Reliable across every CLI and consistent with the displayed list.
    public static let activeWindow: TimeInterval = 900   // 15 minutes

    public func isActive(_ s: SessionInfo) -> Bool {
        state.lastUpdated.timeIntervalSince(s.lastActivity) < Self.activeWindow
    }

    public func activeCount(for provider: Provider? = nil) -> Int {
        state.activeSessions.filter { (provider == nil || $0.provider == provider) && isActive($0) }.count
    }
}
