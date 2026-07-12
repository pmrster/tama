using Tama.Core;

namespace Tama.Core.Tests;

[TestClass]
public sealed class CostEstimatorTests
{
    [TestMethod]
    public void Prices_each_token_type_separately_including_1h_cache_split()
    {
        var rates = new Rates(Input: 5.0, Output: 25.0, CacheRead: 0.5, CacheWrite: 6.25, CacheWrite1h: 10.0);
        var est = new CostEstimator(new Dictionary<Provider, ProviderRates>
        {
            [Provider.ClaudeCode] = new(rates, new Dictionary<string, Rates>()),
        });
        // 1M of each type; 400K of the 1M cacheWrite used the 1h TTL.
        var b = new TokenBreakdown(1_000_000, 1_000_000, 1_000_000, 1_000_000, 400_000);
        var expected = 5.0 + 25.0 + 0.5 + 0.6 * 6.25 + 0.4 * 10.0;
        Assert.AreEqual(expected, est.Cost(b, Provider.ClaudeCode), 1e-9);
    }

    [TestMethod]
    public void Model_tier_substring_match_overrides_default()
    {
        var opus = new Rates(5.0, 25.0, 0.5, 6.25, 10.0);
        var haiku = new Rates(1.0, 5.0, 0.1, 1.25, 2.0);
        var est = new CostEstimator(new Dictionary<Provider, ProviderRates>
        {
            [Provider.ClaudeCode] = new(opus, new Dictionary<string, Rates> { ["haiku"] = haiku }),
        });
        var b = new TokenBreakdown(Input: 1_000_000);
        Assert.AreEqual(1.0, est.Cost(b, Provider.ClaudeCode, "claude-haiku-4-5"), 1e-9);
        Assert.AreEqual(5.0, est.Cost(b, Provider.ClaudeCode, "claude-opus-4-8"), 1e-9);   // no tier match → default
        Assert.AreEqual(5.0, est.Cost(b, Provider.ClaudeCode, null), 1e-9);
    }

    [TestMethod]
    public void Unknown_provider_costs_zero()
    {
        var est = new CostEstimator(new Dictionary<Provider, ProviderRates>());
        Assert.AreEqual(0, est.Cost(new TokenBreakdown(Input: 1_000_000), Provider.Gemini));
    }

    [TestMethod]
    public void Default_constructor_loads_embedded_prices_with_claude_tiers()
    {
        var est = new CostEstimator();
        var b = new TokenBreakdown(Input: 1_000_000);
        Assert.AreEqual(3.0, est.Cost(b, Provider.ClaudeCode, "claude-sonnet-5"), 1e-9);  // sonnet tier from prices.json
        Assert.AreEqual(2.5, est.Cost(b, Provider.Codex, "gpt-5-codex"), 1e-9);
    }

    [TestMethod]
    public void Rates_without_cacheWrite1h_price_1h_writes_at_the_5m_rate()
    {
        var rates = new Rates(Input: 2.5, Output: 10.0, CacheRead: 0.25, CacheWrite: 2.5);
        var est = new CostEstimator(new Dictionary<Provider, ProviderRates>
        {
            [Provider.Codex] = new(rates, new Dictionary<string, Rates>()),
        });
        var b = new TokenBreakdown(CacheWrite: 1_000_000, CacheWrite1h: 1_000_000);
        Assert.AreEqual(2.5, est.Cost(b, Provider.Codex), 1e-9);
    }
}
