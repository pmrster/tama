using System.Diagnostics;

namespace Tama.Core;

public interface IOllamaReading
{
    OllamaStatus? Read();
}

public interface IOllamaPresence
{
    bool IsRunning();
}

/// <summary>
/// Detects a local Ollama server from the process table — read-only enumeration, never
/// Process.Start. Name-only match (the design-approved Windows simplification of the mac
/// argv-based `ollama serve` check: command lines aren't readable in-box on Windows, and a
/// transient `ollama run` briefly matching is acceptable).
/// </summary>
public sealed class ProcessOllamaPresence : IOllamaPresence
{
    public bool IsRunning()
    {
        var procs = Process.GetProcessesByName("ollama");
        try { return procs.Length > 0; }
        finally { foreach (var p in procs) p.Dispose(); }
    }
}
