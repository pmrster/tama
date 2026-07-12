import XCTest
import TamaCore

final class OllamaStatusTests: XCTestCase {
    func test_active_within_window() {
        let now = Date(timeIntervalSince1970: 1000)
        let m = OllamaModelActivity(model: "x", lastActivity: Date(timeIntervalSince1970: 900))  // 100s ago
        XCTAssertTrue(m.active(now: now, within: 900))
    }

    func test_inactive_past_window() {
        let now = Date(timeIntervalSince1970: 2000)
        let m = OllamaModelActivity(model: "x", lastActivity: Date(timeIntervalSince1970: 900))  // 1100s ago
        XCTAssertFalse(m.active(now: now, within: 900))
    }

    func test_inactive_when_no_activity() {
        XCTAssertFalse(OllamaModelActivity(model: "x").active(now: Date(timeIntervalSince1970: 1000), within: 900))
    }

    func test_context_fraction_halfway() {
        let m = OllamaModelActivity(model: "x", contextWindow: 32768, contextTokens: 16384)
        XCTAssertEqual(m.contextFraction!, 0.5, accuracy: 0.001)
    }

    func test_context_fraction_clamped_to_one() {
        let m = OllamaModelActivity(model: "x", contextWindow: 100, contextTokens: 250)
        XCTAssertEqual(m.contextFraction!, 1.0, accuracy: 0.001)
    }

    func test_context_fraction_nil_without_tokens() {
        XCTAssertNil(OllamaModelActivity(model: "x", contextWindow: 32768).contextFraction)
    }

    func test_current_model_prefers_flagged_else_first() {
        let s = OllamaStatus(models: [
            OllamaModelActivity(model: "a"),
            OllamaModelActivity(model: "b", current: true),
        ])
        XCTAssertEqual(s.currentModel?.model, "b")
        XCTAssertEqual(OllamaStatus(models: [OllamaModelActivity(model: "a")]).currentModel?.model, "a")
    }

    func test_status_busy_when_any_model_busy() {
        let s = OllamaStatus(models: [OllamaModelActivity(model: "a"),
                                      OllamaModelActivity(model: "b", busy: true)])
        XCTAssertTrue(s.busy)
        XCTAssertFalse(OllamaStatus(models: [OllamaModelActivity(model: "a")]).busy)
    }
}
