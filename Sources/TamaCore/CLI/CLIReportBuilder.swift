import Foundation

/// Builds a CLIReport from an AppState. Pure: pricing and active-classification are injected as
/// closures (AgentMonitor supplies them at the call site) so this stays unit-testable.
public enum CLIReportBuilder {
    public static func build(state: AppState,
                             cost: (SessionInfo) -> Double,
                             isActive: (SessionInfo) -> Bool,
                             now: Date) -> CLIReport {
        let projects = folderGroups(state.activeSessions).map { group in
            CLIReport.ProjectReport(
                project: group.project,
                folder: group.folder,
                sessions: group.sessions.map { s in
                    CLIReport.SessionReport(
                        provider: s.provider.rawValue,
                        name: s.displayName,
                        model: s.model,
                        active: isActive(s),
                        tokens: s.provider.hasUsageData ? s.tokens : nil,
                        contextFraction: s.contextFraction,
                        cost: cost(s))
                })
        }
        let providers = Provider.allCases.map { p -> CLIReport.ProviderTotal in
            let usage = state.usage[p] ?? .empty
            let activeCount = state.activeSessions.filter { $0.provider == p && isActive($0) }.count
            return CLIReport.ProviderTotal(provider: p.rawValue,
                                           todayTokens: usage.todayTokens,
                                           todayCost: usage.todayCost,
                                           activeCount: activeCount)
        }
        return CLIReport(timestamp: now, providers: providers, projects: projects)
    }
}
