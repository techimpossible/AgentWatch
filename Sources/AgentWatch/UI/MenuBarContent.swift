import SwiftUI

struct MenuBarContent: View {
    /// Extra padding applied *inside* the dark background so content clears the
    /// notch band (top) and the rounded bottom corners, without exposing a gap.
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0

    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @State private var launchAtLogin: Bool = LoginItem.isEnabled
    @State private var mascotEnabled: Bool = MascotOverlayController.isEnabled
    @State private var favorites = FavoritesStore.shared

    /// Active sessions sorted with favourites first; within each group keep
    /// the existing recency-ordered scan order from SessionScanner.
    private var sortedSessions: [Session] {
        let starred = state.sessions.filter { favorites.contains($0.id) }
        let rest = state.sessions.filter { !favorites.contains($0.id) }
        return starred + rest
    }

    /// Sessions grouped by profile, preserving favourites-first/recency order
    /// within each group. Profile order: "default" first, then alphabetical.
    private var groupedSessions: [(profile: String, sessions: [Session])] {
        var order: [String] = []
        var map: [String: [Session]] = [:]
        for s in sortedSessions {
            if map[s.profile] == nil { order.append(s.profile) }
            map[s.profile, default: []].append(s)
        }
        let profiles = order.sorted { a, b in
            if a == b { return false }
            if a == "default" { return true }
            if b == "default" { return false }
            return a < b
        }
        return profiles.map { ($0, map[$0] ?? []) }
    }

    /// Only label sessions by profile when more than one profile is in play.
    private var showProfileHeaders: Bool { groupedSessions.count > 1 }

    var body: some View {
        ZStack {
            // Opaque dark base — guarantees legibility regardless of system popover chrome.
            Theme.inkDeep
                .overlay {
                    // Subtle neon corner glows for the cyberpunk vibe, tuned down.
                    RadialGradient(
                        colors: [Theme.neonCyan.opacity(0.20), .clear],
                        center: .topLeading, startRadius: 20, endRadius: 280
                    )
                    RadialGradient(
                        colors: [Theme.neonMagenta.opacity(0.14), .clear],
                        center: .bottomTrailing, startRadius: 20, endRadius: 280
                    )
                }

            popoverBody
                .padding(.top, topInset)
                .padding(.bottom, bottomInset)
        }
        .environment(\.colorScheme, .dark)
        // Disable implicit animations on the popover root so first-paint
        // doesn't visibly cascade through every nested view.
        .animation(nil, value: state.sessions.map(\.id))
        .animation(nil, value: launchAtLogin)
    }

    private var popoverBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("AGENTWATCH")
                    .font(Theme.chromeCaption)
                    .tracking(2.0)
                    .foregroundStyle(Theme.neonCyan)
                Text("·")
                    .foregroundStyle(Theme.dpChrome.opacity(0.5))
                Text("\(state.sessions.count) ACTIVE")
                    .font(Theme.chromeCaption)
                    .tracking(1.0)
                    .foregroundStyle(Theme.dpChrome)
                Spacer()
                Button {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "history")
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.neonCyan)
                .help("History")
                .accessibilityLabel("History")
                Button {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "search")
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.neonMagenta)
                .help("Search")
                .accessibilityLabel("Search")
                Button {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "costs")
                } label: {
                    Image(systemName: "dollarsign.circle")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.neonGold)
                .help("Costs")
                .accessibilityLabel("Costs")
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 6)

            Divider()

            if state.sessions.isEmpty {
                VStack(spacing: 6) {
                    Text("No active Claude Code sessions")
                        .foregroundStyle(.secondary)
                    Text("Run `claude` in any terminal — it'll appear here within 3s.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(groupedSessions, id: \.profile) { group in
                        if showProfileHeaders {
                            ProfileSectionHeader(profile: group.profile, count: group.sessions.count)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                                .padding(.bottom, 4)
                        }
                        ForEach(group.sessions) { session in
                            Button {
                                DebugLog.write("ui: open transcript for \(session.id)")
                                NSApp.setActivationPolicy(.regular)
                                NSApp.activate(ignoringOtherApps: true)
                                openWindow(value: session.id)
                            } label: {
                                SessionRow(session: session)
                            }
                            .buttonStyle(.plain)
                            if session.id != group.sessions.last?.id {
                                Divider().padding(.leading, 36)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(spacing: 10) {
                Toggle(isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        if let actual = LoginItem.setEnabled(newValue) {
                            launchAtLogin = actual
                        }
                    }
                )) {
                    Text("LAUNCH AT LOGIN")
                        .font(Theme.chromeCaption)
                        .tracking(0.8)
                        .foregroundStyle(Theme.dpChrome.opacity(0.85))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                Toggle(isOn: Binding(
                    get: { mascotEnabled },
                    set: { newValue in
                        mascotEnabled = newValue
                        MascotOverlayController.isEnabled = newValue
                    }
                )) {
                    Text("MASCOT")
                        .font(Theme.chromeCaption)
                        .tracking(0.8)
                        .foregroundStyle(Theme.dpChrome.opacity(0.85))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                Spacer()
                Button("REFRESH") { Task { await state.refresh() } }
                    .buttonStyle(.neonCyan)
                    .keyboardShortcut("r")
                Button("QUIT") { NSApp.terminate(nil) }
                    .buttonStyle(.neonMagenta)
                    .keyboardShortcut("q")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .task {
            // Re-sync the toggle with the system state on each popover open.
            // Wrapped in a no-animation transaction so the switch doesn't
            // visibly slide on first paint.
            let actual = LoginItem.isEnabled
            if actual != launchAtLogin {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { launchAtLogin = actual }
            }
        }
    }
}

private struct SessionRow: View {
    @Environment(AppState.self) private var state
    let session: Session
    @State private var confirmingKill = false

    var body: some View {
        HStack(spacing: 12) {
            StatusDot(status: session.status)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.displayTitle)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(session.displaySubtitle.uppercased())
                    .font(Theme.chromeCaption)
                    .tracking(0.6)
                    .foregroundStyle(Theme.dpChrome.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer()
            // StarButton and CopyButton already provide their own
            // .accessibilityLabel internally, so none is added here.
            StarButton(sessionId: session.id)
            CopyButton(
                text: TerminalLauncher.resumeCommand(profile: session.profile, sessionId: session.id, cwd: session.cwd),
                help: "Copy resume command",
                icon: "terminal"
            )
            CopyButton(
                text: TerminalLauncher.resumeURL(profile: session.profile, sessionId: session.id, cwd: session.cwd),
                help: "Copy AgentWatch link (click to resume in terminal)",
                icon: "link"
            )
            Button {
                TerminalLauncher.resumeSession(profile: session.profile, sessionId: session.id, cwd: session.cwd)
            } label: {
                Image(systemName: "play.circle")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.neonCyan)
            .help("Open a new Terminal and run: claude --resume \(session.id)")
            .accessibilityLabel("Resume session in new Terminal")
            Button {
                TerminalLauncher.bringToFront(pid: session.pid, fallbackCwd: session.cwd)
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.neonCyan)
            .help("Bring this session's terminal to front")
            .accessibilityLabel("Bring terminal to front")
            Button {
                confirmingKill = true
            } label: {
                Image(systemName: "stop.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.red.opacity(0.85))
            }
            .buttonStyle(.plain)
            .help("Kill this session (terminate PID \(session.pid))")
            // Spell out the destructive nature in the label since AppKit exposes
            // no dedicated "destructive" accessibility trait for a plain button.
            .accessibilityLabel("Kill session (destructive)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .confirmationDialog(
            "Kill this session?",
            isPresented: $confirmingKill,
            titleVisibility: .visible
        ) {
            Button("Kill (PID \(session.pid))", role: .destructive) {
                DebugLog.write("ui: kill session \(session.id) pid \(session.pid)")
                SessionControl.kill(pid: session.pid)
                Task { await state.refresh() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Terminates the Claude process for “\(session.displayTitle)”. Unsaved work in that session will be lost.")
        }
    }
}
