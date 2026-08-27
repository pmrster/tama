using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Tama.Core.Ui;
// Several WinForms types brought into scope by UseWindowsForms's implicit usings collide with
// same-named WPF types/members (CS0104) or with FrameworkElement's own instance properties
// (CS0120/CS0176 when an unqualified type name matches an inherited property name, e.g.
// FrameworkElement.HorizontalAlignment) — alias/fully-qualify throughout this file rather than
// `using System.Windows;`/`using System.Windows.Forms;` wholesale, same pattern as Palette.cs's
// and TrayIcon.cs's own CS0104 notes.
using AppAppearance = Tama.Core.Appearance;
using AppFontSize = Tama.Core.FontSize;

namespace Tama.Tray.Views;

/// <summary>
/// WPF port of SettingsView.swift (planc-ui-spec.md §5), hosted per §1c's fixed-size,
/// non-resizable, always-on-top utility window shape (mac's Settings/About NSPanels: no
/// `.resizable`, `hidesOnDeactivate = false`, `isReleasedWhenClosed = false`). Reused across
/// opens: <see cref="Window.Closing"/> hides rather than destroys the window, so
/// <c>Program.cs</c> constructs one instance and shows/reactivates it every time the tray menu's
/// "Settings" item is clicked — unlike the transient popover, this window does not close on
/// focus loss.
/// </summary>
public partial class SettingsWindow : Window
{
    private readonly AppSettingsViewModel _vm;
    private readonly List<(Border Border, AppAppearance Value)> _appearanceSegments = new();
    private readonly List<(Border Border, AppFontSize Value)> _fontSizeSegments = new();
    private bool _closeForReal;

    public SettingsWindow(AppSettingsViewModel vm)
    {
        InitializeComponent();
        _vm = vm;

        BuildAppearancePicker();
        BuildFontSizePicker();
        RenderFloatingCat();
        RenderPreview();

        _vm.PropertyChanged += Vm_PropertyChanged;
        Closing += SettingsWindow_Closing;
    }

    /// <summary>Lets Program.cs release the window for real on app shutdown instead of just
    /// hiding it (symmetry with the hide-not-destroy reuse path below, not load-bearing since the
    /// process is exiting either way).</summary>
    public void CloseForReal()
    {
        _closeForReal = true;
        Close();
    }

    private void SettingsWindow_Closing(object? sender, CancelEventArgs e)
    {
        if (_closeForReal) return;
        e.Cancel = true;
        Hide();
    }

    private void Vm_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        RefreshAppearanceHighlight();
        RefreshFontSizeHighlight();
        RenderFloatingCat();
        RenderPreview();
    }

    private void Close_Click(object sender, System.Windows.Input.MouseButtonEventArgs e) => Hide();

    // ---- APPEARANCE segmented picker ----

    private void BuildAppearancePicker()
    {
        AddAppearanceSegment("System", AppAppearance.System);
        AddAppearanceSegment("Light", AppAppearance.Light);
        AddAppearanceSegment("Dark", AppAppearance.Dark);
        RefreshAppearanceHighlight();
    }

    private void AddAppearanceSegment(string label, AppAppearance value)
    {
        var border = MakeSegment(label);
        border.MouseLeftButtonDown += (_, _) => _vm.Appearance = value;
        _appearanceSegments.Add((border, value));
        AppearancePanel.Children.Add(border);
    }

    private void RefreshAppearanceHighlight() => RefreshHighlight(_appearanceSegments, _vm.Appearance);

    // ---- TEXT SIZE segmented picker ----

    private void BuildFontSizePicker()
    {
        AddFontSizeSegment("S", AppFontSize.Small);
        AddFontSizeSegment("M", AppFontSize.Medium);
        AddFontSizeSegment("L", AppFontSize.Large);
        RefreshFontSizeHighlight();
    }

    private void AddFontSizeSegment(string label, AppFontSize value)
    {
        var border = MakeSegment(label);
        border.MouseLeftButtonDown += (_, _) => _vm.FontSize = value;
        _fontSizeSegments.Add((border, value));
        FontSizePanel.Children.Add(border);
    }

    private void RefreshFontSizeHighlight() => RefreshHighlight(_fontSizeSegments, _vm.FontSize);

    // ---- WIDGET: "Show floating cat" ☑/☐ (same idiom as DashboardView's launch-at-login row) ----

    private void FloatingCat_Click(object sender, System.Windows.Input.MouseButtonEventArgs e) =>
        _vm.FloatingCatVisible = !_vm.FloatingCatVisible;

    private void RenderFloatingCat()
    {
        var on = _vm.FloatingCatVisible;
        FloatingCatIcon.Text = on ? "☑" : "☐";
        FloatingCatIcon.Foreground = on ? Palette.Yellow : Palette.Dim;
    }

    // ---- shared segmented-control plumbing ----

    private static Border MakeSegment(string label)
    {
        var border = new Border
        {
            CornerRadius = new CornerRadius(6),
            Padding = new Thickness(10, 4, 10, 4),
            Margin = new Thickness(0, 0, 4, 0),
            Cursor = System.Windows.Input.Cursors.Hand,
        };
        border.Child = new TextBlock
        {
            Text = label,
            FontSize = 11,
            FontWeight = FontWeights.SemiBold,
            HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
        };
        return border;
    }

    private static void RefreshHighlight<T>(List<(Border Border, T Value)> segments, T selected)
    {
        foreach (var (border, value) in segments)
        {
            var isSelected = EqualityComparer<T>.Default.Equals(value, selected);
            border.Background = isSelected ? Palette.PanelEdge : System.Windows.Media.Brushes.Transparent;
            ((TextBlock)border.Child).Foreground = isSelected ? Palette.Text : Palette.Dim;
        }
    }

    // ---- §5.4 PREVIEW: live-scaled by the current FontScale, background re-derived from the
    // (possibly just-retinted) Palette.PanelEdge color so it tracks theme changes too ----

    private void RenderPreview()
    {
        PreviewAgentsText.FontSize = 13 * _vm.FontScale;
        PreviewUsageText.FontSize = 11 * _vm.FontScale;
        PreviewBox.Background = new SolidColorBrush(Palette.PanelEdge.Color) { Opacity = 0.5 };
    }
}
