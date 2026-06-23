import Foundation

/// A single Claude Code config root (one "profile").
struct ClaudeRoot {
    let profile: String   // human label: "default", "work", "personal", …
    let url: URL          // the config dir itself (e.g. ~/.config/claude-work)
}

enum ClaudeHome {
    /// The default config dir, ~/.claude.
    static let root: URL = {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    }()

    /// Every Claude config root to scan, each tagged with a profile label:
    ///   1. ~/.claude                       → "default"
    ///   2. ~/.config/claude-<name>         → "<name>"   (per-terminal profiles)
    ///   3. paths in $CLAUDE_CONFIG_DIR     → last path component
    /// Re-evaluated on access so newly-created profiles appear without a restart.
    static var roots: [ClaudeRoot] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var found: [ClaudeRoot] = []
        var seen = Set<String>()

        func add(_ url: URL, profile: String) {
            let std = url.standardizedFileURL
            guard seen.insert(std.path).inserted else { return }
            found.append(ClaudeRoot(profile: profile, url: std))
        }

        // 1. Default — always included, even if empty.
        add(home.appendingPathComponent(".claude", isDirectory: true), profile: "default")

        // 2. ~/.config/claude-* profile dirs that look like Claude configs.
        let configDir = home.appendingPathComponent(".config", isDirectory: true)
        if let entries = try? fm.contentsOfDirectory(at: configDir, includingPropertiesForKeys: [.isDirectoryKey]) {
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where entry.lastPathComponent.hasPrefix("claude-") {
                guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                      looksLikeConfig(entry) else { continue }
                let profile = String(entry.lastPathComponent.dropFirst("claude-".count))
                add(entry, profile: profile.isEmpty ? entry.lastPathComponent : profile)
            }
        }

        // 3. $CLAUDE_CONFIG_DIR (colon-separated), if the GUI inherited it.
        if let raw = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !raw.isEmpty {
            for part in raw.split(separator: ":") {
                let url = URL(fileURLWithPath: String(part), isDirectory: true)
                add(url, profile: url.lastPathComponent)
            }
        }

        return found
    }

    /// True if `dir` carries a sessions/ or projects/ subdir (i.e. it's a real config root).
    private static func looksLikeConfig(_ dir: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: dir.appendingPathComponent("sessions").path)
            || fm.fileExists(atPath: dir.appendingPathComponent("projects").path)
    }

    /// The config dir backing a profile label (nil if unknown). "default" maps
    /// to ~/.claude. Used to build CLAUDE_CONFIG_DIR for profile-aware resume.
    static func configDir(forProfile profile: String) -> URL? {
        roots.first { $0.profile == profile }?.url
    }

    /// Each root's sessions/ dir, tagged with its profile.
    static var sessionDirs: [(profile: String, dir: URL)] {
        roots.map { ($0.profile, $0.url.appendingPathComponent("sessions", isDirectory: true)) }
    }

    /// Flattened list of every project subdirectory across all roots, each tagged
    /// with the profile it belongs to.
    static func projectDirs() -> [(profile: String, dir: URL)] {
        let fm = FileManager.default
        var out: [(profile: String, dir: URL)] = []
        for root in roots {
            let projects = root.url.appendingPathComponent("projects", isDirectory: true)
            guard let entries = try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil) else { continue }
            for entry in entries where entry.hasDirectoryPath {
                out.append((root.profile, entry))
            }
        }
        return out
    }
}

/// Derives a human-readable project/folder name for a session.
///
/// `~/.claude/projects/` directory names are the cwd with every `/` replaced by
/// `-`, which is lossy: `-Users-alex` can't be split back into a path,
/// so naively taking the last `-`-segment yields the username ("alex").
/// The reliable source is the `cwd` recorded inside each session's JSONL — use
/// that when available, and fall back to the decoded dir name only when it isn't.
enum ProjectName {
    /// Last path component of `cwd`, with the home dir collapsed to "(home)".
    /// Returns `fallback` when `cwd` is nil/empty or yields nothing usable.
    static func fromCwd(_ cwd: String?, fallback: String) -> String {
        guard let cwd, !cwd.isEmpty else { return fallback }
        let home = NSString(string: "~").expandingTildeInPath
        if cwd == home { return "(home)" }
        let last = URL(fileURLWithPath: cwd).lastPathComponent
        return last.isEmpty ? fallback : last
    }

    /// Best-effort decode of a mangled `~/.claude/projects/` directory name.
    /// Used only as a fallback when a session's real cwd is unavailable.
    static func decodeDir(_ encoded: String) -> String {
        let trimmed = encoded.hasPrefix("-") ? String(encoded.dropFirst()) : encoded
        let parts = trimmed.split(separator: "-", omittingEmptySubsequences: true)
        return parts.last.map(String.init) ?? encoded
    }

    /// Scan a JSONL file's lines for the first `"cwd"` field. Cheap best-effort:
    /// returns nil if no line carries one.
    static func scanCwd(inLines lines: [Substring]) -> String? {
        for line in lines {
            guard let data = String(line).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let c = obj["cwd"] as? String, !c.isEmpty else { continue }
            return c
        }
        return nil
    }
}

/// File-based debug log. Enabled only when AGENTWATCH_DEBUG is set in the environment
/// (e.g., `AGENTWATCH_DEBUG=1 open AgentWatch.app`). Off by default to keep the
/// auditability posture clean — no persistent on-disk artifacts during normal use.
enum DebugLog {
    static let url = URL(fileURLWithPath: "/tmp/agentwatch.log")
    static let enabled = ProcessInfo.processInfo.environment["AGENTWATCH_DEBUG"] != nil

    static func write(_ msg: String) {
        guard enabled else { return }
        let line = "\(Date().formatted(date: .omitted, time: .standard)) \(msg)\n"
        if let data = line.data(using: .utf8) {
            if let h = try? FileHandle(forWritingTo: url) {
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: data)
                try? h.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
