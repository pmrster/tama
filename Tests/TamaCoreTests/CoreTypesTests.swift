import XCTest
import TamaCore

final class CoreTypesTests: XCTestCase {
    func test_tokenBreakdown_total_and_addition() {
        let a = TokenBreakdown(input: 10, output: 5, cacheRead: 3, cacheWrite: 2)
        XCTAssertEqual(a.total, 20)
        let b = TokenBreakdown(input: 1, output: 1, cacheRead: 1, cacheWrite: 1)
        let sum = a + b
        XCTAssertEqual(sum.total, 24)
        XCTAssertEqual(sum.input, 11)
    }

    func test_sessionInfo_contextFraction() {
        func s(ctx: Int, window: Int) -> SessionInfo {
            SessionInfo(provider: .claudeCode, project: "p", folder: "/p", lastActivity: .distantPast,
                        tokens: 999_999, contextTokens: ctx, contextWindow: window)
        }
        XCTAssertEqual(s(ctx: 50_000, window: 200_000).contextFraction, 0.25)
        XCTAssertEqual(s(ctx: 250_000, window: 200_000).contextFraction, 1.0)   // clamped to 1
        XCTAssertNil(s(ctx: 0, window: 200_000).contextFraction)                 // unknown occupancy
        XCTAssertNil(s(ctx: 5_000, window: 0).contextFraction)                   // unknown window
    }

    func test_sessionInfo_cost_uses_breakdown_and_provider_rates() {
        let est = CostEstimator(rates: [.claudeCode: Rates(input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75)])
        let s = SessionInfo(provider: .claudeCode, project: "p", folder: "/p", lastActivity: .distantPast,
                            breakdown: TokenBreakdown(input: 1_000_000, output: 1_000_000))
        // 1M input × $3 + 1M output × $15 = $18.00
        XCTAssertEqual(s.cost(using: est), 18.0, accuracy: 0.0001)
    }

    func test_agentSession_construction() {
        let s = AgentSession(pid: 42, provider: .claudeCode, location: .terminal, cwd: "/tmp")
        XCTAssertEqual(s.id, 42)
        XCTAssertEqual(s.provider.shortName, "CC")
        XCTAssertEqual(Provider.codex.shortName, "CX")
    }
}
