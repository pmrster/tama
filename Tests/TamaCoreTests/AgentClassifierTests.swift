import XCTest
import TamaCore

final class AgentClassifierTests: XCTestCase {
    private func proc(pid: Int32 = 1, path: String?, argv: [String], tty: Bool, comm: String) -> ProcInfo {
        ProcInfo(pid: pid, ppid: 1, execPath: path, argv: argv, cwd: nil, hasTTY: tty, commName: comm)
    }

    func test_claude_terminal() {
        let p = proc(path: "/Example/Home/.local/bin/claude", argv: ["claude"], tty: true, comm: "claude")
        let s = AgentClassifier.classify(p)
        XCTAssertEqual(s?.provider, .claudeCode)
        XCTAssertEqual(s?.location, .terminal)
    }

    func test_claude_cli_version_named_binary() {
        // Real shape on the dev machine: the CLI is installed at
        // ~/.local/share/claude/versions/<ver> and renames its process to the version
        // string, so comm and the path basename are e.g. "2.1.183", not "claude".
        let p = proc(path: "/Example/Home/.local/share/claude/versions/2.1.183",
                     argv: ["claude"], tty: true, comm: "2.1.183")
        let s = AgentClassifier.classify(p)
        XCTAssertEqual(s?.provider, .claudeCode)
        XCTAssertEqual(s?.location, .terminal)
    }

    func test_codex_ide_app_server() {
        let p = proc(path: "/Example/Home/.vscode/extensions/openai.chatgpt-26.616/bin/macos-aarch64/codex",
                     argv: ["codex", "app-server", "--analytics-default-enabled"], tty: false, comm: "codex")
        let s = AgentClassifier.classify(p)
        XCTAssertEqual(s?.provider, .codex)
        XCTAssertEqual(s?.location, .ide)
    }

    func test_codex_desktop() {
        let p = proc(path: "/Applications/Codex.app/Contents/Resources/cua_node/bin/node_repl",
                     argv: ["node_repl"], tty: false, comm: "node_repl")
        let s = AgentClassifier.classify(p)
        XCTAssertEqual(s?.provider, .codex)
        XCTAssertEqual(s?.location, .desktop)
    }

    func test_claude_desktop() {
        let p = proc(path: "/Applications/Claude.app/Contents/MacOS/Claude",
                     argv: ["Claude"], tty: false, comm: "Claude")
        let s = AgentClassifier.classify(p)
        XCTAssertEqual(s?.provider, .claudeCode)
        XCTAssertEqual(s?.location, .desktop)
    }

    func test_security_review_subprocess_excluded() {
        let p = proc(path: "/Example/Home/.local/bin/claude",
                     argv: ["claude", "--system-prompt", "You are a senior application-security engineer performing a deep review"],
                     tty: false, comm: "claude")
        XCTAssertNil(AgentClassifier.classify(p))
    }

    func test_unrelated_process_is_nil() {
        let p = proc(path: "/usr/bin/ssh", argv: ["ssh", "host"], tty: true, comm: "ssh")
        XCTAssertNil(AgentClassifier.classify(p))
    }
}
