import XCTest
@testable import TamaCore

final class SessionGroupingTests: XCTestCase {
    private func s(_ folder: String, _ project: String, _ t: TimeInterval, provider: Provider = .claudeCode) -> SessionInfo {
        SessionInfo(provider: provider, project: project, folder: folder,
                    lastActivity: Date(timeIntervalSince1970: t))
    }

    func test_empty_input_yields_no_groups() {
        XCTAssertEqual(folderGroups([]).count, 0)
    }

    func test_groups_by_folder_and_carries_project_name() {
        let groups = folderGroups([s("/a/tama", "tama", 100), s("/a/tama", "tama", 200)])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].folder, "/a/tama")
        XCTAssertEqual(groups[0].project, "tama")
        XCTAssertEqual(groups[0].sessions.count, 2)
    }

    func test_sessions_within_group_sorted_recent_first() {
        let groups = folderGroups([s("/a/tama", "tama", 100), s("/a/tama", "tama", 300), s("/a/tama", "tama", 200)])
        XCTAssertEqual(groups[0].sessions.map { $0.lastActivity.timeIntervalSince1970 }, [300, 200, 100])
    }

    func test_groups_sorted_by_most_recent_activity_first() {
        let groups = folderGroups([s("/a/old", "old", 100), s("/a/new", "new", 500)])
        XCTAssertEqual(groups.map { $0.project }, ["new", "old"])
    }

    func test_equal_recency_breaks_tie_by_folder_for_determinism() {
        let groups = folderGroups([s("/a/zeta", "zeta", 100), s("/a/alpha", "alpha", 100)])
        XCTAssertEqual(groups.map { $0.folder }, ["/a/alpha", "/a/zeta"])
    }
}
