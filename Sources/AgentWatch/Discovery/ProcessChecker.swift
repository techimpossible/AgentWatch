import Darwin
import Foundation

enum ProcessChecker {
    static func isAlive(pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        let result = kill(pid, 0)
        if result == 0 { return true }
        return errno != ESRCH
    }

    /// Full command line of the process (argv joined). Nil if the process
    /// doesn't exist or `ps` fails.
    static func commandLine(pid: Int32) -> String? {
        let p = Process()
        p.launchPath = "/bin/ps"
        p.arguments = ["-p", "\(pid)", "-o", "command="]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True if a process with this PID is alive AND its command line references
    /// `claude`. Filters PID-reuse "ghost" sessions: when Claude Code exits and
    /// macOS reuses its PID for an unrelated process, the stale
    /// ~/.claude/sessions/<pid>.json is no longer trustworthy.
    static func isClaudeSession(pid: Int32) -> Bool {
        guard isAlive(pid: pid) else { return false }
        guard let cmd = commandLine(pid: pid) else { return false }
        return cmd.lowercased().contains("claude")
    }
}

/// Terminates Claude Code sessions by PID — stays within the user's own session,
/// no privileges required.
enum SessionControl {
    /// Ask the process to exit (SIGTERM), then force-kill (SIGKILL) after a short
    /// grace period if it's still alive. Safe no-op for invalid/non-claude PIDs.
    static func kill(pid: Int32) {
        guard pid > 0, ProcessChecker.isClaudeSession(pid: pid) else {
            DebugLog.write("kill: pid \(pid) skipped (invalid or not a claude process)")
            return
        }
        DebugLog.write("kill: SIGTERM pid \(pid)")
        _ = Darwin.kill(pid, SIGTERM)

        // Escalate if it doesn't go quietly.
        Task.detached {
            try? await Task.sleep(for: .seconds(3))
            if ProcessChecker.isAlive(pid: pid) {
                DebugLog.write("kill: still alive, SIGKILL pid \(pid)")
                _ = Darwin.kill(pid, SIGKILL)
            }
        }
    }
}
