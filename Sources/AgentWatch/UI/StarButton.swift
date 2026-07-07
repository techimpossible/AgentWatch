import SwiftUI

/// Compact star toggle for marking a session as favourite.
/// Outline = not starred, filled gold = starred. Click to toggle.
struct StarButton: View {
    let sessionId: String
    @State private var favorites = FavoritesStore.shared

    private var isStarred: Bool { favorites.contains(sessionId) }

    var body: some View {
        Button {
            favorites.toggle(sessionId)
        } label: {
            Image(systemName: isStarred ? "star.fill" : "star")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isStarred ? Theme.dpGold : Theme.dpChrome.opacity(0.55))
                .shadow(color: isStarred ? Theme.dpGold.opacity(0.7) : .clear, radius: isStarred ? 3 : 0)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help(isStarred ? "Unstar this session" : "Star this session")
        .accessibilityLabel("Favourite")
        .accessibilityValue(isStarred ? "Starred" : "Not starred")
    }
}
