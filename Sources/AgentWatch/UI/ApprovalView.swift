import SwiftUI

/// The approval card: what tool the agent wants to run, for which session, with
/// Allow / Deny / Ask-in-terminal. Reads the broker's current request reactively.
struct ApprovalView: View {
    var broker: ApprovalBroker

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
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(Theme.dpGold)
                Text("PERMISSION")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Theme.dpChrome.opacity(0.85))
                Spacer()
                if let prof {
                    Text(prof.uppercased())
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.6))
                            .overlay(Capsule().strokeBorder(Theme.profileColor(prof).opacity(0.8), lineWidth: 1)))
                }
                if broker.pending.count > 1 {
                    Text("+\(broker.pending.count - 1)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.dpChrome.opacity(0.6))
                }
            }

            Text(req.headline)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)

            ScrollView(.vertical) {
                Text(req.detail.isEmpty ? "(no details)" : req.detail)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.dpChrome.opacity(0.9))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))

            HStack(spacing: 8) {
                Button("Deny")            { broker.resolve(req, decision: "deny") }
                    .tint(.red)
                Button("Ask in terminal") { broker.resolve(req, decision: "ask") }
                Spacer()
                Button("Allow")           { broker.resolve(req, decision: "allow") }
                    .tint(Theme.neonCyan)
                    .keyboardShortcut(.defaultAction)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.glowOrange.opacity(0.7), lineWidth: 1.5))
                .shadow(color: Theme.glowOrange.opacity(0.35), radius: 16)
        )
        .padding(6)
    }
}
