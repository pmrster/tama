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
