import Foundation

struct Session: Identifiable, Hashable, Sendable {
    let pid: Int32
    let sessionId: String
    let profile: String        // Claude config profile this session belongs to
    let cwd: String
    let status: SessionStatus
    let startedAt: Date?
    let updatedAt: Date?
    let version: String?
    let name: String?              // From `claude --name` or /rename
    let firstUserMessage: String?  // First user prompt, truncated
    let totalTokens: Int           // Sum of input + output + cache tokens across the session
    let totalCostUSD: Double       // Best-effort cost at Anthropic published rates

    var id: String { sessionId }

    /// Best-effort human label for the session.
    /// Priority: explicit name -> first user message -> project folder -> start-time.
    var displayTitle: String {
        if let n = name, !n.isEmpty { return n }
        if let m = firstUserMessage, !m.isEmpty { return m }
        if !isCwdHome { return projectName }
        // Empty home-dir session — distinguish by start time.
        if let started = startedAt {
            let elapsed = Date().timeIntervalSince(started)
            if elapsed < 90 { return "New session" }
            return "Session from \(started.formatted(date: .omitted, time: .shortened))"
        }
        return "New session"
    }

    /// Subtitle: always relative cwd + PID + status. Stays informative regardless of title.
    var displaySubtitle: String {
        "\(relativeCwd) • PID \(pid) • \(status.label)"
    }

    /// Last path component of cwd, with home dir collapsed to "(home)".
    var projectName: String {
        if isCwdHome { return "(home)" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// "~" if cwd is exactly $HOME, "~/foo/bar" if under home, full path otherwise.
    var relativeCwd: String {
        let home = NSString(string: "~").expandingTildeInPath
        if cwd == home { return "~" }
        if cwd.hasPrefix(home + "/") {
            return "~" + cwd.dropFirst(home.count)
        }
        return cwd
    }

    private var isCwdHome: Bool {
        cwd == NSString(string: "~").expandingTildeInPath
    }

    /// Compact human-readable elapsed time since the session started.
    /// Examples: "12s", "4m", "1h 23m".
    var elapsedString: String {
        guard let started = startedAt else { return "—" }
        let secs = Int(Date().timeIntervalSince(started))
        if secs < 60 { return "\(secs)s" }
        let mins = secs / 60
        if mins < 60 { return "\(mins)m" }
        let h = mins / 60
        let m = mins % 60
        return "\(h)h \(m)m"
    }

    /// Compact token count: "342", "1.2k", "13.5k", "1.2M".
    var tokensString: String {
        if totalTokens >= 1_000_000 {
            return String(format: "%.1fM", Double(totalTokens) / 1_000_000)
        }
        if totalTokens >= 1_000 {
            return String(format: "%.1fk", Double(totalTokens) / 1_000)
        }
        return "\(totalTokens)"
    }
}
