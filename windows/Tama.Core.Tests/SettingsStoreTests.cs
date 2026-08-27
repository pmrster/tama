using Tama.Core;

namespace Tama.Core.Tests;

/// <summary>
/// Port of Sources/TamaCore/Settings/SettingsStore.swift's persistence semantics (planc-ui-spec.md
/// §5) onto a JSON file instead of UserDefaults: round-trip, missing file, whole-file-malformed,
/// and per-field-malformed (an individual bad enum string falls back to just that field's
/// default, mirroring Swift's `.flatMap(Appearance.init(rawValue:)) ?? .system` per key) all
/// fall back to defaults and never throw — same contract as CatStateStoreTests.
/// </summary>
[TestClass]
public sealed class SettingsStoreTests
{
    private string _dir = null!;

    [TestInitialize]
    public void SetUp() => _dir = Path.Combine(Path.GetTempPath(), "settings-" + Guid.NewGuid());

    [TestCleanup]
    public void TearDown() { if (Directory.Exists(_dir)) Directory.Delete(_dir, recursive: true); }

    [TestMethod]
    public void Round_trips_settings()
    {
        var store = new SettingsStore(_dir);
        var settings = new AppSettings(Appearance.Dark, FontSize.Large);
        store.Save(settings);
        Assert.AreEqual(settings, store.Load());
    }

    [TestMethod]
    public void Round_trips_every_appearance_and_font_size_combination()
    {
        var store = new SettingsStore(_dir);
        foreach (var appearance in Enum.GetValues<Appearance>())
        foreach (var fontSize in Enum.GetValues<FontSize>())
        {
            var settings = new AppSettings(appearance, fontSize);
            store.Save(settings);
            Assert.AreEqual(settings, store.Load());
        }
    }

    [TestMethod]
    public void Missing_file_loads_defaults()
    {
        Assert.AreEqual(AppSettings.Default, new SettingsStore(_dir).Load());
        Assert.AreEqual(Appearance.System, AppSettings.Default.Appearance);
        Assert.AreEqual(FontSize.Small, AppSettings.Default.FontSize);
    }

    [TestMethod]
    public void Whole_file_malformed_loads_defaults()
    {
        Directory.CreateDirectory(_dir);
        File.WriteAllText(Path.Combine(_dir, "settings.json"), "not json");
        Assert.AreEqual(AppSettings.Default, new SettingsStore(_dir).Load());
    }

    [TestMethod]
    public void Non_object_json_loads_defaults()
    {
        Directory.CreateDirectory(_dir);
        File.WriteAllText(Path.Combine(_dir, "settings.json"), "[1,2,3]");
        Assert.AreEqual(AppSettings.Default, new SettingsStore(_dir).Load());
    }

    [TestMethod]
    public void Unknown_appearance_value_falls_back_to_system_but_keeps_valid_font_size()
    {
        Directory.CreateDirectory(_dir);
        File.WriteAllText(Path.Combine(_dir, "settings.json"), """{"appearance":"neon","fontSize":"medium"}""");
        var loaded = new SettingsStore(_dir).Load();
        Assert.AreEqual(Appearance.System, loaded.Appearance);
        Assert.AreEqual(FontSize.Medium, loaded.FontSize);
    }

    [TestMethod]
    public void Unknown_font_size_value_falls_back_to_small_but_keeps_valid_appearance()
    {
        Directory.CreateDirectory(_dir);
        File.WriteAllText(Path.Combine(_dir, "settings.json"), """{"appearance":"dark","fontSize":"huge"}""");
        var loaded = new SettingsStore(_dir).Load();
        Assert.AreEqual(Appearance.Dark, loaded.Appearance);
        Assert.AreEqual(FontSize.Small, loaded.FontSize);
    }

    [TestMethod]
    public void Missing_keys_load_defaults()
    {
        Directory.CreateDirectory(_dir);
        File.WriteAllText(Path.Combine(_dir, "settings.json"), "{}");
        Assert.AreEqual(AppSettings.Default, new SettingsStore(_dir).Load());
    }

    [TestMethod]
    public void Undefined_numeric_enum_values_load_as_defaults()
    {
        Directory.CreateDirectory(_dir);
        File.WriteAllText(Path.Combine(_dir, "settings.json"), """{"appearance":"5","fontSize":"7"}""");
        var loaded = new SettingsStore(_dir).Load();
        Assert.AreEqual(AppSettings.Default, loaded);
        Assert.AreEqual(Appearance.System, loaded.Appearance);
        Assert.AreEqual(FontSize.Small, loaded.FontSize);
    }

    [TestMethod]
    public void Save_writes_only_inside_the_injected_directory()
    {
        var outside = Path.Combine(Path.GetTempPath(), "settings-outside-" + Guid.NewGuid());
        Directory.CreateDirectory(outside);
        try
        {
            var before = Directory.GetFiles(outside);
            new SettingsStore(_dir).Save(new AppSettings(Appearance.Light, FontSize.Medium));
            CollectionAssert.AreEqual(before, Directory.GetFiles(outside));
            Assert.IsTrue(File.Exists(Path.Combine(_dir, "settings.json")));
        }
        finally { Directory.Delete(outside, recursive: true); }
    }

    // --- pinned-window frame (planc-ui-spec.md §1b: "remembers frame") ---

    [TestMethod]
    public void Round_trips_a_pinned_frame()
    {
        var store = new SettingsStore(_dir);
        var settings = new AppSettings(Appearance.System, FontSize.Small, new WindowFrame(10, 20, 360, 480));
        store.Save(settings);
        Assert.AreEqual(settings, store.Load());
    }

    [TestMethod]
    public void Missing_pinned_frame_loads_as_null()
    {
        var store = new SettingsStore(_dir);
        store.Save(new AppSettings(Appearance.Dark, FontSize.Medium));
        Assert.IsNull(store.Load().PinnedFrame);
    }

    [TestMethod]
    public void Saving_a_frame_does_not_clobber_appearance_or_font_size()
    {
        var store = new SettingsStore(_dir);
        store.Save(new AppSettings(Appearance.Dark, FontSize.Large, new WindowFrame(1, 2, 3, 4)));
        var loaded = store.Load();
        Assert.AreEqual(Appearance.Dark, loaded.Appearance);
        Assert.AreEqual(FontSize.Large, loaded.FontSize);
        Assert.AreEqual(new WindowFrame(1, 2, 3, 4), loaded.PinnedFrame);
    }

    [TestMethod]
    public void Partial_pinned_frame_object_falls_back_to_null_not_a_half_populated_frame()
    {
        Directory.CreateDirectory(_dir);
        File.WriteAllText(Path.Combine(_dir, "settings.json"),
            """{"appearance":"system","fontSize":"small","pinnedFrame":{"x":1,"y":2}}""");
        var loaded = new SettingsStore(_dir).Load();
        Assert.AreEqual(Appearance.System, loaded.Appearance);
        Assert.IsNull(loaded.PinnedFrame);
    }

    [TestMethod]
    public void Non_object_pinned_frame_falls_back_to_null()
    {
        Directory.CreateDirectory(_dir);
        File.WriteAllText(Path.Combine(_dir, "settings.json"),
            """{"appearance":"system","fontSize":"small","pinnedFrame":"nope"}""");
        Assert.IsNull(new SettingsStore(_dir).Load().PinnedFrame);
    }

    // --- font-size factors (planc-ui-spec.md §5, SettingsStore.swift:13-19 verbatim) ---

    [TestMethod]
    public void Font_size_factors_match_spec_exactly()
    {
        Assert.AreEqual(1.0, FontSize.Small.Factor());
        Assert.AreEqual(1.15, FontSize.Medium.Factor());
        Assert.AreEqual(1.3, FontSize.Large.Factor());
    }

    // --- floating cat: "floatingCatVisible" (bool, default true) + "floatingCatFrame" ---

    [TestMethod]
    public void Floating_cat_defaults_to_visible_with_no_frame()
    {
        Assert.IsTrue(AppSettings.Default.FloatingCatVisible);
        Assert.IsNull(AppSettings.Default.FloatingCatFrame);
    }

    [TestMethod]
    public void Missing_floating_cat_keys_load_as_visible_true_and_null_frame()
    {
        // Upgrade path: a settings.json written by a build that predates the floating cat.
        Directory.CreateDirectory(_dir);
        File.WriteAllText(Path.Combine(_dir, "settings.json"),
            """{"appearance":"dark","fontSize":"large","pinnedFrame":{"x":1,"y":2,"width":3,"height":4}}""");
        var loaded = new SettingsStore(_dir).Load();
        Assert.IsTrue(loaded.FloatingCatVisible);
        Assert.IsNull(loaded.FloatingCatFrame);
        Assert.AreEqual(Appearance.Dark, loaded.Appearance);
        Assert.AreEqual(new WindowFrame(1, 2, 3, 4), loaded.PinnedFrame);
    }

    [TestMethod]
    public void Round_trips_floating_cat_hidden_and_frame()
    {
        var store = new SettingsStore(_dir);
        var settings = new AppSettings(Appearance.Light, FontSize.Medium, null,
            FloatingCatVisible: false, FloatingCatFrame: new WindowFrame(5, 6, 120, 68));
        store.Save(settings);
        Assert.AreEqual(settings, store.Load());
    }

    [TestMethod]
    public void Non_boolean_floating_cat_visible_falls_back_to_true()
    {
        Directory.CreateDirectory(_dir);
        File.WriteAllText(Path.Combine(_dir, "settings.json"),
            """{"appearance":"system","fontSize":"small","floatingCatVisible":"nope"}""");
        Assert.IsTrue(new SettingsStore(_dir).Load().FloatingCatVisible);
    }

    [TestMethod]
    public void Partial_floating_cat_frame_falls_back_to_null()
    {
        Directory.CreateDirectory(_dir);
        File.WriteAllText(Path.Combine(_dir, "settings.json"),
            """{"appearance":"system","fontSize":"small","floatingCatFrame":{"x":1}}""");
        Assert.IsNull(new SettingsStore(_dir).Load().FloatingCatFrame);
    }

    [TestMethod]
    public void Pinned_and_floating_cat_frames_are_independent()
    {
        var store = new SettingsStore(_dir);
        store.Save(new AppSettings(Appearance.System, FontSize.Small,
            PinnedFrame: new WindowFrame(1, 2, 3, 4), FloatingCatFrame: new WindowFrame(9, 8, 7, 6)));
        var loaded = store.Load();
        Assert.AreEqual(new WindowFrame(1, 2, 3, 4), loaded.PinnedFrame);
        Assert.AreEqual(new WindowFrame(9, 8, 7, 6), loaded.FloatingCatFrame);
    }
}
