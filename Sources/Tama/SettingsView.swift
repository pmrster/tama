import SwiftUI
import TamaCore

/// The Settings window: appearance + text-size pickers, themed like the rest of the app.
/// Observes `AppSettings.shared`, so picking a value updates this window and everything else.
struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings")
                .font(.system(size: scaled(18), weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.text)

            section("APPEARANCE") {
                Picker("", selection: $settings.appearance) {
                    Text("System").tag(Appearance.system)
                    Text("Light").tag(Appearance.light)
                    Text("Dark").tag(Appearance.dark)
                }
                .pickerStyle(.segmented).labelsHidden()
            }

            section("TEXT SIZE") {
                Picker("", selection: $settings.fontSize) {
                    Text("S").tag(FontSize.small)
                    Text("M").tag(FontSize.medium)
                    Text("L").tag(FontSize.large)
                }
                .pickerStyle(.segmented).labelsHidden()
            }

            section("NOTIFICATIONS") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $settings.notifyAgentQuiet) {
                        Text("Alert when an agent goes quiet (may be waiting for input)")
                            .font(.system(size: scaled(12)))
                            .foregroundStyle(Palette.text)
                    }
                    Toggle(isOn: $settings.notifyContextHigh) {
                        Text("Warn when a session's context is nearly full (85%)")
                            .font(.system(size: scaled(12)))
                            .foregroundStyle(Palette.text)
                    }
                }
                .toggleStyle(.switch)
            }

            section("PLAN LIMITS") {
                Toggle(isOn: $settings.showLimits) {
                    Text("Show the plan-limits section (session / weekly quota)")
                        .font(.system(size: scaled(12))).foregroundStyle(Palette.text)
                }
                .toggleStyle(.switch)
            }

            section("ACCOUNTS") {
                AccountsSettings()
            }

            section("CLAUDE LIVE LIMITS (BRIDGE)") {
                StatuslineBridgeSettings()
            }

            section("PREVIEW") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle().fill(Palette.yellow).frame(width: scaled(7), height: scaled(7))
                        Text("3 agents active").font(.system(size: scaled(13))).foregroundStyle(Palette.text)
                    }
                    Text("CC 1.2M  ~$4.10").font(.system(size: scaled(11), design: .monospaced))
                        .foregroundStyle(Palette.dim)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.panelEdge.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer(minLength: 4)

            HStack {
                Spacer()
                Button { SettingsPanel.close() } label: {
                    Text("Close").font(.system(size: scaled(12), weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .padding(.horizontal, 22).padding(.vertical, 7)
                        .background(Palette.coral.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.panel)
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: scaled(10), weight: .heavy)).tracking(1)
                .foregroundStyle(Palette.dim)
            content()
        }
    }
}
