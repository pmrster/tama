using System.Text.Json;

namespace Tama.Core;

/// <summary>Forced appearance. <see cref="System"/> follows the OS
/// (Sources/TamaCore/Settings/SettingsStore.swift:3-6).</summary>
public enum Appearance { System, Light, Dark }

/// <summary>Text-size preset. <see cref="FontSizeExtensions.Factor"/> multiplies every hardcoded
/// point size; <c>Small</c> = 1.0 so the app is pixel-identical to its original size, and the
/// presets only grow from there (SettingsStore.swift:8-19).</summary>
public enum FontSize { Small, Medium, Large }

public static class FontSizeExtensions
{
    /// <summary>Exact factors from SettingsStore.swift:13-19 — copied verbatim, not re-derived.</summary>
    public static double Factor(this FontSize size) => size switch
    {
        FontSize.Small => 1.0,
        FontSize.Medium => 1.15,
        FontSize.Large => 1.3,
        _ => 1.0,
    };
}

/// <summary>The user's persisted visual preferences (planc-ui-spec.md §5). Value type mirroring
/// Swift's SettingsStore's two properties as one unit, so Load()/Save() have a single argument.</summary>
public readonly record struct AppSettings(Appearance Appearance, FontSize FontSize)
{
    public static readonly AppSettings Default = new(Appearance.System, FontSize.Small);
}

/// <summary>
/// Persists <see cref="AppSettings"/> as JSON in the injected directory (real app →
/// %APPDATA%\Tama\settings.json; tests → a temp dir) — the same never-throw, atomic tmp+move
/// pattern as <see cref="CatStateStore"/>. This is the Windows port of
/// Sources/TamaCore/Settings/SettingsStore.swift, which is a plain UserDefaults-backed struct;
/// Windows has no UserDefaults equivalent, so a small JSON file plays that role instead. Missing
/// or malformed data falls back to <see cref="AppSettings.Default"/> field-by-field (an unknown
/// enum string for one key doesn't invalidate the other, mirroring Swift's
/// `.flatMap(Appearance.init(rawValue:)) ?? .system` per-key fallback) — never crash, never take
/// down the rest of the app over a corrupt settings file.
/// </summary>
public sealed class SettingsStore
{
    private readonly string _filePath;

    public SettingsStore(string directory) => _filePath = Path.Combine(directory, "settings.json");

    public AppSettings Load()
    {
        try
        {
            var doc = JsonDocument.Parse(File.ReadAllBytes(_filePath));
            using var _ = doc;
            if (doc.RootElement.ValueKind != JsonValueKind.Object) return AppSettings.Default;

            var appearance = doc.RootElement.TryGetProperty("appearance", out var a)
                && a.ValueKind == JsonValueKind.String
                && Enum.TryParse<Appearance>(a.GetString(), ignoreCase: true, out var parsedAppearance)
                ? parsedAppearance
                : AppSettings.Default.Appearance;

            var fontSize = doc.RootElement.TryGetProperty("fontSize", out var f)
                && f.ValueKind == JsonValueKind.String
                && Enum.TryParse<FontSize>(f.GetString(), ignoreCase: true, out var parsedFontSize)
                ? parsedFontSize
                : AppSettings.Default.FontSize;

            return new AppSettings(appearance, fontSize);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException
            or ArgumentException or NotSupportedException)
        { return AppSettings.Default; }
    }

    public void Save(AppSettings settings)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_filePath)!);
            var json = JsonSerializer.Serialize(new
            {
                appearance = settings.Appearance.ToString().ToLowerInvariant(),
                fontSize = settings.FontSize.ToString().ToLowerInvariant(),
            });
            var tmp = _filePath + ".tmp";
            File.WriteAllText(tmp, json);
            File.Move(tmp, _filePath, overwrite: true);   // atomic-ish replace
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException
            or ArgumentException or NotSupportedException)
        { /* persistence is best-effort; settings just reload as defaults next launch */ }
    }

    /// <summary>The shipped store: %APPDATA%\Tama (falls back to the temp dir, never throws).</summary>
    public static SettingsStore AppData()
    {
        var basePath = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        if (string.IsNullOrEmpty(basePath)) basePath = Path.GetTempPath();
        return new SettingsStore(Path.Combine(basePath, "Tama"));
    }
}
