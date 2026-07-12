using System.Text.Json;

namespace Tama.Core;

/// <summary>
/// Persists the cat's own CatState as JSON in the injected directory (real app → %APPDATA%\Tama;
/// tests → a temp dir). This is the app's ONLY write, strictly inside that directory — never in
/// any agent log tree. Missing/malformed files fall back to Initial and never crash.
/// </summary>
public sealed class CatStateStore
{
    private readonly string _filePath;

    public CatStateStore(string directory) =>
        _filePath = Path.Combine(directory, "cat-state.json");

    public CatState Load()
    {
        try
        {
            var doc = JsonDocument.Parse(File.ReadAllBytes(_filePath));
            using var _ = doc;
            if (doc.RootElement.ValueKind != JsonValueKind.Object) return CatState.Initial;
            if (doc.RootElement.TryGetProperty("lastSeenDay", out var v)
                && v.ValueKind == JsonValueKind.String
                && DateTimeOffset.TryParse(v.GetString(), out var d))
                return new CatState(d);
            return CatState.Initial;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException
            or ArgumentException or NotSupportedException)
        { return CatState.Initial; }
    }

    public void Save(CatState state)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_filePath)!);
            var json = JsonSerializer.Serialize(new
            {
                lastSeenDay = state.LastSeenDay?.ToString("O"),
            });
            var tmp = _filePath + ".tmp";
            File.WriteAllText(tmp, json);
            File.Move(tmp, _filePath, overwrite: true);   // atomic-ish replace
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException
            or ArgumentException or NotSupportedException)
        { /* persistence is best-effort; mood still works from Initial next launch */ }
    }

    /// <summary>The shipped store: %APPDATA%\Tama (falls back to the temp dir, never throws).</summary>
    public static CatStateStore AppData()
    {
        var basePath = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        if (string.IsNullOrEmpty(basePath)) basePath = Path.GetTempPath();
        return new CatStateStore(Path.Combine(basePath, "Tama"));
    }
}
