import Foundation

public struct Rates: Sendable, Equatable {
    public let input: Double       // USD per 1M tokens
    public let output: Double
    public let cacheRead: Double
    public let cacheWrite: Double    // 5-minute cache write (1.25× input)
    public let cacheWrite1h: Double  // 1-hour cache write (2× input); defaults to cacheWrite if omitted
    public init(input: Double, output: Double, cacheRead: Double, cacheWrite: Double, cacheWrite1h: Double? = nil) {
        self.input = input; self.output = output; self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite; self.cacheWrite1h = cacheWrite1h ?? cacheWrite
    }
}

extension Rates: Decodable {
    private enum CodingKeys: String, CodingKey { case input, output, cacheRead, cacheWrite, cacheWrite1h }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // cacheWrite1h is optional in prices.json; absent → priced like a 5-minute write (no regression).
        self.init(input: try c.decode(Double.self, forKey: .input),
                  output: try c.decode(Double.self, forKey: .output),
                  cacheRead: try c.decode(Double.self, forKey: .cacheRead),
                  cacheWrite: try c.decode(Double.self, forKey: .cacheWrite),
                  cacheWrite1h: try c.decodeIfPresent(Double.self, forKey: .cacheWrite1h))
    }
}

/// One provider's rates: a `default` (used when the model is unknown) plus optional per-model-tier
/// overrides keyed by a substring of the model id ("opus"/"sonnet"/"haiku"/"fable"). Claude prices
/// each tier very differently (Opus ≈ 5× Haiku), so pricing the whole provider at one flat rate is
/// wrong — `default` is only the fallback for ids that match no tier.
public struct ProviderRates: Sendable, Equatable {
    public let `default`: Rates
    public let models: [String: Rates]
    public init(default d: Rates, models: [String: Rates] = [:]) {
        self.default = d; self.models = models
    }
}

extension ProviderRates: Decodable {
    private enum CodingKeys: String, CodingKey { case `default`, models }
    public init(from decoder: Decoder) throws {
        // Preferred shape: { "default": {...}, "models": { "opus": {...}, ... } }.
        if let c = try? decoder.container(keyedBy: CodingKeys.self), c.contains(.default) {
            let d = try c.decode(Rates.self, forKey: .default)
            let m = (try? c.decode([String: Rates].self, forKey: .models)) ?? [:]
            self.init(default: d, models: m)
        } else {
            // Back-compat: a bare flat `Rates` object becomes the default with no per-model overrides.
            self.init(default: try Rates(from: decoder), models: [:])
        }
    }
}

public struct CostEstimator: Sendable {
    private let rates: [Provider: ProviderRates]

    /// Model-aware construction (default + per-tier overrides).
    public init(providerRates: [Provider: ProviderRates]) { self.rates = providerRates }

    /// Flat, model-agnostic construction — every model for a provider is priced the same.
    public init(rates: [Provider: Rates]) { self.rates = rates.mapValues { ProviderRates(default: $0) } }

    /// Loads rates from bundled prices.json, falling back to built-in (model-aware) defaults.
    public init() { self.rates = CostEstimator.loadBundledRates() }

    /// Cost of a breakdown for a provider, model-agnostic (uses the provider's default rate).
    public func cost(_ b: TokenBreakdown, provider: Provider) -> Double {
        cost(b, provider: provider, model: nil)
    }

    /// Cost of a breakdown for a provider at the rate for `model` (its tier), or the default rate
    /// when `model` is nil or matches no known tier.
    public func cost(_ b: TokenBreakdown, provider: Provider, model: String?) -> Double {
        guard let pr = rates[provider] else { return 0 }
        let r = Self.rate(for: model, in: pr)
        let write1h = min(b.cacheWrite1h, b.cacheWrite)      // 1-hour portion of cache writes
        let write5m = max(0, b.cacheWrite - write1h)         // remainder is 5-minute
        return Double(b.input)     / 1_000_000 * r.input
             + Double(b.output)    / 1_000_000 * r.output
             + Double(b.cacheRead) / 1_000_000 * r.cacheRead
             + Double(write5m)     / 1_000_000 * r.cacheWrite
             + Double(write1h)     / 1_000_000 * r.cacheWrite1h
    }

    /// Pick the tier rate whose key appears in the (lowercased) model id; else the default.
    static func rate(for model: String?, in pr: ProviderRates) -> Rates {
        guard !pr.models.isEmpty, let m = model?.lowercased() else { return pr.default }
        for (key, r) in pr.models where m.contains(key) { return r }
        return pr.default
    }

    /// Flat per-provider fallback rates (the default tier each provider falls back to). Claude's
    /// default is the Opus tier — the flagship and what Tama's own sessions run on.
    public static let defaultRates: [Provider: Rates] = [
        .claudeCode: Rates(input: 5.0, output: 25.0, cacheRead: 0.5, cacheWrite: 6.25, cacheWrite1h: 10.0),
        .codex:      Rates(input: 2.5, output: 10.0, cacheRead: 0.25, cacheWrite: 2.5),
    ]

    /// Per-tier Claude rates (USD per 1M tokens). cacheRead ≈ 0.1× input, cacheWrite (5-min) ≈ 1.25×
    /// input, cacheWrite1h (1-hour) ≈ 2× input. Claude Code writes to the 1-hour cache.
    static let claudeModelRates: [String: Rates] = [
        "opus":   Rates(input: 5.0,  output: 25.0, cacheRead: 0.5,  cacheWrite: 6.25,  cacheWrite1h: 10.0),
        "sonnet": Rates(input: 3.0,  output: 15.0, cacheRead: 0.3,  cacheWrite: 3.75,  cacheWrite1h: 6.0),
        "haiku":  Rates(input: 1.0,  output: 5.0,  cacheRead: 0.1,  cacheWrite: 1.25,  cacheWrite1h: 2.0),
        "fable":  Rates(input: 10.0, output: 50.0, cacheRead: 1.0,  cacheWrite: 12.5,  cacheWrite1h: 20.0),
    ]

    /// Built-in model-aware fallback used when prices.json is absent or unparseable.
    static var defaultProviderRates: [Provider: ProviderRates] {
        [
            .claudeCode: ProviderRates(default: defaultRates[.claudeCode]!, models: claudeModelRates),
            .codex:      ProviderRates(default: defaultRates[.codex]!),
        ]
    }

    /// Searches likely bundle locations WITHOUT touching Bundle.module (which calls fatalError
    /// internally when the resource bundle is missing — uncatchable by try?).
    private static func bundledPricesURL() -> URL? {
        let bundleName = "Tama_TamaCore.bundle"
        let bases: [URL] = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"),
        ].compactMap { $0 }
        for base in bases {
            let inBundle = base.appendingPathComponent(bundleName).appendingPathComponent("prices.json")
            if FileManager.default.fileExists(atPath: inBundle.path) { return inBundle }
            let direct = base.appendingPathComponent("prices.json")
            if FileManager.default.fileExists(atPath: direct.path) { return direct }
        }
        return nil
    }

    static func loadBundledRates() -> [Provider: ProviderRates] {
        guard let url = bundledPricesURL(),
              // Read the bundled prices.json through SafeFileReader (size cap + symlink/regular-file
              // check), keeping every disk read on the one hardened path. 1 MiB is ample headroom.
              let data = SafeFileReader.data(at: url, maxBytes: 1 << 20),
              let raw = try? JSONDecoder().decode([String: ProviderRates].self, from: data) else {
            return defaultProviderRates
        }
        var out: [Provider: ProviderRates] = [:]
        for (k, v) in raw { if let p = Provider(rawValue: k) { out[p] = v } }
        return out.isEmpty ? defaultProviderRates : out
    }
}
