import Foundation

/// Detects whether a local Ollama server is running, from a read-only process snapshot.
/// Standalone (not routed through `AgentClassifier`): Ollama is an inference server, not a
/// coding agent, so it is detected and displayed on its own — never as an `AgentSession`.
public enum OllamaPresence {
    /// True when some process is `ollama serve` (the local server), ignoring transient
    /// `ollama run` / `ollama pull` invocations and unrelated processes.
    public static func isRunning(in procs: [ProcInfo]) -> Bool {
        procs.contains { proc in
            guard let path = proc.execPath else { return false }
            return (path as NSString).lastPathComponent == "ollama" && proc.argv.contains("serve")
        }
    }
}
