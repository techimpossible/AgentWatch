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

    func start() {
        guard pollingTask == nil else { return }
        DebugLog.write("starting polling loop (3s)")
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
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
