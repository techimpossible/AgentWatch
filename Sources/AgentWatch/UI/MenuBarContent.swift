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
            // Solid warm base + one barely-there sheen (§7.1). The popover base is
            // never glass; the notch always renders dark, so we resolve dark tokens.
            Theme.surface
                .overlay {
                    LinearGradient(
                        colors: [Color.white.opacity(0.03), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    RadialGradient(
                        colors: [Theme.accent.opacity(0.06), .clear],
                        center: .topTrailing, startRadius: 20, endRadius: 320
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
                    .font(Theme.eyebrow)
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                Text("·")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textTertiary)
                Text("\(state.sessions.count) ACTIVE")
                    .font(Theme.eyebrow)
                    .tracking(1.2)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Button {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "history")
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.secondary)
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
                .buttonStyle(.secondary)
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
                .buttonStyle(.secondary)
                .help("Costs")
                .accessibilityLabel("Costs")
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider().overlay(Theme.hairline.opacity(0.12))

            if state.sessions.isEmpty {
                VStack(spacing: 8) {
                    Text("No active Claude Code sessions")
                        .font(Theme.prose)
                        .foregroundStyle(Theme.textSecondary)
                    Text("Run `claude` in any terminal — it'll appear here within 3s.")
                        .font(Theme.prose)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                VStack(spacing: 0) {
                    ForEach(groupedSessions, id: \.profile) { group in
                        if showProfileHeaders {
                            ProfileSectionHeader(profile: group.profile, count: group.sessions.count)
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
                                Divider()
                                    .overlay(Theme.hairline.opacity(0.12))
                                    .padding(.leading, 36)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider().overlay(Theme.hairline.opacity(0.12))

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
                        .font(Theme.eyebrowTiny)
                        .tracking(1.2)
                        .foregroundStyle(Theme.textSecondary)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Theme.accentBlue)
                Toggle(isOn: Binding(
                    get: { mascotEnabled },
                    set: { newValue in
                        mascotEnabled = newValue
                        MascotOverlayController.isEnabled = newValue
                    }
                )) {
                    Text("MASCOT")
                        .font(Theme.eyebrowTiny)
                        .tracking(1.2)
                        .foregroundStyle(Theme.textSecondary)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Theme.accentBlue)
                Spacer()
                Button("REFRESH") { Task { await state.refresh() } }
                    .buttonStyle(.secondary)
                    .keyboardShortcut("r")
                Button("QUIT") { NSApp.terminate(nil) }
                    .buttonStyle(.danger)
                    .keyboardShortcut("q")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
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
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            StatusDot(status: session.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayTitle)
                    .font(Theme.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(session.displaySubtitle)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
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
            .buttonStyle(.secondary)
            .help("Open a new Terminal and run: claude --resume \(session.id)")
            .accessibilityLabel("Resume session in new Terminal")
            Button {
                TerminalLauncher.bringToFront(pid: session.pid, fallbackCwd: session.cwd)
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.secondary)
            .help("Bring this session's terminal to front")
            .accessibilityLabel("Bring terminal to front")
            Button {
                confirmingKill = true
            } label: {
                Image(systemName: "stop.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.danger)
            }
            .buttonStyle(.plain)
            .help("Kill this session (terminate PID \(session.pid))")
            // Spell out the destructive nature in the label since AppKit exposes
            // no dedicated "destructive" accessibility trait for a plain button.
            .accessibilityLabel("Kill session (destructive)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.hover.opacity(hovering ? 0.06 : 0))
                .padding(.horizontal, 6)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
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
