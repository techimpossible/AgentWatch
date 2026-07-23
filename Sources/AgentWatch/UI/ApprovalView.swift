import SwiftUI

/// The approval card: what tool the agent wants to run, for which session, with
/// Allow / Deny / Ask-in-terminal. Reads the broker's current request reactively.
struct ApprovalView: View {
    var broker: ApprovalBroker

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if let req = broker.current {
                card(req)
            } else {
                Color.clear
            }
        }
        .frame(width: 460, height: 340)
    }

    private func profile(for sessionId: String) -> String? {
        AppState.shared.sessions.first { $0.sessionId == sessionId }?.profile
    }

    private func card(_ req: ApprovalRequest) -> some View {
        let prof = profile(for: req.sessionId)
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("PERMISSION")
                    .font(Theme.eyebrow)
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 8)
                if let prof {
                    let tint = Theme.profileColor(prof)
                    Text(prof.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(tint)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .glassEffect(.regular.tint(tint.opacity(0.16)), in: Capsule())
                        .overlay(Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 0.75))
                }
                if broker.pending.count > 1 {
                    Text("+\(broker.pending.count - 1)")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            Text(req.headline)
                .font(Theme.titleCard)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)

            ScrollView(.vertical) {
                Text(req.detail.isEmpty ? "(no details)" : req.detail)
                    .font(Theme.approvalDetail)
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.surfaceSunken)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.hairline.opacity(scheme == .dark ? 0.12 : 0.10), lineWidth: 0.5)
            )

            HStack(spacing: 8) {
                Button("Deny")            { broker.resolve(req, decision: "deny") }
                    .buttonStyle(.bordered)
                    .tint(Theme.danger)
                Button("Ask in terminal") { broker.resolve(req, decision: "ask") }
                    .buttonStyle(.bordered)
                Spacer(minLength: 8)
                Button("Allow")           { broker.resolve(req, decision: "allow") }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(16)
        .background(shape.fill(Theme.surfaceRaised))
        .background(.thinMaterial, in: shape)
        .glassEffect(.regular.tint(Theme.accent.opacity(0.12)), in: shape)
        .overlay(
            shape.strokeBorder(
                LinearGradient(colors: [Theme.specularTop.opacity(scheme == .dark ? 0.30 : 0.55),
                                        Theme.specularBottom.opacity(scheme == .dark ? 0.05 : 0.06)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 0.75)
        )
        .overlay(shape.strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(scheme == .dark ? 0.55 : 0.18), radius: 22, y: 10)
        .shadow(color: Theme.accent.opacity(0.30), radius: 16, y: 0)
        .padding(6)
    }
}
