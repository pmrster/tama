using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using Tama.Core;
using Tama.Core.Ui;

namespace Tama.Tray.Views;

/// <summary>
/// WPF port of DashboardView.swift (planc-ui-spec.md §2/§3/§4) — the popover's real content.
/// Binds directly to a long-lived <see cref="DashboardViewModel"/> (constructed once alongside
/// AgentMonitor in Program.cs, NOT per popover open/close — see that class's doc comment for why).
/// <see cref="_ollamaCollapsed"/> is deliberately kept here instead of in the VM, mirroring the
/// Swift source's per-view @State that resets on every re-host (spec §4/§7 note 7).
/// The "Launch at login" checkbox is chrome-only for now: Task 6 owns the real read/write behind
/// an <c>IRunAtLogin</c> interface (task-6-brief.md); no registry access happens from this view.
/// </summary>
public partial class DashboardView : System.Windows.Controls.UserControl   // fully qualified: UseWPF+UseWindowsForms both export a UserControl (CS0104)
{
    private DashboardViewModel? _vm;
    private Action? _onAbout;
    private Action? _onQuit;
    private bool _ollamaCollapsed;

    public DashboardView()
    {
        InitializeComponent();
        BuildLegend();
        BuildInfoPopover();
        RenderLaunchAtLogin();
    }

    /// <summary>Wires the view to its (shared, long-lived) view model and the two footer actions
    /// that live one level up in Program.cs (About/Quit — see PopoverWindow).</summary>
    public void Initialize(DashboardViewModel vm, Action onAbout, Action onQuit)
    {
        _vm = vm;
        _onAbout = onAbout;
        _onQuit = onQuit;
        DataContext = vm;
        vm.PropertyChanged += (_, _) => Pet.SetMood(vm.Mood);
        Pet.SetMood(vm.Mood);
    }

    private DashboardViewModel Vm => _vm ?? throw new InvalidOperationException("DashboardView.Initialize was not called.");

    // ---- header ----

    private void MetricCycle_Click(object sender, RoutedEventArgs e) => Vm.CycleDefaultMetric();
    private void ActiveOnly_Click(object sender, RoutedEventArgs e) => Vm.ActiveOnly = !Vm.ActiveOnly;
    private void ExpandCollapseAll_Click(object sender, RoutedEventArgs e) => Vm.ExpandOrCollapseAll();
    private void Refresh_Click(object sender, RoutedEventArgs e) => Vm.RefreshNow();

    // ---- tree rows (each handler reads the row VM off the sender's DataContext) ----

    private void ProviderRow_Click(object sender, MouseButtonEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is ProviderRowVm row) Vm.ToggleProviderCollapsed(row.Provider);
    }

    private void FolderRow_Click(object sender, MouseButtonEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is FolderRowVm row) Vm.ToggleFolderExpanded(row.FolderKey);
    }

    /// <summary>The project-name text has its own, narrower tap target (path reveal) nested
    /// inside the folder row's own tap target (expand/collapse) — mirrors the Swift source's
    /// overlapping Button + onTapGesture (MenuBarView.swift:454-457). Marking the event handled
    /// stops it from also toggling the folder's expand state.</summary>
    private void FolderProject_Click(object sender, MouseButtonEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is FolderRowVm row) Vm.ToggleRevealedPath(row.FolderKey);
        e.Handled = true;
    }

    private void FolderMetric_Click(object sender, MouseButtonEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is FolderRowVm row) Vm.CycleMetric("F:" + row.FolderKey);
        e.Handled = true;
    }

    private void GroupRow_Click(object sender, MouseButtonEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is SessionGroupRowVm row) Vm.ToggleGroupExpanded(row.GroupKey);
    }

    private void GroupMetric_Click(object sender, MouseButtonEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is SessionGroupRowVm row) Vm.CycleMetric("G:" + row.GroupKey);
        e.Handled = true;
    }

    private void LeafMetric_Click(object sender, MouseButtonEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is SessionLeafRowVm row) Vm.CycleMetric(row.SessionKey);
        e.Handled = true;
    }

    // ---- Ollama strip ----

    /// <summary>Local, non-persisted state (spec §4: "not persisted in UIState.shared … resets on
    /// every panel re-hosting") — resets naturally because this whole DashboardView is
    /// reconstructed each time the (transient) popover reopens.</summary>
    private void OllamaHeader_Click(object sender, MouseButtonEventArgs e)
    {
        _ollamaCollapsed = !_ollamaCollapsed;
        OllamaChevron.Text = _ollamaCollapsed ? "▸" : "▾";
        OllamaBody.Visibility = _ollamaCollapsed ? Visibility.Collapsed : Visibility.Visible;
    }

    // ---- TODAY bar ----

    private void WindowToggle_Click(object sender, MouseButtonEventArgs e) =>
        Vm.Window = Vm.Window == TokenWindow.Today ? TokenWindow.Last24h : TokenWindow.Today;

    private void InfoButton_Click(object sender, RoutedEventArgs e) => InfoPopup.IsOpen = !InfoPopup.IsOpen;

    // ---- footer ----

    private void About_Click(object sender, MouseButtonEventArgs e) => _onAbout?.Invoke();
    private void Quit_Click(object sender, MouseButtonEventArgs e) => _onQuit?.Invoke();

    /// <summary>Task 6 owns the real on/off state (via IRunAtLogin); until then this always
    /// renders unchecked/dim — the checkbox itself is IsEnabled="False" in XAML.</summary>
    private void RenderLaunchAtLogin()
    {
        LaunchAtLoginIcon.Text = "☐";
        LaunchAtLoginIcon.Foreground = Palette.Dim;
    }

    // ---- static text built from the VM's own constants, so it can never drift from them ----

    private void BuildLegend()
    {
        LegendText.Inlines.Add(new Run(DashboardViewModel.LegendPrefix) { Foreground = DimBrush(0.7) });
        foreach (var (name, descWithSeparator) in DashboardViewModel.LegendPieces)
        {
            LegendText.Inlines.Add(new Run(name + " ") { Foreground = Palette.Yellow });
            LegendText.Inlines.Add(new Run(descWithSeparator) { Foreground = Palette.Dim });
        }
    }

    private void BuildInfoPopover()
    {
        InfoTitle.Text = DashboardViewModel.InfoPopoverTitle;
        foreach (var (name, desc) in DashboardViewModel.InfoRows)
        {
            var block = new StackPanel { Margin = new Thickness(0, 0, 0, 6) };
            block.Children.Add(new TextBlock
            {
                Text = name, FontFamily = new System.Windows.Media.FontFamily("Consolas"), FontWeight = FontWeights.Black,
                FontSize = 9.5, Foreground = Palette.Yellow,
            });
            block.Children.Add(new TextBlock
            {
                Text = desc, FontSize = 10, Foreground = Palette.Dim, TextWrapping = TextWrapping.Wrap,
            });
            InfoRowsPanel.Children.Add(block);
        }
    }

    private static SolidColorBrush DimBrush(double opacity)
    {
        var brush = Palette.Dim.Clone();
        brush.Opacity = opacity;
        return brush;
    }
}
