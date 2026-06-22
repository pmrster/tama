import Foundation

/// What a model's recent requests were for. Ollama is stateless, so this is inferred from the
/// request endpoints in the log, not from any stored session.
public enum OllamaRequestKind: String, Sendable, Equatable {
    case chat       // /api/chat or /api/generate — text generation
    case embed      // /api/embeddings or /api/embed
    case unknown
}

/// Activity attributed to one model in the current Ollama server session, built by segmenting
/// `server.log` between runner load/unload events. Metrics are exact for serial use (one model at
/// a time); if models run concurrently the untagged log lines interleave and metrics are approximate.
public struct OllamaModelActivity: Sendable, Equatable, Identifiable {
    public var model: String                  // tag, e.g. "gemma4:12b-mlx"
    public var current: Bool                  // most-recently-loaded model (best-effort "loaded now")
    public var busy: Bool                     // a request is being processed (only the current model)
    public var lastActivity: Date?            // last request/log time attributed to this model
    public var contextWindow: Int?            // n_ctx_slot
    public var contextTokens: Int?            // task.n_tokens (live occupancy)
    public var tokensPerSecond: Double?       // last print_timing throughput
    public var lastLatency: TimeInterval?     // last request's wall time (from [GIN])
    public var kind: OllamaRequestKind        // chat vs embed, inferred from endpoints
    public var requestCount: Int              // inference requests in this session

    public var id: String { model }

    public init(model: String, current: Bool = false, busy: Bool = false, lastActivity: Date? = nil,
                contextWindow: Int? = nil, contextTokens: Int? = nil, tokensPerSecond: Double? = nil,
                lastLatency: TimeInterval? = nil, kind: OllamaRequestKind = .unknown, requestCount: Int = 0) {
        self.model = model; self.current = current; self.busy = busy; self.lastActivity = lastActivity
        self.contextWindow = contextWindow; self.contextTokens = contextTokens
        self.tokensPerSecond = tokensPerSecond; self.lastLatency = lastLatency
        self.kind = kind; self.requestCount = requestCount
    }

    /// True when this model logged activity within `window` of `now`.
    public func active(now: Date, within window: TimeInterval) -> Bool {
        guard let last = lastActivity else { return false }
        return now.timeIntervalSince(last) < window
    }

    /// Context-window occupancy 0…1, or nil when either side is unknown.
    public var contextFraction: Double? {
        guard let window = contextWindow, window > 0, let tokens = contextTokens else { return nil }
        return min(1, max(0, Double(tokens) / Double(window)))
    }
}

/// Presence + per-model activity of a local Ollama inference server.
///
/// Ollama is *not* a coding-agent session (no project folder, no session id), so it is surfaced as
/// its own group — Ollama → each model — and is never priced (local inference is free). `running`
/// is filled in by the caller from the process table; the rest comes from a read-only parse of
/// `server.log`.
public struct OllamaStatus: Sendable, Equatable {
    public var running: Bool
    public var lastActivity: Date?            // log mtime — overall recency
    public var models: [OllamaModelActivity]  // most-recently-used first

    public init(running: Bool = false, lastActivity: Date? = nil, models: [OllamaModelActivity] = []) {
        self.running = running; self.lastActivity = lastActivity; self.models = models
    }

    /// The currently-loaded model (best effort), else the most recently used.
    public var currentModel: OllamaModelActivity? {
        models.first { $0.current } ?? models.first
    }

    /// True when any model is processing a request right now.
    public var busy: Bool { models.contains { $0.busy } }
}
