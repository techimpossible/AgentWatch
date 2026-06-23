import Foundation

enum JSONLReader {
    private static func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: raw) { return d }
        return ISO8601DateFormatter().date(from: raw)
    }

    private static func decodeContent(_ value: Any?) -> [ContentBlock] {
        if let s = value as? String { return [.text(s)] }
        guard let arr = value as? [[String: Any]] else { return [] }
        var out: [ContentBlock] = []
        for block in arr {
            let t = block["type"] as? String ?? "unknown"
            switch t {
            case "text":
                out.append(.text(block["text"] as? String ?? ""))
            case "thinking":
                out.append(.thinking(block["thinking"] as? String ?? ""))
            case "redacted_thinking":
                out.append(.redactedThinking)
            case "tool_use":
                let name = block["name"] as? String ?? "?"
                let input = block["input"]
                let inputStr: String
                if let data = try? JSONSerialization.data(withJSONObject: input ?? [:], options: [.prettyPrinted, .sortedKeys]),
                   let s = String(data: data, encoding: .utf8) {
                    inputStr = s
                } else {
                    inputStr = "(unparseable input)"
                }
                out.append(.toolUse(name: name, input: inputStr))
            case "tool_result":
                let isError = block["is_error"] as? Bool ?? false
                let content = block["content"]
                let text: String
                if let s = content as? String { text = s }
                else if let arr = content as? [[String: Any]] {
                    text = arr.compactMap { $0["text"] as? String }.joined(separator: "\n")
                } else { text = "" }
                out.append(.toolResult(text: text, isError: isError))
            default:
                out.append(.unknown(t))
            }
        }
        return out
    }

    private static func decodeUsage(_ raw: [String: Any]?) -> UsageBlock? {
        guard let raw else { return nil }
        let inT = raw["input_tokens"] as? Int ?? 0
        let outT = raw["output_tokens"] as? Int ?? 0
        let ccT = raw["cache_creation_input_tokens"] as? Int ?? 0
        let crT = raw["cache_read_input_tokens"] as? Int ?? 0
        if inT == 0 && outT == 0 && ccT == 0 && crT == 0 { return nil }
        return UsageBlock(
            inputTokens: inT,
            outputTokens: outT,
            cacheCreationInputTokens: ccT,
            cacheReadInputTokens: crT
        )
    }

    static func read(_ url: URL) -> [TranscriptEntry] {
        DebugLog.write("jsonl: read \(url.lastPathComponent)")
        guard let data = try? Data(contentsOf: url) else {
            DebugLog.write("jsonl: cannot read \(url.path)")
            return []
        }
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var entries: [TranscriptEntry] = []
        var lineNum = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            lineNum += 1
            let lineStr = String(line)
            guard let lineData = lineStr.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            let type = obj["type"] as? String ?? ""
            let role: Role
            switch type {
            case "user": role = .user
            case "assistant": role = .assistant
            case "system": role = .system
            default: continue
            }

            let uuid = obj["uuid"] as? String ?? "\(url.lastPathComponent)#\(lineNum)"
            let ts = parseTimestamp(obj["timestamp"] as? String)
            let message = obj["message"] as? [String: Any]
            let blocks = decodeContent(message?["content"])
            let model = message?["model"] as? String
            let usage = decodeUsage(message?["usage"] as? [String: Any])

            entries.append(TranscriptEntry(
                id: uuid,
                role: role,
                timestamp: ts,
                blocks: blocks,
                model: model,
                usage: usage
            ))
        }

        DebugLog.write("jsonl: \(entries.count) entries from \(url.lastPathComponent)")
        return entries
    }

    static func findFile(sessionId: String) -> URL? {
        let fm = FileManager.default
        for (_, dir) in ClaudeHome.projectDirs() {
            let candidate = dir.appendingPathComponent("\(sessionId).jsonl")
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}
