using System.Reflection;
using System.Text.Json;

namespace Tama.Core;

/// <summary>USD per 1M tokens. CacheWrite = 5-minute TTL rate; CacheWrite1h = 1-hour TTL rate
/// (defaults to CacheWrite when a price file omits it).</summary>
public readonly record struct Rates(
    double Input, double Output, double CacheRead, double CacheWrite, double CacheWrite1h)
{
    public Rates(double Input, double Output, double CacheRead, double CacheWrite)
        : this(Input, Output, CacheRead, CacheWrite, CacheWrite) { }
}

/// <summary>One provider's rates: a Default (unknown model) plus per-tier overrides keyed by a
/// substring of the model id ("opus"/"sonnet"/…). Mirror of the Swift ProviderRates.</summary>
public sealed record ProviderRates(Rates Default, IReadOnlyDictionary<string, Rates> Models);

/// <summary>Estimates pay-as-you-go API cost of token usage. Mirror of the Swift CostEstimator.</summary>
public sealed class CostEstimator
{
    private readonly IReadOnlyDictionary<Provider, ProviderRates> _rates;

    public CostEstimator(IReadOnlyDictionary<Provider, ProviderRates> providerRates) =>
        _rates = providerRates;

    /// <summary>Loads rates from the embedded prices.json, falling back to built-in defaults.</summary>
    public CostEstimator() => _rates = LoadEmbeddedRates();

    /// <summary>Cost of a breakdown at the rate for the model's tier, or the provider default.</summary>
    public double Cost(TokenBreakdown b, Provider provider, string? model = null)
    {
        if (!_rates.TryGetValue(provider, out var pr)) return 0;
        var r = RateFor(model, pr);
        var write1h = Math.Min(b.CacheWrite1h, b.CacheWrite);   // 1-hour portion of cache writes
        var write5m = Math.Max(0, b.CacheWrite - write1h);      // remainder is 5-minute
        return b.Input / 1e6 * r.Input
             + b.Output / 1e6 * r.Output
             + b.CacheRead / 1e6 * r.CacheRead
             + write5m / 1e6 * r.CacheWrite
             + write1h / 1e6 * r.CacheWrite1h;
    }

    /// <summary>Pick the tier whose key appears in the lowercased model id; else the default.</summary>
    public static Rates RateFor(string? model, ProviderRates pr)
    {
        if (pr.Models.Count == 0 || model is null) return pr.Default;
        var m = model.ToLowerInvariant();
        foreach (var (key, r) in pr.Models)
            if (m.Contains(key, StringComparison.Ordinal)) return r;
        return pr.Default;
    }

    // Built-in model-aware fallback used when prices.json is absent or unparseable.
    // Claude's default is the Opus tier; per-tier table mirrors the Swift claudeModelRates.
    internal static IReadOnlyDictionary<Provider, ProviderRates> DefaultProviderRates => new Dictionary<Provider, ProviderRates>
    {
        [Provider.ClaudeCode] = new(new Rates(5.0, 25.0, 0.5, 6.25, 10.0), new Dictionary<string, Rates>
        {
            ["opus"] = new(5.0, 25.0, 0.5, 6.25, 10.0),
            ["sonnet"] = new(3.0, 15.0, 0.3, 3.75, 6.0),
            ["haiku"] = new(1.0, 5.0, 0.1, 1.25, 2.0),
            ["fable"] = new(10.0, 50.0, 1.0, 12.5, 20.0),
        }),
        [Provider.Codex] = new(new Rates(2.5, 10.0, 0.25, 2.5), new Dictionary<string, Rates>()),
    };

    private static IReadOnlyDictionary<Provider, ProviderRates> LoadEmbeddedRates()
    {
        try
        {
            using var stream = Assembly.GetExecutingAssembly()
                .GetManifestResourceStream("Tama.Core.prices.json");
            if (stream is null) return DefaultProviderRates;
            using var doc = JsonDocument.Parse(stream);
            if (doc.RootElement.ValueKind != JsonValueKind.Object) return DefaultProviderRates;
            var result = new Dictionary<Provider, ProviderRates>();
            foreach (var prop in doc.RootElement.EnumerateObject())
            {
                var provider = prop.Name switch
                {
                    "claudeCode" => Provider.ClaudeCode,
                    "codex" => Provider.Codex,
                    "gemini" => Provider.Gemini,
                    "antigravity" => Provider.Antigravity,
                    _ => (Provider?)null,
                };
                if (provider is null || ParseProviderRates(prop.Value) is not { } pr) continue;
                result[provider.Value] = pr;
            }
            return result.Count > 0 ? result : DefaultProviderRates;
        }
        catch (JsonException) { return DefaultProviderRates; }
    }

    private static ProviderRates? ParseProviderRates(JsonElement el)
    {
        if (el.ValueKind != JsonValueKind.Object) return null;
        // Preferred shape: { "default": {...}, "models": {...} }; back-compat: a bare Rates object.
        if (el.TryGetProperty("default", out var d))
        {
            if (ParseRates(d) is not { } def) return null;
            var models = new Dictionary<string, Rates>();
            if (el.TryGetProperty("models", out var ms) && ms.ValueKind == JsonValueKind.Object)
                foreach (var m in ms.EnumerateObject())
                    if (ParseRates(m.Value) is { } r) models[m.Name] = r;
            return new ProviderRates(def, models);
        }
        return ParseRates(el) is { } bare
            ? new ProviderRates(bare, new Dictionary<string, Rates>()) : null;
    }

    private static Rates? ParseRates(JsonElement el)
    {
        if (el.ValueKind != JsonValueKind.Object) return null;
        double? Get(string name) =>
            el.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Number
                ? v.GetDouble() : null;
        if (Get("input") is not { } i || Get("output") is not { } o
            || Get("cacheRead") is not { } cr || Get("cacheWrite") is not { } cw) return null;
        // cacheWrite1h optional: absent → priced like a 5-minute write (no regression).
        return Get("cacheWrite1h") is { } cw1h
            ? new Rates(i, o, cr, cw, cw1h) : new Rates(i, o, cr, cw);
    }
}
