import SwiftUI

/// Compact star toggle for marking a session as favourite.
/// Outline = not starred, filled amber = starred. Click to toggle.
struct StarButton: View {
    let sessionId: String
    @State private var favorites = FavoritesStore.shared

    private var isStarred: Bool { favorites.contains(sessionId) }

    /// Warm amber for the "favourite" state — a quiet editorial gold that reads as
    /// personal emphasis without borrowing coral (reserved for "your turn").
    private static let starTint = Color.adaptive(0xC68A3E, 0xD69B4E)

    var body: some View {
        Button {
            favorites.toggle(sessionId)
        } label: {
            Image(systemName: isStarred ? "star.fill" : "star")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(isStarred ? Self.starTint : Theme.textTertiary.opacity(0.6))
                .contentTransition(.symbolEffect(.replace))
                // Match CopyButton's tap target so row-trailing controls align
                // and neither state (star vs star.fill) shifts layout.
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help(isStarred ? "Unstar this session" : "Star this session")
        .accessibilityLabel("Favourite")
        .accessibilityValue(isStarred ? "Starred" : "Not starred")
    }
}
