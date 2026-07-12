import SwiftUI
import TamaCore

/// Collapsible Today / 7d / 30d usage summary: three stat tiles, and when expanded a
/// 30-day cost histogram plus per-model / per-provider / per-project tables for the
/// selected window. All figures derive from `state.history` (hybrid log-scan + store);
/// the TODAY tile uses the live per-poll totals so it always matches the TODAY bar.
struct UsageSection: View {
    @ObservedObject var monitor: AgentMonitor
    @ObservedObject private var ui = UIState.shared

    private var cal: Calendar { .current }
    private var todayKey: String { UsageHistory.dayKey(Date(), calendar: cal) }
    private var history: UsageHistory { UsageHistory(days: monitor.state.history) }

    private func key(daysAgo: Int) -> String {
        UsageHistory.dayKey(cal.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date(),
                            calendar: cal)
    }
    private func rollup(_ days: Int) -> DayUsage {
        history.rollup(from: key(daysAgo: days - 1), through: todayKey)
    }
    private func cost(_ d: DayUsage) -> Double {
        d.models.reduce(0) { acc, pm in
            acc + pm.value.reduce(0) {
                $0 + monitor.cost($1.value, provider: pm.key,
                                  model: $1.key.isEmpty ? nil : $1.key)
            }
        }
    }
    private var liveTodayTokens: Int { monitor.state.usage.values.reduce(0) { $0 + $1.todayTokens } }
    private var liveTodayCost: Double { monitor.state.usage.values.reduce(0) { $0 + $1.todayCost } }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                tile("TODAY", days: 1, cost: liveTodayCost, tokens: liveTodayTokens)
                tile("7D", days: 7, cost: cost(rollup(7)), tokens: rollup(7).totalTokens)
                tile("30D", days: 30, cost: cost(rollup(30)), tokens: rollup(30).totalTokens)
                Spacer()
                Button { ui.usageExpanded.toggle() } label: {
                    Image(systemName: ui.usageExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: scaled(8), weight: .bold))
                        .foregroundStyle(Palette.dim)
                        .frame(width: 16, height: 16).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(ui.usageExpanded ? "Collapse usage breakdown" : "Expand usage breakdown")
            }
            if ui.usageExpanded {
                histogram
                if monitor.state.hourlyActivity.contains(where: { $0 > 0 }) {
                    UsageHeatmap(grid: monitor.state.hourlyActivity)
                }
                cacheBar(rollup(ui.usageWindowDays))
                breakdownTables(rollup(ui.usageWindowDays))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .help(costCaveat)
    }

    /// One stat tile; tapping selects the window the expanded tables cover.
    private func tile(_ label: String, days: Int, cost: Double, tokens: Int) -> some View {
        let selected = ui.usageWindowDays == days
        return Button {
            ui.usageWindowDays = days
            if !ui.usageExpanded { ui.usageExpanded = true }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: scaled(8), weight: .heavy)).tracking(0.5)
                    .foregroundStyle(selected ? Palette.yellow : Palette.dim)
                Text(cost > 0 ? formatCost(cost) : "$0")
                    .font(.system(size: scaled(11), weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.text)
                Text("\(formatTokens(tokens)) tok")
                    .font(.system(size: scaled(8.5), design: .monospaced))
                    .foregroundStyle(Palette.dim)
            }
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5)
                .fill(selected ? Palette.dim.opacity(0.14) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 30 bars, one per day, height = that day's estimated cost; today highlighted.
    private var histogram: some View {
        let keys = (0..<30).reversed().map { key(daysAgo: $0) }
        let costs = keys.map { cost(history.rollup(from: $0, through: $0)) }
        let maxCost = max(costs.max() ?? 0, 0.000001)
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(zip(keys, costs)), id: \.0) { day, c in
                RoundedRectangle(cornerRadius: 1)
                    .fill(day == todayKey ? Palette.yellow : Palette.dim.opacity(0.4))
                    .frame(height: max(2, CGFloat(c / maxCost) * 36))
                    .frame(maxWidth: .infinity)
                    .help("\(day): \(c > 0 ? formatCost(c) : "$0")")
            }
        }
        .frame(height: 38)
    }

    /// Summed token breakdown across every provider/model in `d`.
    private func summedBreakdown(_ d: DayUsage) -> TokenBreakdown {
        d.models.values.flatMap { $0.values }.reduce(TokenBreakdown(), +)
    }

    /// Estimated cost of one composition segment, priced per provider/model then summed.
    private func segmentCost(_ d: DayUsage, _ part: TokenComposition.Part) -> Double {
        d.models.reduce(0.0) { acc, pm in
            acc + pm.value.reduce(0.0) { inner, mb in
                let m = mb.key.isEmpty ? nil : mb.key
                let seg: TokenBreakdown
                switch part {
                case .fresh:      seg = TokenBreakdown(input: mb.value.input, output: mb.value.output)
                case .cacheRead:  seg = TokenBreakdown(cacheRead: mb.value.cacheRead)
                case .cacheWrite: seg = TokenBreakdown(cacheWrite: mb.value.cacheWrite, cacheWrite1h: mb.value.cacheWrite1h)
                }
                return inner + monitor.cost(seg, provider: pm.key, model: m)
            }
        }
    }

    @ViewBuilder
    private func cacheBar(_ d: DayUsage) -> some View {
        let comp = TokenComposition(summedBreakdown(d))
        if comp.total > 0 {
            VStack(alignment: .leading, spacing: 3) {
                sectionLabel("TOKEN MIX")
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        cacheSegment("fresh", Palette.green, comp.fraction(of: .fresh),
                                     tokens: comp.fresh, cost: segmentCost(d, .fresh), width: geo.size.width)
                        cacheSegment("cache rd", Palette.dim.opacity(0.55), comp.fraction(of: .cacheRead),
                                     tokens: comp.cacheRead, cost: segmentCost(d, .cacheRead), width: geo.size.width)
                        cacheSegment("cache wr", Palette.yellow.opacity(0.8), comp.fraction(of: .cacheWrite),
                                     tokens: comp.cacheWrite, cost: segmentCost(d, .cacheWrite), width: geo.size.width)
                    }
                }
                .frame(height: 14)
                Text("cache re-reads dominate tokens but cost ~0.1× input — hover a segment")
                    .font(.system(size: scaled(7.5))).foregroundStyle(Palette.dim.opacity(0.7))
            }
        }
    }

    @ViewBuilder
    private func cacheSegment(_ label: String, _ color: Color, _ frac: Double,
                              tokens: Int, cost: Double, width: CGFloat) -> some View {
        if frac > 0 {
            let w = max(2, CGFloat(frac) * (width - 2))
            RoundedRectangle(cornerRadius: 2).fill(color)
                .frame(width: w)
                .overlay(alignment: .leading) {
                    if w > 34 {
                        Text("\(Int((frac * 100).rounded()))%")
                            .font(.system(size: scaled(7.5), weight: .semibold, design: .monospaced))
                            .foregroundStyle(Palette.panel).padding(.leading, 3)
                    }
                }
                .help("\(label): \(formatTokens(tokens)) tok · \(cost > 0 ? formatCost(cost) : "~$0")")
        }
    }

    @ViewBuilder
    private func breakdownTables(_ d: DayUsage) -> some View {
        // ForEach ids include the provider — the same model/project name can appear
        // under two providers, and duplicate ids break SwiftUI diffing.
        let models = d.models
            .flatMap { p, mm in mm.map { (id: "\(p.rawValue):\($0.key)", provider: p, model: $0.key, bd: $0.value) } }
            .map { (row: $0, cost: monitor.cost($0.bd, provider: $0.provider,
                                                model: $0.model.isEmpty ? nil : $0.model)) }
            .sorted { $0.cost > $1.cost }
        let providers = Provider.allCases.compactMap { p -> (Provider, TokenBreakdown, Double)? in
            guard let mm = d.models[p], !mm.isEmpty else { return nil }
            let bd = mm.values.reduce(TokenBreakdown(), +)
            let c = mm.reduce(0.0) { $0 + monitor.cost($1.value, provider: p,
                                                       model: $1.key.isEmpty ? nil : $1.key) }
            return (p, bd, c)
        }
        let projects = d.projects
            .flatMap { p, pp in pp.map { (id: "\(p.rawValue):\($0.key)", provider: p, name: $0.key, bd: $0.value) } }
            .map { (row: $0, cost: monitor.cost($0.bd, provider: $0.provider, model: nil)) }
            .sorted { $0.cost > $1.cost }

        VStack(alignment: .leading, spacing: 6) {
            if !models.isEmpty {
                sectionLabel("MODELS")
                ForEach(models.prefix(6), id: \.row.id) { m in
                    row(name: m.row.model.isEmpty ? "(unknown model)" : m.row.model,
                        tint: providerTint(m.row.provider),
                        tokens: m.row.bd.total, cost: m.cost)
                }
            }
            if !providers.isEmpty {
                sectionLabel("PROVIDERS")
                ForEach(providers, id: \.0) { p in
                    row(name: p.0.displayName, tint: providerTint(p.0),
                        tokens: p.1.total, cost: p.2)
                }
            }
            if !projects.isEmpty {
                sectionLabel("PROJECTS")
                ForEach(projects.prefix(5), id: \.row.id) { pr in
                    row(name: pr.row.name, tint: providerTint(pr.row.provider),
                        tokens: pr.row.bd.total, cost: pr.cost)
                }
                if projects.count > 5 {
                    Text("+ \(projects.count - 5) more")
                        .font(.system(size: scaled(8.5), design: .monospaced))
                        .foregroundStyle(Palette.dim.opacity(0.7))
                }
            }
            if models.isEmpty {
                Text("No usage recorded in this window.")
                    .font(.system(size: scaled(9.5))).foregroundStyle(Palette.dim)
            }
        }
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s).font(.system(size: scaled(7.5), weight: .heavy)).tracking(1)
            .foregroundStyle(Palette.dim.opacity(0.8)).padding(.top, 2)
    }

    private func row(name: String, tint: Color, tokens: Int, cost: Double) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 5, height: 5)
            Text(name).font(.system(size: scaled(9.5), design: .monospaced))
                .foregroundStyle(Palette.text).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Text(formatTokens(tokens))
                .font(.system(size: scaled(9.5), design: .monospaced)).foregroundStyle(Palette.dim)
            Text(cost > 0 ? formatCost(cost) : "")
                .font(.system(size: scaled(9.5), weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.text)
                .frame(minWidth: 52, alignment: .trailing)
        }
    }
}
