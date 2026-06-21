import Foundation

public struct CodexReader {
    private let sessionsDir: URL
    private let now: () -> Date
    private let calendar: Calendar

    public init(sessionsDir: URL, now: @escaping () -> Date, calendar: Calendar = .current) {
        self.sessionsDir = sessionsDir; self.now = now; self.calendar = calendar
    }

    public init(now: @escaping () -> Date, calendar: Calendar = .current) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.init(sessionsDir: home.appendingPathComponent(".codex/sessions"),
                  now: now, calendar: calendar)
    }

    /// Today's token usage keyed by short session id (parsed from the rollout filename).
    public func read() -> [String: TokenBreakdown] {
        var result: [String: TokenBreakdown] = [:]
        let comps = calendar.dateComponents([.year, .month, .day], from: now())
        guard let y = comps.year, let m = comps.month, let d = comps.day else { return result }
        let dayDir = sessionsDir
            .appendingPathComponent(String(format: "%04d", y))
            .appendingPathComponent(String(format: "%02d", m))
            .appendingPathComponent(String(format: "%02d", d))
        guard SafeFileReader.isSafeDirectory(dayDir) else { return result }
        let fileKeys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: dayDir, includingPropertiesForKeys: fileKeys) else {
            return result
        }
        for file in files where file.lastPathComponent.hasPrefix("rollout-") && file.pathExtension == "jsonl" {
            if let bd = lastUsage(in: file) {
                result[sessionId(from: file.lastPathComponent)] = bd
            }
        }
        return result
    }

    /// total_token_usage is cumulative; the last token_count event holds the session total.
    private func lastUsage(in file: URL) -> TokenBreakdown? {
        var latest: TokenBreakdown?
        SafeFileReader.forEachLineData(at: file) { line in
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any],
                  (payload["type"] as? String) == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let total = info["total_token_usage"] as? [String: Any] else { return }
            let input = total["input_tokens"] as? Int ?? 0
            let cached = total["cached_input_tokens"] as? Int ?? 0
            let output = total["output_tokens"] as? Int ?? 0
            // cached_input_tokens is the cached subset of input_tokens; split it out for cache pricing.
            latest = TokenBreakdown(input: max(0, input - cached), output: output, cacheRead: cached, cacheWrite: 0)
        }
        return latest
    }

    private func sessionId(from filename: String) -> String {
        let stem = filename.replacingOccurrences(of: ".jsonl", with: "")
        let parts = stem.split(separator: "-")
        // rollout-2026-06-19T09-17-34-019eddab-... -> parts[6] == "019eddab"
        return parts.count >= 7 ? String(parts[6].prefix(8)) : stem
    }
}
