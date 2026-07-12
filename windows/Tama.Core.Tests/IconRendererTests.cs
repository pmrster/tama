using Tama.Core.Ui;

namespace Tama.Core.Tests;

[TestClass]
public sealed class IconRendererTests
{
    // BGRA = 4 bytes/pixel; frame is a square canvas of `size` x `size`.
    private static int ExpectedLength(int size) => size * size * 4;

    [TestMethod]
    public void Renders_exactly_the_three_spec_sizes()
    {
        var frames = IconRenderer.RenderFrames(asleep: false);
        CollectionAssert.AreEquivalent(new[] { 16, 20, 24 }, frames.Select(f => f.Size).ToArray());
    }

    [TestMethod]
    public void Each_frame_buffer_is_size_squared_times_4_bytes_bgra()
    {
        foreach (var (size, bgra) in IconRenderer.RenderFrames(asleep: false))
            Assert.AreEqual(ExpectedLength(size), bgra.Length, $"size {size}");
    }

    [TestMethod]
    public void Asleep_frames_are_also_the_three_spec_sizes_and_correctly_sized()
    {
        foreach (var (size, bgra) in IconRenderer.RenderFrames(asleep: true))
            Assert.AreEqual(ExpectedLength(size), bgra.Length, $"size {size}");
    }

    [TestMethod]
    public void Palette_is_exactly_two_colors_foreground_or_fully_transparent()
    {
        // "2-color pixel rows": every pixel is either fully-transparent background (alpha 0,
        // all channels 0) or fully-opaque foreground (alpha 255, same BGR triple everywhere) —
        // no antialiasing / no third color, matching the nearest-neighbor integer-scale spec.
        foreach (var (_, bgra) in IconRenderer.RenderFrames(asleep: false))
        {
            byte? fgB = null, fgG = null, fgR = null;
            for (var i = 0; i < bgra.Length; i += 4)
            {
                byte b = bgra[i], g = bgra[i + 1], r = bgra[i + 2], a = bgra[i + 3];
                if (a == 0)
                {
                    Assert.AreEqual(0, b);
                    Assert.AreEqual(0, g);
                    Assert.AreEqual(0, r);
                }
                else
                {
                    Assert.AreEqual(255, a);
                    fgB ??= b; fgG ??= g; fgR ??= r;
                    Assert.AreEqual(fgB, b);
                    Assert.AreEqual(fgG, g);
                    Assert.AreEqual(fgR, r);
                }
            }
        }
    }

    [TestMethod]
    public void Awake_and_asleep_render_different_pixel_data_at_every_size()
    {
        var awake = IconRenderer.RenderFrames(asleep: false).ToDictionary(f => f.Size, f => f.Bgra);
        var asleepFrames = IconRenderer.RenderFrames(asleep: true).ToDictionary(f => f.Size, f => f.Bgra);
        foreach (var size in awake.Keys)
            CollectionAssert.AreNotEqual(awake[size], asleepFrames[size], $"size {size}");
    }

    [TestMethod]
    public void Every_frame_has_at_least_one_foreground_pixel()
    {
        // A silhouette that renders as fully transparent would be an invisible/broken tray icon.
        foreach (var (size, bgra) in IconRenderer.RenderFrames(asleep: false).Concat(IconRenderer.RenderFrames(asleep: true)))
        {
            var hasForeground = false;
            for (var i = 3; i < bgra.Length; i += 4) if (bgra[i] != 0) { hasForeground = true; break; }
            Assert.IsTrue(hasForeground, $"size {size}");
        }
    }

    [TestMethod]
    public void Frame_is_letterboxed_and_centered_for_the_24x15_source_grid()
    {
        // Source grid is 24 wide x 15 tall (wider than the square canvas), so scaling by width
        // leaves empty (transparent) rows top and bottom, roughly symmetric.
        var (size, bgra) = IconRenderer.RenderFrames(asleep: false).First(f => f.Size == 24);
        bool RowHasForeground(int y)
        {
            for (var x = 0; x < size; x++)
            {
                var idx = (y * size + x) * 4 + 3;
                if (bgra[idx] != 0) return true;
            }
            return false;
        }
        Assert.IsFalse(RowHasForeground(0), "top row should be letterboxed (transparent)");
        Assert.IsFalse(RowHasForeground(size - 1), "bottom row should be letterboxed (transparent)");
    }
}
