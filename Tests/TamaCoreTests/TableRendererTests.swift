import XCTest
@testable import TamaCore

final class TableRendererTests: XCTestCase {
    private func report() -> CLIReport {
        CLIReport(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            providers: [
                CLIReport.ProviderTotal(provider: "claudeCode", todayTokens: 1_234_567, todayCost: 4.56, activeCount: 1),
                CLIReport.ProviderTotal(provider: "gemini", todayTokens: 0, todayCost: 0, activeCount: 0),
            ],
            projects: [
                CLIReport.ProjectReport(project: "tama", folder: "/Users/x/tama", sessions: [
                    CLIReport.SessionReport(provider: "claudeCode", name: "main-work", model: "opus",
                                            active: true, tokens: 842_000, contextFraction: 0.41, cost: 3.10),
                    CLIReport.SessionReport(provider: "gemini", name: "gem-sess", model: nil,
                                            active: false, tokens: nil, contextFraction: nil, cost: 0),
                ]),
            ])
    }

    func test_renders_project_and_session_names() {
        let out = TableRenderer.render(report(), color: false)
        XCTAssertTrue(out.contains("tama"))
        XCTAssertTrue(out.contains("main-work"))
        XCTAssertTrue(out.contains("gem-sess"))
    }

    func test_renders_provider_totals() {
        let out = TableRenderer.render(report(), color: false)
        XCTAssertTrue(out.contains("Claude Code"))
        XCTAssertTrue(out.contains("1.23M"))
        XCTAssertTrue(out.contains("$4.56"))
    }

    func test_renders_active_marker_and_context() {
        let out = TableRenderer.render(report(), color: false)
        XCTAssertTrue(out.contains("●"))   // active session
        XCTAssertTrue(out.contains("○"))   // inactive session
        XCTAssertTrue(out.contains("41%"))
    }

    func test_no_data_provider_session_shows_dash() {
        let out = TableRenderer.render(report(), color: false)
        XCTAssertTrue(out.contains("—"))   // gemini session tokens/ctx
    }

    func test_empty_report_says_no_sessions() {
        let empty = CLIReport(timestamp: Date(timeIntervalSince1970: 0), providers: [], projects: [])
        XCTAssertTrue(TableRenderer.render(empty, color: false).contains("No active sessions"))
    }

    func test_color_false_emits_no_escape_codes() {
        XCTAssertFalse(TableRenderer.render(report(), color: false).contains("\u{1B}["))
    }
}
