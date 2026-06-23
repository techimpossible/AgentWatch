import SwiftUI

@main
struct AgentWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var windowOpener = WindowOpener.shared

    var body: some Scene {
        WindowGroup("Transcript", for: Session.ID.self) { $sessionId in
            if let id = sessionId, let session = AppState.shared.sessions.first(where: { $0.id == id }) {
                TranscriptView(session: session)
                    .environment(AppState.shared)
            } else {
                ContentUnavailableView("Session not active", systemImage: "questionmark.circle")
            }
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        WindowGroup("Transcript", for: URL.self) { $url in
            if let u = url {
                TranscriptView(fileURL: u)
            } else {
                ContentUnavailableView("No file", systemImage: "questionmark.circle")
            }
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("Costs", id: "costs") {
            CostsView()
                .environment(AppState.shared)
                .background(WindowOpenerBridge())
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("Search", id: "search") {
            SearchView()
                .environment(AppState.shared)
                .background(WindowOpenerBridge())
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("History", id: "history") {
            HistoryView()
                .environment(AppState.shared)
                .background(WindowOpenerBridge())
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

/// Bridges AppKit's right-click menu requests ("open window id X") into SwiftUI's openWindow action.
/// Lives in an empty background view so every Window scene listens for pending requests.
private struct WindowOpenerBridge: View {
    @ObservedObject private var opener = WindowOpener.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .onChange(of: opener.pendingOpen) { _, newValue in
                if let id = newValue {
                    openWindow(id: id)
                    opener.pendingOpen = nil
                }
            }
    }
}
