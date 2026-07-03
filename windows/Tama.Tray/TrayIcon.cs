using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Tama.Core;
using Tama.Core.Ui;

namespace Tama.Tray;

/// <summary>
/// WinForms NotifyIcon wrapper — the Windows analog of AppChrome.swift's MenuBarIcon +
/// StatusItemController (spec §1a/§1d, §7 note 8). NotifyIcon natively supports a left-click
/// handler alongside a separate ContextMenuStrip, so (unlike AppKit's MenuBarExtra) no bypass is
/// needed to get right-click working independently of left-click.
///
/// Menu order mirrors task-2-brief.md: Open, Pin window, Settings, About, (separator), Quit.
/// Pin window / Settings are wired up in later tasks (6 / 5 respectively) — kept visible but
/// disabled here so the menu shape is already correct.
/// </summary>
public sealed class TrayIcon : IDisposable
{
    private readonly NotifyIcon _notifyIcon;
    private bool _asleep;

    public TrayIcon(Action onToggle, Action onAbout, Action onQuit)
    {
        ArgumentNullException.ThrowIfNull(onToggle);
        ArgumentNullException.ThrowIfNull(onAbout);
        ArgumentNullException.ThrowIfNull(onQuit);

        var menu = new ContextMenuStrip();
        menu.Items.Add("Open", null, (_, _) => onToggle());
        menu.Items.Add("Pin window").Enabled = false;   // stub — real window ships in Task 6
        menu.Items.Add("Settings").Enabled = false;      // stub — real window ships in Task 5
        menu.Items.Add("About", null, (_, _) => onAbout());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit", null, (_, _) => onQuit());

        _notifyIcon = new NotifyIcon
        {
            Text = "Tama",
            Icon = BuildIcon(asleep: false),
            ContextMenuStrip = menu,
            Visible = true,
        };
        // Left-click toggles the popover; right-click's ContextMenuStrip pop-up is automatic.
        _notifyIcon.MouseUp += (_, e) => { if (e.Button == MouseButtons.Left) onToggle(); };
    }

    /// <summary>Swaps the glyph when the mood's awake/asleep state changes (idempotent no-op
    /// otherwise, so a 7s/30s poll tick doesn't rebuild the icon every refresh).</summary>
    public void SetMood(Mood mood)
    {
        var asleep = mood.Kind == MoodKind.Napping;
        if (asleep == _asleep) return;
        _asleep = asleep;
        var old = _notifyIcon.Icon;
        _notifyIcon.Icon = BuildIcon(asleep);
        old?.Dispose();
    }

    /// <summary>Renders IconRenderer's BGRA frame closest to the system's small-icon metric
    /// (DPI-aware) into a GDI+ HICON. Icon.FromHandle() only borrows the handle, so it is cloned
    /// into an independently-owned Icon before the borrowed HICON is destroyed.</summary>
    private static Icon BuildIcon(bool asleep)
    {
        // Rectangle and PixelFormat are ambiguous here without qualification: UseWPF's and
        // UseWindowsForms' implicit global usings both put a same-named type in scope
        // (System.Windows.Shapes.Rectangle / System.Windows.Media.PixelFormat vs. these
        // System.Drawing[.Imaging] ones) — see App.xaml.cs's CS0104 note for the same pattern.
        var frames = IconRenderer.RenderFrames(asleep);
        var target = SystemInformation.SmallIconSize.Width;
        var frame = frames.OrderBy(f => Math.Abs(f.Size - target)).First();

        using var bitmap = new Bitmap(frame.Size, frame.Size, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        var rect = new System.Drawing.Rectangle(0, 0, frame.Size, frame.Size);
        var bits = bitmap.LockBits(rect, ImageLockMode.WriteOnly, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        try { Marshal.Copy(frame.Bgra, 0, bits.Scan0, frame.Bgra.Length); }
        finally { bitmap.UnlockBits(bits); }

        var hIcon = bitmap.GetHicon();
        try { return (Icon)Icon.FromHandle(hIcon).Clone(); }
        finally { NativeMethods.DestroyIcon(hIcon); }
    }

    public void Dispose()
    {
        _notifyIcon.Visible = false;
        _notifyIcon.Icon?.Dispose();
        _notifyIcon.Dispose();
    }

    private static class NativeMethods
    {
        [DllImport("user32.dll")]
        public static extern bool DestroyIcon(IntPtr handle);
    }
}
