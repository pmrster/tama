import XCTest
@testable import TamaCore

final class CLIReportBuilderTests: XCTestCase {
    private func session(_ provider: Provider, _ folder: String, _ project: String,
                         tokens: Int = 0, t: TimeInterval = 100) -> SessionInfo {
        SessionInfo(provider: provider, project: project, folder: folder,
                    lastActivity: Date(timeIntervalSince1970: t), tokens: tokens,
                    contextTokens: 50, contextWindow: 100, model: "opus")
    }

    func test_groups_sessions_into_projects() {
        let state = AppState(sessions: [], usage: [:], lastUpdated: Date(timeIntervalSince1970: 100),
                             activeSessions: [session(.claudeCode, "/a/tama", "tama", tokens: 500)])
        let report = CLIReportBuilder.build(state: state, cost: { _ in 1.0 },
                                            isActive: { _ in true }, now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(report.projects.count, 1)
        XCTAssertEqual(report.projects[0].project, "tama")
        XCTAssertEqual(report.projects[0].sessions.first?.cost, 1.0)
        XCTAssertEqual(report.projects[0].sessions.first?.tokens, 500)
        XCTAssertEqual(report.projects[0].sessions.first?.contextFraction, 0.5)
    }

    func test_provider_totals_cover_all_providers_with_active_counts() {
        let state = AppState(sessions: [],
            usage: [.claudeCode: UsageStats(todayTokens: 1000, todayCost: 2.0, byProject: [])],
            lastUpdated: Date(timeIntervalSince1970: 100),
            activeSessions: [session(.claudeCode, "/a/tama", "tama")])
        let report = CLIReportBuilder.build(state: state, cost: { _ in 0 },
                                            isActive: { _ in true }, now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(report.providers.count, Provider.allCases.count)
        let cc = report.providers.first { $0.provider == "claudeCode" }
        XCTAssertEqual(cc?.todayTokens, 1000)
        XCTAssertEqual(cc?.todayCost, 2.0)
        XCTAssertEqual(cc?.activeCount, 1)
    }

    func test_gemini_sessions_have_nil_tokens() {
        let state = AppState(sessions: [], usage: [:], lastUpdated: Date(timeIntervalSince1970: 100),
                             activeSessions: [session(.gemini, "/a/g", "g", tokens: 0)])
        let report = CLIReportBuilder.build(state: state, cost: { _ in 0 },
                                            isActive: { _ in false }, now: Date(timeIntervalSince1970: 100))
        XCTAssertNil(report.projects[0].sessions[0].tokens)
    }

    func test_inactive_sessions_not_counted_active() {
        let state = AppState(sessions: [], usage: [:], lastUpdated: Date(timeIntervalSince1970: 100),
                             activeSessions: [session(.claudeCode, "/a/tama", "tama")])
        let report = CLIReportBuilder.build(state: state, cost: { _ in 0 },
                                            isActive: { _ in false }, now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(report.providers.first { $0.provider == "claudeCode" }?.activeCount, 0)
    }
}
