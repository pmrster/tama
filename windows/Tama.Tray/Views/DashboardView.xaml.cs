using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using Tama.Core;
using Tama.Core.Ui;

namespace Tama.Tray.Views;

/// <summary>
/// WPF port of DashboardView.swift (planc-ui-spec.md §2/§3/§4) — the popover's real content, also
/// reused verbatim (same class, a separate instance) by <see cref="PinnedWindow"/>. Binds directly
/// to a long-lived <see cref="DashboardViewModel"/> (constructed once alongside AgentMonitor in
/// Program.cs, NOT per popover open/close — see that class's doc comment for why).
/// <see cref="_ollamaCollapsed"/> is deliberately kept here instead of in the VM, mirroring the
/// Swift source's per-view @State that resets on every re-host (spec §4/§7 note 7).
///
/// <see cref="Initialize"/>'s <c>fixedWidth</c>/<c>fontScale</c> parameters are this view's only
/// per-host (popover vs. pinned) configuration — everything else is identical between the two
/// hosts. <c>fixedWidth: false</c> (pinned window, spec §1b "no width clamp") clears this view's
/// own local Width and the tree ScrollViewer's local Height so both flex with the host window
/// instead of the popover's hard 300pt/listHeight-formula sizing (see Root's Grid.RowDefinitions
/// in the XAML: the tree row is Height="*", a no-op under the popover's SizeToContent="Height"
/// measure pass — WPF measures Star rows as Auto under an infinite constraint — but a real fill
/// once the pinned window's finite viewport and the cleared ScrollViewer Height combine). Deferred
/// out of this task's scope: the finer per-mode visual deltas spec §2/§3 also describe (message
/// bubble visibility, the pinned-only " ctx"/type-label metric suffix, the 360pt compact/stacked
/// row breakpoint) — none of those are wired here; only the width/height clamp itself is.
/// </summary>
public partial class DashboardView : System.Windows.Controls.UserControl   // fully qualified: UseWPF+UseWindowsForms both export a UserControl (CS0104)
{
    private DashboardViewModel? _vm;
    private Action? _onAbout;
    private Action? _onQuit;
    private Action? _onPin;
    private bool _ollamaCollapsed;

    public DashboardView()
    {
        InitializeComponent();
        BuildLegend();
        BuildInfoPopover();
        RenderLaunchAtLogin();
    }

    /// <summary>Wires the view to its (shared, long-lived) view model and the footer/header
    /// actions that live one level up in Program.cs (About/Quit/Pin — see PopoverWindow/
    /// PinnedWindow). <paramref name="fixedWidth"/>/<paramref name="fontScale"/> configure this
    /// specific host instance (see class doc comment); always call <see cref="Teardown"/> from the
    /// hosting window's Closed handler to release the PropertyChanged subscription below.</summary>
    public void Initialize(DashboardViewModel vm, Action onAbout, Action onQuit, Action? onPin = null,
        bool fixedWidth = true, double fontScale = 1.0)
    {
        _vm = vm;
        _onAbout = onAbout;
        _onQuit = onQuit;
        _onPin = onPin;
        DataContext = vm;
        vm.PropertyChanged += Vm_PropertyChanged;
        Pet.SetMood(vm.Mood);
        RenderLaunchAtLogin();
        if (!fixedWidth)
        {
            ClearValue(WidthProperty);
            TreeScroll.ClearValue(HeightProperty);
        }
        SetFontScale(fontScale);
    }

    /// <summary>Unsubscribes from the shared VM's PropertyChanged (lifecycle-leak fix, task-6
    /// carry-forward from Task 4): DashboardView.Initialize used to subscribe a closure over
    /// <c>vm</c>/<c>this</c> to the process-lifetime DashboardViewModel and never unsubscribe it —
    /// since a NEW DashboardView (and its whole visual tree, including PetControl's own
    /// DispatcherTimer) is constructed on every popover open, every past instance stayed alive
    /// forever as a dead subscriber. Call this from the hosting window's Closed event
    /// (PopoverWindow/PinnedWindow both do).</summary>
    public void Teardown()
    {
        if (_vm is not null) _vm.PropertyChanged -= Vm_PropertyChanged;
    }

    private void Vm_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        Pet.SetMood(Vm.Mood);
        RenderLaunchAtLogin();
    }

    /// <summary>FontScale wiring (spec §5, Task 5 carry): applies uniformly via a LayoutTransform
    /// on the root Grid rather than rewriting every hardcoded FontSize in this file to a bound,
    /// scaled value (~50 call sites) — the simpler of the two valid options the task brief allows
    /// ("pick simpler; document"). This scales layout (margins/paddings) along with text, which is
    /// a real deviation from mac's `scaled()` (font sizes only) — accepted here as a deliberate
    /// scope trim; the popover's fixed-300pt/clipped() overflow handling still degrades gracefully
    /// at 1.3x same as mac. Not live-reactive to a Settings change while a window is already open:
    /// re-applied fresh each time Initialize runs (popover: every reopen, since it's rebuilt each
    /// time) or each time PinnedWindow.Toggle() shows the reused instance — i.e. "next open," the
    /// simpler of the two options the brief explicitly sanctions over an immediately-live update.</summary>
    public void SetFontScale(double scale)
    {
        Root.LayoutTransform = Math.Abs(scale - 1.0) < 0.001 ? Transform.Identity : new ScaleTransform(scale, scale);
    }

    private DashboardViewModel Vm => _vm ?? throw new InvalidOperationException("DashboardView.Initialize was not called.");

    // ---- header ----

    private void MetricCycle_Click(object sender, RoutedEventArgs e) => Vm.CycleDefaultMetric();
    private void ActiveOnly_Click(object sender, RoutedEventArgs e) => Vm.ActiveOnly = !Vm.ActiveOnly;
    private void ExpandCollapseAll_Click(object sender, RoutedEventArgs e) => Vm.ExpandOrCollapseAll();
    private void Refresh_Click(object sender, RoutedEventArgs e) => Vm.RefreshNow();
    private void Pin_Click(object sender, RoutedEventArgs e) => _onPin?.Invoke();

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

    /// <summary>Toggles launch-at-login through the VM (backed by IRunAtLogin — Tama.Tray.RunAtLogin
    /// on Windows). RenderLaunchAtLogin refreshes automatically afterward via Vm_PropertyChanged,
    /// since ToggleLaunchAtLogin raises PropertyChanged(LaunchAtLoginEnabled).</summary>
    private void LaunchAtLogin_Click(object sender, MouseButtonEventArgs e) => Vm.ToggleLaunchAtLogin();

    /// <summary>Checked (yellow ☑) when IRunAtLogin reports the app is registered; dim ☐ otherwise
    /// (spec §2g: checkmark.square.fill / square). Called before Initialize (constructor) too, when
    /// _vm is still null — renders the safe "off" default in that window.</summary>
    private void RenderLaunchAtLogin()
    {
        var enabled = _vm?.LaunchAtLoginEnabled ?? false;
        LaunchAtLoginIcon.Text = enabled ? "☑" : "☐";
        LaunchAtLoginIcon.Foreground = enabled ? Palette.Yellow : Palette.Dim;
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
