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

    /// Wrap `value` in POSIX single quotes for safe use as a single shell word.
    /// Single-quoted strings are literal in the shell — `$(...)`, backticks, `$VAR`,
    /// and backslash are all inert inside them, so this neutralises command injection
    /// from untrusted cwd/session values. The only character that can't appear inside a
    /// single-quoted string is `'` itself; the classic `'\''` sequence closes the quote,
    /// emits an escaped literal quote, then reopens quoting.
    private static func singleQuoted(_ value: String) -> String {
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Build the shell command that resumes a session. Suitable for pasting into a terminal.
    /// For a non-default profile, prefixes `CLAUDE_CONFIG_DIR` so `claude --resume` reads
    /// and writes the correct profile's config (otherwise it would resume under default).
    static func resumeCommand(profile: String = "default", sessionId: String, cwd: String) -> String {
        // Single-quote every interpolated value so the shell treats them as literals
        // and cannot evaluate embedded `$(...)`, backticks, or `$VAR`.
        let quotedCwd = singleQuoted(cwd)
        let quotedId = singleQuoted(sessionId)
        var envPrefix = ""
        if profile != "default", let dir = ClaudeHome.configDir(forProfile: profile) {
            envPrefix = "CLAUDE_CONFIG_DIR=\(singleQuoted(dir.path)) "
        }
        // The user's claude binary is at ~/.local/bin/claude per `which claude`.
        // Using the bare name `claude` so it works for anyone whose PATH includes claude.
        return "cd \(quotedCwd) && \(envPrefix)claude --resume \(quotedId)"
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
    /// `@MainActor` because URL-initiated resumes present a confirmation dialog (AppKit UI);
    /// the caller (NSApplicationDelegate) already runs on the main actor.
    @MainActor
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

        // The URL is fully external (e.g. clicked in Asana), so validate before doing
        // anything with it. Reject unless the session looks like a UUID and the cwd is an
        // existing absolute directory, and reject any value carrying control chars/newlines.
        guard isValidSessionId(session) else {
            DebugLog.write("terminal: rejecting URL — session is not a UUID: \(session)")
            return
        }
        guard isValidCwd(cwd) else {
            DebugLog.write("terminal: rejecting URL — cwd is not an existing absolute dir: \(cwd)")
            return
        }
        guard !containsControlCharacters(profile) else {
            DebugLog.write("terminal: rejecting URL — profile contains control characters")
            return
        }

        // Only URL-initiated resumes prompt for confirmation — in-app clicks that call
        // resumeSession(...) directly are already a deliberate user action.
        confirmAndResume(profile: profile, sessionId: session, cwd: cwd)
    }

    /// Present a confirmation dialog for a URL-initiated resume, then launch if approved.
    /// Runs on the main actor because it drives AppKit UI.
    @MainActor
    private static func confirmAndResume(profile: String, sessionId: String, cwd: String) {
        let alert = NSAlert()
        alert.messageText = "Open this Claude session in Terminal?"
        alert.informativeText = "Directory: \(cwd)\nSession: \(sessionId)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            DebugLog.write("terminal: user cancelled URL-initiated resume")
            return
        }
        resumeSession(profile: profile, sessionId: sessionId, cwd: cwd)
    }

    // MARK: - Input validation (for external URLs)

    /// True when `value` is a canonical 36-char UUID (hex digits + hyphens).
    private static func isValidSessionId(_ value: String) -> Bool {
        return UUID(uuidString: value) != nil
    }

    /// True when `value` is an absolute path that exists as a directory and carries
    /// no control characters. Uses FileManager rather than trusting the URL.
    private static func isValidCwd(_ value: String) -> Bool {
        guard value.hasPrefix("/"), !containsControlCharacters(value) else { return false }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: value, isDirectory: &isDir) else { return false }
        return isDir.boolValue
    }

    /// True when `value` contains any Unicode control character (includes newlines/CR).
    private static func containsControlCharacters(_ value: String) -> Bool {
        return value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    /// Open a new Terminal.app window, cd to `cwd`, run `claude --resume <sessionId>`.
    static func resumeSession(profile: String = "default", sessionId: String, cwd: String) {
        let cmd = resumeCommand(profile: profile, sessionId: sessionId, cwd: cwd)
        // Newlines/control chars would break the AppleScript string literal (`do script "…"`)
        // and could smuggle in a second statement, so refuse to proceed if any slipped through.
        guard !containsControlCharacters(cmd) else {
            DebugLog.write("terminal: refusing to run command with control characters")
            return
        }
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
        // Single-quote the path so the shell can't evaluate `$(...)`/backticks/`$VAR`.
        let cmd = "cd \(singleQuoted(cwd))"
        // Refuse control chars that would break/escape the AppleScript string literal.
        guard !containsControlCharacters(cmd) else {
            DebugLog.write("terminal: refusing to open cwd with control characters")
            return
        }
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
