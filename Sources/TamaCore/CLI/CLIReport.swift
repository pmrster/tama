// Sources/TamaCore/CLI/CLIReport.swift
import Foundation

/// A serializable snapshot of the dashboard, rendered to either a human table or JSON.
public struct CLIReport: Codable, Equatable, Sendable {
    public struct ProviderTotal: Codable, Equatable, Sendable {
        public let provider: String
        public let todayTokens: Int
        public let todayCost: Double
        public let activeCount: Int
        public init(provider: String, todayTokens: Int, todayCost: Double, activeCount: Int) {
            self.provider = provider; self.todayTokens = todayTokens
            self.todayCost = todayCost; self.activeCount = activeCount
        }
    }

    public struct SessionReport: Codable, Equatable, Sendable {
        public let provider: String
        public let name: String
        public let model: String?
        public let active: Bool
        public let tokens: Int?            // nil for providers without token data (Gemini/Antigravity)
        public let contextFraction: Double?
        public let cost: Double
        public init(provider: String, name: String, model: String?, active: Bool,
                    tokens: Int?, contextFraction: Double?, cost: Double) {
            self.provider = provider; self.name = name; self.model = model; self.active = active
            self.tokens = tokens; self.contextFraction = contextFraction; self.cost = cost
        }

        enum CodingKeys: String, CodingKey {
            case provider, name, model, active, tokens, contextFraction, cost
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(provider, forKey: .provider)
            try container.encode(name, forKey: .name)
            try container.encode(model, forKey: .model)
            try container.encode(active, forKey: .active)
            try container.encode(tokens, forKey: .tokens)
            try container.encode(contextFraction, forKey: .contextFraction)
            try container.encode(cost, forKey: .cost)
        }
    }

    public struct ProjectReport: Codable, Equatable, Sendable {
        public let project: String
        public let folder: String
        public let sessions: [SessionReport]
        public init(project: String, folder: String, sessions: [SessionReport]) {
            self.project = project; self.folder = folder; self.sessions = sessions
        }
    }

    public let timestamp: Date
    public let providers: [ProviderTotal]
    public let projects: [ProjectReport]
    public init(timestamp: Date, providers: [ProviderTotal], projects: [ProjectReport]) {
        self.timestamp = timestamp; self.providers = providers; self.projects = projects
    }

    private func encode(pretty: Bool) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
                                      : [.sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(self), let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    /// Pretty multi-line JSON for one-shot `--json`.
    public func jsonString() -> String { encode(pretty: true) }
    /// Compact single-line JSON for NDJSON streaming under `--watch --json`.
    public func jsonLine() -> String { encode(pretty: false) }
}
