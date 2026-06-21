import XCTest
import TamaCore

final class CostEstimatorTests: XCTestCase {
    func test_cost_uses_per_million_rates() {
        let est = CostEstimator(rates: [
            .claudeCode: Rates(input: 3.0, output: 15.0, cacheRead: 0.3, cacheWrite: 3.75)
        ])
        let bd = TokenBreakdown(input: 1_000_000, output: 1_000_000, cacheRead: 0, cacheWrite: 0)
        XCTAssertEqual(est.cost(bd, provider: .claudeCode), 18.0, accuracy: 0.0001)
    }

    func test_cost_uses_model_specific_rate_when_model_given() {
        // Claude is priced per model tier: Opus ≠ Sonnet ≠ Haiku. The estimator matches the
        // tier name as a substring of the model id (robust to version suffixes).
        let est = CostEstimator(providerRates: [
            .claudeCode: ProviderRates(
                default: Rates(input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25),   // Opus
                models: [
                    "sonnet": Rates(input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75),
                    "haiku":  Rates(input: 1, output: 5,  cacheRead: 0.1, cacheWrite: 1.25),
                ]),
        ])
        let bd = TokenBreakdown(input: 1_000_000)
        XCTAssertEqual(est.cost(bd, provider: .claudeCode, model: "claude-opus-4-8"), 5.0, accuracy: 0.0001)
        XCTAssertEqual(est.cost(bd, provider: .claudeCode, model: "claude-sonnet-4-6"), 3.0, accuracy: 0.0001)
        XCTAssertEqual(est.cost(bd, provider: .claudeCode, model: "claude-haiku-4-5"), 1.0, accuracy: 0.0001)
    }

    func test_cost_falls_back_to_default_for_unknown_or_nil_model() {
        let est = CostEstimator(providerRates: [
            .claudeCode: ProviderRates(
                default: Rates(input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25),
                models: ["sonnet": Rates(input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75)]),
        ])
        let bd = TokenBreakdown(input: 1_000_000)
        XCTAssertEqual(est.cost(bd, provider: .claudeCode, model: "some-future-model"), 5.0, accuracy: 0.0001)
        XCTAssertEqual(est.cost(bd, provider: .claudeCode, model: nil), 5.0, accuracy: 0.0001)
        // The no-model overload also uses the default.
        XCTAssertEqual(est.cost(bd, provider: .claudeCode), 5.0, accuracy: 0.0001)
    }

    func test_bundled_rates_price_opus_above_sonnet_above_haiku() {
        let est = CostEstimator()   // bundled prices.json, or model-aware built-in defaults
        let bd = TokenBreakdown(input: 1_000_000)
        let opus = est.cost(bd, provider: .claudeCode, model: "claude-opus-4-8")
        let sonnet = est.cost(bd, provider: .claudeCode, model: "claude-sonnet-4-6")
        let haiku = est.cost(bd, provider: .claudeCode, model: "claude-haiku-4-5")
        XCTAssertGreaterThan(opus, sonnet)
        XCTAssertGreaterThan(sonnet, haiku)
        XCTAssertEqual(opus, 5.0, accuracy: 0.0001)   // Opus input is $5 / 1M tokens
    }

    func test_one_hour_cache_writes_cost_more_than_five_minute() {
        // Claude Code writes to the 1-hour cache (cache_creation.ephemeral_1h_input_tokens),
        // billed at 2× input ($10/M opus), not the 5-minute rate (1.25× = $6.25/M). cacheWrite1h
        // is the subset of cacheWrite that used the 1-hour TTL.
        let est = CostEstimator(providerRates: [
            .claudeCode: ProviderRates(default: Rates(input: 5, output: 25, cacheRead: 0.5,
                                                      cacheWrite: 6.25, cacheWrite1h: 10.0)),
        ])
        let allOneHour = TokenBreakdown(cacheWrite: 1_000_000, cacheWrite1h: 1_000_000)
        XCTAssertEqual(est.cost(allOneHour, provider: .claudeCode), 10.0, accuracy: 0.0001)
        let allFiveMin = TokenBreakdown(cacheWrite: 1_000_000, cacheWrite1h: 0)
        XCTAssertEqual(est.cost(allFiveMin, provider: .claudeCode), 6.25, accuracy: 0.0001)
        // Mixed: 600k 1-hour ($6.00) + 400k 5-minute ($2.50) = $8.50
        let mixed = TokenBreakdown(cacheWrite: 1_000_000, cacheWrite1h: 600_000)
        XCTAssertEqual(est.cost(mixed, provider: .claudeCode), 8.50, accuracy: 0.0001)
    }

    func test_bundled_one_hour_cache_write_is_double_input() {
        let est = CostEstimator()   // bundled prices.json or built-in defaults
        let bd = TokenBreakdown(cacheWrite: 1_000_000, cacheWrite1h: 1_000_000)
        // Opus 1-hour cache write = 2 × $5 input = $10 / 1M tokens
        XCTAssertEqual(est.cost(bd, provider: .claudeCode, model: "claude-opus-4-8"), 10.0, accuracy: 0.0001)
    }

    func test_unknown_provider_is_zero() {
        let est = CostEstimator(rates: [:])
        XCTAssertEqual(est.cost(TokenBreakdown(input: 5), provider: .codex), 0)
    }

    func test_default_rates_are_nonzero() {
        XCTAssertNotNil(CostEstimator.defaultRates[.claudeCode])
        XCTAssertNotNil(CostEstimator.defaultRates[.codex])
    }

    /// Verifies the no-arg init (bundled-load path) never crashes and returns working rates.
    /// This catches regressions where Bundle.module fatalError would terminate the process.
    func test_bundled_init_does_not_crash_and_returns_working_rates() {
        // This must not crash — the fix replaces Bundle.module (which fatalErrors when the
        // resource bundle is absent) with a crash-free best-effort search + defaultRates fallback.
        let est = CostEstimator()
        let bd = TokenBreakdown(input: 1_000_000, output: 0, cacheRead: 0, cacheWrite: 0)
        // defaultRates has claudeCode.input = 3.0, so cost for 1M input tokens = 3.0
        XCTAssertGreaterThan(est.cost(bd, provider: .claudeCode), 0,
            "CostEstimator() init must return non-zero rates (either bundled or default)")
    }
}
