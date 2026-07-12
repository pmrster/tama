using Tama.Core;

namespace Tama.Core.Tests;

[TestClass]
public sealed class TokenBreakdownTests
{
    [TestMethod]
    public void Total_sums_input_output_and_both_cache_kinds_but_not_the_1h_subset()
    {
        var b = new TokenBreakdown(Input: 10, Output: 20, CacheRead: 30, CacheWrite: 40, CacheWrite1h: 40);
        Assert.AreEqual(100, b.Total); // CacheWrite1h is a subset of CacheWrite, never added
    }

    [TestMethod]
    public void Plus_adds_every_field()
    {
        var sum = new TokenBreakdown(1, 2, 3, 4, 5) + new TokenBreakdown(10, 20, 30, 40, 50);
        Assert.AreEqual(new TokenBreakdown(11, 22, 33, 44, 55), sum);
    }

    [TestMethod]
    public void Default_is_all_zero()
    {
        Assert.AreEqual(0, default(TokenBreakdown).Total);
    }
}
