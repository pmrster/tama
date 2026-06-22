import Foundation

/// Sessions for one project folder, ready for display. The core-side analogue of the UI's
/// private FolderGroup; named differently so the two never collide.
public struct ProjectGroup: Sendable, Equatable, Identifiable {
    public let project: String
    public let folder: String
    public let sessions: [SessionInfo]
    public var id: String { folder }
    public init(project: String, folder: String, sessions: [SessionInfo]) {
        self.project = project
        self.folder = folder
        self.sessions = sessions
    }
}

/// Group active sessions by their project folder. Sessions within a group are ordered
/// most-recent first; groups are ordered most-recent first, tie-broken by folder path so the
/// output is deterministic (Dictionary iteration order is not).
public func folderGroups(_ sessions: [SessionInfo]) -> [ProjectGroup] {
    Dictionary(grouping: sessions, by: { $0.folder }).map { folder, sess in
        ProjectGroup(project: sess.first?.project ?? folder,
                     folder: folder,
                     sessions: sess.sorted { $0.lastActivity > $1.lastActivity })
    }
    .sorted { lhs, rhs in
        let l = lhs.sessions.first?.lastActivity ?? .distantPast
        let r = rhs.sessions.first?.lastActivity ?? .distantPast
        if l != r { return l > r }
        return lhs.folder < rhs.folder
    }
}
