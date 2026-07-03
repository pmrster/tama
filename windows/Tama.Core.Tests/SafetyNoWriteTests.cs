using System.Security.Cryptography;
using Tama.Core;

namespace Tama.Core.Tests;

[TestClass]
public sealed class SafetyNoWriteTests
{
    private sealed record Snapshot(string Path, long Length, DateTime LastWriteUtc, string Sha256);

    private static List<Snapshot> Snap(string root) =>
        Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories)
            .OrderBy(p => p, StringComparer.Ordinal)
            .Select(p =>
            {
                var info = new FileInfo(p);
                using var stream = File.OpenRead(p);
                return new Snapshot(p, info.Length, info.LastWriteTimeUtc,
                    Convert.ToHexString(SHA256.HashData(stream)));
            })
            .ToList();

    [TestMethod]
    public void Readers_never_modify_the_fixture_tree()
    {
        var fixtures = FixtureLocator.FixturesDir();
        var before = Snap(fixtures);

        // Exercise EVERY reader + the scanner (extend per new reader — same rule as mac).
        foreach (var file in Directory.EnumerateFiles(fixtures, "*", SearchOption.AllDirectories))
        {
            SafeFileReader.ReadData(file);
            SafeFileReader.Tail(file, maxBytes: 64);
        }
        ClaudeSessionReader.ParseFile(
            Path.Combine(fixtures, "claude", "-Example-Code-myapp", "aabbccdd.jsonl"));
        CodexReader.ParseFile(Path.Combine(fixtures, "codex", "2026", "06", "19",
            "rollout-2026-06-19T08-00-00-019eddab-x.jsonl"));
        GeminiReader.Read(Path.Combine(fixtures, "gemini"));
        AntigravityReader.Read(Path.Combine(fixtures, "antigravity", "history.jsonl"));
        new OllamaReader(Path.Combine(fixtures, "ollama", "server.log"), TimeZoneInfo.Utc).Read();
        new ActiveSessionsScanner(
            Path.Combine(fixtures, "claude"), Path.Combine(fixtures, "codex"),
            Path.Combine(fixtures, "gemini"), Path.Combine(fixtures, "antigravity", "history.jsonl"),
            () => DateTimeOffset.Parse("2026-06-19T12:00:00Z"), TimeZoneInfo.Utc)
            .Scan(TokenWindow.Today);

        CollectionAssert.AreEqual(before, Snap(fixtures));
    }
}
