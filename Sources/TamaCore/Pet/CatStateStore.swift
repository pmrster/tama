import Foundation

/// Persists the cat's own `CatState` as JSON. The directory is injected (real app →
/// Application Support; tests → a temp dir). This is the app's ONLY write, and it lands
/// strictly inside the injected directory — never in any agent log tree. Missing or
/// malformed files fall back to `.initial` and never crash.
public struct CatStateStore {
    private let fileURL: URL
    private let fileManager: FileManager

    public init(directory: URL, fileManager: FileManager = .default) {
        self.fileURL = directory.appendingPathComponent("cat-state.json")
        self.fileManager = fileManager
    }

    public func load() -> CatState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(CatState.self, from: data) else {
            return .initial
        }
        return state
    }

    public func save(_ state: CatState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? fileManager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    /// The shipped store: `~/Library/Application Support/Tama/`. Falls back to the temporary
    /// directory if Application Support can't be resolved, so it never force-unwraps.
    public static func applicationSupport(fileManager: FileManager = .default) -> CatStateStore {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return CatStateStore(directory: base.appendingPathComponent("Tama", isDirectory: true),
                             fileManager: fileManager)
    }
}
