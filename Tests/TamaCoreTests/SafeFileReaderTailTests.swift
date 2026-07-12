import XCTest
@testable import TamaCore

final class SafeFileReaderTailTests: XCTestCase {
    private func tmp(_ name: String = "tail-\(UUID().uuidString)") -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    func test_tail_returns_only_last_bytes() throws {
        let url = tmp()
        try "ABCDEFGHIJ".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = SafeFileReader.tail(at: url, maxBytes: 3)
        XCTAssertEqual(data.map { String(decoding: $0, as: UTF8.self) }, "HIJ")
    }

    func test_tail_returns_whole_file_when_smaller_than_window() throws {
        let url = tmp()
        try "hi".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(SafeFileReader.tail(at: url, maxBytes: 4096).map { String(decoding: $0, as: UTF8.self) }, "hi")
    }

    func test_tail_rejects_symlink() throws {
        let fm = FileManager.default
        let real = tmp(); let link = tmp()
        try "data".write(to: real, atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(at: link, withDestinationURL: real)
        defer { try? fm.removeItem(at: real); try? fm.removeItem(at: link) }
        XCTAssertNil(SafeFileReader.tail(at: link, maxBytes: 4096))
    }

    func test_tail_missing_file_is_nil() {
        XCTAssertNil(SafeFileReader.tail(at: tmp("does-not-exist"), maxBytes: 4096))
    }
}
