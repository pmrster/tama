import XCTest
import TamaCore

final class OllamaPresenceTests: XCTestCase {
    private func proc(_ path: String?, _ argv: [String]) -> ProcInfo {
        ProcInfo(pid: 1, ppid: 0, execPath: path, argv: argv, cwd: nil, hasTTY: false, commName: "ollama")
    }

    func test_detects_ollama_serve() {
        let procs = [proc("/Applications/Ollama.app/Contents/Resources/ollama",
                          ["/Applications/Ollama.app/Contents/Resources/ollama", "serve"])]
        XCTAssertTrue(OllamaPresence.isRunning(in: procs))
    }

    func test_ignores_ollama_run_and_pull() {
        let procs = [proc("/usr/local/bin/ollama", ["ollama", "pull", "qwen3.6:27b-mlx"]),
                     proc("/usr/local/bin/ollama", ["ollama", "run", "qwen3.6:27b-mlx"])]
        XCTAssertFalse(OllamaPresence.isRunning(in: procs))
    }

    func test_ignores_unrelated_process_named_serve() {
        // basename must be `ollama`; a different binary that merely takes a "serve" arg is not Ollama.
        XCTAssertFalse(OllamaPresence.isRunning(in: [proc("/usr/bin/caddy", ["caddy", "serve"])]))
    }

    func test_empty_is_false() {
        XCTAssertFalse(OllamaPresence.isRunning(in: []))
    }
}
