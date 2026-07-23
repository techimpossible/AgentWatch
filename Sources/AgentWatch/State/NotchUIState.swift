import CoreGraphics
import Foundation
import Observation

/// Shared state between NotchView (SwiftUI) and NotchController (AppKit).
/// The view writes its current stage when hover/click changes; the controller
/// observes and resizes the host NSWindow to match. This keeps the window
/// pixel-perfect to the visible shape so transparent regions stop intercepting
/// clicks meant for apps below.
@MainActor
@Observable
final class NotchUIState {
    enum Stage: Equatable, Sendable {
        case collapsed
        case preview(rows: Int)
        case active
        case approval        // a pending tool-permission request; overrides the rest
    }

    var stage: Stage = .collapsed

    /// Measured height the active panel wants (top clearance + content + bottom
    /// padding). The view writes it; the controller clamps to the screen.
    var activeDesiredHeight: CGFloat = activeHeight

    static let collapsedWidth: CGFloat  = 220
    static let collapsedHeight: CGFloat = 32
    static let expandedWidth: CGFloat   = 440
    static let previewHeightBase: CGFloat = 110
    static let activeHeight: CGFloat    = 510
    static let approvalHeight: CGFloat  = 320   // header + diff + action row, below the camera

    var currentSize: CGSize {
        switch stage {
        case .collapsed:
            return CGSize(width: Self.collapsedWidth, height: Self.collapsedHeight)
        case .preview(let rows):
            let h = min(Self.previewHeightBase + CGFloat(max(0, rows - 1)) * 22, 240)
            return CGSize(width: Self.expandedWidth, height: h)
        case .active:
            return CGSize(width: Self.expandedWidth, height: activeDesiredHeight)
        case .approval:
            return CGSize(width: Self.expandedWidth, height: Self.approvalHeight)
        }
    }
}
