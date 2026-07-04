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
}
