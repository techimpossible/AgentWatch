import AppKit
import SwiftUI

/// Manages the borderless NSWindow that hangs under the MacBook camera notch
/// and hosts the SwiftUI NotchView. No-op on non-notched displays.
@MainActor
final class NotchController {
    static private(set) var shared: NotchController?

    private let window: NSWindow
    private weak var statusController: StatusItemController?
    private let uiState = NotchUIState()
    private var observationTask: Task<Void, Never>?
    private var notchCenterX: CGFloat = 0
    private var screenTopY: CGFloat = 0
    private var screenUsableBottomY: CGFloat = 0   // top of the Dock (visibleFrame.minY)

    init?(state: AppState, statusController: StatusItemController) {
        guard let screen = NSScreen.notchedScreen() else {
            DebugLog.write("notch: no notched screen detected; skipping notch UI")
            return nil
        }

        // Use the menu-bar auxiliary regions (left + right of the camera housing) to
        // compute the *actual* horizontal centre of the notch. On some hardware the
        // notch is slightly offset from screen.frame.midX. Fall back to the screen's
        // mid-X if the auxiliary properties are unavailable.
        let notchCenterX: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchCenterX = (left.maxX + right.minX) / 2
            DebugLog.write("notch: aux left.maxX=\(left.maxX) right.minX=\(right.minX) center=\(notchCenterX)")
        } else {
            notchCenterX = screen.frame.midX
            DebugLog.write("notch: aux regions nil; falling back to screen.frame.midX=\(notchCenterX)")
        }

        // Initial frame matches the collapsed shape exactly. The window is
        // resized to match the current stage whenever the user hovers/clicks.
        let initialSize = NotchUIState.Stage.collapsed
        let initialW: CGFloat = initialSize == .collapsed ? NotchUIState.collapsedWidth : NotchUIState.expandedWidth
        let initialH: CGFloat = initialSize == .collapsed ? NotchUIState.collapsedHeight : NotchUIState.activeHeight
        let x = notchCenterX - initialW / 2
        let y = screen.frame.maxY - initialH
        let frame = NSRect(x: x, y: y, width: initialW, height: initialH)
        DebugLog.write("notch: initial window frame x=\(x) y=\(y) w=\(initialW) h=\(initialH)")

        let w = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        w.level = .statusBar
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = false
        w.isMovable = false
        w.isReleasedWhenClosed = false
        // acceptsFirstMouse so clicks (approval buttons, tap-to-expand) reach the
        // SwiftUI content even though this borderless overlay never becomes key —
        // otherwise macOS swallows the mouse-down just to (fail to) activate it.
        w.contentView = FirstMouseHostingView(
            rootView: NotchView()
                .environment(state)
                .environment(uiState)
                .environment(\.colorScheme, .dark)
        )
        w.orderFrontRegardless()
        DebugLog.write("notch: actual window frame after setup: \(NSStringFromRect(w.frame))")

        self.notchCenterX = notchCenterX
        self.screenTopY = screen.frame.maxY
        self.screenUsableBottomY = screen.visibleFrame.minY

        self.window = w
        self.statusController = statusController
        NotchController.shared = self
        DebugLog.write("notch: showing on screen frame \(NSStringFromRect(screen.frame))")
        startStageObservation()
    }

    /// Polling-based observer: every 50ms, check if the SwiftUI side has flipped
    /// the stage and resize the window to match the new visible shape exactly.
    /// Cheap, simple, and avoids @Observable change-callback concurrency issues.
    private func startStageObservation() {
        observationTask?.cancel()
        observationTask = Task { @MainActor [weak self] in
            var lastSize: CGSize = .zero
            while !Task.isCancelled {
                guard let self else { return }
                let size = self.uiState.currentSize
                if size != lastSize {
                    self.resizeWindow(to: size)
                    lastSize = size
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func resizeWindow(to size: CGSize) {
        // Never let the panel run past the usable bottom of the screen; the
        // SwiftUI ScrollView inside handles any overflow beyond this.
        let maxHeight = screenTopY - screenUsableBottomY - 8
        let h = min(size.height, maxHeight)
        let x = notchCenterX - size.width / 2
        let y = screenTopY - h
        let frame = NSRect(x: x, y: y, width: size.width, height: h)
        // animate:true gives a smooth NSWindow resize that roughly matches
        // SwiftUI's spring on the inner content.
        window.setFrame(frame, display: true, animate: true)
    }

}

/// Hosting view that accepts the first click while the notch window is not key,
/// so approval buttons (and tap-to-expand) fire without the overlay stealing focus.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Notch detection

extension NSScreen {
    /// True if this screen has a physical notch (MacBook Pro 2021+ on the built-in display).
    var hasNotch: Bool {
        // safeAreaInsets.top > 0 only on notched built-in displays.
        safeAreaInsets.top > 0
    }

    /// Pick the notched screen, preferring the main if it has one. Returns nil if
    /// no connected display has a notch.
    static func notchedScreen() -> NSScreen? {
        if let main = NSScreen.main, main.hasNotch { return main }
        return NSScreen.screens.first { $0.hasNotch }
    }
}
