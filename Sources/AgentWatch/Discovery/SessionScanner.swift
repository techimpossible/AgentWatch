import Foundation
import OSLog

enum SessionScanner {
    private static let log = Logger(subsystem: "com.techimpossible.agentwatch", category: "SessionScanner")

    private struct SessionFile: Decodable {
        let pid: Int32
        let sessionId: String
        let cwd: String
        let status: String?
        let startedAt: Double?
        let updatedAt: Double?
        let version: String?
        let name: String?
    }

    private static func dateFromMillis(_ ms: Double?) -> Date? {
        guard let ms else { return nil }
        return Date(timeIntervalSince1970: ms / 1000.0)
    }

    private static func mapStatus(_ raw: String?) -> SessionStatus {
        switch raw?.lowercased() {
        case "busy", "working", "running":
            return .working
        case "idle", "ready":
            return .idle
        case "waiting", "needs_input", "needsinput", "waiting_for_input":
            return .needsInput
        case nil:
            return .unknown
        case .some(let other):
            log.warning("Unknown session status string: \(other, privacy: .public)")
            return .needsInput
        }
    }

    static func scan() -> [Session] {
        let fm = FileManager.default
        let decoder = JSONDecoder()
        var sessions: [Session] = []

        for (profile, dir) in ClaudeHome.sessionDirs {
            DebugLog.write("scan: profile=\(profile) dir=\(dir.path)")
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
                DebugLog.write("scan: contentsOfDirectory failed for \(dir.path)")
                continue
            }
            DebugLog.write("scan: \(entries.count) entries in \(profile)")

            for url in entries where url.pathExtension == "json" {
                guard let data = try? Data(contentsOf: url) else {
                    DebugLog.write("scan: cannot read \(url.lastPathComponent)")
                    continue
                }
                guard let file = try? decoder.decode(SessionFile.self, from: data) else {
                    DebugLog.write("scan: decode failed \(url.lastPathComponent)")
                    continue
                }

                let isClaude = ProcessChecker.isClaudeSession(pid: file.pid)
                guard isClaude else {
                    DebugLog.write("scan: \(url.lastPathComponent) pid=\(file.pid) skipped (not a claude process)")
                    continue
                }

                // Filter "ghost" sessions: a claude process that's been alive for a while
                // but has no JSONL on disk (the user never prompted it). Without this,
                // forgotten idle sessions clutter the list and produce empty transcripts.
                let hasJSONL = JSONLReader.findFile(sessionId: file.sessionId) != nil
                let started = dateFromMillis(file.startedAt) ?? .distantPast
                let ageSeconds = Date().timeIntervalSince(started)
                if !hasJSONL && ageSeconds > 60 {
                    DebugLog.write("scan: \(url.lastPathComponent) pid=\(file.pid) skipped (no JSONL, age=\(Int(ageSeconds))s)")
                    continue
                }
                DebugLog.write("scan: \(url.lastPathComponent) pid=\(file.pid) isClaude=true status=\(file.status ?? "nil") jsonl=\(hasJSONL)")

                let firstUser = firstUserMessage(sessionId: file.sessionId)
                let usage = computeTokensAndCost(sessionId: file.sessionId)
                sessions.append(Session(
                    pid: file.pid,
                    sessionId: file.sessionId,
                    profile: profile,
                    cwd: file.cwd,
                    status: mapStatus(file.status),
                    startedAt: dateFromMillis(file.startedAt),
                    updatedAt: dateFromMillis(file.updatedAt),
                    version: file.version,
                    name: file.name,
                    firstUserMessage: firstUser,
                    totalTokens: usage.tokens,
                    totalCostUSD: usage.cost
                ))
            }
        }

        return sessions.sorted { (a, b) in
            (a.startedAt ?? .distantPast) > (b.startedAt ?? .distantPast)
        }
    }

    /// Find the first user message in this session's JSONL (if any).
    /// Reads at most ~30 lines to keep the polling loop cheap.
    private static func firstUserMessage(sessionId: String) -> String? {
        guard let url = JSONLReader.findFile(sessionId: sessionId),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return nil }
        var scanned = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            scanned += 1
            if scanned > 30 { break }
            guard let lineData = String(line).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
            guard obj["type"] as? String == "user",
                  let msg = obj["message"] as? [String: Any] else { continue }
            let content = msg["content"]
            if let s = content as? String, !s.isEmpty {
                return truncated(s, max: 70)
            }
            if let arr = content as? [[String: Any]] {
                let joined = arr.compactMap { $0["text"] as? String }.joined(separator: " ")
                if !joined.isEmpty { return truncated(joined, max: 70) }
            }
        }
        return nil
    }

    private static func truncated(_ s: String, max: Int) -> String {
        let cleaned = s.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if cleaned.count <= max { return cleaned }
        return String(cleaned.prefix(max)) + "…"
    }

    /// Sum tokens and cost across this session's JSONL file. Reuses Pricing
    /// for cost. Returns (0, 0) if the file can't be read.
    private static func computeTokensAndCost(sessionId: String) -> (tokens: Int, cost: Double) {
        guard let url = JSONLReader.findFile(sessionId: sessionId),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return (0, 0)
        }
        var tokens = 0
        var cost = 0.0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = String(line).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
            guard obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let model = message["model"] as? String,
                  let raw = message["usage"] as? [String: Any] else { continue }

            let inT = raw["input_tokens"] as? Int ?? 0
            let outT = raw["output_tokens"] as? Int ?? 0
            let ccT = raw["cache_creation_input_tokens"] as? Int ?? 0
            let crT = raw["cache_read_input_tokens"] as? Int ?? 0
            tokens += inT + outT + ccT + crT
            cost += Pricing.cost(
                model: model,
                usage: UsageBlock(
                    inputTokens: inT,
                    outputTokens: outT,
                    cacheCreationInputTokens: ccT,
                    cacheReadInputTokens: crT
                )
            )
        }
        return (tokens, cost)
    }
}
