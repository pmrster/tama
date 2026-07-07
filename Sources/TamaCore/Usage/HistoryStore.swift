import Foundation

/// Persists per-day usage rollups as JSON so days that age out of the agents' own log
/// retention (Claude keeps ~30 days by default) survive. The directory is injected
/// (shipped app → `~/Library/Application Support/Tama/`; tests → a temp dir) and, like
/// `CatStateStore`, every write lands strictly inside it — never in any agent log tree.
/// Missing or malformed files load as empty and never crash.
/// @unchecked Sendable: crosses onto AgentMonitor's IO queue; FileManager is thread-safe
/// and the struct is otherwise immutable.
public struct HistoryStore: @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager

    public init(directory: URL, fileManager: FileManager = .default) {
        self.fileURL = directory.appendingPathComponent("history.json")
        self.fileManager = fileManager
    }

    public func load() -> [DayUsage] {
        guard let data = try? Data(contentsOf: fileURL),
              let days = try? JSONDecoder().decode([DayUsage].self, from: data) else { return [] }
        return days
    }

    /// Atomic write, skipped when the encoded bytes are unchanged (sortedKeys keeps the
    /// encoding deterministic so the byte compare is meaningful).
    public func save(_ days: [DayUsage]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(days.sorted { $0.day < $1.day }) else { return }
        if let existing = try? Data(contentsOf: fileURL), existing == data { return }
        try? fileManager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    /// The shipped store: `~/Library/Application Support/Tama/`. Same fallback as CatStateStore.
    public static func applicationSupport(fileManager: FileManager = .default) -> HistoryStore {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return HistoryStore(directory: base.appendingPathComponent("Tama", isDirectory: true),
                            fileManager: fileManager)
    }

    /// Hybrid merge: any day the fresh scan produced wins (logs are the truth while they
    /// exist); days only the store knows (aged out of logs) survive; everything outside
    /// [oldestKey, todayKey] is dropped (retention cap + future-dated junk).
    public static func merge(stored: [DayUsage], scanned: [DayUsage],
                             oldestKey: String, todayKey: String) -> [DayUsage] {
        var byDay: [String: DayUsage] = [:]
        for d in stored { byDay[d.day] = d }
        for d in scanned { byDay[d.day] = d }
        return byDay.values
            .filter { $0.day >= oldestKey && $0.day <= todayKey }
            .sorted { $0.day < $1.day }
    }
}
