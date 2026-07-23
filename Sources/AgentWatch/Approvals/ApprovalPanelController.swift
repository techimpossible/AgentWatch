import AppKit
import SwiftUI

/// Shows a floating approval card (top-center, below the menu bar) whenever the
/// broker has a pending request, and hides it when the queue drains. The card
/// must receive clicks, so unlike the mascot overlay it is a key-able panel.
@MainActor
final class ApprovalPanelController {
    static private(set) var shared: ApprovalPanelController?

    private let broker = ApprovalBroker.shared
    private var panel: NSPanel?

    init() {
        ApprovalPanelController.shared = self
        broker.onChange = { [weak self] in self?.update() }
        broker.start()
        DebugLog.write("approvals: panel controller ready")
    }

    private func update() {
        if broker.current != nil {
            let p = panel ?? makePanel()
            panel = p
            if !p.isVisible {
                positionTopCenter(p)
                p.orderFrontRegardless()
                p.makeKey()
            }
        } else {
            panel?.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let p = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 340),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        p.contentView = NSHostingView(
            rootView: ApprovalView(broker: broker).environment(\.colorScheme, .dark))
        return p
    }

    private func positionTopCenter(_ p: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let size = p.frame.size
        p.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2,
                                 y: vf.maxY - size.height - 12))
    }
}

/// Borderless panels aren't key by default; the card has buttons, so allow it.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
