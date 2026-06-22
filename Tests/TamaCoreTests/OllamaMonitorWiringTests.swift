import XCTest
import TamaCore

private struct StubActivity: ActivityScanning {
    func scan() -> Activity { .empty }
}
private struct StubProcs: OllamaPresenceScanning {
    let procs: [ProcInfo]
    func ollamaProcesses() -> [ProcInfo] { procs }
}
private struct StubOllama: OllamaReading {
    let status: OllamaStatus?
    func read() -> OllamaStatus? { status }
}

@MainActor
final class OllamaMonitorWiringTests: XCTestCase {
    private let serve = ProcInfo(pid: 1, ppid: 0, execPath: "/x/ollama", argv: ["ollama", "serve"],
                                 cwd: nil, hasTTY: false, commName: "ollama")

    private func busyStatus(_ tag: String = "qwen3.6:27b-mlx", window: Int? = nil) -> OllamaStatus {
        OllamaStatus(models: [OllamaModelActivity(model: tag, current: true, busy: true, contextWindow: window)])
    }

    // Pure gating logic.
    func test_state_hidden_when_not_running() {
        XCTAssertNil(AgentMonitor.ollamaState(presence: false, enrichment: busyStatus()))
    }

    func test_state_running_keeps_enrichment_and_marks_running() {
        let s = AgentMonitor.ollamaState(presence: true, enrichment: busyStatus())
        XCTAssertEqual(s?.running, true)
        XCTAssertEqual(s?.busy, true)
        XCTAssertEqual(s?.currentModel?.model, "qwen3.6:27b-mlx")
    }

    func test_state_running_without_log_still_shows() {
        let s = AgentMonitor.ollamaState(presence: true, enrichment: nil)
        XCTAssertEqual(s?.running, true)
        XCTAssertEqual(s?.models.isEmpty, true)
    }

    // Wired through refresh (synchronous mode).
    func test_refresh_populates_ollama_when_serve_running() {
        let monitor = AgentMonitor(reader: StubActivity(), now: { Date() }, runsInBackground: false,
                                   presenceScanner: StubProcs(procs: [serve]),
                                   ollamaReader: StubOllama(status: busyStatus(window: 32768)))
        monitor.refresh()
        XCTAssertEqual(monitor.state.ollama?.running, true)
        XCTAssertEqual(monitor.state.ollama?.currentModel?.model, "qwen3.6:27b-mlx")
        XCTAssertEqual(monitor.state.ollama?.currentModel?.contextWindow, 32768)
    }

    func test_refresh_ollama_nil_when_not_running() {
        let monitor = AgentMonitor(reader: StubActivity(), now: { Date() }, runsInBackground: false,
                                   presenceScanner: StubProcs(procs: []),
                                   ollamaReader: StubOllama(status: busyStatus()))
        monitor.refresh()
        XCTAssertNil(monitor.state.ollama)
    }
}
