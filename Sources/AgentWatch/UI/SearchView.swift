import SwiftUI

struct SearchView: View {
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
                    .foregroundStyle(Theme.neonMagenta)
                    .accessibilityHidden(true)
                TextField("SEARCH INSIDE MESSAGES…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { run() }
                    .accessibilityLabel("Search inside messages")
                if !query.isEmpty {
                    Button { query = ""; hits = []; lastQuery = ""; capReached = false } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.neonMagenta)
                    .accessibilityLabel("Clear search")
                }
                Button("SEARCH") { run() }
                    .buttonStyle(.neonMagenta)
                    .keyboardShortcut(.return)
                    .disabled(query.trimmingCharacters(in: .whitespaces).count < 2 || loading)
            }
            .padding(14)
            .glassEffect(.regular.tint(Theme.neonMagenta.opacity(0.08)), in: RoundedRectangle(cornerRadius: 0))

            Divider()

            if loading {
                ProgressView("Searching…")
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
                }
                .listStyle(.inset)
                // Only shown when scanning stopped early at the cap — never on complete results.
                if capReached {
                    Text("Showing first \(searchLimit) matches — refine your search")
                        .font(Theme.chromeCaption)
                        .foregroundStyle(.secondary)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                NeonGlassCapsule(label: hit.role, tint: roleColor)
                NeonGlassCapsule(label: hit.profile, tint: Theme.profileColor(hit.profile))
                Text(hit.projectName)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(Theme.neonCyan)
                Spacer()
                if let ts = hit.timestamp {
                    Text(ts.formatted(date: .numeric, time: .shortened))
                        .font(Theme.chromeCaption)
                        .foregroundStyle(.tertiary)
                }
            }
            Text(highlightedPreview)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(3)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Text(hit.sessionId).font(.caption2).foregroundStyle(.tertiary)
                Text("line \(hit.lineNumber)").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                actions
            }
        }
        .padding(.vertical, 4)
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
            .buttonStyle(.neonMagenta)
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
        case "user": Theme.neonCyan
        case "assistant": Theme.neonMagenta
        case "system": Theme.dpChrome
        default: .gray
        }
    }

    private var highlightedPreview: AttributedString {
        var attr = AttributedString(hit.preview)
        if !query.isEmpty {
            let lower = hit.preview.lowercased()
            var searchStart = lower.startIndex
            while let range = lower.range(of: query.lowercased(), range: searchStart..<lower.endIndex),
                  let attrRange = Range(range, in: attr) {
                attr[attrRange].backgroundColor = .yellow.opacity(0.4)
                attr[attrRange].font = .system(.caption, design: .monospaced).bold()
                searchStart = range.upperBound
            }
        }
        return attr
    }
}
