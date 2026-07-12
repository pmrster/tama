import XCTest
@testable import TamaCore

final class UsageInsightsTests: XCTestCase {
    func test_token_composition_splits_fresh_cache_read_write() {
        let c = TokenComposition(TokenBreakdown(input: 3, output: 2, cacheRead: 90, cacheWrite: 5))
        XCTAssertEqual(c.fresh, 5)          // input + output
        XCTAssertEqual(c.cacheRead, 90)
        XCTAssertEqual(c.cacheWrite, 5)
        XCTAssertEqual(c.total, 100)
        XCTAssertEqual(c.fraction(of: .cacheRead), 0.90, accuracy: 1e-9)
        XCTAssertEqual(c.fraction(of: .fresh), 0.05, accuracy: 1e-9)
    }

    func test_token_composition_empty_has_zero_fractions_no_nan() {
        let c = TokenComposition(TokenBreakdown())
        XCTAssertEqual(c.total, 0)
        XCTAssertEqual(c.fraction(of: .fresh), 0)
        XCTAssertEqual(c.fraction(of: .cacheRead), 0)
        XCTAssertEqual(c.fraction(of: .cacheWrite), 0)
    }

    func test_usage_delta_up_down_flat_unavailable() {
        if case .up(let f) = UsageDelta.compare(current: 112, prior: 100) {
            XCTAssertEqual(f, 0.12, accuracy: 1e-9)
        } else { XCTFail("expected up") }
        if case .down(let f) = UsageDelta.compare(current: 92, prior: 100) {
            XCTAssertEqual(f, 0.08, accuracy: 1e-9)
        } else { XCTFail("expected down") }
        if case .flat = UsageDelta.compare(current: 100.2, prior: 100) {} else { XCTFail("expected flat (<0.5%)") }
        if case .unavailable = UsageDelta.compare(current: 50, prior: 0) {} else { XCTFail("prior 0 → unavailable") }
    }
}
