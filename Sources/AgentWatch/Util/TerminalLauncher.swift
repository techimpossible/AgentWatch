import AppKit
import Foundation

/// Opens or focuses terminal windows for Claude Code sessions.
/// All actions stay within the user's session — no privileges needed.
enum TerminalLauncher {

    /// Walk the parent-process chain of `pid` and bring the owning terminal app to front.
    /// Falls back to opening the cwd in Terminal.app if no host terminal is identifiable.
    static func bringToFront(pid: Int32, fallbackCwd: String) {
        if let terminalApp = findTerminalAncestor(pid: pid) {
            DebugLog.write("terminal: focusing \(terminalApp) for pid \(pid)")
            activateApp(named: terminalApp)
            return
        }
        DebugLog.write("terminal: no terminal ancestor for pid \(pid); opening cwd in Terminal")
        openCwdInTerminal(fallbackCwd)
    }

    private static func activateApp(named name: String) {
        let escaped = name.replacingOccurrences(of: "\"", with: "\\\"")
        runAppleScript("tell application \"\(escaped)\" to activate")
    }

    /// Build the shell command that resumes a session. Suitable for pasting into a terminal.
    /// For a non-default profile, prefixes `CLAUDE_CONFIG_DIR` so `claude --resume` reads
    /// and writes the correct profile's config (otherwise it would resume under default).
    static func resumeCommand(profile: String = "default", sessionId: String, cwd: String) -> String {
        let escapedCwd = cwd.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedId = sessionId.replacingOccurrences(of: "\"", with: "\\\"")
        var envPrefix = ""
        if profile != "default", let dir = ClaudeHome.configDir(forProfile: profile) {
            let escapedDir = dir.path.replacingOccurrences(of: "\"", with: "\\\"")
            envPrefix = "CLAUDE_CONFIG_DIR=\"\(escapedDir)\" "
        }
        // The user's claude binary is at ~/.local/bin/claude per `which claude`.
        // Using the bare name `claude` so it works for anyone whose PATH includes claude.
        return "cd \"\(escapedCwd)\" && \(envPrefix)claude --resume \"\(escapedId)\""
    }

    /// Build the `agentwatch://resume?...` URL string that, when opened (e.g. clicked in
    /// Asana), launches AgentWatch's URL handler and reopens this session in a terminal.
    /// Carries the profile so the handler can target the right config dir.
    static func resumeURL(profile: String = "default", sessionId: String, cwd: String) -> String {
        var comps = URLComponents()
        comps.scheme = "agentwatch"
        comps.host = "resume"
        var items = [
            URLQueryItem(name: "session", value: sessionId),
            URLQueryItem(name: "cwd", value: cwd),
        ]
        if profile != "default" { items.append(URLQueryItem(name: "profile", value: profile)) }
        comps.queryItems = items
        return comps.url?.absoluteString ?? "agentwatch://resume"
    }

    /// Parse an incoming `agentwatch://resume?session=…&cwd=…[&profile=…]` URL and run the
    /// matching terminal launch. No-op for any other shape.
    static func handleURL(_ url: URL) {
        DebugLog.write("terminal: incoming URL \(url.absoluteString)")
        guard url.scheme?.lowercased() == "agentwatch",
              url.host?.lowercased() == "resume",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let session = comps.queryItems?.first(where: { $0.name == "session" })?.value,
              let cwd = comps.queryItems?.first(where: { $0.name == "cwd" })?.value,
              !session.isEmpty, !cwd.isEmpty else {
            DebugLog.write("terminal: ignoring malformed URL \(url.absoluteString)")
            return
        }
        let profile = comps.queryItems?.first(where: { $0.name == "profile" })?.value ?? "default"
        resumeSession(profile: profile, sessionId: session, cwd: cwd)
    }

    /// Open a new Terminal.app window, cd to `cwd`, run `claude --resume <sessionId>`.
    static func resumeSession(profile: String = "default", sessionId: String, cwd: String) {
        let cmd = resumeCommand(profile: profile, sessionId: sessionId, cwd: cwd)
        let escapedCmd = cmd.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escapedCmd)"
        end tell
        """
        runAppleScript(script)
    }

    /// Reveal the project directory in Finder.
    static func revealInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    // MARK: - Private

    /// Names that mean "this process owns a terminal window the user is staring at."
    /// Comparison is case-insensitive substring against `comm` (process name).
    private static let knownTerminals: [(processSubstring: String, appName: String)] = [
        ("ghostty", "Ghostty"),
        ("iterm",    "iTerm"),
        ("warp",     "Warp"),
        ("kitty",    "kitty"),
        ("alacritty","Alacritty"),
        ("wezterm",  "WezTerm"),
        ("Terminal", "Terminal"),    // macOS Terminal.app's process is literally "Terminal"
        ("hyper",    "Hyper"),
        ("Tabby",    "Tabby"),
        // VS Code / Cursor terminal lives inside the renderer; matching here jumps to the IDE.
        ("Code Helper",   "Visual Studio Code"),
        ("Cursor Helper", "Cursor"),
    ]

    private static func findTerminalAncestor(pid: Int32) -> String? {
        var current: Int32 = pid
        var depth = 0
        while current > 1 && depth < 8 {
            depth += 1
            guard let info = processInfo(pid: current) else { return nil }
            let lower = info.command.lowercased()
            for (needle, appName) in knownTerminals where lower.contains(needle.lowercased()) {
                return appName
            }
            current = info.ppid
        }
        return nil
    }

    private struct ProcInfo { let ppid: Int32; let command: String }

    private static func processInfo(pid: Int32) -> ProcInfo? {
        // Use `ps` rather than libproc so we don't touch private SPIs.
        let p = Process()
        p.launchPath = "/bin/ps"
        p.arguments = ["-p", "\(pid)", "-o", "ppid=,comm="]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !out.isEmpty else { return nil }

        // Format: "<ppid> <command>"  — command may contain spaces.
        let parts = out.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let ppid = parts.first.flatMap({ Int32($0) }) else { return nil }
        let command = parts.count > 1 ? String(parts[1]) : ""
        return ProcInfo(ppid: ppid, command: command)
    }

    private static func openCwdInTerminal(_ cwd: String) {
        let escapedCwd = cwd.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "cd \\"\(escapedCwd)\\""
        end tell
        """
        runAppleScript(script)
    }

    private static func runAppleScript(_ source: String) {
        let p = Process()
        p.launchPath = "/usr/bin/osascript"
        p.arguments = ["-e", source]
        do {
            try p.run()
        } catch {
            DebugLog.write("terminal: osascript failed: \(error.localizedDescription)")
        }
    }
}
