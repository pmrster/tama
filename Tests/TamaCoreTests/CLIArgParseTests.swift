import XCTest
@testable import TamaCore

final class CLIArgParseTests: XCTestCase {
    private func ok(_ args: [String]) -> CLIOptions {
        switch CLIOptions.parse(args) {
        case .success(let o): return o
        case .failure(let e): XCTFail("unexpected failure \(e)"); return CLIOptions()
        }
    }

    func test_defaults_when_no_args() {
        let o = ok([])
        XCTAssertEqual(o, CLIOptions())
        XCTAssertEqual(o.interval, 7)
        XCTAssertFalse(o.watch)
    }

    func test_watch_flags() {
        XCTAssertTrue(ok(["-w"]).watch)
        XCTAssertTrue(ok(["--watch"]).watch)
    }

    func test_json_and_no_color_and_version_and_help() {
        XCTAssertTrue(ok(["--json"]).json)
        XCTAssertTrue(ok(["--no-color"]).noColor)
        XCTAssertTrue(ok(["--version"]).version)
        XCTAssertTrue(ok(["-h"]).help)
        XCTAssertTrue(ok(["--help"]).help)
    }

    func test_interval_value_and_clamp() {
        XCTAssertEqual(ok(["-n", "10"]).interval, 10)
        XCTAssertEqual(ok(["--interval", "0.5"]).interval, 1)  // clamped to min 1
    }

    func test_combined_flags() {
        let o = ok(["-w", "--json", "-n", "3"])
        XCTAssertTrue(o.watch); XCTAssertTrue(o.json); XCTAssertEqual(o.interval, 3)
    }

    func test_unknown_flag_fails() {
        XCTAssertEqual(CLIOptions.parse(["--bogus"]), .failure(.unknownFlag("--bogus")))
    }

    func test_interval_missing_value_fails() {
        XCTAssertEqual(CLIOptions.parse(["--interval"]), .failure(.missingValue("--interval")))
    }

    func test_interval_non_numeric_fails() {
        XCTAssertEqual(CLIOptions.parse(["-n", "abc"]), .failure(.invalidInterval("abc")))
    }
}
