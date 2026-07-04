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

/// <summary>A top-level window's position + size, persisted so the pinned window "remembers frame"
/// across pin/unpin cycles and app relaunches (planc-ui-spec.md §1b: mac's PinnedPanel reuses
/// whatever frame the user last left it at; there is no Windows/WPF equivalent of NSPanel's own
/// frame autosave, so this plays that role via <see cref="SettingsStore"/>).</summary>
public readonly record struct WindowFrame(double X, double Y, double Width, double Height);

/// <summary>The user's persisted visual preferences (planc-ui-spec.md §5). Value type mirroring
/// Swift's SettingsStore's two properties as one unit, so Load()/Save() have a single argument.
/// <see cref="PinnedFrame"/> is null until the pinned window has been shown at least once (spec
/// §1b: "centered on first presentation only").</summary>
public readonly record struct AppSettings(Appearance Appearance, FontSize FontSize, WindowFrame? PinnedFrame = null)
{
    public static readonly AppSettings Default = new(Appearance.System, FontSize.Small, null);
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
                && Enum.IsDefined(typeof(Appearance), parsedAppearance)
                ? parsedAppearance
                : AppSettings.Default.Appearance;

            var fontSize = doc.RootElement.TryGetProperty("fontSize", out var f)
                && f.ValueKind == JsonValueKind.String
                && Enum.TryParse<FontSize>(f.GetString(), ignoreCase: true, out var parsedFontSize)
                && Enum.IsDefined(typeof(FontSize), parsedFontSize)
                ? parsedFontSize
                : AppSettings.Default.FontSize;

            var pinnedFrame = ParseFrame(doc.RootElement);

            return new AppSettings(appearance, fontSize, pinnedFrame);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException
            or ArgumentException or NotSupportedException)
        { return AppSettings.Default; }
    }

    /// <summary>A malformed/partial "pinnedFrame" object (missing field, wrong type) falls back to
    /// null rather than a half-populated frame — same never-throw, field-by-field-independent
    /// fallback contract as appearance/fontSize above.</summary>
    private static WindowFrame? ParseFrame(JsonElement root)
    {
        if (!root.TryGetProperty("pinnedFrame", out var f) || f.ValueKind != JsonValueKind.Object)
            return null;
        if (f.TryGetProperty("x", out var x) && x.ValueKind == JsonValueKind.Number
            && f.TryGetProperty("y", out var y) && y.ValueKind == JsonValueKind.Number
            && f.TryGetProperty("width", out var w) && w.ValueKind == JsonValueKind.Number
            && f.TryGetProperty("height", out var h) && h.ValueKind == JsonValueKind.Number)
            return new WindowFrame(x.GetDouble(), y.GetDouble(), w.GetDouble(), h.GetDouble());
        return null;
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
                pinnedFrame = settings.PinnedFrame is { } pf
                    ? new { x = pf.X, y = pf.Y, width = pf.Width, height = pf.Height }
                    : null,
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
