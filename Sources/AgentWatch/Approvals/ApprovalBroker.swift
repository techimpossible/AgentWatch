import AppKit
import Foundation
import Observation

/// One pending permission request, pre-rendered into display strings so the
/// model stays Equatable (the raw tool_input is not).
struct ApprovalRequest: Identifiable, Equatable {
    let id: String          // request filename stem (correlates the response)
    let sessionId: String
    let cwd: String
    let toolName: String
    let headline: String    // e.g. "Run command", "Edit MascotView.swift"
    let detail: String      // command text / content / diff preview
    let createdAt: Date     // for FIFO ordering + TTL expiry
}

/// The app side of the GUI-approval flow. A `PreToolUse` hook shim writes a
/// request JSON into `approvals/requests/<id>.json` and blocks polling for
/// `approvals/responses/<id>`. This broker watches the requests folder, surfaces
/// each request for the UI, and writes the user's decision back.
///
/// File-based IPC (rather than a socket) keeps the prototype dependency-free and
/// robust: if the app isn't running the shim sees no fresh `.listening` marker
/// and defers to Claude's normal terminal prompt, so an agent never hangs.
///
/// Security note: this is single-user local IPC. Files live under a 0700 dir and
/// the shim writes them 0600, but a process running as the same user could still
/// forge a response. That's an accepted limitation for a local single-user tool;
/// the hook only ever *gates* a call the user's own agent was already about to make.
@MainActor
@Observable
final class ApprovalBroker {
    static let shared = ApprovalBroker()

    /// FIFO queue of requests awaiting a decision; `current` is what the UI shows.
    private(set) var pending: [ApprovalRequest] = []
    var current: ApprovalRequest? { pending.first }

    /// Fired whenever `pending` changes, so the panel controller can show/hide.
    var onChange: (() -> Void)?

    let baseDir: URL
    private let reqDir: URL
    private let resDir: URL
    private let marker: URL
    private var timer: Timer?
    private var seen = Set<String>()

    /// Drop a request the UI never resolved after this long — just past the
    /// shim's ~110s poll window, so its shim has already given up.
    private let requestTTL: TimeInterval = 115

    private init() {
        let appSup = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        baseDir = appSup.appendingPathComponent("AgentWatch/approvals", isDirectory: true)
        reqDir  = baseDir.appendingPathComponent("requests", isDirectory: true)
        resDir  = baseDir.appendingPathComponent("responses", isDirectory: true)
        marker  = baseDir.appendingPathComponent(".listening")
    }

    /// Begin listening: create dirs (0700), drop the marker, and poll.
    func start() {
        let fm = FileManager.default
        try? fm.createDirectory(at: baseDir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        try? fm.createDirectory(at: reqDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: resDir, withIntermediateDirectories: true)
        // Clear stale RESPONSES only. Leave requests: a prior instance's request
        // may still have a live shim waiting, so we adopt it in poll() instead.
        if let old = try? fm.contentsOfDirectory(at: resDir, includingPropertiesForKeys: nil) {
            for f in old { try? fm.removeItem(at: f) }
        }
        touchMarker()
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        DebugLog.write("approvals: listening at \(baseDir.path)")
    }

    func stop() {
        timer?.invalidate(); timer = nil
        try? FileManager.default.removeItem(at: marker)
        DebugLog.write("approvals: stopped")
    }

    /// Heartbeat: rewrite the marker each tick. A crashed app's marker goes stale,
    /// and the shim treats a stale marker as "not listening" (defers to terminal).
    private func touchMarker() {
        try? Data("\(Date().timeIntervalSince1970)".utf8).write(to: marker)
    }

    private func creationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }

    private func poll() {
        touchMarker()
        let fm = FileManager.default
        let now = Date()

        let files = ((try? fm.contentsOfDirectory(
            at: reqDir, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { (creationDate($0) ?? .distantPast) < (creationDate($1) ?? .distantPast) }
        let liveIds = Set(files.map { $0.deletingPathExtension().lastPathComponent })

        var changed = false

        // 1. Ingest newly-seen requests (FIFO by creation date).
        for f in files {
            let id = f.deletingPathExtension().lastPathComponent
            if seen.contains(id) { continue }
            seen.insert(id)
            if let req = parse(file: f, id: id, createdAt: creationDate(f) ?? now) {
                pending.append(req); changed = true
            } else {
                writeResponse(id: id, decision: "ask")   // unparseable → normal flow
                try? fm.removeItem(at: f)
                seen.remove(id)
            }
        }

        // 2. Reconcile: drop cards whose request file vanished (shim timed out) or
        //    that exceeded the TTL, and prune `seen` + orphan files with them.
        let before = pending.count
        pending.removeAll { req in
            let gone = !liveIds.contains(req.id)
            let expired = now.timeIntervalSince(req.createdAt) > requestTTL
            guard gone || expired else { return false }
            seen.remove(req.id)
            try? fm.removeItem(at: resDir.appendingPathComponent(req.id))       // orphan response
            if expired { try? fm.removeItem(at: reqDir.appendingPathComponent(req.id + ".json")) }
            return true
        }
        if pending.count != before { changed = true }

        if changed { onChange?() }
    }

    private func parse(file: URL, id: String, createdAt: Date) -> ApprovalRequest? {
        guard let data = try? Data(contentsOf: file),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let sessionId = obj["session_id"] as? String ?? ""
        let cwd = obj["cwd"] as? String ?? ""
        let tool = obj["tool_name"] as? String ?? "?"
        let input = obj["tool_input"] as? [String: Any] ?? [:]
        let (headline, detail) = Self.describe(tool: tool, input: input, cwd: cwd)
        return ApprovalRequest(id: id, sessionId: sessionId, cwd: cwd, toolName: tool,
                               headline: headline, detail: detail, createdAt: createdAt)
    }

    /// Resolve a request: write the decision word for the blocked shim to read,
    /// then remove it from the queue.
    func resolve(_ req: ApprovalRequest, decision: String) {
        writeResponse(id: req.id, decision: decision)
        try? FileManager.default.removeItem(at: reqDir.appendingPathComponent(req.id + ".json"))
        pending.removeAll { $0.id == req.id }
        seen.remove(req.id)
        DebugLog.write("approvals: \(decision) \(req.toolName) [\(req.id.prefix(8))]")
        onChange?()
    }

    private func writeResponse(id: String, decision: String) {
        try? decision.write(to: resDir.appendingPathComponent(id), atomically: true, encoding: .utf8)
    }

    // MARK: - Rendering (generic: tolerant of unverified tool_input schemas)

    static func describe(tool: String, input: [String: Any], cwd: String) -> (String, String) {
        func str(_ keys: String...) -> String? {
            for k in keys { if let v = input[k] as? String { return v } }
            return nil
        }
        switch tool {
        case "Bash":
            return ("Run command", str("command") ?? prettyJSON(input))
        case "Write":
            let path = str("file_path", "path") ?? "file"
            let body = str("content") ?? ""
            return ("Write \(relPath(path, cwd: cwd))", String(body.prefix(2000)))
        case "Edit", "MultiEdit":
            let path = str("file_path", "path") ?? "file"
            if let old = str("old_string"), let new = str("new_string") {
                let diff = "- " + String(old.prefix(900)) + "\n+ " + String(new.prefix(900))
                return ("Edit \(relPath(path, cwd: cwd))", diff)
            }
            return ("Edit \(relPath(path, cwd: cwd))", prettyJSON(input))
        default:
            return (tool, prettyJSON(input))
        }
    }

    static func relPath(_ p: String, cwd: String) -> String {
        if !cwd.isEmpty, p.hasPrefix(cwd + "/") { return String(p.dropFirst(cwd.count + 1)) }
        let home = NSHomeDirectory()
        if p.hasPrefix(home + "/") { return "~" + String(p.dropFirst(home.count)) }
        return (p as NSString).lastPathComponent
    }

    static func prettyJSON(_ obj: [String: Any]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: obj,
                                                  options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: d, encoding: .utf8) else { return "\(obj)" }
        return s
    }
}
