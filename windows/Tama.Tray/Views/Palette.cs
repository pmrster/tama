using System.Windows;
using System.Windows.Media;
using Tama.Core;

namespace Tama.Tray.Views;

/// <summary>
/// WPF port of MenuBarView.swift's <c>Palette</c> enum (planc-ui-spec.md §2-Palette) — every hex
/// pair below is copied verbatim from that table. Light/dark-aware entries are mutable
/// <see cref="SolidColorBrush"/> instances (never frozen) so <see cref="Apply"/> can retint them
/// in place — SolidColorBrush is a Freezable, so mutating <c>Color</c> notifies everything already
/// rendering with it. XAML references them directly via <c>{x:Static views:Palette.Panel}</c>
/// (no per-lookup resource indirection needed); a <see cref="ResourceDictionary"/> mirror is also
/// kept for anything that prefers <c>{DynamicResource …}</c> keys.
///
/// System theme detection is via the registry's per-user <c>AppsUseLightTheme</c> value — no live
/// OS theme-change listener exists, so <see cref="IsSystemDark"/> is a one-shot probe (acceptable
/// per task-4-brief.md). Task 5's <c>AppSettingsViewModel</c> is now the single source of truth
/// for when <see cref="Apply"/> runs: once at startup (resolving <c>Appearance.System</c> via
/// <see cref="IsSystemDark"/> the one time) and again on every Settings change — overriding the
/// OS-follow default when the user picks Light/Dark explicitly (planc-ui-spec.md §5). Callers
/// other than <c>AppSettingsViewModel</c> must not call <see cref="Apply"/> themselves, or they
/// will silently discard the user's explicit choice back to whatever the OS says right now.
/// </summary>
public static class Palette
{
    public static readonly ResourceDictionary Resources = new();

    // Light/dark pairs (planc-ui-spec.md §2-Palette) — mutable, retinted by Apply().
    public static SolidColorBrush Panel { get; } = new();
    public static SolidColorBrush PanelEdge { get; } = new();
    public static SolidColorBrush Text { get; } = new();
    public static SolidColorBrush Dim { get; } = new();
    public static SolidColorBrush Track { get; } = new();

    // Fixed-opacity variants of the theme-aware brushes above (same Color, retinted together in
    // Apply) — the spec's `.opacity(…)` call sites that sit on long-lived static text/chrome:
    // window-toggle arrow 0.55 (§2f), legend prefix + info (?) 0.7 (§2e/§2f), folder-path row
    // 0.8 (§2c), footer-chip idle background 0.6 (§2g).
    public static SolidColorBrush Dim55 { get; } = new() { Opacity = 0.55 };
    public static SolidColorBrush Dim70 { get; } = new() { Opacity = 0.7 };
    public static SolidColorBrush Dim80 { get; } = new() { Opacity = 0.8 };
    public static SolidColorBrush PanelEdge60 { get; } = new() { Opacity = 0.6 };

    // Single-hex-both-modes accents (planc-ui-spec.md §2-Palette).
    public static readonly SolidColorBrush Yellow = Frozen(0xF3, 0xBD, 0x4F);   // Tama accent
    public static readonly SolidColorBrush Coral = Frozen(0xD9, 0x77, 0x57);    // Claude Code tint
    public static readonly SolidColorBrush Green = Frozen(0x10, 0xA3, 0x7F);    // Codex tint
    public static readonly SolidColorBrush Blue = Frozen(0x42, 0x85, 0xF4);     // Gemini tint
    public static readonly SolidColorBrush Purple = Frozen(0x9B, 0x8A, 0xFB);   // Antigravity tint
    public static readonly SolidColorBrush Warn = Frozen(0xE5, 0x48, 0x4D);     // context >= 90% full

    /// <summary>Warn at 0.14 opacity — the destructive footer chip's hover pill (§2g).</summary>
    public static readonly SolidColorBrush WarnPill = FrozenWithOpacity(0xE5, 0x48, 0x4D, 0.14);

    /// <summary>Coral at 0.18 opacity — the Settings window's Close button background (§5.6).</summary>
    public static readonly SolidColorBrush CoralPill = FrozenWithOpacity(0xD9, 0x77, 0x57, 0.18);

    static Palette()
    {
        Resources["Panel"] = Panel;
        Resources["PanelEdge"] = PanelEdge;
        Resources["Text"] = Text;
        Resources["Dim"] = Dim;
        Resources["Track"] = Track;
        Resources["Yellow"] = Yellow;
        Resources["Coral"] = Coral;
        Resources["Green"] = Green;
        Resources["Blue"] = Blue;
        Resources["Purple"] = Purple;
        Resources["Warn"] = Warn;
        Apply(IsSystemDark());
    }

    /// <summary>Retints every light/dark-aware brush in place (planc-ui-spec.md §2-Palette).</summary>
    public static void Apply(bool dark)
    {
        Panel.Color = dark ? Rgb(0x1C, 0x1A, 0x17) : Rgb(0xF7, 0xF4, 0xEF);
        PanelEdge.Color = dark ? Rgb(0x2A, 0x26, 0x20) : Rgb(0xE0, 0xDA, 0xD0);
        Text.Color = dark ? Rgb(0xED, 0xE6, 0xDC) : Rgb(0x1C, 0x1A, 0x17);
        Dim.Color = dark ? Rgb(0x9A, 0x8F, 0x84) : Rgb(0x6E, 0x65, 0x5C);
        Track.Color = dark ? Rgb(0x3A, 0x35, 0x2E) : Rgb(0xD8, 0xD2, 0xC8);
        Dim55.Color = Dim.Color;
        Dim70.Color = Dim.Color;
        Dim80.Color = Dim.Color;
        PanelEdge60.Color = PanelEdge.Color;
    }

    /// <summary>Provider tint lookup (MenuBarView.swift:67-74, providerTint).</summary>
    public static SolidColorBrush Tint(Provider provider) => provider switch
    {
        Provider.ClaudeCode => Coral,
        Provider.Codex => Green,
        Provider.Gemini => Blue,
        Provider.Antigravity => Purple,
        _ => Dim,
    };

    /// <summary>Windows has no live "appearance changed" push notification as simple as AppKit's
    /// NSApp.effectiveAppearance; reading the registry value once at process start is the
    /// documented, acceptable stand-in for Task 4 (task-4-brief.md's own architecture note).</summary>
    public static bool IsSystemDark()
    {
        try
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("AppsUseLightTheme") is int v && v == 0;
        }
        catch (Exception ex) when (ex is System.Security.SecurityException or System.IO.IOException or UnauthorizedAccessException)
        {
            return false;   // default to light, matching Swift's Appearance.system-with-no-signal fallback
        }
    }

    private static System.Windows.Media.Color Rgb(byte r, byte g, byte b) =>
        System.Windows.Media.Color.FromRgb(r, g, b);   // fully qualified vs System.Drawing.Color (CS0104)

    private static SolidColorBrush Frozen(byte r, byte g, byte b)
    {
        var brush = new SolidColorBrush(Rgb(r, g, b));
        brush.Freeze();
        return brush;
    }

    private static SolidColorBrush FrozenWithOpacity(byte r, byte g, byte b, double opacity)
    {
        var brush = new SolidColorBrush(Rgb(r, g, b)) { Opacity = opacity };
        brush.Freeze();
        return brush;
    }
}
