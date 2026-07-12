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

    [TestMethod]
    public void Gemini_fixture_produces_expected_values()
    {
        var fixtures = FixtureLocator.FixturesDir();
        using var expectedDoc = JsonDocument.Parse(
            File.ReadAllBytes(Path.Combine(fixtures, "expected.json")));
        var e = expectedDoc.RootElement.GetProperty("gemini");

        var sessions = GeminiReader.Read(Path.Combine(fixtures, "gemini"));
        Assert.AreEqual(1, sessions.Count);
        Assert.AreEqual(e.GetProperty("folder").GetString(), sessions[0].Folder);
    }

    [TestMethod]
    public void Antigravity_fixture_produces_expected_values()
    {
        var fixtures = FixtureLocator.FixturesDir();
        using var expectedDoc = JsonDocument.Parse(
            File.ReadAllBytes(Path.Combine(fixtures, "expected.json")));
        var e = expectedDoc.RootElement.GetProperty("antigravity");

        var sessions = AntigravityReader.Read(Path.Combine(fixtures, "antigravity", "history.jsonl"));
        Assert.AreEqual(1, sessions.Count);
        Assert.AreEqual(e.GetProperty("folder").GetString(), sessions[0].Folder);
        Assert.AreEqual(e.GetProperty("lastActivityEpochSeconds").GetInt64(),
            sessions[0].LastActivity.ToUnixTimeSeconds());
    }

    [TestMethod]
    public void Ollama_fixture_produces_expected_values()
    {
        var fixtures = FixtureLocator.FixturesDir();
        using var expectedDoc = JsonDocument.Parse(
            File.ReadAllBytes(Path.Combine(fixtures, "expected.json")));
        var expectedModels = expectedDoc.RootElement.GetProperty("ollama").GetProperty("models");

        var status = new OllamaReader(Path.Combine(fixtures, "ollama", "server.log"), TimeZoneInfo.Utc).Read();
        Assert.IsNotNull(status);
        Assert.AreEqual(expectedModels.GetArrayLength(), status.Models.Count);

        for (var i = 0; i < status.Models.Count; i++)
        {
            var m = status.Models[i];
            var e = expectedModels[i];
            Assert.AreEqual(e.GetProperty("model").GetString(), m.Model);
            Assert.AreEqual(e.GetProperty("current").GetBoolean(), m.Current);
            Assert.AreEqual(e.GetProperty("busy").GetBoolean(), m.Busy);
            Assert.AreEqual(e.GetProperty("contextWindow").GetInt32(), m.ContextWindow);
            Assert.AreEqual(e.GetProperty("contextTokens").GetInt32(), m.ContextTokens);
            Assert.AreEqual(e.GetProperty("tokensPerSecond").GetDouble(), m.TokensPerSecond);
            Assert.AreEqual(e.GetProperty("lastLatencySeconds").GetDouble(), m.LastLatencySeconds!.Value, 0.001);
            Assert.AreEqual(e.GetProperty("kind").GetString(),
                m.Kind.ToString().ToLowerInvariant());
            Assert.AreEqual(e.GetProperty("requestCount").GetInt32(), m.RequestCount);
            Assert.AreEqual(e.GetProperty("lastActivityEpochSeconds").GetInt64(),
                m.LastActivity!.Value.ToUnixTimeSeconds());
        }
    }

    /// <summary>End-to-end mirror of the Swift conformance test: fixtures copied into a
    /// temp tree shaped like the real log roots, every mtime pinned to scanNow.</summary>
    [TestMethod]
    public void Full_scan_produces_expected_sessions_for_all_providers()
    {
        var fixtures = FixtureLocator.FixturesDir();
        using var expectedDoc = JsonDocument.Parse(
            File.ReadAllBytes(Path.Combine(fixtures, "expected.json")));
        var e = expectedDoc.RootElement;
        var now = DateTimeOffset.Parse(e.GetProperty("scanNow").GetString()!);

        var root = Path.Combine(Path.GetTempPath(), "spec-conf-" + Guid.NewGuid());
        try
        {
            foreach (var name in new[] { "claude", "codex", "gemini", "antigravity" })
                CopyTree(Path.Combine(fixtures, name), Path.Combine(root, name));
            foreach (var f in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories))
                File.SetLastWriteTimeUtc(f, now.UtcDateTime);

            var scanner = new ActiveSessionsScanner(
                Path.Combine(root, "claude"), Path.Combine(root, "codex"),
                Path.Combine(root, "gemini"), Path.Combine(root, "antigravity", "history.jsonl"),
                () => now, TimeZoneInfo.Utc);
            var sessions = scanner.Scan(TokenWindow.Today).Sessions;
            Assert.AreEqual(4, sessions.Count);

            var claude = sessions.Single(s => s.Provider == Provider.ClaudeCode);
            var ec = e.GetProperty("claude");
            Assert.AreEqual(ec.GetProperty("folder").GetString(), claude.Folder);
            Assert.AreEqual(ec.GetProperty("project").GetString(), claude.Project);
            Assert.AreEqual(ec.GetProperty("tokens").GetInt32(), claude.Tokens);
            Assert.AreEqual(ec.GetProperty("cacheTokens").GetInt32(), claude.CacheTokens);
            Assert.AreEqual(ec.GetProperty("contextTokens").GetInt32(), claude.ContextTokens);
            Assert.AreEqual(ec.GetProperty("contextWindow").GetInt32(), claude.ContextWindow);
            Assert.AreEqual(ec.GetProperty("model").GetString(), claude.Model);
            Assert.AreEqual(ec.GetProperty("sessionId").GetString(), claude.SessionId);
            Assert.AreEqual(ec.GetProperty("title").GetString(), claude.Title);
            Assert.AreEqual(ec.GetProperty("messages").GetInt32(), claude.Messages);

            var codex = sessions.Single(s => s.Provider == Provider.Codex);
            var ex = e.GetProperty("codex");
            Assert.AreEqual(ex.GetProperty("folder").GetString(), codex.Folder);
            Assert.AreEqual(ex.GetProperty("project").GetString(), codex.Project);
            Assert.AreEqual(ex.GetProperty("tokens").GetInt32(), codex.Tokens);
            Assert.AreEqual(ex.GetProperty("contextTokens").GetInt32(), codex.ContextTokens);
            Assert.AreEqual(ex.GetProperty("contextWindow").GetInt32(), codex.ContextWindow);
            Assert.AreEqual(ex.GetProperty("cacheTokens").GetInt32(), codex.CacheTokens);
            Assert.AreEqual(ex.GetProperty("model").GetString(), codex.Model);
            Assert.AreEqual(ex.GetProperty("sessionId").GetString(), codex.SessionId);
            Assert.AreEqual(ex.GetProperty("title").GetString(), codex.Title);
            Assert.AreEqual(ex.GetProperty("messages").GetInt32(), codex.Messages);

            Assert.AreEqual(e.GetProperty("gemini").GetProperty("folder").GetString(),
                sessions.Single(s => s.Provider == Provider.Gemini).Folder);
            var anti = sessions.Single(s => s.Provider == Provider.Antigravity);
            Assert.AreEqual(e.GetProperty("antigravity").GetProperty("folder").GetString(), anti.Folder);
            Assert.AreEqual(e.GetProperty("antigravity").GetProperty("lastActivityEpochSeconds").GetInt64(),
                anti.LastActivity.ToUnixTimeSeconds());
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    private static void CopyTree(string from, string to)
    {
        Directory.CreateDirectory(to);
        foreach (var dir in Directory.GetDirectories(from, "*", SearchOption.AllDirectories))
            Directory.CreateDirectory(Path.Combine(to, Path.GetRelativePath(from, dir)));
        foreach (var file in Directory.GetFiles(from, "*", SearchOption.AllDirectories))
            File.Copy(file, Path.Combine(to, Path.GetRelativePath(from, file)));
    }
}
