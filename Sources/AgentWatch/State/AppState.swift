import AppKit
import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    var sessions: [Session] = []
    var lastRefresh: Date = .distantPast

    private var pollingTask: Task<Void, Never>?
    private var previousStatuses: [Session.ID: SessionStatus] = [:]
    private let log = Logger(subsystem: "com.techimpossible.agentwatch", category: "AppState")

    private init() {
        DebugLog.write("AppState init")
        NotificationManager.shared.requestAuthorizationIfNeeded()
        start()
    }

    // Adaptive polling cadence: fast while there's active work (or the app is
    // frontmost), slow when everything is idle — saves battery without changing
    // what data is shown.
    private static let activeInterval: Duration = .seconds(3)
    private static let idleInterval: Duration = .seconds(10)

    func start() {
        guard pollingTask == nil else { return }
        DebugLog.write("starting polling loop (adaptive 3s/10s)")
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                // Pick the next delay from the state produced by refresh().
                let interval = self?.pollInterval() ?? AppState.activeInterval
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Fast interval when any session is working/needs-input or the app is
    /// active; otherwise back off to the idle interval.
    private func pollInterval() -> Duration {
        let hasActiveSession = sessions.contains {
            $0.status == .working || $0.status == .needsInput
        }
        if hasActiveSession || NSApp.isActive {
            return AppState.activeInterval
        }
        return AppState.idleInterval
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refresh() async {
        DebugLog.write("refresh: starting scan")
        let scanned = await Task.detached(priority: .utility) {
            SessionScanner.scan()
        }.value

        // Detect status transitions and fire notifications + the mascot.
        for session in scanned {
            let prev = previousStatuses[session.id]
            if session.status == .needsInput && prev != .needsInput {
                NotificationManager.shared.notifyNeedsInput(for: session)
                MascotOverlayController.shared?.show(reason: .needsInput, profile: session.profile)
            } else if session.status == .idle && prev == .working {
                // A task just finished (was actively working, now idle).
                MascotOverlayController.shared?.show(reason: .finished, profile: session.profile)
            }
        }
        // Refresh the previous-status map (drop sessions that disappeared).
        var next: [Session.ID: SessionStatus] = [:]
        for s in scanned { next[s.id] = s.status }
        previousStatuses = next

        self.sessions = scanned
        self.lastRefresh = Date()
        DebugLog.write("refresh: complete, \(scanned.count) sessions")
    }
}
