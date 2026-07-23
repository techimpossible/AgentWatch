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
            Divider().overlay(Theme.hairline.opacity(0.12))
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
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(entries) { entry in
                            EntryView(entry: entry)
                            Divider()
                                .overlay(Theme.hairline.opacity(0.12))
                                .padding(.leading, 28)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 540)
        .darkGlassBackground()
        .onAppear { load() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(headerTitle)
                    .font(Theme.titleCard)
                    .foregroundStyle(Theme.textPrimary)
                Text(headerSubtitle)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("SESSION \(headerSessionId)")
                    .font(Theme.eyebrowTiny)
                    .tracking(1.0)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if case .active(let s) = source {
                    Label(s.status.label, systemImage: s.status.symbol)
                        .font(Theme.eyebrow)
                        .tracking(0.8)
                        .foregroundStyle(s.status.color)
                    Text("PID \(s.pid)")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Label("HISTORICAL", systemImage: "clock")
                        .font(Theme.eyebrow)
                        .tracking(0.8)
                        .foregroundStyle(Theme.textSecondary)
                }
                if !entries.isEmpty {
                    Text("\(entries.count) MESSAGES")
                        .font(Theme.eyebrowTiny)
                        .tracking(1.0)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(20)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: roleIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(roleColor)
                Text(roleLabel.uppercased())
                    .font(Theme.eyebrow)
                    .tracking(1.2)
                    .foregroundStyle(roleColor)
                if let model = entry.model {
                    Text(modelShortName(model))
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.surfaceRaised))
                        .overlay(Capsule().strokeBorder(Theme.hairline.opacity(0.14), lineWidth: 0.75))
                }
                Spacer()
                if let ts = entry.timestamp {
                    Text(ts.formatted(date: .omitted, time: .shortened))
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textTertiary)
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
        case .user: Theme.accentBlue
        case .assistant: Theme.textPrimary
        case .system: Theme.idle
        case .other: Theme.textTertiary
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
                .font(.system(.body, design: .serif))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .thinking(let s):
            DisclosureGroup {
                Text(s)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.surfaceSunken)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Theme.hairline.opacity(0.12), lineWidth: 0.5)
                    )
            } label: {
                Label("Thinking (\(s.count) chars)", systemImage: "bubble.left")
                    .font(Theme.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(Theme.textSecondary)
            }
        case .redactedThinking:
            Label("Redacted thinking", systemImage: "eye.slash")
                .font(Theme.eyebrow)
                .tracking(0.8)
                .foregroundStyle(Theme.textSecondary)
        case .toolUse(let name, let input):
            VStack(alignment: .leading, spacing: 6) {
                Label("TOOL · \(name)", systemImage: "wrench.and.screwdriver")
                    .font(Theme.eyebrow)
                    .tracking(1.0)
                    .foregroundStyle(Theme.textSecondary)
                payloadWell(input, tint: Theme.hairline.opacity(0.12))
            }
        case .toolResult(let text, let isError):
            VStack(alignment: .leading, spacing: 6) {
                Label(isError ? "TOOL ERROR" : "TOOL RESULT",
                      systemImage: isError ? "xmark.circle" : "checkmark.circle")
                    .font(Theme.eyebrow)
                    .tracking(1.0)
                    .foregroundStyle(isError ? Theme.danger : Theme.accentGreen)
                payloadWell(text.isEmpty ? "(empty)" : text,
                            tint: (isError ? Theme.danger : Theme.accentGreen).opacity(0.30))
            }
        case .unknown(let t):
            Text("(unknown block: \(t))")
                .font(Theme.mono)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    /// Inset payload well: sunken warm surface, monospaced payload, hairline (or semantic) border.
    private func payloadWell(_ content: String, tint: Color) -> some View {
        Text(content)
            .font(Theme.approvalDetail)
            .foregroundStyle(Theme.textSecondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.surfaceSunken)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(tint, lineWidth: 0.75)
            )
    }
}
