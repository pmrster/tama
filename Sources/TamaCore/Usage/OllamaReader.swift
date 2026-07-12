import Foundation

/// Supplies Ollama enrichment from the log. A protocol so the monitor can be tested with a stub.
public protocol OllamaReading: Sendable {
    func read() -> OllamaStatus?
}

/// Reads per-model activity for a local Ollama server from its llama.cpp `server.log`.
///
/// Read-only and local-only by construction: it never opens the Ollama HTTP API
/// (`http://localhost:11434/...`) — doing so would break Tama's no-network invariant — and never
/// reads `~/.ollama/history` (plaintext user prompts). Only `server.log` is parsed, via
/// `SafeFileReader`. Presence (`running`) is filled in by the caller from the process table.
///
/// The log carries no per-line model tag, so activity is attributed by **segmenting** the log
/// between `starting`/`stopping mlx runner subprocess` events: every request/timing line belongs to
/// the model whose runner is currently loaded. Exact for serial use (one model at a time); if models
/// run concurrently the untagged lines interleave and per-model metrics become approximate.
public struct OllamaReader: OllamaReading {
    private let logURL: URL
    private let calendar: Calendar

    /// Default macOS location of the Ollama server log.
    public static func defaultLogURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ollama/logs/server.log")
    }

    /// `calendar` (its time zone) parses the `[GIN]` request timestamps, which carry no zone of
    /// their own. Defaults to the current calendar; tests inject a fixed zone for determinism.
    public init(logURL: URL = OllamaReader.defaultLogURL(), calendar: Calendar = .current) {
        self.logURL = logURL
        self.calendar = calendar
    }

    /// Only the tail of the log is inspected: it can grow to many MB and the live state is at the end.
    private static let tailBytes = 256 * 1024

    public func read() -> OllamaStatus? {
        guard let data = SafeFileReader.tail(at: logURL, maxBytes: Self.tailBytes), !data.isEmpty else {
            return nil
        }
        let text = String(decoding: data, as: UTF8.self)
        let formatter = ginFormatter()

        var segments: [String: Segment] = [:]   // keyed by model tag (dedupes across reloads)
        var order: [String] = []                // first-seen order
        var active: String?                      // model owning the lines being read
        var current: String?                     // model whose runner is still loaded

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if let tag = startedModel(line) {
                active = tag; current = tag
                if segments[tag] == nil { segments[tag] = Segment(); order.append(tag) }
                continue
            }
            if line.contains("stopping mlx runner subprocess") {
                active = nil; current = nil
                continue
            }
            guard let tag = active, var seg = segments[tag] else { continue }
            apply(line, to: &seg, formatter: formatter)
            segments[tag] = seg
        }

        var status = OllamaStatus()
        status.lastActivity = modificationDate()
        status.models = order.map { tag in
            let s = segments[tag]!
            return OllamaModelActivity(model: tag, current: tag == current, busy: s.busy,
                                       lastActivity: s.lastActivity, contextWindow: s.contextWindow,
                                       contextTokens: s.contextTokens, tokensPerSecond: s.tokensPerSecond,
                                       lastLatency: s.lastLatency, kind: s.kind, requestCount: s.requestCount)
        }
        .sorted { a, b in
            if a.current != b.current { return a.current }   // currently-loaded model first
            return (a.lastActivity ?? .distantPast) > (b.lastActivity ?? .distantPast)
        }
        return status
    }

    // MARK: - Per-model accumulator

    private struct Segment {
        var busy = false
        var lastActivity: Date?
        var contextWindow: Int?
        var contextTokens: Int?
        var tokensPerSecond: Double?
        var lastLatency: TimeInterval?
        var requestCount = 0
        var chatCount = 0
        var embedCount = 0
        var kind: OllamaRequestKind {
            if embedCount > chatCount { return .embed }
            return chatCount > 0 ? .chat : .unknown
        }
    }

    private func apply(_ line: Substring, to seg: inout Segment, formatter: DateFormatter) {
        if let w = intAfter("n_ctx_slot = ", in: line) { seg.contextWindow = w }
        if let t = intAfter("task.n_tokens = ", in: line) { seg.contextTokens = t }
        if let tps = doubleAfter("tg = ", in: line) { seg.tokensPerSecond = tps }
        if line.contains("all slots are idle") { seg.busy = false }
        if line.contains("processing task") { seg.busy = true }
        if line.hasPrefix("[GIN]") { applyGIN(line, to: &seg, formatter: formatter) }
    }

    private func applyGIN(_ line: Substring, to seg: inout Segment, formatter: DateFormatter) {
        guard let endpoint = ginEndpoint(line) else { return }
        let kind: OllamaRequestKind
        if endpoint.contains("/embed") { kind = .embed }
        else if endpoint.hasSuffix("/api/chat") || endpoint.hasSuffix("/api/generate") { kind = .chat }
        else { return }   // /api/tags, /show, /ps, /version, /pull, /delete — not inference
        seg.requestCount += 1
        if kind == .embed { seg.embedCount += 1 } else { seg.chatCount += 1 }
        let fields = line.split(separator: "|", omittingEmptySubsequences: false)
        if fields.count > 2, let dur = parseDuration(fields[2].trimmingCharacters(in: .whitespaces)) {
            seg.lastLatency = dur
        }
        if let first = fields.first {
            let stamp = first.replacingOccurrences(of: "[GIN]", with: "").trimmingCharacters(in: .whitespaces)
            if let date = formatter.date(from: stamp) { seg.lastActivity = date }
        }
    }

    // MARK: - Line parsing helpers

    /// `model=<tag>` on a runner-subprocess *start* line (ignores `pulling manifest model=…` noise).
    private func startedModel(_ line: Substring) -> String? {
        guard line.contains("runner subprocess"), line.contains("starting"),
              let r = line.range(of: "model=") else { return nil }
        let tag = line[r.upperBound...].prefix { !$0.isWhitespace }
        return tag.isEmpty ? nil : String(tag)
    }

    private func intAfter(_ needle: String, in line: Substring) -> Int? {
        guard let r = line.range(of: needle) else { return nil }
        return Int(line[r.upperBound...].prefix { $0.isNumber })
    }

    private func doubleAfter(_ needle: String, in line: Substring) -> Double? {
        guard let r = line.range(of: needle) else { return nil }
        let rest = line[r.upperBound...].drop { $0 == " " }
        return Double(rest.prefix { $0.isNumber || $0 == "." })
    }

    /// The quoted route on a `[GIN]` line, e.g. `/api/chat`.
    private func ginEndpoint(_ line: Substring) -> String? {
        guard let close = line.lastIndex(of: "\"") else { return nil }
        let before = line[..<close]
        guard let open = before.lastIndex(of: "\"") else { return nil }
        return String(line[line.index(after: open)..<close])
    }

    /// llama.cpp's Go-duration strings: `5.0s`, `200ms`, `23.917µs`, `41ns`.
    private func parseDuration(_ s: String) -> TimeInterval? {
        func value(_ drop: Int, _ scale: Double) -> TimeInterval? { Double(s.dropLast(drop)).map { $0 * scale } }
        if s.hasSuffix("ms") { return value(2, 1e-3) }
        if s.hasSuffix("µs") || s.hasSuffix("us") { return value(2, 1e-6) }
        if s.hasSuffix("ns") { return value(2, 1e-9) }
        if s.hasSuffix("s") { return value(1, 1) }
        return nil
    }

    private func ginFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy/MM/dd - HH:mm:ss"
        return f
    }

    private func modificationDate() -> Date? {
        (try? logURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
