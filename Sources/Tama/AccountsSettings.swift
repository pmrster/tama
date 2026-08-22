import SwiftUI
import AppKit
import TamaCore

/// Settings section for extra provider accounts — additional `CLAUDE_CONFIG_DIR` / `CODEX_HOME`
/// dirs so a second Claude/Codex login on this Mac shows up as its own account (its own sessions,
/// usage and plan limits). The default `~/.claude` / `~/.codex` are always scanned and not listed.
struct AccountsSettings: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var adding = false
    @State private var newProvider: Provider = .claudeCode
    @State private var newLabel = ""
    @State private var newPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The default ~/.claude and ~/.codex are always included. Add a folder here only if you point the CLI at another config dir (CLAUDE_CONFIG_DIR / CODEX_HOME) for a second account.")
                .font(.system(size: scaled(10.5))).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true)

            ForEach(settings.extraAccounts) { acct in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(providerTint(acct.provider)).frame(width: 8, height: 8)
                    Text(acct.label ?? "—").font(.system(size: scaled(11), weight: .semibold, design: .monospaced))
                    Text(acct.provider.displayName).font(.system(size: scaled(10))).foregroundStyle(Palette.dim)
                    Text(acct.root.path).font(.system(size: scaled(9.5), design: .monospaced))
                        .foregroundStyle(Palette.dim).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button { remove(acct) } label: {
                        Image(systemName: "trash").font(.system(size: scaled(10))).foregroundStyle(Palette.coral)
                    }.buttonStyle(.plain).help("Remove this account")
                }
            }

            if adding {
                addForm
            } else {
                Button { adding = true } label: {
                    Label("Add account", systemImage: "plus.circle")
                        .font(.system(size: scaled(11), weight: .semibold)).foregroundStyle(Palette.text)
                }.buttonStyle(.plain)
            }
        }
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: $newProvider) {
                Text("Claude Code").tag(Provider.claudeCode)
                Text("Codex").tag(Provider.codex)
            }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 220)
            TextField("Label (e.g. work)", text: $newLabel)
                .textFieldStyle(.roundedBorder).font(.system(size: scaled(11)))
            HStack(spacing: 6) {
                Text(newPath.isEmpty ? "No folder chosen" : newPath)
                    .font(.system(size: scaled(9.5), design: .monospaced))
                    .foregroundStyle(newPath.isEmpty ? Palette.dim : Palette.text)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose…") { chooseFolder() }.font(.system(size: scaled(10)))
            }
            HStack {
                Spacer()
                Button("Cancel") { resetForm() }.font(.system(size: scaled(10)))
                Button("Add") { commit() }
                    .font(.system(size: scaled(10), weight: .semibold))
                    .disabled(newLabel.trimmingCharacters(in: .whitespaces).isEmpty || newPath.isEmpty)
            }
        }
        .padding(8)
        .background(Palette.panelEdge.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose config dir"
        panel.message = "Pick the CLAUDE_CONFIG_DIR / CODEX_HOME folder for this account."
        if panel.runModal() == .OK, let url = panel.url { newPath = url.path }
    }

    private func commit() {
        let label = newLabel.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, !newPath.isEmpty else { return }
        let root = AccountRoot(provider: newProvider, label: label, root: URL(fileURLWithPath: newPath))
        settings.extraAccounts.append(root)
        resetForm()
    }

    private func remove(_ acct: AccountRoot) {
        settings.extraAccounts.removeAll { $0.id == acct.id }
    }

    private func resetForm() {
        adding = false; newLabel = ""; newPath = ""; newProvider = .claudeCode
    }
}
