import Foundation

// Per-million-token rates in USD. Source: docs.anthropic.com/pricing
// Rates as of 2026-05-11. Update this file when Anthropic changes prices.
struct ModelRate: Sendable {
    let input: Double
    let output: Double
    let cacheWrite5m: Double
    let cacheWrite1h: Double
    let cacheRead: Double
}

enum Pricing {
    static let asOf = "2026-05-11"

    private static let opusNew    = ModelRate(input: 5.00,  output: 25.00, cacheWrite5m: 6.25,  cacheWrite1h: 10.00, cacheRead: 0.50)  // 4.5, 4.6, 4.7
    private static let opusLegacy = ModelRate(input: 15.00, output: 75.00, cacheWrite5m: 18.75, cacheWrite1h: 30.00, cacheRead: 1.50)  // 3, 4, 4.1
    private static let sonnet4x   = ModelRate(input: 3.00,  output: 15.00, cacheWrite5m: 3.75,  cacheWrite1h: 6.00,  cacheRead: 0.30)
    private static let haiku45    = ModelRate(input: 1.00,  output: 5.00,  cacheWrite5m: 1.25,  cacheWrite1h: 2.00,  cacheRead: 0.10)
    private static let haiku35    = ModelRate(input: 0.80,  output: 4.00,  cacheWrite5m: 1.00,  cacheWrite1h: 1.60,  cacheRead: 0.08)
    private static let haiku3     = ModelRate(input: 0.25,  output: 1.25,  cacheWrite5m: 0.30,  cacheWrite1h: 0.50,  cacheRead: 0.03)

    /// Match against any model string seen in the wild:
    ///  - Anthropic native:      `claude-opus-4-7-20260416`, `claude-3-5-haiku-20241022`
    ///  - Proxy / gateway:       `anthropic/claude-4.7-opus-20260416`, `anthropic/claude-4.6-sonnet-20260217`
    ///  - Bedrock / Vertex:      `anthropic.claude-opus-4-v1:0` etc.
    /// Strategy: lowercase, then check both family-version and version-family orderings.
    static func rate(for model: String) -> ModelRate? {
        let s = model.lowercased()

        // Helper: does the string contain any of these substrings?
        func has(_ needles: String...) -> Bool {
            for n in needles where s.contains(n) { return true }
            return false
        }

        // Opus 4.5 / 4.6 / 4.7 (new pricing)
        if has("opus-4.7", "4.7-opus", "opus-4-7",
               "opus-4.6", "4.6-opus", "opus-4-6",
               "opus-4.5", "4.5-opus", "opus-4-5") {
            return opusNew
        }
        // Opus 4 / 4.1 / Opus 3 (legacy pricing)
        if has("opus-4.1", "4.1-opus", "opus-4-1") { return opusLegacy }
        if has("opus-3",   "3-opus",   "opus-3-0") { return opusLegacy }
        if has("opus-4",   "4-opus",   "opus-4-0") { return opusLegacy }

        // Sonnet 4.x and 3.7
        if has("sonnet-4.6", "4.6-sonnet", "sonnet-4-6",
               "sonnet-4.5", "4.5-sonnet", "sonnet-4-5",
               "sonnet-4",   "4-sonnet",   "sonnet-4-0",
               "sonnet-3.7", "3.7-sonnet", "sonnet-3-7") {
            return sonnet4x
        }

        // Haiku
        if has("haiku-4.5", "4.5-haiku", "haiku-4-5") { return haiku45 }
        if has("haiku-3.5", "3.5-haiku", "haiku-3-5") { return haiku35 }
        if has("haiku-3",   "3-haiku",   "haiku-3-0") { return haiku3 }

        return nil
    }

    static func cost(model: String, usage: UsageBlock) -> Double {
        guard let r = rate(for: model) else { return 0 }
        let m = 1_000_000.0
        return Double(usage.inputTokens) * r.input / m
            + Double(usage.outputTokens) * r.output / m
            + Double(usage.cacheCreationInputTokens) * r.cacheWrite5m / m
            + Double(usage.cacheReadInputTokens) * r.cacheRead / m
    }
}
