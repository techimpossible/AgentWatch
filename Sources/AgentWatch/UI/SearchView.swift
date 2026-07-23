import SwiftUI

struct SearchView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var query: String = ""
    @State private var hits: [SearchHit] = []
    @State private var loading = false
    @State private var lastQuery = ""
    @State private var capReached = false
    @State private var searchLimit = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
                TextField("Search inside messages…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .onSubmit { run() }
                    .accessibilityLabel("Search inside messages")
                if !query.isEmpty {
                    Button { query = ""; hits = []; lastQuery = ""; capReached = false } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.secondary)
                    .accessibilityLabel("Clear search")
                }
                Button("SEARCH") { run() }
                    .buttonStyle(.neonCyan)
                    .keyboardShortcut(.return)
                    .disabled(query.trimmingCharacters(in: .whitespaces).count < 2 || loading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Theme.surfaceRaised.opacity(0.5))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.hairline.opacity(scheme == .dark ? 0.12 : 0.10))
                    .frame(height: 0.5)
            }

            if loading {
                ProgressView("Searching…")
                    .font(Theme.prose)
                    .tint(Theme.accentBlue)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !lastQuery.isEmpty && hits.isEmpty {
                ContentUnavailableView(
                    "No matches for \"\(lastQuery)\"",
                    systemImage: "magnifyingglass",
                    description: Text("Searched every session under ~/.claude/projects/.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if hits.isEmpty {
                ContentUnavailableView(
                    "Full-text search across every message",
                    systemImage: "magnifyingglass",
                    description: Text("Scans the full text of every session under ~/.claude/projects/. For filtering sessions by project or opening prompt, use the History window. Type at least 2 characters and press Enter.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(hits) { hit in
                    HitRow(hit: hit, query: lastQuery)
                        .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                        .listRowSeparatorTint(Theme.hairline.opacity(scheme == .dark ? 0.12 : 0.10))
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                // Only shown when scanning stopped early at the cap — never on complete results.
                if capReached {
                    Text("Showing first \(searchLimit) matches — refine your search")
                        .font(Theme.eyebrow)
                        .tracking(0.8)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                        .accessibilityLabel("Showing only the first \(searchLimit) matches. Refine your search to narrow results.")
                }
            }
        }
        .frame(minWidth: 760, minHeight: 540)
        .darkGlassBackground()
    }

    private func run() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return }
        loading = true
        lastQuery = q
        Task.detached(priority: .userInitiated) {
            let result = SearchEngine.search(query: q)
            await MainActor.run {
                hits = result.hits
                capReached = result.capReached
                searchLimit = result.limit
                loading = false
            }
        }
    }
}

private struct HitRow: View {
    @Environment(\.openWindow) private var openWindow
    let hit: SearchHit
    let query: String

    /// Shared footer metadata font so session id and line number read as one mono column.
    private let footerMono = Font.system(size: 10, weight: .medium, design: .monospaced)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                NeonGlassCapsule(label: hit.role, tint: roleColor)
                NeonGlassCapsule(label: hit.profile, tint: Theme.profileColor(hit.profile))
                Text(hit.projectName)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if let ts = hit.timestamp {
                    Text(ts.formatted(date: .numeric, time: .shortened))
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .layoutPriority(1)
                        .frame(minWidth: 112, alignment: .trailing)
                }
            }
            Text(highlightedPreview)
                .font(Theme.approvalDetail)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(3)
                .truncationMode(.tail)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text(hit.sessionId)
                    .font(footerMono)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("line \(hit.lineNumber)")
                    .font(footerMono)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                actions
            }
        }
        // Combine the descriptive text into one VoiceOver element; action buttons stay
        // individually focusable via .accessibilityElement(children: .contain).
        .accessibilityElement(children: .contain)
        .accessibilityLabel(rowLabel)
    }

    /// One-line summary of the match for VoiceOver, read before the action buttons.
    private var rowLabel: String {
        var parts = ["\(hit.role) message in \(hit.projectName), profile \(hit.profile)"]
        if let ts = hit.timestamp {
            parts.append(ts.formatted(date: .numeric, time: .shortened))
        }
        parts.append("line \(hit.lineNumber)")
        parts.append(hit.preview)
        return parts.joined(separator: ", ")
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Button {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(value: hit.fileURL)
            } label: {
                Image(systemName: "text.alignleft")
            }
            .help("Open transcript")
            .buttonStyle(.secondary)
            .accessibilityLabel("Open transcript")
            .accessibilityHint("Opens the full session transcript in a new window")

            CopyButton(
                text: hit.sessionId,
                help: "Copy session ID",
                icon: "number"
            )
            .accessibilityLabel("Copy session ID")
            if let cwd = hit.cwd {
                CopyButton(
                    text: TerminalLauncher.resumeCommand(profile: hit.profile, sessionId: hit.sessionId, cwd: cwd),
                    help: "Copy resume command",
                    icon: "terminal"
                )
                .accessibilityLabel("Copy resume command")
                CopyButton(
                    text: TerminalLauncher.resumeURL(profile: hit.profile, sessionId: hit.sessionId, cwd: cwd),
                    help: "Copy AgentWatch link (click to resume in terminal)",
                    icon: "link"
                )
                .accessibilityLabel("Copy AgentWatch resume link")
            }
        }
    }

    private var roleColor: Color {
        switch hit.role {
        case "user": Theme.accentBlue
        case "assistant": Theme.accentGreen
        case "system": Theme.idle
        default: Theme.idle
        }
    }

    private var highlightedPreview: AttributedString {
        var attr = AttributedString(hit.preview)
        if !query.isEmpty {
            let lower = hit.preview.lowercased()
            var searchStart = lower.startIndex
            while let range = lower.range(of: query.lowercased(), range: searchStart..<lower.endIndex),
                  let attrRange = Range(range, in: attr) {
                attr[attrRange].backgroundColor = Theme.accentBlue.opacity(0.22)
                attr[attrRange].foregroundColor = Theme.textPrimary
                attr[attrRange].font = .system(size: 11, weight: .semibold, design: .monospaced)
                searchStart = range.upperBound
            }
        }
        return attr
    }
}
