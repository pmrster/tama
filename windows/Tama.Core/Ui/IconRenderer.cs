namespace Tama.Core.Ui;

/// <summary>
/// Pure mood → tray-icon-frame renderer. Framework-free (no System.Drawing / WPF), so it is
/// unit-tested on macOS like the rest of Tama.Core; Tama.Tray converts the returned BGRA byte
/// buffers into an HICON (see TrayIcon.cs).
///
/// Source pixels are the SAME 24x15 pixel-art grid PetView.swift uses for the cat sprite —
/// frame1 for "awake" (working/greeting/resting), the nap frame for "asleep" (napping) — rather
/// than re-deriving the mac status-bar icon's separate, coarser 13x9 grid (AppChrome.swift's
/// MenuBarIcon). Sharing PetView's grid keeps the two ports drawing from one visual source of
/// truth; per task-2-brief.md this is the deliberate choice for this port.
///
/// Windows NotifyIcon icons do not auto-recolor for light/dark like a macOS template image
/// (spec §1d / §7 note 9), so rather than shipping separate light/dark ICO assets this renders
/// a single mid-tone brand color (the Tama accent yellow, #F3BD4F — MenuBarView.swift's
/// Palette.yellow) as an opaque foreground over a fully-transparent background, which reads
/// acceptably against both light and dark taskbars.
/// </summary>
public static class IconRenderer
{
    public const int GridCols = 24;
    public const int GridRows = 15;

    /// <summary>The Windows tray-icon sizes needed across the common DPI scales (100/125/150%).</summary>
    public static readonly IReadOnlyList<int> Sizes = new[] { 16, 20, 24 };

    // Foreground brand color: Tama accent yellow (#F3BD4F), BGRA opaque.
    private const byte FgB = 0x4F;
    private const byte FgG = 0xBD;
    private const byte FgR = 0xF3;
    private const byte FgA = 0xFF;

    // Awake silhouette — verbatim PetView.swift:30-46 frame1 (contact pose). 'Y' = body → opaque
    // foreground; 'E' = eyes/nose → left as background (a punched-through notch), same as '.'.
    // Note: frame1's and the nap frame's *outer body outline* (Y vs non-Y) is pixel-identical —
    // PetView's nap pose literally is "frame1 body with eyes closed to dashes" (its own
    // comment). Rendering E as filled (same as Y) would make the awake/asleep icons identical
    // at every size, since the eye markings are the only difference between the two grids.
    // Rendering E as background instead turns the eyes into visible negative-space notches —
    // two small gaps (open eyes) for awake vs. one longer eye-level groove (closed eyes) for
    // asleep — which is what actually makes the two icons distinguishable.
    private static readonly string[] Awake =
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

    // Asleep silhouette — verbatim PetView.swift:70-86 nap frame (eyes closed to dashes).
    private static readonly string[] Asleep =
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

    /// <summary>One BGRA frame per spec size (16/20/24 px) for the given sleep state.</summary>
    public static IReadOnlyList<(int Size, byte[] Bgra)> RenderFrames(bool asleep)
    {
        var grid = asleep ? Asleep : Awake;
        var frames = new List<(int, byte[])>(Sizes.Count);
        foreach (var size in Sizes) frames.Add((size, RenderFrame(grid, size)));
        return frames;
    }

    /// <summary>Renders a single size on demand (e.g. to match a specific DPI's icon metric).</summary>
    public static byte[] RenderFrame(bool asleep, int size) => RenderFrame(asleep ? Asleep : Awake, size);

    private static byte[] RenderFrame(string[] grid, int size)
    {
        var pixels = new byte[size * size * 4];

        // Nearest-neighbor scale of the 24x15 grid onto the square canvas: fit by the binding
        // dimension (here, width — the grid is wider than tall) so it letterboxes (transparent
        // bars top/bottom) rather than overflowing, then center on the other axis.
        var scale = Math.Min((double)size / GridCols, (double)size / GridRows);
        var drawW = (int)Math.Round(GridCols * scale);
        var drawH = (int)Math.Round(GridRows * scale);
        var offsetX = (size - drawW) / 2;
        var offsetY = (size - drawH) / 2;

        for (var y = 0; y < size; y++)
        {
            var gy = y - offsetY;
            var row = gy >= 0 && gy < drawH ? Math.Min((int)(gy / scale), GridRows - 1) : -1;
            for (var x = 0; x < size; x++)
            {
                var idx = (y * size + x) * 4;
                var gx = x - offsetX;
                var filled = false;
                if (row >= 0 && gx >= 0 && gx < drawW)
                {
                    var col = Math.Min((int)(gx / scale), GridCols - 1);
                    filled = grid[row][col] == 'Y';
                }
                if (filled)
                {
                    pixels[idx] = FgB;
                    pixels[idx + 1] = FgG;
                    pixels[idx + 2] = FgR;
                    pixels[idx + 3] = FgA;
                }
                // else: byte[] default-initializes to 0 — fully transparent.
            }
        }
        return pixels;
    }
}
