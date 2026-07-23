import AppKit
import SwiftUI

/// Tiny clipboard-icon button. On click, writes `text` to NSPasteboard and
/// flips the icon to a checkmark for 1.5s as confirmation feedback.
struct CopyButton: View {
    let text: String
    var help: String = "Copy"
    var tint: Color = Theme.textSecondary        // neutral row/toolbar icon
    var icon: String = "doc.on.doc"
    @State private var copied = false
    @State private var hovering = false

    var body: some View {
        Button {
            guard !text.isEmpty else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
            withAnimation(.easeOut(duration: 0.15)) { copied = true }
            Task {
                try? await Task.sleep(for: .milliseconds(1500))
                withAnimation(.easeOut(duration: 0.2)) { copied = false }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : icon)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                // green = done; otherwise quiet neutral, lifting to primary on hover.
                .foregroundStyle(copied ? Theme.accentGreen : (hovering ? Theme.textPrimary : tint))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(Theme.hover.opacity(hovering ? 0.10 : 0.0))
                )
        }
        .buttonStyle(.plain)
        .disabled(text.isEmpty)
        .onHover { hovering = $0 }
        .help(text.isEmpty ? "Nothing to copy" : help)
        .accessibilityLabel(text.isEmpty ? "Nothing to copy" : help)
        .accessibilityValue(copied ? "Copied" : "")
    }
}
