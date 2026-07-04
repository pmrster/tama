using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace Tama.Core.Ui;

/// <summary>
/// The Windows analog of Swift's <c>AppSettings</c> @MainActor ObservableObject
/// (Sources/Tama/AppSettings.swift, planc-ui-spec.md §5) — wraps <see cref="SettingsStore"/>,
/// exposing <see cref="Appearance"/>/<see cref="FontSize"/> as bindable properties and
/// <see cref="FontScale"/> as the multiplier every WPF font size should scale by (mirrors
/// <c>AppSettings.fontScale</c> / Theme.swift's <c>scaled(_:)</c>).
///
/// Framework-free by injection, exactly like <see cref="AgentMonitor"/>'s injected clock/paths:
/// theme retinting is delegated to an <c>onAppearanceChanged</c> callback (Tama.Tray wires this
/// to <c>Palette.Apply</c>) and "is the OS dark right now" is delegated to a <c>systemIsDark</c>
/// probe (Tama.Tray wires this to <c>Palette.IsSystemDark</c>) — so this class is unit-testable
/// here with fakes for both, without any WPF/AppKit dependency.
/// </summary>
public sealed class AppSettingsViewModel : INotifyPropertyChanged
{
    private readonly SettingsStore _store;
    private readonly Func<bool> _systemIsDark;
    private readonly Action<bool>? _onAppearanceChanged;
    private Appearance _appearance;
    private FontSize _fontSize;

    public event PropertyChangedEventHandler? PropertyChanged;

    public AppSettingsViewModel(SettingsStore store, Func<bool>? systemIsDark = null,
        Action<bool>? onAppearanceChanged = null)
    {
        _store = store;
        _systemIsDark = systemIsDark ?? (() => false);
        _onAppearanceChanged = onAppearanceChanged;

        var loaded = _store.Load();
        _appearance = loaded.Appearance;
        _fontSize = loaded.FontSize;
    }

    /// <summary>Persists on every change and retints live via the injected callback (spec §5:
    /// "AppSettings.appearance didSet persists ... and calls applyAppearance() immediately").</summary>
    public Appearance Appearance
    {
        get => _appearance;
        set
        {
            if (_appearance == value) return;
            _appearance = value;
            Persist();
            _onAppearanceChanged?.Invoke(IsDark);
            Raise();
            Raise(nameof(IsDark));
        }
    }

    /// <summary>Persists on every change (spec §5: "AppSettings.fontSize didSet persists").</summary>
    public FontSize FontSize
    {
        get => _fontSize;
        set
        {
            if (_fontSize == value) return;
            _fontSize = value;
            Persist();
            Raise();
            Raise(nameof(FontScale));
        }
    }

    /// <summary>Every hardcoded WPF point size should multiply by this
    /// (<c>AppSettings.fontScale</c> / Theme.swift's <c>scaled(_:)</c>, spec §5).</summary>
    public double FontScale => _fontSize.Factor();

    /// <summary>Resolved light/dark right now: <see cref="Tama.Core.Appearance.Light"/>/
    /// <see cref="Tama.Core.Appearance.Dark"/> force it; <see cref="Tama.Core.Appearance.System"/>
    /// follows the injected OS probe (AppSettings.nsAppearance's mapping, spec §5).</summary>
    public bool IsDark => _appearance switch
    {
        Appearance.Light => false,
        Appearance.Dark => true,
        _ => _systemIsDark(),
    };

    /// <summary>Applies the currently-resolved appearance once, without waiting for a change —
    /// call at startup (mirrors <c>AppDelegate.applicationDidFinishLaunching</c>'s explicit
    /// <c>AppSettings.shared.applyAppearance()</c> before anything is shown, spec §6).</summary>
    public void ApplyInitialAppearance() => _onAppearanceChanged?.Invoke(IsDark);

    /// <summary>If <see cref="Appearance"/> is <see cref="Tama.Core.Appearance.System"/>, re-probes
    /// the OS theme via the injected <c>systemIsDark</c> and reinvokes <c>onAppearanceChanged</c>;
    /// explicit Light/Dark are untouched. Call on every popover open (macOS/Windows reapply resolved
    /// appearance per popover show, spec §1a).</summary>
    public void ReapplyIfSystem()
    {
        if (_appearance == Appearance.System)
            _onAppearanceChanged?.Invoke(IsDark);
    }

    private void Persist() => _store.Save(new AppSettings(_appearance, _fontSize));

    private void Raise([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
