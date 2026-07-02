using System.Text;
using System.Text.Json;

namespace Tama.Core;

/// <summary>A provider session known only by folder + recency (no token data).</summary>
public readonly record struct FolderSession(string Folder, DateTimeOffset LastActivity);

/// <summary>
/// Gemini CLI: one session per &lt;gemini-root&gt;/tmp/&lt;hash&gt;/ subdirectory. Folder = trimmed
/// content of `.project_root` (≤ 8 KiB; empty → skip); last activity = `logs.json` mtime,
/// else the subdirectory's mtime. Mirror of the Swift geminiSessions.
/// </summary>
public static class GeminiReader
{
    public static IReadOnlyList<FolderSession> Read(string tmpDir)
    {
        var result = new List<FolderSession>();
        string[] dirs;
        try { dirs = Directory.GetDirectories(tmpDir); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
        { return result; }
        foreach (var dir in dirs)
        {
            if (!SafeFileReader.IsSafeDirectory(dir)) continue;
            var rootFile = Path.Combine(dir, ".project_root");
            var data = SafeFileReader.ReadData(rootFile, SafeFileReader.MaxMetadataBytes);
            if (data is null) continue;
            var folder = Encoding.UTF8.GetString(data).Trim();
            if (folder.Length == 0) continue;
            var last = MTime(Path.Combine(dir, "logs.json")) ?? MTime(dir);
            if (last is null) continue;
            result.Add(new FolderSession(folder, last.Value));
        }
        return result;
    }

    private static DateTimeOffset? MTime(string path)
    {
        try
        {
            if (File.Exists(path))
                return new DateTimeOffset(File.GetLastWriteTimeUtc(path), TimeSpan.Zero);
            if (Directory.Exists(path))
                return new DateTimeOffset(Directory.GetLastWriteTimeUtc(path), TimeSpan.Zero);
            return null;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
        { return null; }
    }
}

/// <summary>
/// Antigravity: &lt;gemini-root&gt;/antigravity-cli/history.jsonl, lines
/// {"workspace":path,"timestamp":msEpoch} (≤ 16 MiB). One session per distinct workspace,
/// last activity = max timestamp. Mirror of the Swift antigravitySessions.
/// </summary>
public static class AntigravityReader
{
    public static IReadOnlyList<FolderSession> Read(string historyFile)
    {
        var byFolder = new Dictionary<string, DateTimeOffset>();
        var data = SafeFileReader.ReadData(historyFile, SafeFileReader.MaxHistoryBytes);
        if (data is null) return Array.Empty<FolderSession>();
        SafeFileReader.ForEachLine(data, line =>
        {
            JsonDocument doc;
            try { doc = JsonDocument.Parse(line); }
            catch (JsonException) { return; }
            using var _ = doc;
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return;
            if (!root.TryGetProperty("workspace", out var ws) || ws.ValueKind != JsonValueKind.String
                || ws.GetString() is not { Length: > 0 } folder) return;
            if (!root.TryGetProperty("timestamp", out var ts) || ts.ValueKind != JsonValueKind.Number
                || !ts.TryGetDouble(out var ms)) return;
            var date = DateTimeOffset.FromUnixTimeMilliseconds((long)ms);
            if (byFolder.TryGetValue(folder, out var existing) && existing >= date) return;
            byFolder[folder] = date;
        });
        return byFolder.Select(kv => new FolderSession(kv.Key, kv.Value)).ToList();
    }
}
