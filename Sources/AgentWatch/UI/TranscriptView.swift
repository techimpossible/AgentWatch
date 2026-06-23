import SwiftUI

struct TranscriptView: View {
    /// Either an active Session (with PID/status) or just a file URL for historical sessions.
    enum Source {
        case active(Session)
        case historical(fileURL: URL)
    }

    let source: Source
    @State private var entries: [TranscriptEntry] = []
    @State private var loadError: String?

    init(session: Session) {
        self.source = .active(session)
    }
    init(fileURL: URL) {
        self.source = .historical(fileURL: fileURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let err = loadError {
                ContentUnavailableView(
                    "Could not load transcript",
                    systemImage: "exclamationmark.triangle",
                    description: Text(err)
                )
            } else if entries.isEmpty {
                ContentUnavailableView("Loading…", systemImage: "ellipsis")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(entries) { entry in
                            EntryView(entry: entry)
                            Divider()
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 540)
        .darkGlassBackground()
        .onAppear { load() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle).font(.headline)
                Text(headerSubtitle).font(.caption).foregroundStyle(.secondary)
                Text("Session \(headerSessionId)").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if case .active(let s) = source {
                    Label(s.status.label, systemImage: s.status.symbol)
                        .foregroundStyle(s.status.color)
                    Text("PID \(s.pid)").font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("Historical", systemImage: "clock")
                        .foregroundStyle(.secondary)
                }
                if !entries.isEmpty {
                    Text("\(entries.count) messages").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
    }

    private var headerTitle: String {
        switch source {
        case .active(let s): return s.displayTitle
        case .historical(let url): return url.deletingLastPathComponent().lastPathComponent
        }
    }
    private var headerSubtitle: String {
        switch source {
        case .active(let s): return s.cwd
        case .historical(let url): return url.path
        }
    }
    private var headerSessionId: String {
        switch source {
        case .active(let s): return s.sessionId
        case .historical(let url): return url.deletingPathExtension().lastPathComponent
        }
    }

    private func load() {
        let url: URL?
        switch source {
        case .active(let s):
            url = JSONLReader.findFile(sessionId: s.sessionId)
        case .historical(let u):
            url = u
        }
        guard let resolved = url else {
            loadError = "No JSONL file found"
            return
        }
        Task.detached(priority: .userInitiated) {
            let parsed = JSONLReader.read(resolved)
            await MainActor.run { entries = parsed }
        }
    }
}

private struct EntryView: View {
    let entry: TranscriptEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: roleIcon)
                    .foregroundStyle(roleColor)
                Text(roleLabel)
                    .font(.headline)
                    .foregroundStyle(roleColor)
                if let model = entry.model {
                    Text(modelShortName(model))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.gray.opacity(0.15), in: Capsule())
                }
                Spacer()
                if let ts = entry.timestamp {
                    Text(ts.formatted(date: .omitted, time: .shortened))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                CopyButton(
                    text: copyableText,
                    help: "Copy this \(roleLabel.lowercased()) message"
                )
            }
            ForEach(Array(entry.blocks.enumerated()), id: \.offset) { _, block in
                BlockView(block: block)
            }
        }
    }

    /// Concatenate the entry's content blocks into a single string for the clipboard.
    /// Includes text, thinking, tool_use (name + input JSON), tool_result content,
    /// and redacted-thinking placeholder. Empty blocks are skipped so the button
    /// only greys out when the entry truly has nothing copyable.
    private var copyableText: String {
        entry.blocks.compactMap { block -> String? in
            switch block {
            case .text(let s):
                return s.isEmpty ? nil : s
            case .thinking(let s):
                return s.isEmpty ? nil : s
            case .toolUse(let name, let input):
                return "Tool: \(name)\n\(input)"
            case .toolResult(let text, let isError):
                guard !text.isEmpty else { return nil }
                return isError ? "[error] \(text)" : text
            case .redactedThinking:
                return "[redacted thinking]"
            case .unknown(let t):
                return "[unknown block: \(t)]"
            }
        }
        .joined(separator: "\n\n")
    }

    private var roleIcon: String {
        switch entry.role {
        case .user: "person.fill"
        case .assistant: "sparkles"
        case .system: "gear"
        case .other: "questionmark"
        }
    }
    private var roleColor: Color {
        switch entry.role {
        case .user: Theme.neonCyan
        case .assistant: Theme.neonMagenta
        case .system: Theme.dpChrome
        case .other: .gray
        }
    }
    private var roleLabel: String {
        switch entry.role {
        case .user: "User"
        case .assistant: "Assistant"
        case .system: "System"
        case .other: "Other"
        }
    }
    private func modelShortName(_ s: String) -> String {
        if let slash = s.firstIndex(of: "/") {
            return String(s[s.index(after: slash)...])
        }
        return s
    }
}

private struct BlockView: View {
    let block: ContentBlock

    var body: some View {
        switch block {
        case .text(let s):
            Text(s)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .thinking(let s):
            DisclosureGroup {
                Text(s)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            } label: {
                Label("Thinking (\(s.count) chars)", systemImage: "bubble.left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .redactedThinking:
            Label("Redacted thinking", systemImage: "eye.slash")
                .font(.caption).foregroundStyle(.secondary)
        case .toolUse(let name, let input):
            VStack(alignment: .leading, spacing: 4) {
                Label("Tool: \(name)", systemImage: "wrench.and.screwdriver")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                Text(input)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
        case .toolResult(let text, let isError):
            VStack(alignment: .leading, spacing: 4) {
                Label(isError ? "Tool error" : "Tool result",
                      systemImage: isError ? "xmark.circle" : "checkmark.circle")
                    .font(.caption.bold())
                    .foregroundStyle(isError ? .red : .green)
                Text(text.isEmpty ? "(empty)" : text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background((isError ? Color.red : .green).opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 6))
            }
        case .unknown(let t):
            Text("(unknown block: \(t))")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }
}
