import Foundation
import Observation

/// Persistent set of starred session IDs. Backed by UserDefaults so it survives
/// across app launches without adding a third-party storage dep. Session IDs
/// are stable UUIDs assigned by Claude Code, so they're safe to use as keys.
@MainActor
@Observable
final class FavoritesStore {
    static let shared = FavoritesStore()

    private(set) var ids: Set<String> = []
    private let defaultsKey = "favoriteSessionIds"

    private init() {
        if let saved = UserDefaults.standard.array(forKey: defaultsKey) as? [String] {
            ids = Set(saved)
        }
    }

    func contains(_ sessionId: String) -> Bool {
        ids.contains(sessionId)
    }

    func toggle(_ sessionId: String) {
        if ids.contains(sessionId) {
            ids.remove(sessionId)
        } else {
            ids.insert(sessionId)
        }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(Array(ids), forKey: defaultsKey)
    }
}
