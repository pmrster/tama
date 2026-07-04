namespace Tama.Core.Ui;

/// <summary>
/// Pure mood/time → cat-sprite motion computation, framework-free port of `PetView.swift`'s
/// pixel-art cat (contact/passing walk frames + nap pose) and its motion function. Unit-tested on
/// macOS like the rest of Tama.Core; Tama.Tray's PetControl renders the WriteableBitmaps and
/// applies the WPF-specific effects (ScaleTransform flip, DispatcherTimer tick) from this class's
/// pure outputs — mirrors the IconRenderer / TrayIcon split (see IconRenderer.cs).
/// </summary>
public static class CatSprite
{
    public const int GridCols = 24;
    public const int GridRows = 15;

    // Cell rendering constants PetControl uses to size its WriteableBitmaps: PetView.swift's `px`
    // (2.0 logical units per cell, :23) plus a 0.35-unit overlap per cell edge so adjoining filled
    // cells don't show hairline seams once scaled (PetView.swift:173-178).
    public const double PixelSize = 2.0;
    public const double CellOverlap = 0.35;

    // Traced straight from the SVG fills (PetView.swift:99-101).
    public const string BodyColorHex = "#F3BD4F";
    public const string EyeColorHex = "#1B1A18";
    public const string GroundColorHex = "#4D453D";

    // Pixel legend: Y = warm yellow body, E = dark eyes/nose, . = empty. 24 cols x 15 rows.

    /// <summary>Frame 1 — contact pose: tail low, legs gathered (verbatim PetView.swift:30-46).</summary>
    public static readonly IReadOnlyList<string> Frame1 = new[]
    {
        "........................",
        "...........YY.....YY....",
        "..........YYYY...YYYY...",
        "..........YYYYYYYYYYY...",
        ".........YYYYYYYYYYYYY..",
        ".........YYYYYYYYYYYYY..",
        "..YY.....YYYYEYYYYYEYY..",
        "..YYY...YYYYYEYYYYYEYY..",
        "...YYYYYYYYYYEYYEYYEYY..",
        "....YYYYYYYYYYYYYYYYYY..",
        "......YYYYYYYYYYYYYYYY..",
        "......YYYYYYYYYYYYYYY...",
        "......YYYYYYYYYYYYYY....",
        "......YYYYYYYYYYYYYY....",
        "......YY..YYY.YY..Y.....",
    };

    /// <summary>Frame 2 — passing pose: tail raised, legs mid-stride, front foot kicked (verbatim
    /// PetView.swift:49-65).</summary>
    public static readonly IReadOnlyList<string> Frame2 = new[]
    {
        "...........YY.....YY....",
        "..........YYYY...YYYY...",
        "..........YYYYYYYYYYY...",
        ".........YYYYYYYYYYYYY..",
        ".........YYYYYYYYYYYYY..",
        "YY.......YYYYEYYYYYEYY..",
        "YYY...YYYYYYYEYYYYYEYY..",
        ".YYYYYYYYYYYYEYYEYYEYY..",
        "..YYYYYYYYYYYYYYYYYYYY..",
        ".....YYYYYYYYYYYYYYYYY..",
        ".....YYYYYYYYYYYYYYYY...",
        ".....YYYYYYYYYYYYYY.....",
        "....YYYYYYYYYYYYYY......",
        "...YYYYY....YY...YY.....",
        "...YYY.YY...YY..........",
    };

    /// <summary>Nap pose — frame 1 body with eyes closed to gentle dashes (verbatim
    /// PetView.swift:70-86).</summary>
    public static readonly IReadOnlyList<string> Nap = new[]
    {
        "........................",
        "...........YY.....YY....",
        "..........YYYY...YYYY...",
        "..........YYYYYYYYYYY...",
        ".........YYYYYYYYYYYYY..",
        ".........YYYYYYYYYYYYY..",
        "..YY.....YYYYYYYYYYYYY..",
        "..YYY...YYYYEEEYYYEEEY..",
        "...YYYYYYYYYYYYYYYYYYY..",
        "....YYYYYYYYYYYYYYYYYY..",
        "......YYYYYYYYYYYYYYYY..",
        "......YYYYYYYYYYYYYYY...",
        "......YYYYYYYYYYYYYY....",
        "......YYYYYYYYYYYYYY....",
        "......YY..YYY.YY..Y.....",
    };

    /// <summary>Which of the three pixel-art grids a given motion sample selects.</summary>
    public enum CatFrame { Walk1, Walk2, Nap }

    /// <summary>Returns the 24x15 pixel grid for a given <see cref="CatFrame"/>.</summary>
    public static IReadOnlyList<string> Pixels(CatFrame frame) => frame switch
    {
        CatFrame.Walk1 => Frame1,
        CatFrame.Walk2 => Frame2,
        CatFrame.Nap => Nap,
        _ => throw new ArgumentOutOfRangeException(nameof(frame), frame, null),
    };

    /// <summary>One drifting sleep "z" (PetView.swift:146-159). <paramref name="Index"/> (0..2)
    /// is which of the three z's this is — the caller uses it to size the glyph
    /// (`scaled(6) + Index*2`); <paramref name="P"/> is this frame's 0..1 loop phase the caller
    /// uses to drift the glyph's x/y offset; <paramref name="Opacity"/> is the pre-computed
    /// `0.85*(1-p)` fade.</summary>
    public readonly record struct ZDrop(int Index, double P, double Opacity);

    /// <summary>Pure snapshot of one instant of the cat's motion — everything Tama.Tray's
    /// PetControl needs to pick a bitmap, position it, flip it, and draw the meow/z overlays,
    /// with no framework types involved (PetView.swift:198-236, :146-159, :194-196).</summary>
    public sealed record MotionState(
        double X,
        bool FacingLeft,
        CatFrame Frame,
        bool MeowVisible,
        bool IsNapping,
        IReadOnlyList<ZDrop> ZDrops);

    /// <summary>Walk speed / liveliness by mood (PetView.swift:11-17): working uses
    /// `max(1, intensity)` (never fully stops, even at intensity 0); greeting is a fixed 2;
    /// resting and napping are stationary (0).</summary>
    public static int Energy(Mood mood) => mood.Kind switch
    {
        MoodKind.Working => Math.Max(1, mood.Intensity),
        MoodKind.Greeting => 2,
        MoodKind.Resting => 0,
        MoodKind.Napping => 0,
        _ => 0,
    };

    /// <summary>Pure port of PetView.swift's `motion(t:spriteW:width:)` (:198-236), its
    /// `meowVisible(_:)` (:194-196), and its `sleepZ` z-loop math (:146-159). <paramref name="t"/>
    /// is the animation clock in seconds (wall-clock reference time in the Swift original);
    /// <paramref name="spriteW"/> and <paramref name="width"/> are the sprite's and the available
    /// container's logical widths, in the same units.</summary>
    public static MotionState Motion(double t, double spriteW, double width, Mood mood)
    {
        const double margin = 6.0;
        var range = Math.Max(10.0, width - spriteW - margin * 2);
        var energy = Energy(mood);
        var isNapping = mood.Kind == MoodKind.Napping;

        // Sleeping z's only ever show while napping (PetView.swift:132-134) — resting is also
        // energy 0 but stays plain frame 1 with no z overlay.
        var zDrops = isNapping ? ComputeZDrops(t) : Array.Empty<ZDrop>();

        if (energy <= 0)
        {
            // Napping -> curled nap pose with z's; resting -> awake but still (frame 1).
            return new MotionState(
                X: margin + range / 2,
                FacingLeft: false,
                Frame: isNapping ? CatFrame.Nap : CatFrame.Walk1,
                MeowVisible: false,
                IsNapping: isNapping,
                ZDrops: zDrops);
        }

        // Slower than a literal speed dial so it feels cute, not frantic (PetView.swift:216-217).
        var speed = 28.0 + Math.Min(energy, 8) * 10.0;

        var phase = (t * speed / range) % 2.0;
        var p = phase < 0 ? phase + 2 : phase;

        var x = p < 1 ? p * range : (2 - p) * range;
        var facingLeft = p >= 1;

        // Two-frame walk cycle; the frames already encode the body bob.
        var stepHz = 3.2 + Math.Min(energy, 6) * 0.4;
        var frameIndex = (int)(t * stepHz) % 2;
        var frame = frameIndex == 0 ? CatFrame.Walk1 : CatFrame.Walk2;

        var meowVisible = (t % 7.0) < 1.0; // energy > 0 already established by this branch

        return new MotionState(
            X: margin + x,
            FacingLeft: facingLeft,
            Frame: frame,
            MeowVisible: meowVisible,
            IsNapping: false,
            ZDrops: Array.Empty<ZDrop>());
    }

    private static IReadOnlyList<ZDrop> ComputeZDrops(double t)
    {
        var loop = (t % 3.0) / 3.0;
        var drops = new ZDrop[3];
        for (var i = 0; i < 3; i++)
        {
            var p = (loop + i / 3.0) % 1.0;
            drops[i] = new ZDrop(i, p, 0.85 * (1.0 - p));
        }
        return drops;
    }
}
