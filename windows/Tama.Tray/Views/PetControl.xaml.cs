using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Tama.Core;
using Tama.Core.Ui;

namespace Tama.Tray.Views;

/// <summary>
/// Windows port of PetView.swift's pixel-cat strip: a small pacing cat rendered from three
/// pre-baked WriteableBitmaps (frame1/frame2/nap, sourced from the framework-free
/// <see cref="CatSprite"/>), re-picked and re-positioned every <see cref="DispatcherTimer"/> tick
/// from <see cref="CatSprite.Motion"/>'s pure output — mirrors the IconRenderer/TrayIcon split
/// (pure math lives in Tama.Core.Ui; only WPF-only concerns — bitmaps, transforms, the timer, and
/// this class's own Canvas layout math — live here). Zero NuGet, no network.
/// </summary>
public partial class PetControl : System.Windows.Controls.UserControl
{
    // CatSprite.PixelSize (2.0 logical units/cell) as an *integer* raster scale. PetView.swift's
    // Canvas path also adds a 0.35-unit overlap per cell (PetView.swift:173-178) to hide seams
    // between adjacent vector rects at fractional scale factors — a raster WriteableBitmap has no
    // such seams (adjacent same-color pixels already touch), so that overlap is intentionally not
    // reproduced here (per task-3-brief.md's own "at the bitmap level just render each cell as
    // filled pixels at an integer scale" instruction).
    private const int RasterScale = 2;
    private const double SpriteWidth = CatSprite.GridCols * RasterScale;  // 48
    private const double SpriteHeight = CatSprite.GridRows * RasterScale; // 30

    private readonly DispatcherTimer _timer = new();
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private readonly WriteableBitmap _walk1;
    private readonly WriteableBitmap _walk2;
    private readonly WriteableBitmap _nap;
    private Mood _mood = Mood.Resting;

    public PetControl()
    {
        InitializeComponent();

        _walk1 = RenderBitmap(CatSprite.Frame1);
        _walk2 = RenderBitmap(CatSprite.Frame2);
        _nap = RenderBitmap(CatSprite.Nap);
        SpriteImage.Source = _walk1;

        _timer.Tick += (_, _) => Tick();
        Loaded += (_, _) => { ApplyTimerCadence(); _timer.Start(); Tick(); };
        Unloaded += (_, _) => _timer.Stop();
        SizeChanged += (_, _) => Tick();
    }

    /// <summary>Called by PopoverWindow whenever AgentMonitor publishes a new mood (mirrors
    /// PetView.swift's `mood:` input re-rendering on every SwiftUI state change).</summary>
    public void SetMood(Mood mood)
    {
        _mood = mood;
        ApplyTimerCadence();
        Tick();
    }

    /// <summary>Timer cadence per PetView.swift:111 — 0.2s while animate-worthy (energy > 0),
    /// 0.5s while stationary.</summary>
    private void ApplyTimerCadence()
    {
        var energy = CatSprite.Energy(_mood);
        var interval = TimeSpan.FromSeconds(energy > 0 ? 0.2 : 0.5);
        if (_timer.Interval != interval) _timer.Interval = interval;
    }

    private void Tick()
    {
        var t = _clock.Elapsed.TotalSeconds;
        // PetView.swift:110 — width fills the (resizable) container, floored at spriteW + 12.
        var width = Math.Max(SpriteWidth + 12, ActualWidth);
        var m = CatSprite.Motion(t, SpriteWidth, width, _mood);

        SpriteImage.Source = m.Frame switch
        {
            CatSprite.CatFrame.Walk1 => _walk1,
            CatSprite.CatFrame.Walk2 => _walk2,
            CatSprite.CatFrame.Nap => _nap,
            _ => _walk1,
        };
        FlipTransform.ScaleX = m.FacingLeft ? -1 : 1;

        Canvas.SetLeft(SpriteImage, m.X);
        Canvas.SetBottom(SpriteImage, 2); // PetView.swift:136 — bob is always 0; offset is -2.

        MeowText.Visibility = m.MeowVisible ? Visibility.Visible : Visibility.Collapsed;
        if (m.MeowVisible)
        {
            // PetView.swift:130 — offset(x: spriteW + 2, y: -spriteH/2 - 4), relative to the
            // sprite's own (already-positioned) origin.
            Canvas.SetLeft(MeowText, m.X + SpriteWidth + 2);
            Canvas.SetBottom(MeowText, 2 + SpriteHeight / 2 + 4);
        }

        var zTexts = new[] { Z0Text, Z1Text, Z2Text };
        for (var i = 0; i < zTexts.Length; i++)
        {
            if (i >= m.ZDrops.Count)
            {
                zTexts[i].Visibility = Visibility.Collapsed;
                continue;
            }
            var z = m.ZDrops[i];
            zTexts[i].Visibility = Visibility.Visible;
            zTexts[i].FontSize = 6 + z.Index * 2; // PetView.swift:152 — scaled(6) + i*2.
            zTexts[i].Opacity = z.Opacity;
            // PetView.swift:155-156 — offset(x: spriteW*0.62 + p*7, y: -spriteH*0.55 - p*16).
            Canvas.SetLeft(zTexts[i], m.X + SpriteWidth * 0.62 + z.P * 7);
            Canvas.SetBottom(zTexts[i], 2 + SpriteHeight * 0.55 + z.P * 16);
        }
    }

    /// <summary>Renders a CatSprite pixel grid once into a frozen (thread-shareable, immutable)
    /// WriteableBitmap at an integer raster scale.</summary>
    private static WriteableBitmap RenderBitmap(IReadOnlyList<string> rows)
    {
        var width = CatSprite.GridCols * RasterScale;
        var height = CatSprite.GridRows * RasterScale;
        var bitmap = new WriteableBitmap(width, height, 96, 96, PixelFormats.Bgra32, null);
        var stride = width * 4;
        var pixels = new byte[height * stride];

        var body = ParseBgra(CatSprite.BodyColorHex);
        var eye = ParseBgra(CatSprite.EyeColorHex);

        for (var r = 0; r < rows.Count; r++)
        {
            var row = rows[r];
            for (var c = 0; c < row.Length; c++)
            {
                var ch = row[c];
                if (ch != 'Y' && ch != 'E') continue;
                var (b, g, red, a) = ch == 'Y' ? body : eye;
                for (var dy = 0; dy < RasterScale; dy++)
                {
                    var rowStart = (r * RasterScale + dy) * stride;
                    for (var dx = 0; dx < RasterScale; dx++)
                    {
                        var idx = rowStart + (c * RasterScale + dx) * 4;
                        pixels[idx] = b;
                        pixels[idx + 1] = g;
                        pixels[idx + 2] = red;
                        pixels[idx + 3] = a;
                    }
                }
            }
        }

        bitmap.WritePixels(new Int32Rect(0, 0, width, height), pixels, stride, 0);
        bitmap.Freeze();
        return bitmap;
    }

    private static (byte B, byte G, byte R, byte A) ParseBgra(string hex)
    {
        var r = Convert.ToByte(hex.Substring(1, 2), 16);
        var g = Convert.ToByte(hex.Substring(3, 2), 16);
        var b = Convert.ToByte(hex.Substring(5, 2), 16);
        return (b, g, r, 255);
    }
}
