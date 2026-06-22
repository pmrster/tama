import XCTest
@testable import TamaCore

final class CatStateStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CatStateStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func test_missing_file_loads_initial_state() {
        let store = CatStateStore(directory: dir)
        XCTAssertEqual(store.load(), .initial)
    }

    func test_save_then_load_round_trips() {
        let store = CatStateStore(directory: dir)
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        store.save(CatState(lastSeenDay: day))
        XCTAssertEqual(store.load(), CatState(lastSeenDay: day))
    }

    func test_malformed_json_loads_initial_state() throws {
        try "not json".data(using: .utf8)!.write(to: dir.appendingPathComponent("cat-state.json"))
        let store = CatStateStore(directory: dir)
        XCTAssertEqual(store.load(), .initial)
    }

    // Safety: the store must write nothing outside its injected directory.
    func test_save_writes_only_inside_injected_directory() throws {
        let store = CatStateStore(directory: dir)
        store.save(CatState(lastSeenDay: Date(timeIntervalSince1970: 1)))
        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(contents.sorted(), ["cat-state.json"])
    }

    func test_save_creates_directory_if_missing() {
        let nested = dir.appendingPathComponent("Tama", isDirectory: true)
        let store = CatStateStore(directory: nested)
        store.save(CatState(lastSeenDay: Date(timeIntervalSince1970: 2)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.appendingPathComponent("cat-state.json").path))
    }
}
