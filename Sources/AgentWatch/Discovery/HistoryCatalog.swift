import Foundation

struct HistoricalSession: Identifiable, Hashable {
    let sessionId: String
    let profile: String         // Claude config profile this session belongs to
    let projectName: String
    let cwd: String?            // best-effort: from the JSONL itself, may be nil
    let name: String?           // session name: customTitle (rename) ?? agentName (auto-title)
    let firstMessage: String?   // first user message for a preview
    let lastModified: Date
    let messageCount: Int
    let fileURL: URL

    var id: String { sessionId }

    /// Row identity (bold first line): the session's name — its custom title, else
    /// the auto-generated agent title — falling back to the first prompt, then the
    /// project folder for empty/untitled sessions.
    var displayName: String {
        if let n = name, !n.isEmpty { return n }
        if let m = firstMessage, !m.isEmpty { return m }
        return projectName
    }

    /// "~"-relative working directory for the context line (nil if unknown).
    var relativeCwd: String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let home = NSString(string: "~").expandingTildeInPath
        if cwd == home { return "~" }
        if cwd.hasPrefix(home + "/") { return "~" + cwd.dropFirst(home.count) }
        return cwd
    }
}

enum HistoryCatalog {
    /// Walk every JSONL under ~/.claude/projects/ and produce a sorted-by-recency list.
    /// Cheap version: parses only the first ~5 lines of each file for metadata,
    /// uses the file's mtime for last-activity time, counts lines via byte-scan.
    static func load() -> [HistoricalSession] {
        DebugLog.write("history: load start")
        let fm = FileManager.default

        var sessions: [HistoricalSession] = []
        for (profile, projectDir) in ClaudeHome.projectDirs() {
            // Fallback name derived from the mangled dir; the real name comes
            // from each session's parsed cwd (see makeSession).
            let fallbackName = ProjectName.decodeDir(projectDir.lastPathComponent)
            guard let files = try? fm.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
            ) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                if let s = makeSession(file: file, profile: profile, fallbackName: fallbackName) {
                    sessions.append(s)
                }
            }
        }

        sessions.sort { $0.lastModified > $1.lastModified }
        DebugLog.write("history: \(sessions.count) sessions")
        return sessions
    }

    private static func makeSession(file: URL, profile: String, fallbackName: String) -> HistoricalSession? {
        let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey])
        let mtime = attrs?.contentModificationDate ?? Date.distantPast
        let sessionId = file.deletingPathExtension().lastPathComponent

        // Best-effort first-line scan for cwd + first user message + line count.
        // We only read the file once.
        guard let data = try? Data(contentsOf: file),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        var cwd: String?
        var firstMessage: String?
        var customTitle: String?   // explicit `claude --name` / rename (last wins)
        var agentName: String?     // auto-generated title (last wins)
        var lineCount = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            lineCount += 1
            let ls = String(line)
            // Title lines can appear (and change) anywhere, so always inspect them;
            // otherwise only parse until we have cwd + first message, to stay cheap.
            let mightBeTitle = ls.contains("\"custom-title\"") || ls.contains("\"agent-name\"")
            let needMeta = (cwd == nil || firstMessage == nil)
            if !mightBeTitle && !needMeta { continue }
            guard let lineData = ls.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
            switch obj["type"] as? String {
            case "custom-title":
                if let t = obj["customTitle"] as? String, !t.isEmpty { customTitle = trimmed(t, max: 200) }
            case "agent-name":
                if let t = obj["agentName"] as? String, !t.isEmpty { agentName = trimmed(t, max: 200) }
            default:
                break
            }
            if cwd == nil, let c = obj["cwd"] as? String, !c.isEmpty {
                cwd = c
            }
            if firstMessage == nil, obj["type"] as? String == "user",
               let msg = obj["message"] as? [String: Any],
               let content = msg["content"] {
                if let s = content as? String, !s.isEmpty {
                    firstMessage = trimmed(s, max: 200)
                } else if let arr = content as? [[String: Any]] {
                    let joined = arr.compactMap { $0["text"] as? String }.joined(separator: " ")
                    if !joined.isEmpty { firstMessage = trimmed(joined, max: 200) }
                }
            }
        }

        // Prefer the real folder name from the parsed cwd; the mangled-dir
        // fallback is unreliable (e.g. "~" decodes to the username "alex").
        let projectName = ProjectName.fromCwd(cwd, fallback: fallbackName)

        return HistoricalSession(
            sessionId: sessionId,
            profile: profile,
            projectName: projectName,
            cwd: cwd,
            name: customTitle ?? agentName,
            firstMessage: firstMessage,
            lastModified: mtime,
            messageCount: lineCount,
            fileURL: file
        )
    }

    private static func trimmed(_ s: String, max: Int) -> String {
        let cleaned = s.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if cleaned.count <= max { return cleaned }
        return String(cleaned.prefix(max)) + "…"
    }

}
