import XCTest
import TamaCore

final class BarLabelFormatterTests: XCTestCase {
    private func sess(_ provider: Provider) -> AgentSession {
        AgentSession(pid: Int32.random(in: 1...9999), provider: provider, location: .terminal, cwd: nil)
    }

    func test_label_counts_per_provider() {
        let sessions = [sess(.claudeCode), sess(.claudeCode), sess(.claudeCode),
                        sess(.codex), sess(.codex), sess(.codex), sess(.codex)]
        XCTAssertEqual(BarLabelFormatter.label(for: sessions), "CC 3 · CX 4")
    }

    func test_label_omits_zero_providers() {
        XCTAssertEqual(BarLabelFormatter.label(for: [sess(.codex)]), "CX 1")
    }

    func test_label_empty_is_dash() {
        XCTAssertEqual(BarLabelFormatter.label(for: []), "—")
    }
}
