import Foundation

public enum AgentClassifier {
    /// Pure classification of a process into a tracked AI-agent session, or nil.
    public static func classify(_ p: ProcInfo) -> AgentSession? {
        let path = p.execPath ?? ""
        let lowerPath = path.lowercased()
        let comm = p.commName.lowercased()
        let argv0 = (p.argv.first ?? "").lowercased()

        // Exclude internal automation (e.g. the security-review subprocess) — not interactive agents.
        if lowerPath.contains("application-security engineer") || arguments(p.argv, contain: "application-security engineer") { return nil }
        if lowerPath.contains("security_reminder_hook") || arguments(p.argv, contain: "security_reminder_hook") { return nil }

        guard let provider = detectProvider(lowerPath: lowerPath, argv0: argv0, argv: p.argv, comm: comm) else { return nil }
        let location = detectLocation(path: path, lowerPath: lowerPath, argv: p.argv, hasTTY: p.hasTTY)
        return AgentSession(pid: p.pid, provider: provider, location: location, cwd: p.cwd)
    }

    private static func detectProvider(lowerPath: String, argv0: String, argv: [String], comm: String) -> Provider? {
        if comm == "codex"
            || argv0 == "codex"
            || lowerPath.contains("codex")           // ".../codex" exec or "/Codex.app"
            || arguments(argv, contain: "openai.chatgpt")
            || arguments(argv, contain: "app-server") {
            return .codex
        }
        if comm == "antigravity" || argv0 == "antigravity" || lowerPath.contains("antigravity") {
            return .antigravity
        }
        if comm == "gemini" || argv0 == "gemini" || lowerPath.contains("gemini-cli") {
            return .gemini
        }
        // The Claude Code CLI installs as ~/.local/share/claude/versions/<version> and
        // renames its process to the version string, so comm/path basename is e.g. "2.1.183",
        // not "claude". Match the install path and argv[0] as well.
        if comm == "claude"
            || argv0 == "claude"
            || lowerPath.hasSuffix("/claude")
            || lowerPath.contains("/claude/versions/")
            || arguments(argv, contain: ".claude/local")
            || lowerPath.contains("/claude.app/") {
            return .claudeCode
        }
        return nil
    }

    private static func detectLocation(path: String, lowerPath: String, argv: [String], hasTTY: Bool) -> Location {
        if path.contains("/Applications/") && path.contains(".app/") { return .desktop }
        if lowerPath.contains(".vscode/extensions")
            || lowerPath.contains("openai.chatgpt")
            || lowerPath.contains("/.cursor/")
            || lowerPath.contains("jetbrains")
            || arguments(argv, contain: "app-server")
            || arguments(argv, contain: ".vscode/extensions")
            || arguments(argv, contain: "openai.chatgpt")
            || arguments(argv, contain: "/.cursor/")
            || arguments(argv, contain: "jetbrains") {
            return .ide
        }
        // tty-backed (or headless, lumped here for v1) CLI session.
        return .terminal
    }

    private static func arguments(_ argv: [String], contain needle: String) -> Bool {
        argv.contains { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
