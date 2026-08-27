using Tama.Core;
using Tama.Core.Ui;

namespace Tama.Core.Tests;

/// <summary>
/// Cases per planc-ui-spec.md §5 (AppSettings.appearance/fontSize didSet persistence + live
/// retint) — the VM is framework-free, so the "OS is dark" probe and the "retint" callback are
/// simple fakes here instead of Palette.IsSystemDark/Palette.Apply.
/// </summary>
[TestClass]
public sealed class AppSettingsViewModelTests
{
    private string _dir = null!;

    [TestInitialize]
    public void SetUp() => _dir = Path.Combine(Path.GetTempPath(), "asvm-" + Guid.NewGuid());

    [TestCleanup]
    public void TearDown() { if (Directory.Exists(_dir)) Directory.Delete(_dir, recursive: true); }

    private SettingsStore Store() => new(_dir);

    [TestMethod]
    public void Loads_defaults_when_nothing_persisted()
    {
        var vm = new AppSettingsViewModel(Store());
        Assert.AreEqual(Appearance.System, vm.Appearance);
        Assert.AreEqual(FontSize.Small, vm.FontSize);
        Assert.AreEqual(1.0, vm.FontScale);
    }

    [TestMethod]
    public void Loads_previously_persisted_settings()
    {
        var store = Store();
        store.Save(new AppSettings(Appearance.Dark, FontSize.Large));
        var vm = new AppSettingsViewModel(store);
        Assert.AreEqual(Appearance.Dark, vm.Appearance);
        Assert.AreEqual(FontSize.Large, vm.FontSize);
        Assert.AreEqual(1.3, vm.FontScale);
    }

    [TestMethod]
    public void Setting_appearance_persists_it()
    {
        var store = Store();
        var vm = new AppSettingsViewModel(store);
        vm.Appearance = Appearance.Light;
        Assert.AreEqual(Appearance.Light, new AppSettingsViewModel(store).Appearance);
    }

    [TestMethod]
    public void Setting_font_size_persists_it_and_updates_font_scale()
    {
        var store = Store();
        var vm = new AppSettingsViewModel(store);
        vm.FontSize = FontSize.Medium;
        Assert.AreEqual(1.15, vm.FontScale);
        Assert.AreEqual(FontSize.Medium, new AppSettingsViewModel(store).FontSize);
    }

    [TestMethod]
    public void Setting_appearance_invokes_the_retint_callback_with_the_resolved_dark_flag()
    {
        var calls = new List<bool>();
        var vm = new AppSettingsViewModel(Store(), systemIsDark: () => false, onAppearanceChanged: calls.Add);
        vm.Appearance = Appearance.Dark;
        CollectionAssert.AreEqual(new[] { true }, calls);
        vm.Appearance = Appearance.Light;
        CollectionAssert.AreEqual(new[] { true, false }, calls);
    }

    [TestMethod]
    public void System_appearance_resolves_dark_via_the_injected_probe()
    {
        var systemDark = true;
        var vm = new AppSettingsViewModel(Store(), systemIsDark: () => systemDark);
        Assert.AreEqual(Appearance.System, vm.Appearance);
        Assert.IsTrue(vm.IsDark);
        systemDark = false;
        Assert.IsFalse(vm.IsDark);
    }

    [TestMethod]
    public void Light_and_dark_force_regardless_of_the_system_probe()
    {
        var vm = new AppSettingsViewModel(Store(), systemIsDark: () => true);
        vm.Appearance = Appearance.Light;
        Assert.IsFalse(vm.IsDark);
        vm.Appearance = Appearance.Dark;
        Assert.IsTrue(vm.IsDark);
    }

    [TestMethod]
    public void Apply_initial_appearance_invokes_the_callback_once_without_a_change()
    {
        var calls = new List<bool>();
        var vm = new AppSettingsViewModel(Store(), systemIsDark: () => true, onAppearanceChanged: calls.Add);
        Assert.AreEqual(0, calls.Count); // construction alone must not retint
        vm.ApplyInitialAppearance();
        CollectionAssert.AreEqual(new[] { true }, calls);
    }

    [TestMethod]
    public void Setting_the_same_value_again_does_not_reinvoke_the_callback_or_raise_property_changed()
    {
        var calls = new List<bool>();
        var vm = new AppSettingsViewModel(Store(), onAppearanceChanged: calls.Add);
        vm.Appearance = Appearance.Dark;
        Assert.AreEqual(1, calls.Count);
        var raised = 0;
        vm.PropertyChanged += (_, _) => raised++;
        vm.Appearance = Appearance.Dark;
        Assert.AreEqual(1, calls.Count);
        Assert.AreEqual(0, raised);
    }

    [TestMethod]
    public void Property_changed_fires_for_appearance_and_font_size_changes()
    {
        var vm = new AppSettingsViewModel(Store());
        var names = new List<string?>();
        vm.PropertyChanged += (_, e) => names.Add(e.PropertyName);

        vm.Appearance = Appearance.Dark;
        CollectionAssert.Contains(names, nameof(AppSettingsViewModel.Appearance));
        CollectionAssert.Contains(names, nameof(AppSettingsViewModel.IsDark));

        names.Clear();
        vm.FontSize = FontSize.Large;
        CollectionAssert.Contains(names, nameof(AppSettingsViewModel.FontSize));
        CollectionAssert.Contains(names, nameof(AppSettingsViewModel.FontScale));
    }

    // --- pinned-window frame (planc-ui-spec.md §1b) ---

    [TestMethod]
    public void Pinned_frame_starts_null_and_persists_once_set()
    {
        var store = Store();
        var vm = new AppSettingsViewModel(store);
        Assert.IsNull(vm.PinnedFrame);

        vm.PinnedFrame = new WindowFrame(10, 20, 360, 480);
        Assert.AreEqual(new WindowFrame(10, 20, 360, 480), new AppSettingsViewModel(store).PinnedFrame);
    }

    [TestMethod]
    public void Setting_pinned_frame_does_not_disturb_appearance_or_font_size()
    {
        var store = Store();
        var vm = new AppSettingsViewModel(store);
        vm.Appearance = Appearance.Dark;
        vm.FontSize = FontSize.Large;

        vm.PinnedFrame = new WindowFrame(1, 2, 3, 4);

        var reloaded = new AppSettingsViewModel(store);
        Assert.AreEqual(Appearance.Dark, reloaded.Appearance);
        Assert.AreEqual(FontSize.Large, reloaded.FontSize);
        Assert.AreEqual(new WindowFrame(1, 2, 3, 4), reloaded.PinnedFrame);
    }

    [TestMethod]
    public void Setting_the_same_frame_again_does_not_reraise_property_changed()
    {
        var vm = new AppSettingsViewModel(Store());
        vm.PinnedFrame = new WindowFrame(1, 2, 3, 4);
        var raised = 0;
        vm.PropertyChanged += (_, _) => raised++;
        vm.PinnedFrame = new WindowFrame(1, 2, 3, 4);
        Assert.AreEqual(0, raised);
    }

    [TestMethod]
    public void ReapplyIfSystem_reprobes_in_system_mode_and_is_noop_in_explicit_mode()
    {
        var calls = new List<bool>();
        var systemDark = true;
        var vm = new AppSettingsViewModel(Store(), systemIsDark: () => systemDark, onAppearanceChanged: calls.Add);
        Assert.AreEqual(Appearance.System, vm.Appearance);

        // System mode starts dark
        vm.ApplyInitialAppearance();
        CollectionAssert.AreEqual(new[] { true }, calls);

        // OS switches to light; system mode reapply re-probes
        systemDark = false;
        vm.ReapplyIfSystem();
        CollectionAssert.AreEqual(new[] { true, false }, calls);

        // Explicit mode is untouched by ReapplyIfSystem
        vm.Appearance = Appearance.Light;
        Assert.AreEqual(3, calls.Count);
        systemDark = true;  // system changes back
        vm.ReapplyIfSystem();
        Assert.AreEqual(3, calls.Count); // no new call in explicit Light mode
    }

    // --- floating cat visibility + frame (mirrors the PinnedFrame contract) ---

    [TestMethod]
    public void Floating_cat_visible_defaults_true_and_persists_when_toggled_off()
    {
        var store = Store();
        var vm = new AppSettingsViewModel(store);
        Assert.IsTrue(vm.FloatingCatVisible);

        vm.FloatingCatVisible = false;
        Assert.IsFalse(new AppSettingsViewModel(store).FloatingCatVisible);
    }

    [TestMethod]
    public void Floating_cat_frame_starts_null_and_persists_once_set()
    {
        var store = Store();
        var vm = new AppSettingsViewModel(store);
        Assert.IsNull(vm.FloatingCatFrame);

        vm.FloatingCatFrame = new WindowFrame(10, 20, 120, 68);
        Assert.AreEqual(new WindowFrame(10, 20, 120, 68), new AppSettingsViewModel(store).FloatingCatFrame);
    }

    [TestMethod]
    public void Setting_the_same_floating_cat_values_again_does_not_reraise_property_changed()
    {
        var vm = new AppSettingsViewModel(Store());
        vm.FloatingCatVisible = false;
        vm.FloatingCatFrame = new WindowFrame(1, 2, 3, 4);
        var raised = 0;
        vm.PropertyChanged += (_, _) => raised++;
        vm.FloatingCatVisible = false;
        vm.FloatingCatFrame = new WindowFrame(1, 2, 3, 4);
        Assert.AreEqual(0, raised);
    }

    [TestMethod]
    public void Floating_cat_changes_raise_property_changed_with_their_own_names()
    {
        var vm = new AppSettingsViewModel(Store());
        var names = new List<string?>();
        vm.PropertyChanged += (_, e) => names.Add(e.PropertyName);
        vm.FloatingCatVisible = false;
        vm.FloatingCatFrame = new WindowFrame(1, 2, 3, 4);
        CollectionAssert.AreEqual(
            new[] { nameof(AppSettingsViewModel.FloatingCatVisible), nameof(AppSettingsViewModel.FloatingCatFrame) },
            names);
    }

    [TestMethod]
    public void Setting_floating_cat_state_does_not_disturb_appearance_font_size_or_pinned_frame()
    {
        var store = Store();
        var vm = new AppSettingsViewModel(store);
        vm.Appearance = Appearance.Dark;
        vm.FontSize = FontSize.Large;
        vm.PinnedFrame = new WindowFrame(1, 2, 3, 4);

        vm.FloatingCatVisible = false;
        vm.FloatingCatFrame = new WindowFrame(9, 8, 7, 6);

        var reloaded = new AppSettingsViewModel(store);
        Assert.AreEqual(Appearance.Dark, reloaded.Appearance);
        Assert.AreEqual(FontSize.Large, reloaded.FontSize);
        Assert.AreEqual(new WindowFrame(1, 2, 3, 4), reloaded.PinnedFrame);
        Assert.IsFalse(reloaded.FloatingCatVisible);
        Assert.AreEqual(new WindowFrame(9, 8, 7, 6), reloaded.FloatingCatFrame);
    }
}
