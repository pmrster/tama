import Foundation

public protocol TokenSource {
    func read() -> [String: TokenBreakdown]
}

extension ClaudeReader: TokenSource {}
extension CodexReader: TokenSource {}

public struct UsageReader {
    private let claude: TokenSource
    private let codex: TokenSource
    private let estimator: CostEstimator

    public init(claude: TokenSource, codex: TokenSource, estimator: CostEstimator) {
        self.claude = claude; self.codex = codex; self.estimator = estimator
    }

    public func read() -> [Provider: UsageStats] {
        [
            .claudeCode: stats(from: claude.read(), provider: .claudeCode),
            .codex: stats(from: codex.read(), provider: .codex),
        ]
    }

    private func stats(from raw: [String: TokenBreakdown], provider: Provider) -> UsageStats {
        var totalTokens = 0
        var totalCost = 0.0
        var projects: [ProjectUsage] = []
        for (name, bd) in raw {
            let cost = estimator.cost(bd, provider: provider)
            totalTokens += bd.total
            totalCost += cost
            projects.append(ProjectUsage(project: name, tokens: bd.total, cost: cost))
        }
        projects.sort { $0.tokens > $1.tokens }
        return UsageStats(todayTokens: totalTokens, todayCost: totalCost, byProject: projects)
    }
}
