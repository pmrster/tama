import XCTest
@testable import TamaCore

final class SettingsStoreTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let suite = "tama.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    func test_defaults_when_empty() {
        let store = SettingsStore(defaults: freshDefaults())
        XCTAssertEqual(store.appearance, .system)
        XCTAssertEqual(store.fontSize, .small)
    }

    func test_appearance_round_trip() {
        let store = SettingsStore(defaults: freshDefaults())
        store.appearance = .dark
        XCTAssertEqual(store.appearance, .dark)
        store.appearance = .light
        XCTAssertEqual(store.appearance, .light)
    }

    func test_fontSize_round_trip() {
        let store = SettingsStore(defaults: freshDefaults())
        store.fontSize = .large
        XCTAssertEqual(store.fontSize, .large)
    }

    func test_show_limits_defaults_on_and_round_trips() {
        let store = SettingsStore(defaults: freshDefaults())
        XCTAssertTrue(store.showLimits, "the plan-limits section is shown by default")
        store.showLimits = false
        XCTAssertFalse(store.showLimits)
    }

    func test_limits_collapsed_defaults_off_and_round_trips() {
        let store = SettingsStore(defaults: freshDefaults())
        XCTAssertFalse(store.limitsCollapsed, "expanded by default")
        store.limitsCollapsed = true
        XCTAssertTrue(store.limitsCollapsed)
    }

    func test_unknown_raw_string_falls_back_to_default() {
        let d = freshDefaults()
        d.set("nonsense", forKey: "tama.appearance")
        d.set("huge", forKey: "tama.fontSize")
        let store = SettingsStore(defaults: d)
        XCTAssertEqual(store.appearance, .system)
        XCTAssertEqual(store.fontSize, .small)
    }

    func test_fontSize_factors() {
        XCTAssertEqual(FontSize.small.factor, 1.0)
        XCTAssertEqual(FontSize.medium.factor, 1.15)
        XCTAssertEqual(FontSize.large.factor, 1.3)
    }

    func test_notification_toggles_default_off_and_persist() {
        let store = SettingsStore(defaults: freshDefaults())
        XCTAssertFalse(store.notifyAgentQuiet)
        XCTAssertFalse(store.notifyContextHigh)
        store.notifyAgentQuiet = true
        store.notifyContextHigh = true
        XCTAssertTrue(store.notifyAgentQuiet)
        XCTAssertTrue(store.notifyContextHigh)
    }
}

final class SettingsStoreAccountsTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let suite = "tama.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    func test_extra_accounts_round_trip_and_keep_order() {
        let store = SettingsStore(defaults: freshDefaults())
        XCTAssertEqual(store.extraAccounts, [])
        let work = AccountRoot(provider: .claudeCode, label: "work", root: URL(fileURLWithPath: "/Users/x/.claude-work"))
        let cx = AccountRoot(provider: .codex, label: "B", root: URL(fileURLWithPath: "/Users/x/codex-b"))
        store.extraAccounts = [work, cx]
        XCTAssertEqual(store.extraAccounts, [work, cx])
        XCTAssertEqual(store.extraAccounts[0].configFile, URL(fileURLWithPath: "/Users/x/.claude-work/.claude.json"),
                       "an extra Claude root keeps its .claude.json INSIDE the dir (CLAUDE_CONFIG_DIR semantics)")
    }

    func test_corrupt_stored_accounts_fall_back_to_none() {
        let d = freshDefaults()
        d.set("not json", forKey: "tama.extraAccounts")
        XCTAssertEqual(SettingsStore(defaults: d).extraAccounts, [])
    }

    func test_account_roots_are_defaults_plus_extras() {
        let store = SettingsStore(defaults: freshDefaults())
        let home = URL(fileURLWithPath: "/Users/x")
        let work = AccountRoot(provider: .claudeCode, label: "work", root: URL(fileURLWithPath: "/Users/x/.claude-work"))
        store.extraAccounts = [work]
        let roots = store.accountRoots(home: home)
        XCTAssertEqual(roots.count, 3)
        XCTAssertEqual(roots[0], AccountRoot(provider: .claudeCode, label: nil, root: home.appendingPathComponent(".claude"),
                                             configFile: home.appendingPathComponent(".claude.json")))
        XCTAssertEqual(roots[1], AccountRoot(provider: .codex, label: nil, root: home.appendingPathComponent(".codex")))
        XCTAssertEqual(roots[2], work)
    }
}
