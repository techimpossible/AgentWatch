import Foundation

struct CostBucket: Identifiable, Hashable {
    let key: String
    let cost: Double
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int

    var id: String { key }
    var totalTokens: Int { inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens }
}

struct CostAggregate: Sendable {
    var byDay: [String: Double] = [:]                     // "YYYY-MM-DD" -> cost
    var byProfile: [String: Double] = [:]                 // profile -> cost
    var byProject: [String: Double] = [:]                 // "profile · project" -> cost
    var byModel: [String: Double] = [:]                   // model -> cost
    var totalCost: Double = 0
    var totalInputTokens: Int = 0
    var totalOutputTokens: Int = 0
    var totalCacheRead: Int = 0
    var totalCacheWrite: Int = 0
    var entriesCounted: Int = 0
    var asOf: Date = Date()
}
