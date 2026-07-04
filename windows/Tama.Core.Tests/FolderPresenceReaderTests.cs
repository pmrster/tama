using Tama.Core;

namespace Tama.Core.Tests;

[TestClass]
public sealed class FolderPresenceReaderTests
{
    private string _root = null!;

    [TestInitialize]
    public void SetUp()
    {
        _root = Path.Combine(Path.GetTempPath(), "fp-" + Guid.NewGuid());
        Directory.CreateDirectory(_root);
    }

    [TestCleanup]
    public void TearDown() => Directory.Delete(_root, recursive: true);

    [TestMethod]
    public void Gemini_reads_project_root_and_uses_logs_json_mtime()
    {
        var hash = Path.Combine(_root, "hash1");
        Directory.CreateDirectory(hash);
        File.WriteAllText(Path.Combine(hash, ".project_root"), "/Example/Code/site\n");
        var logs = Path.Combine(hash, "logs.json");
        File.WriteAllText(logs, "[]");
        var stamp = new DateTime(2026, 6, 19, 12, 0, 0, DateTimeKind.Utc);
        File.SetLastWriteTimeUtc(logs, stamp);

        var sessions = GeminiReader.Read(_root);
        Assert.AreEqual(1, sessions.Count);
        Assert.AreEqual("/Example/Code/site", sessions[0].Folder);   // trimmed
        Assert.AreEqual(new DateTimeOffset(stamp), sessions[0].LastActivity);
    }

    /// <summary>Task-6 carry-forward: when `logs.json` is absent, LastActivity falls back to the
    /// hash directory's own mtime rather than being skipped or defaulting to "now" (GeminiReader.MTime
    /// tries the file first, then the directory).</summary>
    [TestMethod]
    public void Gemini_falls_back_to_directory_mtime_when_logs_json_is_absent()
    {
        var hash = Path.Combine(_root, "hash-no-logs-json");
        Directory.CreateDirectory(hash);
        File.WriteAllText(Path.Combine(hash, ".project_root"), "/Example/Code/other\n");
        var stamp = new DateTime(2026, 6, 20, 8, 30, 0, DateTimeKind.Utc);
        Directory.SetLastWriteTimeUtc(hash, stamp);

        var sessions = GeminiReader.Read(_root);
        Assert.AreEqual(1, sessions.Count);
        Assert.AreEqual("/Example/Code/other", sessions[0].Folder);
        Assert.AreEqual(new DateTimeOffset(stamp), sessions[0].LastActivity);
        Assert.IsFalse(File.Exists(Path.Combine(hash, "logs.json")));
    }

    [TestMethod]
    public void Gemini_skips_dirs_with_empty_or_missing_project_root()
    {
        Directory.CreateDirectory(Path.Combine(_root, "empty"));
        var blank = Path.Combine(_root, "blank");
        Directory.CreateDirectory(blank);
        File.WriteAllText(Path.Combine(blank, ".project_root"), "   \n");
        Assert.AreEqual(0, GeminiReader.Read(_root).Count);
    }

    [TestMethod]
    public void Gemini_missing_tmp_dir_returns_empty()
    {
        Assert.AreEqual(0, GeminiReader.Read(Path.Combine(_root, "nope")).Count);
    }

    [TestMethod]
    public void Antigravity_dedupes_workspaces_keeping_max_timestamp()
    {
        var history = Path.Combine(_root, "history.jsonl");
        File.WriteAllText(history, string.Join("\n",
            "{\"workspace\":\"/Example/Code/api\",\"timestamp\":1781856000000}",
            "{\"workspace\":\"/Example/Code/api\",\"timestamp\":1781859600000}",
            "{\"workspace\":\"/Example/Code/web\",\"timestamp\":1781850000000}",
            "not json"));
        var sessions = AntigravityReader.Read(history)
            .OrderBy(s => s.Folder, StringComparer.Ordinal).ToList();
        Assert.AreEqual(2, sessions.Count);
        Assert.AreEqual("/Example/Code/api", sessions[0].Folder);
        Assert.AreEqual(DateTimeOffset.FromUnixTimeMilliseconds(1781859600000), sessions[0].LastActivity);
        Assert.AreEqual("/Example/Code/web", sessions[1].Folder);
    }

    [TestMethod]
    public void Antigravity_missing_file_returns_empty()
    {
        Assert.AreEqual(0, AntigravityReader.Read(Path.Combine(_root, "nope.jsonl")).Count);
    }
}
