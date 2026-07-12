using Tama.Core.Ui;

namespace Tama.Core.Tests;

[TestClass]
public sealed class CatSpriteTests
{
    // ---- Frame dimensions / pixel counts (verbatim-ness of the sprite transcription) ----

    [TestMethod]
    public void All_three_frames_are_24_wide_by_15_tall()
    {
        foreach (var frame in new[] { CatSprite.Frame1, CatSprite.Frame2, CatSprite.Nap })
        {
            Assert.AreEqual(CatSprite.GridRows, frame.Count);
            foreach (var row in frame) Assert.AreEqual(CatSprite.GridCols, row.Length);
        }
    }

    [TestMethod]
    public void Frame1_pixel_counts_match_PetView_swift_verbatim()
    {
        // PetView.swift:30-46 — counted independently against the Swift source.
        Assert.AreEqual(178, CountChar(CatSprite.Frame1, 'Y'));
        Assert.AreEqual(7, CountChar(CatSprite.Frame1, 'E'));
    }

    [TestMethod]
    public void Frame2_pixel_counts_match_PetView_swift_verbatim()
    {
        // PetView.swift:49-65
        Assert.AreEqual(194, CountChar(CatSprite.Frame2, 'Y'));
        Assert.AreEqual(7, CountChar(CatSprite.Frame2, 'E'));
    }

    [TestMethod]
    public void Nap_pixel_counts_match_PetView_swift_verbatim()
    {
        // PetView.swift:70-86
        Assert.AreEqual(179, CountChar(CatSprite.Nap, 'Y'));
        Assert.AreEqual(6, CountChar(CatSprite.Nap, 'E'));
    }

    [TestMethod]
    public void Pixels_helper_maps_each_CatFrame_enum_value_to_its_grid()
    {
        Assert.AreSame(CatSprite.Frame1, CatSprite.Pixels(CatSprite.CatFrame.Walk1));
        Assert.AreSame(CatSprite.Frame2, CatSprite.Pixels(CatSprite.CatFrame.Walk2));
        Assert.AreSame(CatSprite.Nap, CatSprite.Pixels(CatSprite.CatFrame.Nap));
    }

    private static int CountChar(IReadOnlyList<string> frame, char c)
    {
        var count = 0;
        foreach (var row in frame) foreach (var ch in row) if (ch == c) count++;
        return count;
    }

    // ---- Energy mapping (PetView.swift:11-17) ----

    [TestMethod]
    public void Working_energy_is_at_least_1_even_at_zero_intensity()
    {
        Assert.AreEqual(1, CatSprite.Energy(Mood.Working(0)));
    }

    [TestMethod]
    public void Working_energy_matches_intensity_above_1()
    {
        Assert.AreEqual(5, CatSprite.Energy(Mood.Working(5)));
    }

    [TestMethod]
    public void Greeting_energy_is_fixed_at_2()
    {
        Assert.AreEqual(2, CatSprite.Energy(Mood.Greeting));
    }

    [TestMethod]
    public void Resting_and_napping_energy_is_zero()
    {
        Assert.AreEqual(0, CatSprite.Energy(Mood.Resting));
        Assert.AreEqual(0, CatSprite.Energy(Mood.Napping));
    }

    // ---- Still poses (energy == 0) ----

    [TestMethod]
    public void Resting_is_centered_frame1_facing_right_not_napping()
    {
        var m = CatSprite.Motion(t: 12.3, spriteW: 48, width: 110, mood: Mood.Resting);
        Assert.AreEqual(6 + Math.Max(10.0, 110 - 48 - 12) / 2, m.X, 1e-9);
        Assert.IsFalse(m.FacingLeft);
        Assert.AreEqual(CatSprite.CatFrame.Walk1, m.Frame);
        Assert.IsFalse(m.IsNapping);
        Assert.IsFalse(m.MeowVisible);
        Assert.AreEqual(0, m.ZDrops.Count);
    }

    [TestMethod]
    public void Napping_is_centered_nap_frame_with_three_z_drops()
    {
        var m = CatSprite.Motion(t: 12.3, spriteW: 48, width: 110, mood: Mood.Napping);
        Assert.AreEqual(6 + Math.Max(10.0, 110 - 48 - 12) / 2, m.X, 1e-9);
        Assert.IsFalse(m.FacingLeft);
        Assert.AreEqual(CatSprite.CatFrame.Nap, m.Frame);
        Assert.IsTrue(m.IsNapping);
        Assert.IsFalse(m.MeowVisible);
        Assert.AreEqual(3, m.ZDrops.Count);
    }

    // ---- Triangle-wave walk position + direction flip (PetView.swift:219-223) ----

    [TestMethod]
    public void Triangle_wave_starts_at_the_left_margin_facing_right()
    {
        // width=110, spriteW=48, margin=6 -> range = max(10, 110-48-12) = 50.
        var m = CatSprite.Motion(t: 0, spriteW: 48, width: 110, mood: Mood.Working(1));
        Assert.AreEqual(6.0, m.X, 1e-9);
        Assert.IsFalse(m.FacingLeft);
    }

    [TestMethod]
    public void Triangle_wave_reaches_the_far_end_and_flips_to_facing_left()
    {
        // energy=1 -> speed=38; range=50 -> phase reaches 1 (turn point) at t = range/speed.
        var range = 50.0;
        var speed = 38.0;
        var t = range / speed;
        var m = CatSprite.Motion(t: t, spriteW: 48, width: 110, mood: Mood.Working(1));
        Assert.AreEqual(6.0 + range, m.X, 1e-6);
        Assert.IsTrue(m.FacingLeft);
    }

    [TestMethod]
    public void Triangle_wave_returns_to_the_left_margin_after_a_full_cycle()
    {
        var range = 50.0;
        var speed = 38.0;
        var t = 2 * range / speed; // phase wraps back to 0 (mod 2)
        var m = CatSprite.Motion(t: t, spriteW: 48, width: 110, mood: Mood.Working(1));
        Assert.AreEqual(6.0, m.X, 1e-6);
        Assert.IsFalse(m.FacingLeft);
    }

    [TestMethod]
    public void Range_is_floored_at_10_units_for_very_narrow_containers()
    {
        // width - spriteW - margin*2 would be negative here; range should clamp to 10.
        var m = CatSprite.Motion(t: 0, spriteW: 48, width: 50, mood: Mood.Resting);
        Assert.AreEqual(6 + 10.0 / 2, m.X, 1e-9);
    }

    // ---- Frame alternation (PetView.swift:226-228) ----

    [TestMethod]
    public void Walk_frame_alternates_between_Walk1_and_Walk2_over_time()
    {
        // energy=1 -> stepHz = 3.2 + min(1,6)*0.4 = 3.6.
        var early = CatSprite.Motion(t: 0.0, spriteW: 48, width: 110, mood: Mood.Working(1));
        Assert.AreEqual(CatSprite.CatFrame.Walk1, early.Frame); // int(0*3.6)%2 == 0

        var mid = CatSprite.Motion(t: 0.3, spriteW: 48, width: 110, mood: Mood.Working(1));
        Assert.AreEqual(CatSprite.CatFrame.Walk2, mid.Frame); // int(0.3*3.6)=int(1.08)=1 -> %2==1

        var later = CatSprite.Motion(t: 0.6, spriteW: 48, width: 110, mood: Mood.Working(1));
        Assert.AreEqual(CatSprite.CatFrame.Walk1, later.Frame); // int(0.6*3.6)=int(2.16)=2 -> %2==0
    }

    // ---- Meow window (PetView.swift:194-196) ----

    [TestMethod]
    public void Meow_is_visible_during_the_first_second_of_each_7_second_loop_while_moving()
    {
        var visible = CatSprite.Motion(t: 0.5, spriteW: 48, width: 110, mood: Mood.Greeting);
        Assert.IsTrue(visible.MeowVisible);

        var hidden = CatSprite.Motion(t: 1.5, spriteW: 48, width: 110, mood: Mood.Greeting);
        Assert.IsFalse(hidden.MeowVisible);

        var loopedAround = CatSprite.Motion(t: 7.5, spriteW: 48, width: 110, mood: Mood.Greeting);
        Assert.IsTrue(loopedAround.MeowVisible);
    }

    [TestMethod]
    public void Meow_never_shows_when_stationary_even_inside_the_visible_window()
    {
        var m = CatSprite.Motion(t: 0.5, spriteW: 48, width: 110, mood: Mood.Resting);
        Assert.IsFalse(m.MeowVisible);
    }

    // ---- Sleep-z loop parameters (PetView.swift:146-159) ----

    [TestMethod]
    public void Z_drops_have_the_expected_phase_and_opacity_at_the_start_of_the_loop()
    {
        var m = CatSprite.Motion(t: 0.0, spriteW: 48, width: 110, mood: Mood.Napping);
        Assert.AreEqual(3, m.ZDrops.Count);

        Assert.AreEqual(0, m.ZDrops[0].Index);
        Assert.AreEqual(0.0, m.ZDrops[0].P, 1e-9);
        Assert.AreEqual(0.85, m.ZDrops[0].Opacity, 1e-9);

        Assert.AreEqual(1, m.ZDrops[1].Index);
        Assert.AreEqual(1.0 / 3.0, m.ZDrops[1].P, 1e-9);
        Assert.AreEqual(0.85 * (2.0 / 3.0), m.ZDrops[1].Opacity, 1e-9);

        Assert.AreEqual(2, m.ZDrops[2].Index);
        Assert.AreEqual(2.0 / 3.0, m.ZDrops[2].P, 1e-9);
        Assert.AreEqual(0.85 * (1.0 / 3.0), m.ZDrops[2].Opacity, 1e-9);
    }

    [TestMethod]
    public void Z_loop_phase_wraps_every_3_seconds()
    {
        var atZero = CatSprite.Motion(t: 0.0, spriteW: 48, width: 110, mood: Mood.Napping);
        var oneLoopLater = CatSprite.Motion(t: 3.0, spriteW: 48, width: 110, mood: Mood.Napping);
        for (var i = 0; i < 3; i++)
            Assert.AreEqual(atZero.ZDrops[i].P, oneLoopLater.ZDrops[i].P, 1e-9);
    }

    [TestMethod]
    public void No_z_drops_while_resting_or_working_only_while_napping()
    {
        Assert.AreEqual(0, CatSprite.Motion(0, 48, 110, Mood.Resting).ZDrops.Count);
        Assert.AreEqual(0, CatSprite.Motion(0, 48, 110, Mood.Working(1)).ZDrops.Count);
        Assert.AreEqual(0, CatSprite.Motion(0, 48, 110, Mood.Greeting).ZDrops.Count);
        Assert.AreEqual(3, CatSprite.Motion(0, 48, 110, Mood.Napping).ZDrops.Count);
    }
}
