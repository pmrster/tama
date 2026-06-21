import XCTest
import TamaCore

private struct MockSource: TokenSource {
    let data: [String: TokenBreakdown]
    func read() -> [String: TokenBreakdown] { data }
}

final class UsageReaderTests: XCTestCase {
    func test_aggregates_tokens_and_cost_per_provider() {
        let est = CostEstimator(rates: [
            .claudeCode: Rates(input: 3.0, output: 15.0, cacheRead: 0.3, cacheWrite: 3.75),
            .codex: Rates(input: 2.5, output: 10.0, cacheRead: 0.25, cacheWrite: 2.5),
        ])
        let claude = MockSource(data: ["projA": TokenBreakdown(input: 1_000_000, output: 0)])
        let codex = MockSource(data: ["sess1": TokenBreakdown(output: 1_000_000)])
        let reader = UsageReader(claude: claude, codex: codex, estimator: est)
        let stats = reader.read()

        XCTAssertEqual(stats[.claudeCode]?.todayTokens, 1_000_000)
        XCTAssertEqual(stats[.claudeCode]?.todayCost ?? 0, 3.0, accuracy: 0.0001)
        XCTAssertEqual(stats[.codex]?.todayTokens, 1_000_000)
        XCTAssertEqual(stats[.codex]?.todayCost ?? 0, 10.0, accuracy: 0.0001)
        XCTAssertEqual(stats[.claudeCode]?.byProject.first?.project, "projA")
    }
}
