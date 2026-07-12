using System.Globalization;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media;
using Tama.Core;
using Tama.Core.Ui;

namespace Tama.Tray.Views;

/// <summary>
/// Value converters gluing DashboardViewModel's framework-free display rows to WPF brushes.
/// Every brush returned here IS one of Palette's own theme-aware brushes (Palette.Tint /
/// Palette.Dim / Palette.Warn / …) — these converters never construct a new Color, so
/// DashboardView.xaml never hardcodes a hex value of its own (planc-ui-spec.md §2-Palette).
/// </summary>
public static class Converters
{
    public static readonly IValueConverter ProviderTint = new ProviderTintConverter();
    public static readonly IValueConverter PositiveCountAccent = new PositiveCountAccentConverter();
    public static readonly IValueConverter BoolAccent = new BoolAccentConverter();
    public static readonly IValueConverter BoolAccentPill = new BoolAccentPillConverter();
    public static readonly IValueConverter OllamaDot = new OllamaDotConverter();
    public static readonly IValueConverter NullToVisible = new NullToVisibleConverter();
    public static readonly IValueConverter Chevron = new ChevronConverter();
    public static readonly IMultiValueConverter LiveDot = new LiveDotConverter();
    public static readonly IMultiValueConverter MetricBrush = new MetricBrushConverter();
    public static readonly IMultiValueConverter WarnTint = new WarnTintConverter();
    public static readonly IValueConverter GaugeWidth = new GaugeWidthConverter();
    public static readonly IValueConverter ProviderTintPill = new ProviderTintPillConverter();
    public static readonly IValueConverter LeafIndent = new LeafIndentConverter();
    public static readonly IValueConverter ExpandGlyph = new ExpandGlyphConverter();
    public static readonly IMultiValueConverter OllamaGaugeBrush = new OllamaGaugeBrushConverter();
}

internal sealed class ProviderTintConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is Provider p ? Palette.Tint(p) : Palette.Dim;
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

/// <summary>int > 0 -> Yellow, else Dim (header active-now dot, spec §2a:331).</summary>
internal sealed class PositiveCountAccentConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is int n && n > 0 ? Palette.Yellow : Palette.Dim;
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

/// <summary>bool -> Yellow (true) / Dim (false) — Ollama busy dot, active-only bolt icon.</summary>
internal sealed class BoolAccentConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is true ? Palette.Yellow : Palette.Dim;
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

/// <summary>bool -> Yellow at 0.16 opacity (true) / Transparent (false) — the active-only filter's
/// pill background (MenuBarView.swift:359, "Palette.yellow.opacity(0.16)").</summary>
internal sealed class BoolAccentPillConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is not true) return System.Windows.Media.Brushes.Transparent;   // CS0104 vs System.Drawing.Brushes
        var pill = Palette.Yellow.Clone();
        pill.Opacity = 0.16;
        return pill;
    }
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

/// <summary>Ollama per-model status dot: busy -> yellow, active(within 15m) -> green, else dim
/// (spec §4, ollamaModelRow).</summary>
internal sealed class OllamaDotConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) => value switch
    {
        OllamaDotState.Busy => Palette.Yellow,
        OllamaDotState.Active => Palette.Green,
        _ => Palette.Dim,
    };
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

/// <summary>Non-null/non-empty -> Visible, else Collapsed (optional cost chips, model badges, …).</summary>
internal sealed class NullToVisibleConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is null || (value is string s && s.Length == 0) ? Visibility.Collapsed : Visibility.Visible;
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

/// <summary>Expanded bool -> chevron glyph ("v" expanded / ">" collapsed) — SF Symbols
/// chevron.down/chevron.right have no WPF glyph equivalent (spec §7 note 10); a plain Segoe UI
/// Symbol character is the pragmatic stand-in.</summary>
internal sealed class ChevronConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is true ? "▾" : "▸";   // ▾ expanded / ▸ collapsed
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

/// <summary>[bool Live, Provider] -> provider tint when live, else Palette.Dim at the given
/// opacity (ConverterParameter — e.g. "0.35" folders / "0.3" groups+leaves, spec §2c/§3a/§3c).</summary>
internal sealed class LiveDotConverter : IMultiValueConverter
{
    public object Convert(object[] values, Type targetType, object parameter, CultureInfo culture)
    {
        var live = values.Length > 0 && values[0] is true;
        var provider = values.Length > 1 && values[1] is Provider p ? p : Provider.ClaudeCode;
        if (live) return Palette.Tint(provider);
        var opacity = parameter is string s && double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out var d) ? d : 0.3;
        var dim = Palette.Dim.Clone();
        dim.Opacity = opacity;
        return dim;
    }
    public object[] ConvertBack(object value, Type[] targetTypes, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

/// <summary>[string MetricText, Provider, (optional) bool Warn] -> Dim when the text is the
/// "no data" dash, Palette.Warn when the (ctx) gauge is >= 90% full, else the provider tint
/// (MenuBarView.swift:843-852 metricText + :643 gauge number coloring).</summary>
internal sealed class MetricBrushConverter : IMultiValueConverter
{
    public object Convert(object[] values, Type targetType, object parameter, CultureInfo culture)
    {
        var text = values.Length > 0 ? values[0] as string : null;
        var provider = values.Length > 1 && values[1] is Provider p ? p : Provider.ClaudeCode;
        if (text == "—") return Palette.Dim;
        if (values.Length > 2 && values[2] is true) return Palette.Warn;
        return Palette.Tint(provider);
    }
    public object[] ConvertBack(object value, Type[] targetTypes, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

/// <summary>[bool Warn, Provider] -> Palette.Warn when the context gauge is >= 90% full, else the
/// provider tint (spec §3b).</summary>
internal sealed class WarnTintConverter : IMultiValueConverter
{
    public object Convert(object[] values, Type targetType, object parameter, CultureInfo culture)
    {
        var warn = values.Length > 0 && values[0] is true;
        var provider = values.Length > 1 && values[1] is Provider p ? p : Provider.ClaudeCode;
        return warn ? Palette.Warn : Palette.Tint(provider);
    }
    public object[] ConvertBack(object value, Type[] targetTypes, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

/// <summary>double? fraction * ConverterParameter (track width, e.g. "18" session / "16" ollama)
/// clamped to a minimum of 2 (spec §3b: `max(2, 18 * frac)`).</summary>
internal sealed class GaugeWidthConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        var frac = value as double?;
        var track = parameter is string s && double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out var d) ? d : 18.0;
        return frac is { } f ? Math.Max(2.0, track * f) : 0.0;
    }
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

/// <summary>Provider -> tint at 0.16 opacity — the model-badge pill background
/// ("tint.opacity(0.16), in: Capsule()", MenuBarView.swift:575/:521).</summary>
internal sealed class ProviderTintPillConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        var tint = value is Provider p ? Palette.Tint(p) : Palette.Dim;
        var pill = tint.Clone();
        pill.Opacity = 0.16;
        return pill;
    }
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

/// <summary>Nested bool -> leaf row left margin: 13+30 = 43 plain, +14 = 57 when nested inside an
/// expanded same-prompt group (spec §3a `.padding(.leading, 30)` inside the 13pt-indented folder
/// block; §3c children additionally `.padding(.leading, 14)`).</summary>
internal sealed class LeafIndentConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is true ? new Thickness(57, 0, 0, 2) : new Thickness(43, 0, 0, 2);
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

/// <summary>AnyFolderExpanded -> the expand/collapse-all glyph (Segoe MDL2 Assets: BackToWindow
/// E73F when anything is expanded / FullScreen E740 when all collapsed — standing in for SF's
/// arrow.down.right.and.arrow.up.left / arrow.up.left.and.arrow.down.right, spec §2a).</summary>
internal sealed class ExpandGlyphConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is true ? "\uE73F" : "\uE740";
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

/// <summary>[bool ContextWarn, OllamaDotState] -> gauge fill: Warn when >= 90% full, else the same
/// busy/active/idle tint as the row's status dot (spec §4 item 3).</summary>
internal sealed class OllamaGaugeBrushConverter : IMultiValueConverter
{
    public object Convert(object[] values, Type targetType, object parameter, CultureInfo culture)
    {
        if (values.Length > 0 && values[0] is true) return Palette.Warn;
        return values.Length > 1 && values[1] is OllamaDotState dot
            ? dot switch
            {
                OllamaDotState.Busy => Palette.Yellow,
                OllamaDotState.Active => Palette.Green,
                _ => Palette.Dim,
            }
            : Palette.Dim;
    }
    public object[] ConvertBack(object value, Type[] targetTypes, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}
