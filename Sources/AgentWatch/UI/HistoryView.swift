import SwiftUI

struct HistoryView: View {
    @State private var sessions: [HistoricalSession] = []
    @State private var loading = false
    @State private var filter: String = ""
    @State private var favoritesOnly: Bool = false
    @State private var favorites = FavoritesStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("HISTORY")
                        .font(Theme.chromeTitle)
                        .tracking(3.0)
                        .foregroundStyle(Theme.neonCyan)
                    Text("\(sessions.count) SESSIONS ACROSS ALL PROJECTS")
                        .font(Theme.chromeCaption)
                        .tracking(1.2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button {
                    favoritesOnly.toggle()
                } label: {
                    Image(systemName: favoritesOnly ? "star.fill" : "star")
                }
                .buttonStyle(.neonGold)
                .help(favoritesOnly ? "Show all sessions" : "Show favourites only")
                .accessibilityLabel("Favourites only")
                .accessibilityValue(favoritesOnly ? "On" : "Off")
                TextField("FILTER SESSIONS…", text: $filter)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(.regular.tint(Theme.neonCyan.opacity(0.10)), in: Capsule())
                    .frame(width: 220)
                Button {
                    reload()
                } label: {
                    Label("REFRESH", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.neonCyan)
                .disabled(loading)
            }
            .padding(16)

            Divider()

            if loading {
                ProgressView("Scanning…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredSessions.isEmpty {
                ContentUnavailableView(
                    sessions.isEmpty ? "No past sessions" : "No matches",
                    systemImage: "clock.arrow.circlepath"
                )
            } else {
                List {
                    if groupedSessions.count > 1 {
                        ForEach(groupedSessions, id: \.profile) { group in
                            Section {
                                ForEach(group.sessions) { session in
                                    HistoryRow(session: session)
                                }
                            } header: {
                                ProfileSectionHeader(profile: group.profile, count: group.sessions.count)
                            }
                        }
                    } else {
                        ForEach(filteredSessions) { session in
                            HistoryRow(session: session)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 760, minHeight: 540)
        .darkGlassBackground()
        .onAppear { if sessions.isEmpty { reload() } }
    }

    private var filteredSessions: [HistoricalSession] {
        var result = sessions
        if favoritesOnly {
            result = result.filter { favorites.contains($0.sessionId) }
        }
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            result = result.filter {
                $0.projectName.lowercased().contains(q)
                    || $0.firstMessage?.lowercased().contains(q) == true
                    || $0.sessionId.lowercased().contains(q)
            }
        }
        return result
    }

    /// Filtered sessions grouped by profile, preserving the recency order within
    /// each group. Profile order: "default" first, then alphabetical.
    private var groupedSessions: [(profile: String, sessions: [HistoricalSession])] {
        var order: [String] = []
        var map: [String: [HistoricalSession]] = [:]
        for s in filteredSessions {
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

    private func reload() {
        loading = true
        Task.detached(priority: .userInitiated) {
            let loaded = HistoryCatalog.load()
            await MainActor.run {
                sessions = loaded
                loading = false
            }
        }
    }
}

private struct HistoryRow: View {
    @Environment(\.openWindow) private var openWindow
    let session: HistoricalSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(session.projectName)
                    .font(.callout.bold())
                Text("•")
                    .foregroundStyle(.tertiary)
                Text(session.lastModified.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("• \(session.messageCount) lines")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                actions
            }
            if let preview = session.firstMessage {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(session.sessionId)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var actions: some View {
        HStack(spacing: 6) {
            StarButton(sessionId: session.sessionId)
            CopyButton(
                text: session.firstMessage ?? "",
                help: "Copy first prompt"
            )
            if let cwd = session.cwd {
                Button {
                    TerminalLauncher.resumeSession(profile: session.profile, sessionId: session.sessionId, cwd: cwd)
                } label: {
                    Image(systemName: "play.circle")
                }
                .help("Open Terminal and run: claude --resume \(session.sessionId)")
                .buttonStyle(.neonCyan)
                .accessibilityLabel("Resume in Terminal")

                CopyButton(
                    text: TerminalLauncher.resumeCommand(profile: session.profile, sessionId: session.sessionId, cwd: cwd),
                    help: "Copy resume command",
                    icon: "terminal"
                )
                CopyButton(
                    text: TerminalLauncher.resumeURL(profile: session.profile, sessionId: session.sessionId, cwd: cwd),
                    help: "Copy AgentWatch link (click to resume in terminal)",
                    icon: "link"
                )

                Button {
                    TerminalLauncher.revealInFinder(cwd)
                } label: {
                    Image(systemName: "folder")
                }
                .help("Reveal \(cwd) in Finder")
                .buttonStyle(.neonCyan)
                .accessibilityLabel("Reveal in Finder")
            }

            Button {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(value: session.fileURL)
            } label: {
                Image(systemName: "text.alignleft")
            }
            .help("Open transcript")
            .buttonStyle(.neonMagenta)
            .accessibilityLabel("Open transcript")
        }
    }
}
