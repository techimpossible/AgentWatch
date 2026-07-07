import Foundation

struct SearchHit: Identifiable, Hashable {
    let id: String                  // unique per (file, line)
    let sessionId: String           // file basename without extension
    let profile: String             // Claude config profile this session belongs to
    let projectName: String
    let cwd: String?                // session's working dir, for resume command/URL
    let lineNumber: Int
    let role: String                // "user" / "assistant" / etc.
    let preview: String             // ~200 chars of context around the match
    let timestamp: Date?
    let fileURL: URL
}

/// Outcome of a search: the hits plus whether the result set was truncated at `limit`.
struct SearchResult {
    let hits: [SearchHit]
    let limit: Int          // the cap that was applied
    let capReached: Bool    // true when scanning stopped early because `limit` was hit
}

enum SearchEngine {
    /// Plain substring search across all JSONL files under ~/.claude/projects/.
    /// Case-insensitive. Returns up to `limit` hits, flagging when the cap was reached.
    static func search(query: String, limit: Int = 200) -> SearchResult {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 2 else { return SearchResult(hits: [], limit: limit, capReached: false) }

        DebugLog.write("search: query='\(q)' limit=\(limit)")
        var hits: [SearchHit] = []
        var capReached = false
        let fm = FileManager.default

        outer: for (profile, projectDir) in ClaudeHome.projectDirs() {
            let fallbackName = ProjectName.decodeDir(projectDir.lastPathComponent)
            guard let files = try? fm.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                guard let data = try? Data(contentsOf: file),
                      let text = String(data: data, encoding: .utf8) else { continue }

                let sessionId = file.deletingPathExtension().lastPathComponent
                let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
                // Real folder name from the session's cwd; mangled-dir name is a fallback.
                let cwd = ProjectName.scanCwd(inLines: lines)
                let projectName = ProjectName.fromCwd(cwd, fallback: fallbackName)
                var lineNum = 0
                for line in lines {
                    lineNum += 1
                    let lineLower = line.lowercased()
                    guard lineLower.contains(q) else { continue }

                    let preview = makePreview(String(line), match: q)
                    let parsed = parseLineMeta(String(line))
                    hits.append(SearchHit(
                        id: "\(sessionId)#\(lineNum)",
                        sessionId: sessionId,
                        profile: profile,
                        projectName: projectName,
                        cwd: cwd,
                        lineNumber: lineNum,
                        role: parsed.role,
                        preview: preview,
                        timestamp: parsed.timestamp,
                        fileURL: file
                    ))
                    if hits.count >= limit { capReached = true; break outer }
                }
            }
        }

        DebugLog.write("search: \(hits.count) hits capReached=\(capReached)")
        // Sort by timestamp desc, nil last
        hits.sort { (a, b) in
            switch (a.timestamp, b.timestamp) {
            case let (l?, r?): return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.id < b.id
            }
        }
        return SearchResult(hits: hits, limit: limit, capReached: capReached)
    }

    private static func parseLineMeta(_ line: String) -> (role: String, timestamp: Date?) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ("?", nil)
        }
        let role = obj["type"] as? String ?? "?"
        let ts = (obj["timestamp"] as? String).flatMap { raw -> Date? in
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        }
        return (role, ts)
    }

    private static func makePreview(_ line: String, match: String) -> String {
        // Find the first match, return ~80 chars on each side.
        let lower = line.lowercased()
        guard let range = lower.range(of: match) else {
            return String(line.prefix(160))
        }
        let start = line.index(range.lowerBound, offsetBy: -80, limitedBy: line.startIndex) ?? line.startIndex
        let end = line.index(range.upperBound, offsetBy: 80, limitedBy: line.endIndex) ?? line.endIndex
        let prefix = start == line.startIndex ? "" : "…"
        let suffix = end == line.endIndex ? "" : "…"
        let snippet = String(line[start..<end])
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\n", with: " ")
        return prefix + snippet + suffix
    }
}
