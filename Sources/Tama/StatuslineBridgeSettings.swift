import SwiftUI
import AppKit
import TamaCore

/// Settings section explaining the opt-in Claude Code "statusline bridge": Claude Code's live
/// 5h / weekly limits are only handed to the user's own statusline command, so Tama can't read
/// them directly. Adding this one line to the statusline mirrors that data into a file Tama reads,
/// upgrading the Claude rows from the (sometimes stale) cache to live figures. Read-only for Tama;
/// nothing here talks to the network.
struct StatuslineBridgeSettings: View {
    @State private var copied = false

    private var command: String {
        "cat | tee \"$HOME/Library/Application Support/Tama/statusline/default.json\" | jq -r '.model.display_name'"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Optional. Claude Code's live 5h / weekly limits are only sent to your statusline, so Tama shows a cached copy that can lag. Add this to your Claude Code statusLine command to mirror the live numbers into a file Tama reads (for a second account, write to <label>.json).")
                .font(.system(size: scaled(10.5))).foregroundStyle(Palette.dim)
                .fixedSize(horizontal: false, vertical: true)

            Text(command)
                .font(.system(size: scaled(9.5), design: .monospaced))
                .foregroundStyle(Palette.text)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.panelEdge.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                .textSelection(.enabled)

            HStack {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy command", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: scaled(10), weight: .semibold)).foregroundStyle(Palette.text)
                }.buttonStyle(.plain)
                Spacer()
            }
        }
    }
}
