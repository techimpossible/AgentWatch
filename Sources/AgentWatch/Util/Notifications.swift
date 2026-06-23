import Foundation
import UserNotifications

/// Wraps UNUserNotificationCenter with a per-session cooldown and an osascript fallback.
/// Ad-hoc signed apps sometimes can't post via UNUserNotificationCenter because the
/// bundle ID isn't registered with Apple's notification service — in that case we fall
/// back to `osascript -e 'display notification ...'`, which works without entitlements.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private var lastNotifiedAt: [Session.ID: Date] = [:]
    private let cooldown: TimeInterval = 30
    private var authorized: Bool = false
    private var triedAuth: Bool = false

    func requestAuthorizationIfNeeded() {
        guard !triedAuth else { return }
        triedAuth = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            Task { @MainActor in
                self?.authorized = granted
                if let error {
                    DebugLog.write("notif: auth error: \(error.localizedDescription)")
                } else {
                    DebugLog.write("notif: auth granted=\(granted)")
                }
            }
        }
    }

    func notifyNeedsInput(for session: Session) {
        let now = Date()
        if let last = lastNotifiedAt[session.id], now.timeIntervalSince(last) < cooldown {
            DebugLog.write("notif: cooldown — skip \(session.id)")
            return
        }
        lastNotifiedAt[session.id] = now

        let title = "Claude Code needs input"
        let body = "\(session.projectName) (PID \(session.pid)) is waiting."
        DebugLog.write("notif: post — \(title): \(body)")

        if authorized {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    DebugLog.write("notif: add failed (\(error.localizedDescription)) — falling back to osascript")
                    Self.osascriptFallback(title: title, body: body)
                }
            }
        } else {
            Self.osascriptFallback(title: title, body: body)
        }
    }

    nonisolated private static func osascriptFallback(title: String, body: String) {
        let safeTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let safeBody = body.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(safeBody)\" with title \"\(safeTitle)\""
        let p = Process()
        p.launchPath = "/usr/bin/osascript"
        p.arguments = ["-e", script]
        do {
            try p.run()
        } catch {
            DebugLog.write("notif: osascript fallback failed: \(error.localizedDescription)")
        }
    }
}
