import XCTest
import TamaCore

final class QuotaFormatTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func test_reset_countdown_uses_the_two_largest_units() {
        XCTAssertEqual(QuotaFormat.countdown(to: t0.addingTimeInterval(5 * 86400 + 3 * 3600 + 900), from: t0), "5d 3h")
        XCTAssertEqual(QuotaFormat.countdown(to: t0.addingTimeInterval(2 * 3600 + 10 * 60), from: t0), "2h 10m")
        XCTAssertEqual(QuotaFormat.countdown(to: t0.addingTimeInterval(45), from: t0), "<1m")
        XCTAssertEqual(QuotaFormat.countdown(to: t0.addingTimeInterval(-5), from: t0), "now")
        XCTAssertEqual(QuotaFormat.countdown(to: t0.addingTimeInterval(86400), from: t0), "1d")
    }

    func test_staleness_hint_only_appears_past_fifteen_minutes() {
        XCTAssertNil(QuotaFormat.staleness(fetchedAt: t0.addingTimeInterval(-600), now: t0))
        XCTAssertEqual(QuotaFormat.staleness(fetchedAt: t0.addingTimeInterval(-40 * 60), now: t0), "as of 40m ago")
        XCTAssertEqual(QuotaFormat.staleness(fetchedAt: t0.addingTimeInterval(-28 * 3600), now: t0), "as of 1d 4h ago")
        XCTAssertEqual(QuotaFormat.staleness(fetchedAt: .distantPast, now: t0), "as of unknown time")
    }

    func test_account_display_name_prefers_identity_then_label_then_plan() {
        func q(label: String?, identity: String?, plan: String?) -> AccountQuota {
            AccountQuota(provider: .claudeCode, label: label, accountKey: "k", identity: identity, plan: plan,
                         windows: [], fetchedAt: t0, source: .claudeConfigCache)
        }
        XCTAssertEqual(QuotaFormat.title(q(label: "work", identity: "dev@example.com", plan: "Max 5x")), "work · dev@example.com · Max 5x")
        XCTAssertEqual(QuotaFormat.title(q(label: nil, identity: "dev@example.com", plan: nil)), "dev@example.com")
        XCTAssertEqual(QuotaFormat.title(q(label: nil, identity: nil, plan: "Plus")), "Plus")
        XCTAssertEqual(QuotaFormat.title(q(label: nil, identity: nil, plan: nil)), "default")
    }

    func test_compact_title_keeps_only_the_local_part_of_an_email() {
        let q = AccountQuota(provider: .claudeCode, label: "work", accountKey: "k", identity: "dev.ops@example.com",
                             plan: "Max 5x", windows: [], fetchedAt: t0, source: .claudeConfigCache)
        XCTAssertEqual(QuotaFormat.title(q, compact: true), "work · dev.ops · Max 5x")
        let noEmail = AccountQuota(provider: .codex, label: nil, accountKey: "k", identity: nil,
                                   plan: "Plus", windows: [], fetchedAt: t0, source: .codexLog)
        XCTAssertEqual(QuotaFormat.title(noEmail, compact: true), "Plus")
    }

    func test_percent_label_drops_needless_decimals() {
        XCTAssertEqual(QuotaFormat.percent(46), "46%")
        XCTAssertEqual(QuotaFormat.percent(12.5), "12.5%")
        XCTAssertEqual(QuotaFormat.percent(2.04), "2%")
        XCTAssertEqual(QuotaFormat.percent(100), "100%")
    }
}
