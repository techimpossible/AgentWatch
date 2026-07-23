import Foundation

/// Installs / removes the AgentWatch `PreToolUse` hook in a profile's
/// settings.json, and stages the hook shim at a stable path.
///
/// The shim is copied to ~/Library/Application Support/AgentWatch/hooks/ (a
/// location independent of where AgentWatch.app lives) and referenced by
/// absolute path from settings.json, so it keeps working if the app moves.
///
/// Settings edits are non-destructive: if the file exists but can't be read or
/// parsed as a JSON object, or if `hooks`/`PreToolUse` have unexpected shapes,
/// the operation ABORTS rather than overwriting the user's settings.
enum ApprovalHookInstaller {
    static let shimName = "agentwatch-approve.sh"
    static let matcher = "Edit|Write|MultiEdit|Bash"
    static let timeout = 120                     // seconds; shim polls under this

    static var hooksDir: URL {
        let appSup = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSup.appendingPathComponent("AgentWatch/hooks", isDirectory: true)
    }
    static var shimDest: URL { hooksDir.appendingPathComponent(shimName) }

    /// Copy the bundled shim to the stable path and mark it executable.
    @discardableResult
    static func stageShim() -> Bool {
        try? FileManager.default.createDirectory(at: hooksDir, withIntermediateDirectories: true)
        guard let src = Bundle.main.url(forResource: shimName, withExtension: nil, subdirectory: "hooks")
                ?? Bundle.main.url(forResource: "agentwatch-approve", withExtension: "sh", subdirectory: "hooks") else {
            DebugLog.write("approvals: shim not found in bundle")
            return false
        }
        do {
            if FileManager.default.fileExists(atPath: shimDest.path) {
                try FileManager.default.removeItem(at: shimDest)
            }
            try FileManager.default.copyItem(at: src, to: shimDest)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shimDest.path)
            return true
        } catch {
            DebugLog.write("approvals: stageShim failed: \(error)")
            return false
        }
    }

    private static func settingsURL(profile: String) -> URL? {
        ClaudeHome.configDir(forProfile: profile)?.appendingPathComponent("settings.json")
    }

    /// Reading settings distinguishes three cases so we never overwrite data we
    /// failed to understand.
    private enum SettingsRead {
        case dict([String: Any])   // usable (existing object, or empty for absent/empty file)
        case unusable              // exists but unreadable / not a JSON object → do NOT overwrite
    }

    private static func readSettings(_ url: URL) -> SettingsRead {
        if !FileManager.default.fileExists(atPath: url.path) { return .dict([:]) }
        guard let data = try? Data(contentsOf: url) else { return .unusable }
        if data.isEmpty { return .dict([:]) }
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else { return .unusable }
        return .dict(dict)
    }

    private static func writeSettings(_ dict: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: dict,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    private static func isOurGroup(_ group: [String: Any]) -> Bool {
        (group["hooks"] as? [[String: Any]])?.contains {
            ($0["command"] as? String)?.contains(shimName) == true
        } == true
    }

    private static func preToolUseGroups(_ settings: [String: Any]) -> [[String: Any]] {
        ((settings["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]]) ?? []
    }

    /// Is our hook entry present in this profile's settings.json?
    static func isInstalled(profile: String) -> Bool {
        guard let url = settingsURL(profile: profile),
              case .dict(let s) = readSettings(url) else { return false }
        return preToolUseGroups(s).contains(where: isOurGroup)
    }

    /// Add our hook group (idempotent). Returns false — without writing — if the
    /// settings file can't be safely parsed or has unexpected hook shapes.
    @discardableResult
    static func install(profile: String) -> Bool {
        guard stageShim(), let url = settingsURL(profile: profile) else { return false }
        guard case .dict(var settings) = readSettings(url) else {
            DebugLog.write("approvals: refusing to install — \(url.path) is unreadable/malformed")
            return false
        }
        // Refuse to touch a non-conforming `hooks` / `PreToolUse` rather than clobber it.
        if settings["hooks"] != nil, settings["hooks"] as? [String: Any] == nil {
            DebugLog.write("approvals: refusing to install — 'hooks' is not an object")
            return false
        }
        var hooks = (settings["hooks"] as? [String: Any]) ?? [:]
        if hooks["PreToolUse"] != nil, hooks["PreToolUse"] as? [[String: Any]] == nil {
            DebugLog.write("approvals: refusing to install — 'PreToolUse' is not an array of objects")
            return false
        }
        var groups = (hooks["PreToolUse"] as? [[String: Any]]) ?? []
        groups.removeAll(where: isOurGroup)                 // drop any stale AgentWatch group
        groups.append([
            "matcher": matcher,
            "hooks": [[
                "type": "command",
                "command": shimDest.path,
                "timeout": timeout,
            ]],
        ])
        hooks["PreToolUse"] = groups
        settings["hooks"] = hooks
        do {
            try writeSettings(settings, to: url)
            DebugLog.write("approvals: installed hook for profile \(profile)")
            return true
        } catch {
            DebugLog.write("approvals: install write failed for \(profile): \(error)")
            return false
        }
    }

    /// Remove only our hook group, preserving other settings. Aborts (returns
    /// false) if the file can't be parsed rather than overwriting it.
    @discardableResult
    static func uninstall(profile: String) -> Bool {
        guard let url = settingsURL(profile: profile) else { return false }
        guard case .dict(var settings) = readSettings(url) else {
            DebugLog.write("approvals: refusing to uninstall — \(url.path) is unreadable/malformed")
            return false
        }
        guard var hooks = settings["hooks"] as? [String: Any],
              var groups = hooks["PreToolUse"] as? [[String: Any]] else { return true }
        groups.removeAll(where: isOurGroup)
        if groups.isEmpty { hooks.removeValue(forKey: "PreToolUse") } else { hooks["PreToolUse"] = groups }
        if hooks.isEmpty { settings.removeValue(forKey: "hooks") } else { settings["hooks"] = hooks }
        do {
            try writeSettings(settings, to: url)
            DebugLog.write("approvals: uninstalled hook for profile \(profile)")
            return true
        } catch {
            DebugLog.write("approvals: uninstall write failed for \(profile): \(error)")
            return false
        }
    }
}
