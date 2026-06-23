import Foundation

enum CostCalculator {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    /// Walk every JSONL in ~/.claude/projects/ and aggregate cost.
    /// Pure function over disk; safe to call from a background actor.
    static func computeAll() -> CostAggregate {
        DebugLog.write("cost: computeAll start")
        let fm = FileManager.default
        var agg = CostAggregate()

        for (profile, projectDir) in ClaudeHome.projectDirs() {
            let fallbackName = ProjectName.decodeDir(projectDir.lastPathComponent)
            guard let files = try? fm.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: nil) else { continue }
            let jsonlFiles = files.filter { $0.pathExtension == "jsonl" }
            // Derive the real folder name from the first file carrying a cwd.
            let projectName = projectName(forFiles: jsonlFiles, fallback: fallbackName)
            for file in jsonlFiles {
                attribute(fileURL: file, profile: profile, projectName: projectName, into: &agg)
            }
        }

        agg.asOf = Date()
        DebugLog.write("cost: computeAll done — entries=\(agg.entriesCounted) total=$\(String(format: "%.4f", agg.totalCost))")
        return agg
    }

    private static func attribute(fileURL: URL, profile: String, projectName: String, into agg: inout CostAggregate) {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return }

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = String(line).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
            guard obj["type"] as? String == "assistant" else { continue }
            guard let message = obj["message"] as? [String: Any],
                  let model = message["model"] as? String,
                  let rawUsage = message["usage"] as? [String: Any] else { continue }

            let inT = rawUsage["input_tokens"] as? Int ?? 0
            let outT = rawUsage["output_tokens"] as? Int ?? 0
            let ccT = rawUsage["cache_creation_input_tokens"] as? Int ?? 0
            let crT = rawUsage["cache_read_input_tokens"] as? Int ?? 0
            if inT == 0 && outT == 0 && ccT == 0 && crT == 0 { continue }

            let usage = UsageBlock(
                inputTokens: inT,
                outputTokens: outT,
                cacheCreationInputTokens: ccT,
                cacheReadInputTokens: crT
            )
            let cost = Pricing.cost(model: model, usage: usage)

            let day: String
            if let ts = obj["timestamp"] as? String, let parsed = parseTimestamp(ts) {
                day = dayFormatter.string(from: parsed)
            } else {
                day = "unknown"
            }

            agg.totalCost += cost
            agg.totalInputTokens += inT
            agg.totalOutputTokens += outT
            agg.totalCacheRead += crT
            agg.totalCacheWrite += ccT
            agg.entriesCounted += 1

            agg.byDay[day, default: 0] += cost
            agg.byProfile[profile, default: 0] += cost
            agg.byProject["\(profile) · \(projectName)", default: 0] += cost
            agg.byModel[shortModelName(model), default: 0] += cost
        }
    }

    private static func parseTimestamp(_ raw: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: raw) { return d }
        return ISO8601DateFormatter().date(from: raw)
    }

    private static func shortModelName(_ s: String) -> String {
        let lower = s.lowercased()
        // Match both "opus-4.7" and "4.7-opus" forms.
        if lower.contains("opus-4.7") || lower.contains("4.7-opus") { return "Opus 4.7" }
        if lower.contains("opus-4.6") || lower.contains("4.6-opus") { return "Opus 4.6" }
        if lower.contains("opus-4.5") || lower.contains("4.5-opus") { return "Opus 4.5" }
        if lower.contains("opus-4.1") || lower.contains("4.1-opus") { return "Opus 4.1" }
        if lower.contains("opus-3")   || lower.contains("3-opus")   { return "Opus 3" }
        if lower.contains("opus-4")   || lower.contains("4-opus")   { return "Opus 4" }
        if lower.contains("sonnet-4.6") || lower.contains("4.6-sonnet") { return "Sonnet 4.6" }
        if lower.contains("sonnet-4.5") || lower.contains("4.5-sonnet") { return "Sonnet 4.5" }
        if lower.contains("sonnet-4")   || lower.contains("4-sonnet")   { return "Sonnet 4" }
        if lower.contains("sonnet-3.7") || lower.contains("3.7-sonnet") { return "Sonnet 3.7" }
        if lower.contains("haiku-4.5")  || lower.contains("4.5-haiku")  { return "Haiku 4.5" }
        if lower.contains("haiku-3.5")  || lower.contains("3.5-haiku")  { return "Haiku 3.5" }
        if lower.contains("haiku-3")    || lower.contains("3-haiku")    { return "Haiku 3" }
        return s.split(separator: "/").last.map(String.init) ?? s
    }

    /// Real folder name for a project dir, found by scanning its files for a cwd.
    /// Falls back to the decoded mangled-dir name when none is found.
    private static func projectName(forFiles files: [URL], fallback: String) -> String {
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let text = String(data: data, encoding: .utf8) else { continue }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            if let cwd = ProjectName.scanCwd(inLines: lines) {
                return ProjectName.fromCwd(cwd, fallback: fallback)
            }
        }
        return fallback
    }
}
