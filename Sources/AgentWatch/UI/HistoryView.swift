import SwiftUI

struct HistoryView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var sessions: [HistoricalSession] = []
    @State private var loading = false
    @State private var filter: String = ""
    @State private var favoritesOnly: Bool = false
    @State private var favorites = FavoritesStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("HISTORY")
                        .font(Theme.titleWindow)
                        .tracking(0.5)
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 6) {
                        Text("\(sessions.count)")
                            .font(Theme.mono)
                            .foregroundStyle(Theme.textSecondary)
                        Text("SESSIONS ACROSS ALL PROJECTS")
                            .font(Theme.eyebrow)
                            .tracking(1.2)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer(minLength: 12)
                Button {
                    favoritesOnly.toggle()
                } label: {
                    Image(systemName: favoritesOnly ? "star.fill" : "star")
                }
                .buttonStyle(favoritesOnly ? .neonGold : .secondary)
                .help(favoritesOnly ? "Show all sessions" : "Show favourites only")
                .accessibilityLabel("Favourites only")
                .accessibilityValue(favoritesOnly ? "On" : "Off")

                TextField("FILTER SESSIONS…", text: $filter)
                    .textFieldStyle(.plain)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassEffect(.regular.tint(Theme.idle.opacity(0.08)), in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(Theme.hairline.opacity(scheme == .dark ? 0.12 : 0.10), lineWidth: 0.5)
                    )
                    .frame(width: 220)

                Button {
                    reload()
                } label: {
                    Label("REFRESH", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.secondary)
                .disabled(loading)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()
                .overlay(Theme.hairline.opacity(scheme == .dark ? 0.12 : 0.10))

            if loading {
                ProgressView("Scanning…")
                    .font(Theme.prose)
                    .tint(Theme.accentBlue)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredSessions.isEmpty {
                ContentUnavailableView(
                    sessions.isEmpty ? "No past sessions" : "No matches",
                    systemImage: "clock.arrow.circlepath"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if groupedSessions.count > 1 {
                        ForEach(groupedSessions, id: \.profile) { group in
                            Section {
                                ForEach(group.sessions) { session in
                                    HistoryRow(session: session)
                                        .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                                        .listRowSeparatorTint(Theme.hairline.opacity(scheme == .dark ? 0.12 : 0.10))
                                }
                            } header: {
                                ProfileSectionHeader(profile: group.profile, count: group.sessions.count)
                            }
                        }
                    } else {
                        ForEach(filteredSessions) { session in
                            HistoryRow(session: session)
                                .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                                .listRowSeparatorTint(Theme.hairline.opacity(scheme == .dark ? 0.12 : 0.10))
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
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
    @Environment(\.colorScheme) private var scheme
    let session: HistoricalSession

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Profile identity spine
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Theme.profileColor(session.profile))
                .frame(width: 2)
                .padding(.vertical, 2)
                .opacity(0.9)

            VStack(alignment: .leading, spacing: 6) {
                // Title + timestamp column (timestamp stays pinned right; title flexes).
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(session.projectName)
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text(session.lastModified.formatted(date: .abbreviated, time: .shortened))
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                        .frame(minWidth: 130, alignment: .trailing)
                }

                if let preview = session.firstMessage {
                    Text(preview)
                        .font(Theme.prose)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Footer metadata + actions (actions stay pinned right).
                HStack(spacing: 8) {
                    Text(session.sessionId)
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(session.messageCount) lines")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textTertiary)
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    actions
                }
            }
        }
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
                .buttonStyle(.secondary)
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
                .buttonStyle(.secondary)
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
            .buttonStyle(.secondary)
            .accessibilityLabel("Open transcript")
        }
    }
}
