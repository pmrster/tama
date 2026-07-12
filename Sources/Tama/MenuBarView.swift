import SwiftUI
import ServiceManagement
import TamaCore

private extension Color {
    init(_ hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Bubbles the measured row-area width up to `DashboardView` so it can switch rows between the
/// horizontal and stacked (compact) layouts as the pinned window is resized.
private struct RowWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

enum Palette {
    static let panel     = Color(light: 0xF7F4EF, dark: 0x1C1A17)
    static let panelEdge = Color(light: 0xE0DAD0, dark: 0x2A2620)
    static let text      = Color(light: 0x1C1A17, dark: 0xEDE6DC)
    static let dim       = Color(light: 0x6E655C, dark: 0x9A8F84)
    static let yellow    = Color(0xF3BD4F)  // Tama accent (matches the sprite)
    static let coral     = Color(0xD97757)  // Claude Code
    static let green     = Color(0x10A37F)  // Codex
    static let blue      = Color(0x4285F4)  // Gemini
    static let purple    = Color(0x9B8AFB)  // Antigravity
    static let warn      = Color(0xE5484D)  // context window nearly full
    static let track     = Color(light: 0xD8D2C8, dark: 0x3A352E)  // gauge background
}

/// The per-row token number can show four different things. The user taps a number
/// to cycle the type; the choice is remembered per row (`UIState.rowMetric`).
private enum MetricKind: Int, CaseIterable {
    case ctx, today, fresh, input, output, cacheRead, cacheWrite
    var label: String {
        switch self {
        case .ctx: return "ctx"
        case .today: return "today"
        case .fresh: return "fresh"
        case .input: return "in"
        case .output: return "out"
        case .cacheRead: return "cache rd"
        case .cacheWrite: return "cache wr"
        }
    }
    var next: MetricKind { MetricKind(rawValue: (rawValue + 1) % MetricKind.allCases.count) ?? .ctx }
    /// This session's value for this metric (0 → the row shows "—", never a borrowed number).
    /// in/out/cache are read straight off the per-type `breakdown` so each is exact and additive
    /// (cache read is reads ONLY — not lumped with cache writes).
    func value(_ s: SessionInfo) -> Int {
        switch self {
        case .ctx: return s.contextTokens
        case .today: return s.tokens
        case .fresh: return s.freshTokens
        case .input: return s.breakdown.input
        case .output: return s.breakdown.output
        case .cacheRead: return s.breakdown.cacheRead
        case .cacheWrite: return s.breakdown.cacheWrite
        }
    }
    func value(_ sessions: [SessionInfo]) -> Int { sessions.reduce(0) { $0 + value($1) } }
}

/// Collapse/expand state, shared so it survives the popover being recreated.
@MainActor final class UIState: ObservableObject {
    static let shared = UIState()
    @Published var collapsedProviders: Set<String> = []
    @Published var expandedFolders: Set<String> = []
    @Published var expandedGroups: Set<String> = []
    @Published var revealedPaths: Set<String> = []   // folders whose full path row is shown
    @Published var activeOnly: Bool = false   // filter the tree to sessions active right now
    /// The metric every row shows by default; the header button cycles it. `MetricKind.rawValue`.
    @Published var defaultMetric: Int = 0
    /// Per-row overrides (session/folder/group key → `MetricKind.rawValue`). Tapping a single
    /// number sets one here; the header button clears these so all rows snap back to the default.
    @Published var rowMetric: [String: Int] = [:]
    @Published var usageExpanded = false
    /// Window the expanded usage tables cover: 1 (today), 7, or 30 days.
    @Published var usageWindowDays = 7
    /// A day key ("yyyy-MM-dd") when the user has clicked a histogram bar to inspect one day;
    /// nil = show the selected window rollup.
    @Published var usageSelectedDay: String? = nil
    /// Which expanded Usage detail panel is shown (Chart / Time / Breakdown). In-memory.
    @Published var usageTab: UsageTab = .chart
}

private struct FolderGroup: Identifiable {
    let folder: String
    let project: String
    let sessions: [SessionInfo]
    let contextTotal: Int    // live context held across this folder's sessions
    let last: Date
    var id: String { folder }
}

/// Sessions in a folder that share the same name (same opening prompt) — e.g. repeated
/// `/security-review` runs each create their own session. Collapsed into one row.
private struct NameGroup: Identifiable {
    let name: String
    let sessions: [SessionInfo]
    var contextTotal: Int { sessions.reduce(0) { $0 + $1.contextTokens } }
    var last: Date { sessions.map { $0.lastActivity }.max() ?? .distantPast }
    var id: String { name }
}

/// The shared widget content, used both as the menu-bar popover and the (resizable) pinned window.
struct DashboardView: View {
    @ObservedObject var monitor: AgentMonitor
    @ObservedObject private var ui = UIState.shared
    @ObservedObject private var settings = AppSettings.shared
    /// Popover passes a fixed width; the pinned window passes nil so it can be resized.
    /// Kept at 300 so the content sits comfortably inside the menu-bar popover window
    /// (which is narrower than it reports) — wider values were clipping at the edges.
    var fixedWidth: CGFloat? = 300
    var managesRefresh = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showInfo = false
    @State private var ollamaCollapsed = false
    /// Measured width of the whole widget (pinned window only). Drives `compact`.
    @State private var panelWidth: CGFloat = 0

    /// The pinned window's default width (`PinnedPanel` opens at 360). At or above this the rows
    /// use the normal horizontal flow; only when the user drags the window narrower do they switch
    /// to the stacked (compact) layout, so the numbers never bleed past the panel edge.
    private static let compactBelow: CGFloat = 360

    /// True when the resizable pinned window has been dragged narrower than its default width — the
    /// numbers then wrap under the title instead of getting clipped. Never compact in the
    /// fixed-width popover (tuned to fit at 300), nor before the first width measurement.
    private var compact: Bool { fixedWidth == nil && panelWidth > 0 && panelWidth < Self.compactBelow }

    private var activeNow: Int { monitor.activeCount() }

    private var visibleProviders: [Provider] {
        Provider.allCases.filter { !sessions(for: $0).isEmpty }
    }

    /// Today's sessions for a provider, narrowed to currently-active ones when the filter is on.
    private func sessions(for provider: Provider) -> [SessionInfo] {
        let all = monitor.activeSessions(for: provider)
        return ui.activeOnly ? all.filter { monitor.isActive($0) } : all
    }

    // The popover sizes to content, so its scroll area needs an explicit height or it
    // collapses to ~0. The pinned (resizable) window fills available space instead.
    private var listHeight: CGFloat {
        var rows = 0
        for p in visibleProviders {
            rows += 1
            if !ui.collapsedProviders.contains(p.rawValue) {
                let groups = folderGroups(sessions(for: p))
                rows += groups.count
                for g in groups where ui.expandedFolders.contains(key(p, g.folder)) { rows += g.sessions.count }
            }
        }
        return min(max(CGFloat(rows) * 26 + 16, 60), 340)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            PetView(mood: monitor.state.mood)
                .frame(height: 34)
                .clipped()                       // keep the sprite + meow inside the strip
                .padding(.horizontal, 14)        // inset so the cat doesn't touch the edges
                .padding(.top, 2).padding(.bottom, 6)
            Divider().overlay(Palette.panelEdge)
            UsageSection(monitor: monitor)
            Divider().overlay(Palette.panelEdge)
            tree
            Divider().overlay(Palette.panelEdge)
            ollamaStrip
            todayBar
            legend
            Divider().overlay(Palette.panelEdge)
            footer
        }
        // Popover: one unambiguous fixed width so the hosting window matches the
        // content exactly (a second min/max frame reports a smaller ideal width to
        // the menu-bar window and the system clips the edges). Pinned window: flex.
        .frame(width: fixedWidth, alignment: .leading)
        .frame(minWidth: fixedWidth == nil ? 300 : nil,
               maxWidth: fixedWidth == nil ? .infinity : nil,
               maxHeight: fixedWidth == nil ? .infinity : nil,
               alignment: .topLeading)
        .background(Palette.panel)
        .background(GeometryReader { geo in
            Color.clear.preference(key: RowWidthKey.self, value: geo.size.width)
        })
        .onPreferenceChange(RowWidthKey.self) { panelWidth = $0 }
        .foregroundStyle(Palette.text)
        // The popover is a hard fixed width (the menu-bar popover window can't grow past it
        // without clipping). Left-align + clip so an over-wide row trims its trailing edge
        // cleanly instead of bleeding sideways over the TODAY bar / neighbouring UI.
        .clipped()
        .onAppear { if managesRefresh { monitor.beginInteractiveRefresh(interval: 7) } }
        .onDisappear { if managesRefresh { monitor.endInteractiveRefresh(backgroundInterval: 30) } }
    }

    @ViewBuilder
    private var tree: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                if visibleProviders.isEmpty {
                    Text(ui.activeOnly ? "No sessions active right now." : "No sessions today.")
                        .font(.system(size: scaled(11))).foregroundStyle(Palette.dim)
                        .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 8)
                } else {
                    ForEach(visibleProviders, id: \.self) { providerBlock($0) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: fixedWidth == nil ? nil : listHeight + 22)
        .frame(maxHeight: fixedWidth == nil ? .infinity : nil)
    }

    /// A distinct "local model" group for a running Ollama server — separate from the folder-grouped
    /// agent sessions above (Ollama is an inference server, not a coding session). Mirrors the
    /// provider→folder tree as Ollama→model: one row per model used this session. Hidden entirely
    /// when no server is running. Shows no cost: local inference is free.
    @ViewBuilder
    private var ollamaStrip: some View {
        if let o = monitor.state.ollama {
            VStack(alignment: .leading, spacing: 5) {
                Button { ollamaCollapsed.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: ollamaCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: scaled(8), weight: .bold)).foregroundStyle(Palette.dim).frame(width: 8)
                        Circle().fill(o.busy ? Palette.yellow : Palette.dim).frame(width: 6, height: 6)
                        Text("Ollama").font(.system(size: scaled(11), weight: .semibold)).foregroundStyle(Palette.text)
                        Spacer(minLength: 4)
                        Text(ollamaCountLabel(o)).font(.system(size: scaled(9.5), design: .monospaced))
                            .foregroundStyle(Palette.dim).fixedSize()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if !ollamaCollapsed {
                    if o.models.isEmpty {
                        Text("running · no model loaded").font(.system(size: scaled(9.5), design: .monospaced))
                            .foregroundStyle(Palette.dim).padding(.leading, 14)
                    } else {
                        ForEach(o.models) { ollamaModelRow($0) }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            Divider().overlay(Palette.panelEdge)
        }
    }

    private func ollamaCountLabel(_ o: OllamaStatus) -> String {
        let n = o.models.count
        return (n == 1 ? "1 model" : "\(n) models") + " · local · free"
    }

    @ViewBuilder
    private func ollamaModelRow(_ m: OllamaModelActivity) -> some View {
        let active = m.active(now: monitor.state.lastUpdated, within: AgentMonitor.activeWindow)
        let tint = m.busy ? Palette.yellow : (active ? Palette.green : Palette.dim)
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 5, height: 5).fixedSize()
            Text(m.model).font(.system(size: scaled(10.5), design: .monospaced))
                .foregroundStyle(Palette.text).lineLimit(1).truncationMode(.middle)
            if let frac = m.contextFraction {
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.track).frame(width: 16, height: 4)
                    Capsule().fill(frac >= 0.9 ? Palette.warn : tint).frame(width: max(2, 16 * frac), height: 4)
                }
            }
            Spacer(minLength: 4)
            Text(ollamaMetrics(m)).font(.system(size: scaled(9), design: .monospaced))
                .foregroundStyle(Palette.dim).fixedSize()
        }
        .padding(.leading, 14)
        .help(ollamaRowHelp(m))
    }

    /// Compact per-model metric line: status · (tok/s when busy, else last latency) · chat|embed.
    private func ollamaMetrics(_ m: OllamaModelActivity) -> String {
        var parts = [m.busy ? "busy" : "idle"]
        if m.busy, let tps = m.tokensPerSecond { parts.append("\(Int(tps.rounded())) t/s") }
        else if let lat = m.lastLatency { parts.append(formatDuration(lat)) }
        if m.kind != .unknown { parts.append(m.kind == .embed ? "embed" : "chat") }
        return parts.joined(separator: " · ")
    }

    private func ollamaRowHelp(_ m: OllamaModelActivity) -> String {
        var bits = [m.model, m.current ? "loaded" : "used this session"]
        if let w = m.contextWindow { bits.append("ctx \(formatTokens(m.contextTokens ?? 0))/\(formatTokens(w))") }
        if m.requestCount > 0 { bits.append("\(m.requestCount) req") }
        if let tps = m.tokensPerSecond { bits.append("\(Int(tps.rounded())) tok/s") }
        return bits.joined(separator: " · ")
    }

    /// Human duration for a request's wall time: `2.0s`, `200ms`, `120µs`.
    private func formatDuration(_ t: TimeInterval) -> String {
        if t >= 1 { return String(format: "%.1fs", t) }
        if t >= 0.001 { return "\(Int((t * 1000).rounded()))ms" }
        return "\(Int((t * 1_000_000).rounded()))µs"
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(activeNow > 0 ? Palette.yellow : Palette.dim).frame(width: 7, height: 7)
            (Text("\(activeNow) ")
                .font(.system(size: scaled(14), weight: .bold))
             + Text(activeNow == 1 ? "agent active" : "agents active")
                .font(.system(size: scaled(13))).foregroundColor(Palette.dim))
                .lineLimit(1).fixedSize()
            Spacer(minLength: 6)
            HStack(spacing: 2) {
                Button { cycleDefaultMetric() } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.left.arrow.right.circle").font(.system(size: scaled(11), weight: .semibold))
                        Text(globalMetric.label).font(.system(size: scaled(9), weight: .semibold, design: .monospaced))
                            .lineLimit(1).fixedSize()
                    }
                    .foregroundStyle(Palette.dim).frame(height: 22).padding(.horizontal, 3)
                    .contentShape(Rectangle())   // hover/click the whole frame so .help fires
                }
                .buttonStyle(.plain)
                .help("All rows show \(globalMetric.label) (\(metricBlurb(globalMetric))). "
                      + "Click to switch all to \(globalMetric.next.label) — cycles ctx → today → fresh → in → out → cache rd → cache wr. "
                      + "Or tap a single number to switch just that row.")
                Button { ui.activeOnly.toggle() } label: {
                    // Icon-only: when on, the bolt fills yellow on a faint pill — that (plus the
                    // visibly-filtered tree and the tooltip) is the indicator. An inline "active
                    // only" label can't fit the fixed-width popover header and wrapped vertically.
                    Image(systemName: "bolt.fill").font(.system(size: scaled(11), weight: .semibold))
                        .foregroundStyle(ui.activeOnly ? Palette.yellow : Palette.dim)
                        .frame(width: 20, height: 22)
                        .background(ui.activeOnly ? Palette.yellow.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(ui.activeOnly
                      ? "Active-now filter is ON — showing only sessions with activity in the last 15 min. Click to show all of today."
                      : "Active-now filter — show only sessions active in the last 15 min (hide idle ones). Click to turn on.")
                let anyExpanded = !ui.expandedFolders.isEmpty
                iconButton(anyExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                           help: anyExpanded ? "Collapse all folders" : "Expand all folders") {
                    if anyExpanded { ui.expandedFolders.removeAll() } else { expandAll() }
                }
                iconButton("pin.fill", help: "Keep on screen (pin/unpin)") { PinnedPanel.shared.toggle() }
                iconButton("arrow.clockwise", help: "Refresh now") { monitor.refresh() }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    // MARK: Row layout (responsive)

    /// Arranges a row's `title` and its trailing numbers. Wide: everything on one line
    /// (`title … primary secondary`). Compact (pinned window dragged below default width): the
    /// numbers wrap under the title — `primary` (model + main metric) on its own line, then
    /// `secondary` (the smaller stats: messages / cost / time) on a line under it. Each closure
    /// supplies its own inner `HStack`; this only decides the layout.
    @ViewBuilder
    private func rowLayout<T: View, P: View, S: View>(
        detailIndent: CGFloat = 15,
        @ViewBuilder title: () -> T,
        @ViewBuilder primary: () -> P,
        @ViewBuilder secondary: () -> S
    ) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: 3) {
                title()
                VStack(alignment: .leading, spacing: 2) {
                    primary()
                    secondary()
                }
                .padding(.leading, detailIndent)
            }
        } else {
            HStack(spacing: 0) {
                title()
                Spacer(minLength: 8)
                HStack(spacing: 5) { primary(); secondary() }
            }
        }
    }

    // MARK: Provider level

    @ViewBuilder
    private func providerBlock(_ provider: Provider) -> some View {
        let sessions = sessions(for: provider)
        let groups = folderGroups(sessions)
        let tint = providerTint(provider)
        let expanded = !ui.collapsedProviders.contains(provider.rawValue)
        VStack(alignment: .leading, spacing: 5) {
            Button {
                toggle(&ui.collapsedProviders, provider.rawValue)
            } label: {
                HStack(spacing: 7) {
                    chevron(expanded)
                    RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 8, height: 8)
                    Text(provider.displayName.uppercased())
                        .font(.system(size: scaled(11), weight: .heavy)).tracking(0.8)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(groups.count) proj · \(monitor.activeCount(for: provider)) active")
                        .font(.system(size: scaled(9.5), design: .monospaced)).foregroundStyle(Palette.dim)
                        .lineLimit(1).fixedSize()
                }
            }
            .buttonStyle(.plain).help(expanded ? "Collapse this provider" : "Expand this provider's projects")
            if expanded {
                ForEach(groups) { folderBlock(provider, $0, tint: tint) }
            }
        }
    }

    // MARK: Folder level

    @ViewBuilder
    private func folderBlock(_ provider: Provider, _ g: FolderGroup, tint: Color) -> some View {
        let k = key(provider, g.folder)
        let expanded = ui.expandedFolders.contains(k)
        let live = g.sessions.contains { monitor.isActive($0) }
        VStack(alignment: .leading, spacing: 2) {
            Button { toggle(&ui.expandedFolders, k) } label: {
                rowLayout {
                    HStack(spacing: 6) {
                        chevron(expanded)
                        Circle().fill(live ? tint : Palette.dim.opacity(0.35)).frame(width: 6, height: 6)
                        Text(g.project).font(.system(size: scaled(12), weight: .semibold, design: .monospaced))
                            .lineLimit(1).truncationMode(.tail)
                            .onTapGesture { toggle(&ui.revealedPaths, k) }
                            .help(ui.revealedPaths.contains(k) ? "Hide folder path" : "Show folder path")
                        Text("(\(g.sessions.count))").font(.system(size: scaled(9), design: .monospaced)).foregroundStyle(Palette.dim)
                            .fixedSize()
                    }
                } primary: {
                    HStack(spacing: 6) {
                        let fk = "F:" + k
                        let kind = metric(forKey: fk)
                        metricText(kind.value(g.sessions), kind: kind, tint: tint)
                            .lineLimit(1).fixedSize()
                            .onTapGesture { cycleMetric(fk) }
                            .help(folderMetricHelp(kind, g))
                        let folderCost = cost(g.sessions)
                        if folderCost >= 0.01 {
                            Text(formatCost(folderCost)).font(.system(size: scaled(9), design: .monospaced))
                                .foregroundStyle(Palette.dim).lineLimit(1).fixedSize()
                                .help("\(costCaveat)\nThis project \(windowNoun): \(formatCost(folderCost)).")
                        }
                    }
                } secondary: { EmptyView() }
            }
            .buttonStyle(.plain).help(expanded ? "Collapse this folder's sessions" : "Expand this folder's sessions")
            if ui.revealedPaths.contains(k) {
                Text(prettyFolder(g.folder))
                    .font(.system(size: scaled(9.5), design: .monospaced)).foregroundStyle(Palette.dim.opacity(0.8))
                    .lineLimit(1).truncationMode(.middle).padding(.leading, 16)
            }
            if expanded {
                ForEach(nameGroups(g.sessions)) { ng in
                    if ng.sessions.count == 1 {
                        sessionLeaf(ng.sessions[0], tint: tint)
                    } else {
                        sessionGroup(provider, g.folder, ng, tint: tint)
                    }
                }
            }
        }
        .padding(.leading, 13)
    }

    // MARK: Session-name group (repeated same-prompt sessions)

    @ViewBuilder
    private func sessionGroup(_ provider: Provider, _ folder: String, _ ng: NameGroup, tint: Color) -> some View {
        let k = groupKey(provider, folder, ng.name)
        let expanded = ui.expandedGroups.contains(k)
        let live = ng.sessions.contains { monitor.isActive($0) }
        let model = uniformModel(ng.sessions)
        VStack(alignment: .leading, spacing: 2) {
            Button { toggle(&ui.expandedGroups, k) } label: {
                rowLayout {
                    HStack(spacing: 6) {
                        chevron(expanded)
                        Circle().fill(live ? tint : Palette.dim.opacity(0.3)).frame(width: 5, height: 5).fixedSize()
                        Text(ng.name).font(.system(size: scaled(10.5))).foregroundStyle(Palette.text)
                            .lineLimit(1).truncationMode(.tail)
                        Text("×\(ng.sessions.count)").font(.system(size: scaled(9), weight: .semibold, design: .monospaced))
                            .foregroundStyle(Palette.dim).fixedSize()
                    }
                } primary: {
                    HStack(spacing: 6) {
                        if let model {
                            Text(prettyModel(model)).font(.system(size: scaled(8), weight: .semibold, design: .monospaced))
                                .foregroundStyle(tint).padding(.horizontal, 3).padding(.vertical, 0.5)
                                .background(tint.opacity(0.16), in: Capsule()).fixedSize()
                        }
                        let gk = "G:" + k
                        let kind = metric(forKey: gk)
                        metricText(kind.value(ng.sessions), kind: kind, tint: tint)
                            .fixedSize()
                            .onTapGesture { cycleMetric(gk) }
                            .help(groupMetricHelp(kind, ng))
                    }
                } secondary: {
                    HStack(spacing: 6) {
                        let groupCost = cost(ng.sessions)
                        if groupCost >= 0.01 {
                            Text(formatCost(groupCost)).font(.system(size: scaled(9), design: .monospaced))
                                .foregroundStyle(Palette.dim).fixedSize()
                        }
                        Text(relativeTime(ng.last))
                            .font(.system(size: scaled(9), design: .monospaced)).foregroundStyle(Palette.dim)
                            .frame(width: 30, alignment: .trailing).fixedSize()
                    }
                }
            }
            .buttonStyle(.plain)
            .help("\(ng.sessions.count) sessions that each began with this prompt. Tokens are the sum; expand to see each session.")
            if expanded {
                ForEach(ng.sessions) { sessionLeaf($0, tint: tint, showId: true) }
                    .padding(.leading, 14)
            }
        }
        .padding(.leading, 30)
    }

    // MARK: Session leaf

    private func sessionLeaf(_ s: SessionInfo, tint: Color, showId: Bool = false) -> some View {
        let asId = showId || s.title == nil
        let name = showId ? (s.sessionId ?? "session") : s.displayName
        return rowLayout {
            // The session name: its log title/first prompt if any, else the short session
            // id shown in mono so it reads as an id. Gets the whole left column;
            // model/tokens/time are grouped on the right.
            HStack(spacing: 5) {
                Circle().fill(monitor.isActive(s) ? tint : Palette.dim.opacity(0.3)).frame(width: 5, height: 5).fixedSize()
                Text(name)
                    .font(.system(size: scaled(10.5), design: asId ? .monospaced : .default))
                    .foregroundStyle(asId ? Palette.dim : Palette.text)
                    .lineLimit(1).truncationMode(asId ? .middle : .tail)
                    .help(sessionTooltip(s))
            }
        } primary: {
            HStack(spacing: 5) {
                if let model = s.model {
                    Text(prettyModel(model)).font(.system(size: scaled(8), weight: .semibold, design: .monospaced))
                        .foregroundStyle(tint).padding(.horizontal, 3).padding(.vertical, 0.5)
                        .background(tint.opacity(0.16), in: Capsule())
                        .lineLimit(1).fixedSize()
                }
                sessionMetric(s, tint: tint)
            }
        } secondary: {
            HStack(spacing: 5) {
                // Conversation length (the /resume number). Inline only in the resizable pinned window
                // — the fixed-width popover has no room; it's in the tooltip there. A bubble glyph
                // disambiguates it from the relative-time column (which also uses "m").
                if fixedWidth == nil, s.messages > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "bubble.left").font(.system(size: scaled(7)))
                        Text("\(s.messages)").font(.system(size: scaled(8.5), design: .monospaced))
                    }
                    .foregroundStyle(Palette.dim).fixedSize()
                    .help("\(s.messages) messages — conversation length (the count Claude /resume shows).")
                }
                let c = monitor.cost(s)
                if c >= 0.01 {
                    Text(formatCost(c)).font(.system(size: scaled(9), design: .monospaced))
                        .foregroundStyle(Palette.dim).fixedSize().help("\(costCaveat)\nThis session \(windowNoun): \(formatCost(c)).")
                }
                Text(relativeTime(s.lastActivity))
                    .font(.system(size: scaled(9), design: .monospaced)).foregroundStyle(Palette.dim)
                    .frame(width: 30, alignment: .trailing).fixedSize()
            }
        }
        .padding(.leading, 30)
    }

    // MARK: Per-session metric (tap to cycle ctx → today → fresh → in → out → cache rd → cache wr)

    /// The session's token number. Tapping it cycles the type (remembered per session).
    /// In `ctx` mode it shows the fill bar — ctx is the only type with a real max (the
    /// context window); the others are plain counts. Shows "—" when that type is 0.
    @ViewBuilder
    private func sessionMetric(_ s: SessionInfo, tint: Color) -> some View {
        let kind = metric(forKey: s.id)
        Button { cycleMetric(s.id) } label: {
            if kind == .ctx {
                contextGauge(s, tint: tint)
            } else {
                metricText(kind.value(s), kind: kind, tint: tint).fixedSize()
            }
        }
        .buttonStyle(.plain)
        .help(sessionMetricHelp(kind, s))
    }

    // MARK: Context-window gauge (the ctx-mode fill bar + number)

    /// How full this session's context window is right now — a mini fill bar + the live token
    /// count. This is the live conversation size, NOT today's cumulative usage (the TODAY bar).
    @ViewBuilder
    private func contextGauge(_ s: SessionInfo, tint: Color) -> some View {
        if s.contextTokens > 0 {
            let frac = s.contextFraction
            HStack(spacing: 3) {
                if let frac {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.track).frame(width: 18, height: 4)
                        Capsule().fill(frac >= 0.9 ? Palette.warn : tint)
                            .frame(width: max(2, 18 * frac), height: 4)
                    }
                }
                (Text(formatTokens(s.contextTokens))
                    .font(.system(size: scaled(10.5), design: .monospaced))
                    .foregroundColor(frac.map { $0 >= 0.9 } == true ? Palette.warn : tint)
                 + (fixedWidth == nil ? Text(" ctx").font(.system(size: scaled(8), design: .monospaced)).foregroundColor(Palette.dim) : Text("")))
                    .fixedSize()
            }
            .help(contextHelp(s))
        } else {
            Text("—").font(.system(size: scaled(10.5), design: .monospaced))
                .foregroundStyle(Palette.dim).fixedSize()
        }
    }

    private func contextHelp(_ s: SessionInfo) -> String {
        let pct = s.contextFraction.map { " (\(Int(($0 * 100).rounded()))%)" } ?? ""
        let win = s.contextWindow > 0 ? " / \(formatTokens(s.contextWindow))" : ""
        return "Context window: \(formatTokens(s.contextTokens))\(win)\(pct) in use right now.\n"
            + "Live conversation size — not today's cumulative tokens (see the session tooltip / TODAY)."
    }

    /// One provider's TODAY entry: "CC 1.2M ~$4.10" (cost dim, omitted when zero).
    private func todayEntry(_ label: String, _ tint: Color, tokens: Int, cost: Double) -> Text {
        let costStr = cost > 0 ? " " + formatCost(cost) : ""
        return Text("\(label) ").font(.system(size: scaled(11), design: .monospaced)).foregroundColor(tint)
            + Text(formatTokens(tokens)).font(.system(size: scaled(11), weight: .semibold, design: .monospaced)).foregroundColor(Palette.text)
            + Text(costStr).font(.system(size: scaled(9.5), design: .monospaced)).foregroundColor(Palette.dim)
    }

    /// Header label for the current token/cost window.
    private var windowLabel: String { monitor.window == .today ? "TODAY" : "LAST 24H" }
    /// Human phrase for the window, used in tooltips.
    private var windowPhrase: String { monitor.window == .today ? "Today (since local midnight)" : "Last 24 hours (rolling)" }
    /// Lowercase noun for inline tooltips ("This session \(windowNoun): …").
    private var windowNoun: String { monitor.window == .today ? "today" : "in the last 24h" }

    /// Tappable window label: switches the token/cost totals between TODAY and a rolling LAST 24H.
    private var windowToggle: some View {
        Button { monitor.window = (monitor.window == .today ? .last24h : .today) } label: {
            HStack(spacing: 3) {
                Text(windowLabel).font(.system(size: scaled(9), weight: .heavy)).tracking(1).foregroundStyle(Palette.dim)
                Image(systemName: "arrow.left.arrow.right").font(.system(size: scaled(7), weight: .bold))
                    .foregroundStyle(Palette.dim.opacity(0.55))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(monitor.window == .today
              ? "Token/cost totals cover TODAY (since local midnight, matching the providers' daily usage reset). Click for a rolling LAST 24H window."
              : "Token/cost totals cover the rolling LAST 24H. Click to switch back to TODAY (since local midnight).")
    }

    /// (?) button opening a short "how these numbers are calculated" popover.
    private var infoButton: some View {
        Button { showInfo.toggle() } label: {
            Image(systemName: "questionmark.circle").font(.system(size: scaled(9.5), weight: .semibold))
                .foregroundStyle(Palette.dim.opacity(0.7)).frame(width: 16, height: 16).contentShape(Rectangle())
        }
        .buttonStyle(.plain).padding(.leading, 4)
        .help("How these numbers are calculated")
        .popover(isPresented: $showInfo, arrowEdge: .bottom) { infoPopover }
    }

    private func infoRow(_ name: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name).font(.system(size: scaled(9.5), weight: .heavy, design: .monospaced)).foregroundStyle(Palette.yellow)
            Text(desc).font(.system(size: scaled(10))).foregroundStyle(Palette.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var infoPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How the numbers are calculated")
                .font(.system(size: scaled(11), weight: .bold)).foregroundStyle(Palette.text)
            infoRow("TODAY / 24H", "Window for the token + cost totals. TODAY = since local midnight (matches the providers' daily reset); 24H = rolling last 24 hours. Tap the label to switch. Includes cache reads.")
            infoRow("ctx", "How full the context window is right now — the live conversation size, not a windowed total.")
            infoRow("red row", "Idle: the session's last log write was over 15 min ago. A green dot means active within 15 min.")
            infoRow("$ cost", "Estimated pay-as-you-go API price of the windowed tokens — an estimate, not your subscription bill.")
            infoRow("source", "Read-only from ~/.claude and ~/.codex logs. Claude is summed per assistant reply, counted once per message id (the log repeats each reply's usage across its thinking/text lines); Codex reports its session-cumulative total.")
            infoRow("vs claude /cost", "Tama reads the saved session logs; Claude's /cost reads its live billing. They match on completed turns and differ only by an interrupted or still-running turn — a call Claude billed but hasn't written to the log yet. Tama never touches the network, so reading a little under /cost is expected, not an error; it catches up once the turn is saved.")
        }
        .padding(12).frame(width: 288, alignment: .leading).background(Palette.panel)
    }

    private var todayBar: some View {
        let cc = monitor.state.usage[.claudeCode]?.todayTokens ?? 0
        let cx = monitor.state.usage[.codex]?.todayTokens ?? 0
        let ccCost = monitor.state.usage[.claudeCode]?.todayCost ?? 0
        let cxCost = monitor.state.usage[.codex]?.todayCost ?? 0
        return HStack(spacing: 0) {
            windowToggle
            infoButton
            Spacer()
            todayEntry("CC", Palette.coral, tokens: cc, cost: ccCost)
            + Text("   ")
            + todayEntry("CX", Palette.green, tokens: cx, cost: cxCost)
        }
        .help("\(costCaveat)\n\(windowPhrase): Claude \(formatCost(ccCost)), Codex \(formatCost(cxCost)).")
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    /// One "name desc · " fragment of the legend (name in yellow, desc dim).
    private func legendPiece(_ name: String, _ desc: String, last: Bool = false) -> Text {
        Text(name + " ").foregroundColor(Palette.yellow)
            + Text(desc + (last ? "" : " · ")).foregroundColor(Palette.dim)
    }

    /// Key for the tappable per-row numbers: what each type means. Tap any number to cycle them.
    private var legend: some View {
        var t = Text("tap any number · ").foregroundColor(Palette.dim.opacity(0.7))
        t = t + legendPiece("ctx", "live context")
        t = t + legendPiece("today", "total incl cache")
        t = t + legendPiece("fresh", "in+out")
        t = t + legendPiece("in", "input")
        t = t + legendPiece("out", "output")
        t = t + legendPiece("cache rd", "cache reads")
        t = t + legendPiece("cache wr", "cache writes", last: true)
        return t
            .font(.system(size: scaled(8.5), design: .monospaced))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.top, 2).padding(.bottom, 6)
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Button(action: toggleLaunchAtLogin) {
                HStack(spacing: 6) {
                    Image(systemName: launchAtLogin ? "checkmark.square.fill" : "square")
                        .foregroundStyle(launchAtLogin ? Palette.yellow : Palette.dim)
                    Text("Launch at login").font(.system(size: scaled(11))).foregroundStyle(Palette.text)
                }
            }
            .buttonStyle(.plain).help("Start automatically when you log in")
            Spacer()
            FooterChip(icon: "info.circle", title: "About") { AboutPanel.show() }
                .help("About Tama — show the installed version")
            FooterChip(icon: "power", title: "Quit", destructive: true) {
                NSApplication.shared.terminate(nil)
            }
            .help("Quit Tama")
            .padding(.leading, 6)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    // MARK: helpers

    private func chevron(_ expanded: Bool) -> some View {
        Image(systemName: expanded ? "chevron.down" : "chevron.right")
            .font(.system(size: scaled(8), weight: .bold)).foregroundStyle(Palette.dim).frame(width: 9)
    }

    private func iconButton(_ symbol: String, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: scaled(11), weight: .semibold))
                .foregroundStyle(Palette.dim).frame(width: 20, height: 22)
                .contentShape(Rectangle())   // hover/click the whole frame, not just the glyph (so .help fires)
        }
        .buttonStyle(.plain).help(help)
    }

    private func folderGroups(_ sessions: [SessionInfo]) -> [FolderGroup] {
        Dictionary(grouping: sessions, by: { $0.folder }).map { folder, sess in
            FolderGroup(folder: folder, project: sess.first?.project ?? folder,
                        sessions: sess.sorted { $0.lastActivity > $1.lastActivity },
                        contextTotal: sess.reduce(0) { $0 + $1.contextTokens },
                        last: sess.map { $0.lastActivity }.max() ?? .distantPast)
        }
        .sorted { $0.last > $1.last }
    }

    private func nameGroups(_ sessions: [SessionInfo]) -> [NameGroup] {
        Dictionary(grouping: sessions, by: { $0.displayName })
            .map { NameGroup(name: $0.key, sessions: $0.value.sorted { $0.lastActivity > $1.lastActivity }) }
            .sorted { $0.last > $1.last }
    }

    private func uniformModel(_ sessions: [SessionInfo]) -> String? {
        let models = Set(sessions.compactMap { $0.model })
        return models.count == 1 ? models.first : nil
    }

    /// Summed estimated API cost across a set of sessions (today's tokens).
    private func cost(_ sessions: [SessionInfo]) -> Double { sessions.reduce(0) { $0 + monitor.cost($1) } }

    // MARK: per-row metric selection

    /// The metric a row shows: its own override if it has one, else the global default.
    private func metric(forKey k: String) -> MetricKind { MetricKind(rawValue: ui.rowMetric[k] ?? ui.defaultMetric) ?? .ctx }
    private func cycleMetric(_ k: String) { ui.rowMetric[k] = metric(forKey: k).next.rawValue }

    /// The global default, and the header button that cycles it (clearing per-row overrides
    /// so every row visibly snaps to the new type).
    private var globalMetric: MetricKind { MetricKind(rawValue: ui.defaultMetric) ?? .ctx }
    private func cycleDefaultMetric() {
        ui.defaultMetric = globalMetric.next.rawValue
        ui.rowMetric.removeAll()
    }

    /// "12.4k ctx" — number in the provider tint, type suffix dim. "—" when the value is 0
    /// (no data of this type for this row), so it never shows a borrowed/wrong number.
    private func metricText(_ v: Int, kind: MetricKind, tint: Color) -> Text {
        guard v > 0 else {
            return Text("—").font(.system(size: scaled(10.5), design: .monospaced)).foregroundColor(Palette.dim)
        }
        let num = Text(formatTokens(v)).font(.system(size: scaled(10.5), design: .monospaced)).foregroundColor(tint)
        // Compact popover: drop the per-row type suffix (the header switch + legend already say
        // which metric is shown). The resizable pinned window keeps it.
        if fixedWidth != nil { return num }
        return num + Text(" " + kind.label).font(.system(size: scaled(8), design: .monospaced)).foregroundColor(Palette.dim)
    }

    private func metricBlurb(_ kind: MetricKind) -> String {
        switch kind {
        case .ctx:        return "Live context-window usage right now"
        case .today:      return "Today's cumulative tokens (incl. cache)"
        case .fresh:      return "Today's fresh tokens (input + output, no cache)"
        case .input:      return "Today's input tokens (fresh, non-cache)"
        case .output:     return "Today's output tokens"
        case .cacheRead:  return "Today's cache-read tokens (re-read context)"
        case .cacheWrite: return "Today's cache-write tokens (context cached)"
        }
    }

    private func sessionMetricHelp(_ kind: MetricKind, _ s: SessionInfo) -> String {
        "Showing: \(kind.label) — \(metricBlurb(kind)): \(formatTokens(kind.value(s))).\n"
            + "Click to switch type (ctx → today → fresh → in → out → cache rd → cache wr). '—' means no data of this type."
    }

    private func folderMetricHelp(_ kind: MetricKind, _ g: FolderGroup) -> String {
        "\(metricBlurb(kind)), summed across this project's \(g.sessions.count) session(s): "
            + "\(formatTokens(kind.value(g.sessions))).\nClick to switch type."
    }

    private func groupMetricHelp(_ kind: MetricKind, _ ng: NameGroup) -> String {
        "\(metricBlurb(kind)), summed across these \(ng.sessions.count) sessions: "
            + "\(formatTokens(kind.value(ng.sessions))).\nClick to switch type."
    }

    private func key(_ provider: Provider, _ folder: String) -> String { "\(provider.rawValue):\(folder)" }
    private func groupKey(_ provider: Provider, _ folder: String, _ name: String) -> String { "\(provider.rawValue):\(folder):\(name)" }

    private func toggle(_ set: inout Set<String>, _ k: String) {
        if set.contains(k) { set.remove(k) } else { set.insert(k) }
    }

    private func expandAll() {
        for p in visibleProviders {
            for g in folderGroups(sessions(for: p)) { ui.expandedFolders.insert(key(p, g.folder)) }
        }
    }

    private func toggleLaunchAtLogin() {
        launchAtLogin.toggle()
        try? launchAtLogin ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
    }

    private func sessionTooltip(_ s: SessionInfo) -> String {
        var lines = ["One \(s.provider.displayName) session (a single conversation) — not a subagent."]
        if let t = s.title { lines.append("Title: \(t)") }
        if let id = s.sessionId { lines.append("Session id: \(id)") }
        if s.messages > 0 { lines.append("Messages: \(s.messages) (conversation length — the count Claude /resume shows)") }
        if s.contextTokens > 0 {
            let pct = s.contextFraction.map { " (\(Int(($0 * 100).rounded()))% full)" } ?? ""
            let win = s.contextWindow > 0 ? " / \(formatTokens(s.contextWindow))" : ""
            lines.append("Context now: \(formatTokens(s.contextTokens))\(win)\(pct)")
        }
        if s.tokens > 0 {
            lines.append("\(windowPhrase): \(formatTokens(s.tokens)) total · \(formatTokens(s.freshTokens)) fresh · \(formatTokens(s.cacheTokens)) cache")
            let c = monitor.cost(s)
            if c > 0 { lines.append("Est. API cost \(windowNoun): \(formatCost(c))  (\(costCaveat))") }
        }
        return lines.joined(separator: "\n")
    }

    private func prettyModel(_ m: String) -> String {
        m.hasPrefix("claude-") ? String(m.dropFirst("claude-".count)) : m
    }

    private func prettyFolder(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func relativeTime(_ date: Date) -> String {
        let secs = Int(monitor.state.lastUpdated.timeIntervalSince(date))
        if secs < 60 { return "now" }
        if secs < 3600 { return "\(secs / 60)m" }
        return "\(secs / 3600)h"
    }
}

/// A footer action drawn as a clickable chip (icon + label on a faint rounded fill), so it
/// reads as a button rather than static text — the same affordance the header icon buttons use.
/// Brightens on hover; `destructive` actions (Quit) warm to the warn tint instead.
private struct FooterChip: View {
    let icon: String
    let title: String
    var destructive = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: scaled(9.5), weight: .semibold))
                Text(title).font(.system(size: scaled(11), weight: .medium))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(background, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var foreground: Color {
        if destructive { return hovering ? Palette.warn : Palette.dim }
        return hovering ? Palette.text : Palette.dim
    }

    private var background: Color {
        if destructive && hovering { return Palette.warn.opacity(0.14) }
        return hovering ? Palette.panelEdge : Palette.panelEdge.opacity(0.6)
    }
}
