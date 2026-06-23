import SwiftUI

enum SessionStatus: String, Sendable {
    case working
    case idle
    case needsInput
    case unknown

    var label: String {
        switch self {
        case .working: "Working"
        case .idle: "Idle"
        case .needsInput: "Needs input"
        case .unknown: "Unknown"
        }
    }

    var symbol: String {
        switch self {
        case .working: "circle.fill"
        case .idle: "circle"
        case .needsInput: "exclamationmark.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var color: Color { Theme.statusColor(self) }
}
