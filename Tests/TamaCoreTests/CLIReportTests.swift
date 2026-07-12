import XCTest
@testable import TamaCore

final class CLIReportTests: XCTestCase {
    private func sample() -> CLIReport {
        CLIReport(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            providers: [CLIReport.ProviderTotal(provider: "claudeCode", todayTokens: 1000, todayCost: 1.5, activeCount: 1)],
            projects: [CLIReport.ProjectReport(project: "tama", folder: "/a/tama", sessions: [
                CLIReport.SessionReport(provider: "claudeCode", name: "main", model: "opus",
                                        active: true, tokens: 1000, contextFraction: 0.4, cost: 1.5)
            ])]
        )
    }

    func test_jsonString_is_decodable_round_trip() throws {
        let report = sample()
        let data = Data(report.jsonString().utf8)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(CLIReport.self, from: data)
        XCTAssertEqual(back, report)
    }

    func test_jsonString_has_stable_top_level_keys() {
        let json = sample().jsonString()
        XCTAssertTrue(json.contains("\"timestamp\""))
        XCTAssertTrue(json.contains("\"providers\""))
        XCTAssertTrue(json.contains("\"projects\""))
    }

    func test_jsonLine_is_single_line() {
        let line = sample().jsonLine()
        XCTAssertFalse(line.contains("\n"))
        XCTAssertTrue(line.contains("\"timestamp\""))
    }

    func test_missing_token_fields_encode_as_null() {
        let r = CLIReport(timestamp: Date(timeIntervalSince1970: 0), providers: [],
            projects: [CLIReport.ProjectReport(project: "g", folder: "/g", sessions: [
                CLIReport.SessionReport(provider: "gemini", name: "x", model: nil,
                                        active: false, tokens: nil, contextFraction: nil, cost: 0)
            ])])
        XCTAssertTrue(r.jsonString().contains("\"tokens\" : null"))
    }
}
