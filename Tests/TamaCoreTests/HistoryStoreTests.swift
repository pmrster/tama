import XCTest
@testable import TamaCore

final class HistoryStoreTests: XCTestCase {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("hstore-\(UUID().uuidString)")
    }
    private func day(_ key: String, input: Int) -> DayUsage {
        DayUsage(day: key, models: [.claudeCode: ["opus": TokenBreakdown(input: input)]])
    }

    func test_round_trip() {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir)
        let days = [day("2026-07-01", input: 1), day("2026-07-02", input: 2)]
        store.save(days)
        XCTAssertEqual(store.load(), days)
    }

    func test_missing_or_corrupt_file_loads_empty() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir)
        XCTAssertEqual(store.load(), [])
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "not json".write(to: dir.appendingPathComponent("history.json"),
                             atomically: true, encoding: .utf8)
        XCTAssertEqual(store.load(), [])
    }

    func test_merge_scan_wins_inside_window_stored_survives_outside() {
        let stored = [day("2026-06-01", input: 99),   // aged out of logs — must survive
                      day("2026-07-01", input: 5)]    // still in logs — scan must win
        let scanned = [day("2026-07-01", input: 7), day("2026-07-07", input: 1)]
        let merged = HistoryStore.merge(stored: stored, scanned: scanned,
                                        oldestKey: "2026-05-07", todayKey: "2026-07-07")
        XCTAssertEqual(merged.map(\.day), ["2026-06-01", "2026-07-01", "2026-07-07"])
        XCTAssertEqual(merged[1].models[.claudeCode]?["opus"]?.input, 7)
        XCTAssertEqual(merged[0].models[.claudeCode]?["opus"]?.input, 99)
    }

    func test_merge_drops_days_beyond_retention_and_future_days() {
        let stored = [day("2026-04-01", input: 1)]                    // older than oldestKey
        let scanned = [day("2026-07-08", input: 1), day("2026-07-07", input: 2)]  // 07-08 = future
        let merged = HistoryStore.merge(stored: stored, scanned: scanned,
                                        oldestKey: "2026-05-07", todayKey: "2026-07-07")
        XCTAssertEqual(merged.map(\.day), ["2026-07-07"])
    }

    func test_save_writes_nothing_outside_its_directory_and_skips_unchanged() throws {
        let root = tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("store")
        let store = HistoryStore(directory: dir)
        store.save([day("2026-07-01", input: 1)])
        let file = dir.appendingPathComponent("history.json")
        let mtime1 = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        // Only history.json exists, only inside `dir`.
        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(contents, ["history.json"])
        // Saving identical content must not rewrite the file (stable mtime).
        Thread.sleep(forTimeInterval: 0.05)
        store.save([day("2026-07-01", input: 1)])
        let mtime2 = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        XCTAssertEqual(mtime1, mtime2)
    }
}
