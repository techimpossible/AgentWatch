import Foundation

enum Role: String, Sendable {
    case user, assistant, system, other
}

enum ContentBlock: Sendable, Hashable {
    case text(String)
    case thinking(String)
    case redactedThinking
    case toolUse(name: String, input: String)
    case toolResult(text: String, isError: Bool)
    case unknown(String)
}

struct UsageBlock: Sendable, Hashable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationInputTokens: Int
    let cacheReadInputTokens: Int
}

struct TranscriptEntry: Identifiable, Sendable, Hashable {
    let id: String           // uuid from JSONL
    let role: Role
    let timestamp: Date?
    let blocks: [ContentBlock]
    let model: String?
    let usage: UsageBlock?

    var isEmpty: Bool { blocks.isEmpty }
}
