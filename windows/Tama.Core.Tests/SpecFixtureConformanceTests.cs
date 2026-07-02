using System.Text.Json;
using Tama.Core;

namespace Tama.Core.Tests;

internal static class FixtureLocator
{
    /// <summary>Walks up from the test bin dir to the repo root's spec/fixtures.</summary>
    public static string FixturesDir()
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir != null; dir = dir.Parent)
        {
            var candidate = Path.Combine(dir.FullName, "spec", "fixtures");
            if (Directory.Exists(candidate)) return candidate;
        }
        throw new InvalidOperationException("spec/fixtures not found above " + AppContext.BaseDirectory);
    }
}

[TestClass]
public sealed class SpecFixtureConformanceTests
{
    // Plan A covers Claude; Plan B extends this class for Codex/Gemini/Antigravity/Ollama.
    [TestMethod]
    public void Claude_fixture_produces_expected_values()
    {
        var fixtures = FixtureLocator.FixturesDir();
        using var expectedDoc = JsonDocument.Parse(
            File.ReadAllBytes(Path.Combine(fixtures, "expected.json")));
        var e = expectedDoc.RootElement.GetProperty("claude");

        var logPath = Path.Combine(fixtures, "claude", "-Example-Code-myapp", "aabbccdd.jsonl");
        var parsed = ClaudeSessionReader.ParseFile(logPath);
        Assert.IsNotNull(parsed);

        Assert.AreEqual(e.GetProperty("folder").GetString(), parsed.Folder);
        Assert.AreEqual(e.GetProperty("tokens").GetInt32(), parsed.Cumulative.Total);
        Assert.AreEqual(e.GetProperty("cacheTokens").GetInt32(),
            parsed.Cumulative.CacheRead + parsed.Cumulative.CacheWrite);
        Assert.AreEqual(e.GetProperty("contextTokens").GetInt32(), parsed.ContextTokens);
        Assert.AreEqual(e.GetProperty("contextWindow").GetInt32(), parsed.ContextWindow);
        Assert.AreEqual(e.GetProperty("model").GetString(), parsed.Model);
        Assert.AreEqual(e.GetProperty("sessionId").GetString(), parsed.SessionId);
        Assert.AreEqual(e.GetProperty("title").GetString(), parsed.Title);
        Assert.AreEqual(e.GetProperty("messages").GetInt32(), parsed.Messages);
    }

    [TestMethod]
    public void Codex_fixture_produces_expected_values()
    {
        var fixtures = FixtureLocator.FixturesDir();
        using var expectedDoc = JsonDocument.Parse(
            File.ReadAllBytes(Path.Combine(fixtures, "expected.json")));
        var e = expectedDoc.RootElement.GetProperty("codex");

        var logPath = Path.Combine(fixtures, "codex", "2026", "06", "19",
            "rollout-2026-06-19T08-00-00-019eddab-x.jsonl");
        var parsed = CodexReader.ParseFile(logPath);
        Assert.IsNotNull(parsed);

        Assert.AreEqual(e.GetProperty("folder").GetString(), parsed.Folder);
        Assert.AreEqual(e.GetProperty("tokens").GetInt32(), parsed.Cumulative.Total);
        Assert.AreEqual(e.GetProperty("cacheTokens").GetInt32(),
            parsed.Cumulative.CacheRead + parsed.Cumulative.CacheWrite);
        Assert.AreEqual(e.GetProperty("contextTokens").GetInt32(), parsed.ContextTokens);
        Assert.AreEqual(e.GetProperty("contextWindow").GetInt32(), parsed.ContextWindow);
        Assert.AreEqual(e.GetProperty("model").GetString(), parsed.Model);
        Assert.AreEqual(e.GetProperty("sessionId").GetString(), parsed.SessionId);
        Assert.AreEqual(e.GetProperty("title").GetString(), parsed.Title);
        Assert.AreEqual(e.GetProperty("messages").GetInt32(), parsed.Messages);
    }
}
