import Foundation

public struct ClaudeReader {
    private let projectsDir: URL
    private let now: () -> Date
    private let calendar: Calendar

    public init(projectsDir: URL, now: @escaping () -> Date, calendar: Calendar = .current) {
        self.projectsDir = projectsDir; self.now = now; self.calendar = calendar
    }

    public init(now: @escaping () -> Date, calendar: Calendar = .current) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.init(projectsDir: home.appendingPathComponent(".claude/projects"),
                  now: now, calendar: calendar)
    }

    /// Today's token usage keyed by project name (last path component of `cwd`, else dir name).
    public func read() -> [String: TokenBreakdown] {
        let today = now()
        var result: [String: TokenBreakdown] = [:]
        let fm = FileManager.default
        let directoryKeys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        let fileKeys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let dirs = try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: directoryKeys) else {
            return result
        }
        for projDir in dirs {
            guard SafeFileReader.isSafeDirectory(projDir) else { continue }
            guard let files = try? fm.contentsOfDirectory(at: projDir, includingPropertiesForKeys: fileKeys) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                if let mod = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   !calendar.isDate(mod, inSameDayAs: today) { continue }  // fast skip of old files
                accumulate(file: file, today: today, into: &result)
            }
        }
        return result
    }

    private func accumulate(file: URL, today: Date, into result: inout [String: TokenBreakdown]) {
        SafeFileReader.forEachLineData(at: file) { line in
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let ts = obj["timestamp"] as? String,
                  let date = ISO8601DateFormatter.shared.date(from: ts),
                  calendar.isDate(date, inSameDayAs: today),
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { return }
            let project = (obj["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
                ?? file.deletingPathExtension().lastPathComponent
            let bd = TokenBreakdown(
                input: usage["input_tokens"] as? Int ?? 0,
                output: usage["output_tokens"] as? Int ?? 0,
                cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0,
                cacheWrite: usage["cache_creation_input_tokens"] as? Int ?? 0
            )
            result[project, default: TokenBreakdown()] = result[project, default: TokenBreakdown()] + bd
        }
    }
}

extension ISO8601DateFormatter {
    // nonisolated(unsafe): formatter is read-only after init; safe across concurrency domains.
    public nonisolated(unsafe) static let shared: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
